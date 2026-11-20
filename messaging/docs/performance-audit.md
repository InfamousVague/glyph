# Performance audit (2026-11-20)

Matt, 2026-11-20: "Please audit the whole app and search for ways we can improve performance it's quite laggy on
linux". Every finding is fixed or answered, said under each. None of it has been measured on Linux yet. Read at 0.10.4 (`49d0e0a21`).

**How it was done, and what it is not.** The code was read for what makes frames slow or keeps them coming (three
sweeps: idle animations and timers; rebuild scope and lists; blocking work on the UI thread), and the top findings
were checked in the code. Two were measured with throwaway tests on a Mac. **Nothing was measured on Linux**: there
was no Linux machine to run on, so the order below is by reasoning, not by a profile. None of the findings is
Linux-only; Linux (often a weaker GPU path, sometimes software rendering) shows them first.

**First, on the Linux machine itself:** `glxinfo | grep "OpenGL renderer"`. If it says `llvmpipe`, the app is drawn
by the CPU (no GPU driver, or a VM), and everything below is a multiplier on that. The Linux runner is Flutter's
stock one (`linux/runner/my_application.cc`); the build is `flutter build linux --release` with no special flags.

## Ranked findings

### 1. Every settings write rebuilds and re-themes the whole app (proven)

**Fixed 2026-11-20** (Matt: "Yes, fix both"; `test/perf_rebuilds_test.dart`, which fails without the fixes): the
typography object is the same for the same emoji set (`ghostTypography`, `lib/main.dart`), so a choice written no
longer makes new tokens; `AppState.set` to the same value does nothing; `AppState.keep` keeps a store's bookkeeping
without telling the screens (`voice_seen`, `voice_read`, `hangout_*_m`, `circles_seen`); the computer's choices file
is written at most once in 200 ms, the newest of a burst, and the folder is closed (`chmod 700`) once a run in place
of a `chmod` started for every write (`lib/desktop/store.dart`). Still as it was: `AppScope` tells every
`AppState.of` dependent on each real change, and the other stores' keys still go through `set`.

- `AppState.set` (`lib/app_state.dart:38`) always notifies, also when the value did not change.
- The app's root listens (`lib/desktop/main.dart:320`, `lib/main.dart:195`) and rebuilds `WidgetsApp`, passing
  `typography: ghostTypography(state.emoji)`: a new object each time, with no `==`.
- `GlacierTheme` keys its tokens on that object (`packages/glacier/lib/src/tokens/theme.dart:76`), so it makes new
  root `Tokens`: every widget that reads `context.tokens` (nearly all) rebuilds, every token cache is dropped, and
  every `GlacierScope` (one per avatar) scans the sheet's 134 rules again.
- `AppScope` also tells all ~100 `AppState.of` dependents every time (`version: Object()`, `app_state.dart:122`).
- Each write also encodes the whole prefs file (111 KB on Matt's Mac), writes it with a flush, and **starts a
  `/bin/chmod` process** (`lib/desktop/store.dart:39-48`).

Measured (throwaway test): after `state.set('voice_seen', …)` the theme is a different object and its dependents
rebuild. A new root with ~15 lookups is ~1 ms and an avatar's scope ~0.13 ms (debug VM): the theme itself is cheap;
the cost is the whole tree rebuilding, laying out and painting.

What writes there while the app is just open: `voice_seen` on **every** presence "looks" event from the hub
(`lib/voice/channels.dart:228`, from `:436`), `hangout_*_m` per space message (`:974`), summaries, circles' seen
marks, kept lists, emoji recents; the text-size slider on every tick.

Fixes, small: memoise `ghostTypography` (or give `GlacierTypography` equality); `set` returns early when unchanged;
bookkeeping keys (seen/read marks) do not notify, or live outside `AppState`; debounce the prefs write; set the file's
mode once instead of spawning `chmod`.

### 2. The conversation list rebuilds whole on any network, voice or summary change, with O(N) work each time

**Fixed 2026-11-20** (Matt: "fix all the performance issues found above"; `test/perf_lists_test.dart`): a network's
shown and archived chats are made once for each change and each state of Ghost's own lists (`InboxNetwork.stamp`,
`shownChats`), and one of those lists is read from its kept form once (`localList`); Telegram marks its lists stale on
an update and makes them when next read, once, and TDLib's JSON is read in its own isolate; a chat's scam signs are
remembered; a tab's conversations are worked out once a build. Still as it was: the list is one `State` that builds
whole on any of its notifiers (a build is now cheap, but it is still a build), and Voice tells it of every change in
a call.

- `ConversationsScreen` calls `setState` on `Summaries`, `Voice`, `Circles` and every network
  (`lib/ui/conversations.dart:170-188`); the build then filters, sorts and re-parses pref strings per chat
  (`_shown`, `_of` twice, `_mixed`, `shownChats`/`localList` in `lib/inbox/inbox.dart:482,598`), runs scam regexes
  per snippet (`lib/inbox/scams.dart:106`), and each network's `chats` getter rebuilds every `InboxChat`.
- Telegram re-sorts all chats and notifies on almost every TDLib update, uncoalesced
  (`lib/inbox/telegram.dart:688`): thousands at sign-in and start. TDLib's JSON is decoded on the UI thread
  (`lib/inbox/td_json.dart:104`).

Fixes: coalesce each network's notify to one a frame; cache `chats` and the parsed lists by a change stamp; memoise
the per-chat facts; decode TDLib's JSON in its own isolate.

### 3. A conversation builds every message it holds, with regexes made per message

**Fixed 2026-11-20** (`test/jump_to_latest_test.dart`): the list is a builder, a message one keyed row made as it
nears the screen, so what the plugins find in a message's words is found for the rows on screen alone. The patterns
were left where they are: Dart keeps the patterns it has compiled, so making one again by its source is a lookup.
The Dial-Up look's transcript (`_lines`) is still built whole.

- `lib/ui/thread.dart:1091`: `ListView(reverse: true, children: items)`, not a builder: 120 messages at first, 300
  more a page, all built on every rebuild.
- Per message per rebuild: plugin fills construct ~14 `RegExp`s (`lib/plugins/actions.dart:48-130`), find links
  (`embeds.dart:246`), and more (`conversation.dart:105`).
- Rebuilt on any `AppState` change (so on finding 1), groups, sends, loads.

Fixes: `ListView.builder` over prepared rows; cache a message's fills by its key; make the regexes top-level finals.

### 4. Signal, WhatsApp and Matrix write their whole store on the UI thread after every event

**Fixed 2026-11-20** (`test/kept_writer_test.dart`): `lib/inbox/kept_writer.dart` hands what is kept to another
isolate, which makes the JSON and writes the file, a run of changes as one write (two seconds after the last, ten at
most after the first); the three stores, Telegram's kept edits and a files space's log go through it. WhatsApp knows
a message it has by an index of ids and sorts a chat only when a message comes out of order; Signal looks from the
end back. Still as it was: history is never trimmed (Signal's exists nowhere else), each store is read whole on the
main thread as the app starts, and a helper's lines are read (JSON) on the main thread one at a time.

- `lib/inbox/signal.dart:880`, `whatsapp.dart:760`, `matrix.dart:776`: `writeAsStringSync(jsonEncode(everything))`
  400 ms after each message, receipt, reaction or name; history is never trimmed, so it grows without end.
- WhatsApp's history sync is quadratic (`whatsapp.dart:366-415`: a linear dedupe and a whole-chat sort per message),
  and the one giant line is decoded on the UI thread. Signal has the same per-message `any` + `sort`.

Fixes: write asynchronously (encode in an isolate), a longer debounce, a file a chat or a cap; an id set and one sort
a batch.

### 5. After the first call, the window is redrawn every frame for ever

**Fixed 2026-11-20** (`test/perf_rebuilds_test.dart`): the beat and the call's clock run only while there is a call
(`_CallBannerState._sync`), and the dot is painted by itself (`RepaintBoundary`).

`lib/ui/voice_screen.dart:677`: the call banner's pulse (`..repeat(reverse: true)`) starts with the first call shown
and is never stopped; the banner stays mounted in the sidebar with no `RepaintBoundary`. From then on the app
asks for a frame at every refresh, call or no call. During a call it sits over a blur (`:728`), re-blurred each
frame. Fix: run it only while there is a call; a `RepaintBoundary` round it.

### 6. Pictures decoded at full size, and some decoded again on every rebuild

**Fixed 2026-11-20** (`test/picture_decode_test.dart`): `lib/kit/picture_decode.dart` gives the width to unpack a
face or a filling picture at, keeps a base64 picture's bytes so each build hands the image cache the same ones, and
reads a previewed file once. Faces, space and profile faces, circle banners, a network's message photographs, the
chat background and the files preview use it. The full-screen viewer still unpacks the whole picture (it zooms).

- Avatars and message pictures have no `cacheWidth` (`lib/ui/common.dart:764,774`, `lib/ui/inbox_ui.dart:1425`,
  `thread.dart:2113`): a 40 px face decodes the whole photo.
- Space faces `base64Decode` and decode anew each build, one a message row (`lib/ui/hangout_screen.dart:2461`,
  `profile_card.dart:514`, `circles/circle_list.dart:213`); `file_preview.dart:182` reads the file in `build`.

### 7. Signature checks inside builds (spaces and circles)

**Fixed 2026-11-20** (`test/perf_verify_test.dart`): `NetCrypto.verifyOnce` remembers the answer for the same key,
message and signature; a roster's and a circle's grants ask it.

`lib/voice/roles.dart:235` and `lib/circles/circle.dart:362-403` verify P-256 signatures in pure Dart from getters
that rows call while building (`hangout_screen.dart:1815`): several ms each, per message row, per rebuild. Fix:
remember the answer per grant.

### 8. Smaller, real

**Fixed 2026-11-20**: the search (each conversation's words folded once, `conversations.dart`); the resize
(`GlacierTheme.resizeSettle`, 120 ms on a computer; `test/perf_rebuilds_test.dart`); the polls (Bluesky, Mastodon,
Google Chat, Teams and the phone's friends tell their listeners only when the answer differs); the spinner paints by
itself. **Left, on purpose:** every face listening to presence (looked at again: the face itself is not built again,
only a dot, so there is little to win); hover building a row again (inside the kit, and it stays in the row); and
pausing when the window is hidden (Flutter stops drawing a hidden window by itself; what goes on is the networks'
asking, which notifications need).

- Every avatar listens to all presence changes (`common.dart:665`): one status change rebuilds every face.
- Search scans everything on each keystroke (`conversations.dart:530`): debounce, pre-fold once.
- Resizing the window makes a new theme every frame (`theme.dart:75` keys on the window's size): resize stutter.
- Polls that notify with nothing new: Bluesky, Mastodon, Google Chat, Teams every 20-30 s; buddies every 20 s on a
  paired computer (`friends/buddies.dart:240`). Each is a full list rebuild (finding 2).
- The desktop app never pauses when the window is hidden or unfocused: no lifecycle handling in
  `lib/desktop/main.dart`.
- Hover rebuilds the whole row (`packages/glacier/.../pressable.dart:89`): contained, minor.

## Looked at and fine

Icon paths are parsed once (`lib/art/svg_path.dart`); token lookups are cached per theme; the conversation list is
lazy and keyed; contact-photo futures are cached; effects, ripple avatars and spinners stop by themselves; glass blur
is in menus, popovers and call screens, not the everyday screen (and `--dart-define=GHOST_PLAIN=true` turns the kit's
blur off: an option for the Linux build); game sensing does not run on Linux.

## What is left

1. **Measure on Linux.** Everything above was reasoned and tested on a Mac. `glxinfo | grep "OpenGL renderer"`
   first; then `flutter run --profile` with the performance overlay, or `integration_test/desk_frames_test.dart`.
2. The list of conversations as one `State` (finding 2's remainder): split what Voice, Summaries and the networks
   each change into their own listeners, if a profile still shows its builds.
3. The stores read whole at start, and a store a chat rather than one file (finding 4's remainder), if start-up or
   memory shows it.
