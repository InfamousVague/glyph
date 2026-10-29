# Sound packs

Settings › Sounds plays these (lib/sounds/sound_pack.dart, lib/sounds/sounds.dart). The plan, with the ElevenLabs
prompts for each pack, is docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, "Sounds".

**Every file in `ghostly/` now is a PLACEHOLDER**: soft sine tones made by `tool/placeholder_sounds.py`, so the
settings work before the real sounds exist. Replace them by dropping files in with the same names.

## Layout

```
assets/sounds/<pack>/<event>.ogg   Android (SoundPool in the app, the notification channels)
assets/sounds/<pack>/<event>.caf   the Mac and the iPhone (AVAudioPlayer, and a notification's sound)
```

A pack folder must be listed in `pubspec.yaml` under `flutter: assets:` (Ghostly's is), and named in `soundPacks`
in lib/sounds/sound_pack.dart and `soundPackChoices` in lib/core/preferences.dart.

## The twelve files of a pack

| File | When | Kind | Length |
| --- | --- | --- | --- |
| `todo-ticked` | a to-do's box ticked | interface | under 0.25 s |
| `all-ticked` | the last open to-do ticked | interface | about 1 s |
| `record-start` | the recorder starts | interface | under 0.4 s |
| `record-stop` | the recorder stops | interface | under 0.4 s |
| `writeup-ready` | a summary or write-up is ready | notification | about 1 s |
| `reminder-due` | a reminder is due | notification | 1 to 1.5 s |
| `meeting-joining` | Ghost is joining a meeting | notification | about 1 s |
| `team-comment` | a comment or mention from the team | notification | under 1 s |
| `lovart-ready` | Lovart's picture is ready | notification | under 1 s |
| `failed` | something failed | interface | under 0.4 s |
| `job-done` | a long job you started is done (docs/ACTIVITY.md) | interface | under 0.8 s |
| `saved` | a note saved | interface | under 0.3 s |

## Specs

- **Mono, 44.1 kHz.**
- **Peaks**: about **-12 dBFS** for an interface sound, about **-3 dBFS** for a notification sound.
- **Trimmed**: silence cut to 5 ms at each end, no reverb tail.
- **Android**: Ogg (Vorbis, or Opus for Android 10 and later). **Apple**: CAF (or AIFF), 30 seconds at most.
- Each file well under 100 KB; the app refuses anything near a megabyte.

From one master WAV per sound, for example:

```
ffmpeg -i todo-ticked.wav -ac 1 -ar 44100 -c:a libopus -b:a 64k todo-ticked.ogg
ffmpeg -i todo-ticked.wav -ac 1 -ar 44100 -c:a adpcm_ima_qt todo-ticked.caf
```

## Android notification channels

A notification's sound belongs to its channel and cannot change once the channel exists, so Android plays these
from `android/app/src/main/res/raw/`, named `sound_<pack>_<event with underscores>.ogg`
(`sound_ghostly_writeup_ready.ogg`, `sound_ghostly_reminder_due.ogg`). Copy the new `.ogg` there as well when a
notification sound is replaced, and bump that pack's channel version in android/…/ghost_md/SoundChannels.kt so
phones make a fresh channel with the new sound.
