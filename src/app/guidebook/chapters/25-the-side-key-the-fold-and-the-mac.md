# The side key, the Fold and the Mac

_Ghost.md runs on Android phones, folding ones included, on the Mac and in a browser. The notes are the same everywhere. What changes is how you start one, and what the device can do._

## Where it runs

| | Android app | Mac app | Web app |
| --- | --- | --- | --- |
| Starting a recording | Hold the side key, the Record note shortcut, or Speak | Speak | Speak |
| Speech into words | On the phone | On the Mac | The browser's own recognition |
| The models, for formatting and asks | On the phone | On the Mac | None |
| Haptics | Yes | No | No |
| Notion | Yes | Yes | No |
| Updates | Itself | Itself | Reload the page |

## Android: the side key

Holding the side key starts a recording, even over the lock screen. That works because Ghost.md registers as the phone's digital assistant, and a held side key opens the assistant. The welcome guide's side-key page shows the rows to tap on your phone, opens the right settings screen, and looks again when you come back.

| Phone | Make Ghost.md the assistant | Point the side key at it |
| --- | --- | --- |
| Samsung | Settings › Apps › Choose default apps › Digital assistant app › Device assistance app › Ghost.md | Settings › Advanced features › Side button › Press and hold › Digital assistant |
| Pixel | Settings › Apps › Default apps › Digital assistant app › Default digital assistant app › Ghost.md | Settings › System › Gestures › Press and hold power button › Digital assistant |
| Others | The same as the Pixel's | Search Settings for "press and hold", then Digital assistant |

Ghost.md then takes the place of the phone's own assistant: Gemini, or on a Samsung, Bixby or Gemini. You can switch back in the same place at any time.

If you would rather not, long-press the Ghost.md icon and choose **Record note**. It opens the same recording the side key does.

### While it records

- **The screen stays on** for as long as the recording runs.
- **A press of the side key stops it** and saves the note, as Done does. Holding the key again stops it too. Letting go of the hold that started it does not. Before your first words, the recorder says which works on your phone: "Press the side key to stop", or "Hold the side key again to stop".
- **Rings rise from where the key is**, paced by your voice: one faint ring now and then in a pause, more and wider as you talk. Android doesn't say where a phone's buttons are, so Ghost.md guesses from the model. If the rings aren't beside your key, **Settings › Recording › Where the side key is** has a Height slider, and once it has moved, **Reset** puts Ghost.md's guess back. With reduced motion, three rings stand still.
- **Over the lock screen, only the recording shows.** When it ends on a locked phone, Ghost.md steps back behind the lock screen, and the note is there once you unlock.

### Touch and back

**Haptics** answer a style or a cue with a small tap. Switch them in Settings › Feel. The phone's back gesture works inside Ghost.md, stepping back one screen at a time rather than leaving the app.

## Folding phones

On a folding phone that reports its hinge, the note unfolds with it: paper folded down its middle, flattening as you open the phone. Your hand drives it, not a clock. It runs only on the way open, from about thirty degrees, where the phone hands the app to the inner screen. If the hinge stops partway, the note settles flat by itself. Closing never folds it back up, and with reduced motion there is no unfold at all.

Opened out, the window has room for more. Settings becomes a split view. The sidebar icon opens your notes in a popover over the note, or, with **Appearance › Sidebar › Docked**, in a column beside it. On a folding phone the docked sidebar starts hidden, a tap away.

## The Mac

The Mac app needs macOS 13.1 or later. It is signed but not yet notarised, so the first open takes a step. macOS says it can't check the app: choose Done, then in System Settings › Privacy & Security scroll down and choose **Open Anyway**. On macOS 14 or older, Control-click Ghost.md and choose Open instead. You only do this once.

The first time you record, allow the microphone. What you say is turned into words on the Mac itself, and the models run there too. Sign in with the same account as your phone and your notes follow you. Settings › Recording is Android's, but those settings sync, so the Mac follows what the phone chose.

- **Browse files**, in the notes list, opens the notes folder in Finder. On Android the same button opens the Files app, where Ghost.md lists its library.
- **⌘K** opens the command palette: everything Ghost.md can do, searched. On a phone it is Search and commands in the sidebar.

## The web app

**attack.fm/glyph** is the same editor, with the same marks. Notes are kept in that browser, and sync once you sign in. Speech is turned into words by the browser's own recognition, which in Chrome sends your voice to Google, and a recording's sound is not kept. There are no models, so the AI does not run there, and there are no haptics and no Notion. A link card shows the site and its path without asking the site anything.

## iPhone and iPad

There is no app yet, so the web app is the way in, and ghostmarkdown.com puts it first on an iPhone or iPad. The iPhone build in the code has no on-device transcription, no models, no Notion, no link previews and no updates of its own yet.

## Getting the app, and keeping it new

**ghostmarkdown.com** offers Download for Android, Download for Mac, and Open in your browser, with the device in your hand first. **attack.fm/glyph/install.html** has the steps. On Android: tap Install, open the download, allow installs from Chrome if Android asks, and tap Update or Install. Your notes stay where they are.

From then on the app updates itself:

- It looks for an update about four seconds after it starts, when you come back after a minute or more away, and every two minutes while it is on screen.
- Every update is signed, and one that Ghost.md's key did not sign is refused.
- A downloaded update runs the next time the app starts, or at once from **Reload** in Settings › About.
- A build that fails to start is set aside, and the one before it runs instead.
- When an update needs a new app, About offers **Install**. Android asks you to confirm, and the first time, to allow installs from Ghost.md. A copy from the Play Store gets new apps from the store.

**Update alerts**, in Settings › About on Android, are off until you switch them on. Then a check about every six hours tells you, once, when a new version is out, even with Ghost.md closed. Local only stops the app's own checks, but not these.

## Read next

- [[Recording a note]]
- [[Settings, one section at a time]]
- [[Over the air, and releases]]
