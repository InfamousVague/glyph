#!/bin/sh
# The stylesheets the token engine reads, copied from the web app beside this folder: run after ink.css, app.css,
# typefaces.css or the vendored @glacier/tokens change there. The kit's test (packages/glacier/test/tokens_test.dart)
# then says whether the page and this still agree.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
web="${1:-$here/../glyph}"
cp "$web/vendor/@glacier/tokens/css/tokens.css" "$here/packages/glacier/assets/css/tokens.css"
cp "$web/src/app/ink.css" "$web/src/app/app.css" "$web/src/app/typefaces.css" "$here/assets/css/"
echo "synced from $web"
