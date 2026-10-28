# Meetings and the Meet bot
Ghost.md can sit in on your meetings. Record one on your phone or Mac, or send Ghost into a Google Meet, a Zoom call or a Discord voice channel and it joins by itself. Whichever way, you get a note with the transcript, who said what, and a summary of what was decided and who does what next.

**Works on:** recording a meeting yourself, and the Google Meet, Zoom and Discord pages, on Android and the Mac. A meeting Ghost was in still reaches your iPhone as a note.

## Recording a meeting yourself

1. Tap **+** and choose **Meeting**. In Simple, it's behind **More…**.
2. Talk. On Android, the screen can go off and you can leave the app: stop from the meeting screen or from the notification.
3. Tap **Done** when it's over. **Discard** throws the recording away.

On a Mac, switch on **Record the computer's sound too** on the + sheet before you start, and both sides of a call are recorded: what the Mac plays goes in with the microphone. macOS asks the first time.

On Android, **Include sound from other apps** adds what other apps play, such as a video. Android never lets an app hear calls, so a call in another app is heard only through the microphone. Android asks to share your screen each time; only the sound is kept.

You can also switch a voice note to a meeting before you've said anything, with **Meeting instead** on the recording screen.

A meeting is named for when it started, such as `Meeting, 18 Oct 14:00`. When its summary comes, a better title takes the place of the date, unless you've renamed it already. Rename it by changing its first line.

Spoken cues and commands aren't read in a meeting. Everything said is kept as said.

## Ghost in your calls

Ghost can also join a call without you recording anything. It's three plugins, one for each service:

| Plugin | How Ghost is sent in | On at first |
|---|---|---|
| **Google Meet** | Your Ghost address on a calendar invite, or a pasted link | Yes |
| **Zoom** | Your Ghost address on a calendar invite, or a pasted link | Yes |
| **Discord** | `/ghost join` in a voice channel | No |

Each has its own page in Settings: **Settings › Google Meet**, **Settings › Zoom** and **Settings › Discord**. Switch a plugin on or off in the Market. See [[The Market]].

You need a Ghost.md account, signed in. The Google Meet and Zoom pages are kept in Simple; Discord, like every other plugin, is part of Advanced.

With a plugin off, Ghost joins nothing of that kind. An invite for it books nothing, and the invite's note ends "Ghost wasn't booked: the Zoom plugin is off. Turn it on in Ghost.md to have Ghost join." Meetings already booked of that kind are skipped, and booked again if you turn the plugin back on while they're still to come. Meetings already recorded stay, as notes.

## Google Meet

### Your Ghost address

Ghost is invited through your own address, such as `you@in.ghostmarkdown.com`. It's the same address as **Email to a note**, and it works for Meet and Zoom invites alike. If you don't have one yet, the page says "Ghost is invited by your Email to a note address. Turn one on in Settings › Account, then invite Ghost here", with **Account** to take you there. See [[Email to a note]].

On the **Invite Ghost** card, beside your address:

- **Copy** copies it.
- **Choose a name…** gives it a name of your own.
- The refresh button, **Make a new address**, swaps it for a new one. It asks first: **Make a new address?**, then **Make it**. The old one stops taking invites and mail, so a calendar invite with the old address on it needs the new one.

A change here is a change on the Zoom page too: it's one address.

### Sending Ghost into a Meet

- **From your calendar.** Add your Ghost address as a guest on a Google Calendar invite with a Meet link. Ghost joins by itself when the meeting starts. The invite mail becomes a note in your Inbox too.
- **Right now.** Paste a Meet link, such as `meet.google.com/abc-defg-hij`, into **Invite Ghost** and tap **Join**. "Ghost is on its way into the meeting."

A Zoom link pasted here is turned away: "That is a Zoom link. Send it from the Zoom plugin's page."

Ghost joins from its own Google account. Unless the meeting lets anyone with the link straight in, someone in the call has to admit it, within ten minutes. When it arrives it posts a line in the meeting's chat: "Ghost.md is taking notes for this meeting. The recording goes to the person who invited it, sealed to their account." It turns Meet's captions on, which is how it knows who's speaking.

### Recurring meetings

Invite Ghost to a meeting that repeats, such as a daily standup, and it joins every time it comes round. No new invite is needed.

Under **Recurring**, each series shows how it repeats, such as "Every weekday at 9:30", and when it's next, such as "Next: Mon 27 Oct". If the invite is in another time zone, the zone is named. To skip just one, use **Don't join** on that meeting's row. To stop for good, tap **Stop joining**; it asks first, and says "Past recordings stay."

### Your Meet meetings

**Ghost in Google Meet** lists every Meet that Ghost is booked for or has been to: those coming up first, then by day, newest first. Each says where it stands: **Booked**, **Joining**, **In the meeting**, **Leaving**, **Being written up**, **Written up**, or why Ghost couldn't join, such as "Couldn't join: nobody let Ghost in".

- **Don't join** skips a meeting to come. **Leave now** calls Ghost out of one it's in.
- Tap a meeting to open its note.
- **Show more** loads older meetings. Meetings are listed here for 30 days after they end; their notes stay for good.
- **Check for new meetings**, with **Check now**, looks again straight away. The page checks by itself every minute while it's open.

The page's row in Settings says how many meetings Ghost is booked for.

### When Ghost leaves

These rules are the same for Meet, Zoom and Discord. Ghost leaves when:

- the call ends, or you tap **Leave now**;
- it has been alone for two minutes (if nobody has come at all, it waits ten minutes past the start first);
- the call had five or more people and is down to Ghost and one other, for two minutes;
- it has been there three hours.

A meeting that runs over its booked end is stayed in for as long as it goes on.

Ghost is in one meeting at a time. If it's still in another meeting more than ten minutes after yours starts, yours says "Couldn't join: Ghost was in another meeting". You can have up to 100 meetings booked and still to come.

## Zoom

### Sending Ghost into a Zoom

The Zoom page works like the Google Meet page: the same **Invite Ghost** card and address, **Recurring**, and **Ghost in Zoom** with your Zoom calls.

- **From your calendar.** Add your Ghost address as a guest on an invite with a Zoom link, from Zoom or from Google Calendar. A Zoom link put in the event's location wins over a Meet link that Calendar added by itself.
- **Right now.** Paste a Zoom link into **Invite Ghost** and tap **Join**.

Ghost takes meeting links such as `zoom.us/j/83512345678?pwd=…` (any `…zoom.us` name in front), Zoom's web links (`zoom.us/wc/join/…`) and personal links (`zoom.us/my/sam.lee`). It doesn't take webinar links, or a host's start link. Keep the passcode in the link: Ghost has no way to type one.

Ghost joins as a guest named **Ghost (notetaker)**, from its browser, never signed in to Zoom. It joins the meeting's sound, stays muted with its camera off, posts the same line in the chat, and turns on captions where the host lets participants see them.

### What the host must allow

Whether Ghost gets in is up to the Zoom host's settings. The Zoom page lists them under **What the host must allow**:

- **Guests:** "Only authenticated users can join" turned off, or Ghost meets a sign-in wall.
- **Joining from the browser:** "Show a Join from your browser link" turned on. An admin may lock it.
- **The passcode in the link:** "Embed passcode in invite link", Zoom's default. Without it Ghost has no passcode to type.
- **The waiting room:** someone lets Ghost (notetaker) in within 10 minutes.
- **Captions:** automated captions on and shown to participants, so the note says who said what. Without them, Ghost records the sound alone.

If the meeting's chat is closed, Ghost just doesn't post its line.

### Zoom's limits

When Ghost can't get in, its row says why, such as "Couldn't join: the host turned off joining from a browser", "the meeting lets in signed-in Zoom users only", "the link had no passcode in it" or "the passcode was wrong".

Zoom watches for automated visitors, and may ask a guest to prove it's a person. Ghost never answers such a check: the meeting fails with "Zoom asked Ghost to prove it is a person". Zoom changes its web page from time to time; when Ghost can't get in, the meeting's row says why.

Without captions, a Zoom's transcript has the words but not the names.

## Discord calls

The Discord plugin can post notes to a channel, and it can bring Ghost into a voice channel to record the call. It's off to begin with: add **Discord** in the Market, then open **Settings › Discord**. Its **Discord calls** card is first on the page.

### Linking Discord

Ghost needs to know which Discord account is yours. You do this once.

1. On **Settings › Discord**, tap **Link Discord**. You get a code, such as `K7QM-2XRP`. It works once, for ten minutes.
2. **Add Ghost to your Discord server**, once for each server, by someone who may manage it. **Add Ghost** opens Discord's page for it. Ghost asks to see channels, send messages and connect to voice.
3. In any channel of that server, type `/ghost link` and your code. **Copy** copies the whole command. The page shows "Linked as" and your Discord name when it has worked.

To add Ghost to another server later, use **Add Ghost to a server** on the same card.

A Discord account links to one Ghost.md account, and a Ghost.md account to one Discord account: linking again moves the link. **Unlink** asks first; calls already recorded stay.

### Recording a call

1. Join a voice channel in a server Ghost has been added to.
2. Run `/ghost join`. Ghost joins, muted, and posts in the channel's chat that it's taking notes, and for whom.
3. Talk. Anyone who joins later is told by name that the call is being recorded.
4. Run `/ghost leave` when you're done, or let Ghost leave by itself, by the rules under **When Ghost leaves**, above. A line in the chat says why it left.

Anyone in the call can stop Ghost with `/ghost leave`, not only the person who asked. Ghost never pings anyone: names in its messages are plain text.

**Join Discord calls**, on the card once you're linked, is on to begin with. Off, `/ghost join` answers that it's switched off and where to turn it on. Taking the Discord plugin out in the Market turns it off too, and you turn it back on by hand.

### Your Discord calls

**Your Discord calls** lists the calls Ghost recorded for you, each named for its channel and server, such as "General in Ghost HQ", with where it stands. **Leave now** calls Ghost out of one going on, and a call that's written up opens its note. Calls are kept in the list for 30 days after they end.

Discord has no captions. Ghost hears each person on their own, so it knows who spoke when, and the transcript names each speaker by their server nickname.

### Discord's limits

- One call a server at a time, and voice channels only: not Stage channels.
- Three hours at most, as for any meeting.
- Names are Discord's at the moment of the call. Two people with the same nickname read as one speaker.
- A word or two can be lost when someone joins or leaves, while Discord changes the call's encryption keys.
- If nobody was heard at all, the call says "Couldn't join: Ghost heard nobody in the call".
- The recording leaves Discord's own encryption: Ghost is a participant, as a person recording on their phone would be. It's sealed to your account as it reaches Ghost.md's server.

## What you get

When a meeting ends, Ghost.md writes it up **on your device**:

- **The transcript,** under `## Transcript`. From Google Meet, Zoom with captions, and Discord, each part says who was speaking, with when: `**Sam Lee (0:04):**`. A meeting you recorded yourself names nobody.
- **A summary** under the title, under `## Summary`: one line on what it was about, what was decided, and the to-dos as to-dos.
- **The tape** at the top of the note, to play it back. See [[Tapes and transcripts]].

Until it's written up, a meeting Ghost was in says "It is being written up on your device", with the captions in the meantime.

### Who writes the summary

The summary is written by the AI model on your phone or Mac. If the Claude plugin is on with your own key, Claude writes meeting summaries instead, with your key, straight to Anthropic. See [[Claude in Ghost.md]].

Choose what gets a summary in Settings › Recording, under **Summaries**: **Meetings**, **Meetings and long voice notes**, or **Off**.

On Android, a meeting is written up when the phone is charging or has more than half its battery, unless you switch on **Write up straight away**. **Tell me when a meeting is written up** sends a notification, with the first line of the summary.

### Written up on another device

If the device that got the meeting can't write a summary, because it has no summary model and no Claude, it hands the meeting on. Another of your Android phones or Macs that can write it picks it up, writes the summary, and the note syncs back. Only one device writes it.

Meanwhile the meeting's row and its tape say where it stands, such as "Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone", or "Being summarized on your phone."

## Where meetings go

Every meeting goes to the same place, whichever plugin it came from or if you recorded it yourself. That's set once, on the **Meetings** card in **Settings › Recording**. Each meeting plugin's page has a **Where meetings go** row, saying **Workspaces** or **Inbox**, that takes you there.

On the Meetings card:

- This device's own meeting settings first: **Include sound from other apps**, **Tell me when a meeting is written up** and **Write up straight away** on Android, **Record the computer's sound too** on a Mac.
- **Sync meeting recordings** (on to begin with): a meeting's audio goes to your other devices, and with a team's note to everyone in the team. Off, the words sync and the audio stays on the device it was made on. The card says how many recordings stayed on this device.
- **Sort meetings into workspaces** (on to begin with): once a meeting is written up, the AI files it in the **Meetings** folder of the workspace it's about, making the folder if it's missing. It only moves a meeting when it's sure, and only once. A meeting you've filed yourself stays where you put it. Off, meetings stay in your Inbox.

Filing a meeting in an organization's workspace shares it with everyone in it. See [[Organizations and shared notes]].

In Simple, Settings › Recording shows the Meetings card first, and the rest of the page behind **More**.

## Action items to Slack or Discord

Once a meeting is written up, its action items can go to a chat channel by themselves. In Slack the post is the action items first, with who they're for and when they're due, then a brief summary with the decisions when there are only a few, then the public link to the meeting's notes (a link that opens it in Ghost.md when there's no share link). In Discord it's the same items and decisions, with a link that opens the meeting in Ghost.md and a share link to its notes.

1. Add the Slack or Discord plugin in the Market, and add a channel on its page. See [[Plugins, one by one]].
2. On the plugin's page, under **Post to Slack** or **Post to Discord**, switch on **Post meetings to Slack** (or **Post meetings to Discord**).
3. Under **Channel**, choose where they go. With one channel, it's chosen for you.
4. **Include a share link** is on to begin with. Anyone with the link can read the meeting's notes and its whole transcript, a team's meeting too, and it follows the note's edits. Stop it from the note's **Share**.

Each meeting is posted once, from the device that writes it up. One that couldn't post shows on the page as **Not posted**, with Discord's or Slack's reason: **Try now**, or **Don't post** to let it go. It's tried again by itself the next time Ghost.md opens, up to five times.

On Discord, the link that opens Ghost.md is shown as text to copy, since Discord only links web addresses.

**Works on:** Android and the Mac. Not on the iPhone.

## On every device

A meeting's note syncs like any note. With **Sync meeting recordings** on, the recording goes to your other devices too. A meeting filed in a team's workspace goes to everyone in the team.

Meetings Ghost recorded reach your devices as soon as Ghost leaves the call, if Ghost.md is open on one of them. On the iPhone, which can't keep the sound yet, a meeting Ghost was in is filed from the captions after a day, if no other device has filed it first.

## The Meetings shelf

In Advanced, your home page has a shelf of **Meetings**: a cassette for each recorded meeting, from every plugin and your own, newest first, with its length and date. One being recorded says **Recording now**.

- **Tap a cassette** to open its note at the tape, playing.
- **On a Mac,** rest the pointer on a cassette to hear it.
- **See all** shows every note with a tape, once there are more than the shelf holds.

## Private by design

A meeting's sound passes through Ghost.md's server while Ghost records it, sealed to your account as it arrives. The server can't open it. It's written up on your device, never on the server.

To join a call, the server keeps the link, the title and the times in the clear, until an hour after the meeting ends. The organizer and the guest list are read and dropped.

Remember that a meeting is other people's voices. Let them know Ghost is there.

See also: [[Tapes and transcripts]], [[Speaking your notes]], [[Email to a note]], [[Claude in Ghost.md]], [[Plugins, one by one]], [[Workspaces, folders and search]], [[Organizations and shared notes]]
