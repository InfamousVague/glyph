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
