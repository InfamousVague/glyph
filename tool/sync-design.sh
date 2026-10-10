#!/bin/sh
# The stylesheets the token engine reads, copied from the web app beside this folder: run after ink.css, app.css,
# typefaces.css or the vendored @glacier/tokens change there, and the token sheet the app is built with worked out
# from them again. The kit's test (packages/glacier/test/tokens_test.dart) then says whether the page and this
# still agree.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
web="${1:-$here/../glyph}"
cp "$web/vendor/@glacier/tokens/css/tokens.css" "$here/packages/glacier/assets/css/tokens.css"
cp "$web/src/app/ink.css" "$web/src/app/app.css" "$web/src/app/typefaces.css" "$here/assets/css/"
# The app reads no CSS as it starts: the sheet is worked out here, as the app is built (lib/app/token_sheet.g.dart),
# and its test says so when this was not run.
(cd "$here" && dart run tool/token_sheet.dart)
echo "synced from $web"
