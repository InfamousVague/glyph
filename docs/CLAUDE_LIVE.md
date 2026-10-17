# Claude, live in Ghost.md

Matt, 2026-10-17: "I'd like to have notes streamed in real time and see claude typing as it is typing, i want it to
show online while connected as well and be able to go view what it's editing", then, of the five phases proposed for
it: "Build all of these and deploy to my phone".

Claude reaches the account through the MCP connector (mcp/, tauri/docs/MCP.md). Until now it wrote a whole note at
the end of a tool call, appeared as an AI entry "last seen" at most every six hours, and its notifications arrived on
the next sync. This document is the contract between the connector and the app for what replaces that. Every part
below names who owns it.

## What a person sees

1. **Claude online.** While Claude is working on the account, it shows as online: a dot on its AI entry in the
   organization screen, "reading Roadmap" or "editing Roadmap", a Claude chip in the app's top bar, and "Claude is
   editing Roadmap" on the home page. It goes idle five minutes after its last request.
2. **Claude typing.** In a note open on a device, Claude's words arrive as it writes them, a few letters at a time,
   with a caret labelled Claude in its own colour.
3. **Follow Claude.** A Follow button on Claude's entry and chip, and a "Claude is editing X - Watch" notice when it
   starts on a note: the app opens the note Claude is in and keeps Claude's caret in view, moving to the next note
   with it, until Stop (a bar at the top) or until the person scrolls or types.
4. **Personal notes too.** All of the above for the account's own notes, not only an organization's.
5. **Deeper.** Notes offered to Claude as resources it can attach; prompts (weekly review, plan my day, tidy a note,
   work through the Ask Claude inbox); Claude reading and answering comment threads; a suggest mode in which
   Claude's edits are suggestions to keep or revert; and an "Ask Claude" inbox note a scheduled routine works through.

## Honest limits

- An MCP tool's arguments reach the connector whole, after Claude has written them: the connector cannot see words
  as the model produces them. "Typing" is the connector writing what it was handed into the open note at a reading
  pace, at most a few seconds a call. The tools' descriptions ask Claude to write long changes in parts (a section
  per call) so the note fills in as Claude works.
- It types only when someone is watching (a device is in the note's room). Otherwise it writes at once, as before.
- Claude on claude.ai keeps no connection open between requests, so "online" is "made a request in the last five
  minutes". Claude Code's local connector is a process, but uses the same rule, so an idle terminal does not show
  online all day.

## Wire contract (connector and app)

All of it rides the existing relay (`/api/v1/live`, server/src/live.rs, tauri/docs/LIVE.md), sealed as today. No
server change.

### Who Claude is in awareness

Every awareness state the connector publishes has:

```json
"user": { "name": "Claude", "hue": "violet", "ai": true, "via": "<the account handle>" }
```

`name` is the AI's name as the connector knows it (`by(undefined)` in mcp/server.ts: the name Claude's app gave, else
"Claude"). `ai: true` marks it as an AI; `via` is the member whose connector it is. The app must never count such an
entry as a member being present, and must show it as the AI instead.

### Presence rooms

- **An organization's:** the existing room `presence` with `org`, sealed under the org key
  (`openTeamEnvelope`, context `live:org:<org>:presence`). The connector joins it in every organization whose key it
  holds.
- **The account's own (new):** a room named `presence` with no `org`, sealed under the account key with
  `seal(key, envelope, 'presence')` (wire.ts `seal`, context `live:presence`). Every device of the account joins it
  while signed in, as it does an organization's, and announces itself there too (with its handle as `name`, no
  `ai`). The connector joins it as well.

Claude's presence state in either room:

```json
{ "user": { ... as above ... },
  "at": { "note": "<id>", "title": "Roadmap", "kind": "note", "doing": "reading" | "editing",
          "cursor": null, "pointer": null } }
```

`at` is null while Claude is online but on no note (it listed notes, searched, or read the account). The account's
room carries personal notes' `at`; an organization's carries that organization's notes' `at`.

### Lifetime

- The connector opens one relay socket per account on its first tool call, joins the presence rooms, and publishes
  its state. Each tool call renews it: `touch()` with what the call is doing (reading note X, editing note X, or
  nothing in particular).
- Five minutes after the last call it leaves every room and closes the socket. It renews awareness every 15 seconds
  while open (y-protocols does), so a device forgets it within 30 seconds of the socket going.
- On the hosted server the socket belongs to the account's session store, not the per-request MCP server.
- A 4401 close (token expired) renews the session (`GlyphAccount.resume`) and reconnects once.

### Typing into a note

- **An organization's note:** the connector joins the note's room (`room = noteId`, `org`) with a document of the
  note's lineage (the `looseTeamDoc` mcp/team.ts already builds). If `joined` says there are peers, it streams the
  edit; if not, it writes as today and leaves.
- **A personal note:** the connector joins the note's room (`room = noteId`, no `org`) as a device that never seeds:
  on `first` it leaves and writes as today; otherwise it queries, adopts the state (keeping the seed), streams the
  edit, and leaves. The note's write to the account (`PUT notes/<id>`) still follows, as a device's pass would.
- **Streaming:** the change is diffed against what the room holds; deletions are applied at once, insertions in
  chunks of a few words (about 40 ms apart, the whole capped near six seconds however long it is), each its own Yjs
  transaction sent as an `Update`. Before each chunk the connector's awareness carries
  `cursor: { anchor, head }` (Yjs relative positions as JSON, as y-codemirror writes them) at the end of what it has
  typed, so Claude's caret leads the words. When it is done it clears `cursor` and leaves the room.
- The log of record is still written (an organization's updates posted, a personal note's record put): the room is
  only how a watching device sees it happen.

### Carets in the app

- Team notes already draw remote carets with the name on them; Claude's is drawn the same way, in `hue`.
- Personal notes (new): a personal room's session handles `Kind.Presence` and draws the carets of `ai: true` entries
  only. The account's own devices still do not show each other's carets (LIVE.md, "carets are not shared between
  your own devices").
- Words that arrive from an `ai: true` peer may rise "out of smoke" as the recorder's do (lib/editor/ai/
  wisp_arrivals.dart), with Ghostly typing on.

### Live typing for personal notes

The per-device "Live typing (trial)" switch (lib/live/enabled.dart) turns on by default: a personal note open on a
device joins its room, so Claude can type into it. The switch stays, to turn it off.

## Suggest mode

`update_note` and `append_to_note` take `suggest: true`. Then the connector does not change the words: it writes
the change as CriticMarkup, which other markdown apps read too:

- an insertion `{++new words++}`
- a deletion `{--old words--}`
- a replacement `{~~old~>new~~}`

each followed by `{>>Claude<<}`, the author. The app (new, lib/editor/suggestions/) draws an insertion underlined in
the author's colour, a deletion struck through, the author note hidden, and each with Keep and Revert on a tap; a bar
over the note says "Claude suggested N changes" with Keep all and Revert all. Keep and Revert are ordinary edits:
Keep writes the new words without the marks, Revert the old ones.

## Comments

New tools: `list_comments` (a note's threads: id, the words they are on, each message, resolved), `add_comment`
(on given words of the note, or the note as a whole), `reply_to_comment`, `resolve_comment`. They read and write the
format tauri/docs/SHARED.md defines (`[^c1]` and the ```comments fence), as the app's own code does, with the AI's
name as the author.

## Resources, prompts, subscriptions

- Resources: `ghost://note/{id}` for every note (listed newest first, at most 100), its markdown as `text/markdown`,
  so a person can attach notes in Claude's app.
- Subscriptions: the local stdio connector accepts `resources/subscribe` and tells Claude when a subscribed note
  changes (it pulls every 20 seconds while anything is subscribed). The hosted one cannot push (a JSON response per
  request) and does not offer it.
- Prompts: `weekly-review`, `plan-my-day`, `tidy-note` (argument: note title), `ask-claude-inbox`.

## The Ask Claude inbox

A personal note titled "Ask Claude": a list of `- [ ]` requests. The `ask-claude-inbox` prompt (and a scheduled
routine on Matt's Mac that runs it) works through the open ones: does each, writes what it did as an indented line
under it, and ticks it.

## Ownership

| Part | Where |
| --- | --- |
| Relay client in the connector, presence, typing, lifetime | mcp/live.ts (new); tauri/src/app/core/live/teamRoom.ts (TeamRoom moved out of team.ts so Node can import it); `ws` in tauri/package.json; scripts/build-mcp.mjs |
| Connector tools: suggest, comments, resources, prompts, subscriptions | mcp/server.ts registrations; mcp/suggest.ts, mcp/comments.ts, mcp/resources.ts, mcp/prompts.ts (new) |
| App: AI presence, chip, Follow, notice, account presence room, personal carets, switch default | lib/live/*, lib/orgs/ui/*, lib/home/*, lib/root/* |
| App: suggestions drawn with Keep and Revert | lib/editor/suggestions/* (new), wired in lib/root/note_desk.dart |
