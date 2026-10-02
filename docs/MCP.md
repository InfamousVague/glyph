# Ghost.md for Claude: the MCP server

Claude can read, add and update the notes in a Ghost.md account, through an MCP server: hosted on the box beside the
sync service, or run on your own computer. Matt's brief (2026-09-18): "make an MCP plugin for Claude so I can use Claude to remote control my
account and add and update notes as well as read them, be detailed and make sure it all works for every user".

It works for any Ghost.md account, and it comes two ways:

- **Hosted** (the easy one): Claude connects to `https://ghostmarkdown.com/api/mcp`, you sign in on a page once, and
  that is all. Nothing to install. While you are signed in, Ghost.md's server holds your account key in memory (below).
- **On your own computer**: one file you run with Node, which keeps your key on your machine and the server never
  sees it. For anyone who would rather keep end-to-end encryption whole.

## What it can do

Once it is connected, ask Claude in words. Behind them are thirteen tools, and a fourteenth on the hosted server:

| Tool | What it does |
| --- | --- |
| `list_notes` | Your notes, newest change first: id, title, dates, pinned, archived, folder, a line of preview. `query` narrows by title. |
| `read_note` | One note in full, by id or by title, or a ticket by its key, `GHO-12` (docs/TICKETS.md). |
| `search_notes` | Notes whose words contain something, with a snippet around the match. |
| `create_note` | A new note from markdown, with a title as its heading. Every mark the app draws works: headings, lists, `- [ ]` to-dos, tables, boards. |
| `update_note` | A note's whole body replaced. |
| `append_to_note` | Words added the way the app's own "add task" adds them: a task or an item joins the note's list, in the list's style; a paragraph goes on the end. Not a journal, whose words are the list of its entries: it says to use the next tool. |
| `add_journal_entry` | An entry in a journal (a notebook kept as a journal, DESIGN §142), as the app writes one: a note named by the minute, "2026-09-28 14.05", started from the journal's template, with the words going on from its time line or into its to-do list, and its line added to the journal. `at` is the person's local time, `YYYY-MM-DDTHH:MM`; left out, the time where the local server runs, and the hosted one asks for it, since its clock is not yours. Never a place. |
| `set_note_flags` | Pin or archive a note, or undo either. |
| `list_workspaces` | The workspaces notes are filed under, as the app lists them: id, name, whether it is an organization's (`org-<orgId>`, made by the app for each organization you are a member of, docs/TEAMS.md), and how many notes each holds. |
| `file_notes` | Notes filed under a workspace by its name or id, as a note's Workspace setting does in the app, moving them from any other; or `unfile` to take them out. Only an existing workspace: it never makes one, so an organization's appears once the app has synced the organization. |
| `get_rules` | The "Claude rules" note: your standing instructions for Claude on this account. Made, pinned, the first time it is wanted. |
| `add_rule` | Records a standing or repeated request into the "Claude rules" note, so Claude keeps doing it: for when you say to always, from now on, or again do something. |
| `account_status` | Which account this is, where its sync service is, how many notes it holds, and how many Claude connections it has. |
| `sign_out_everywhere` | Hosted only. Ends every Claude connection to the account - every Claude account and computer signed in to it, this one included; each signs in again on the page. |

**Authors.** A note the AI creates, rewrites or adds to lists it among the note's authors, after the account's own
handle: `authors: infamousvague, Claude` in the front matter (`src/app/core/authors.ts`). The name is the tool's
`author` argument when given, else what the AI's app called itself when it connected ("claude-ai" is Claude). The
hosted server builds a fresh server for each request, so it keeps that name on the sign-in session: the name the app
registered with, then its `initialize` clientInfo. A rewrite never drops an author the note already had. The app
draws the authors as a byline: on the note, gathered across a notebook in its index, and on a shared page. A known
AI wears a spark, and anyone else their initial.

**Notifications.** Each write Claude makes is told to the account's own notifications feed (docs/TEAMS.md), so the
bell on your phone lights and the Notifications page reads "Claude edited Trip to Lisbon · 2 lines changed". After a
write lands - `create_note`, `update_note`, `append_to_note`, `add_journal_entry`, `add_rule`, and the Claude rules
note the first time it is made - the server posts one self notification, `POST notifications { id, kind, blob }`,
sealed under the account key exactly as the note was, with `notification:<id>` as its context and the kind inside the
seal: `note-created` carries `{ noteId, title, by }`; `note-edited` a line diff, `{ noteId, title, by, added,
removed, first, at }` - how many lines came and went, the first changed line (at most 120 characters) and its anchor,
so the row opens the note at that line; `note-appended` `{ noteId, title, by, lines, first }`; `journal-entry`
`{ noteId, title, by, journal, first }`; `rule-added` `{ noteId, title, by, first }`. `by` is the author the tool
resolved, as above, or `Claude` when the connection gave no name. The sync service sees only the kind and the time:
the title and the lines are inside the seal. The post is best effort and never the tool's answer: a write refused by
the service (another device's words, below) posts nothing, and a post that fails - a sync service without the route
yet, which answers 404 `no such route` - is swallowed with a `glyph-mcp:` line on stderr and the tool still answers.
The app's own switch for these rows is Settings › Notifications › Claude.

**Workspaces.** Which workspace a note is filed in is not part of the note: it is one of the synced settings
(core/sync/prefs.ts), a single object sealed under the account key, `workspaces: { list, notes }`, the second a map of
note id to workspace id. `file_notes` reads the settings with their revision, changes only that map, and writes the
whole object back from the revision it read (`GlyphAccount.changePrefs`), keeping every other setting as it came,
known to this client or not. If another device wrote its settings in between, the service refuses the write and the
change is made again on theirs, once. Filing is per person, as in the app: an organization's workspace files your
copy of a note, and does not share it with the organization's other members.

Every tool reads the account fresh before it acts, so Claude sees what your phone last wrote. A write goes from the
version just read: if another device changed the note in between, the service refuses the write and Claude is shown
that device's words instead, never over them. That is the rule the app itself lives by (docs/SYNC.md).

A note Claude makes or changes reaches every signed-in device at its next sync, exactly as one typed on a phone would.
There is no delete: archive a note instead (`set_note_flags`), which the app can undo. Emptying the trash is a thing
you do in the app.

**The Claude rules.** Your account keeps a note called **Claude rules**: your standing instructions for Claude when it
works here. It is made (and pinned) the first time Claude connects, seeded with what the note is for and a sensible
default you can keep or change (`mcp/server.ts` `ensureRulesNote`, `DEFAULT_RULES`). On connect it is handed to Claude
as the server's MCP instructions, so Claude follows it without being asked and can re-read it any time with `get_rules`.
When you ask Claude to always, from now on, or again do something, it writes that standing request into the note with
`add_rule`, under a "Standing requests" heading, so it is not lost the next time you connect. It is a note like any
other: edit it in the app to change the rules, or archive it to clear them. The rules are the oldest note of that name
that is not archived, whatever the case of its letters, so a second one made by hand changes nothing; connections
opened together take turns finding it, so they make one between them (`rulesNoteIn`). Until 2026-10-02 a name two
notes shared was found as none, and every connection made another.

These steps are also in the app: the Claude plugin's page (Settings › Plugins › Claude) carries the address with a
Copy, and an instructions drawer with the steps for either way, each command with its own Copy
(`src/app/plugins/claude/`).

## Setting it up: hosted

Add `https://ghostmarkdown.com/api/mcp` to Claude as a remote MCP server. Where that is:

- **claude.ai and Claude Desktop**: Settings › Connectors › Add custom connector, with that URL.
- **Claude Code**: `claude mcp add --transport http glyph https://ghostmarkdown.com/api/mcp`
- **Any other MCP client** that speaks HTTP with OAuth: the same URL.

Claude opens a Ghost.md page in your browser: sign in with your handle and password, and you are back in Claude with
the tools ready. That is the whole setup, on every device you use Claude from.

**What the hosted server keeps.** Your notes are end-to-end encrypted, so a server that reads them has to hold your
account key. The sign-in page unwraps the key in your browser - your password stays there; the sync service sees the
same login half it sees from your phone - and hands the key to the MCP server, which keeps it **in memory only**, as
a key object the process cannot read out, never on disk. For as long as that session lasts, the server can read your
notes: that is what lets Claude. The page says so before it asks for the password.

The session ends, and the key with it, when you disconnect the server in Claude (Claude tells it), when nobody has
used it for a week, when the refresh token runs out after thirty days, or when the server restarts (a deploy of the
MCP server itself signs everyone out - a deploy of glyph-api alone does not - and Claude asks you to sign in again).
Changing your Ghost.md password does not end it: disconnect to be sure.

## Setting it up: on your own computer

You need Node.js 20 or newer (`node --version`), and the server as one file:

```bash
curl -fsSL https://ghostmarkdown.com/mcp/glyph-mcp.mjs -o ~/glyph-mcp.mjs
```

Sign in once. The password is typed at the prompt and is not stored; what is stored is what a signed-in phone
stores (below).

```bash
node ~/glyph-mcp.mjs login <your handle>
```

Then tell Claude where the server is.

**Claude Code**, one line:

```bash
claude mcp add glyph -- node ~/glyph-mcp.mjs
```

**Claude Desktop**: Settings › Developer › Edit Config, and add the server to `mcpServers` (use the full path to
the file, not `~`):

```json
{
  "mcpServers": {
    "glyph": {
      "command": "node",
      "args": ["/Users/you/glyph-mcp.mjs"]
    }
  }
}
```

Restart Claude Desktop. Any other MCP client (Cursor, Windsurf, Zed, …) is configured the same way: the command is
`node`, the one argument is the file.

Then: "What's in my Groceries note?", "Add 'book the ferry' as a task to my Trip plan", "Make a note called
Standup with these three points", "Which notes mention the cabin?".

### Without a terminal prompt

A headless setup can give the handle and password in the environment instead, and the server signs in each time it
starts:

```json
{
  "mcpServers": {
    "glyph": {
      "command": "node",
      "args": ["/Users/you/glyph-mcp.mjs"],
      "env": { "GLYPH_HANDLE": "you", "GLYPH_PASSWORD": "…" }
    }
  }
}
```

The `login` command takes the password from `GLYPH_PASSWORD` too, for the one command, when there is no terminal.

### Commands

```
node glyph-mcp.mjs login <handle>   sign in and keep the session
node glyph-mcp.mjs status           which account, whether the session still works, how many notes
node glyph-mcp.mjs logout           forget the session
node glyph-mcp.mjs                  serve (what Claude runs)
```

`GLYPH_API` points the server at another sync service (the default is `https://ghostmarkdown.com/api`);
`GLYPH_MCP_HOME` moves the session file (the default is `~/.config/glyph-mcp`).

## What it keeps, and where the key lives

Ghost.md's notes are end-to-end encrypted: the sync service holds copies it cannot read, and every device that shows
them holds the account key (docs/SYNC.md, "Keys"). The MCP server is a device like that. After `login` it keeps, in
`~/.config/glyph-mcp/session.json`, readable by you alone:

- the session token (renewed as it runs, and renewed again with the server's own signing key when it lapses, so
  the password is never asked for twice - the same as a phone);
- the account key, which opens the notes;
- that signing key.

The password itself is never written down. The sync service never sees the key: the server unwraps it on your
computer with the half of the password that never leaves, seals every note it writes, and opens every note it reads,
exactly as the app does (`src/app/core/sync/crypto.ts` is the same code, bundled in). Anyone who can read that file can read
your notes, as anyone who can unlock your phone can; keep it as you keep the phone. `logout` removes it.

The server itself runs on your computer, started by Claude, and talks to nothing but Ghost.md's sync service. Claude
sees the words of the notes it reads, as it sees anything you paste into it, including where a tagged note was
written (its `location:` and `place:` front matter, DESIGN §134); `update_note` keeps that across a rewrite that
dropped it, as it keeps the authors, the keys that make a note a notebook, a journal or an entry (`title:`,
`book:`, `journal:`, `template:`, `entry-place:` and `date:`), the one that makes it your Templates notebook or one of
its pages (`templates:`), and how the note looks (`look:`, DESIGN §144) unless the new body gives one of its own. A
ticket (DESIGN §157) keeps its `type:` and `id:` through any rewrite, and its other properties through one that dropped
the front matter whole; front matter Claude writes itself is what it meant, so a status changed or a `blocked-by:`
taken off stays so. A notebook keeps the `key:` its tickets are numbered by and its `statuses:`.

## Where the pieces are

| | |
| --- | --- |
| `mcp/glyph.ts` | the account as a client: sign-in, the session's renewal, the note feed opened into a cache, writes sealed as the app seals them, the conflict rule, and the self notification posted after a write (`postNotification`) |
| `mcp/server.ts` | the tools: thirteen everywhere, and `sign_out_everywhere` on the hosted server; each writing tool tells the feed what it wrote |
| `mcp/main.ts`, `mcp/cli.ts` | the command: its entry point, and login, status, logout and serve |
| `mcp/webcrypto.ts` | WebCrypto on whatever Node runs it: the box's Node 18 has no global `crypto` until it is put there |
| `mcp/hosted.ts`, `mcp/hosted-main.ts` | the hosted server: OAuth with the SDK's handlers, MCP over HTTP, and its start-up from the environment; run on the box as `glyph-mcp.service` (`server/glyph-mcp.service`) |
| `mcp/loginPage.ts` | the hosted server's sign-in page, whose own script derives the password's halves and unwraps the key in the browser |
| `mcp/hostedStore.ts` | what the hosted server holds in memory, and when it lets go: clients, sign-in requests, codes, sessions and tokens |
| `server/src/mcp_proxy.rs` | glyph-api hands `/api/mcp` on to it, so the shared Caddy configuration is untouched |
| `scripts/deploy-server.mjs` | ships both services in one session; `--mcp-only` ships just the hosted server, and either way glyph-mcp is restarted only when its file changed, since a restart signs everyone out |
| `scripts/build-mcp.mjs` | the build, `npm run mcp:build`: two files into mcp/dist, `glyph-mcp.mjs` for a person's Node 20 and `glyph-mcp-hosted.mjs` for the box's Node 18. It imports esbuild, which package.json does not name: it arrives with Vite |
| `scripts/deploy-ota.mjs --mcp` | publishes the local file at https://ghostmarkdown.com/mcp/glyph-mcp.mjs; `scripts/deploy-server.mjs` ships the hosted one |
| `mcp/testKit.ts` | what the tests share: a note as another device wrote it, a tool's words, and an account in memory with Claude connected |
| `mcp/glyph.test.ts` | the client against a sync service stood in for in memory: sign-in, renewal, reading, writing, the conflict |
| `mcp/server.test.ts`, `mcp/cli.test.ts`, `mcp/loginPage.test.ts`, `mcp/webcrypto.test.ts` | the tools, the commands, the sign-in page's script, and WebCrypto on an old Node |
| `mcp/hosted.test.ts` | the hosted server connected to as Claude connects: the client library's own OAuth flow, the page, tokens, refresh, the tools, and a week's idleness ending the session |
| `mcp/mcp.e2e.test.ts` | a phone (the app's own sync code), the built local server over stdio, and the built hosted server over HTTP with the full sign-in, all on one real glyph-api: `GLYPH_MCP_E2E=1 VITE_GLYPH_API=http://127.0.0.1:<port>/api npx vitest run mcp.e2e` |

## How it was proven

- **Against a service in memory** (`mcp/glyph.test.ts`): the password derived and the key unwrapped as the app does;
  a lapsed token renewed with the device key, mid-call and without one being told to sign in again; notes listed and
  followed through the feed; a note made that the app opens; an edit that keeps everything the note carried (its pin,
  folder, recording) and drops the stale formatted copy; and a write over another device's change refused with their
  words.
- **Against a real glyph-api** (`mcp/mcp.e2e.test.ts`): a phone, run by the app's own `syncNotes`, writes a note; the
  client signs in with the password and reads it; what the client makes and edits is on the phone after one sync,
  with nothing copied twice. Then the built file is started over stdio as Claude starts it, its eleven tools listed,
  and each one called: list, status, create with a title, append an item and a task, read by title, search, replace,
  archive - and all of it on the phone afterwards.
- **By hand** on a local service: `login` with a password, the session file written mode 600 with the token, key and
  device key; `status` from the file alone; a raw MCP `initialize` and `tools/list` over stdio; `logout`. The
  commands are tested since (`mcp/cli.test.ts`), and so is the sign-in page's script (`mcp/loginPage.test.ts`).
- **The hosted server** (`mcp/hosted.test.ts`, and the last part of the e2e): the client library refused with a 401
  that says where the sign-in metadata is, finds it, registers itself, is sent to the page; the page's own steps
  sign in, unwrap the key and hand it over; the code becomes tokens; the tools work; an hour on the access token has
  run out and the library refreshes it unasked; a token never issued, a stale page and a non-key are refused; and a
  week's idleness ends the session, key and all. Then the same, with the built file run as the box runs it, against
  a real glyph-api, with a phone syncing what Claude did.
