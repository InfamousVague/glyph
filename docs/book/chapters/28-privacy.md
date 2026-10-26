# Privacy

Ghost.md is built so that your notes stay yours. This chapter sums up the privacy policy. The policy itself is the one that counts: read it at https://ghostmarkdown.com/privacy.html. It covers the Ghost.md apps for Android, iPhone and Mac, the web version, and the ghostmarkdown.com site.

## The short version

- **Your notes are files on your device.** You don't need an account.
- **In the apps, your voice is turned into text on your device.** It isn't sent anywhere to be transcribed.
- **If you make an account to sync, everything is encrypted on your device before it is sent**, so the service can't read it.
- **If you join an organization**, its name and members are kept in the clear so teammates can be invited by handle. Notes you file in it are shared with its members, encrypted so only they can read them. Your other notes stay yours alone.
- **No ads, no analytics, no tracking.** Your data is never sold or shared, and never used to train AI models.
- **You can delete your account**, and everything it keeps on the servers, from the app at any time.

## On your device

Your notes, their recordings and their pictures are stored on your device as plain Markdown files and the files beside them. Transcription and formatting run on your device, with models the app downloads once. Nothing that stays on your device can be seen by anyone else.

Your device's own backup, such as Android's backup to your Google account, may include the app's files. That is between you and your device's maker.

## With an account

The sync service stores:

- **Your handle**, and when the account was made and last signed in to.
- **A value made from your password**, so you can sign in. Your password never leaves your device. The app makes two keys from it and sends only one, which is stored as a salted hash. The other, which unlocks your notes, stays on your devices.
- **Your synced notes, recordings, pictures and settings**, encrypted on your device (AES-256-GCM) with a key only your devices and your recovery codes can open.
- **What's needed to sync**: random ids for each note and file, when each changed, their sizes and how many there are, a picture's file type, and which kind of device each of yours is.
- **A public key for each of your devices**, so they can stay signed in.

Your IP address isn't stored with your account. It is used briefly, in memory, to limit repeated sign-in attempts. The web server keeps ordinary access logs for security and troubleshooting.

See [[Accounts, sync and encryption]].

## Organizations and notifications

For each organization, the service can see its name and colour, its owner, when it was made, and who is in it by handle, with each person's role and who invited them. Inviting a handle tells you whether it exists ("No one has that handle."), limited to thirty invitations an hour.

Team notes are encrypted with a key held only by the organization's members. The service can't read their titles, words, comments, pictures or version history. It can see which organization a note belongs to, its size, when it changed and which account wrote each change. While team notes are edited live, it can see who has which note open, but not what is typed.

Of your notifications, the service can read the ones it writes itself, such as an invitation. The ones about your own notes, such as a note Claude edited or a meeting written up, are encrypted like a note.

Someone who leaves an organization loses access at once, and the team's notes are re-encrypted under a new key. They keep what their devices already downloaded. Because team notes can't be read by the service, they aren't reviewed: share only with people you trust. You can report a member from the organization's settings, under Report.

## Shared links and sites

A shared note is encrypted, and the key is in the link after the `#`, which browsers don't send to servers. Anyone you give the link to can read it. You can stop a link at any time in **Settings › Account**. See [[Sharing and published sites]].

## Live typing

Live typing passes what you type between your devices through the service as you type it, encrypted the same way as your notes, and not stored.

## Connecting an AI assistant

If you connect an assistant such as Claude through the hosted connection, you sign in on a page that gives the server your notes' key for the length of that connection, so it can read and write your notes when the assistant asks. The key is held in memory, and on disk only sealed, openable only with a token the assistant holds. It is forgotten when you disconnect, when you sign out everywhere, or after 7 days without use. What the assistant reads goes to its maker, under their privacy policy. Notes the assistant writes are marked with its name.

## Plugins

Plugins are optional, and each one's Market page says what it may reach. The policy names two:

- **Notion**: your device talks to Notion directly, sending the tasks you choose. Signing in passes through the server, which holds the sign-in in memory for up to ten minutes until your device collects it.
- **GitHub**: your device talks to GitHub directly, with the token you give it.

What you send to any service is covered by that service's own policy. See [[Plugins, one by one]].

## Links, places, blanks and downloads

These are the few times your device talks to someone else, each with its own switch:

- **Link previews**: your device fetches the linked page to show its title. The site sees your IP address. Turn it off in **Settings › Account › Privacy**.
- **Where a note was written**: a new note starts with where you are, once you allow it. Finding that asks your device's location service. Turn off **Tag new notes with my location** in **Settings › Account › Location**, on each device. Notes you already have are never tagged.
- **Maps and place names**: a tagged note's map is drawn with tiles from openstreetmap.org, and the place's name is asked of OpenStreetMap once. Those servers see your IP address and the coordinates asked about. Each has its own switch under **Location**.
- **Blanks the AI fills**: a question like `{?weather tomorrow}` is answered on your device. When it needs something live and you press Fill, your device asks one public source directly (Open-Meteo, Frankfurter or Wikipedia), sending only the question. Turn off **Look up blanks online** under **Privacy**.
- **Updates and models**: the apps check for updates and download models from attack.fm, or from Hugging Face if that can't be reached. No account or device id is sent.

**Local only** stops all of these at once.

## The web version

In a browser, Ghost.md uses the browser's own speech recognition. In Chrome, that sends your voice to Google. The apps transcribe on your device instead.

## Deleting your data

Open **Settings › Account › Delete account** and enter your password. At once and for good, it deletes your account and everything it keeps: synced notes, recordings, pictures, settings, shared links, devices, recovery codes, notifications and your place in every organization. Your other devices are signed out. The notes on your device stay, because they're your files. Without an account, nothing of yours is on the servers, and uninstalling the app removes its files from your device.

Ghost.md isn't directed at children under 13.

## Questions

For a question about privacy, or a request about your data, write to the address under **Contact** at https://ghostmarkdown.com/privacy.html. In the app, **Settings › Account › Privacy › Privacy policy** opens the same page.

See also: [[Accounts, sync and encryption]] · [[Sharing and published sites]] · [[Settings]] · [[AI on your device]]
