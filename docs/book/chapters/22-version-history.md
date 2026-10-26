# Version history

A note can keep every version of itself, like git keeps a project. You see who changed what and when, and you can go back to any version. Going back is kept as a version too, so it can be undone.

## Which notes keep versions

- **A team's note**, filed in an organization, keeps versions from the start. See [[Organizations and shared notes]].
- **A note of your own** keeps them once you switch it on. Open the note, tap **More for this note**, then **Keep version history**.

Your choice follows you to every device. Canvases don't keep versions.

## When a version is kept

A version is saved:

- after a pause in the writing, about two minutes;
- when you leave the note;
- whenever you save one by hand.

A version is never saved when nothing has changed.

To save one by hand, open **Version history** from the note's More. Type a **Name** if you like, such as "Sent to the client", then tap **Save a version now**.

## The timeline

**Version history** shows every version, newest first, on a line down the page under the day it was kept: Today, Yesterday, or the date. Each version shows:

- who made it;
- when;
- how much it changed, like `+3 −1`, or "Named" for a named version with no new words;
- the first line it changed.

Tap a version to open it. You see **What this version changed**, against the version before it. Under that, **Restoring it changes the note like this** shows what going back would do to the note as it is now. Unchanged lines are folded away, so only the changes stand out.

## Going back

Open a version and tap **Restore version** with its number. The note goes back to those words.

Before it does, the note as it is now is kept as a version. So a restore never loses anything, and you can restore your way forward again.

## The versions file

The history is kept in a file beside the note, with the same name and `.versions` at the end. It moves with the note, and syncs sealed like the note does.

It is plain text, so you can read it. Each version is a line saying its number, when, who and a short hash, and its name in quotes if it has one. Under that are the lines it took out (`-`) and put in (`+`), and how many lines it kept the same (`=N`):

```
# Ghost.md versions 1
# note 5e8f1c24-7b9a-4a3d-9c61-2d4e8f0b6a17
# A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.

v1 2026-09-26T11:03:47.000Z matt 0351c39d full
 +# Launch plan
 +
 +- [ ] Ship the pricing page ^ship-page
 +- [ ] Pick a launch date ^pick-date
v2 2026-09-29T16:20:05.000Z sam dfb138ca "Date picked"
 =3
 -- [ ] Pick a launch date ^pick-date
 +- [x] Pick a launch date ^pick-date
```

Every fiftieth version is a whole copy of the note, marked `full`. Each version is checked against its hash. If one can't be read, it is left out, and the history says how many were.

A file keeps up to a thousand versions. Past that, the oldest go first.

If two devices both kept versions of the same note, their files are merged, so none is lost.

## Sharing the history

**Share the versions file**, under the timeline, sends the file itself: to yourself, to another app, or to someone who should see how a note came to be.

## Stopping

**Stop keeping history**, at the foot of Version history, stops saving new versions. The versions kept so far stay. Switch it on again and they carry on from there.

In an organization, a note's history can be switched off the same way. The organization's audit log then says which notes have it off.

## The audit log

An organization's page has an **Audit log**, the clock at the top. It reads the version history of every note in the workspace, so it lists every change by who and when, with the team's news beside it. **What the log shows** narrows it to notes or the team, and you can filter it by a note's name. Tap a change to see what it did, and **Open the note**.

See also: [[Organizations and shared notes]] · [[Accounts, sync and encryption]] · [[Workspaces, folders and search]] · [[Settings]]
