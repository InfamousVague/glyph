# Troubleshooting

Most problems have a quick fix. Find yours below. If it isn't here, the last section says where to get help.

A good first step for almost anything: check **Settings › About** for an update, and check that **Local only** is off in **Settings › Account › Privacy** if something should be reaching the internet.

## Updates

### Android

Ghost.md downloaded from ghostmarkdown.com updates itself. It looks for a new version a few seconds after it starts, when you come back to it, and every couple of minutes while it's open. When one is out, a card above your notes says "Ghost.md … is out." with **Install**.

- **"Let Ghost.md install apps, then come back."** Android needs your permission the first time. Tap **Install**, allow installs from Ghost.md in the screen Android opens, then come back and tap **Install** again.
- **"Ghost.md … is waiting on Android."** Android's own installer is open, or was dismissed. Tap **Open**, then **Update**.
- **"… didn't install."** Tap **Try again**. If it keeps failing, download the newest version from ghostmarkdown.com and install it over the top. Your notes stay where they are.
- **Nothing happens.** Open **Settings › About** and tap **Check for updates**. Updates are off while Local only is on.

### Mac

From version 2.3.16, the Mac app updates itself. When a new version has downloaded, a card says "Ghost.md … is ready." with **Restart to update**, and About says the same. Restart, or simply quit: the next launch is the new version, and its launch screen says "Updated to Ghost.md …". It won't restart while a meeting or a recording is running.

- **Version 2.3.15 or older** has no updater. Download the disk image from ghostmarkdown.com once, and drag the app over the old one. From then on it updates itself.
- **It can't replace itself** if it is running from the disk image, from your Downloads folder, or from a folder your account can't write to. It says why, and opens the disk image in your browser. Drag Ghost.md into Applications and open it from there.
- **macOS says it can't check the app** on first open: choose **Done**, then open **System Settings › Privacy & Security** and choose **Open Anyway**. On macOS 14 or older, Control-click Ghost.md and choose **Open**. You only do this once.
- The **Mac App Store** version is updated by the App Store.

### Windows

The Windows app isn't signed yet. The first time you open the installer, Windows says it protected your PC. Choose **More info**, then **Run anyway**.

### iPhone

The iPhone app updates through the App Store.

## The microphone

- **Nothing is heard, or "Permission denied".** Ghost.md needs the microphone. On Android, open the phone's Settings › Apps › Ghost.md › Permissions › Microphone and allow it. On a Mac, open System Settings › Privacy & Security › Microphone and switch Ghost.md on.
- **"This device has no microphone Ghost.md can open."** Plug in or choose a microphone, then try again.
- **"The microphone could not be opened."** Another app may be using it, such as a call. Close it and try again.
- **On a Mac, the other side of a call is missing.** Switch on **Include sound from other apps** in **Settings › Recording**. macOS asks the first time.
- **The iPhone doesn't record.** The iPhone app is notes only for now.

The microphone is only ever open while you are recording.

## Models

Ghost.md turns speech into words and formats notes with models that run on your device. They download once.

- **"The voice model didn't download."** Tap **Try again**. Check your connection. Models come from attack.fm, or from Hugging Face if attack.fm can't be reached.
- **"Local only is on, so nothing is downloaded."** Turn Local only off, download the model, then turn it back on if you like. The model stays.
- **A download stalls.** Keep Ghost.md open while it downloads. The formatting model is large, so use Wi-Fi.
- **Choose or remove a model** in **Settings › AI › Model**.
- **"… can't run in this version of Ghost.md."** Choose another model in **Settings › AI**, or update the app.

## Sync not arriving

Open **Settings › Account** and read the line under your handle.

| It says | Do this |
|---|---|
| Waiting to sync | Tap **Sync now**. |
| Sign in again to sync | This device no longer holds your key. Sign out, then sign in again. |
| Sync needs the newest Ghost.md. | Update the app on this device. |
| Synced 2 min ago, but something's missing | The other device may not have synced yet. Open Ghost.md there and tap **Sync now**. |

Also check:

- **Local only** is off, on both devices. It stops sync until it's off.
- **Both devices are signed in to the same handle.**
- **"A note was changed on two devices at once."** Nothing is lost: both versions are kept as separate notes. Merge them by hand and delete the one you don't need.
- **Some changes weren't sent.** The page says so, with the reason. They are sent again next time.
- **A plugin's key is missing on a new device.** Check **Keep keys and connections in sync** is on. Notion's sign-in doesn't travel: sign in to Notion on each device.

## "This recording is not on this device."

The words of the note are here, but its audio stayed on the device that made it. That happens when:

- **It is a meeting, and Sync meeting recordings is off.** Turn it on in **Settings › Meetings**, then open Ghost.md on the device that recorded it and let it sync.
- **It is longer than about 2 hours 19 minutes**, the most a recording can be to sync. Play it on the device that made it.
- **The audio was removed** by **Remove audio older than a month** in **Settings › Recording**. Then it says "The audio was removed." The words stay; the sound can't come back.

**Settings › Meetings** says how many recordings stayed on this device, and why.

## A plugin is held off by Local only

With **Local only** on, every plugin that uses the internet is held off. In the Market such a plugin wears a **Local only** tag, and the Market says "Local only is on, so plugins that use the internet are held off until it is off." Its Settings page is gone until then.

Tap **Local only** in that message to go to the switch, in **Settings › Account › Privacy**. Turn it off and the plugins come back as they were. Marks, Contacts, Place reminders and Things keep working either way.

## A plugin isn't there

- **Simple mode** hides the Market and every plugin's settings. Switch to Advanced in **Settings › Appearance › Mode**.
- **Not added**: open the Market and tap **Add to Ghost.md**.
- **Not on this device**: Notion and Slack aren't on the iPhone yet; Place reminders is Android only; Todoist and Things are Android and Mac. The plugin's Market page says where it works.
- **"… needs the newest Ghost.md."** Update the app.

## Lovart errors

| It says | Do this |
|---|---|
| Add your Lovart keys in Settings › Lovart first. | Paste your access key and secret key and tap **Keep them**. |
| Lovart didn't accept these keys. | Copy both again from your Lovart avatar menu › AK/SK Management. |
| Lovart says your plan or credits don't cover this. | Add credits or change plan in Lovart. |
| Lovart wants your go-ahead before a costly step. | Ghost.md never approves these. Approve it in Lovart, or reword the cue. |
| Lovart is asking this device to slow down. | Wait a minute and try again. |
| Lovart made no image: … | Lovart declined the prompt. Change the words. |
| Lovart took more than 5 minutes. | What it made is in your Lovart project. |

If the mark doesn't appear beside a `{image: …}`, check the plugin is added, the `}` is there and the prompt has words. See [[Lovart]].

## Where to get help

- **In the app**: **Settings › About › Help** has the **Ghost.md Academy**, **The welcome walkthrough** and the **Cheat sheet**.
- **This book**: [[Welcome to Ghost.md]] is the start.
- **Write to us** at the address under Contact on https://ghostmarkdown.com/privacy.html. Say what you did, what you expected and what happened, and include the version from **Settings › About** and the **This build** card there.

See also: [[Install Ghost.md]] · [[Accounts, sync and encryption]] · [[The Market]] · [[Lovart]] · [[Settings]]
