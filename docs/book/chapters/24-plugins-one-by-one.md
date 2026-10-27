# Plugins, one by one

Ghost.md ships with sixteen plugins. Each is built in: you add it in the Market, and its settings, if it has any, get a page of their own in Settings. This chapter takes them in turn, in the Market's order: what each does, how to set it up, where it works and what it needs from you.

Plugins that use the internet are held off while **Local only** is on. Each section says whether that applies.

## At a glance

| Plugin | Category | On from the start | Works on | You bring |
|---|---|---|---|---|
| Claude | AI | Yes | Android, iPhone, Mac | An Anthropic API key, for the app's half |
| Lovart | AI | No | Android, iPhone, Mac | A Lovart access key and secret key |
| Calendar | Calendar & tasks | No | Android, iPhone, Mac | An iCal address, or a Google sign-in |
| Contacts | Calendar & tasks | No | Android, iPhone, Mac | Permission to read your contacts |
| Place reminders | Calendar & tasks | No | Android only | Permission to know your location all the time |
| Things | Import | No | Android, Mac | Things 3's data, or a list it copied |
| Todoist | Import | No | Android, Mac | A Todoist API token or a CSV export |
| Discord | Connections | No | Android, Mac | A Discord webhook per channel; a Ghost.md account for calls |
| GitHub | Connections | Yes | Android, iPhone, Mac | A GitHub token, to make issues |
| Google Meet | Connections | Yes | Android, Mac | A Ghost.md account with Email to a note |
| Notion | Connections | Yes | Android, Mac | A Notion sign-in |
| Slack | Connections | No | Android, Mac | A Slack incoming webhook per channel |
| Webhooks | Connections | No | Android, iPhone, Mac | A URL of yours; an account for incoming hooks |
| Zoom | Connections | Yes | Android, Mac | A Ghost.md account with Email to a note |
| Marks | Editor | Yes | Android, iPhone, Mac | Nothing |
| Rich embeds | Editor | Yes | Android, iPhone, Mac | Nothing |

"Works on" is where you set the plugin up and use it. What it makes, such as a meeting's note or a picture, syncs to all your devices like any other note.

## Claude

Claude on your notes, both ways.

**In the app**, Claude answers with your own Anthropic API key. It sits on the dock at the head of every page and as **Ask Claude** in the command palette. Ask in the chat and Claude writes into the note as you watch. A to-do written in your "Ask Claude" note can be done for you a few seconds after you stop typing it.

**From Claude's own app** (claude.ai, Claude Desktop or Claude Code), Claude reaches your notes through Ghost.md's connector. Nothing about that half runs inside the app.

To set it up, open **Settings › Claude**. Under **In the app**:

- **Ask Claude**: paste your key (it starts `sk-ant-`) under **API key** and tap **Keep it**. It is checked before it is kept. Once kept, **Check** asks again, and **Forget the key** removes it.
- **Model**: Sonnet 5.5, Opus 5.5 or Haiku 5.5. Each is billed to your key at its own price.
- **Spending limit**: an optional monthly limit in US dollars ($5, $10, $25, $50 or **Another amount**), with **Warn me at 80%** and **Reset count**. The count is this device's.
- **Ask Claude note**: **Do requests as they are written**.
- **Phone assistant** (Android): make Ghost.md your phone's assistant, so holding the side key talks to Claude.

Under **From Claude's own app**, **Connect** has **How to connect**, the **Server address** with Copy, and **On your own computer**.

The key, the model and these switches follow your account, sealed, while **Keep keys and connections in sync** is on in Settings › Account.

Removing the plugin takes Claude off the dock and out of the palette. It does not disconnect Claude's own app: do that in Claude.

Works on: Android, iPhone and Mac. Held off by Local only. More in [[Claude in Ghost.md]].

## Lovart

Images from your notes, made by Lovart's design agent. Write `{image: a prompt}` where a picture should go, ask any note for a moodboard of four, give notes a header image in the ghost's dotwork, or let design meetings come back with inspiration.

It is off until you add it, because it sends words to Lovart and spends your Lovart credits. You bring your own Lovart keys, kept in **Settings › Lovart**. Once it is added, **Header images for notes** is on until you switch it off.

Works on: Android, iPhone and Mac. Held off by Local only. The whole story is in [[Lovart]].

## Calendar

Your calendars' events in queries and on the home page's **Today**.

Set it up in **Settings › Calendar**:

- **Calendar addresses**: paste the iCal address of any calendar. Nothing to sign in to. **Remove** takes one away.
- **Google Calendar**: tap **Connect**, allow Ghost.md in your browser, then tick the calendars to read. They are read every 15 minutes, and **Read now** reads them at once. **Disconnect** signs out. The sign-in passes through ghostmarkdown.com; your notes never do.
- **To-dos on the calendar**: every open to-do with a due date becomes an all-day event on the Google calendar you pick, linked back to its note. A new date moves it; ticked or removed, it goes. Events Ghost.md did not make are never changed.

Query events with `from: events`:

````markdown
```query
from: events
where: start >= today
show: calendar
```
````

The events are kept on the device. The addresses are treated as secrets and travel sealed with your settings. Remove the plugin and nothing is read; add it back and your calendars are still chosen.

Works on: Android, iPhone and Mac. Held off by Local only: the page says no calendar is read until it is off.

## Contacts

Matches the people named on your to-dos with your phone's contacts. Write `@sam` on a to-do: once Sam is matched, the chip shows their picture, and a tap offers call, text or email. **A person**, on the + beside a line, picks someone from your contacts.

Add it, then tap **Turn on** in **Settings › Contacts** and allow your phone to share its contacts. If you said no before, **Open settings** takes you to the phone's own switch. **People in your notes** lists each name and the contact it matched: **Choose** another, match **By name**, or **Unlink**. Your choices are kept on this device.

Nothing about a contact leaves the device or goes into a note, except the name you pick.

Works on: Android, iPhone and Mac. Not affected by Local only.

## Place reminders

A to-do with a place reminds you when your phone arrives there.

Press and hold a to-do and choose **Remind me at a place**. Search for a place, pick one the note already has, or use where you are. Within about 150 metres of it, the to-do reminds you, with **Done** to tick it, even with Ghost.md closed. The place is written on the to-do as a pin and a link, `📍 [Target](geo:…)`, so other apps can read it.

Android must let Ghost.md know where your phone is all the time. **Settings › Place reminders** says whether it does, and how to allow it. Where you are stays on the phone.

Works on: Android only. On other devices a place on a to-do is shown and kept, and your phone does the reminding. A place searched by name is looked up on OpenStreetMap, which Local only turns off; the reminders themselves keep working.

## Things

Brings Things 3 in: its areas become notebooks and its projects their pages, with headings, to-dos, When dates, deadlines, tags, notes and checklists, in a workspace of the import's own. Nothing you already have is changed.

Add it, then open **Settings › Things** (or **Settings › Export › Import**) and find **Things 3**:

- **From Things on this Mac** reads a copy of Things' own data, every area and project. The Mac may ask you first. Tick **The Logbook too** to bring done and cancelled to-dos, ticked. Mac only.
- **Paste from Things**: in Things, open a list and choose Share › Copy, then press it. The list becomes one note.

Works on: Android and Mac. Nothing leaves the device, so Local only does not hold it off.

## Todoist

Brings your Todoist projects in as notes: their sections become headings and their tasks to-dos, with dates, priorities, labels and sub-tasks, in a workspace of the import's own.

Add it, then open **Settings › Todoist** (or **Settings › Export › Import**) and find **Todoist**. Either:

- Paste an API token, from Todoist › Settings › Integrations › Developer, and tap **Import from Todoist**. The token is used for this one import and not kept. Switch on **Completed tasks too** to bring those done in the last year, ticked.
- Or choose **Todoist CSV export (.csv)** and pick one or more projects' exports (in Todoist, a project's menu › Manage data › Export as CSV). They are read on the device, and each becomes a note. An export has no completed tasks.

Works on: Android and Mac. Held off by Local only.

## Discord

Two things in one plugin: posting notes to Discord channels, and Ghost taking notes in your Discord voice calls. It is off until you add it.

### Posting to a channel

1. In Discord, open the channel's settings: **Integrations › Webhooks › New Webhook**, then **Copy Webhook URL**. You need Manage Webhooks on the server.
2. In **Settings › Discord**, under **Add a channel**, give it a name (such as `#launch`), paste the webhook URL and tap **Add it**.
3. In a note's More sheet, choose **Post to Discord**. A meeting's note also has **Post the summary to Discord**, which sends the summary and nothing else of the note. With more than one channel, you choose which.

A Discord message holds 2,000 characters. A longer note is cut at a line, with a share link to the rest where you are signed in, and the row says so before you press it. Anyone with that link can read the whole note. Signed out, the message says the rest is in Ghost.md. Nobody is pinged by a post, @everyone included.

Each channel under **Channels** has **Test**, which sends a test message, **Rename** and **Forget**. The channels and their webhooks follow your account, sealed, while **Keep keys and connections in sync** is on.

**Post to Discord**, on the same page once a channel is added, sends each meeting's action items and links by itself once it is written up. Switch on **Post meetings to Discord**, pick the **Channel**, and choose whether to **Include a share link**. Each meeting is posted once, from the device that writes it up. A meeting that couldn't be posted is listed, with a way to try again or **Don't post**.

What you post leaves Ghost.md's encryption: Discord, and everyone in the channel, can read it.

### Discord calls

Ghost can join a Discord voice channel when you ask it there, record the call, and file it as a note written up with who said what. You need a Ghost.md account.

1. In **Settings › Discord**, under **Discord calls**, tap **Link Discord**. A code appears. It works once, for ten minutes.
2. **Add Ghost to your Discord server** with **Add Ghost**. Someone who can manage the server does this once for each server. Ghost asks to see channels, send messages and connect to voice.
3. In any channel of that server, type `/ghost link` and your code (**Copy** copies the whole command). The page shows your Discord name once it has worked: **Linked as** your name.

Then, to have Ghost take notes:

- Join a voice channel and run `/ghost join`. Ghost says in the channel's chat that it is taking notes, and who for.
- Anyone in the call can stop it with `/ghost leave`. It also leaves once everyone else has, and after three hours.
- **Join Discord calls** is the switch: off, Ghost answers `/ghost join` by saying it is switched off.
- **Your Discord calls** lists the calls, with **Leave now** on one going on. A written-up call opens its note.
- **Unlink** stops Ghost joining for that Discord account. Calls already recorded stay.

A call is filed, written up and sorted like every meeting: see **Where meetings go**, and [[Meetings and the Meet bot]]. The sound passes through Ghost.md's server sealed to your account; it is written up on your device.

Works on: Android and Mac. Not on the iPhone yet, where the call notes still arrive. Held off by Local only.

## GitHub

Links a note to a repo. Its list items can become issues you tick off from either side, and the repo is read into a short briefing, so names and terms come out right when the note is formatted.

1. Open a note, tap **More for this note**, and choose **GitHub repo**.
2. Pick or type the repo. Public repos are read without a token.
3. To send items as issues, or to read a private repo, paste a token in **Settings › GitHub › Token** and tap **Keep it**.

Then swipe a list item left, or tap the quiet "GitHub" after it, to make it an issue. **Send list to GitHub**, in the note's More sheet, sends every item not sent yet. Each item becomes a link to its issue. **Repos**, on the same page, lists the repos read so far, each with **Forget**.

Only the repo goes to the model, and the model runs on your device. Issues carry the words of the items you send and nothing else. The token follows your account, sealed, while **Keep keys and connections in sync** is on.

Works on: Android, iPhone and Mac. The briefing needs a device that runs a model, so not the iPhone. Held off by Local only.

## Google Meet

Ghost joins your Google Meet meetings, records them, and files each as a note, written up with who said what. It is on from the start for an account that has Ghost in meetings.

Its page is **Settings › Google Meet**:

- **Invite Ghost**: paste a Meet link and tap **Join** to send Ghost in now. Or add your address, shown here with **Copy**, as a guest on a calendar invite with a Meet link, and Ghost joins by itself. **Choose a name…** picks an address of your own, and the last button makes a new one. The same address works for Meet and Zoom invites, so a change here is Zoom's too.
- **Recurring**: the series Ghost joins every time, with **Stop joining**.
- **Ghost in Google Meet**: the meetings it is booked for and was in. **Don't join** on one to come, **Leave now** on one going on, and **Check now** for new invites.
- **Where meetings go**: Workspaces or Inbox, set once for every meeting on **Settings › Recording**'s **Meetings** card.

Ghost is invited by your Email to a note address. Without one, the page says to turn one on in Settings › Account.

Turn the plugin off and an invite for a Meet books nothing: the mail's note says Ghost wasn't booked because the plugin is off. The switch follows your account to your other devices. The page stays in Simple mode.

Works on: Android and Mac. Not on the iPhone yet, where the meeting notes still arrive. Held off by Local only. More in [[Meetings and the Meet bot]].

## Notion

Turns list items into tasks on your Notion boards.

1. In **Settings › Notion**, sign in and pick the boards Ghost.md may see. Signing in goes through ghostmarkdown.com to finish the handshake with Notion; your notes never do.
2. In a note, tap **More for this note** and choose **Notion board**.
3. Swipe a list item left, or tap the quiet "Notion" after it, to send it. **Send list to Notion** sends the lot.

A sent item becomes a link to its task. To give Ghost.md more boards later, sign in again and pick them. **Sign out** is on the same page.

Notion's sign-in stays on each device: sign in on each one you use.

Works on: Android and Mac. Not on the iPhone yet. Held off by Local only.

## Slack

Posts a note, or a meeting's summary, to a Slack channel when you say so.

1. In Slack, add an incoming webhook to the channel and copy its URL.
2. In **Settings › Slack**, under **Add a channel**, give it a name, paste the webhook and tap **Add it**.
3. In a note's More sheet, choose **Post to Slack**. A meeting has **Post the summary to Slack**. With more than one channel, you choose which.

Each channel under **Channels** has **Test**, **Rename** and **Forget**.

Two things can post by themselves, only if you set them up on the same page:

- **Post to Slack**: switch on **Post meetings to Slack**, pick the **Channel**, and choose whether to **Include a share link**. Each meeting's action items and links go there once, from the device that writes it up. A meeting that couldn't be posted is listed with a way to try again.
- **Organizations' news**: who joined, left or changed role in an organization, and its new name, to the channel you pick for it. This is set on one device only, since every device with a channel set posts the news.

The channels and Post to Slack follow your account, sealed, while **Keep keys and connections in sync** is on.

What you post leaves Ghost.md's encryption: Slack, and everyone in the channel, can read it.

Works on: Android and Mac. Not on the iPhone yet. Held off by Local only.

## Webhooks

For an automation service, or a line of `curl`.

- **Outgoing webhooks**: a URL of yours is told when a note you change on this device is made, edited, or has a to-do ticked. It gets JSON with the note's words and the lines that changed, at most once every 10 seconds a note. Pick which events, and which notes: a workspace's or a notebook's pages. **Test** tries it.
- **Incoming webhooks**: a URL on ghostmarkdown.com that adds to a note. Post JSON with `note`, `text` and `as` (`task`, `item`, `paragraph` or `note`), or plain text, which goes to the hook's own note. What arrives is sealed to your account at once, and your devices pick it up on their next sync. These need an account. **Examples** on the page shows a request to copy.

Set both up in **Settings › Webhooks**.

Works on: Android, iPhone and Mac. Held off by Local only.

## Zoom

Ghost joins your Zoom calls as a guest from its browser, records them, and files each as a note, written up with who said what. It is on from the start for an account that has Ghost in meetings.

Its page, **Settings › Zoom**, has the same cards as Google Meet's, for Zoom links: **Invite Ghost** with **Join** and your address, **Recurring**, **Ghost in Zoom**, and **Where meetings go**. It adds **What the host must allow**, since Ghost is never signed in to Zoom and the host's settings decide whether it gets in:

| Setting | What it needs |
|---|---|
| Guests | Only authenticated users can join turned off |
| Joining from the browser | Show a Join from your browser link turned on |
| The passcode in the link | Embed passcode in invite link, Zoom's default |
| The waiting room | Someone lets Ghost (notetaker) in within 10 minutes |
| Captions | Automated captions on and shown, so the note says who said what |

Without captions the note has the sound only, with no names. Turn the plugin off and a Zoom invite books nothing. The page stays in Simple mode.

Works on: Android and Mac. Not on the iPhone yet, where the meeting notes still arrive. Held off by Local only. More in [[Meetings and the Meet bot]].

## Marks

Ghost.md's own formatting on top of Markdown, typed or said: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout and an addition, plus five effects: heat, frost, a wave, a shimmer and a haunting. For example, `||a secret||` blurs until you put the caret in it.

It has no settings and asks for nothing. Remove it and the marks are plain text.

Works on: Android, iPhone and Mac. Not affected by Local only. See [[Markdown and the Ghost.md marks]].

## Rich embeds

A YouTube, Spotify or Figma link alone on its line becomes a card that plays the video or song, or shows the Figma file.

There is nothing to set. The card's title and picture are asked of the service only while **Link previews** is on (Settings › Account › Privacy), and it plays only when you tap. Nothing of your notes goes but the link. Remove the plugin and such a link is an ordinary link card.

Works on: Android, iPhone and Mac. Held off by Local only.

See also: [[The Market]] · [[Lovart]] · [[Claude in Ghost.md]] · [[Settings]] · [[Privacy]]
