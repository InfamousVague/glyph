# Android extras and the watch

Ghost.md on Android reaches past its own window: widgets on your home screen, shortcuts on its icon, a tile in Quick Settings, an optional place as your phone's assistant, layouts made for the Galaxy Fold, and a watch app. This chapter covers each, and how the app keeps itself up to date.

Works on: Android, except where it says otherwise.

## Home-screen widgets

Press and hold an empty spot on your home screen, choose Widgets, and find Ghost.md. There are twelve:

| Widget | What it does |
|---|---|
| **Voice note** | Record a voice note in one tap, and see your last recordings. |
| **Quick capture** | A new note, a voice note, a checklist or a scan, in one tap. |
| **To-dos** | Your open to-dos from every note, overdue first. Tick them here. |
| **Calendar** | Today's and the week's events, beside the to-dos due. |
| **Recent notes** | The notes you wrote in last, a tap away. |
| **Pinned notes** | The notes you pinned to the top, a tap away. |
| **Today** | Today's note: its first lines, its to-dos ticked here, and a pen to write in it. |
| **Search** | Search your notes, with the ones you wrote in last under the field. |
| **A note** | One note you choose: its name and first lines. Tick its to-dos here. |
| **A folder** | One workspace or folder you choose: its notes, and a + that files a new one there. |
| **Ask AI** | Ask the app's AI assistant about your notes, aloud or in the chat. |
| **Next up** | The one next thing: today's next event, or the most pressing to-do. |

A few notes:

- **A note** and **A folder** ask which one to show when you place them.
- A to-do ticked on a widget is ticked in its note, even with the app closed.
- **Calendar** needs the Calendar plugin. **Ask AI** needs Claude on, with an API key. See [[Plugins, one by one]] and [[Claude in Ghost.md]].
- The widgets follow the app's light or dark look.

## The icon's shortcuts

Press and hold Ghost.md's icon for its shortcuts:

- **New note**: write a new note.
- **Voice note**: record a voice note.
- **Today**: today's note.
- **Search**: search your notes.
- **Scan**: scan a document.

The notes you opened last follow them. Drag any shortcut onto your home screen to keep it there.

## The Quick Settings tile

Swipe down twice from the top of the screen and edit your tiles. Add **New note**. Tap it and Ghost.md opens a new note with the keyboard up. On a locked phone, it asks you to unlock first.

## The phone's assistant and the side key

You can make Ghost.md your phone's digital assistant. Then holding the side key, or your phone's assistant gesture, opens Ghost.md listening. If Claude is set up, you talk to Claude, and it opens the note it writes in. Without an API key on this device, it records a voice note instead.

**It's off by default**, on every phone. To turn it on:

1. Add Claude in the Market and keep your Anthropic API key. See [[Claude in Ghost.md]].
2. Go to Settings › Claude, and find the **Phone assistant** card.
3. Switch on **Ghost.md as the phone's assistant**. Android's screen to choose an assistant opens.
4. Pick Ghost.md under **Default digital assistant app**.
5. Open Ghost.md again.

Ghost.md can't make itself the assistant: Android asks you to pick it. Back on the card, **Default digital assistant app** says whether Ghost.md is the one chosen, with **Choose** or **Change**.

To have the side key open it, set your phone's side key to wake the digital assistant, in the phone's own settings.

With the switch on, the icon's **Voice note** shortcut becomes **Record note**. With it off, nothing outside Ghost.md starts a recording.

**The microphone is only open while you talk.** Ghost.md never waits in the background for a word. Recording, voice memos and meetings work the same either way.

## On a Galaxy Fold

Folded, Ghost.md is a phone app. Opened out, it uses the room:

- Your notes can sit in a column beside the open note. Press the panel icon on the top bar to show or hide it.
- All notes shows its cards three or four across.
- The Market's cards stand two to four across, and a plugin's page opens beside them.
- Menus and panels keep to their own side of the crease, so nothing is split down the middle.

See [[Home, tabs and the sidebar]].

## The watch app

Ghost.md has a Wear OS watch app for voice notes from your wrist. Tap, talk, and the note is made on your phone, its words heard by your phone, as if you'd recorded it there.

**It isn't in the Play Store yet.** For now it's installed by hand with Android's developer tools, and needs a watch on Wear OS 3 or later: a Galaxy Watch4 or newer, for example. We'll say here when it can be installed from the store.

### On the watch

One screen: the ghost in a ring is the button, with "Tap to record" under it. Your last five recordings are listed below, each saying where it is: *Waiting for your phone*, *Sending*, *Sent*, or *On your phone*.

Other ways to start:

- The tile **Record a note**. Add it from the end of your tiles.
- A complication on a watch face that takes one.
- The long-press shortcut **Record** on the app's icon.
- A button on the side of the watch, where the watch lets apps have one.

The microphone opens only on a tap. A recording keeps going when your wrist drops, and stops by itself at an hour.

### Getting it to your phone

The watch and the phone find each other on their own, through the watch's pairing with the phone. If the phone isn't near, the recording waits on the watch and goes when it is. It stays on the watch until the phone says it has it.

On the phone:

- **Ghost.md running**: the note is made at once.
- **Ghost.md closed**: a notification, "Recording from your watch", says to open Ghost.md to finish it.

Up to ten minutes, a recording becomes a voice note, written as dictation on the phone is: "new paragraph" and "bullet point" work, but "Hey Ghost" commands are written as words. Over ten minutes it becomes a meeting, written up like one.

If Claude is set up, **Send short watch recordings to Claude** sends recordings of up to ten minutes to Claude instead, as if you'd said them to Talk to Claude. It's on by default where Claude is.

### Settings › Recording › Watch

Shows each watch with Ghost.md, "Connected" or "Connected, not nearby", the last voice note from the watch, and how many wait to be made notes. The **Send short watch recordings to Claude** switch is here too.

## Updates

The Ghost.md from ghostmarkdown.com updates itself. It looks for a new version a few seconds after it opens, and again when you come back to it after a while.

When one is out, a card above your notes says "Ghost.md 2.3.35 is out." with **Install**. Ghost.md downloads it, checks it was signed by us, and hands it to Android's installer. The first time, Android may ask you to let Ghost.md install apps: allow it, then come back.

Settings › About shows where things stand, with **Check for updates**.

From the Play Store, updates come through the Play Store instead. Nothing looks for updates while the app is closed.

See also: [[Install Ghost.md]] · [[Speaking your notes]] · [[Claude in Ghost.md]] · [[Plugins, one by one]] · [[Home, tabs and the sidebar]] · [[Meetings and the Meet bot]]
