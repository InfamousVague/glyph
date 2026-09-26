# The Claude connector, inside

_How `mcp/` signs in as one more device, seals what it writes the way the app does, and serves the same tools from a person's own computer or from the server._

## One more device

The connector is a client of the sync service and nothing more. It never talks to the app. It reads and writes the account's notes on the same wire a phone uses, sealing and opening them with the account key, and a note it writes reaches the other devices like any device's note.

It imports the app's own code rather than keeping copies:

- `core/sync/crypto.ts` for the keys and the seal
- `core/noteTitle.ts` for titles
- `core/imageRefs.ts` for the pictures a body names
- `capture/listAppend.ts` for placing words in a list
- `core/authors.ts` for authors

## The account as a client

All of this is `mcp/glyph.ts`.

- **Signing in.** `GlyphAccount.signIn` derives the password's two halves exactly as the app does. It sends the login half to `POST login` and unwraps the account key with the other half. It then makes an Ed25519 signing key of its own and registers it as a device labelled Claude, so a lapsed session can be renewed without the password. It returns a `StoredSession`: the service, the handle and account id, the token, the raw account key, and the signing key as a private JWK. Unlike the app's keys, these can be exported, because the local connector keeps them in a file between runs.
- **Renewing.** `resume` tries `POST refresh`. Once the token has lapsed, it signs a challenge with the device key instead. A call that meets a 401 renews once and tries again, so a long-running server never notices a token lapsing.
- **Reading.** `pull` pages through the feed from its cursor and opens each note under `note:<id>`. It keeps a cache of records: each note, the revision seen, and the recording hash and picture names the note carried.
- **Writing.** Every write is sealed the way the app seals one and sent with the revision it was read at. `create` writes a new note from no revision. `edit` keeps everything the note carried (its created time, pin, folder and recording) and names every picture the new words show. When the words change, it drops the formatted copy. A 409 becomes a `Conflict` carrying the other device's note, which also replaces the copy in the cache. Nothing is written over a note that was not read first.

## The tools

`mcp/server.ts` builds the MCP server. Every tool that reads or changes a note pulls the account fresh before it acts. `create_note` writes a new note without reading first, and `sign_out_everywhere` reads nothing. When the sync service refuses a request, the tool answers with the refusal in words rather than crashing.

| Tool | What it does |
|---|---|
| `list_notes` | notes, newest change first, with an optional title filter and archived notes on request; 50 by default, up to 500 |
| `read_note` | one note in full, by id, by exact title, or by the only title that contains the words |
| `search_notes` | notes whose words contain the query, with a snippet around the first match; 20 by default, up to 200 |
| `create_note` | a new note from Markdown; a `title` becomes a `# ` heading if the body has none |
| `update_note` | replaces the whole body, from the version last read; an empty body is refused |
| `append_to_note` | places a task, an item or a paragraph the way the app's "add task" does |
| `set_note_flags` | pins or archives a note, or undoes either |
| `account_status` | which account, which service, how many notes, and how many connections |
| `sign_out_everywhere` | hosted only: ends every Claude connection to the account |

Every build has the first eight. The ninth is added only when the hosted server hands in its hooks. There is no delete tool: archiving takes a note out of the list, and the app can undo it.

A note the connector creates, rewrites or adds to names the AI in its `authors:` front matter. Pinning or archiving leaves the authors alone. If the note named nobody before, the account's own handle goes first (`withAuthor` in `core/authors.ts`). The AI's name is the tool's `author` argument, or else the name the client gave when it connected (`aiName` reads `claude-ai` as Claude). A rewrite never drops an author the note already had.

## Serving it on a person's computer

`mcp/main.ts` is the entry point that `scripts/build-mcp.mjs` bundles into `mcp/dist/glyph-mcp.mjs`. The commands themselves are in `mcp/cli.ts`.

| Command | What it does |
|---|---|
| `login <handle>` | asks for the password without showing it, signs in, and keeps the session |
| `status` | says which account is signed in and how many notes it has |
| `logout` | removes the session file |
| `version` | prints the version |
| `serve`, or no command | serves the tools over stdio; this is what Claude starts |

The session is kept in `session.json` in `~/.config/glyph-mcp` (under `XDG_CONFIG_HOME` when that is set), or in the folder `GLYPH_MCP_HOME` names. A folder the command makes is readable by its owner only (mode 0700), and so is the file (mode 0600). The password is never written down. A headless setup can give `GLYPH_HANDLE` and `GLYPH_PASSWORD` in the environment instead, and the connector then signs in at each start. Everything the command touches comes in through `CliIo`, so its tests can run it against a folder, a terminal and a sync service of their own.

## Serving it hosted

`mcp/hosted.ts` is an express app. `mcp/hosted-main.ts` starts it, and every ten minutes sweeps away whatever has run out. It is reached at `https://attack.fm/glyph/api/mcp`, through `server/src/mcp_proxy.rs`.

OAuth 2.1 comes from the MCP SDK's own handlers: dynamic client registration, the authorisation code with PKCE (S256), refresh tokens and revocation. The discovery documents live under the same path.

`authorize` answers with the sign-in page (`mcp/loginPage.ts`). The page's own script does in the browser what a phone does at sign-in, using the app's `ROUNDS`, which are written into the script:

1. It derives the password's two halves.
2. It sends the login half to the public sync service.
3. It unwraps the account key.
4. It posts the token and the raw key to `authorize/complete`.

The password never reaches the connector. The page is served with a content security policy that lets it reach only itself and the sync service, with no caching and no referrer, and before it asks for the password it says what the connection will be able to do.

`authorize/complete` imports the key as one that cannot be exported, and only if it is exactly 32 bytes. It renews the token and pulls the notes to prove the key opens them, then makes the session and the code. MCP itself is served at the base path as `POST`, one request and one answer. Each request builds a fresh server over the session's account, so the name the client gave at `initialize` is kept on the session for the authors line.

`mcp/hostedStore.ts` holds everything in memory, so a restart signs everyone out.

| What is held | How long |
|---|---|
| a sign-in request | 10 minutes |
| a code | 10 minutes |
| an access token | an hour |
| a refresh token | 30 days |
| a session, with its key | until its tokens are gone, after a week unused, or once the week-long sync token it holds runs out |

Revoking a token, as disconnecting in Claude does, ends its session, and the key goes with it.

## Node 18

From Node 19, WebCrypto is on `globalThis` already. On Node 18 it is not, and importing a key throws. `mcp/webcrypto.ts` puts Node's WebCrypto on `globalThis` where it is missing. Both entry points call it first (the local one through `runCli`), so the fix travels inside both bundles.

## Two bundles

`scripts/build-mcp.mjs` (`npm run mcp:build`) writes two files with esbuild:

- `mcp/dist/glyph-mcp.mjs`, built from `main.ts` for Node 20, to run on a person's own machine
- `mcp/dist/glyph-mcp-hosted.mjs`, built from `hosted-main.ts` for Node 18, with the sign-in page's typeface folded in

`node scripts/deploy-ota.mjs --mcp` publishes the local bundle at `https://attack.fm/glyph/mcp/glyph-mcp.mjs`. `scripts/deploy-server.mjs` ships the hosted one.

## Tests

`mcp/testKit.ts` holds what the tests share: a note as another device wrote it, an account signed in to the in-memory sync service in `src/test/fakeService.ts`, and Claude connected over in-memory transports, including Claude's side of OAuth and the sign-in page's script.

- **`mcp/glyph.test.ts`** checks that the password is derived and the key unwrapped as the app does it, that a lapsed token is renewed in the middle of a call, and that the feed is followed. It checks that an edit keeps what the note carried, and that a write over another device's change is refused with that device's words.
- **`mcp/server.test.ts`** covers each tool, authors kept through a rewrite, a conflict shown rather than written over, and the hosted hooks.
- **`mcp/hosted.test.ts`** checks that Claude finds the server from the 401, registers, and signs in on the page, and it covers tokens and refresh. It checks that a stale page and a key that is not a key are refused. It checks that a week unused, a disconnect, and a session the sync service will no longer renew each end the session.
- **`mcp/mcp.e2e.test.ts`** puts a phone running the app's own `syncNotes`, the built local server over stdio, and the built hosted server over HTTP with the full sign-in, all on one real glyph-api. Each half runs only when `GLYPH_MCP_E2E=1` is set and its bundle is built, with `VITE_GLYPH_API` pointed at a local glyph-api.

`cli.test.ts`, `loginPage.test.ts` and `webcrypto.test.ts` cover the command, the page's script and the shim.

## Where MCP.md and the code differ

- MCP.md says "eight tools", but its table holds nine rows. The paragraph on authors sits in the middle of the table and splits it in two. The local build has eight tools, and the hosted build has those eight and `sign_out_everywhere`. The Claude page in Settings also says eight, which is true of the local build.
- It says every tool reads the account fresh before it acts, and so does the Claude page in Settings. `create_note` writes without reading first, and `sign_out_everywhere` reads nothing.
- Its table of pieces gives `mcp/main.ts` as the command. The commands are in `mcp/cli.ts`, which also has `version`. The table leaves out `cli.ts`, `hostedStore.ts`, `loginPage.ts`, `webcrypto.ts`, `testKit.ts` and `server.test.ts`.
- It says `build-mcp.mjs` makes `mcp/dist/glyph-mcp.mjs`. It makes that and `glyph-mcp-hosted.mjs`.
- It lists the thirty-day refresh token among what ends a hosted session. In practice the week-long sync token ends it first. The session holds the sync service's seven-day token, renewed once at sign-in and never again before it lapses, and the hosted account has no device key to renew it afterwards. So a hosted connection ends about a week after sign-in, used or not, and Claude asks for sign-in again.
- It gives `~/.config/glyph-mcp` as the session folder when `GLYPH_MCP_HOME` is not set. The code also honours `XDG_CONFIG_HOME`.

## Read next

- [[Claude on your notes]]
- [[Tests, and the report that ships]]
- [[Where the docs and the code disagree]]
