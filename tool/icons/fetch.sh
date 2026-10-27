#!/bin/sh
# Fetches the icon packs' own SVGs, at the versions tool/icons/map.json pins, into a folder OUTSIDE the repository:
# only the paths tool/icons/generate.dart makes of them (lib/art/packs/*.g.dart) and the packs' licences
# (tool/icons/licences/) are kept in it.
#
#   tool/icons/fetch.sh "$TMPDIR/ghost-icon-packs"
#   dart run tool/icons/generate.dart "$TMPDIR/ghost-icon-packs"
#
# Each pack is unpacked in a folder of its own, by the id map.json gives it: <dir>/phosphor/package/assets/...
set -eu
dir="${1:?the folder to fetch into, outside the repository}"
mkdir -p "$dir"
fetch() {
  mkdir -p "$dir/$1"
  (cd "$dir/$1" && rm -rf package && npm pack "$2" --silent >/dev/null && tar xzf ./*.tgz && rm -f ./*.tgz)
}
fetch phosphor @phosphor-icons/core@2.1.1
fetch tabler @tabler/icons@3.49.0
fetch material-400 @material-symbols/svg-400@0.48.0
fetch material-700 @material-symbols/svg-700@0.48.0
fetch remix remixicon@4.9.1
echo "fetched into $dir"
