#!/bin/sh
# The Lovart page's phone shots (landing/lovart.html; Matt, 2026-10-26: "update the website with more imagery by
# generating some prompts and showing screenshots of the different steps too"): draws them with
# test/site/lovart_site_shots_test.dart into build/feature-shots/lovart-site/, light and dark, then makes the dark ones
# into landing/shots/lovart-<name>.webp at 780 by 1688, quality 86, as tauri/scripts/landing-shots.mjs makes the rest.
#
#   scripts/lovart-site-shots.sh                                   cue, making, menu and settings
#   LOVART_SHOT_IMAGES=~/Pictures/lovart scripts/lovart-site-shots.sh
#                                                                  done and inspiration too, with the pictures Lovart
#                                                                  made: the folder's .png, .jpg and .webp in name
#                                                                  order, the first two for the note's two cues and
#                                                                  the last four for its moodboard (six or more keep
#                                                                  them apart)
set -e
cd "$(dirname "$0")/.."

command -v cwebp >/dev/null || { echo 'cwebp is needed: brew install webp' >&2; exit 1; }

# Last run's pictures go first, so a shot skipped this time is not made from them.
rm -f build/feature-shots/lovart-site/*.png
LOVART_SHOT_IMAGES="${LOVART_SHOT_IMAGES:-}" flutter test test/site/lovart_site_shots_test.dart --update-goldens

for png in build/feature-shots/lovart-site/*-dark.png; do
  name=$(basename "$png" -dark.png)
  cwebp -quiet -q 86 -resize 780 1688 "$png" -o "landing/shots/lovart-$name.webp"
  echo "landing/shots/lovart-$name.webp"
done
