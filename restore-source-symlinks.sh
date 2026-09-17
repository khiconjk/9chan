#!/usr/bin/env bash
set -euo pipefail

while IFS=$'\t' read -r mode path; do
    target=$(git show "HEAD:${path}")
    rm -f -- "$path"
    ln -s "$target" "$path"
done < <(git ls-tree -r -z HEAD | tr '\0' '\n' | awk '$1 == "120000" { sub(/^[^\t]*\t/, ""); print "120000\t" $0 }')

echo "Restored source symlinks"
