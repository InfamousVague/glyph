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

Changing the password changes nothing else. No note is sealed again, and your other devices stay signed in.

**Lost the password.** On the sign-in page, choose **Lost the password**. Give your handle, one recovery code and a new password, then tap **Recover and set password**. The code is spent, the new password is set, this device is signed in, and a fresh sheet of eight codes is shown in place of the old one. Dashes and capitals in a code make no difference.

If you forget the password, a device that is still signed in keeps syncing. Changing the password, making new codes and deleting the account all ask for it, though, so recover with a code.

## End to end, in plain words

- **Your password never leaves the device as itself.** The app turns it into two halves. One is sent, to sign you in. The other stays on the device, and is what opens your account's key.
- **The account key is made on the device you sign up on.** Every note, setting, recording and picture is sealed with it before it is sent.
- **The server keeps that key only locked**, once under your password and once under each recovery code. It holds nothing that opens it.
- **A device keeps the key where the app can use it but cannot copy it out.**

The server sees your handle, a random id for each note, which notes have a recording, each picture's name and file type (a picture added in the app has a random name), when each changed, how big each is and how many there are, and which kind of device each of yours is ("Android", "Mac"). It never sees a title, a folder, a word of a note, a setting or a second of a recording.

The one place your key is ever held away from your own devices is the hosted Claude connector: in its memory only, and only while you keep it connected ([[Claude on your notes]]).

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

What travels: notes, their recordings and pictures, the trash, your workspaces, the notes open as tabs and their groups, your shared links, and the settings that describe you (the page and its spacing, text size, fonts, link previews, code colours, how notes are shown, the recording choices, the animations). What stays on each device: the accent colour, size, corners, the sidebar docked or popped over, haptics, Local only, the model you downloaded, which plugins are on, which workspace you are looking at, Live typing and the developer settings. A browser syncs notes and pictures, and keeps no recordings.

Settings are one set for the whole account. If two devices change them at the same moment, the later one wins.

**Local only**, in Settings › Formatting, stops sync until it is off.

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

Below come **Shared links** ([[Sharing a note or a book]]) and **Delete account**.

## Deleting the account

Settings › Account › **Delete account**. The page says what goes, then asks for your password; tap **Delete my account**. At once and for good, the service deletes the account and its handle, your synced notes with their recordings and pictures, your settings, every link you have shared (which stops opening), your devices' keys and your recovery codes. Your other devices sign out the next time they start. The notes on this device stay, and the page says so: "Your account is deleted. The notes on this device are still here."

## Read next

- [[Live typing]]
- [[Sharing a note or a book]]
- [[What stays on your phone]]
