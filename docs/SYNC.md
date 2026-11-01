# Sync in the Flutter app

The accounts, the keys, the wire and the merge rules are the Tauri app's, ported case for case: tauri/docs/SYNC.md
has them (the account key, what the server can and cannot see, `GET/PUT prefs`, the notes' feed). The code that
refers to "docs/SYNC.md" means that document for all of it, and this one for what the Flutter app added since.

## Keys and connections

Matt, 2026-10-26: "Also make it so things like the Claude tokens and other stuff is kept in sync across all instances
of ghost logged in to my account". That morning a meeting's summary stuck on the Mac: Claude's key was kept per
device, the Fold had one and the Mac did not (lib/ai/summary_handoff.dart). Now the keys and the settings of the
connections follow the account. The code is lib/sync/sealed_keys.dart (how) and lib/sync/connections.dart (what);
the tests are test/sync/sealed_keys_test.dart.

### What travels, and what stays

| Travels | Where it is kept on a device |
| --- | --- |
| Claude: the API key, the model, the effort, the inbox switch, the watch's To Claude switch | the secure store, `anthropic-api-key`, `-model`, `-effort`, `-inbox`, `-watch` |
| Claude's spending limit: on, the amount, the warning | the secure store, `anthropic-limit` (new: written only when it is set) |
| The Claude, Slack and GitHub plugins' switches, and Google Meet's and Zoom's (which kinds Ghost joins; docs/MEET.md) | `glyph-plugins`, as `plugin:<id>` |
| Slack: each channel's webhook, and the list that names them | the secure store, `glyph-slack-webhook:<id>`; storage, `glyph-slack-channels` |
| The Slack page's Post to Slack: the switch, the channel, the share link | storage, `glyph-slack-meetings` |
| GitHub's personal access token | the secure store, `glyph-github-token` |

Already travelling with the settings, sealed with the blob as a whole: the calendars' iCal addresses and Google's
sign-in (`calendars`), and the webhooks with their secrets (`webhooks`). Google's refresh token can be shared: Google
does not turn it over when it is used, so each device makes its own access tokens from the one refresh token.

Stays on each device, and why:

- **Notion's sign-in** and the boards notes send to. Notion turns its refresh token over on every refresh: the old
  one stops working. Two devices sharing the pair would each refresh in turn, and the one holding a token already
  spent would be signed out; a sync every few minutes cannot close that gap. Each device signs in itself.
- **What Claude spent this month**: each device's own count, held to the same limit.
- **Where an organization's news goes on Slack**: every device with a channel set for an organization posts its news,
  so synced, each row would be posted once per device.
- **Bookkeeping and caches**: what was posted, the meetings' queue of tries, Notion's and GitHub's caches, the events
  fetched.
- **What is the device's**: the microphone and the models, its sign-in session and its own keys, window and layout,
  and the plugins tied to its permissions (contacts, places and their reminders).
- **On an iPhone, Slack.** Slack is not there yet (lib/core/iphone_app.dart `notOnIPhone`), so the Slack items are
  not offered there and their entries are carried untouched. Claude's key does go to an iPhone.

### How, and the encryption

No new route: the keys ride in the synced settings (`PUT prefs`), under one key, `sealedKeys`, in the preferences'
unknown keys (`Preferences.more`). The settings blob is sealed whole under the account key already, so the service
reads nothing of it. **Each value is also sealed on its own**, AES-256-GCM under the account key with `key:<name>` as
its associated data, because the settings are kept on each device in its ordinary storage (`glyph-preferences`, and
the account's copy in `glyph-sync-<id>-prefs-held`), and a key must not sit there readable. What the settings hold:

```
sealedKeys: {
  "anthropic-api-key": { "at": 1761475200000, "by": "<device id>", "sealed": "<base64url>" },
  "glyph-slack-webhook:9f…": { "at": 1761475300000, "by": "<device id>", "gone": true }
}
```

A device keeps where its values live as it did; only the sync reads and writes them, through the doors their owners
use (the secure store, a plugin's host, the registry), and has the owner read again (`ClaudeSettings.reload`), so a
caller never knows a key travelled. Which entries a device has taken is `glyph-sync-<account id>-keys`, `{name: at}`:
times, never values. Nothing is logged but the kind of a failure.

### A pass

The engine's settings step (lib/sync/engine.dart) is three moves:

1. **Gather**: each item read and compared with its entry, opened. Changed here (and its entry already taken here):
   sealed into a new entry, `at` now, never at or before the entry it replaces, `by` this device
   (`glyph-handoff-device`).
2. **The settings' pass**, which merges `sealedKeys` an entry at a time (`mergedSealedKeys`).
3. **Apply**: each entry not taken yet, opened and written into its item; values before removals, and a webhook
   before the list that names it.

A key changed here asks for a sync four seconds later, as a setting does (`SealedKeys.changes`, from Claude's
settings, the plugins' storage and secrets, and the switches).

### The rules

- **Last change wins, per item.** An entry changed on one device is that one's; changed on both, the later `at`
  stands (a tie, the device id that sorts last). The time is when the change was gathered, so a change made offline
  and sent later still loses to one made after it.
- **A removal is a tombstone**, `gone`, merged like any change: a key forgotten on one device is forgotten on every
  other at its next sync, and stays forgotten. Tombstones are kept.
- **A device's first sync takes the account's** keys, as it takes the settings; a key only it has is sent at its
  next pass. Where the account's settings have no `sealedKeys` at all (written by an older build), the device's own
  are left unseen, so they go (lib/sync/prefs.dart, the first-take branch).
- **The switch**, Settings › Account › Keep keys and connections in sync (`glyph-keys-sync`, this device's, on by
  default): off, the device gathers nothing and applies nothing; each device keeps the copy it has, and the account
  keeps the entries it holds. Turned on again, what arrived meanwhile is taken.
- **Signing out** takes `sealedKeys` out of the settings here and forgets what was taken, so another account signed
  in here is never sent this one's; the values stay where they are kept, as the notes do.
- **The account's own.** The settings are sealed under the account key; an organization's key never touches them
  and a teammate never has them.
- **Older builds** do not sync `sealedKeys`: they carry it among the blob's unknown keys and write it back as it came
  (`PrefsContext.carried`). An item name this build does not know is carried the same way, inside the map.
- **Meetings.** With the key and the switch on the Mac, the summaries' handoff, which hears Claude's settings and the
  switches (lib/root/voice_wiring.dart), sees the Mac able to write a waiting meeting up. Slack's channels on every
  device let the device that writes a meeting up post it; `slackMeetingPosts` still posts it once.

## Leaving an organization, and moves between organizations

Matt, 2026-11-01 ("Leaving an org", "Moves between orgs"). That day the connector filed 26 of Hello HQ's team notes
into a folder of HelloTrade's; Matt then deleted Hello HQ (server/src/store/orgs.rs `delete_org`, whose rows
cascade), and the 26 were gone everywhere: the settings said HelloTrade, HelloTrade's team never held them. The same
deletion left about a thousand of his notes the settings had filed under Hello HQ loose at the top, in no folder.

**Leaving or deleting.** The organization's workspace becomes a folder of the person's named after it, in its
colour, with the id its place gives it (`folderIdFor`, so every device makes the same one); every folder that was
inside it is inside that one with its id, name and colour; every note filed in any of them stays filed where it was,
the ones in the organization's own workspace in the new folder; the files follow, `orgs/Hello HQ/Engineering Tasks/`
to `workspaces/Hello HQ/Engineering Tasks/` (lib/core/workspaces.dart `dropOrgWorkspace`). Filings are re-pointed
whether or not this device holds the note. Nothing is deleted, unfiled or trashed. A team's note this device holds
becomes the person's own and goes to the account at the next pass: on a delete the team's rows are gone for everyone
on the service, and each member keeps what their devices held, as files, as docs/MARKDOWN_FIRST.md asks (an old build
unfiles them into the inbox instead, which also keeps them; neither deletes another member's note, since the
organization's channel is not run for an organization the list no longer has). Settings › the organization ›
Delete or Leave says so, counted ("Its 24 notes and 3 folders are kept on your devices in a folder of your own called
"Hello HQ"…"), and Delete syncs first and waits while a note is still on its way into another organization
(`SyncEngine.movesPending`).

The notes that missed that are mended too. A note at `orgs/<name>/…` that is filed nowhere, where no organization of
the person's is that name, is filed in their folder of that name once the organizations are known
(lib/core/folder_adopter.dart `fileFormerOrgNotes`, after every pass that got the list). And a row of the account's
feed passed over because its note was a team's here is kept aside (lib/sync/notes.dart `SyncState.aside`): once the
note is no team's, or its team has never had it, while this device lacks it, the feed is read again from that row
and the note taken. A state kept by a build before this is read again from the start once, which finds the thousand.

**Moves between organizations: the second holds it before the first lets go.**

- A note filed from organization A into B on a device: A's channel keeps A's row while B's state does not hold the
  note (lib/team/sync.dart `mayLetGo`, from the engine's reading of B's kept state, `teamHoldingIn`), so the note is
  never only on the device. B's channel puts it; A lets go at the next pass. The note's document is one per note
  whichever team has it: A's channel neither drops it as A's row goes nor moves its place in the log; B's row is put
  with its history at B's log's start (`_pushOne`), and a device whose document came from A takes B's place in the
  log from B's first row (`_takeRow`). A note filed back into an organization it once left is put over its old row
  there, where before the deletion was taken and the note removed from the device.
- The connector writes the row into B's store itself, reads it back from B's feed, then deletes A's
  (tauri/docs/MCP.md, "Filing is sharing").
- **A note the settings file in a team that never had it**, held by no device but in the account's feed (the
  connector's `accountOnly`): its row is taken where the team's channel has read its feed whole (`goneRead`, a
  team's deletions gathered, once from the start for a state kept before) and neither holds nor deleted it, and the
  team's channel puts it; the account's row of it stays until the team holds it (`SyncState.owed`). One a team let
  go of, or one a team cannot speak for yet, is never taken.

The service needed no change: a move is the devices' and the connector's, and `delete_org` cascading the team's rows
is right once nothing lives only there.
