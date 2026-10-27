# Accounts, sync and encryption

An account is optional. Without one, Ghost.md works fully and nothing of yours is on a server. With one, your notes are the same on your phone and your computer, and everything is encrypted on your device before it leaves.

**Works on:** Android, iPhone, Mac and Windows. A browser version is coming back; until it does, this chapter is about the apps.

The first time you open Ghost.md, it offers the way in before anything else: **Sign in** or **Sign up**, or **Use without an account**. Whatever you choose, it doesn't ask again, and the way in is **Settings › Account** from then on.

## Making an account

Open **Settings › Account** and choose **Create an account**. It asks for:

- **A handle**, the name you sign in with: 3 to 24 letters, digits, `.`, `_` or `-`, starting with a letter or a digit.
- **A password** of at least 8 characters.

Tap **Create account**. Next you see your eight **recovery codes**. Each one opens your account once if you lose the password. **Copy all** puts them on the clipboard. Keep them somewhere safe, away from this device, then tap **I've kept them**. They are shown this once and never again.

A handle is yours alone: no two accounts share one, whatever the capitals.

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

There are a few exceptions, each on purpose:

- **Organizations**: their names, colours and members are kept in the clear so invitations can reach people. The notes filed in one are still encrypted. See [[Organizations and shared notes]].
- **Email to a note**: a mail is read by the service as it arrives, as any mail server must, then sealed to your account at once. Only the sealed copy is kept.
- **Meetings Ghost joins**: the meeting's link, title and times are kept in the clear until an hour after it ends, because the bot that joins has no key. The recording is sealed to your account as it arrives.

[[Privacy]] has the details.

### The one thing that cannot be undone

**Nobody can reset your password, not even the people who run the service.** If you forget the password, lose every signed-in device and lose every recovery code, what the account keeps on the server can't be opened by anyone, ever. The notes on a device you still have are yours either way.

If you forget the password but still have a code:

1. Choose **Lost the password** on the sign-in page.
2. Give your **Handle**, one **Recovery code** and a **New password**.
3. Tap **Recover and set password**.

That code is spent, and you get a fresh set of codes to keep.

## The Account page

Signed in, the page opens with your handle, **End-to-end encrypted**, and how sync stands:

| It says | Meaning |
|---|---|
| Syncing | A sync is running now. |
| Synced just now, Synced 4 min ago | The last one finished cleanly. |
| Waiting to sync | Signed in, not synced yet. |
| Sign in again to sync | This device no longer holds your key. Sign in again. |
| Not synced | The last sync failed; the page says why. |

Under the line, a note may say "3 notes not synced" and why. They are sent again next time.

Sync runs when the app opens, when you come back to it, a few seconds after you change something, and every five minutes while it's open. A meeting, a mail or a recording that arrives for you is fetched at once.

Under it, the **Sync** card has:

- **Sync now**: syncs at once. On a Mac, `⌘R` does the same.
- **Live typing**: a note open on two of your devices, or one Claude is writing in, shows the words as they are typed, encrypted like everything else. On unless you turn it off. It starts with the next note you open.
- **Keep keys and connections in sync**: see below.
- **Password and recovery codes**: **Change password**, or **Make new recovery codes instead**. Both ask for your current password. New codes replace the old set.
- **Sign out**: "Your notes stay on this device."

After it come:

- **Your colour**, how a team sees you ([[Organizations and shared notes]]);
- **Shared links** and **Published sites**, once you have some ([[Sharing and published sites]]);
- **Email to a note**, your private address ([[Email to a note]]);
- **Privacy** and **Location** ([[Privacy]]);
- **Export everything** ([[Import, export and backup]]);
- **Delete account**, below.

## What syncs

- **Notes**, with everything in them: words, front matter, transcripts, a note's location.
- **Pictures** and files in your notes.
- **Recordings.** A recording longer than about 2 hours 19 minutes stays on the device that made it.
- **Meeting recordings**, by default. A meeting is other people's voices, so you can turn **Sync meeting recordings** off on the **Meetings** card in **Settings › Recording**. Off, the words of a meeting sync and the audio stays on the device it was made on. The card says how many recordings stayed on this device, and why.
- **Version history**: each note's versions file, sealed like the note.
- **Your settings**: the look of the page, fonts, text size, Simple or Advanced, recording choices and the like.
- **Your workspaces and folders, smart notebooks, the Trash, your shared links**, and your notification choices.

What stays on each device: the model you downloaded, the Developer settings, and choices that are the device's own, such as **Tag new notes with my location**, **Local only** and the window's layout. An iPhone records nothing, so it has no recordings to send.

### Keys and connections

**Keep keys and connections in sync**, on the Sync card, is on to begin with. While it's on, these follow your account to each device you sign in to, each sealed again on its own so the server can't read them and they never sit readable in a device's storage:

- **Claude**: your API key, the model, the effort, the switch for the "Ask Claude" note, the watch's switch for sending to Claude, and the spending limit (on or off, the amount and the warning).
- **Slack**: your channels and their webhooks, and **Post to Slack** for meetings.
- **Discord**: your channels and their webhooks, and **Post to Discord** for meetings.
- **GitHub**: your token.
- **Lovart**: your access key and secret key.
- Whether the Claude, Slack, Discord, GitHub, Lovart, Google Meet and Zoom plugins are on. So turning Zoom off on one device stops Ghost joining Zoom meetings for the whole account.

The calendars' addresses, Google's sign-in and your webhooks travel sealed with the rest of your settings.

These stay on each device:

- **Your Notion sign-in**, and which board each note sends to. Notion replaces its sign-in each time it's used, so two devices can't share one: sign in to Notion on each.
- **What Claude spent this month**: each device counts its own, held to the same limit.
- **Where an organization's news goes on Slack**, so each piece of news is posted once, not once a device.
- **Lovart's project** and **Inspiration for design meetings**.

On an iPhone, the Slack and Discord items aren't offered, as neither plugin is there yet. Claude's key does reach an iPhone.

If two devices change the same key between syncs, the later change wins. Removing a key on one device removes it everywhere. Turn the switch off, on each device you want, to keep that device's keys to itself: it then sends nothing and takes nothing, and keeps the copy it has. Signing out takes the account's keys out of this device's settings, so another account signed in here never sees them.

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

At once and for good, it deletes your account and everything it keeps on the sync service: your synced notes, their recordings and pictures, your settings, every link you've shared and every site you've published (which stop opening), your email address and any mail waiting, your meetings and their recordings waiting to be fetched, your Discord link, your incoming webhooks, your devices, your recovery codes and your notifications. The organizations you were in are told you left. Your other devices are signed out. **The notes on this device stay here**, and the page says "Your account is deleted. The notes on this device are still here."

If you own an organization that anyone else is in, the app says "Hand over or delete your organizations first." An organization with nobody else in it goes with the account.

An AI assistant you connected loses access too. If you can't sign in, sign in with a recovery code first. If you have lost both the password and every code, https://ghostmarkdown.com/delete-account.html says how to ask for the account to be deleted.

See also: [[Sharing and published sites]] · [[Privacy]] · [[Organizations and shared notes]] · [[Settings]] · [[Troubleshooting]]
