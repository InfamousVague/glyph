# Ghost's Signal helper: the protocol

Matt, 2026-11-15: "Lets wire it up for signal through the mautrix". A helper process, `signal-sidecar`, built on
mautrix-signal's signalmeow (AGPL) and Signal's libsignal, linked to the person's Signal account as a secondary device
(as Signal Desktop is). The app (lib/inbox/signal.dart) runs it as a child process on the phone and on a computer and
speaks JSON lines over its stdin and stdout, as it does with the Google Messages helper (sidecar/gmessages).

Run: `signal-sidecar --dir <folder>`. The folder holds its SQLite store (`signal.db`). Logs go to stderr.

## Requests (stdin), one JSON object a line

Every request has `id` (a number the app picks) and `op`. Each is answered by one line
`{"id": <same>, "ok": true, "result": <...>}` or `{"id": <same>, "ok": false, "error": "<words>"}`.

| op | fields | result |
| --- | --- | --- |
| `status` | | `{"linked": bool, "connected": bool, "aci": "<uuid>", "number": "+1…", "name": "…"}` |
| `link` | `name` (the device name Signal shows, "Ghost Messaging") | `null` at once; then `qr` and `linked` / `link_failed` events |
| `unlink` | | `null`; forgets everything |
| `contacts` | | `[{"aci": "<uuid>", "name": "…", "number": "+1…", "avatar": "<path or null>"}]` (from Signal's contact sync, and their Signal profile where the sync names them not) |
| `groups` | | `[{"id": "<group id, base64>", "title": "…", "members": ["<aci>", …], "avatar": "<path or null>"}]` |
| `send` | `to` (an ACI uuid, or a group id), `text`, optional `quote` (`{"ts": <ms>, "author": "<aci>"}`) | `{"ts": <ms the message was sent at>}` |
| `send_media` | `to`, `path`, `mime`, `name`, optional `text` (the caption) | `{"ts": <ms>, "pointer": {…}}`: the attachment pointer sent, with its key |
| `read` | `to`, `author` (aci), `ts` (list of message times) | `null`: read receipts sent |
| `react` | `to`, `author`, `ts`, `emoji`, `remove` | `null` |
| `delete` | `to`, `ts` | `null`: deleted for everyone (your own message) |
| `download` | `pointer` (an attachment as an event gave it: the JSON object, or that object as a string), `path` | `null` once written to `path` |
| `who` | `aci` | `{"aci", "name", "number", "avatar"}`: the person as the store has them, and from their Signal profile (fetched with the profile key a message carried) where nothing names them; `name` empty where Signal has none |
| `group_info` | `to` (a group id) | the group in full: `groups`' fields and `description`, `timer` (seconds, 0 off), `people` and `pending` and `requesting` (`[{"aci", "name", "number", "admin", "me"}]`), `admin` (you are), `edit_info` and `add_members` (`"members"`, `"admins"` or `"anyone"`), `announcements_only`, `terminated`, `invite_link` (where there is one) |
| `group_update` | `to`, `change`: any of `title`, `description`, `avatar` (a picture's path; `""` removes it), `timer`, `add`, `remove`, `admin`, `unadmin` (lists of ACIs), `announcements_only`, `edit_info` and `add_members` (`"members"` or `"admins"`), `leave` | the group as `group_info` gives it, once Signal has made the change and told everyone in it (also sent as a `group` event); `{"id", "left": true}` after `leave`. Signal refuses what the group's rules do not let you do |

## Events (stdout), one JSON object a line, each with `ev`

| ev | fields |
| --- | --- |
| `ready` | `linked` (bool) |
| `qr` | `url` (the `sgnl://linkdevice?…` address, drawn as a QR code for Signal's Linked devices › Link new device); a new one every 45 seconds, for 15 minutes |
| `linked` | `aci`, `number` |
| `link_failed` | `error` |
| `connected` / `disconnected` | |
| `message` | `chat` (the other person's ACI, or the group id), `group` (bool), `from` (sender ACI), `name` (sender's name where known), `mine` (bool: sent from another of the person's devices), `ts` (ms), `text`, `media` (list of `{"pointer": <opaque JSON>, "mime": "…", "name": "…", "size": n, "width": n, "height": n}`), `quote` (optional `{"ts", "author", "text"}`) |
| `receipt` | `chat` (the ACI of the person whose device sent the receipt, in a group too), `ts` (list), `kind` (`delivered` or `read`) |
| `reaction` | `chat`, `from`, `target_ts`, `target_author`, `emoji`, `remove` |
| `deleted` | `chat`, `target_ts` (deleted for everyone by its author) |
| `contacts` | `list`: the same list as the `contacts` op (Signal's contact sync, as it arrives; avatars come with the op) |
| `name` | `aci`, `name`, `number`, `avatar`: someone who wrote with nothing naming them, once their profile is fetched (once a run each) |
| `unlinked` | Signal removed this device |

Signal keeps no history for a new linked device: the app keeps what arrives from linking on.
