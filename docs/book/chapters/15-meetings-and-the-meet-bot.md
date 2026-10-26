# Meetings and the Meet bot
Ghost.md can sit in on your meetings. Record one on your phone or Mac, or invite Ghost to a Google Meet call and it joins by itself. Either way you get a note with the transcript, and a summary of what was decided and who does what next.

## Recording a meeting yourself

1. Tap **+** and choose **Meeting**. In Simple, it's behind **More…**.
2. Talk. On Android, the screen can go off and you can leave the app: stop from the meeting screen or from the notification.
3. Tap **Done** when it's over.

To catch the other side of a call, switch on **Include sound from other apps** on Android, or **Record the computer's sound too** on the Mac, on the + sheet before you start.

You can also switch a voice note to a meeting before you've said anything, with **Meeting instead** on the recording screen.

A meeting is named for when it started, such as `Meeting, 18 Oct 14:00`. Rename it by changing its first line.

Spoken cues and commands aren't read in a meeting. Everything said is kept as said.

**Works on:** Android and the Mac. Not on the iPhone.

## Inviting Ghost to a Google Meet

Ghost can join a Google Meet call on its own, record it, and file it as a note. You need a Ghost.md account. Everything about it is in Settings › **Meetings**.

### Your Ghost address

Ghost is invited through your own address, such as `you@in.ghostmarkdown.com`. If you don't have one yet, Settings › Meetings says so and offers to turn on **Email to a note**. Mail sent to the address becomes a note in your Inbox too.

- **Copy** copies your address.
- **Choose a name…** gives it a name of your own.
- The refresh button, **Make a new address**, swaps it for a new one. The old one stops taking invites and mail.

### Two ways to send Ghost in

- **From your calendar.** Add your Ghost address as a guest on a Google Calendar invite with a Meet link. Ghost joins by itself when the meeting starts.
- **Right now.** Paste a Meet link, such as `meet.google.com/abc-defg-hij`, into **Invite Ghost** and tap **Join**. "Ghost is on its way into the meeting."

Ghost joins from its own Google account, so someone in the call has to let it in. When it arrives, it posts a line in the meeting's chat to say it's taking notes. It leaves when the call ends, or when it's left alone.

### Recurring meetings

Invite Ghost to a meeting that repeats, such as a daily standup, and it joins every time it comes round. No new invite is needed.

Under **Recurring**, each series shows how it repeats, such as "Every weekday at 9:30", and when it's next. To skip just one, use **Don't join** on that meeting's row. To stop for good, tap **Stop joining**. Past recordings stay.

### Your meetings, past and to come

**Ghost in meetings** lists every meeting Ghost is booked for or has been to: **Coming up** first, then by day, newest first. Each says where it stands: Booked, Joining, In the meeting, Leaving, Written up, or why Ghost couldn't join, such as when nobody let it in.

- **Don't join** skips a meeting to come. **Leave now** calls Ghost out of one it's in.
- Tap a meeting to open its note.
- **Show more** loads older meetings. Meetings are listed here for 30 days after they end; their notes stay for good.
- **Check for new meetings** looks again straight away.

## What you get

When a meeting ends, Ghost.md writes it up **on your device**:

- **The transcript,** under `## Transcript`. From Google Meet, each part says who was speaking, with the names from Meet's captions.
- **A summary** under the title: what was decided, with the to-dos as to-dos.
- **The tape** at the top of the note, to play it back. See [[Tapes and transcripts]].

Until it's written up, a Meet note says "It is being written up on your device", with Meet's captions in the meantime.

### Who writes the summary

The summary is written by the AI model on your phone or Mac. If you've set up Claude with your own key, Claude writes meeting summaries instead. See [[Claude in Ghost.md]].

Choose what gets a summary in Settings › Recording, under **Summaries**: **Meetings**, **Meetings and long voice notes**, or **Off**.

On Android, a meeting is written up when the phone is charging or has more than half its battery, unless you switch on **Write up straight away**. **Tell me when a meeting is written up** sends a notification when it's ready.

## Filed where it belongs

With **Sort meetings into workspaces** on, in Settings › Meetings, the AI reads each meeting once it's written up and files it in the **Meetings** folder of the workspace it's about. It only moves a meeting when it's confident, and a meeting you've filed yourself stays where you put it.

## On every device

A meeting's note syncs like any note. With **Sync meeting recordings** on, as it is to begin with, the recording goes to your other devices too. A meeting filed in a team's workspace goes to everyone in the team. Turn it off and the words still sync, but the sound stays on the device that made it.

Meetings Ghost recorded from Google Meet reach your devices as soon as Ghost leaves the call. On the iPhone, which can't keep the sound yet, a Meet note is filed from Meet's captions.

## The Meetings shelf

In Advanced, your home page has a shelf of **Meetings**: a cassette for each recorded meeting, newest first, with its length and date. One being recorded says **Recording now**.

- **Tap a cassette** to open its note at the tape, playing.
- **On a Mac,** rest the pointer on a cassette to hear it.
- **See all** shows every note with a tape.

## Private by design

The meeting's sound passes through Ghost.md's server while Ghost records it, sealed to your account as it arrives. The server can't open it. It's written up on your device, never on the server.

Remember that a meeting is other people's voices. Let them know Ghost is there.

See also: [[Tapes and transcripts]], [[Speaking your notes]], [[Claude in Ghost.md]], [[Workspaces, folders and search]], [[Organizations and shared notes]]
