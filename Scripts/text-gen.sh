#!/bin/bash

DIR="${1:-.}"
STRUCT_FILE="$DIR/AccessibleTextContainer.swift"
LM_API_URL="http://localhost:1234/v1/chat/completions"
# Default model, can be overridden by LM_STUDIO_MODEL environment variable
MODEL="${LM_STUDIO_MODEL:-qwen/qwen3-4b-2507}"
LMS_EXECUTABLE_PATH=${LMS_EXECUTABLE_PATH:-~/.lmstudio/bin/lms}

# ----------------------------
# Helper: Start LMS server if not running
# ----------------------------
server_started_by_script=0
model_loaded_by_script=0
        
start_lms_server() {
    # Check LMS server status
    if ! lsof -i :1234 >/dev/null 2>&1; then
        echo "LMS server not running. Starting..."
        $LMS_EXECUTABLE_PATH server start >/dev/null 2>&1 &
        # Wait until API responds
        until curl -s "$LM_API_URL" >/dev/null 2>&1; do
            sleep 1
        done
        echo "LMS server is up."
        return 0  # Indicate we started it
    fi
    return 1  # Indicate it was already running
}

ensure_model_loaded() {
    # Check if the model exists locally
    if ! $LMS_EXECUTABLE_PATH ls 2>/dev/null | grep -q "^$MODEL"; then
        echo "Model $MODEL not found locally. Downloading..."
        $LMS_EXECUTABLE_PATH get "$MODEL" -y
        echo "Model $MODEL downloaded."
    fi

    # Check if the model is already loaded in the server
    if $LMS_EXECUTABLE_PATH ps 2>/dev/null | grep -q "$MODEL"; then
        return 1  # Indicate it was already loaded
    else
        echo "Loading model $MODEL..."
        $LMS_EXECUTABLE_PATH load "$MODEL" >/dev/null 2>&1
        echo "Model $MODEL loaded."
        return 0
    fi
}

# ----------------------------
# Step 1: Ensure the struct file exists
# ----------------------------
if [ ! -f "$STRUCT_FILE" ]; then
    echo "Creating $STRUCT_FILE..."
    cat > "$STRUCT_FILE" <<EOL
import Foundation
import AccessibleText
import SwiftUI

struct AccessibleTextContainer {
}
EOL
fi

# ----------------------------
# Step 2: Compute all current hashes in the codebase
# ----------------------------
current_hashes=""
while IFS= read -r file; do
    [ "$file" = "$STRUCT_FILE" ] && continue

    # Read the file line by line
    while IFS= read -r line; do
        text=""

        # Extract #accessibleText("...")
        text=$(echo "$line" | perl -ne 'print "$1\n" if /#accessibleText\s*\("(.+?)"\)/')

        # If nothing, try #accessibleNavigationTitle("...", content:
        if [ -z "$text" ]; then
            text=$(echo "$line" | perl -ne 'print "$1\n" if /#accessibleNavigationTitle\s*\("(.+?)"\s*,\s*content:/')
        fi

        # Skip empty matches
        [ -z "$text" ] && continue

        # Hash the exact string
        hash=$(echo -n "$text" | shasum -a 256 | awk '{print $1}')
        current_hashes="$current_hashes $hash"

    done < "$file"
done < <(find "$DIR" -type f -name "*.swift")

# ----------------------------
# Step 3: Remove stale functions from AccessibleTextContainer.swift
# ----------------------------
tmp_clean=$(mktemp)
inside_func=0
keep_func=1
brace_depth=0

while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*(private|public|internal|fileprivate)?[[:space:]]+(var|func)[[:space:]]+\`([0-9a-f]{64})\` ]]; then
        func_hash="${BASH_REMATCH[3]}"
        if echo "$current_hashes" | grep -q "$func_hash"; then
            keep_func=1
        else
            keep_func=0
        fi
        inside_func=1
        brace_depth=0
    fi

    if [ "$inside_func" -eq 1 ] && [ "$keep_func" -eq 0 ]; then
        # Track opening and closing braces
        brace_depth=$((brace_depth + $(grep -o "{" <<< "$line" | wc -l)))
        brace_depth=$((brace_depth - $(grep -o "}" <<< "$line" | wc -l)))

        if [ "$brace_depth" -le 0 ]; then
            inside_func=0
            keep_func=1
        fi
        continue
    fi

    echo "$line" >> "$tmp_clean"
done < "$STRUCT_FILE"

mv "$tmp_clean" "$STRUCT_FILE"

# ----------------------------
# Step 4: Append new functions only
# ----------------------------
tmpfile=$(mktemp)
seen_hashes=""

while IFS= read -r file; do
    [ "$file" = "$STRUCT_FILE" ] && continue

    # Read lines containing either #accessibleText or #accessibleNavigationTitle
    while IFS= read -r match; do
        text=""

        if [[ "$match" == *"#accessibleText("* ]]; then
            # Extract quoted string from #accessibleText("...")
            text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleText\s*\("(.+?)"\)/')
        elif [[ "$match" == *"#accessibleNavigationTitle("* ]]; then
            # Extract quoted string from #accessibleNavigationTitle("...", content:
            text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleNavigationTitle\s*\("(.+?)"\s*,\s*content:/')
        fi
        [ -z "$text" ] && continue  # skip if nothing found

        hash=$(printf "%s" "$text" | shasum -a 256 | awk '{print $1}')
        
        # Skip if already processed in this run or already exists in struct
        if echo "$seen_hashes" | grep -q "$hash" || grep -q "func \`$hash\`(" "$STRUCT_FILE"; then
            continue
        fi
        seen_hashes="$seen_hashes $hash"
        
        if start_lms_server; then
            server_started_by_script=1
        fi

        # Ensure model is loaded after starting server
        if ensure_model_loaded; then
            model_loaded_by_script=1
        fi

        variations=()

        # Generate LM variations preserving Swift string interpolations
        PROMPT="You are generating alternative text variations for UI display. Follow these rules:

1. Generate between 3 and 5 **progressively** shorter variations of the input text.
2. Preserve all Swift string interpolations (e.g., \\(name), \\(count)) exactly as they appear in the original string.
3. You may remove interpolations if it makes sense in the shorter variation.
4. Do not add new interpolations.
5. Variations must be natural to read and suitable for a real user interface.
6. Respond only as a JSON array of strings.
7. If absolutely no valid shorter variation exists, you may generate fewer than 3, but otherwise produce at least 3.
8. Do not duplicate variations.

Original text: $text"
        payload=$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{
            model: $model,
            messages: [
                { role: "system", content: "You are a helpful assistant." },
                { role: "user", content: $prompt }
            ],
            temperature: 0.7,
            max_tokens: 200,
            stream: false
        }')
        response=$(curl -s "$LM_API_URL" -H "Content-Type: application/json" -d "$payload")

        # Extract LLM content as a raw string
        raw_variations=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)

        # Remove leading/trailing brackets
        raw_variations=${raw_variations#\[}
        raw_variations=${raw_variations%\]}

        # Split by comma into array
        IFS=',' read -r -a variations <<< "$raw_variations"

        # Trim quotes and whitespace from each LLM-generated element
        for i in "${!variations[@]}"; do
            variations[$i]=$(echo "${variations[$i]}" | sed -E 's/^ *"(.*)" *$/\1/')
        done

        # --- Deduplicate and exclude the original ---
        placeholder_text=$(echo "$text" | sed -E 's/\\\([^)]*\)/%@/g')

        unique_variations=()
        for v in "${variations[@]}"; do
            var_placeholder=$(echo "$v" | sed -E 's/\\\([^)]*\)/%@/g')
            skip=0
            if [ "$var_placeholder" = "$placeholder_text" ]; then
                skip=1
            else
                for u in "${unique_variations[@]}"; do
                    if [ "$var_placeholder" = "$u" ]; then
                        skip=1
                        break
                    fi
                done
            fi
            if [ $skip -eq 0 ] && [ -n "$var_placeholder" ]; then
                unique_variations+=("$var_placeholder")
            fi
        done
        variations=("${unique_variations[@]}")

        # Replace all \(...) with %@ placeholders
        placeholder_text=$(echo "$text" | sed -E 's/\\\([^)]*\)/%@/g')

        {
            echo "    private func \`$hash\`(_ args: any CVarArg...) -> [Text] {"
            echo "        ["
            echo "            Text(String(format: \"$(echo "$text" | sed -E 's/\\\([^)]*\)/%@/g' | sed 's/"/\\"/g')\", arguments: args)),"
            for var in "${variations[@]}"; do
                var_placeholder=$(echo "$var" | sed -E 's/\\\([^)]*\)/%@/g')
                echo "            Text(String(format: \"$(echo "$var_placeholder" | sed 's/"/\\"/g')\", arguments: args)),"
            done
            echo "        ]"
            echo "    }"
            echo
        } >> "$tmpfile"

    done < <(grep -E '#accessibleText|#accessibleNavigationTitle' "$file")
done < <(find "$DIR" -type f -name "*.swift")

# ----------------------------
# Step 5: Append new functions safely before last closing brace
# ----------------------------
if [ -s "$tmpfile" ]; then
    sed '$d' "$STRUCT_FILE" > "${STRUCT_FILE}.tmp"
    cat "$tmpfile" >> "${STRUCT_FILE}.tmp"
    tail -n 1 "$STRUCT_FILE" >> "${STRUCT_FILE}.tmp"
    mv "${STRUCT_FILE}.tmp" "$STRUCT_FILE"
    echo "New functions appended to $STRUCT_FILE"
fi

rm "$tmpfile"

# ----------------------------
# Step 6: Normalize line breaks inside the struct properly
# ----------------------------
awk '
/struct AccessibleTextContainer *{/ {inside=1; print; first_func=1; next}
/^}/ {inside=0; print; next}
inside==1 {
    if (NF) {
        if (match($0, /^ *func /)) {
            if (!first_func) print ""   # blank line before each function except first
            first_func=0
        }
        print
        prev_blank=0
    }
    next
}
{print}
' "$STRUCT_FILE" > "${STRUCT_FILE}.tmp" && mv "${STRUCT_FILE}.tmp" "$STRUCT_FILE"

# ----------------------------
# Step 7: Unload model if script loaded it
# ----------------------------
if [ "$model_loaded_by_script" -eq 1 ]; then
    echo "Unloading model $MODEL loaded by this script..."
    $LMS_EXECUTABLE_PATH unload "$MODEL" >/dev/null 2>&1
fi

# ----------------------------
# Step 8: Stop LMS server if we started it
# ----------------------------
if [ "$server_started_by_script" -eq 1 ]; then
    echo "Stopping LMS server started by this script..."
    $LMS_EXECUTABLE_PATH server stop >/dev/null 2>&1
fi

# ----------------------------
# Step 9: Generate text and navigationTitle functions
# ----------------------------
SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SH_DIR/navigationTitle-function-gen.sh" "$DIR"
bash "$SH_DIR/text-function-gen.sh" "$DIR"
