# Ghost.md on the wrist

Matt, 2026-10-20: "build a watch app for ghost markdown that allows us to take voice notes from our wrist". A Wear OS
app that records a voice note at a tap and hands it to Ghost.md on the phone, where it becomes a voice note exactly as
if it had been recorded there: heard by the phone's own Whisper, written as dictation is, with its tape.

Matt's watches are a Samsung Galaxy Watch9 and a TAG Heuer, both paired to his Galaxy Z Fold 8. The app needs
Wear OS 3 or later (API 30): every Galaxy Watch from the Watch4 on, and TAG Heuer's Calibre E4, which shipped with
Wear OS 3. Round screens first; it lays out on square ones too.

## The parts

| Where | What |
|---|---|
| `android/wear/` | The watch app: Gradle module `:wear`, Kotlin and Compose for Wear OS |
| `android/wear-shared/kotlin/…/watchlink/WatchLink.kt` | What both ends say: the paths, the capability names, a take's frame. Compiled into both apps |
| `android/app/…/ghost_md/watch/` | The phone's receiver (`WatchListenerService`), its inbox (`WatchInbox`) and the app's channel (`WatchBridge`) |
| `lib/watch/` | The app making each take a note (`watch_notes.dart`), the channel (`watch_link.dart`), the phone's halves (`watch_device.dart`) |
| `lib/settings/panes/watch_section.dart` | Settings › Recording › Watch |

## On the watch

One screen, black and ink, Inter, the listening ghost (`assets/art/ghosts/08-listening.webp`, cut to 240 px and drawn
in ink):

- **Idle**: the ghost in a ring is the button, "Tap to record" under it, and the last five takes under that, each with
  its time, its length and where it is: *Waiting for your phone*, *Sending*, *Sent*, *On your phone*. Tapping a
  waiting one tries to send it now.
- **Recording**: the take's clock, and Stop ringed by three rings that spread with the voice's level. Tap to stop.
- **Stopped**: "Sent to Ghost.md" once the phone has it, "Queued. It goes to your phone when it is near." when it is
  not near, and back to the list.

Ways in, each a tap: the launcher icon; the **tile** "Record a note" (the whole tile is the button, and it opens the
app with a take started); the **complication** for any watch face that takes one (short text, monochrome or small
image), which does the same; the launcher's long-press **shortcut** "Record"; and a stem button the watch lets apps
have (`KEYCODE_STEM_1..3`, never the home key) starts and stops a take.

**The microphone opens only on a tap.** Matt's standing rule: no always-on microphone, ever. The tile and the
complication never open it themselves; they open the screen, which starts the take. A take is a foreground service of
type `microphone` (`RecordService`), started while the screen is in front, so it keeps going when the wrist drops and
the screen goes off; its notification is an ongoing activity, a chip on the watch face back to the take. It holds a
partial wake lock for the take and no longer, does not keep the screen on, and stops by itself at an hour.

**The sound**: `AudioRecord` at 16 kHz mono 16-bit PCM (`VOICE_RECOGNITION`), written as a WAV as it comes
(`WavWriter`), the header's sizes put right at the stop, or from the file's length the next time the app runs when a
kill came first (`WavWriter.repair`). That is the file the core's Whisper reads (`transcribe_wav`, `capture_refine`,
the write-up), so nothing is converted on either side.

**The queue** (`TakeQueue`, `files/takes.json` and `files/takes/<id>.wav`): RECORDING, QUEUED, SENDING, SENT,
ON_PHONE. A take's WAV stays on the watch until the phone says it has it. A take sent and not answered within two
minutes is queued again; a send that broke off is queued again at once; a take left recording or sending by a killed
process is closed and queued at the next start. Under 0.6 s is a mistaken tap and is not kept. The last eight on the
phone are listed, without their sound.

## The link

The Wearable Data Layer. It only lets two apps talk when they have **the same application id and the same signing
certificate**, so `wear/build.gradle.kts` follows the phone's own switches: `com.mattssoftware.glyph` with
`GHOST_CUTOVER=1` (the Ghost.md on Matt's phone), `com.mattssoftware.glyph.flutter` otherwise; a release signed from
the phone's own signing file (`~/.config/glyph/android-signing.properties`), a debug build with this Mac's debug key.
A debug watch app pairs with a debug phone app, a release with a release, never one with the other.

1. The watch finds the phone by its capability, `ghost_md_phone` (the phone's `res/values/ghost_wear.xml`), the nearby
   node first. None reachable: the take waits (`PhoneNear`), and WorkManager looks again in fifteen minutes, with its
   backoff after that. The phone coming within reach (`CAPABILITY_CHANGED`, heard by the watch's `WatchListener` with
   the app closed) sends at once, as do a stop, the screen coming up and a tap on a waiting take.
2. Each take goes down a `ChannelClient` channel at `/ghost/take`: a `TakeFrame` header (magic, version, the take's
   id, when it started, its length, the watch's name, the WAV's bytes) and then the WAV, byte for byte.
3. The phone answers with a message at `/ghost/ack` whose data is the id, once the WAV is kept. The watch then deletes
   its copy and lists the take as on the phone.

The phone declares `ghost_md_phone`, the watch `ghost_md_watch`, which is how Settings lists the watches.

## On the phone

`WatchListenerService` is in the phone's manifest (`CHANNEL_EVENT` for `/ghost/take`), so Play services starts it with
the app closed. It reads the take into `<dataDir>/watch/inbox/<id>.wav` and `<id>.json`, whole or not at all (a take
that broke off is dropped, and the watch, unanswered, sends it again), and only then answers the watch. A take that is
already waiting, or was made a note (the last 500 ids, `watch/seen.json`), is read to its end, answered, and kept
once.

Then:

- **The app is running** (in front or behind another): it is told on `ghost_md/watch/events` and makes the note at once.
- **The app is not running**: a notification, "Voice note from your watch" (channel *Watch*), "Open Ghost.md to make it
  a note." Opening it, or the app any other way, makes the note four seconds after launch. The notification goes once
  no take waits.

The words cannot be made with the app closed: a voice note's words are the recorder's rules over Whisper's phrases,
which live in Dart, and there is no door from Kotlin to the library to write a note. A meeting's write-up is the only
thing the phone does with the app closed, and it needs the note to be there first. So a take waits, safe in the inbox,
and the notification says so.

### How a take becomes a note (`lib/watch/watch_notes.dart`)

For each take, oldest first:

1. The note's id is made from the take's (`watchNoteId`, a UUID as a mail's is made). A note already there means the
   take was made before; it only leaves the inbox.
2. The WAV is moved into place as the note's recording by the core (`CoreFiles.adopt`, `sync_put_file_path`), as a
   meeting Ghost was in is (`lib/meet/tape.dart`).
3. **Up to ten minutes it is a voice note.** The recording is heard by the phone's Whisper: the larger model's timed
   phrases where it is on the phone (`capture_refine` over the whole tape), else the live model's words in one pass
   (`transcribe_wav`), fetched first where it is not here and Local only is off. The words are written as a note
   dictated on the phone writes them (`renderNote`, titled): a short first sentence is the title, "new paragraph",
   "bullet point", "check box" and the rest are carried out. The phrases are the tape's; the note is dated when the
   watch recorded it. Nothing heard: the note is "Watch recording, 20 Oct 14:05" with its tape.
4. Over three minutes it is a long voice note, and its summary is asked for when Settings › Recording › Summaries
   says *Meetings and long voice notes*, as the recorder asks.
5. **Over ten minutes it is a meeting**: the note is made as "Watch recording, 20 Oct 14:05" with its tape, marked a
   meeting, and written up by the phone's service as a meeting is (Whisper span by span with the app closed, then the
   summary by the Summaries setting, Write up straight away honoured). An hour of audio heard in one pass while the
   app runs would not survive the app being swiped away; the write-up does.
6. Only then does the take leave the inbox.

Words that cannot be heard yet (the recorder is on screen, the engine is busy with another pass, no voice model and
Local only on) leave the take waiting, its recording already the note-to-be's; it is tried again a minute later while
the app runs, when it comes back to the front, and when another take arrives. A take that fails three times in one run
waits for the next run. Local only never holds the words themselves: they are made on the phone.

A take is dictation: "Hey Ghost" commands said on the watch are written as words, not carried out, and the review after
a recording is not offered (nobody is looking at the phone). New notes from the watch are not geotagged: the phone's
position when the take arrives is not where it was said.

## Settings

Settings › Recording › **Watch**, the last card, only where a watch has Ghost.md (connected now, or one that ever sent
a take): each watch connected, "Connected" or "Connected, not nearby", or "No watch connected"; and under it the last
voice note ("Last voice note from Galaxy Watch9 at 14:05, 0:42.") and how many wait.

## Building

```sh
cd android
./gradlew -Pghost.wear=true :wear:assembleDebug            # build/wear/outputs/apk/debug/wear-debug.apk
GHOST_CUTOVER=1 ./gradlew -Pghost.wear=true :wear:assembleRelease   # the one for Matt's watches
./gradlew -Pghost.wear=true :wear:testDebugUnitTest
```

`:wear` is in the build only with `GHOST_WEAR=1` or `-Pghost.wear=true`, since `flutter build apk` and `flutter run`
assemble every project in the build. `tool/cutover-build.sh` sets it, so a release of the phone app leaves the watch app
beside it at `build/wear/outputs/apk/release/wear-release.apk`, same id, same key; `GHOST_WEAR=0` leaves it out. It is
not uploaded anywhere. The release is shrunk by R8 (about 3 MB); the phone's is not, for its JNI.

## Installing it

The watch app goes on each watch by hand, over Wi-Fi ADB, once the phone's Ghost.md has this code (an update of the
phone app; until then the takes wait on the watch). Use the **release** watch APK built with `GHOST_CUTOVER=1`, which
has Ghost.md's id and key: a debug one will not pair with the phone's release.

The watch and the Mac on the same Wi-Fi, the watch's Wi-Fi on (Galaxy: Settings › Connections › Wi-Fi, On rather
than Auto, while you do this).

**Galaxy Watch9** (One UI Watch):

1. Settings › About watch › Software information › tap **Software version** five times: "Developer mode turned on".
2. Settings › Developer options › **ADB debugging** on, then **Wireless debugging** on (allow it).
3. Wireless debugging › **Pair new device**: it shows an address and port and a six-digit code.
   On the Mac: `adb pair <ip>:<pair port> <code>`.
4. Back on the Wireless debugging screen, the watch's own address and port (not the pairing port):
   `adb connect <ip>:<port>`.
5. `adb -s <ip>:<port> install -r build/wear/outputs/apk/release/wear-release.apk`
6. On the watch: open Ghost.md, tap the ghost, allow the microphone and notifications. Add the tile (swipe to the end
   of the tiles, +, Record a note) and, on a watch face that takes one, the complication (long-press the face,
   Customise, a complication slot, Ghost.md).
7. Turn ADB debugging off again when done; it costs battery.

**TAG Heuer** (Wear OS):

1. Settings › System › About › Versions › tap **Build number** seven times.
2. Settings › Developer options › **ADB debugging** on.
3. Wear OS 4 and later: **Wireless debugging** on, then pair and connect as on the Galaxy (steps 3 to 5). Wear OS 3
   (Calibre E4 before its update): **Debug over Wi-Fi** on, which shows `<ip>:5555`; `adb connect <ip>:5555`, then
   install as above.
4. As steps 6 and 7 above.

`adb devices` lists the watch as `<ip>:<port>`; always give `-s` with it, since the Fold and the emulators are listed
too.

## What is not here yet

- The note cannot be made with the phone app closed (see "On the phone"); the take waits safely with a notification.
- No Play Store listing for the watch app: it is installed by hand.
- No standalone mode: a take needs the phone to become words.
