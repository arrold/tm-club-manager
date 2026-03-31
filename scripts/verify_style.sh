#!/usr/bin/env bash
# verify_style.sh - Developer verification script for TM Club Manager
# Checks for common pitfalls and code style consistency.

errors=0

while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    linenum=1
    while IFS= read -r line; do
        if echo "$line" | grep -q '@='; then
            echo "WARNING: $filename:$linenum - Found '@=' syntax. Use '@handle = @object' instead for this compiler."
            errors=$((errors + 1))
        fi

        # Check for invalid null comparisons (== null / != null on handles)
        # In AngelScript these call opEquals on the object and crash if it is actually null.
        # Use 'is null' / '!is null' instead.
        if echo "$line" | grep -qE '(==\s*null|!=\s*null)'; then
            echo "WARNING: $filename:$linenum - Found '== null' or '!= null'. Use 'is null' / '!is null' for handle identity checks."
            errors=$((errors + 1))
        fi
        linenum=$((linenum + 1))
    done < "$file"
done < <(find src -name "*.as" -print0)

if [ "$errors" -eq 0 ]; then
    echo "--- Style Check Passed ---"
else
    echo "--- Style Check Failed with $errors issues ---"
    exit 1
fi
