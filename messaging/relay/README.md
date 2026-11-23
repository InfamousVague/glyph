# Ghost Messaging's relay

Passes sealed frames between a phone and the computer it is paired with when they are on different networks
(Matt, 2026-11-13: "I'd like to support both a relay server and local networking"; [../docs/desktop.md](../docs/desktop.md)).
Dart's own library and nothing else. It is on our server since 2026-11-14 (Matt: "Deploy the relay"), behind
ghost-sms.com: `wss://ghost-sms.com/relay` and `wss://ghost-sms.com/hub`.

```sh
dart pub get                                   # the test package only; nothing the relay itself runs
dart run bin/relay.dart --port 8787 --verbose  # ws://127.0.0.1:8787
dart run bin/relay.dart --web ../build/web     # and the app in a browser at http://127.0.0.1:8787/app/
dart test                                      # the relay and its SHA-256
dart compile exe bin/relay.dart -o ghost-relay # one file to run on a server
```

Use the `dart` that comes with Flutter (`$(dirname $(which flutter))/dart`) where another is first on the path.

**Running your own** (GMFB-25): [../docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md). A Dockerfile here, and in
`deploy/` a Compose file with Caddy, a systemd unit, Caddy and nginx configs, a coturn config, and `relay.env.example`
listing every variable the relay reads (none is required). Relays don't talk to each other: people reach each other
through a relay only when both use the same one.

## The app in a browser (`/app/`)

`--web <folder>` (or `GHOST_WEB_DIR`) names a folder holding the app built for a browser (`node tool/build-web.mjs`
in the app's folder writes `build/web`), and the relay serves it as plain files under `/app/` (`lib/web_app.dart`).
A build that names no hub (the plain `node tool/build-web.mjs`) dials `/hub` where its page came from, so the page and
the hub are one address. Only GET and HEAD; only what is in the folder (no `..`, no names starting with a dot, no
links leading out of it); no lists of a folder; each file said to be what it is (`application/wasm`,
`text/javascript`, ...); `index.html` and every file whose name doesn't say what is in it asked for again each time
(`no-cache`, with a tag), a file with a hash of its contents in its name kept for a year; and `name.br` or `name.gz`
sent in a file's place where it lies beside it and the browser reads that packing. Every answer says what the app may
do (the app's `tool/web/headers.json`): the page's own policy as a `Content-Security-Policy` header, with
`frame-ancestors 'none'` (so the Argon2id worker, which the page's `<meta>` doesn't reach, is held to it too),
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
`Cross-Origin-Opener-Policy` and `Cross-Origin-Resource-Policy` of `same-origin`, and a `Permissions-Policy` that
asks for no camera, microphone, location or screen. HSTS is for the web server in front of the relay to say. Behind a
web server, pass `/app/` on to the relay beside `/hub`. Without the option there is no `/app/`.

Serve it from its own address if you can (as gogho.st does: app.gogho.st, the app's `tool/deploy-site.mjs`): a page
at the same address as anything else there (a site with scripts written into it, the relay's `/link` pages) shares the
app's store in the browser, and a script slipped into one of those could read what the app keeps. A page there
sends the relay two things across addresses, a report (`POST /market/abuse`) and feedback (`POST /feedback`):
`GHOST_APP_ORIGIN` names that address (`https://app.gogho.st` for gogho.st), and the relay answers those two, and
nothing else, so the page may read them (CORS: `Access-Control-Allow-Origin` that address, a `POST` with the app's
signature headers). Without it, the page at its own address can send neither.

## The hub

The same program also serves **the hub** at any address ending `/hub`: where two people's apps find each other
through this server (Matt, 2026-11-14: "for right now we can use our servers to negotiate calls through the app").
It is `lib/hub.dart`, with its own signature checking in `lib/p256.dart`, and is described with the rest of the
app's routes in [../docs/network.md](../docs/network.md). Behind a web server it needs one more line beside the
relay's: in Caddy, `handle /hub { reverse_proxy 127.0.0.1:8787 }`. It keeps nothing on disk: at most 96 MB of
packets for people who are away, in memory, and 20,000 connections.

**Link helpers** (`GHOST_LINK_HELPERS`, optional). The apps also make direct links between a person's own devices
and their friends' ([../docs/OPEN_NETWORK.md](../docs/OPEN_NETWORK.md), section 2). A link helper is a server that
helps two devices find each other across networks and carries their sealed traffic where no straight path can be
made (an `iroh-relay`; it is not this program). Set the variable to where yours are, as https addresses with commas
between (4 at most, 200 characters each at most), and the hub hands them to each app as it signs in: `"helpers"` in
its `{"ok": true, …}`. With none it says nothing of them, and devices link only where they are on one network. Like
every variable, it is listed in `deploy/relay.env.example`.

## What an end says to it

1. It opens a WebSocket at any address ending in the channel: `ws://host/relay/<32 hex digits>`.
2. Its first message, as text: `{"auth":"<64 hex digits>","role":"phone"|"desk"}`, with `"temp":true` for a channel
   made for pairing. The relay answers `{"ok":true,"peer":true|false}`, or `{"ok":false,"err":…}` and closes.
3. Binary messages go to the other end as they are. With the other end away the sender gets `{"dropped":true}`.
4. The relay says `{"peer":true}` and `{"peer":false}` as the other end comes and goes.
5. `{"delete":true}` removes the channel (unpairing). `{"ping":n}` is answered `{"pong":n}`.

## What it keeps, and what it can see

`relay-data/channels.json` holds, for each pairing, the channel, the SHA-256 of its token and the day it was last
used. No frame is written or held; no address is logged. It can see that two addresses share a channel, when, and
how much they send. A pairing's channel is removed by unpairing or after ninety days unused; a pairing-time channel
lives ten minutes and is never written.

## On our server

    node tool/deploy-relay.mjs --keep-connection && node tool/deploy-site.mjs --caddy   # the first time: one login
    node tool/deploy-relay.mjs                                                          # after that, when relay/ changes
    flutter test tool/net/live_hub_test.dart --dart-define=HUB=wss://ghost-sms.com/hub  # two made-up installs through it

`tool/deploy-relay.mjs` builds the relay for the box from the Mac (`dart compile exe --target-os linux
--target-arch x64`), and in one ssh session checks it arrived whole and runs there, that its port is its own or
nobody's, then installs it: a user of its own with no shell (`ghost-relay`), the program in `/opt/ghost-relay`,
what it keeps in `/var/lib/ghost-relay`, and a systemd service (`ghost-relay`) that restarts it, may write nowhere
else, and may use 300 MB and one processor. It listens on `127.0.0.1:18787`: 8787 is another site's on that box,
which the first deploy found and stopped at before changing anything. `tool/deploy-site.mjs --caddy` writes
`@relay path /hub /relay/*` and `reverse_proxy 127.0.0.1:18787` into ghost-sms.com's own block of the shared
Caddyfile, with that script's backup and its asking of every other site before and after.

Done 2026-11-14 04:35 UTC, in one login: the service up, every other site on the box answering as before, and
from outside `https://ghost-sms.com/relay/` and `/hub` answering "Ghost Messaging relay". The live check signed in
in 380 ms, had a packet held for someone away and handed over, one passed and answered in 164 ms, and a room
joined by two and left. A restart of the service drops whoever is connected (the apps connect again by
themselves) and loses what the hub held.

### The Marketplace (`/market`)

Plugins from other developers and their review (Matt, 2026-11-20: "I would like users to be able to develop and
submit their own plugins to our plugin marketplace and I'd like to be able to verify them for the store through a
review process"): `lib/market.dart`, with the checks of a pack it shares with the app in `lib/market_pack.dart` and
what it keeps in `lib/market_store.dart`. Plain HTTP under `/market`, which `tool/deploy-site.mjs --caddy` passes on
with Files' and feedback's routes. [../docs/marketplace.md](../docs/marketplace.md) is the maintainers' note.

**What it keeps**, in `<data>/market` (`/var/lib/ghost-relay/market` on the box): `state.json` (plugins, submissions,
developers, reports, withdrawals and retired keys), saved after each change, with `state.json.bak` the copy before
it; `packages/<sha256>` and `shots/<sha256>`, each package's canonical bytes and each screenshot, named by the SHA-256
the relay worked out itself; and `audit.jsonl`, a line for each thing done (when, by whom, what, which plugin and
submission). Where neither state file can be read, both are put aside as `*.broken-<ms>` and it starts empty, still
knowing from the audit which developer sent which plugin id. Nothing it holds is secret beyond what the admin session
already guards: a package and its screenshots are public once listed, and until then only their developer and review
are shown them. Nothing records which address read what, nor who sent a report (only the username they chose to send
with it; the audit's line for it says `reporter`). Stopping lets route 8's queue finish first (10 seconds at most), and
answers anything new busy; whatever still finishes after the last save is written as it finishes.

**Who may do what.** Anyone reads what is listed. Everything else is signed with the asker's hub key: `x-ghost-key`
(base64 of the 33-byte key), `x-ghost-time` (ms) and `x-ghost-sig` (base64 of the 64-byte signature, r then s) over

    ghost-market v1\n<METHOD>\n<path as asked, never with a query>\n<time>\n<the body's SHA-256 in hex>

and a request with a body says that hash and its length up front, in `x-ghost-body-sha256` and `x-ghost-body-length`,
so all of it is checked before a byte of the body is read, cheapest first, and a request refused is refused unread. A
developer submits only under a username their key holds, a week after it was claimed. Review is whoever signed in to
the admin page over the hub (Settings › Admin, the @matt account and the admin password) in the last 8 hours, and in
the last 30 minutes to approve, list, withdraw or block: no password travels over HTTP, and a restart signs everyone
out. An approval is the reviewer's own signature over `ghost-market approve v1`, the plugin's id, its version and its
package's SHA-256, which every app checks with the review keys it ships with, at install and at every load: this server
can withhold a plugin, never make one reviewed.

| # | Route | Who | What |
|---|---|---|---|
| 1 | `GET /market` | anyone | what it takes: the format, the limits, the vocabularies, whether it is open |
| 2 | `GET /market/catalog` | anyone | the listed plugins: id, version, SHA-256, size, approval; `ETag`, 304 |
| 3 | `GET /market/revoked` | anyone | the withdrawals and the retired keys; `ETag`, 304 |
| 4 | `GET /market/packages/<sha256>` | anyone | an approved package (410 once withdrawn) |
| 6 | `GET /market/shots/<sha256>` | anyone | a listed plugin's screenshot |
| 7 | `POST /market/report` | signed | a report of a plugin |
| 8 | `POST /market/submissions` | a developer | a submission, or a check of a package before the form is filled in |
| 9 | `GET /market/mine` | signed | one's own submissions and plugins |
| 10 to 12 | `GET /market/submissions/<sid>`, `…/package`, `…/shots/<n>` | its developer, or review | |
| 13 | `DELETE /market/submissions/<sid>` | its developer | withdraw it |
| 14 | `GET /market/review` | review | the queue |
| 15 | `GET /market/review/<sid>` | review | one, with the version before it and what review asked last time |
| 16 | `POST /market/review/<sid>` | review (30 minutes to approve) | start, approve, ask for changes, reject |
| 17 | `POST /market/plugins/<id>/listing` | review (30 minutes), or its developer | list or unlist |
| 18 | `POST /market/plugins/<id>/revoke` | review (30 minutes) | withdraw an approved version |
| 19, 20 | `GET /market/reports`, `POST /market/reports/<rid>` | review | the reports, and marking one done |
| 21 | `POST /market/developers/<id>/block` | review (30 minutes) | block or unblock a developer, unlisting their plugins with it |
| 22 | `POST /market/retire` | anyone | a review key's own retirement, for a key that has signed something here |
| 23 | `POST /market/abuse` | signed | a report of a person or a message (GMFB-40), `{sealed}`: sealed in the app to the review keys, unreadable here; 5 an hour and 15 a day a key, 20 a day an address, 15 a day a number or account, `REPORTS_A_DAY` for those with neither; the newest 150 kept, who sent them never |
| 24, 25 | `GET /market/abuse`, `POST /market/abuse/<rid>` | review | the sealed reports of people, opened on the reviewer's device, and marking one done |

Answers are JSON, `{"ok": true, …}` or `{"ok": false, "error": "<code>", "message": "<plain words>"}`; packages are
`application/octet-stream` and screenshots `image/png`, and nothing uploaded is ever served as anything a browser
would run (`nosniff`, a sandboxing CSP).

**Limits**, each with a default (`GHOST_MARKET_*` in the env file, which tool/deploy-relay.mjs's KNOWN lists): `ON` (0
closes it), `MAX_PACKAGE`, `MAX_SHOT`, `MAX_SHOTS`, `MAX_BODY` (held to Caddy's 10 MiB), `TOTAL`,
`BYTES_PER_DEVELOPER`, `SUBMISSIONS_A_DAY`, `SUBMISSIONS_PER_ADDRESS`, `OPEN_PER_DEVELOPER`, `OPEN_PER_ADDRESS`,
`OPEN_TOTAL`, `OPEN_UNVERIFIED`, `NAME_AGE_DAYS`, `PLUGINS_PER_DEVELOPER`, `MAX_PLUGINS`, `SIGNED_AN_HOUR`,
`SIGNED_PER_ADDRESS`, `VERIFY_A_SECOND`, `BODIES_IN_FLIGHT`, `READS_PER_MINUTE`, `REPORTS_A_DAY`, `NEED_VERIFIED` (1
takes plugins only from developers with a verified number, as it should be once it opens) and `REVIEW_KEYS` (the keys
whose approvals and withdrawals it takes; empty, the signed-in admin's own). Its rate counters are in memory and go
with a restart. A body over 64 KiB holds one of `BODIES_IN_FLIGHT` slots while it is read and until its route is done
with it (a submission waits its turn at route 8 with its body in memory): one at a time from one address and from one
key, and it must bring 64 KiB (or the rest of it) every 10 seconds, so a body trickled a byte at a time can't keep a
slot. A signing header sent twice is a 400. A package's check keeps its first hundred problems and says how many more,
so a stranger's package of thousands costs an answer of a few KB. The withdrawals list is never longer than an app
reads (8 MiB as served, 25,000 withdrawals, 100 retired keys, the app's `MarketReads`): one more is refused,
`withdrawals_full`, where review sees it. A path whose escapes aren't UTF-8 is a 400 before anything is routed, and
an error no module caught is a line on stderr, never the end of the relay.

**The sweep**, daily, the first an hour after a start: a rejected, withdrawn or replaced submission closed over 30 days
ago loses its package and screenshots, unless an approved version or another kept submission uses them (its record and
notes stay); a plugin id with nothing approved is let go 30 days after its last submission closed, or after it was
made where it never got one (the relay stopped between a submission's writes and its record); and any package or
screenshot nothing names is deleted.

    flutter test tool/net/live_market_test.dart --dart-define=MARKET=https://gogho.st/market   # after a deploy, by hand

The live check reads what anyone may, asks as a throwaway key for its own submissions, and submits and retires
nothing. Shipping the market is `node tool/deploy-relay.mjs`, and its route `node tool/deploy-site.mjs --caddy`: each
on Matt's word.

Elsewhere: listen on 127.0.0.1 and let the web server that holds the certificate pass the site to it (every path:
`/hub`, `/relay/*`, `/files`, `/word`, `/link`, `/market`), with WebSockets and a 10 MiB body allowed. It needs no
other setup; [../docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md) has the samples.
