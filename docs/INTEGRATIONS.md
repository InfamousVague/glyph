# Webhooks, contacts, place reminders, Todoist and Things, and the .ghostex export

Matt, 2026-10-17: "I want to add the webhooks, phone contacts, location reminders, and todoist and things import
also add bulk export in a ghostex file". The Flutter app (and glyph-api for the incoming webhooks). Each part names
who owns what.

## 1. Webhooks

### Out: a device tells a URL when notes change

Settings › Webhooks › Outgoing: a URL, the events (`note.created`, `note.edited`, `todo.done`), the scope (every note,
a workspace, a notebook, or a tag) and an optional secret. A device that saves a change in scope POSTs JSON to the
URL, at most once per note per 10 seconds (a run of typing is one call):

```json
{ "event": "note.edited", "at": "2026-10-17T18:00:00Z",
  "note": { "id": "...", "title": "...", "workspace": "Family", "url": "ghostmd://note/<id>",
            "body": "<markdown>", "changed": ["- [x] Buy a crib"] } }
```

With a secret, the header `X-Ghost-Signature: sha256=<hex HMAC-SHA256 of the body>`. Sent by the device that made
the change, never by the server (the server cannot read notes). Failures are retried three times, then said in the
pane. Local only on: nothing is sent.

### In: a URL that adds to a note

Settings › Webhooks › Incoming › New: the app asks glyph-api for a hook and shows its URL to copy, with examples for
curl, Zapier, Make and IFTTT.

```
POST /api/v1/hooks              (signed in) { name }      -> { id, name, url, createdAt }
GET  /api/v1/hooks              (signed in)               -> [{ id, name, url, createdAt, lastUsedAt }]
DELETE /api/v1/hooks/{id}       (signed in)
POST /api/hooks/{token}         (no sign-in: the token)   -> 202
GET  /api/v1/hooks/inbox        (signed in)               -> [{ id, hook, at, sealed }]
DELETE /api/v1/hooks/inbox/{id} (signed in)
```

- The incoming body is JSON `{ "note": "<title>", "text": "...", "as": "task"|"item"|"paragraph"|"note" }`, or a
  form with the same fields, or plain text (then `text` is the body and it goes to the hook's default note, set
  when it was made: `{ name, note? }`). At most 32 KB.
- glyph-api seals it at once to the account's public encryption key (ECIES on P-256, exactly
  tauri/src/app/core/orgs/wrap.ts's `wrapFor`, context `hook:<hook id>`), keeps only the seal (at most 500 waiting per
  account, 30 days), and answers 202. The plaintext is never written anywhere. A token is 32 random bytes,
  base64url; only its SHA-256 is stored. Rate: 60 a minute per hook.
- A device's sync pass reads the inbox, opens each with the account's private key, adds it as the app's own "add to
  a note" does (an item to the note's list, a task, a paragraph, or a new note named `note`), and deletes it from
  the inbox. A note that does not exist is made.

## 2. Phone contacts

`@sam` and `@sam-ortiz` already name people on to-dos (core/taskFields). With the **Contacts** plugin on (lib/plugins/
contacts, Settings › Plugins; off until the person switches it on, which asks the phone's permission; its page,
Settings › Plugins › Contacts, is what the phone allows and the people matched), a person whose name matches a contact on the device (first
name, full name, or a name set by hand in the pane) shows the contact's picture in the chip, and a tap opens a card:
Call, Text, Email, Open in Contacts. The + beside a line and a list item's press and hold gain "A person", which
picks a contact and writes `@first-last`. Nothing about a contact leaves the device or enters a note but the name
written.

## 3. Place reminders

A to-do with a place reminds when the phone arrives there:

```markdown
- [ ] Buy diapers 📍 [Target](geo:35.7002,-81.3084)
```

`📍` then a place link, written by press and hold › Remind me at a place (a search of places, the places already in
the note, or "here") and read as a field like `📅`, drawn as a chip with the place's name. Other apps read a pin and a
link. On Android a geofence (radius 150 m, Google Play services' GeofencingClient) is set for each open to-do with a
place, again after a reboot, and removed when the to-do is ticked or deleted; arriving shows a notification on the
reminders' channel ("Buy diapers — you're at Target"), tapping it opens the note at the to-do, with Done on it. The
phone asks for location "all the time" when the first such reminder is made, saying why. iPhone: region monitoring
(at most 20 at once, the nearest). The Mac has none.

Built 2026-10-17 (Android): the field is lib/reminders/place_syntax.dart over core/task_fields.dart (key `place`,
written where `⏰` is); the set is place_plan.dart (open to-dos only, at most 100, the nearest to the phone's last
known position when there are more), handed over whole after every change by place_scheduler.dart from
lib/root/phone_extras.dart's pass; the channel is `ghost_md/places` (place_host.dart: `set [{id, lat, lon, radius,
title, text, place, noteId, line, words}]`, `clear`, `access`, `askForeground`, `askBackground`, `lastKnown`,
`openSettings`) and its phone half android/…/ghost_md/reminders/Places.kt (play-services-location 21.3.0; the
notification and its Done are Reminders.kt's, the restart's ReminderReceivers.kt's). The permission's steps are
place_access.dart; the sheet is place_sheet.dart, its search lib/core/geocode.dart `geocodeSearch` (Nominatim,
sent only, a second apart, never under Local only).

A plugin (Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins"): **Place reminders**,
lib/plugins/places, built in and off until switched on in Settings › Plugins, its page the location's state and the
way to allow it. The `📍` is Markdown and is read and drawn whether it is on or not; Remind me at a place, a chip's
Change place and the geofences are only there while it is on, and switching it off clears the geofences. It declares
the notes and `native` (the location, kept on the phone), not the network, so Local only leaves it working; the
search alone is off then. The first place reminder made on a phone is when it asks for the location
(place_settings.dart keeps that it has).

TODO (iPhone): the app has no iOS native layer for reminders yet (ios/Runner has no notifications or
CLLocationManager), so place reminders are not offered there: `phonePlaces` stays null. When reminders come to the
iPhone, `ghost_md/places` on its side is CLLocationManager region monitoring with the same set cut to the 20
nearest (`nearestPlaces(…, most: 20)`), "Always" asked after "When In Use" as Android's order is here.

## 4. Todoist and Things

Settings › Import (beside Obsidian and Evernote, lib/importer). Todoist and Things are each a plugin
(lib/plugins/todoist, lib/plugins/things), built in and off until switched on in Settings › Plugins: each one's page
holds its import, and Settings › Import offers it only while it is on.

- **Todoist:** an API token (Todoist › Settings › Integrations › Developer) or a project's CSV export. Each project
  becomes a note (sections as headings), tasks as `- [ ]` with due dates `📅`, priorities (p1-p4 as ⏫ 🔼 🔽 none),
  labels as `#tags`, sub-tasks indented, descriptions indented under. Optionally the completed ones, ticked.
- **Things 3:** on a Mac, read from Things' own database (read only); elsewhere, the text Things copies for a list
  (Share › Copy). Areas become notebooks, projects their pages, headings as headings, to-dos with deadlines `📅`,
  `When` dates as `⏳`, tags as `#tags`, checklists indented.
- Both say what was brought over and what was not, as the other importers do.

## 5. The .ghostex export

Settings › Account › Export everything: a single `<name>-<date>.ghostex` file, a ZIP:

```
manifest.json                  { format: "ghostex", version: 1, exportedAt, app, notes: [...], workspaces, notebooks }
notes/<workspace>/<title>.md   each note's markdown, as kept, front matter included
pictures/<name>                the pictures the notes name
files/<name>                   attachments
recordings/<note id>.wav       only when "Include recordings" is ticked (the core keeps a recording as WAV)
```

`manifest.json` lists every note with its id, path in the ZIP, title, created, updated, pinned, archived, workspace,
organization and tags. Options: include archived notes, include organizations' notes, include recordings, and
"Protect with a password" (the ZIP sealed whole with AES-256-GCM under a key derived from the password, as the
account's own key is). Settings › Import › A .ghostex file reads one back: every note made again (a note whose id is
already here is skipped, or kept as a copy, as chosen), with its pictures and files.

As built (lib/export/ghostex.dart, ghostex_seal.dart, ghostex_calls.dart; lib/importer/ghostex.dart): a protected file
is `GHOSTEX1` ‖ version (1 byte) ‖ PBKDF2 rounds (4 bytes, big-endian) ‖ salt (16 random bytes) ‖ the ZIP's own
random key wrapped under the password's (iv ‖ key ‖ tag, 60 bytes) ‖ the whole ZIP sealed under it (1 ‖ iv ‖
AES-256-GCM ‖ tag, context `ghostex`). The core lets a derived password key wrap and never seal, as with the account
key, so the ZIP has a key of its own. An organization's notes come back as the person's own, in a workspace of the
organization's name: an import never shares. Opened from Android's Files (a VIEW filter on the `.ghostex` ending) or
the Mac's Finder (`com.mattssoftware.ghostex`), the file lands in Settings › Import.

## Ownership

| Part | Where |
| --- | --- |
| Incoming hooks on the server | server/src/hooks.rs (new), main.rs |
| Webhooks in the app | lib/integrations/webhooks/* (new), Settings pane, the sync pass |
| Contacts | lib/integrations/contacts/* (new), the people chips (lib/editor/items/field_chips.dart), Settings pane, platform permissions |
| Place reminders | lib/reminders/* (place), core/taskFields, Android Kotlin geofencing, permissions |
| Todoist and Things | lib/importer/todoist*.dart, things*.dart (new) |
| .ghostex | lib/export/* (new), lib/importer/ghostex.dart (new), Settings |
