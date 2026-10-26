# Email to a note

Your account can have a private email address. Anything mailed to it becomes a note in your Inbox: forward yourself a receipt, a booking, a newsletter worth keeping, or an idea typed on someone else's computer.

Works on: Android and Mac, which set up the address and file the mail. The notes then sync to your other devices, iPhone included. You need an account. See [[Accounts, sync and encryption]].

## Your Ghost address

An address looks like `name@in.ghostmarkdown.com`. Ghost.md makes up a readable one for you, something like `sneaky_siren33@in.ghostmarkdown.com`, or you can choose your own.

### Turning it on

Go to Settings › Meetings, and find **Email to a note**. Tap **Turn on an address**. Ghost.md makes one for you straight away.

The address appears on the **Invite Ghost** card, just above, because the same address invites Ghost to your meetings (more on that below). Beside it:

- **Copy** puts the address on your clipboard.
- **Choose a name…** lets you pick your own name.
- The round arrows make a new address. It asks first: **Make a new address?**, then **Make it**.

If your account's server doesn't offer meetings, the whole card is on Settings › Account instead.

### Choosing your own name

Tap **Choose a name…** and type the part before the `@`. Ghost.md checks it as you type. A name must be:

- **3 to 30 characters**: letters, numbers, dots, dashes and underscores only.
- Separated sensibly: a dot, dash or underscore goes between letters or numbers, one at a time.
- Not one Ghost.md would make up for you, and not a reserved name such as `admin`, `support` or `postmaster`.
- Not already taken, now or in the past.

When the name is free, tap **Use this name**, then **Switch**. Your old address stops taking mail at once.

A name of your own is easier to remember, and easier to guess. Anyone who guesses it can send mail to it. What arrives is still sealed to your account, and the address still takes no more than thirty mails an hour.

### A new address

**Make a new address** puts a new one in place of the old. The old one stops taking mail at once, and anyone who mails it gets a bounce. Use this if your address starts getting mail you don't want.

An address you give up is never given to anyone else. You can take it back later, but no other account ever can.

### Turning it off

**Turn off**, at the foot of the Email to a note card, turns mail and invites away. Mail already sent is still filed.

## What the note looks like

Mail sent to your address becomes a note in your Inbox: its subject the title, its words and pictures the note.

```markdown
---
from: "Sam Lee <sam@example.com>"
---
# Café plans

The body of the mail, as Markdown, with each picture in its place.

![door.png](image/….png)
```

- **The subject** becomes the title. Mail with no subject is called "A mail from" and the sender's name.
- **The sender** is kept in the note's front matter as `from:`.
- **The body** is turned into Markdown. A very long body is cut at about 900 KB, and the note says so.
- **The date** is when the mail was sent.
- **Pictures** in the mail (JPEG, PNG, GIF or WebP) are kept as the note's own pictures: in their place where the mail showed them, otherwise under the words.
- **Other files** are kept as attachments in the note. If a file can't be kept, the note names it instead: "Came with it, not kept: menu.pdf (9 KB)."

The note isn't in any workspace, so it lands in your Inbox. File it wherever you like from there. See [[Workspaces, folders and search]].

### Arriving

Mail is filed the next time one of your Android phones or Macs syncs. Until then it waits, sealed, on the server. Each mail becomes one note, even if two devices sync at once.

A `+tag` after the name is ignored, so `name+receipts@in.ghostmarkdown.com` reaches you too. That's handy for telling where a mail came from.

## Who can send to it

Anyone with the address can send to it, so give it only where you mean to.

There are limits that keep it from being flooded:

| | |
|---|---|
| A single mail | 10 MB |
| Files in one mail | 40 |
| Mail an address takes | 30 an hour |
| Mail waiting for your devices | 200 |

Past these, the sender gets a bounce, or their mail server tries again later.

Two things are left out of every mail, for your privacy:

- **Pictures loaded from the web.** In a note they'd be fetched every time you read it, and a tracking picture would learn when you did.
- **Links that run a script.** They're made harmless.

## What the server can see

This is the one place in Ghost.md where the server reads your words in the clear, and the card says so.

Email isn't private on its way to anyone: a mail server has to read a mail to deliver it. So when a mail arrives, Ghost.md's server:

1. checks it came from the mail provider, and that the address and the limits are right;
2. reads it into a note's words, pictures and files;
3. **seals it at once** to your account's key;
4. keeps only the sealed copy, and forgets the rest.

The readable copy is never written to disk or to a log. The sealed copy waits until your next sync, when your device opens it with your account's private key, files the note, and the server's copy is deleted. Your private key never leaves your devices. See [[Privacy]].

## Inviting Ghost to a meeting

The same address brings Ghost to your meetings. Add it as a guest on a calendar invite that has a Google Meet or Zoom link. Ghost joins by itself, records the meeting, and files it as a note, written up with who said what. The invite mail becomes a note too.

Make a new address and a calendar invite that still has the old one needs the new one. See [[Meetings and the Meet bot]].

See also: [[Meetings and the Meet bot]] · [[Accounts, sync and encryption]] · [[Privacy]] · [[Workspaces, folders and search]] · [[Pictures, files and voice memos]]
