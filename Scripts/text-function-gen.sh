#!/bin/bash

DIR="${1:-.}"
STRUCT_FILE="$DIR/AccessibleTextContainer.swift"

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

    while IFS= read -r match; do
        # Use grep + Perl regex for literal capture (avoids sed escaping issues)
        text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleText\s*\("(.+)"\)/')
        # Hash the exact string
        hash=$(echo -n "$text" | shasum -a 256 | awk '{print $1}')
        current_hashes="$current_hashes $hash"
    done < <(grep -o '#accessibleText *(".*")' "$file")
done < <(find "$DIR" -type f -name "*.swift")

# ----------------------------
# Step 3: Remove stale functions from AccessibleTextContainer.swift
# ----------------------------
tmp_clean=$(mktemp)
inside_func=0
keep_func=1
brace_depth=0

while IFS= read -r line; do
    # Match static var/func with optional access modifier, and ending with `_text` function name
    if [[ "$line" =~ ^[[:space:]]*(private|public|internal|fileprivate)?[[:space:]]+(var|func)[[:space:]]+\`([0-9a-f]{64})_text\` ]]; then
        func_hash="${BASH_REMATCH[3]}"
        if echo "$current_hashes" | grep -q "$func_hash"; then
            keep_func=1
        else
            keep_func=0
        fi
        inside_func=1
        brace_depth=0
    fi

    # Skip lines if we're inside a function to remove
    if [ "$inside_func" -eq 1 ] && [ "$keep_func" -eq 0 ]; then
        # Track braces to find the end of the function
        brace_depth=$((brace_depth + $(grep -o "{" <<< "$line" | wc -l)))
        brace_depth=$((brace_depth - $(grep -o "}" <<< "$line" | wc -l)))

        if [ "$brace_depth" -le 0 ]; then
            inside_func=0
            keep_func=1
        fi
        continue
    fi

    # Keep lines that are not skipped
    echo "$line" >> "$tmp_clean"
done < "$STRUCT_FILE"

mv "$tmp_clean" "$STRUCT_FILE"

# ----------------------------
# Step 4: Append new functions only
# ----------------------------
tmpfile=$(mktemp)
while IFS= read -r file; do
    [ "$file" = "$STRUCT_FILE" ] && continue

    while IFS= read -r match; do
        text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleText\s*\("(.+)"\)/')
        hash=$(printf "%s" "$text" | shasum -a 256 | awk '{print $1}')

        # Skip if a function with this hash already exists
        if grep -q "\`${hash}_text\`" "$STRUCT_FILE"; then
            continue
        fi

        {
            echo "    func \`${hash}_text\`(_ args: any CVarArg...) -> AccessibleText.AccessibleTexts {"
            echo "        AccessibleText.AccessibleTexts(\`$hash\`(args))"
            echo "    }"
            echo
        } >> "$tmpfile"

    done < <(grep -o '#accessibleText *(".*")' "$file")
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
