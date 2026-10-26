# Organizations and shared notes

An organization is a team in Ghost.md: a name, a colour, and people by their handle. Each member gets the organization's workspace, and a note filed there is the team's. It is on everyone's devices, open to everyone at once, and sealed with a key only members hold.

You need a Ghost.md account. Organizations are part of Advanced mode.

## Making one

1. Go to **Settings › Organizations**.
2. Under **New organization**, give it a **Name**.
3. Tap **Create**. You are its owner, and its workspace appears at once, named and coloured after it.

**New organization** is in home's filters too. **Settings › Organizations** lists **Your organizations** with your role and how many are in each, and any **Invitations** waiting for you.

There are three roles:

| Role | Can |
| --- | --- |
| **Owner** | Everything an admin can, and set roles, hand the organization over, and delete it |
| **Admin** | Rename it, change its colour, invite people, make and turn off invite links, and remove members |
| **Member** | Read, write and comment on the team's notes, and leave |

An organization has one owner. The owner makes someone an admin with **Make admin**, or back with **Make member**, on the members list. **Hand over**, pressed twice, makes someone else the owner. An admin can remove members but not other admins.

### Limits

- You can own up to 20 organizations.
- An organization holds up to 50 people, joined and invited together.
- You can invite up to thirty people an hour.

## Inviting people

### By handle

1. Open the organization and choose **Invite**.
2. Type someone's handle and tap **Invite**.

They get an invitation in their notifications, with **Accept** and **Decline** on the row. When they accept, the organization's workspace is made on each of their devices. Inviting a handle that doesn't exist says "No one has that handle." Until they accept, the members list shows them as invited, and **Withdraw** takes the invitation back.

### By link

Under **Invite by link**, under the invite on the organization's page or on **Members** in its settings:

1. Choose **New link**.
2. Choose how long it **Lasts**: **A day**, **A week**, **30 days** or **No end**.
3. Choose **Who** can join by it: **One person**, **Five**, **Twenty-five** or **No limit**.
4. Tap **Make the link**. It is copied as it is made.

Each link has **Copy the link**, **Send the link** and **Turn the link off**, and says how many have used it. Anyone signed in who has the link can join as a member, until it runs out or you turn it off, so send it only to the people it's for.

Someone who opens a link sees the organization's name, who shared the link and how many are in it, then **Join** with the organization's name, or **Not now**. Nothing is joined until they choose Join. Signed out, they are asked to sign in or sign up, and the link waits on their device until they do.

## Filing is sharing

A note filed in the organization's workspace, or in any folder inside it, is the team's. There's nothing else to press. To share a note:

1. Open it and tap **More for this note**.
2. Choose **Workspace**.
3. Pick the organization's workspace, or one of its folders. The sheet says the note is now the team's.

Once it's the team's:

- Every member can read, edit and comment on it.
- Edits made apart merge, so there's never a conflicting copy.
- It keeps a version history from the start ([[Versions and history]]).
- A new note made from the organization's page is the team's from its first word.

The organization's workspace can hold folders, like your own ([[Workspaces, folders and search]]). Folders inside it are the team's too, and every member sees the same ones. A team's note can be moved between the organization's folders freely. Deleting one of its folders and keeping the notes moves them up into the folder above, so they stay the team's.

### Taking a note from the team

A note leaves the team only when you file it in a workspace of your own (or another organization's), or delete it for good. Open **Workspace** on the note and pick your own workspace. The sheet warns that this takes the note away from everyone in the organization, and asks you to press again. The note stays on your devices as yours, and goes from everyone else's.

A note that is only unfiled is still the team's. **Take this note out of…** asks twice too, but it leaves the note in your Inbox on this device and nobody else loses it, and it goes back into the organization's workspace when the team next changes it. To share it again yourself, file it back. Ghost.md never takes a note from a team because a device can't tell where it belongs.

### The Trash and team notes

Moving a team note to the Trash puts it in your Trash only. Other members still have it. It waits there until you empty the Trash, with no thirty-day limit. Deleting it for good, from the Trash or by emptying it, deletes it for every member of the organization, and the Trash says so first.

## What the service can see

Team notes, their pictures, their recordings and their history are sealed with the organization's key before they leave the device. The service can't read a title, a word, a comment or where anyone's cursor is.

It does see the organization's name and colour, its members' handles and roles, and each person's colour, so invitations can reach people. For each team note it sees which organization it belongs to, its size, when it changed, and which account wrote each change. See [[Privacy]].

## Writing together

Open a team note while someone else has it open and you write together. Typing reaches the others as it is typed. Everyone in the note is a caret in their own colour with their handle on it, and what they select is washed in it.

There's no switch for this in an organization: it's always on. Between your own devices, the same thing is **Live typing** in Settings › Account, on unless you turn it off.

## Your colour

Your colour is how the team sees you: your caret, your selection, your comments, and your row in the members. Set it in **Settings › Account › Your colour**. For one organization, set **Your colour here** in its settings, and **Use your account's colour** goes back.

## Comments

Select some words, or put the caret on a line, and choose **Comment**. It's on the bar over a selection and in a note's More. Write the comment and tap **Add comment**.

The words are washed in the author's colour, with a small round beside them. Tap it to open the thread: read it, **Reply**, or **Resolve** it when it's settled. A resolved thread keeps its words and loses its wash, and **Reopen** brings it back.

Comments live in the note's own Markdown, so any app can read them. An anchor marks the words, and one block at the end holds every thread:

````
The venue ==needs confirming==[^c1].

```comments
c1 matt 2026-10-04T19:00:12Z
The hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall. Confirmed this morning.
  resolved sam 2026-10-04T19:06:02Z
```
````

Elsewhere, `[^c1]` reads like a footnote marker. Comments work on any note. In an organization, each one wears its author's colour.

## Recordings

A team note's recording travels with it, so every member can play the tape. A meeting's audio is other people's voices, so it is only shared while **Sync meeting recordings** is on, on the **Meetings** card in **Settings › Recording**. It is on to begin with. Off, the transcript and summary are shared, and the audio stays on the device that recorded it.

## The organization's page

Tap an organization's tile on home to open its page. On it:

- The organization's name and colour, how many are in it, and your role, with **New** and **Invite**.
- Its folders, and its notes as cards or icons.
- The members, with their roles, who is here now and what they are editing. Open someone's profile and **Jump to cursor** takes you to where they are writing.
- **Activity**, the team's news, newest first, with **Audit log** beside its heading.

The clock at the top opens the **Audit log**: every version of every note in the workspace, by who and when, with the team's news beside it ([[Versions and history]]). The cog opens the organization's settings.

An AI working through a member's Claude connector is listed under the members with an **AI** chip, showing what it is editing, with **Follow**. It is not a member and holds no key of its own. The owner, an admin, or the member it came through can **Remove** its entry. See [[Claude in Ghost.md]].

## The organization's settings

The cog on its page, or its row in **Settings › Organizations**, opens:

- **General**: its **Name** and **Colour**. The owner and admins can change them; every member sees the change, and their workspace for it is renamed with it.
- **Members**: everyone in it, with their roles, then **Your colour here**, **Invite** and **Invite by link**.
- **Workspace**: its workspace, and **Notes filed here**, which opens home with it chosen.
- **Notifications**: **Mute this organization** stops its team news (who joined, left or was removed, a rename) being shown or counted. Invitations still are. The choice follows you to your other devices.
- **Report**: **Report a member or a note** opens an email to Ghost.md's maker with the organization named. Team notes are sealed, so put the words you're reporting in the email.
- **Leave**, or for the owner, **Delete**.

With the Slack plugin, its page's **Organizations' news** can post an organization's news to a Slack channel, set on each device. See [[Plugins, one by one]].

## Leaving

**Leave organization**, in its settings, removes you. Tap it twice. Your workspace for it goes from your devices, the notes filed there stay yours, unfiled, and nothing new from the team reaches you. The others are told.

When someone leaves or is removed, the team's key is replaced at the next member's sync, so nothing new is sealed with a key they hold. They keep what their devices had already downloaded.

The owner can't leave, or delete their account, while others are in it: hand the organization over first.

## Deleting an organization

The owner's **Delete organization**, tapped twice, deletes it for good. Every member is told, and their workspace for it goes; the notes filed there stay with each of them, unfiled. Invitations waiting are withdrawn, and the team's notes, files and keys go from the service.

See also: [[Workspaces, folders and search]] · [[Versions and history]] · [[Accounts, sync and encryption]] · [[Meetings and the Meet bot]] · [[Claude in Ghost.md]]
