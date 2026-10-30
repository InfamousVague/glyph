#!/bin/sh
# Whether assets/changelog.json has an entry for a version (lib/changelog; Matt, 2026-10-30: "Add a changelog popup
# modal that shows after every update with iconography"). The What's new card after an update says that version's
# changes, so a release with none would say nothing: tool/cutover-build.sh runs this before it builds anything.
#
#   tool/changelog_check.sh 2.3.88                 # exit 0 where the entry is there, 1 with why where it is not
#   tool/changelog_check.sh 2.3.88 path/to.json    # another file's, for a test
#
# An entry is a release whose "version" is the version exactly: {"version": "2.3.88", "date": ..., "items": [...]}.
set -eu
version="${1:?the version: tool/changelog_check.sh 2.3.88}"
file="${2:-$(dirname "$0")/../assets/changelog.json}"
if [ ! -f "$file" ]; then
  echo "error: no changelog at $file. Every release needs its entry in assets/changelog.json." >&2
  exit 1
fi
# The version's dots taken as dots, quoted as the file quotes it.
quoted=$(printf '%s' "$version" | sed 's/[.]/[.]/g')
if ! grep -Eq "\"version\"[[:space:]]*:[[:space:]]*\"$quoted\"" "$file"; then
  newest=$(grep -Eo "\"version\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$file" | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/')
  echo "error: assets/changelog.json has no entry for $version (its newest is ${newest:-none})." >&2
  echo "  Add one at the top before building: {\"version\": \"$version\", \"date\": \"$(date -u +%Y-%m-%d)\", \"title\": \"...\", \"items\": [{\"icon\": \"sparkles\", \"words\": \"...\", \"kind\": \"new\"}]}" >&2
  exit 1
fi
