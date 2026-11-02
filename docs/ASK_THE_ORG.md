# Ask the org: answers from your notes, with receipts

Matt, 2026-11-02, from a list of AI ideas: "'Ask the org' with receipts: questions answered only from your notes,
every claim linked to the note and line it came from; when notes disagree, it shows both instead of guessing."

There was no "ask your notes" before this (the AI expansion plan named one; nothing was built). The chat with Claude
(lib/claude/claude_chat.dart) can search and read notes with its tools, but it answers in its own words, from
anything it knows, and says nothing about where a sentence came from. Ask is the narrow, honest version: one
question, one scope, an answer made only of what the notes say, each sentence carrying the lines it stands on.

The code is in `lib/ask/`; the root's wiring in `lib/root/root_ask.dart`.

## Scope

A question is asked of exactly one of:

| Scope | Notes | Where it is offered |
|---|---|---|
| **My notes** | every note filed in no organization (personal workspaces, unfiled) | the command palette (`Ask my notes`), the sheet's scope chips |
| **An organization** | the notes filed in its workspace or any folder under it (GHST-107), or under `orgs/<Org>/` on disk | an **Ask** word on its teamspace home (lib/orgs/ui/teamspace_home.dart), the palette (`Ask <Org>`), the chips |
| **A folder** | the notes in that folder and the folders under it; a folder inside an organization stays that organization's | the chips, behind More |

Never two organizations, never personal and an organization together (`lib/ask/ask_scope.dart`): the scope is one
value, the notes are filtered by it before anything is read, and the answer's citations are checked against the same
filter, so a model that names a note out of scope has that citation dropped. Trashed and archived notes are left out.

"Only members' visible notes": an organization's notes on this device are the ones this account was sealed (its
team key opened them, lib/team/), so what a member can read is what Ask can read; nothing is fetched for it.

## Retrieval (on the device, always)

`lib/ask/ask_retrieve.dart`. Team notes are end-to-end sealed and opened on the device, so retrieval never runs on
the service; the hosted connector is not given it (see "The connector" below).

1. **Passages.** Each note in scope is cut into passages: a heading starts a new one, a blank line ends a paragraph,
   and paragraphs are joined up to about eight lines or 700 letters. Front matter and fenced code's fences are left
   out of the text but keep their place in the counting, so a passage's lines are the note's own lines, counted from
   1 as the editor counts them (`line:12` lands there). Each passage's id is stable: `<note id>#L<from>-<to>`.
2. **Words.** The question's words of two letters or more, less the common ones ("what", "did", "the"...), each also
   as its plain stem ("meetings" → "meeting").
3. **Score.** Per passage: each word found (whole, or as the start of a word of four letters or more) weighs by how
   rare it is across the scope's passages; a word in the passage's heading counts half again, in the note's title
   once more. A note the app's own search finds for the words (lib/core/search_hits.dart `findNotes`, which forgives a
   slip) is lifted; so are the notes the best notes link to with `[[links]]` and the ones linking to them, a little;
   and a note changed in the last fortnight, a little.
4. **Sent.** The best passages, at most four from one note, up to twelve passages and about 7,000 letters for a cloud
   model, six and about 2,500 for the device's. With nothing found the model is not asked: the answer is "Not in your
   notes".

## The prompt

`lib/ask/ask_prompt.dart`. The system prompt says: answer only from the passages; every sentence cites the lines it
stands on with a quote copied word for word from them; if the passages do not answer, say so; if passages disagree,
give each side, never pick one; no general knowledge (unless the person turned it on, and then each such sentence is
marked `general`). Each passage is sent as

```
<passage note="n1a2" title="Standup Oct 27" written="2026-10-27" lines="4-9">
4: ## Launch
5: We ship on Thursday.
...
</passage>
```

The answer is JSON:

```json
{
  "notFound": false,
  "sentences": [
    {"text": "The launch moved.", "citations": [{"noteId": "n1a2", "fromLine": 5, "toLine": 5, "quote": "We ship on Thursday"}]},
    {"text": "Releases go out from main.", "general": true, "citations": []}
  ],
  "conflicts": [
    {"about": "The launch day", "sides": [
      {"text": "Thursday", "citation": {"noteId": "n1a2", "fromLine": 5, "toLine": 5, "quote": "We ship on Thursday"}},
      {"text": "Monday", "citation": {"noteId": "n9f0", "fromLine": 3, "toLine": 3, "quote": "launch is now Monday"}}
    ]}
  ]
}
```

A fence round it, or words before and after, are forgiven (`lib/ask/ask_answer.dart` `parseAskJson`).

## Receipts: every quote checked

`lib/ask/ask_answer.dart` `validateAsk`. For each citation:

- its note must be one of the passages sent (so in scope), and its lines inside the note;
- its quote, with case, spacing, curly quotes, dashes and Markdown's marks evened out, must appear in those lines.

A quote found in another of that note's sent passages has its lines moved to where it really is. Any other citation is
**dropped**. A sentence left with no citation is left out of the answer (unless it is `general` and general knowledge
is on), and the answer says how many were left out and why. A conflict needs two sides from two different places
that both keep their citation; with fewer it is not a conflict, and a side left standing is an ordinary sentence. The
sides are ordered newest first, by the note's written date (its creation).

## The sheet

`lib/ask/ask_sheet.dart`, a sheet over the app (lib/sheet/sheet.dart).

- **Ask \<scope\>** as its title; one line to type the question on; Ask.
- Above it the scope's chips (My notes, each organization this account is in), and behind **More** the folders and
  **Use general knowledge too** (off by default; while on, its sentences are drawn in a muted face with "General
  knowledge, not from your notes"). In simple mode (`preferences.value.simple`) the chips and the switch are behind
  More too, and the sheet is the box and its answer.
- A line under the box says who answers: "Answered by Claude, from HelloTrade's notes. Only the passages it finds are
  sent." With Local only on (or no cloud model set up) it is the device's model: "Answered on this device by Gemma 3
  1B. A small model may miss or misread passages."
- **The answer**: its sentences, each followed by small numbered chips; then "Your notes disagree", each conflict as
  "[[Standup Oct 29]] says Monday · [[Standup Oct 27]] says Thursday", newest first, each with its chip; then the
  **Receipts**: each number with its note's title, its lines and the quote. A chip or a receipt opens the note at
  `lines:<from>-<to>`: the page scrolls to the first line and the lines are selected, which is their highlight
  (lib/note/land_at.dart).
- **Not in your notes**: "Your notes don't say. Nothing in HelloTrade's notes answers this." with the words looked for.
- **Save as note**: a markdown note, `Ask: <question>`, filed where the scope is (the organization's workspace, the
  folder, or the personal workspace chosen), with the answer, `[^1]`-style numbers, and a Receipts list of
  `[[Note title]]` links with their lines and quotes (`lib/ask/ask_note.dart`). Markdown first: the receipts are in
  the file, readable without the app.

## The AI

`lib/ask/ask_model.dart`. Whatever is connected, as the chat chooses (lib/assistant/assistant.dart `chatBy`): Claude
with its key, else the first other provider set up; each through the provider layer in the Messages API's shape, read
whole with `aiText`, metered on the provider's spending limit. Local only (`preferences.value.localOnly`) or no cloud
model: the device's formatting model (`preferences.value.formatModel`) through lib/ai/backend.dart `generate`, with the
smaller passage budget, and the sheet says retrieval quality may be lower. Neither: the sheet says to set one up in
Settings › AI.

## Privacy

- Retrieval runs on the device. Only the passages chosen, with their note titles and dates, go to the model; never the
  rest of the note, never another scope's notes.
- An organization's sealed notes are opened on the device; with a cloud model, their passages go to that provider as
  any chat does. The sheet's line says whose notes go where before anything is sent.
- Nothing is kept of a question unless Save as note is pressed.

## The connector

Not added. The hosted connector (mcp/) reads the account's notes on the service, where team notes are sealed; a tool
there could only cover personal notes, and Claude already has search_notes and read_note for those. Left as an open
question.

## Tests

`test/ask/`: scope (personal, org, folder, never mixed), retrieval (passages and their lines, ranking, budgets,
nothing found), validation (a made-up quote dropped, wrong lines moved, an out-of-scope note dropped, a conflict with
one side left), the sheet (chips, conflicts newest first, not in your notes, a chip opening the lines, Save as note,
simple mode), and land_at's `lines:` range. Pictures under `build/feature-shots/ask/` with `--update-goldens`.
