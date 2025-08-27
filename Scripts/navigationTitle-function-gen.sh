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
        # Use grep + Perl regex to capture the first quoted string before ", content:"
        text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleNavigationTitle\s*\("(.+?)"\s*,\s*content:/')
        # Hash the exact string
        hash=$(echo -n "$text" | shasum -a 256 | awk '{print $1}')
        current_hashes="$current_hashes $hash"
    done < <(grep '#accessibleNavigationTitle(' "$file")
done < <(find "$DIR" -type f -name "*.swift")

# ----------------------------
# Step 3: Remove stale functions from AccessibleTextContainer.swift
# ----------------------------
tmp_clean=$(mktemp)
inside_func=0
keep_func=1

while IFS= read -r line; do
    # Match ONLY navigationTitle functions: `hash_navigationTitle`
    if [[ "$line" =~ ^[[:space:]]*static\ (var|func)\ \`([0-9a-f]{64})_navigationTitle\` ]]; then
        func_hash="${BASH_REMATCH[2]}"   # just the 64-char hash part
        if echo "$current_hashes" | grep -q "$func_hash"; then
            keep_func=1
        else
            keep_func=0
        fi
        inside_func=1
    fi

    if [ "$inside_func" -eq 1 ] && [ "$keep_func" -eq 0 ]; then
        if [[ "$line" =~ ^[[:space:]]*\}$ ]]; then
            inside_func=0
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
while IFS= read -r file; do
    [ "$file" = "$STRUCT_FILE" ] && continue

    while IFS= read -r match; do
        # Extract just the first string inside #accessibleNavigationTitle("...", content:
        text=$(echo "$match" | perl -ne 'print "$1" if /#accessibleNavigationTitle\s*\("(.+?)"\s*,\s*content:/')
        hash=$(printf "%s" "$text" | shasum -a 256 | awk '{print $1}')

        # Skip if it already exists
        if grep -q "${hash}_navigationTitle" "$STRUCT_FILE"; then
            continue
        fi

        {
            echo "    static func \`${hash}_navigationTitle\`<Content: View>(_ args: any CVarArg..., @ViewBuilder content: () -> Content) -> AccessibleText.AccessibleNavigationTitles<Content> {"
            echo "        AccessibleText.AccessibleNavigationTitles(\`$hash\`(args), content: content)"
            echo "    }"
            echo
        } >> "$tmpfile"

    done < <(grep '#accessibleNavigationTitle(' "$file")
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
        if (match($0, /^ *static func /)) {
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
