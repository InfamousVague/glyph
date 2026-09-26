# glyph-api, the server

_One Rust binary behind attack.fm/glyph/api: accounts, sealed sync, shared links, the live relay, Notion's code swap and the door to Claude._

## The route map

`server/src/main.rs` merges every router into one, wraps them all in one CORS layer, and answers a route or method that does not exist in JSON.

| Path under `/glyph/api/` | What it serves | File |
|---|---|---|
| `v1/pubkey`, `v1/signup`, the `v1/login` routes, `v1/refresh`, `v1/device`, `v1/keys`, `v1/password`, `v1/recovery`, `v1/account` | accounts and session tokens | `accounts.rs`, `accounts/` |
| `v1/notes`, `v1/prefs`, `v1/recordings/{id}` | end-to-end encrypted sync | `sync.rs` |
| `v1/shares`, `v1/shares/{id}` | notes and books shared by link | `shares.rs` |
| `v1/live` | the live typing relay, a WebSocket | `live.rs` |
| `notion/start`, `notion/callback`, `notion/claim`, `notion/refresh` | Notion's OAuth code swap | `notion.rs` |
| `mcp`, `mcp/*` | the hosted Claude connector, passed through | `mcp_proxy.rs` |
| `health` | whether the service is up | `main.rs` |
| `format` (POST) | transcript annotations, which no client asks for any more | `format.rs` |

Accounts, sync, shares and the relay are merged in only when the service has a data folder. Without one, it runs the rest.

## Accounts and tokens

`accounts.rs` owns the service itself: the signing key, issuing and checking tokens, the sign-in limits, and the `Claims` extractor. Every signed-in HTTP handler takes `who: Claims` as an argument. The routes live beside it:

- `accounts/ways_in.rs` has the open routes that hand out a token: sign-up, password, device challenge and signature, and recovery code.
- `accounts/account.rs` covers what a signed-in device may do to its own account.
- `accounts/credentials.rs` holds the rules and hashes. A handle is 3 to 24 characters and a login half is 64 hex characters. The password's half is hashed with Argon2, and a recovery code's half with SHA-256.
- `accounts/challenges.rs` keeps in memory the nonces a device signs.

Every open route refuses a wrong handle and a wrong secret in the same words. The challenge route hands out a nonce whether or not the handle exists. So asking tells you nothing about which handles are taken.

`identity.rs` makes the `glyph1` token. It has three parts: a version tag, the claims (`sub`, `handle`, `iat`, `exp`) as base64url JSON, and an Ed25519 signature over both. It is not a JWT, so no algorithm can be chosen by whoever holds it. The signing key is made on first start and kept in the database's `meta` table, which makes that database the one thing to guard.

Tokens are not revoked: a token is only its signature and its clock. So a token outlives a deleted account until it lapses. Renewing it is refused, and the store has nothing left for it. The relay still admits it.

Axum runs the extractors that read a request's parts before the one that reads its body. So a request with no token is refused before its body is read.

## Who may ask, and how often

`guard.rs` holds the token bucket that every limit spends from, and a `RateLimiter` keyed by address or by handle. The address it counts is the one reported by the web server in front, believed only when it comes from that server.

| Limit | Value |
|---|---|
| sign-in | 20 a minute per address, and 10 per handle |
| share reads | 240 a minute per address |
| Notion sign-in | 30 a minute per address |
| live frames | per socket |
| format route | 20 a minute per address |

If a limiter's lock is poisoned, it refuses, because it guards a door.

## Sync, shares and the relay

All three hold the same `Accounts`, for its `claims` and its `store`.

- `sync.rs` keeps notes as sealed blobs, each written from a revision. It answers a stale write with a 409 carrying the note that won. Its limits are 1.4 MB a note, 350 KB of settings, 64 MB a file and 500 notes a page.
- `shares.rs` takes up to 6 MB of sealed share and up to 500 shares an account, with share ids of 22 to 64 characters. It answers reads with `Cache-Control: no-store`, so an edit or a take-down shows at once.
- `live.rs` is the relay ([[Live typing over a relay]]).

## Notion's code swap

A public Notion integration needs its client secret to swap a sign-in code for a token, and a secret cannot ship inside an app. `notion.rs` does that half and nothing else:

1. The phone opens `start` with a state and a PKCE challenge.
2. Notion sends the browser back to `callback`.
3. The service swaps the code and holds the answer.
4. The phone collects it from `claim`, with the verifier whose SHA-256 it sent at the start.

A pending sign-in lives ten minutes, and at most 256 are held at once. `claim` answers 202 while the callback has not come yet, and 404 once the sign-in has gone. `refresh` swaps a refresh token the same way. Nothing is written to disk. Without the integration's credentials, every route says sign-in is not set up, and the rest of the service is unaffected.

## The door to Claude

`mcp_proxy.rs` passes anything under `/glyph/api/mcp` to the hosted connector running beside the service. It forwards the method, path, query, headers and body, leaves out hop-by-hop headers, and streams the answer back. A body over 4 MB is refused. If the connector is not running, the answer is a 502 that says so. The proxy exists so the connector's sign-in pages, discovery documents and tokens can live under a prefix the web server already sends here.

## The route nobody calls

`POST /glyph/api/format` took a transcript and answered with annotations (a title, phrases to bold, action items) for the phone to apply. Since 0.6.0 the phone formats with spoken cues and its own rules, and no client calls the route. It still runs, behind its own bearer token, one model call at a time with a hard time budget. The binary will not start at all without that token, 32 characters or longer. `format.rs` lists what taking the route out would touch beyond its own files: `health` reports its model, `main.rs`'s CORS tests and the test fixtures lean on it, and the deploy checks both `health` and the route's 401.

## One SQLite file

`store.rs` owns the schema and the one connection. The queries for each table live in `store/accounts.rs`, `store/notes.rs`, `store/prefs.rs`, `store/shares.rs` and `store/recordings.rs`.

The file is `glyph-accounts.sqlite3`, in WAL mode with foreign keys on. It holds the tables `meta`, `accounts`, `device_keys`, `recovery_codes`, `notes`, `prefs`, `shares` and `recordings`. Recordings and pictures are files beside it, at `recordings/<account id>/<id>.bin`, each renamed into place only once its row is ready.

The schema only grows by tables. It is `CREATE TABLE IF NOT EXISTS` and nothing else, so adding the first new column to an existing table needs an ALTER path first.

## The wire's shapes

`wire.rs` holds three things that every route uses:

- `error`, whose body is always `{ "error": message }`. The app shows these words, or matches on them.
- `base64url`, the one check every id, blob and nonce passes before it goes near a path or a query. It allows letters, digits, `-` and `_`, in a length range each route chooses.
- `now_secs`, the clock.

Each route keeps its own limits beside it.

## CORS

The allowed origins are:

- the apps' own webviews: `http://tauri.localhost`, `https://tauri.localhost` and `tauri://localhost`
- `https://ghostmarkdown.com`, for the reader page
- a dev server on the same machine, at any port

The web app at attack.fm/glyph is same-origin and needs no entry. The layer wraps every route, so a preflight is answered before method routing sees it. Errors carry CORS headers too, which lets the phone read a 401 rather than see a network failure. `x-glyph-rev` is exposed, so a page can read a file's revision.

## Deleting an account

`DELETE /glyph/api/v1/account` takes the password's login half. It counts against the sign-in limit, since it is one more way to try a password. A wrong password gets 403 rather than 401, because the session itself is fine.

`store/accounts.rs` deletes the account row, and the cascades take its devices, recovery codes, notes, settings, shares and file rows. Its recordings folder is removed too.

On the device, `deleteAccountHere` in `core/sync/engine.ts` signs out and forgets the sync bookkeeping and the list of shares. The notes on the device stay.

## How it ships

`scripts/deploy-server.mjs` (`npm run deploy:server`):

1. Runs `cargo test`.
2. Builds the server binary and the hosted connector's bundle.
3. Ships both and restarts `glyph-api`. The connector is restarted only when its file or unit changed, because a restart signs every connected person out. If the new binary does not answer its health check, the old one goes straight back in.
4. Checks from outside:
   - `health` answers, and its model is reachable.
   - A format request without the token gets a 401.
   - Notion's `start` hands off to Notion, when Notion is configured.
   - The connector answers its health check, serves its discovery document, and gives a 401 without a token.

`--mcp-only` ships the connector alone and leaves glyph-api untouched. The two service units are `server/glyph-api.service` and `server/glyph-mcp.service`.

## Its tests

Run `cargo test` in `server/`.

- `test_support.rs` holds the shared fixtures once: a temporary folder that cleans up after itself, the values a device sends at sign-up, and the service wired as `main.rs` wires it, with nothing real behind the model.
- `sync_tests.rs` drives sync through the router: a race told who won, paging, limits to the character, a request with no token refused before its body is read, and deleting an account.
- `shares_tests.rs` covers owners and readers, the 500-share and 6,000,000-character limits, and the read limit.
- `accounts/tests.rs` tries every way in.
- `live_tests.rs` uses a real WebSocket client, since the in-memory router cannot upgrade a connection.

Most modules also carry unit tests beside their code.

## Read next

- [[The Claude connector, inside]]
- [[Over the air, and releases]]
- [[Sync and the end-to-end keys]]
