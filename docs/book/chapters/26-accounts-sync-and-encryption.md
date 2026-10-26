# Accounts, sync and encryption

An account is optional. Without one, Ghost.md works fully and nothing of yours is on a server. With one, your notes are the same on your phone, your computer and the web, and everything is encrypted on your device before it leaves.

Works on: Android, iPhone, Mac, Windows and the web.

## Making an account

Open **Settings › Account** and choose **Create an account**. It asks for:

- **A handle**, the name you sign in with: 3 to 24 letters, digits, `.`, `_` or `-`, starting with a letter or a digit.
- **A password** of at least 8 characters.

Tap **Create account**. Next you see your **recovery codes**. Each one opens your account once if you lose the password. **Copy all** puts them on the clipboard. Keep them somewhere safe, away from this device, then tap **I've kept them**. They are shown this once and never again.

The notes already on the device become the account's first notes when it first syncs.

## Signing in on another device

On the other device, open **Settings › Account**, choose **I have an account**, give the same handle and password, and sign in. Your notes arrive, any notes already on that device join them, and the device takes on your account's settings.

A device that is signed in stays signed in. It keeps a key of its own and renews its session with it, so it never needs your password just to keep syncing.

## The key you hold

Ghost.md is end-to-end encrypted. In plain words:

- **Your password never leaves the device as itself.** The app turns it into two keys. One is sent, to sign you in. The other stays on your devices and opens your notes.
- **Everything is sealed on the device before it is sent**: notes, pictures, recordings, settings. The sync service stores only what it cannot read.
- **The service keeps your account's key only locked**, under your password and under each recovery code. It holds nothing that opens it.

The service sees what it needs to sync: your handle, a random id for each note and file, when each changed, how big each is, a picture's file type, and which kind of device each of yours is. It never sees a title, a folder, a word of a note or a second of a recording.

Organizations are the exception, on purpose: their names and members are kept in the clear so invitations can reach people. The notes filed in one are still encrypted. See [[Organizations and shared notes]].

### The one thing that cannot be undone

**Nobody can reset your password, not even the people who run the service.** If you forget the password, lose every signed-in device and lose every recovery code, what the account keeps on the server can't be opened by anyone, ever. The notes on a device you still have are yours either way.

If you forget the password but still have a code, choose **Lost the password** on the sign-in page. Give your handle, one recovery code and a new password, then tap **Recover and set password**. That code is spent, and you get a fresh set.

## The Account page

Signed in, the page opens with your handle, **End-to-end encrypted**, and how sync stands:

| It says | Meaning |
|---|---|
| Syncing | A sync is running now. |
| Synced just now, Synced 4 min ago | The last one finished cleanly. |
| Waiting to sync | Signed in, not synced yet. |
| Sign in again to sync | This device no longer holds your key. Sign in again. |

Under it, the **Sync** card has:

- **Sync now**: syncs at once. On a Mac, `⌘R` does the same.
- **Live typing**: a note open on two of your devices, or one Claude is writing in, shows the words as they are typed, encrypted like everything else. On unless you turn it off.
- **Keep keys and connections in sync**: see below.
- **Password and recovery codes**: **Change password**, or **Make new recovery codes instead**. Both ask for your current password. New codes replace the old set.
- **Sign out**: "Your notes stay on this device."

After it come **Your colour**, **Shared links** and **Published sites** (once you have some), **Privacy**, **Location**, **Export everything**, and **Delete account**.

## What syncs

- **Notes**, with everything in them: words, front matter, transcripts, a note's location.
- **Pictures** and files in your notes.
- **Recordings.** A recording longer than about 2 hours 19 minutes stays on the device that made it.
- **Meeting recordings**, by default. A meeting is other people's voices, so you can turn **Sync meeting recordings** off in **Settings › Meetings**. Off, the words of a meeting sync and the audio stays on the device it was made on.
- **Your settings**: the look of the page, fonts, text size, recording choices and the like.
- **Your workspaces, the trash, your shared links**, and your notification choices.

What stays on each device: the model you downloaded, and the Developer settings.

### Keys and connections

With **Keep keys and connections in sync** on, these follow your account to each device you sign in to, each sealed again on its own so the server can't read them and they never sit readable in a device's storage:

- **Claude**: your API key, the model, the spending limit and its switches.
- **Slack**: your channels and their webhooks, and where meetings post.
- **GitHub**: your token.
- **Lovart**: your access key and secret key.
- Whether each of these four plugins is on.

The calendars' addresses, Google's sign-in and your webhooks travel sealed with the rest of your settings. Your Notion sign-in stays on each device: sign in to Notion on each one.

If two devices change the same key between syncs, the later change wins. Removing a key on one device removes it everywhere. Turn the switch off to keep keys on each device separately.

### When two devices change one note

A note changed on one device reaches the others as it is. If the same note is changed on two devices with different words before they sync, both versions are kept, as separate notes, and nothing you typed is lost. The Account page says so: "A note was changed on two devices at once. Both versions are kept as separate notes." Team notes in an organization merge instead.

## Local only

**Settings › Account › Privacy › Local only** keeps everything on this device: no sync, no updates, no downloads, no link titles, and every plugin that uses the internet is held off. Ghost.md runs from what is already on the device. While it is on, the Account page says so, and sync waits until you turn it off. It is kept on each device separately.

## Signing out

**Sign out** on the Account page signs this device out. Its session and its keys go; the notes on it stay where they are.

To end every device's session at once, there is one way: deleting your account, below. Changing your password does not sign your other devices out.

If you have connected Claude's own app to your notes, ask Claude to **sign out everywhere**. That ends every Claude connection to your account, and each must sign in again. Disconnecting Ghost.md in Claude ends that one. See [[Claude in Ghost.md]].

## Deleting your account

Open **Settings › Account › Delete account**, read what goes, enter your password, and tap **Delete my account**.

At once and for good, it deletes your account and everything it keeps on the sync service: your synced notes, their recordings and pictures, your settings, and every link you've shared, which will stop opening. Your other devices are signed out. **The notes on this device stay here**, and the page says "Your account is deleted. The notes on this device are still here."

If you own an organization that anyone else is in, hand it over or delete it first. An organization with nobody else in it goes with the account.

An AI assistant you connected loses access too. If you can't sign in, sign in with a recovery code first. If you have lost both the password and every code, https://ghostmarkdown.com/delete-account.html says how to ask for the account to be deleted.

See also: [[Sharing and published sites]] · [[Privacy]] · [[Organizations and shared notes]] · [[Settings]] · [[Troubleshooting]]
