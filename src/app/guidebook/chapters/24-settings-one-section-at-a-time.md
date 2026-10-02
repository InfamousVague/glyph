# Settings, one section at a time

_Every section of Settings in the order the list shows them, with what each setting does. Defaults are marked where they matter._

## Finding your way

Settings opens on a list of seven sections: **Account**, **Notifications**, **Appearance**, **Recording**, **AI**, **Plugins** and **About**. Recording and AI are there in the Android app and on the Mac, where a recorder has a model behind it, so the web version lists five. On a phone, each opens as a page of its own: the back gesture or a swipe to the right steps out, and a swipe to the left goes back in. On a wide window, a Mac or a folding phone opened out, Settings is a split view with the sections down the left.

A few pages open from a row on another page rather than from the list: Organizations from Account, a plugin's own page from its card on Plugins, and the cheat sheet, Specification and Examples from About. Over one of those, the way back names the page it came from, "← Account", "← Plugins" or "← About", and back steps there first. In the split view the page it came from stays marked in the column.

**Search settings**, at the top of the list, finds a section or a single setting inside one, the pages behind a row included. Every word you type has to start a word of what it finds, in any order, so "sm ed" finds Smoke at the edges. A result opens its page and lights the setting for a moment. Enter opens the first result, and on a keyboard ⌘F or Ctrl+F goes to the field.

Two things elsewhere open Settings at a card, lit the same way. The words "Local only", where a page says it is holding something off, open Account at the Privacy card. **Get a model** on the home page opens AI at the Model card.

Some rows appear only where they mean something: Recording on Android and the Mac, the side key and the meetings on Android, the sidebar on a wide window, Touch where there is a motor, and a plugin's page while the plugin is on.

## Account

Who you are, and what leaves the device.

Signed out, it opens on **Sign in**, with **Create an account** and **Lost the password**, which takes a recovery code, below it, then the **Privacy** and **Location** cards. Signed in, the **Sync** card has **Sync now**, **Sync meeting recordings** (off, so a meeting's audio stays on the device that recorded it), **Live typing (trial)** (off until you switch it on, for this device only, from the next note you open), **Password and recovery codes**, and **Sign out**, which leaves your notes on the device. Then **Organizations**: the teams you are in, an invitation waiting with its Accept and Decline, and New organization, each opening the organization's settings ([[Accounts, sync and the key you hold]]). Then **Shared links**, once you have shared something, with a Copy and a Stop for each note and notebook. Then Privacy and Location, and **Delete account** last. While Local only is on, a line at the top says nothing syncs, and its "Local only" brings the Privacy card into view. More in [[Accounts, sync and the key you hold]].

### Privacy

| Setting | Default | What it does |
| --- | --- | --- |
| Local only | Off | No sync, updates, downloads or link titles, and plugins that use the internet are held off. The map, place names and the location for new notes are held off too, and the Location card says so under each. It stays on this device. [[What stays on your phone]] has exactly what it stops. |
| Link previews | On | A card under a line that is only a link. The apps read the page's title from the linked site. The web version shows only the site and its path. |
| Privacy policy | | Opens ghostmarkdown.com/privacy.html. Under the card, what it comes to in two lines. |

### Location

| Setting | Default | What it does |
| --- | --- | --- |
| Map on a tagged note | On | A small map at the top of a note that says where it was written, and under each place the + beside the line adds, its tiles fetched from openstreetmap.org. |
| Place names | On | The name of the place, asked of OpenStreetMap once when a location or a place is added, and kept in the note. |
| Tag new notes with my location | On | Every note you make on this device starts with where you were, typed or spoken. It stays on this device. If location is refused, it stays on and new notes are not tagged until location is allowed, and the card says so. |

Local only holds all three off.

## Notifications

What reaches the bell in the tab row and the notifications under it. The row in the list says how many of the four are on, "4 of 4 on".

| Setting | Default | What it does |
| --- | --- | --- |
| Team | On | Who joined, left or was removed from an organization you are in, a rename, a deletion, and an invitation of yours answered. |
| Claude | On | A note Claude created, edited or added to through the connector, an entry it wrote in a journal, a rule it added. |
| Summaries | On | A meeting written up, here in the list. The phone's own notification for that is under Recording. |
| Conflicts | On | A note kept twice because two devices had changed it. |
| Mute an organization | | A row for each organization you are in, once there is one: its team news is not shown or counted. The organization's own settings have the same switch. |

An invitation has no switch: it is always shown, since the person who sent it is waiting. These switches travel with your account. Under the card: "Ghost.md looks when it opens; the bell shows what arrived." Nothing is fetched while the app is closed, and there is no phone notification for these yet.

## Appearance

How it looks, moves and feels. Its cards are Page, Accent, Type, Spacing, Corners, Code, Sidebar on a wide window, Motion and, in the phone app, Touch. Type is led by an "Aa" in the note's own face at the size chosen.

| Setting | Choices | What it does |
| --- | --- | --- |
| Page | System, Light, **Dark**, Dawn, Boreal, Ember | Ink on paper or paper on ink. Dawn is a tinted light page, Boreal and Ember tinted dark ones, and each brings its own accent. System follows the device. |
| Accent | **Ink**, Graphite, Red, Amber, Green, Teal, Purple | Colours the few things that mark a choice: a focus ring, a chosen segment. Ink is the app's own grey. |
| Note font | **Maple Mono**, Fira Code, Inter, Noto, Plex | The words of a note and its code. Maple Mono and Fira Code join pairs like `->` and `!=` into one sign. |
| Interface font | **Inter**, Noto, Plex | Tabs, lists, Settings and buttons. |
| Text size | **Large**, Larger, Largest | The note, the list and the headings. |
| Scale | 85%, 93%, **Default**, 110%, 125% | Everything, buttons and bars as well as words. It stays on this device. |
| Spacing | Tightest, Tight, **Comfortable**, Roomy, Roomiest | The padding and gaps of everything. The words keep their size. |
| Rounding | Square, Soft, **Round**, Roundest | Cards, fields and buttons. Pills stay pills. |
| Code | Light page: **Pastel**, Ink, GitHub, Solarized. Dark page: **Pastel**, Ink, One Dark, Dracula, Nord | The colours of code in a code block. Ink keeps code in the page's ink. |
| Sidebar | **Popover**, Docked | On a wide window only: your notes over the note, or docked as a column beside it. |
| Animation speed | Relaxed, **Normal**, Brisk | How quickly letters gather and screens and sheets move. |
| Ghostly typing | **On** | Words you say arrive as smoke, and words you delete leave as smoke. What you type appears at once. |
| Smoke at the edges | **On** | A page turns to smoke as it passes under the header or the dock. |
| Ripples while recording | **On** | The newest words move with your voice as the phone hears it. |
| Haptics | **On** | A small tap when a style or a cue kicks in. Only in the phone app, where there is a motor. |

Your device's own reduce motion setting comes first: with it on, Ghost.md holds still whatever Motion says. Switching one off leaves the thing itself working, only still.

## Recording

In the Android app and on the Mac.

| Setting | Default | What it does |
| --- | --- | --- |
| Stop when I go quiet | Off | Saves after four seconds of quiet, once you have started talking. The side key and Done still work. |
| Review after recording | On | After you stop, a slower listen and a read-through, with what it would fix for you to keep. For recordings under three minutes. |
| Better words | On | A larger model goes over the recording and fixes the words, a few seconds of the phone or the Mac per minute of speech. |
| Summaries | **Meetings**, Meetings and long voice notes, Off | The model on the phone or the Mac writes a summary under the title: what was said, what was decided, and your to-dos. A long voice note is one over three minutes. |
| Tell me when a meeting is written up | | On Android. **Allow** asks for notifications, and the row then says On. |
| Write up straight away | Off | On Android. Off, a meeting is written up when the phone is charging or above half. On, straight away, which uses more of the battery. |
| Remove audio older than a month | | Two taps, the first arming it. Every word and phrase stays and only the audio goes. Under the card, how much room your tapes take. |

## AI

In the Android app and on the Mac. The **Model** card chooses the model that writes the summaries and the review, and Format, Summarize and Enhance on a note. Each model is listed once. **Get** downloads one, with the bytes shown as they arrive, and a model that is here can be picked, with **Remove** beside it, which takes two taps: Remove, then Tap again. The one in use says In use and has no Remove: pick another first. When it is the only one here there is nothing to pick, so it has Remove too. If the chosen model is not here, the one standing in for it is the one in use. Under the card, how much the models take. Qwen3.5 2B is quick, Qwen3.5 4B is the balance and the default, Qwen3.5 9B is the most careful and wants 12 GB of memory, and Gemma 4 E4B is a different voice. The card also holds the switch for filling a note's blanks on their own once typing stops. More in [[The models on your phone]].

## Plugins

A card and a switch for each of the four, with what each may reach and why. A plugin that is on and has a page of its own has a row on its card that opens it: **Notion** holds its sign-in and the boards Notion shared, **GitHub** the repos read and the token, and **Claude** the way to connect. See [[Notion and GitHub]] and [[Claude on your notes]].

## About

- **The version**, large, and where this build stands under it.
- **Updates**: the state of things, **Reload** when an update is downloaded, **Install** with a version number when an update needs a new app, and **Check for updates**. The web version says to reload the page, and a copy from the Play Store gets new apps from the store.
- **Update alerts**, on Android: off until you switch them on, then a notification when a new version is out, even with Ghost.md closed.
- **Help**, five rows. **Ghost.md Academy** teaches Markdown a mark at a time. **The welcome walkthrough** opens the pages from the first launch. **Cheat sheet** opens every mark you can type on one page, which a note's More sheet and the Academy open too. **Ghost.md: The Guide** adds this Guide and opens it, or opens the one you have. **Examples** opens a page of four: **Add the sample note**, one note with every mark in it, **Add the example board**, **Add the example canvas** and **Add the “How Ghost.md works” canvas**.
- **What's new**: every update, newest first, the one you are on marked "you're on this one". After an update, the new entries also show once, in a sheet.

## What travels, and what stays

Signed in, the settings about you are the same on every device. The ones about this device stay on it.

| Travels with your account | Stays on this device |
| --- | --- |
| Page, Spacing, Text size, both fonts, Code colours | Accent, Scale, Sidebar, Rounding |
| Link previews, Map on a tagged note, Place names | Local only, Tag new notes with my location |
| Stop when I go quiet, Review after recording, Better words, Summaries, Write up straight away, Sync meeting recordings | The chosen model and the models downloaded |
| Animation speed, Ghostly typing, Smoke at the edges, Ripples while recording | Haptics, Live typing, Update alerts |
| The four Notifications switches, and the organizations you have muted | |
| How notes are shown, your open tabs and their groups, workspaces, the trash, your shared links | Each plugin's switch, and what it keeps: boards, repos, tokens, the Notion sign-in |

## Developer mode

Seven quick taps on the version in About turn on developer settings. From the third tap a message counts down the taps that are left. Two pages then join the list, under About:

- **Developer.** **Window** reads off what the page is given: the top inset, the page's size, the screen and the engine that draws it. **Smoke bench** opens a page for timing the smoky edge's frames. **The phone at work** plays the scene after Done from a script, with the **Readings** chosen: a heat reading, none as on a phone that hides its thermal zones, or none at all as on the Mac. **Developer settings** is the switch that hides both pages again.
- **Test results** is the report of the tests this release ran ([[Tests, and the report that ships]]).

The Developer page also has the two resets. **Reset local data** clears the notes, recordings, pictures, settings and the sign-in on this device, and keeps the downloaded models. **Reset everything** takes the models too. Each needs two taps, the first arming it for five seconds, and Ghost.md opens on the welcome walkthrough afterwards. Developer settings stay on.

## Read next

- [[The side key, the Fold and the Mac]]
- [[What stays on your phone]]
- [[The models on your phone]]
