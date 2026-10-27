# Privacy

Ghost.md is built so that your notes stay yours. This chapter says what stays on your device, what the service keeps, and what goes to other services when you use the features that need them. The privacy policy itself is the one that counts: read it at https://ghostmarkdown.com/privacy.html.

## The short version

- **Your notes are files on your device.** You don't need an account.
- **In the apps, your voice is turned into text on your device.** It isn't sent anywhere to be transcribed.
- **If you make an account to sync, everything is encrypted on your device before it is sent**, so the service can't read it.
- **If you join an organization**, its name and members are kept in the clear so teammates can be invited by handle. Notes you file in it are shared with its members, encrypted so only they can read them. Your other notes stay yours alone.
- **Two features are read by the service in passing**: mail sent to your note address, and the link and title of a meeting you invite Ghost to. Both are below.
- **Plugins talk to other services only when you add them.** Claude, Lovart, Slack, Discord, Notion, GitHub and the calendars each send what you ask them to, to that service.
- **No ads, no analytics, no tracking.** Your data is never sold or shared, and never used to train AI models.
- **You can delete your account**, and everything it keeps on the servers, from the app at any time.

## On your device

Your notes, their recordings and their pictures are stored on your device as plain Markdown files and the files beside them. Transcription and formatting run on your device, with models the app downloads once. Nothing that stays on your device can be seen by anyone else.

Your device's own backup, such as Android's backup to your Google account, may include the app's files. That is between you and your device's maker.

## With an account

The sync service stores:

- **Your handle**, and when the account was made and last signed in to.
- **A value made from your password**, so you can sign in. Your password never leaves your device. The app makes two keys from it and sends only one, which is stored as a salted hash. The other, which unlocks your notes, stays on your devices.
- **Your recovery codes**, only as hashes, each with your account's key locked under it. The codes themselves never reach the service.
- **Your synced notes, recordings, pictures, version history and settings**, encrypted on your device (AES-256-GCM) with a key only your devices and your recovery codes can open.
- **Your keys and connections**, while **Keep keys and connections in sync** is on: your Claude key, your Slack and Discord channels, your GitHub token and your Lovart keys, each sealed on its own inside your encrypted settings.
- **What's needed to sync**: random ids for each note and file, when each changed, their sizes and how many there are, a picture's file type, and which kind of device each of yours is.
- **A public key for each of your devices**, so they can stay signed in, and an encryption public key for your account, so sealed things can be sent to you.

Your IP address isn't stored with your account. It is used briefly, in memory, to limit repeated sign-in attempts. The web server keeps ordinary access logs for security and troubleshooting.

While the app is open, the service can tell your device that something new has arrived for it (a meeting, a mail, a recording), so it syncs at once. That message says only what kind of thing it is.

See [[Accounts, sync and encryption]].

## Organizations and notifications

For each organization, the service can see its name and colour, its owner, when it was made, and who is in it by handle, with each person's role, who invited them, and each member's chosen colour. Inviting a handle tells you whether it exists ("No one has that handle."), limited to thirty invitations an hour.

Team notes are encrypted with a key held only by the organization's members. The service can't read their titles, words, comments, pictures, recordings or version history. It can see which organization a note belongs to, its size, when it changed and which account wrote each change. While team notes are edited live, it can see who has which note open, but not what is typed.

An AI that has reached an organization's notes through a member's Claude connector is listed by name beside the members, with the member it came through and when it was seen.

Of your notifications, the service can read the ones it writes itself, such as an invitation. The ones about your own notes, such as a note Claude edited or a meeting written up, are encrypted like a note.

Someone who leaves an organization loses access at once, and the team's notes are re-encrypted under a new key. They keep what their devices already downloaded. Because team notes can't be read by the service, they aren't reviewed: share only with people you trust. You can report a member from the organization's settings, under Report.

## Shared links and sites

A shared note or a published site is encrypted, and the key is in the link after the `#`, which browsers don't send to servers. Anyone you give the link to can read it. A site's page names are in its addresses, so the web server sees those. You can stop a link or unpublish a site at any time in **Settings › Account**. See [[Sharing and published sites]].

## Live typing

Live typing passes what you type between your devices through the service as you type it, encrypted the same way as your notes, and not stored.

## Email to a note

With **Email to a note** on, in **Settings › Account**, you have a private address. Mail sent to it arrives at the service as plain mail, as at any mail server. In the same moment, the service seals it to your account and keeps only the sealed copy, until your next sync files it as a note. The plain copy is never written to disk or to a log.

The address itself is kept in the clear, so the service can find whose a mail is. An address you give up is never given to anyone else. Anyone who has the address can send to it: **Make a new address** replaces it, and **Turn off** stops it. See [[Email to a note]].

## Meetings: Google Meet, Zoom and Discord

When you invite Ghost to a Google Meet or a Zoom meeting, by your address or with **Join**, Ghost joins as a guest from Ghost.md's server and says in the meeting's chat that it is taking notes. When you ask it into a Discord voice channel with `/ghost join`, it joins that call and posts a notice in the channel's chat as it starts recording.

- **What is kept in the clear, and how long**: the meeting's link, title, start and end, because the bot that joins has no key. The organizer and the guest list are read and dropped. The title and link are blanked an hour after the meeting ends, and the booking is deleted thirty days after. A recurring meeting keeps its link and title while it has meetings to come.
- **The recording and the captions** are sealed to your account the moment they reach the service, and only the sealed copy is kept, until your device fetches it. The service can't open it. One of your devices then turns it into a transcript and a write-up, on the device, or through Claude if you use Claude for write-ups.
- **Discord**: linking Discord keeps your Discord user id and the name you had then, in the clear, so the bot knows whose account a call is for. The link code is kept only as a hash, for ten minutes. **Unlink** removes the link.
- **Which kinds Ghost joins** (Google Meet, Zoom, Discord) is kept as a plain setting, so the service can turn away an invitation of a kind you've switched off.

A meeting's recording is other people's voices. Tell the people in it that Ghost is recording, and turn **Sync meeting recordings** off, on Settings › Recording's **Meetings** card, if the audio should stay on the device it was made on. See [[Meetings and the Meet bot]].

## Connecting an AI assistant

If you connect an assistant such as Claude through the hosted connection, you sign in on a page that gives the server your notes' key for the length of that connection, so it can read and write your notes when the assistant asks. The key is held in memory, and on disk only sealed, openable only with a token the assistant holds. It is forgotten when you disconnect, when you sign out everywhere, or after 7 days without use. What the assistant reads goes to its maker, under their privacy policy. Notes the assistant writes are marked with its name.

## Plugins

Plugins are optional, and each one's Market page says what it may reach. **Local only** holds every plugin that uses the internet. What you send to any service is covered by that service's own policy. See [[Plugins, one by one]].

- **Claude, in the app**: your device asks Anthropic's API directly with your own key. No Ghost.md server stands between. What goes is what you ask about: your question and the notes it needs, and, if Claude writes up your meetings, a meeting's transcript.
- **Lovart**: your device asks Lovart directly with your keys. It sends a cue's words; for inspiration images, a note's title and its summary or opening; and for header images, a note's title and its first 900 characters. Header images are on by default once Lovart is added, and a note of 25 words or more gets one when you leave it, so turn **Header images for notes** off in **Settings › Lovart** if you'd rather choose. **Make them**, beside **Header images for recent notes**, sends up to 100 notes' openings at once, only when you press it. See [[Lovart]].
- **Slack and Discord**: your device posts the note, or a meeting's action items, to the channel's webhook you added.
- **Notion**: your device talks to Notion directly, sending the tasks you choose. Signing in passes through the server, which holds the sign-in in memory for up to ten minutes until your device collects it.
- **Google Calendar**: signing in passes through the server the same way. Your device then reads your calendars from Google itself. A calendar's address you add is read by your device directly.
- **GitHub**: your device talks to GitHub directly, with the token you give it.
- **Webhooks**: an outgoing webhook is posted by your device to the address you gave it. An incoming webhook's name and the note it adds to are kept in the clear; what is posted to it is sealed to your account at once and kept until your device adds it, or for thirty days.

## Links, places, blanks and downloads

These are the few other times your device talks to someone else, each with its own switch:

- **Link previews**: your device fetches the linked page to show its title. The site sees your IP address. Turn **Link previews** off in **Settings › Account › Privacy**.
- **Where a note was written**: a new note starts with where you are, once you allow it. Finding that asks your device's location service. Turn off **Tag new notes with my location** in **Settings › Account › Location**, on each device. Notes you already have are never tagged.
- **Maps and place names**: a tagged note's map is drawn with tiles from openstreetmap.org, and the place's name is asked of OpenStreetMap once. Those servers see your IP address and the coordinates asked about. **Map on a tagged note** and **Place names** are each a switch under **Location**.
- **Blanks the AI fills**: a question like `{?weather tomorrow}` is answered on your device. When it needs something live and you press Fill, your device asks one public source directly (Open-Meteo, Frankfurter or Wikipedia), sending only the question. Turn off **Look up blanks online** under **Privacy**.
- **Updates and models**: the apps check for updates and download models from attack.fm, or from Hugging Face if that can't be reached. No account or device id is sent.

**Local only** stops all of these at once, and sync with them.

## The browser version

A browser version of Ghost.md is coming back. This chapter will say what it does once it's here.

## Deleting your data

Open **Settings › Account › Delete account** and enter your password. At once and for good, it deletes your account and everything it keeps: synced notes, recordings, pictures, settings, shared links and sites, your mail address and mail waiting, your meetings and recordings waiting, your Discord link, your webhooks, devices, recovery codes, notifications and your place in every organization. Your other devices are signed out. The notes on your device stay, because they're your files. Without an account, nothing of yours is on the servers, and uninstalling the app removes its files from your device.

Ghost.md isn't directed at children under 13.

## Questions

For a question about privacy, or a request about your data, write to the address under **Contact** at https://ghostmarkdown.com/privacy.html. In the app, **Settings › Account › Privacy › Privacy policy** opens the same page.

See also: [[Accounts, sync and encryption]] · [[Sharing and published sites]] · [[Settings]] · [[AI on your device]]
