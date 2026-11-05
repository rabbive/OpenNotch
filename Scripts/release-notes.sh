#!/bin/sh
# Prints the CHANGELOG.md section for a version, without its heading. Fails if the section is missing or empty.
# Usage: Scripts/release-notes.sh <version>
#        Scripts/release-notes.sh --newest   prints the newest version with a section, or nothing
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" = --newest ]; then
    awk '/^## / { v = substr($0, 4); sub(/ - .*/, "", v); if (v != "Unreleased") { print v; exit } }' CHANGELOG.md
    exit 0
fi

version=${1:?usage: Scripts/release-notes.sh <version>}

notes=$(awk -v v="$version" '
    /^## / {
        if (found) exit
        heading = substr($0, 4)
        sub(/ - .*/, "", heading)
        if (heading == v) { found = 1; next }
    }
    found { print }
' CHANGELOG.md)

# Drop leading and trailing blank lines.
notes=$(printf '%s\n' "$notes" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')
[ -n "$notes" ] || { echo "release-notes: CHANGELOG.md has no notes under '## $version'" >&2; exit 1; }
printf '%s\n' "$notes"
