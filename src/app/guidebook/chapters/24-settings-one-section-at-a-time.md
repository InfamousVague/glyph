# Settings, one section at a time

_Every section of Settings in the order the list shows them, with what each setting does. Defaults are marked where they matter._

## Finding your way

Settings opens on a list of sections. On a phone, each opens as a page of its own: the back gesture or a swipe to the right steps out, and a swipe to the left goes back in. On a wide window, a Mac or a folding phone opened out, Settings is a split view with the sections down the left.

**Search settings**, at the top of the list, finds a section or a single setting inside one. Every word you type has to start a word of what it finds, in any order, so "sm ed" finds Smoke at the edges. A result opens its page and lights the setting for a moment. Enter opens the first result, and on a keyboard ⌘F or Ctrl+F goes to the field.

Some sections appear only where they mean something: Recording on Android, Feel where there is a motor, and a plugin's page while the plugin is on.

## Account

Signed out, it opens on **Sign in**, with **Create an account** and **Lost the password**, which takes a recovery code, below it. Signed in, it has **Sync now**; **Live typing (trial)**, off until you switch it on, for this device only, starting with the next note you open; **Password and recovery codes**; **Sign out**, which leaves your notes on the device; **Shared links**, once you have shared something, with every note and book you have shared and a Copy and a Stop for each; and **Delete account**. More in [[Accounts, sync and the key you hold]].

## Type

| Setting | Choices | What it does |
| --- | --- | --- |
| Text size | **Large**, Larger, Largest | The note, the list and the headings all follow it. |
| Note font | **Maple Mono**, Fira Code, Inter, Noto, Plex | The words of a note and its code. Maple Mono and Fira Code join pairs like `->` and `!=` into one sign. |
| Interface font | **Inter**, Noto, Plex | Tabs, lists, Settings and buttons. |
| Link previews | **On**, or off | A card with the page's title under a line that is only a link. The apps read the title from the linked site; the web version shows only the site and its path. |

## Appearance

| Setting | Choices | What it does |
| --- | --- | --- |
| Page | System, Light, **Dark**, Dawn, Boreal, Ember | Ink on paper or paper on ink. Dawn is a tinted light page, Boreal and Ember tinted dark ones, and each brings its own accent. System follows the device. |
| Accent | **Ink**, Graphite, Red, Amber, Green, Teal, Purple | Colours the few things that mark a choice: a focus ring, a chosen segment. Ink is the app's own grey. |
| Spacing | Tightest, Tight, **Comfortable**, Roomy, Roomiest | The padding and gaps of everything. The words keep their size. |
| Size | 85%, 93%, **Default**, 110%, 125% | Everything larger or smaller together, buttons and bars as well as words. Text size changes only the words. |
| Sidebar | **Popover**, Docked | On a wide window, the sidebar icon opens your notes over the note, or docks them as a column beside it. |
| Corners | Square, Soft, **Round**, Roundest | How round cards and fields are drawn. Pills stay pills. |
| Code | Light page: **Pastel**, Ink, GitHub, Solarized. Dark page: **Pastel**, Ink, One Dark, Dracula, Nord | The colours of code in a code block. Ink keeps code in the page's ink. |

## Recording

On Android only.

| Setting | Default | What it does |
| --- | --- | --- |
| Stop when I go quiet | Off | Saves the recording after four seconds of quiet, once you have started talking. The side key and Done still work. |
| Commands start with “hey Ghost” | On | Whether the recorder's suggestions start with Hey Ghost. At this version it changes little else: see below. |
| Review after recording | On | When you stop, a slower speech model listens again and the language model thinks the note through out loud, then shows what it would fix, for you to keep or commit. |
| Where the side key is | Ghost.md's guess | A Height slider that moves the rings to sit beside your key. Once you have moved it, **Reset** beside Use Ghost.md's guess puts it back. |
| Better words | On | After you finish, a larger model goes over the recording and fixes the words: a few seconds of the phone per minute of speech. |

The Hey Ghost switch does less than its name says. At this version a recording is read for a command once, when you stop, and that reading does not look at the switch. An ask of the AI counts only after Hey Ghost, whichever way it is set. A command that names a note, such as "add eggs to Groceries", counts with or without Hey Ghost, and so do a run's own words at the start of a recording into a note, such as "fix the spelling". A command that names a note still asks before it acts.

## Formatting

**Local only**, off by default, keeps Ghost.md to what is already on the device: no update checks, no model downloads, no sync, no link previews, and no plugin that uses the internet. [[What stays on your phone]] has exactly what it stops.

**Model** chooses which model rewrites your notes. **Get** downloads one, with the bytes shown as they arrive, and a model that is here can be chosen. Qwen3.5 2B is quick, Qwen3.5 4B is the balance and the default, Qwen3.5 9B is the most careful and wants 12 GB of memory, and Gemma 4 E4B is a different voice. Below, **On the phone** lists what is downloaded, with **Remove** and the storage it takes. In a browser the page only says that formatting runs on the device. More in [[The models on your phone]].

## Feel

**Haptics**, on by default: a small tap when a style or a cue kicks in. Only in the phone app, where there is a motor.

## The plugins' pages, then Plugins

Each plugin that is on and has a page of its own is listed next. **Notion** holds its sign-in and the boards Notion shared, **GitHub** the repos read and the token, and **Claude** the way to connect. Then **Plugins**, with a card and a switch for each of the four. See [[Notion and GitHub]].

## Animations

| Setting | Default | What it does |
| --- | --- | --- |
| Animation speed | Relaxed, **Normal**, Brisk | How quickly letters gather and screens and sheets move. |
| Ghostly typing | On | Letters arrive as smoke and gather into words as you talk or type, and dissolve where they are deleted. |
| Smoke at the edges | On | A page going under the header or the dock turns to smoke as it passes. |
| Ripples while recording | On | The newest words move with your voice as the phone hears it. |

Your device's own reduce motion setting comes first: with it on, Ghost.md holds still whatever these say. Switching one off leaves the thing itself working, only still.

## Cheat sheet

Every mark you can type and every cue you can say, on one page to look things up in. It opens from a note's More sheet and from About too.

## About

- **The version**, large, and where this build stands under it.
- **Updates**: the state of things, **Reload** when an update is downloaded, **Install** with a version number when an update needs a new app, and **Check for updates**. The web version says to reload the page, and a copy from the Play Store gets new apps from the store.
- **Update alerts**, on Android: off until you switch them on, then a notification when a new version is out, even with Ghost.md closed.
- **Help**: **Ghost.md Academy**, which teaches Markdown a mark at a time; **How to talk to Ghost.md**, the walkthrough, with the side key on Android; **Formatting cheat sheet**; **Add the example board**; **Add the example canvas**; **Add the “How Ghost.md works” canvas**; and **Add the sample note**, one note with every mark in it.
- **What's new**: every update, newest first, the one you are on marked "you're on this one". After an update, the new entries also show once, in a sheet.
- **Privacy policy**, which opens ghostmarkdown.com/privacy.html.

## What travels, and what stays

Signed in, the settings about you are the same on every device. The ones about this device stay on it.

| Travels with your account | Stays on this device |
| --- | --- |
| Page, Spacing, Text size, both fonts, Link previews, Code colours | Accent, Size, Sidebar, Corners |
| Stop when I go quiet, “hey Ghost”, Review after recording, Better words | Local only, the chosen model and the models downloaded |
| Animation speed, Ghostly typing, Smoke at the edges, Ripples while recording | Haptics, Where the side key is, Live typing, Update alerts |
| How notes are shown, your open tabs and their groups, workspaces, the trash, your shared links | Each plugin's switch, and what it keeps: boards, repos, tokens, the Notion sign-in |

## Developer mode

Seven taps on the version in About turn on developer settings.

## Read next

- [[The side key, the Fold and the Mac]]
- [[What stays on your phone]]
- [[The models on your phone]]
