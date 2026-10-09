#!/bin/sh
# The Mac's half of the iPhone app's tour (lib/shell/phone_tour.dart): leaves a script in the app's own cache
# folder, starts a DEBUG build of the app in a simulator, takes the pictures the script asks for, and prints the
# app's log.
# Nothing is clicked or typed on the Mac's screen: the app walks itself, and the simulator is asked for a picture
# by its own tool.
#
#   tool/ios-tour.sh <udid> <folder for the pictures> '<script>' [seconds to wait, 240]
#
#   tool/ios-tour.sh "$UDID" /tmp/shots 'wait:6000;shot:home;host:appearance light;wait:600;shot:home-light'
#
# The simulator must be booted and the app installed (flutter build ios --simulator --debug --no-pub, then
# xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app). The app is stopped first if it is running,
# and left running at the end.
#
# What the script may ask of this half, through `ask.txt` beside it (`<container>/Library/Caches/<id>/tour/`):
# `shot <name>` (a PNG of the whole screen), `appearance dark|light` (the simulator's own setting), and `end`.
set -eu

udid="${1:?the udid of the simulator}"
out="${2:?a folder for the pictures}"
script="${3:?the script}"
limit="${4:-240}"
id="com.mattssoftware.glyph.flutter"

mkdir -p "$out"
data="$(xcrun simctl get_app_container "$udid" "$id" data)"
tour="$data/Library/Caches/$id/tour"
xcrun simctl terminate "$udid" "$id" >/dev/null 2>&1 || true
rm -rf "$tour"
mkdir -p "$tour"
printf '%s' "$script" > "$tour/script.txt"
xcrun simctl launch "$udid" "$id" >/dev/null

began="$(date +%s)"
while :; do
  if [ -f "$tour/ask.txt" ]; then
    read -r verb word < "$tour/ask.txt" || true
    case "$verb" in
      shot) xcrun simctl io "$udid" screenshot "$out/$word.png" >/dev/null 2>&1 || echo "ios-tour: no picture for $word" >&2 ;;
      appearance) xcrun simctl ui "$udid" appearance "$word" ;;
      end) rm -f "$tour/ask.txt"; break ;;
      *) echo "ios-tour: asked for '$verb', which this does not do" >&2 ;;
    esac
    rm -f "$tour/ask.txt"
  fi
  if [ $(( $(date +%s) - began )) -ge "$limit" ]; then
    echo "ios-tour: stopped waiting after $limit seconds" >&2
    break
  fi
  sleep 0.15
done
[ ! -f "$tour/log.txt" ] || cat "$tour/log.txt"
