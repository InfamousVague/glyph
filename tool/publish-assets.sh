#!/usr/bin/env bash
# The publisher (tauri/publish/) built and copied into the app's assets, so the Back up to git plugin can vendor it into a
# library's repository as .glyph/publish/ when "Publish as a website" is on (lib/plugins/git_backup/publish.dart). Run
# before a release build; assets/publish/ is ignored by git (the bundle is 2 MB and built, not written).
#
#   tool/publish-assets.sh            builds tauri/publish/dist with vite (npm install in tauri/ first if needed), then copies
#
# What lands, flat (one asset folder, always there with its README.txt): assets/publish/ghost-publish.mjs,
# assets/publish/ghost-publish.js, assets/publish/github-pages.yml and assets/publish/VERSION (the package's version and the bundle's hash, which is what the plugin compares before it
# rewrites a repository's copy).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tauri="$root/tauri"
out="$root/assets/publish"

if [ ! -x "$tauri/node_modules/.bin/vite" ]; then
  echo "publish-assets: installing tauri/ dependencies (vite is wanted)"
  (cd "$tauri" && npm install --no-audit --no-fund)
fi
(cd "$tauri" && npm run build:publish)

mkdir -p "$out"
cp "$tauri/publish/bin/ghost-publish.mjs" "$out/ghost-publish.mjs"
cp "$tauri/publish/dist/ghost-publish.js" "$out/ghost-publish.js"
cp "$tauri/publish/templates/github-pages.yml" "$out/github-pages.yml"
version="$(node -p "require('$tauri/publish/package.json').version")"
hash="$(shasum -a 256 "$out/ghost-publish.js" | cut -c1-12)"
echo "$version+$hash" > "$out/VERSION"
echo "publish-assets: $out ($(du -sh "$out/ghost-publish.js" | cut -f1) bundle, version $version+$hash)"
