# Plugins, one by one

Ghost.md ships with thirteen plugins. Each is built in: you add it in the Market, and its settings, if it has any, get a page of their own in Settings. This chapter takes them in turn: what each does, how to set it up, where it works and what it needs from you.

Plugins that use the internet are held off while **Local only** is on. Each section says whether that applies.

## At a glance

| Plugin | Category | On from the start | Works on | You bring |
|---|---|---|---|---|
| Claude | AI | Yes | Android, iPhone, Mac | An Anthropic API key, for the app's half |
| Lovart | AI | No | Android, iPhone, Mac | Lovart access key and secret key |
| Calendar | Calendar & tasks | No | Android, iPhone, Mac | An iCal address, or a Google sign-in |
| Contacts | Calendar & tasks | No | Android, iPhone, Mac | Permission to read your contacts |
| Place reminders | Calendar & tasks | No | Android only | Permission to know your location all the time |
| Things | Import | No | Android, Mac | Things 3's data, or a list it copied |
| Todoist | Import | No | Android, Mac | A Todoist API token or a CSV export |
| GitHub | Connections | Yes | Android, iPhone, Mac | A GitHub token, to make issues |
| Notion | Connections | Yes | Android, Mac | A Notion sign-in |
| Slack | Connections | No | Android, Mac | A Slack incoming webhook per channel |
| Webhooks | Connections | No | Android, iPhone, Mac | A URL of yours; an account for incoming hooks |
| Marks | Editor | Yes | Android, iPhone, Mac | Nothing |
| Rich embeds | Editor | Yes | Android, iPhone, Mac | Nothing |

## Claude

Claude on your notes, both ways.

**In the app**, Claude answers with your own Anthropic API key. It sits on the dock at the head of every page and as **Ask Claude** in the command palette. Ask in the chat and Claude writes into the note as you watch. A to-do written in your "Ask Claude" note can be done for you a few seconds after you stop typing it.

**From Claude's own app** (claude.ai, Claude Desktop or Claude Code), Claude reaches your notes through Ghost.md's connector. Nothing about that half runs inside the app.

To set it up, open **Settings › Claude**:

- **Ask Claude**: paste your key (it starts `sk-ant-`). It is checked before it is kept.
- **Model**: which Claude answers. Each is billed to your key at its own price.
- **Spending limit**: an optional monthly limit in US dollars, with **Warn me at 80%**. The count is this device's.
- **Ask Claude note**: **Do requests as they are written**.
- **Phone assistant** (Android): make Ghost.md your phone's assistant, so holding the side key talks to Claude.
- **Connect**: the server address and the steps for claude.ai, Claude Desktop and Claude Code.

Removing the plugin takes Claude off the dock and out of the palette. It does not disconnect Claude's own app: do that in Claude.

Works on: Android, iPhone and Mac. Held off by Local only. More in [[Claude in Ghost.md]].

## Lovart

Images from your notes, made by Lovart's design agent. Write `{image: a prompt}` where a picture should go, ask any note for a moodboard of four, or let design meetings come back with inspiration.

It is off until you add it, because it sends words to Lovart and spends your Lovart credits. You bring your own Lovart keys.

Works on: Android, iPhone and Mac. Held off by Local only. The whole story is in [[Lovart]].

## Calendar

Your calendars' events in queries and on the home page's **Today**.

Set it up in **Settings › Calendar**:

- **Calendar addresses**: paste the iCal address of any calendar, such as iCloud, Outlook or Fastmail. Nothing to sign in to.
- **Google Calendar**: sign in, then tick the calendars to read. They are read every 15 minutes, and **Read now** reads them at once. The sign-in passes through ghostmarkdown.com; your notes never do.
- **To-dos on the calendar**: every open to-do with a due date becomes an all-day event on the Google calendar you pick. A new date moves it; ticked or removed, it goes. Events Ghost.md did not make are never changed.

Query events with `from: events`:

````markdown
```query
from: events
where: start >= today
show: calendar
```
````

The addresses are treated as secrets and travel sealed with your settings. Remove the plugin and nothing is read; add it back and your calendars are still chosen.

Works on: Android, iPhone and Mac. Held off by Local only.

## Contacts

Matches the people named on your to-dos with your phone's contacts. Write `@sam` on a to-do: once Sam is matched, the chip shows their picture, and a tap offers call, text or email. **A person**, on the + beside a line, picks someone from your contacts.

Add it, then tap **Turn on** in **Settings › Contacts** and allow your phone to share its contacts. **People in your notes** lists each name and the contact it matched. **Choose** another, or **Unlink**.

Nothing about a contact leaves the device or goes into a note, except the name you pick.

Works on: Android, iPhone and Mac. Not affected by Local only.

## Place reminders

A to-do with a place reminds you when your phone arrives there.

Press and hold a to-do and choose **Remind me at a place**. Search for a place, pick one the note already has, or use where you are. Within about 150 metres of it, the to-do reminds you, with **Done** to tick it, even with Ghost.md closed. The place is written on the to-do as a pin and a link, `📍 [Target](geo:…)`, so other apps can read it.

Android must let Ghost.md know where your phone is all the time. **Settings › Place reminders** says whether it does, and how to allow it. Where you are stays on the phone.

Works on: Android only. On other devices a place on a to-do is shown and kept, and your phone does the reminding. A place searched by name is looked up on OpenStreetMap, which Local only turns off; the reminders themselves keep working.

## Things

Brings Things 3 in: its areas become notebooks and its projects their pages, in a workspace of the import's own. Nothing you already have is changed.

Add it, then go to **Settings › Export › Import** (or **Settings › Things**) and find **Things 3**:

- **From Things on this Mac** reads a copy of Things' own data, every area and project. Tick **The Logbook too** to bring done and cancelled to-dos, ticked.
- **Paste from Things**: in Things, open a list and choose Share › Copy, then press it. The list becomes one note.

Works on: Android and Mac. Nothing leaves the device, so Local only does not hold it off.

## Todoist

Brings your Todoist projects in as notes: their sections become headings and their tasks to-dos, in a workspace of the import's own.

Add it, then go to **Settings › Export › Import** (or **Settings › Todoist**) and choose **Todoist**. Either paste an API token from your Todoist settings, used for this one import and then let go, or pick one or more projects' CSV exports (in Todoist, a project's menu › Manage data › Export as CSV), which are read on the device.

Works on: Android and Mac. Held off by Local only.

## GitHub

Links a note to a repo. Its list items can become issues you tick off from either side, and the repo is read into a short briefing, so names and terms come out right when the note is formatted.

1. Open a note, tap **More for this note**, and choose **GitHub repo**.
2. Pick or type the repo. Public repos are read without a token.
3. To send items as issues, or to read a private repo, paste a token in **Settings › GitHub › Token** and tap **Keep it**.

Then swipe a list item left, or tap the quiet "GitHub" after it, to make it an issue. **Send list to GitHub**, in the note's More sheet, sends every item not sent yet. Each item becomes a link to its issue.

Only the repo goes to the model, and the model runs on your device. Issues carry the words of the items you send and nothing else.

Works on: Android, iPhone and Mac. The briefing needs a device that runs a model, so not the iPhone. Held off by Local only.

## Notion

Turns list items into tasks on your Notion boards.

1. In **Settings › Notion**, sign in and pick the boards Ghost.md may see. Signing in goes through ghostmarkdown.com to finish the handshake with Notion; your notes never do.
2. In a note, tap **More for this note** and choose **Notion board**.
3. Swipe a list item left, or tap the quiet "Notion" after it, to send it. **Send list to Notion** sends the lot.

A sent item becomes a link to its task. To give Ghost.md more boards later, sign in again and pick them.

Works on: Android and Mac. Not on the iPhone yet. Held off by Local only.

## Slack

Posts a note, or a meeting's summary, to a Slack channel when you say so.

1. In Slack, add an incoming webhook to the channel and copy its URL.
2. In **Settings › Slack › Add a channel**, give it a name, paste the webhook and tap **Keep it**.
3. In a note's More sheet, choose **Post to Slack**. A meeting has **Post the summary to Slack**.

Two things can post by themselves, only if you set them up: a meeting's action items and links, to the channel chosen under **Settings › Meetings › Post to Slack**, and an organization's news, to the channel set for it under **Organizations' news**.

What you post leaves Ghost.md's encryption: Slack, and everyone in the channel, can read it.

Works on: Android and Mac. Not on the iPhone yet. Held off by Local only.

## Webhooks

For Zapier, Make, IFTTT or a line of `curl`.

- **Outgoing webhooks**: a URL of yours is told when a note you change on this device is made, edited, or has a to-do ticked. It gets JSON with the note's words and the lines that changed, at most once every 10 seconds a note. Pick which events and which notes, and use **Test** to try it.
- **Incoming webhooks**: a URL on ghostmarkdown.com that adds to a note. Post JSON with `note`, `text` and `as` (`task`, `item`, `paragraph` or `note`), or plain text, which goes to the hook's own note. What arrives is sealed to your account at once, and your devices pick it up on their next sync. These need an account.

Set both up in **Settings › Webhooks**.

Works on: Android, iPhone and Mac. Held off by Local only.

## Marks

Ghost.md's own formatting on top of Markdown, typed or said: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout and an addition, plus five effects: heat, frost, a wave, a shimmer and a haunting. For example, `||a secret||` blurs until you put the caret in it.

It has no settings and asks for nothing. Remove it and the marks are plain text.

Works on: Android, iPhone and Mac. See [[Markdown and the Ghost.md marks]].

## Rich embeds

A YouTube, Spotify or Figma link alone on its line becomes a card that plays the video or song, or shows the Figma file.

There is nothing to set. The card's title and picture are asked of the service only while **Link previews** is on (Settings › Account › Privacy), and it plays only when you tap. Remove the plugin and such a link is an ordinary link card.

Works on: Android, iPhone and Mac. Held off by Local only.

See also: [[The Market]] · [[Lovart]] · [[Claude in Ghost.md]] · [[Settings]] · [[Privacy]]
