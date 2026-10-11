# Accounts, sync and the key you hold

_An account is optional. With one, your notes, settings, recordings and pictures are the same on every device, and each is sealed on the device before it leaves._

## Without one

Ghost.md works without an account, and then nothing of yours is on a server. On a phone or a Mac every note is a Markdown file; a browser keeps its notes in its own storage. An account adds one thing: the same library on your phone, your Mac and a browser, kept in step.

## Making an account

Open Settings › Account and choose **Create an account**. It asks for two things.

| | |
|---|---|
| **Handle** | The name you sign in with: 3 to 24 letters, digits, `.`, `_` or `-`, starting with a letter or a digit. |
| **Password** | At least 8 characters. |

Tap **Create account**. The next page shows your eight **recovery codes**. Each is three groups of four letters and digits, shaped like `XXXX-XXXX-XXXX`, with no 0, O, 1 or I to misread. **Copy all** puts them on the clipboard. Keep them somewhere safe, away from this device, then tap **I've kept them**. They are shown this once and never again.

The notes already on the device become the account's first notes with the first sync.

## Signing in on another device

On the other device, open Settings › Account. The page opens on **Sign in**: give the same handle and password and tap **Sign in**. A sync starts at once. The account's notes arrive, any notes already on that device join them, and the device takes on the account's settings.

A signed-in device stays signed in. It registers a key of its own as it signs in and renews its session with it, so it never needs the password just to keep syncing.

## Password, codes and signing out

Signed in, the Account page holds these rows.

| Row | What it does |
|---|---|
| **Sync now** | Runs a sync at once. |
| **Live typing (trial)** | See [[Live typing]]. |
| **Password and recovery codes** | **Change password** asks for the current password and a new one. **Make new recovery codes instead**, then **Make new codes**, makes a fresh sheet of eight, shown once; the old sheet stops working. Both ask for the current password. |
| **Sign out** | "Your notes stay on this device." The session and this device's keys go; the notes stay where they are. |
| **Organizations** | Under the Sync card. The teams you are in, with your role in each and how many have joined; an invitation waiting, with Accept and Decline on its row; and **New organization**, which asks for a name and opens the organization. More under Organizations, below. |

Changing the password changes nothing else. No note is sealed again, and your other devices stay signed in.

**Lost the password.** On the sign-in page, choose **Lost the password**. Give your handle, one recovery code and a new password, then tap **Recover and set password**. The code is spent, the new password is set, this device is signed in, and a fresh sheet of eight codes is shown in place of the old one. Dashes and capitals in a code make no difference.

If you forget the password, a device that is still signed in keeps syncing. Changing the password, making new codes and deleting the account all ask for it, though, so recover with a code.

## End to end, in plain words

- **Your password never leaves the device as itself.** The app turns it into two halves. One is sent, to sign you in. The other stays on the device, and is what opens your account's key.
- **The account key is made on the device you sign up on.** Every note, setting, recording and picture is sealed with it before it is sent.
- **The server keeps that key only locked**, once under your password and once under each recovery code. It holds nothing that opens it.
- **A device keeps the key where the app can use it but cannot copy it out.**

The server sees your handle, a random id for each note, which notes have a recording, each picture's name and file type (a picture added in the app has a random name), when each changed, how big each is and how many there are, and which kind of device each of yours is ("Android", "Mac"). It never sees a title, a folder, a word of a note, a setting or a second of a recording.

An organization is the exception, and on purpose: an invitation has to reach another account, so the server sees an organization's name and colour, who is in it by handle and in what role, who invited whom and when, and, for a day, that someone declined. Of your notifications it sees the kind and the time of each, who caused it and which organization for the ones it writes itself (with the few words in them, such as the organization's name), and when you read or hid each one, so that follows you to your other devices. The ones about your own notes, Claude's edits, a meeting written up or a note kept twice, are sealed like a note: the server sees that Claude edited something, not what. Inviting a handle nobody has answers "No one has that handle.": that is the one place a signed-in account can learn whether a handle exists, and it is limited to thirty invitations an hour.

The one place your key is ever held away from your own devices is the hosted Claude connector: in its memory, and on its disk only sealed under a token Claude holds, and only while you keep it connected ([[Claude on your notes]]).

## The one thing that cannot be undone

Nobody can reset your password, not even the people who run the service. Forget the password, lose every signed-in device and lose every recovery code, and everything the account keeps on the server is sealed for good. Nobody can open it again. The sign-in page says so under its form. Notes on a device you still have are yours either way.

## When sync runs

| When | |
|---|---|
| The app starts | if you are signed in |
| You come back to it | from another app, or waking the device |
| Four seconds after a change | a note saved or a setting changed; each change in between starts the wait again |
| Every five minutes | while the app is open |

One sync runs at a time. Asking while one runs queues one more after it.

What travels: notes, their recordings and pictures, the trash, your workspaces, the notes open as tabs and their groups, your shared links, your notification switches and the organizations you have muted, and the settings that describe you (the page and its spacing, text size, fonts, link previews, code colours, how notes are shown, the recording choices, the animations). An organization's workspace is not sent as such: every device makes the same one from the organization itself, so it is there on each the moment you join. What stays on each device: the accent colour, size, corners, the sidebar docked or popped over, haptics, Local only, the model you downloaded, which plugins are on, which workspace you are looking at, Live typing and the developer settings. A browser syncs notes and pictures, and keeps no recordings.

Settings are one set for the whole account. If two devices change them at the same moment, the later one wins.

**Local only**, in Settings › Account › Privacy, stops sync until it is off.

## When two devices change one note

A note changed on one device reaches the others as it is. A note changed on both, with different words, is kept twice. The version already on the account stays as the note, and this device's version becomes a new note under the same title. On a phone or a Mac the copy's file is made in the Inbox folder, and takes a number if that name is taken there, such as `Shopping 2.md`. Nothing you typed is lost. The copy holds the words; the recording stays with the original.

Only words are kept twice. A pin, the archive or where a note is filed, changed on both sides, takes the other device's. A note deleted on one device and changed on another comes back.

The Account page says when this has happened: "A note was changed on two devices at once. Both versions are kept as separate notes."

## What the Account page shows

At the top: your handle, **End-to-end encrypted**, and how sync stands.

| It says | Meaning |
|---|---|
| Syncing | A sync is running. |
| Synced just now, Synced 4 min ago | The last one finished cleanly. After an hour it gives the time and date instead. |
| Waiting to sync | Signed in, and not synced yet. |
| Sign in again to sync | This device is signed in but no longer holds the key. |
| Sync needs the newest Ghost.md. Install it from attack.fm/glyph. | The app on this device is too old to sync. |

Any other failure is said in its own words. The Account row in the Settings list carries the same news in one line: your handle, then "synced 4 min ago".

Below come **Organizations**, **Shared links** ([[Sharing a note or a notebook]]) and **Delete account**.

## Organizations

An organization is a team: a name, a colour, and people by handle. Make one from **Settings › Account › Organizations › New organization**, or from **New organization** beside New workspace in the home page's filters. You are its owner.

**Its page.** The people icon in the tab row, beside the bell, lists the organizations you are in, and one opens its page: its colour, its name, how many have joined and what you are, with **New note**, which makes a note already filed in its workspace. Under that, the newest notes filed there, its members with their roles, and its news: who joined, left or was removed, a rename, a new role. An owner or an admin also has **Invite** and a field to give a handle. The cog at the top right opens its settings: General (the name and colour), Members, Workspace, Notifications, Report and, last, Leave or Delete. **Report** opens an email to Ghost.md's maker about a member or something written there; team notes are sealed, so the email has to carry the words it is about. An invitation, or a notification about an organization, opens the same page.

**Your colour.** Pick one of the seven under Settings › Account › Your colour, and it is yours in every organization: your initial in the members wears it, and so will your cursor, your selections and your comments once the team's notes are live. An organization can give you another colour under its members ("Your colour here"), worn there alone.

**Who is in the app.** While you are signed in, each organization you are in knows your devices are in the app, and which of its notes you have open: on its page a member in the app has a dot on their initial in their colour, and their row says **here now** or **editing Roadmap**. Tap the row for their profile - since when, the colour they wear here, where they are - and **Jump to cursor** opens the note they are editing at their caret. In the note itself, every member who has it open is a caret in their colour with their handle on it, and what they have selected is washed in it; their typing arrives as they type. On a canvas they are an arrow in their colour instead, and Jump to cursor opens the canvas where their pointer is ([[Canvases, cards and lines]]). Nothing of this is kept anywhere: the moment a device leaves, it is gone from the list.

**Its audit log.** The clock beside the cog, or **Audit log** over its news, opens the organization's audit log: every version of every note filed in its workspace, with what the team did between them, newest first under the day. Each line is who, what they did and to which note, when, how many lines came and went and the first of them; a line opened shows what that version changed, with **Open the note** and **Only this note**. The field over the list narrows it to a note, a person or a version's name, and the pills show everything, the notes or the team. Notes whose history is switched off are named under the figures. The notes are still yours alone, so the log is your own changes on your devices, with the team's news around them.

**Inviting someone.** On the organization's page, or under Members in its settings, give a handle. They are told "No one has that handle." if nobody has it, and "They are already a member." if they are. Otherwise the person sees your invitation at once on their next sync: a dot on the bell, a row in their notifications with **Accept** and **Decline**, a card on their home page (accepting there opens the organization's page), and the organization under their own Account › Organizations. Asking again before they answer sends nothing new. If they decline, the organization has to wait a day before asking them again, and they can have twenty invitations waiting at most.

**Roles.** The owner can rename the organization, pick its colour, change anyone's role, hand it over and delete it. An admin can invite, and remove members and people still invited. A member can leave. There is always exactly one owner: nobody can remove the owner ("Hand the organization over first."), an admin cannot remove an admin, and to hand over the owner sets someone who has joined to owner, becoming an admin themself.

**The team's key.** The notes filed in an organization are sealed under a key the organization's members share, wrapped for each of them under their own account's keys and never seen by the service. When someone leaves, or is removed, the key turns: the next member's device to sync makes a new one, wraps it for everyone still in, and puts every note again under it, so nothing the team writes from then on is sealed under a key the person who left still has. You see none of this happen, except that a sync after someone leaves takes a little longer.

**The workspace.** The moment you join, a workspace named after the organization and in its colour is on every device of yours, with a small mark before its name wherever workspaces are drawn. Notes filed there are the team’s: every member has them, reads them and edits them, and edits made apart merge rather than copy. Filing a note there shares it; taking it out takes it from everyone, so the workspace picker asks twice. If you leave, are removed, or the organization is deleted, the workspace goes from your devices with its notes, which stay the team’s.

**What you are told.** Everyone in an organization hears when someone joins, leaves or is removed, when it is renamed and when it is deleted; the person who did it is not told their own news. The organization can be muted under Settings › Notifications, or from its own Notifications section.

## Deleting the account

Settings › Account › **Delete account**. The page says what goes, then asks for your password; tap **Delete my account**. At once and for good, the service deletes the account and its handle, your synced notes with their recordings and pictures, your settings, every link you have shared (which stops opening), your devices' keys and your recovery codes, your notifications and your place in every organization, whose other members are told you left. While you own an organization that anyone else is in, it is refused with "Hand over or delete your organizations first."; an organization with nobody else in it goes with the account. Your other devices sign out the next time they start. The notes on this device stay, and the page says so: "Your account is deleted. The notes on this device are still here."

## Read next

- [[Live typing]]
- [[Sharing a note or a notebook]]
- [[What stays on your phone]]
