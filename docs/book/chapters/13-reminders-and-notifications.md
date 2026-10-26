# Reminders and notifications

Ghost.md can remind you of a to-do at a time, or when you arrive somewhere. It also keeps a list of what happened while you were away: invitations, your organizations' news, and changes Claude made to your notes. This chapter covers both.

## Reminders

Works on: Android. On an iPhone or a Mac, a reminder written on a line is kept and shown, and rings on your Android phone.

### At a time: ⏰

A reminder is written on the to-do's line, after its words, with `⏰`, a day and a time:

```markdown
- [ ] Call the plumber ⏰ 2026-10-03 09:00 📅 2026-10-03
```

It's the same mark the Obsidian Reminder plugin reads, so the line works there too. The time is your phone's clock wherever you are: a reminder written for nine rings at nine, even if you've changed time zone.

A ticket keeps its reminder in its front matter, as `remind: 2026-10-03 09:00`, beside its `due:`.

You don't need to type any of it. Press and hold a to-do and choose **Remind me**. It offers:

- **In an hour**, to the next five minutes.
- **This evening**, at 18:00. It's offered until five in the afternoon.
- **Tomorrow**, at the time set in Settings.
- **Pick a time**, on your phone's own calendar and clock.
- **Remove**, when the line already has a reminder.

### Due dates remind you too

A to-do or a ticket with a due date (`📅`) and no `⏰` reminds you on the day it's due, at the time set in Settings › Notifications › **Reminders**. Nothing extra is written on the line. See [[Lists, to-dos and tickets]] for due dates.

### At a place: 📍

A place reminder rings when your phone arrives somewhere:

```markdown
- [ ] Buy diapers 📍 [Target](geo:35.7002,-81.3084)
```

The place is written as a pin and a link, so other apps show it too.

Place reminders come from the **Place reminders** plugin. Add it in the Market first. See [[The Market]].

Then press and hold a to-do and choose **Remind me at a place**. You can:

- **Search for a place**: a shop, a street, a town. The search uses OpenStreetMap, and is off while Local only is on.
- Pick one under **In this note**, from the places the note already has.
- Choose **Here**, where you are now.

When your phone comes within about 150 metres, the to-do reminds you. Tick it and the reminder goes.

The first time, Ghost.md explains why it needs your location, then asks for it. A place reminder needs location **all the time**, because it has to work while the app is closed. If you choose **Not now**, the reminder is kept but won't ring until you allow it. The plugin's page in Settings has the way to allow it later.

A reminder for a place you're already in doesn't ring at once. It waits until you arrive next time.

### How a reminder rings

A reminder is a notification titled "A reminder from Ghost.md", with the to-do's words and its note. A place reminder says where you are.

- **Tap it** to open the note at that line.
- **Done** ticks the to-do, even with the app closed.
- **Snooze 1 hour** rings it again in an hour. A place reminder has no Snooze, since an hour from now you could be anywhere.

Reminders keep working after your phone restarts and after Ghost.md updates. One missed while the phone was off rings once when it starts again, if it was due in the last twelve hours.

**Exact times.** From Android 12, Android asks you to allow an app's alarms to ring on the minute. Without that, a reminder may come a few minutes late, but it still comes. Settings › Notifications says so, with **Allow exact times**.

## Settings › Notifications

Works on: Android, iPhone and Mac. The Reminders card and On this phone are on Android only.

### Reminders

- **Remind me**: whether this phone reminds you at all. It's on to start with. It covers to-dos and tickets with a due date, and any line with a time set.
- **Time**: when a due date with no time of its own reminds you. 09:00 to start with.
- **The day before**: also remind you at that time the day before it's due. Off to start with.

If Android isn't showing Ghost.md's notifications, the card says so, with **Allow notifications**.

### What reaches you

Notifications come with an account. Signed out, the page sends you to Settings › Account. Four switches decide what reaches the bell:

| Switch | What it covers |
|---|---|
| **Team** | Who joined, left or was removed, an organization renamed or deleted, and your invitations answered. |
| **Claude** | A note Claude made, edited or added to through the MCP server, with the first line it changed. |
| **Summaries** | A meeting written up. |
| **Conflicts** | A note changed on two devices at once and kept twice. |

An invitation to an organization always arrives, whatever the switches say: whoever sent it is waiting for your answer.

### Mute an organization

Once you're in an organization, each one gets a switch here. Muted, its team news isn't shown or counted. Its invitations still are. See [[Organizations and shared notes]].

### On this phone

On Android, **Phone notifications** turns the bell's news into the phone's own notifications too: team news, invitations and Claude's changes, as the switches above say. They arrive within about fifteen minutes while Ghost.md is closed. While it's open in front of you, the bell has them instead.

## The bell

The bell sits on the top bar. When something unread has arrived, it lights with a dot. Tap it to open the notifications drawer.

The drawer lists what arrived, newest first. Each row says what happened, for example "Sam invited you to Design team", or "Claude edited a note". A row about Claude's change shows the first line it changed underneath.

- **Tap a row** to open what it's about: a note, at the first line that changed, or an organization.
- **Accept** and **Decline** answer an invitation right there.
- **Mark all read** and **Clear all** are at the top.

If there's nothing yet, it says so: invitations, what Claude wrote and your meetings written up arrive here. While Local only is on, nothing arrives until it's off.

## When a meeting is written up

A meeting is written up after it ends. To hear about it, go to Settings › Recording › Meetings, and turn on **Tell me when a meeting is written up**. You get a notification with the first line of the summary, once the phone is unlocked. If Android has notifications off for Ghost.md, the row says so and offers to allow them.

Works on: Android. A meeting written up on another of your devices still reaches the bell, through the **Summaries** switch. See [[Meetings and the Meet bot]].

See also: [[Lists, to-dos and tickets]] · [[Plugins, one by one]] · [[Meetings and the Meet bot]] · [[Claude in Ghost.md]] · [[Organizations and shared notes]] · [[Settings]]
