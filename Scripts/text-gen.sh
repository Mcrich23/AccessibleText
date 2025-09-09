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
        DEFAULT_PROMPT="You are a generator of short, UI-ready Swift string alternatives. When given an input Swift string, produce 3–5 progressively shorter, natural-sounding variations suitable for display in a user interface.

Rules:
1. Produce between 3 and 5 variations. If absolutely no valid shorter variation exists, produce fewer than 3 only as a last resort.
2. Order variations from longest (most detailed) to shortest (most concise).
3. Preserve all original Swift string interpolations exactly as they appear (e.g. \(name), \(count)). Keep backslashes and parentheses intact.
4. You may remove interpolations when doing so produces a natural, shorter string (for example dropping a greeting or optional context).
5. You may MERGE adjacent date/time-style interpolations into a single combined interpolation **only** when both clearly represent a date and a time (e.g., \(date) + \(time) → \(datetime)). Do not invent other merged tokens.
6. Do not add any new interpolations except the allowed merged \(datetime) token described above.
7. Keep punctuation and grammar correct. Use shorter synonyms and rephrase to shorten, but keep meaning intact.
8. Do not duplicate variations; ensure each output string is distinct.
9. Output must be exactly a JSON array of strings (e.g. ["...","...", "..."]) and nothing else — no explanation, no comments, no extra keys.
10. If the original text already contains multiple forms (e.g., both date/time and datetime), prefer preserving the original tokens unless merging produces a clearer, shorter UI string.

Example of the desired pattern (for guidance only — DO NOT include this example in your final output; it's shown here to illustrate the style):
Original swift string:
\"Hello \(name)! Your event is on \(date) at \(time)\"
Desired generated array (longest → shortest):
[
  \"Hi \(name)! Your event is on \(date) at \(time)\",
  \"Your event is on \(date) at \(time)\",
  \"Your event is at \(datetime)\",
  \"Hi \(name)! Your event is at \(datetime)\",
  \"Event at \(datetime)\"
]"

        PROMPT="${PROMPT_INSTRUCTIONS:-$DEFAULT_PROMPT}

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

        # Extract LLM content and parse JSON array properly
        variations=()
        content=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)
        
        # Use a more robust approach - extract variations using sed and awk
        # Remove the outer brackets and split by lines that start with quotes
        temp_file=$(mktemp)
        echo "$content" > "$temp_file"
        
        # Extract each quoted string from the array
        while IFS= read -r line; do
            # Look for lines that contain quoted strings
            if echo "$line" | grep -q '^[[:space:]]*"[^"]*"'; then
                # Extract the content between quotes
                variation=$(echo "$line" | sed -E 's/^[[:space:]]*"([^"]*)"[[:space:]]*,?[[:space:]]*$/\1/')
                if [ -n "$variation" ]; then
                    variations+=("$variation")
                fi
            fi
        done < "$temp_file"
        
        rm "$temp_file"

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
