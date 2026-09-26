# Claude on your notes

_Claude can read your notes, search them, add to them and change them, from wherever you use Claude. It cannot delete one._

## What it is

Ghost.md has a connector for Claude, an MCP server. Through it Claude signs in to your Ghost.md account and works with its notes the way another of your devices would. So it needs an account, and it sees what has synced. A note Claude makes or changes reaches your devices at their next sync, as one typed on a phone would.

The Claude plugin is only a page: **Settings › Claude**, also reached from Claude's card in Settings › Plugins. It carries **How to connect**, **Server address** with a **Copy**, and **On your own computer**. The first and the last each open a drawer of steps, with a Copy beside every command. Below them come what Claude can do and where your key lives. The plugin's switch shows or hides the page. Connecting and disconnecting are done in Claude.

With Local only on, the page is hidden and this device stops syncing, so what Claude writes waits until it is off.

## Two ways in

| | Hosted | On your own computer |
| --- | --- | --- |
| To install | Nothing | One file, run with Node 20 or newer |
| Your account key | Held in the memory of Ghost.md's server while Claude is connected | Stays on your computer |
| Ends when | You disconnect in Claude, Claude signs out everywhere, a week goes by unused, or the server restarts | You sign out on that computer and remove the server from Claude |

### Hosted

1. **Add the server to Claude.** In claude.ai or Claude Desktop: Settings › Connectors › Add custom connector, with the address `https://attack.fm/glyph/api/mcp`. In Claude Code, one line: `claude mcp add --transport http glyph https://attack.fm/glyph/api/mcp`
2. **Sign in on the page that opens.** It says "Let Claude use your notes." Give your handle and password and choose **Allow**.
3. **Ask in words.** "What's in my Groceries note?" "Add 'book the ferry' as a task to my Trip plan."

Your notes are end-to-end encrypted, so whatever reads them must hold your account key. The page works the key out in your browser, as a phone does at sign-in, and your password stays there. It hands the key to Ghost.md's server, which keeps it in memory only, never on disk, as a key it can use but not read out. While you are connected, the server can read your notes: that is what lets Claude. The page says so before it asks for the password.

The key is forgotten when you disconnect the server in Claude, when you ask Claude to sign out everywhere, after a week without use, or when the server restarts, after which Claude asks you to sign in again. Changing your password does not end it. Disconnect to be sure.

### On your own computer

Get the file, sign in once, and tell Claude where it is:

```
curl -fsSL https://attack.fm/glyph/mcp/glyph-mcp.mjs -o ~/glyph-mcp.mjs
node ~/glyph-mcp.mjs login <your handle>
claude mcp add glyph -- node ~/glyph-mcp.mjs
```

That last line is for Claude Code. In Claude Desktop, open Settings › Developer › Edit Config, add the server under `mcpServers` with the full path to the file, not `~`, and restart it. When this device is signed in, the drawer fills your own handle into the sign-in line, ready to copy.

The password is typed at the prompt and never stored. What is kept is what a signed-in phone keeps, in `~/.config/glyph-mcp/session.json`, readable by you alone: the session, your account key, and a signing key of its own. Anyone who can read that file can read your notes, so keep it as you keep your phone. The server talks to nothing but Ghost.md's sync service. `node ~/glyph-mcp.mjs status` says which account it is signed in to, and `node ~/glyph-mcp.mjs logout` forgets it.

## What Claude can do

| Ask it to | Its tool | What happens |
| --- | --- | --- |
| List your notes | `list_notes` | Newest change first, each with a line of preview. It can narrow by title. |
| Read a note | `read_note` | One note in full, by its title or its id. |
| Search | `search_notes` | Notes whose titles or words contain something, with the line around it. |
| Make a note | `create_note` | From Markdown, with a title as its heading. Every mark works: lists, to-dos, tables, boards. |
| Rewrite a note | `update_note` | The whole body replaced. |
| Add to a note | `append_to_note` | A task or an item joins the note's list in its own style, as the app's own adding does. A paragraph goes on the end. |
| Pin or archive | `set_note_flags` | Either one, and undo either. |
| Say which account | `account_status` | Whose notes these are, how many, and how many Claude connections the account has. |
| Sign out everywhere | `sign_out_everywhere` | Hosted only. Ends every Claude connection to the account, this one included. Each signs in again on the page. |

There is no delete. Claude can archive a note, which you can undo in the app. Emptying the trash is yours alone.

## Never over another device

Before Claude reads or changes a note, its tool reads the account fresh, so Claude sees what your phone last wrote. A write goes from the version just read. If another device changed the note in between, the write is refused and Claude is shown that device's words, to read and try again. Your own edit is never written over.

## Its name on the note

A note Claude makes, rewrites or adds to lists Claude among its authors, after your own handle, in the note's front matter:

```
---
authors: <your handle>, Claude
---
```

The note shows its authors as a byline, a book gathers them in its index, and a shared page shows them too. A person is an initial in a ring; an AI the app knows wears a spark. A rewrite never takes anyone off. Pinning and archiving add no name.

Claude sees the words of the notes it reads, as it sees anything you paste into it, under Anthropic's own terms.

## Read next

- [[Accounts, sync and the key you hold]]
- [[What stays on your phone]]
- [[The Claude connector, inside]]
