# Import, export and backup

Your notes are Markdown files, and they're yours. This chapter covers bringing notes in from another app, taking everything out, backing up to a drive, and keeping your library in a folder of your own.

Works on: Android and Mac. The iPhone has no Library folder, Backup, Import or Export yet. These pages are part of Advanced; see [[Simple and Advanced]].

## Importing

Open Settings › Export, then **Import**. Notes from another app come into a workspace of their own, named for the day, so they can be taken out again in one go. Nothing you have is changed.

Keep Ghost.md open while an import runs. It shows how far it has got, with **Stop**.

### Obsidian vault

Tap **Obsidian vault** and choose the vault's folder. Its notes, folders, pictures, files and canvases come in as they are:

- Every note comes in word for word, with its front matter, `[[links]]` and `![[embeds]]`. Its folder comes too, inside a workspace called something like "Imported from Obsidian 2026-10-16".
- Every `.canvas` becomes a canvas. See [[Canvases, cards and lines]].
- Every attachment a note names is kept, and the note points at the kept copy. Attachments no note names are kept too, listed in one note.
- Folders starting with a dot, such as `.obsidian` and `.trash`, are left out. So is any very large file. The report at the end says what was left.

### Evernote

Tap **Evernote export (.enex)** and choose one or more `.enex` files. Each becomes a notebook, with its tags, dates, pictures and files. To make an `.enex` file, export a notebook from Evernote.

### Todoist

Add the **Todoist** plugin in the Market first. A **Todoist** card then appears on the Import page.

Each project becomes a note, its sections headings and its tasks to-dos, with their dates, priorities, labels and sub-tasks. Two ways in:

- **From your account.** Paste your API token and tap **Import from Todoist**. The token is in Todoist › Settings › Integrations › Developer. It's used for this import and not kept. Switch on **Completed tasks too** to bring in those done in the last year, ticked.
- **Todoist CSV export (.csv)**. Choose one or more projects' exports. In Todoist, a project's menu has Manage data › Export as CSV.

### Things 3

Add the **Things** plugin in the Market first. Areas become notebooks and projects their pages, with headings, to-dos, When dates, deadlines, tags, notes and checklists.

- **From Things on this Mac** reads a copy of Things' own data, every area and project. The Mac may ask first. Switch on **The Logbook too** for done and cancelled to-dos, ticked.
- **Paste from Things**: in Things, open a list and choose Share › Copy, then press here. The list becomes one note.

### A .ghostex file

**A .ghostex file** brings back an export from Ghost.md, with its workspaces, pictures and files. If it has a password, Ghost.md asks for it. If some notes are already here, choose **Skip** to leave them as they are, or **Keep copies** to bring the export's in beside them.

### Taking an import back

When an import finishes, it says what came in. **Remove this import** puts everything it brought into the Trash and takes its workspace away. You can still restore the notes from the Trash until it's emptied.

## Exporting

There are two kinds of export.

### Everything as a zip

Settings › **Export** › **Export everything** writes every note, picture, film and recording as one zip, named like `ghostmarkdown_2026-10-01_21-42-05.zip`. Choose a USB drive or any folder. On Android, plug in a USB drive and choose it in the picker.

Inside the zip:

```
Library/       Every note, as a Markdown (.md) file, in its folders.
images/        The pictures notes show.
video/         The films notes play.
recordings/    Voice notes' and meetings' recordings, as WAV.
settings.json  How the app looked and behaved, its plugins and workspaces.
manifest.json  When it was exported, and how many notes and files.
README.txt     What each folder is.
```

Open `Library/` in Obsidian or any text editor. No account, password or key is ever in it. The AI and voice models aren't either; Settings downloads them again.

### A .ghostex file

Settings › Account › **Export everything** makes one `.ghostex` file: every note, with its pictures and files, to keep or to bring into Ghost.md on another device. Notes in the Trash are never in it. You choose what else goes in:

- **Include archived notes**
- **Include organizations' notes**, which are the team's and not only yours.
- **Include recordings**: each spoken note's audio. It can make the file much larger.
- **Protect with a password**: the whole file is encrypted. Without the password nobody can open it, you included. It can't be reset.

When it's ready, **Save or send it** hands the file to your device's share sheet.

## Backup to a drive

Settings › **Backup** copies every note onto a USB drive or an SD card, as plain Markdown files.

1. Plug in a drive. The page is looking for one, and shows it by itself.
2. Tap **Back up** beside it. The first time on Android, the phone asks you to allow Ghost.md to use the drive.
3. Keep the drive plugged in until it's done. On a Mac, **Eject** is right there afterwards.

Everything goes into a `Ghost.md` folder at the top of the drive, with `Inbox/` for notes in no workspace, `Workspaces/`, `Organizations/` and `Attachments/`. Each note's version history sits beside it. The next backup to the same drive only writes what changed. A note you've deleted is taken off at the next backup; nothing else on the drive is ever touched.

Under the drives, each backup is shown as a tree you can open.

Backup isn't in the Mac App Store's version of Ghost.md. Use Export there instead.

## A library folder of your own

Settings › **Library folder** lets you keep your notes in a folder you choose: an Obsidian vault, iCloud Drive or Dropbox, a Syncthing folder. Each note is a Markdown file, in a folder for its workspace, so any app that opens a folder of Markdown opens these.

Tap **Choose a folder…**, pick one, then **Use it**. Ghost.md moves your notes in and tells you when they're there.

Good to know:

- **A folder on the phone is the reliable one.** Syncthing keeps one in step with a computer. Dropbox and Google Drive reach Ghost.md through their own apps, which may keep a note online only and open it slowly.
- **iCloud Drive** has no Android app, so choose it on the Mac.
- **Obsidian:** notes keep their names and properties when Ghost.md edits them, so links still find them. `.obsidian` and its trash are left alone.
- **What stays in Ghost.md:** pictures, films and recordings, and the index that makes the list instant. They never go in your folder, so a sync service never copies half of it.
- Ghost.md keeps a small `.glyph` folder in yours, for things a note has that aren't words.

If the folder can't be reached, say a drive is unplugged or a permission taken back, Ghost.md uses its own folder until it's back. Your notes in the folder are untouched.

To go back, choose **Use Ghost.md's own folder**: **Bring a copy back**, or **Start empty**. Ghost.md never deletes anything in a folder of yours.

See also: [[Accounts, sync and encryption]] · [[Workspaces, folders and search]] · [[The Market]] · [[Plugins, one by one]] · [[Versions and history]] · [[Settings]]
