# Organizations and shared notes

An organization is a team in Ghost.md: a name, a colour, and people by their handle. Each member gets the organization's workspace, and a note filed there is the team's. It is on everyone's devices, open to everyone at once, and sealed with a key only members hold.

You need a Ghost.md account. Organizations are part of Advanced mode.

## Making one

Go to **Settings › Organizations** and choose **New organization**. Give it a name. Its workspace appears at once, named and coloured after it.

There are three roles:

- The **owner** renames the organization, changes its colour, sets roles, hands it over and deletes it.
- An **admin** invites people and removes members.
- A **member** reads and writes the team's notes, and can leave.

## Inviting people

Open the organization and choose **Invite**. Type someone's handle. They get an invitation in their notifications, with **Accept** and **Decline** on the row. When they accept, the organization's workspace is made on each of their devices.

Or send a link. Under **Invite links**, choose how long it lasts and how many people can join by it, then make it. The link is copied as it is made. Each link has Copy, Send and Turn off, and says how many have used it.

Someone who opens a link sees the organization's name, who made the link and how many are in it, then **Join** or **Not now**. Nothing is joined until they choose Join. Signed out, the link waits on their device until they sign in.

## Filing is sharing

A note filed in the organization's workspace, or in any folder inside it, is the team's. There's nothing else to press. To share a note, open it, tap **More for this note**, then **Workspace**, and pick the organization.

- Every member can read and edit it.
- Edits made apart merge, so there's never a conflicting copy.
- Trashing it trashes it for everyone.
- Taking it out of the organization takes it from the team. The Workspace setting asks twice before it does.

A new note made from the organization's page is the team's from its first word.

The organization's workspace can hold folders, like your own ([[Workspaces, folders and search]]). Folders inside it are the team's too, and every member sees the same ones. A team's note can be moved between the organization's folders, but not out into a personal folder by drag.

Team notes, their pictures, their recordings and their history are sealed with the organization's key before they leave the device. The service can't read a title, a word, a comment or where anyone's cursor is. It does see the organization's name and colour, and members' handles, so invitations can reach people.

## Writing together

Open a team note while someone else has it open and you write together. Typing reaches the others as it is typed. Everyone in the note is a caret in their own colour with their handle on it, and what they select is washed in it.

There's no switch for this in an organization: it's always on. (Between your own devices, the same thing is a trial, **Live typing** in Settings › Account.)

## Your colour

Your colour is how the team sees you: your caret, your selection and your comments. Set it in **Settings › Account › Your colour**. For one organization, set **Your colour here** on its page. Without one, you are the app's ink.

## Comments

Select some words, or put the caret on a line, and choose **Comment**. It's on the bar over a selection and in a note's More. Write the comment and add it.

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

A team note's recording travels with it, so every member can play the tape. A meeting's audio is other people's voices, so it is only shared when **Sync meeting recordings** is on in Settings › Meetings. Off, the transcript and summary are shared, and the audio stays on the device that recorded it.

## The organization's page

Tap an organization's card on home to open its page. On it:

- The organization's name and colour, how many are in it, and your role, with **New** and **Invite**.
- Its folders, and its newest notes as cards or icons.
- The members, with their roles, who is here now and what they are editing. Open someone's profile and **Jump to cursor** takes you to where they are writing.
- **Activity**, the team's news, newest first.

The clock at the top opens the **Audit log**: every version of every note in the workspace, by who and when, with the team's news beside it. The cog opens the organization's settings: its name, colour, members, invite links, notifications, and **Leave organization** or, for the owner, **Delete organization**.

An AI working through a member's Claude connector is listed under the members with an **AI** chip, showing what it is editing, with **Follow**. See [[Claude in Ghost.md]].

## Version history

Team notes keep their version history from the start, so you can see who changed what and go back. See [[Version history]].

## Leaving

**Leave organization**, in its settings, removes you. Its workspace goes from your devices, and nothing new from the team reaches you. The owner can't leave or delete their account while others are in it: hand the organization over first. When someone leaves, the team's key is replaced, so nothing new is sealed with a key they hold.

See also: [[Workspaces, folders and search]] · [[Version history]] · [[Accounts, sync and encryption]] · [[Meetings]] · [[Claude in Ghost.md]]
