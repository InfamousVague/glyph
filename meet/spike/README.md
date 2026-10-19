# The Meet bot's spike (GHST-106, 2026-10-19)

`join.mjs` is the proof of concept that Ghost can sit in a Google Meet and hear it: one Chrome per participant,
driven by Playwright (1.59, from the npx cache; not a repo dependency yet) against the installed Google Chrome.

    PROFILE=<signed-in profile> node join.mjs <meet url> bot "Ghost.md Notetaker" <seconds>
    PROFILE=<a copy of it>      node join.mjs <meet url> speaker "Speaker Test" <seconds> <voice.wav>

`lines.txt` is the script the test voices read (macOS `say`: Samantha for "Alice", Daniel for "Bob"), laid out
on 60-second tracks with ffmpeg and played as the speaker's microphone (Chrome's fake capture).

## What was found

- **Anonymous guests are refused outright.** "You can't join this video call" within seconds of Ask to join, before
  the host sees a request: with automation markers and without them, from a plain unautomated browser too, with
  the meeting's access Trusted and even Open. Google's safeguarded guest admit flow (March/April 2026) on a
  personal-account meeting. So Ghost signs in to an account of its own: ghost.notetaker@gmail.com.
- **Signing in.** By hand, once, in a plain Chrome (`open -na "Google Chrome" --args --user-data-dir=…`); Google
  refuses a sign-in in an automated browser. Playwright then opens the same profile with the real keychain: its
  default `--use-mock-keychain` cannot unseal the profile's cookies, and Chrome throws them away (the first sign-in
  was lost that way).
- **Joining.** Signed in and on the invite, Ghost gets "Join now" and walks in. In a meeting set to Trusted with
  "Anyone with the meeting link can ask to join" off, invited only, it joined without knocking. If the account is
  still counted in the call from a window that died, Meet offers "Switch here" (the bot takes it) or "Other ways to
  join › Join here too".
- **In the call.** Meet hides its tray of controls until the pointer moves: "in the call" is the Leave button
  being attached, not visible.
- **Hearing it.** The remote WebRTC tracks fed to Web Audio, and Meet's own media elements, gave silence; Meet does
  not play through page `<audio>` elements. What works is capturing the bot's own tab: `getDisplayMedia` with
  `preferCurrentTab` and Chrome's `--auto-accept-this-tab-capture` ("Tab audio"), into a MediaRecorder (Opus/WebM,
  5-second slices handed to Node). The bot has no microphone or camera permission and no fake devices: with
  `--use-fake-device-for-media-stream` on, tab capture hands back the fake microphone instead.
- **The speaker's voice file.** Chrome's audio service sandbox could not read the WAV; `--disable-features=
  AudioServiceOutOfProcess,AudioServiceSandbox` (the test speaker only).
- **Captions.** Pressing "c" (or Turn on captions) and reading the region `[role=region][aria-label*=aption]` twice a
  second gives live, word-accurate text under the speaker's display name.
- **Result.** 75 seconds recorded; Whisper base.en (the app's own model) gave back the whole script, word for word but
  "pricing page" once heard as "project". Twice: an open meeting, and a private one by invite.

## Not yet tested

- Two different speakers' names (both test windows were Ghost's own account; the captions said "Ghost").
- Linux and the box: there the tab's sound would come from a PulseAudio null sink as well, under Xvfb.
