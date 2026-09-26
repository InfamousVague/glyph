# What stays on your phone

_What Ghost.md keeps on your device, what goes out only when you ask, and what its server can and cannot see._

## What never leaves

- **Your voice.** In the apps, what you say is turned into words on the device, by a model downloaded once. No recording is sent anywhere to be transcribed.
- **The AI's work.** Formatting, the runs on a note's More sheet, spoken asks and the review all use models on the device. Ghost.md has no cloud AI of its own: no note is ever sent away to be written.
- **Every note, when you have no account.** In the apps, your notes, their recordings and their pictures are Markdown files and the files beside them, on the device. In a browser, that browser keeps them. Without an account, nothing of yours is on Ghost.md's servers.

Your device's own backup may include the app's files. That is between you and the device's maker.

## No microphone left on

The microphone listens only while you record. Hey Ghost is heard inside a recording, as words in it, and nowhere else. Nothing listens in the background for it. Holding the side key starts a recording because Ghost.md is the phone's assistant, not because anything was listening.

## Local only

**Settings › Formatting › Local only**, in the app, keeps Ghost.md to what is already on the device. With it on:

| It stops | So |
| --- | --- |
| Update checks | The app doesn't ask whether there is a new version. |
| Model downloads | The voice model, the better-words model and the formatting models aren't fetched. Ask for the voice model or a formatting model and the app says why; the better words simply wait. |
| Sync | Nothing goes to your account, and nothing comes from it. |
| Link previews | No linked site is asked for its title. |
| Plugins that use the internet | Notion, GitHub and Claude's page are held off. |

It does not reach a few things you turn on or tap yourself:

- A shared link keeps following its note's edits. Stop the link in Settings › Account to end that.
- Live typing, if you switched it on, still runs.
- Update alerts, if you switched them on, still check in the background.
- About still reads the list of releases when you open it, and a link you tap still opens.

## What leaves only when you choose

| When you choose | What goes | Who can read it |
| --- | --- | --- |
| An account, and sync | Notes, recordings, pictures and settings, sealed on the device first | Your devices only |
| Sharing a note or a book | A sealed copy. Its key rides in the link after the `#`, which browsers never send to a server. | Anyone you give the link to |
| Live typing | What you type in a note open on two of your devices, sealed, passed through a relay that keeps nothing | Your devices only |
| Link previews | In the apps, your device asks the linked site for the page's title. Off in Settings › Type. | The site, which sees your IP address |
| Notion | Only the items you send, and the reads of their tasks, from your device straight to Notion | Notion |
| GitHub | The repo read, and the issues you make, from your device straight to GitHub with your token | GitHub |
| Claude, hosted | While connected, Ghost.md's server holds your notes' key in memory | The server, for Claude, and Claude |
| Claude, on your own computer | The key stays on your computer | Claude |

Two of those pass through Ghost.md's server on the way. **Signing in to Notion** needs a secret an app can't carry, so the server does that step and holds the sign-in in memory for up to ten minutes, until your device collects it. When Notion later asks for the sign-in to be renewed, the renewal passes through too, and is not kept. **The hosted Claude connector** keeps your key in memory only, never on disk, for about a week after you sign in, used or not. It forgets it sooner when you disconnect, when you sign out everywhere, or when the server restarts. What Claude reads goes to Anthropic, under its own terms.

**Updates and models** are plain downloads, from attack.fm, or for the models from Hugging Face when attack.fm can't be reached. Nothing about you is sent with them. The servers see your IP address.

## What the server can see

With an account, the sync service keeps:

- your handle, and when the account was made and last signed in to;
- a value made from your password so you can sign in. The app derives two keys from the password and sends only one, which is stored as a salted hash. The password itself never leaves the device;
- your notes, recordings, pictures and settings, sealed with AES-256-GCM under a key only your devices and your recovery codes can open;
- what syncing needs, which it can see: random ids for each note and file, when each changed, their sizes and how many there are, a picture's file type, and which kind of device each of yours is;
- a public key for each device, so a signed-in device can stay signed in.

It cannot see a title, a folder, a word of any note, your settings, or a second of audio. Your IP address is used briefly, in memory, to limit repeated sign-in attempts, and the web server keeps ordinary access logs.

## The web version

In a browser, Ghost.md uses the browser's own speech recognition. In Chrome, that sends your voice to Google to be turned into words. Your notes stay in that browser. The apps transcribe on the device instead.

## No ads, no tracking

There is no analytics, no crash reporting, no advertising and no tracking of any kind, and no advertising id. Nothing of yours is sold, shared, or used to train AI models.

## Deleting your account

Open **Settings › Account › Delete account**, enter your password, and tap **Delete my account**. It works from the web version too. At once and for good, it deletes your account and everything it keeps on the servers: your synced notes, their recordings and pictures, your settings, every link you have shared, your devices' keys and your recovery codes. Your other devices are signed out, and an AI assistant you connected loses access. The notes on your devices stay, because they are your own files.

Lost the password? Sign in with a recovery code under **Lost the password**, then delete. If you have lost both, the privacy policy says how to ask. Without the password or a code nobody can open the notes, the server included.

## The whole policy

The privacy policy is at **ghostmarkdown.com/privacy.html**, and **Settings › About › Privacy policy** opens it.

## Read next

- [[Accounts, sync and the key you hold]]
- [[Sharing a note or a book]]
- [[Sync and the end-to-end keys]]
