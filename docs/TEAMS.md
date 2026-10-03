# Organizations, invitations and notifications

A team in Ghost.md is an **organization**: a name, a hue, and people by handle, each with a role. Anyone in one can
be invited by handle, and the invitation arrives as a **notification**, with Accept and Decline on the row. The same
feed carries what the service knows about a team (who joined, who left, a rename) and what only the account knows
about itself (Claude edited a note, a meeting was written up, a note was kept twice by a sync). Matt's brief
(2026-10-02): "build the ability to create teams in the app. We should be able to create an organization in order to
add users as team members by handle, adding a team member should show them an invite, while doing this also
implement a full notification system and put the invites in there with an inline accept and deny also wire up
existing features to notifications where it makes sense so that we see things like claude creating a new note or
making edits etc, there should be a notifications section in settings in order to customize the notifications we
receive. There should be a way to view an organization. Organizations should also get their own workspace
automatically, when on the organization view make a new settings screen copying the same layout and stuff from the
normal settings page but make it tailored towards organization features."

The spelling is **organization**, Matt's word and the app's (Summarize); the code says `org`, `orgs`,
`Organization*`. The decisions and their reasons are DESIGN §170 (Notifications), §171 (Organizations) and §175 (an
organization's dashboard). This page
says what is true of the code: the server under `server/src/orgs.rs`, `notifications.rs` and their stores, the
client under `src/app/core/orgs/` and `src/app/core/notifications/`, the MCP server's part in `mcp/`.

## The model

**An organization** is a row on the service - id, name, hue, who owns it, when it was made - and a row per person in
it. A person's row has a role, a state, who invited them and since when. The service makes the id: 22 base64url
characters, as a share's id is made.

**Three roles, one invariant.** Owner, admin, member. The owner renames, re-hues, deletes, sets roles and hands the
organization over; an admin invites, and removes members and invitees; a member leaves. The one rule the store keeps
and nothing else may break: **an organization has exactly one owner row, with state `member`, at all times.** So
nobody removes the owner ("Hand the organization over first."), an admin cannot remove an admin ("Only the owner can
remove an admin."), the owner's role changes only by handing over - `role: 'owner'` set on a member, in one
transaction that makes the old owner an admin - and a hand-over to someone who has not joined is refused ("They have
not joined yet."). An organization can therefore always be renamed, handed over or deleted by someone, and the rule
on deleting an account (below) always has an owner to hold to.

**An invitation** is a person's row with state `invited`, and the one place a signed-in account learns whether a
handle exists: inviting a handle nobody has answers 404 "No one has that handle." (a handle that cannot be a handle
gets the same words). The ways in never say that (`server/src/accounts/ways_in.rs`), so this is limited to thirty an
hour per inviting account and per address, and this page says so under "What the server can see". The invitee's
row and their `invite` notification are written in the invitation's transaction. Inviting someone already invited
refreshes the row's `since` and `invited_by` and writes nothing new to their feed. Declining keeps the row, with
state `declined`, for a day, so the same organization cannot ask again at once ("They declined; ask again
tomorrow."); after that a new invitation flips the same `invite` notification back to pending, unread and unhidden,
with a new revision - one `invite` row per person per organization, ever. A declined row counts toward nothing: not
the organization's fifty, not the deletion rule, not the list. Withdrawing an invitation (DELETE on an invited row)
settles the invitee's notification as declined and hidden, and tells nobody else.

**The organization's workspace** is on every member's device the moment they join, named after the organization and
in its hue, with the id `org-<orgId>` (the id is the truth: `isOrgWorkspace` reads the prefix, since an older build
rewriting the settings keeps `id`, `name` and `hue` and drops any other field). It is reconciled against the
service's list after each pass that gets one, over rows with state `member` only: made on joining, renamed and
re-hued with the organization, dropped when the person leaves, is removed, or the organization is deleted - its notes
unfiled, never deleted. On disk its folder is `orgs/<name>`, beside `workspaces/<name>`, so a personal workspace of
the same name collides with nothing; `addWorkspace` dedupes names among personal workspaces only, and an organization's
pill, chip and folder row carry `data-org` and a small mark before the name. Its hue follows the organization and is
set in the organization's General section; the personal swatch is not offered for it, and Rename and Remove refuse it.

**Not shared yet.** Notes stay per account and end-to-end encrypted, so in this slice the workspace is one each member
has, not a shared store: a note filed in it is the person's own, and nobody else in the organization sees it. The
Workspace section and the Members hero say so in Matt's register: "Notes filed here stay yours for now; sharing them
with the team comes next." Sharing needs an organization key wrapped per member under a new per-account encryption
key (only Ed25519 signing keys exist today), which is the follow-up.

**Leaving and deleting.** A member removing their own handle is leaving: the row goes, every remaining member is told
(`member-left`), and the workspace is dropped on their devices with its notes unfiled. The owner deleting the
organization settles every pending invitation (declined, hidden), tells every member (`org-deleted`), and the rows go
with it. **Deleting an account** is refused, inside `delete_account`'s own transaction, while the account owns an
organization anyone else is in, joined or invited: 403 "Hand over or delete your organizations first.". An
organization whose only row is its owner's goes with the account. In that same transaction every organization the
account had joined is told it left (`member-left`, `from` null, the handle in the body), and its own rows and
notifications cascade.

**The one who did it is not told.** As the app toasts a voice command rather than recording it, the service writes a
rename, a removal or a deletion to the other members only; who accepted is told nothing of their own acceptance; the
asker hears `invite-accepted` and everyone else `member-joined`, so nobody gets two rows for one event. A person's
other devices learn from the organization itself, through the list.

## Notifications

**One table, two shapes.** A row the service writes - an invitation, a team change - carries its kind, who caused it
(`from`, a handle), the organization and a small plaintext `body`, because the service is the one that knows, and
another account caused it. A row a device writes about its own account - Claude's writes through the MCP server, a
summary written, a conflict kept - carries a `blob` sealed under the account key with `notification:<id>` as its
associated data, whose payload is `{ kind, ...details }`: the kind inside the seal is the one trusted, so nothing
outside it can relabel a row; the plaintext `kind` column is for the service's pruning and limits, and the device's
unread count, which never opens a seal.

**The feed rides the account's one write counter**, `accounts.rev`, as notes and settings do. Every change to a row -
read, hidden, an invitation answered - takes a new revision inside its transaction and the row is fed again, hidden
rows included (as deletions ride the notes feed); a device applies a fed row only when its revision is above the copy
it holds. So a row read on the phone is read on the Mac by its next pass. Pruning orders by `created_at`, never by
revision, which a read mark changes.

**The sync pass** pulls notifications first, then notes, then settings, then the organizations (`core/sync/engine.ts`
`once`): notifications before notes so a note a notification names has arrived by the time its row is drawn;
organizations after the settings and outside `applyingRemote`, so the workspace the list makes or drops is pushed a
moment later. The feed is fetched again at once after an inline answer and when the notifications drawer opens
(`syncNotificationsNow`, the same one-at-a-time door, without the notes). There is no live-relay nudge in this slice,
and nothing fetches while the app is closed.

**What the person does here** - mark read, mark all read, hide, answer an invitation - is applied at once and queued
as a mark, replayed at the start of the next pass and dropped when the service confirms it; while a mark is pending
the local state wins over any fed row that still lacks it. "Mark all read" carries this device's cursor, so it marks
only what was shown. An answer the service refuses as "You were not invited." was given elsewhere already: the mark
is dropped and the feed fetched again.

**A sealed row is opened lazily**, at draw time, memoised by id, never in the pass. One that will not open - sealed by
a newer build, say - is drawn by its kind alone ("Claude edited a note") and never stalls the feed. A row the device
made itself (`record`) is in the feed before its post is made, at revision 0, and stays listed as unsent until the post
lands; the next pass tries again, and the post is idempotent.

**Preferences** are four switches - team, claude, summaries, conflicts - and `mutedOrgs`, synced with the person's
other settings (`preferences.notifications`, in `SYNCED_PREFS`), all on and empty by default. Every row is still
written; the page filters with `isWanted`. **An invitation is not switchable**: it always reaches the feed and the
bell, since the person who sent it is waiting for an answer. There is no phone row: the host has no `notify()` and
nothing syncs while the app is closed, so the pane's footer says "Ghost.md looks when it opens; the bell shows what
arrived." The native piece is a follow-up.

## The wire

All under `/api/v1/`, bearer token; every refusal is `{ "error": "Sentence." }`, and the unauthenticated 401s are the
shared "Sign in first." and "Your session has ended. Sign in again.". Handles in paths and bodies are trimmed and
matched without case (`/members/SAM` works); the handle in an answer is the canonical one. Org ids the service makes
are 22 base64url characters; it accepts 1 to 64 for an org id and for a notification id, as it does for a note's.

```
POST   orgs                              { name, hue? }                   -> 201 { org: Org }        the caller is owner
GET    orgs                                                               -> { orgs: [OrgRow] }      joined or invited to; declined left out; oldest first
GET    orgs/{id}                                                          -> { org: Org }            state 'member' only; one 404 "No such organization." for an invitee, a stranger or no such id
PUT    orgs/{id}                         { name?, hue? }                  -> { org }                 owner or admin; hue absent keeps it, hue null clears it
DELETE orgs/{id}                                                          -> { deleted: true }       owner; settles pending invitations, org-deleted to the members
POST   orgs/{id}/members                 { handle }                       -> { member: Member }      owner or admin; the invitation
DELETE orgs/{id}/members/{handle}                                         -> { removed: true }       {handle} resolved among this organization's rows only; one's own handle is leaving
PUT    orgs/{id}/members/{handle}        { role }                         -> { member }              owner; 'owner' hands over
POST   orgs/{id}/invite                  { accept: boolean }              -> { org } | { declined: true }   the invited person
POST   orgs/{id}/links                   { expiresIn?, maxUses? }         -> 201 { link: InviteLink } owner or admin; seconds 3600..30 days, uses 1..50; none of either is for good, without a limit
GET    orgs/{id}/links                                                    -> { links: [InviteLink] } owner or admin; the working ones, newest first
DELETE orgs/{id}/links/{link}                                             -> { dropped: true }       owner or admin; the code joins nobody from now on
GET    joins/{code}                                                       -> { org: { id, name, hue, members }, by, member }   anyone signed in with a working code
POST   joins/{code}                                                       -> { org }                 the caller in as a member; already in answers the org and counts no use

GET    notifications?since=<rev>&limit=<1..200>                           -> { rev, items: [Notification], more }   default limit 100; the cursor rule of the notes feed
POST   notifications                     { id, kind, blob }               -> { rev }                 self kinds only; an id the account has answers its stored rev and writes nothing
POST   notifications/read                { ids?: [id], all?: true, before?: rev } -> { rev }         `all` marks rows with rev <= before; without before, everything; nothing to mark answers the head
PUT    notifications/{id}                { read?: boolean, hidden?: boolean } -> { rev }             always a new revision
```

Shapes, as the service answers them (an absent field is absent, not null):

```ts
interface OrgRow { id; name; hue: string | null; role: 'owner' | 'admin' | 'member'; state: 'member' | 'invited'; members: number; invitedBy: string | null; createdAt: number }
interface Org extends Omit<OrgRow, 'members'> { members: Member[] }      // joined before invited, then by since
interface Member { handle; role; state: 'member' | 'invited'; since: number; invitedBy: string | null }
interface InviteLink { id; code; createdAt: number; expiresAt: number | null; maxUses: number | null; uses: number; by: string | null }
// Every moment (createdAt, since, at, readAt) is milliseconds since the epoch, as Date.now() counts, though the
// service keeps seconds: wire::millis converts on the way out.
interface Notification {
  id; rev: number; kind; at: number; readAt: number | null; hidden: boolean;
  from?: string | null;       // a server row: the handle of who caused it; null once that account is gone ("Someone")
  org?: { id; name };         // a server row: the live name while the reader is a member, else the name in body
  body?: Record<string, unknown>;   // a server row: small, plaintext; every server row has one
  blob?: string;              // a self row: sealed, payload { kind, ...details }
  state?: 'pending' | 'accepted' | 'declined';   // an invite
}
```

`members` in an `OrgRow` counts those who have joined. `invitedBy` is always present (null when nobody did, or that
account is gone). The role on an invited row is always `member`. `GET orgs` orders by `createdAt`, then by making; a
member list puts joined before invited, then by `since`.

**Two kinds of 404.** The service and the page do not ship in the same minute (D11: glyph-api first, then the OTA
after the login gap), and an older local MCP bundle may talk to a newer service or the reverse. So "not yet" is a 404
whose body is the service's `{ error: 'no such route' }`, or no service body at all (a proxy's 404): one helper,
`notYet(failure)` in `core/account/api.ts`, used by the pass, the pages and `mcp/glyph.ts`, and the two steps of the
pass are quiet on it and change nothing. Every other 404 is an answer in the service's words and is shown as one. The
deploy's probe (`scripts/deploy-server.mjs`) fails when `GET /api/v1/orgs` without a token is not a 401, since an old
binary answers 404 there.

## The refusal sentences

Each comes back as `{ "error": … }` with the status given, and the app shows it as it is (`ApiError.message`).

| Status | Sentence | When |
| --- | --- | --- |
| 400 | An organization's name is 1 to 60 characters. | POST or PUT orgs |
| 400 | That hue is not one of the workspace hues. | POST or PUT orgs |
| 400 | A role is owner, admin or member. | PUT members |
| 400 | That organization's id could not be read. | an id outside 1 to 64 base64url characters |
| 403 | Only the owner or an admin can do that. | PUT orgs, inviting, removing, by a member |
| 403 | Only the owner can do that. | DELETE orgs, PUT members, by an admin or a member |
| 403 | Only the owner can remove an admin. | an admin removing an admin |
| 403 | Hand the organization over first. | removing the owner; the owner setting their own role |
| 403 | Hand over or delete your organizations first. | DELETE account while owning an organization anyone else is in |
| 404 | No such organization. | an invitee, a stranger or no such id, on every route of it |
| 404 | No one has that handle. | inviting a handle nobody has, or one that cannot be a handle |
| 404 | No one by that handle is in this organization. | DELETE or PUT members, for both "no such handle" and "not in it" |
| 404 | You were not invited. | answering with no pending row (answered elsewhere already) |
| 404 | That invite link has expired or was turned off. | a code that is not one, expired, used up or turned off; DELETE links on no such link |
| 400 | A link lasts an hour to thirty days, or until it is turned off. | POST links, `expiresIn` out of range |
| 400 | A link may be used 1 to 50 times, or without a limit. | POST links, `maxUses` out of range |
| 409 | This organization has as many invite links as it can. Turn one off first. | an eleventh working link |
| 409 | They are already a member. | inviting a member |
| 409 | They declined; ask again tomorrow. | inviting within a day of their decline |
| 409 | They have as many invitations waiting as they can. | the invitee has twenty pending |
| 409 | The organization is full. | fifty rows, joined and invited |
| 409 | They have not joined yet. | handing over to an invitee |
| 409 | You own as many organizations as you can. | a twenty-first |
| 429 | Too many invitations in an hour. Try again later. | the thirty-first in an hour, by account or by address |
| 429 | Too many changes in a minute. Try again shortly. | the sixty-first other change in a minute |
| 400 | That notification's id could not be read. | POST or PUT notifications |
| 400 | That kind of notification could not be read. | a kind that is not 1 to 32 characters of `[a-z-]` |
| 400 | That kind of notification is the service's to make. | posting one of the nine server kinds |
| 400 | That notification is empty or too large. | a blob outside 1 to 8192 base64url characters |
| 404 | No such notification. | PUT on an id the account does not have |
| 429 | Too many notifications in a minute. Try again shortly. | the sixty-first post in a minute |
| 413 | (axum's own) | a body past 16 KB on any of these routes |
| 500 | That could not be stored. | the database refused |

The rate limiters are spent before anything is looked up, so a refused attempt still costs a token.

## Limits

Pinned by `server/src/orgs_tests.rs` and `notifications_tests.rs`:

| What | Limit |
| --- | --- |
| An organization's name | 1 to 60 characters after trimming |
| Its hue | one of ink, ember, amber, moss, sea, violet, rose (`WORKSPACE_HUES`, mirrored in `orgs.rs` `HUES`: edit both), or null |
| Organizations owned per account | 20 |
| Rows per organization, joined and invited | 50 |
| Invitations waiting per invitee, across every organization | 20 |
| Invitations | 30 an hour per inviting account, and 30 an hour per address |
| Working invite links per organization | 10; a link lasts an hour to 30 days or for good, and lets 1 to 50 join or any number |
| Every other change to an organization, invitation answers included | 60 a minute per account |
| A device's own notification posts | 60 a minute per account; a blob 8 KB; a body 16 KB |
| Notifications kept per account | 300, pruned inside the write transaction by `created_at`, the read-or-hidden first and never a pending invitation; a pending invitation is counted among the 300 but never the one that goes |
| Read-or-hidden rows | dropped after 60 days, on the next write |
| A page of the feed | 1 to 200 rows, 100 when not asked |
| Ids | an organization's or a notification's, 1 to 64 base64url characters (the service's own are 22) |

## The kinds

| kind | made by | to whom | body or payload | category |
| --- | --- | --- | --- | --- |
| `invite` | the service, on an invitation | the invitee | body `{ name }`; `state` pending, then accepted or declined; declined and hidden when the organization dies or the invitation is withdrawn | always |
| `invite-accepted` | the service | the asker, if still a member, else the owner | `{ name }`; `from` = who accepted | team |
| `invite-declined` | the service | the asker, if still a member, else the owner | `{ name }`; `from` = who declined | team |
| `member-joined` | the service | every other member, except the one told `invite-accepted` | `{ name }`; `from` = who joined | team |
| `member-left` | the service | every remaining member | `{ name, handle }`; `from` = who left, null once their account is gone | team |
| `member-removed` | the service | the removed person: `{ name }`; the other members: `{ name, handle }` | `from` = who removed | team |
| `role-changed` | the service | the person whose role changed | `{ name, role }` | team |
| `org-renamed` | the service | every other member; an unread one for the same organization is updated in place, with a new revision | `{ name, was }`, `was` the name before the first unseen rename | team |
| `org-deleted` | the service | every other member | `{ name }` | team |
| `note-created` | the MCP server (Claude) | self | `{ noteId, title, by }` | claude |
| `note-edited` | the MCP server | self | `{ noteId, title, by, added, removed, first, at }`: a line diff - the counts, the first changed line (at most 120 characters) and its anchor, which the note opens at (`Screen.note.at`) | claude |
| `note-appended` | the MCP server | self | `{ noteId, title, by, lines, first }` | claude |
| `journal-entry` | the MCP server | self | `{ noteId, title, by, journal, first }` | claude |
| `rule-added` | the MCP server | self | `{ noteId, title, by, first }` | claude |
| `summary-written` | the app, when a recording's summary lands (`ai/summaries.ts`) | self | `{ noteId, title }` | summaries |
| `sync-conflict` | the app, when a pass keeps a conflict copy (`core/sync/engine.ts` `onConflict`) | self | `{ noteId, title }` | conflicts |

Two things the design's table did not say, and the server does: **every server body carries `name`**, the
organization's name at the time of writing, so the feed can fall back to it once the reader is no longer a member
and the live name is not theirs to read; and the one who caused a change is not told of it. `by` in a self payload
is the author the MCP server resolved, or `Claude`. Voice commands and the blanks the phone fills are the person's
own act, already toasted, and are not recorded. The sentences each kind reads as live in one place,
`core/notifications/kinds.ts` `sentenceOf`: "sam invited you to Ghost", "Claude edited Trip to Lisbon · 2 lines
changed", "A meeting was written up: Standup", "Someone" for an account that is gone.

## What the server can see

Accounts and sync promise that the server holds copies it cannot read (docs/SYNC.md). An organization is not a note,
and another account must be able to reach this one with an invitation, so this is in the clear on the service, and
each place the app states its promise says so (docs/SYNC.md, the privacy policy, the Play data-safety answers, the
Guide's chapters 19 and 26):

- an organization's name and hue, who owns it, and when it was made;
- who is in it, by handle: each person's role, whether they have joined or are invited, who invited them and when,
  and, for a day, that someone declined;
- for every server-made notification: its kind, when, who caused it, which organization, and the few words in its
  body (the organization's name, a handle, a role, the old name);
- for every notification, server-made or sealed: its kind, when it was made, **when it was read, and whether it is
  hidden** - new, since until now the server saw when things change, not when they are looked at;
- an invite link's code, who made it, when it stops, how many it lets in and how many joined by it. The code is the
  permission, so it is in the clear as a share's id is; it names nobody;
- **whether a handle exists**, told to a signed-in account that invites it (404 "No one has that handle."), thirty
  times an hour per account and per address. It is the one such answer the service gives;
- which notes Claude touched, only as a count and a time: a self notification's `kind` column says `note-edited`,
  and nothing else of it is readable.

It cannot read a self notification's payload - the note's id and title, the author, the lines - nor, as before, a
title, a folder, a word of any note, a setting or a second of audio. Notes filed in an organization's workspace are
sealed per account exactly as any other note; the filing itself rides in the sealed settings.

## Invite by link

Matt: "add the ability to invite people to a team by link". The owner or an admin makes a link on the organization's
Members page or under its dashboard's invite field (`settings/InviteLinks.tsx`), for a day, a week, thirty days or for
good, and for one person, five, twenty-five or anyone who has it. The link is copied as it is made. Each working link
is a row with Copy, Send (where the device can share) and Turn off, and says how long it has and how many used it.

The link is the reader page with the code in its hash, `https://ghostmarkdown.com/read.html#join=<code>`
(`core/orgs/joinLinks.ts`), as a share link is the reader page with its key: the hash never reaches a server log, and
the page is there for someone without the app. It says only that it is an invitation to a team
(`src/read/JoinPage.tsx`), since the code is shown to the service only by someone signed in, and offers
`ghostmd://join/<code>` for the app and the web app at `#join=<code>`. Pasted into + › From a shared link, a link or a
bare code goes the same way.

Nothing is joined until the person says so: the app asks "Join Ghost?" with the name, who made the link and how many
are in it (`notes/JoinSheet.tsx`). Followed signed out, the code waits on this device for a week under
`glyph-join-held` and is asked about as soon as an account is signed in, after the way in at launch has closed.

On the service (`server/src/store/org_links.rs`, table `org_links`): the code is a fresh 128-bit id. Joining is the
invitation and its answer in one transaction. The joiner is a member, `invited_by` is the link's maker while they are
still in, else the owner, and that person is told `invite-accepted` as an asker is. Every other member is told
`member-joined`. A waiting invitation is settled as accepted. A decline within the day is no bar, since following a
link is asking to join. Someone already in counts no use. The fifty rows hold. Links that stopped working are cleared
as a new one is made, and every link goes with its organization. A code that is not one, and one that stopped, get
the same 404 in the same words. The routes share the sixty-a-minute change limit: a link names nobody, so it is no
handle oracle, and 128 bits are not guessed at sixty a minute.

## On the phone

Matt: "also send notifications as actual phone notifications too". From native generation 23, an Android phone shows
the bell's rows as its own notifications (`core/notifications/phone.ts`; the shell's `notices/NoticeAlerts.kt` and
`NoticeWorker.kt`). No push service is involved, and the service is unchanged: the phone reads the same feed.

- **What comes.** What the bell counts (`feed.ts` `isWanted`): team news, invitations still waiting, and Claude's
  changes, by the same switches and mutes. A meeting written up has its own notification under Recording, and a note
  kept twice is the device's own doing, so neither comes again.
- **When.** While the app runs in the background, the rows a sync brings are posted from the page, in their own words:
  "Claude edited Trip to Lisbon", with the first changed line under it. While it is closed, a WorkManager job reads
  the feed about every fifteen minutes, the least Android allows, and words a sealed row by its kind: "Claude edited a
  note". With the app in front nothing is posted, since the bell is in view. A device's first look at the feed posts
  nothing, so signing in does not post a year of history.
- **Once.** The phone keeps the last three hundred row ids it posted, so a row reached by both roads is posted once.
- **The session.** The page hands the worker the service's address, the session token, its cursor and the switches
  (`GlyphHost.watchNotices`) after every pass and every change of a switch, and takes them back on signing out, with
  Local only, or with the phone's switch off. The worker refreshes the token when it has under two days left; a
  refresh leaves the page's own token good. A refused session ends the watch until the page hands a new one.
- **Tapping one** opens the note Claude changed, the organization's dashboard while it is yours, or the notifications
  drawer, through the `ghostmd://` links the app already follows.
- **The switch** is Settings › Notifications › On this phone, per phone and not synced, on unless turned off. When
  Android is keeping the app's notifications from showing, the row says so and offers Allow notifications. The channel
  is "Notifications", private on the lock screen.

Nothing happens on the Mac, in a browser, or on an APK from before generation 23: the row is not drawn, and the page
hands nothing.

## How it is built

**The server.** Three tables, `CREATE TABLE IF NOT EXISTS` as every table here is (`server/src/store.rs`):
`orgs(id, name, hue, owner_id → accounts CASCADE, created_at)`; `org_members(org_id → orgs CASCADE, account_id →
accounts CASCADE, role, state, invited_by → accounts SET NULL, since, PRIMARY KEY (org_id, account_id))`;
`notifications(account_id → accounts CASCADE, id, rev, kind, from_id → accounts SET NULL, org_id, body, blob,
state, created_at, read_at, hidden, PRIMARY KEY (account_id, id))`, with indexes on the lookups. Only `account_id`
and `owner_id` cascade: an inviter deleting their account takes nobody with them, and a row in someone else's feed
keeps everything but its `from`, which reads as null. `store/orgs.rs` keeps the rows and the owner invariant;
`store/notifications.rs` keeps the feed, the pruning and `Store::notify`, which every write that tells someone calls
**inside the transaction of the change**, taking the recipient's next `accounts.rev` through `Store::next_rev` - one
`Mutex<Connection>` is the only writer, so bumping another account's counter there is atomic with the change, as a
sign-up writes its codes. `orgs.rs` and `notifications.rs` are the wire: the routes, the limiters
(`guard::RateLimiter`, with a per-hour shape for invitations) and the words. `main.rs` merges both routers inside the
`if let Some(accounts)` block, so the service still starts without account data.

**The client.** `core/ids.ts` `shortId()` makes the 22-character id the MCP uses too. `core/orgs/types.ts` is the
shapes and the `org-<id>` rule; `core/orgs/orgs.ts` the calls (each a `CallContext` that defaults to the signed-in
session), the list kept per account under `glyph-sync-<accountId>-orgs`, `useOrgs`, `syncOrgs(ctx)` and the
reconcile. `core/notifications/kinds.ts` is the kinds, the categories, the payload shapes and `sentenceOf`;
`core/notifications/feed.ts` the feed per account under `glyph-sync-<accountId>-notifications` (items by id, cursor,
pending marks, unsent self rows), `useNotifications`, `unreadCount(prefs)` from the plaintext fields, `markRead`,
`markAllRead`, `hide`, `answerInvite(orgId, accept)` (keyed by the organization, so the Organizations page can answer
a row it has no notification id for), `openDetails(n)` and `syncNotifications(ctx)`;
`core/notifications/record.ts` `record(kind, details)`, which seals and posts a self row and never throws.
`core/preferences.ts` holds `notifications`, settled on load; `core/workspaces.ts` gains `ensureOrgWorkspace`,
`renameOrgWorkspace`, `dropOrgWorkspace` and `isOrgWorkspace`; `core/noteFolders.ts` `folderFor` takes the workspace
rather than its name, so the type system found every caller. `core/sync/engine.ts` runs the four steps, forgets both
new keys on sign-out, and offers `syncNotificationsNow()`. `src/test/fakeService.ts` is the one stand-in, with every
route in the service's words, `peers: ['sam']` (handles that resolve without being the account), `service.notifies(row)`
to play a server-made row arriving, `service.invited(name, by)`, and `fakeService(seed, { teams: false })` for a
service without the routes yet.

**The MCP server** posts a self notification after each successful write at its five sites - `create_note`,
`update_note` with the line diff, `append_to_note`, `add_journal_entry`, `add_rule`, and `ensureRulesNote` only on
its create branch - sealed with the same id maker and the same seal, best effort: a failed post is swallowed with a
`glyph-mcp:` line on stderr, the tool still answers, and no row follows a refused (409) write. The author is the one
`authored` resolved, or `Claude` (docs/MCP.md).

**The screens** are DESIGN §170, §171 and §175: the bell in the tab row, the notifications drawer under it (§174),
Settings › Notifications, Settings › Account › Organizations, an organization's dashboard (`notes/OrganizationScreen.tsx`,
the `organization` Screen: its notes, its members and its news, opened from the tab row's organizations icon, a
notification, an invitation accepted or one just made), and its settings (`settings/OrganizationSheet.tsx`), a second
`SettingsScreen` with a `title` and no search, over whatever is up: from the dashboard's cog on its sections, from
Settings › Account › Organizations on Members, and from the edit words on its workspace.

**Deploy order** (D11): glyph-api first, then after the login gap the web OTA with `--mcp` and the hosted connector,
with `notYet` carrying the page across the gap. The hosted connector's restart signs its sessions out, as any restart
of it does.

## Tests

- Server: `server/src/orgs_tests.rs` (made, listed, renamed, deleted; a stranger's one 404; the invitation and its
  refusals; an invite link made, previewed, followed and turned off, and its terms and count; the owner invariant through the routes; a rename coalesced and a former member keeping the old name;
  deletion settling invitations; an asker deleting their account; the limits) and `notifications_tests.rs` (a post
  read back and a repeat landing once; the kinds and limits; read marks fed again; the cursor rule; one account never
  seeing another's; three hundred kept with the read ones going first and never a pending invitation; sixty posts a
  minute); the stores' own `mod tests` in `store/orgs.rs`, `store/org_links.rs` and `store/notifications.rs`; and every new signed-in route
  in `sync_tests.rs` `every_signed_in_route_refuses_in_the_same_words`.
- Client: `src/app/core/orgs/orgs.test.ts`, `joinLinks.test.ts`, `notes/JoinSheet.test.tsx`, the invite-link case in
  `settings/OrganizationSheet.test.tsx`, `src/read/JoinPage.test.tsx`, the join cases in `shell/useAppLinks.test.tsx`, `src/app/core/notifications/feed.test.ts`, `kinds.test.ts`,
  `record.test.ts`, `src/app/core/ids.test.ts`, `src/app/core/account/api.test.ts` (`notYet`), and the cases added to
  `workspaces.test.ts`, `noteFolders.test.ts`, `preferences.test.ts`, `sync/prefs.test.ts`, `reset.test.ts` and
  `sync/engine.test.tsx` (the order of the pass).
- The screens and the MCP server's part have their own tests, named in DESIGN §170, §171 and §175.

## Not in this slice

- Notes shared inside an organization: an organization key wrapped per member under a per-account encryption key.
- A nudge over the live relay when a row lands; polling inherits the pass's triggers until then.
- Pruned rows are not fed as deletions, so a device keeps its copy of a row the server dropped; and an account's
  deletion clearing `from` does not bump the row's revision, so a device that already has the row keeps the old handle
  until something else re-feeds it.
