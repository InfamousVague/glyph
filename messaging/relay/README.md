# Ghost Messaging's relay

Passes sealed frames between a phone and the computer it is paired with when they are on different networks
(Matt, 2026-11-13: "I'd like to support both a relay server and local networking"; [../docs/desktop.md](../docs/desktop.md)).
Dart's own library and nothing else. It is on our server since 2026-11-14 (Matt: "Deploy the relay"), behind
ghost-sms.com: `wss://ghost-sms.com/relay` and `wss://ghost-sms.com/hub`.

```sh
dart pub get                                   # the test package only; nothing the relay itself runs
dart run bin/relay.dart --port 8787 --verbose  # ws://127.0.0.1:8787
dart test                                      # the relay and its SHA-256
dart compile exe bin/relay.dart -o ghost-relay # one file to run on a server
```

Use the `dart` that comes with Flutter (`$(dirname $(which flutter))/dart`) where another is first on the path.

**Running your own** (GMFB-25): [../docs/SELF_HOSTING.md](../docs/SELF_HOSTING.md). A Dockerfile here, and in
`deploy/` a Compose file with Caddy, a systemd unit, Caddy and nginx configs, a coturn config, and `relay.env.example`
listing every variable the relay reads (none is required). A relay is an island unless its keeper switches on talking
to other relays (`GHOST_FED`, "Other relays" below): then two people whose apps use different relays can be friends.

## The hub

The same program also serves **the hub** at any address ending `/hub`: where two people's apps find each other
through this server (Matt, 2026-11-14: "for right now we can use our servers to negotiate calls through the app").
It is `lib/hub.dart`, with its own signature checking in `lib/p256.dart`, and is described with the rest of the
app's routes in [../docs/network.md](../docs/network.md). Behind a web server it needs one more line beside the
relay's: in Caddy, `handle /hub { reverse_proxy 127.0.0.1:8787 }`. What it holds for people who are away is in
memory: at most 96 MB of packets, and 20,000 connections. On disk it keeps only the relay's own key and the home
records people gave it (`relay-key.json`, `homes.json`: "Other relays", below).

## Other relays

Relays that pass sealed packets to each other, so two people whose apps use different relays can be friends and talk
(Matt, 2026-11-22: "I'd like the relays to be able to talk to each other"). It is `lib/federation.dart`, with the home
record in `lib/home_record.dart` and the rules for dialling out in `lib/fed_dial.dart`; the plan it follows is
[../docs/OPEN_NETWORK.md](../docs/OPEN_NETWORK.md), section 4. **Off unless `GHOST_FED` is set**: off, the relay dials
nobody, takes no link and passes nothing on, and an app is answered exactly as before.

**A key of its own.** `relay-key.json` in the data folder, made on first start and readable by the relay's own user
alone (mode 600): `{"v":1,"id","key","scalar"}`. The relay's name is the first 16 bytes of the SHA-256 of its public
key, in hex, as an install's is; it prints it as it starts ("this one is …"). Keep the file: a relay that loses it has a
new name, and other relays' lists that name it no longer do. One that can't be read is put aside as
`relay-key.json.broken-<ms>`, never written over. The hub's hello to anything that connects says who the relay is:

    {"hello": <64 hex>, "peek": true, "react": true,
     "relay": {"id", "key", "url": its hub's address (with GHOST_PUBLIC_HUB), "via": (with GHOST_FED_VIA), "fed": true (with GHOST_FED on)}}

**Home records.** Where an account lives, signed by the account, and the only thing a relay believes about it:

    {"v":1, "a": account name, "k": public key (33 bytes, base64), "h": [1 to 3 addresses], "n": count, "t": made (ms), "s": signature}

signed over `"ghost-home v1\n"`, then the name (16 bytes), the count (4 bytes, big end first), the time (8 bytes), how
many addresses (1 byte), and each address as its length (1 byte) and its bytes. A record is kept only where the name is
the key's, the signature is that key's, each address is at most 200 printable characters, and its time is no more than
five minutes ahead; of two for one account the higher count is held. An address is a hub's (`wss://host/hub`) or a
relay hosted from an app's (`ghost-relay://<relay name>?n=<node id>&via=<the public relay it stays linked to>`). The
app makes and checks the same bytes, and both are held to `../test/home_record_vectors.json`.

What an app says of them over its hub connection:

| An app says | The relay answers |
|---|---|
| `{"dir":"home","rec": record}`: its own, or a friend's so the relay can route to them | `{"dir":"home","a","ok":true,"n": the count held}`; or `"ok":false` with `"err":"bad"` (not a record) or `"busy"` (too many checks just now: give it again) |
| `{"dir":"home?","a": name}` | `{"dir":"home?","a","rec": record}` or `{"dir":"home?","a","none":true}` |
| `{"dir":"whois","name":"maya","at":"relay.example"}` | `{"dir":"whois","name","at","id","key","home": her record where that relay holds one}`; or `"none":true`, with `"why"` where it is not that nobody has the name: `off` (this relay doesn't talk to that one), `refused` (that one won't), `down`, `busy`. An `at` that is this relay itself is an ordinary lookup, answered with `"at"` and `"here":true` |
| `[1][number][to][packet]` to someone who lives elsewhere | `{"ack": number,"here": bool,"fed":true}` (what their relay said, or `false` where it waits here), or `{"nak": number,"err"}`: `full`, `far` (their relay is one this relay can't or won't pass to), `refused` |

Records of people who gave theirs here themselves are kept in `homes.json` (the newest 50,000 given); others' (a
friend's, one another relay gave) are the 20,000 used most lately, in memory. An install may have 600 records checked
an hour and a linked relay may give 240 a minute, the relay checks 20 a second for everyone, and asking after someone
else's (`home?`) counts as a lookup, held to the 120 an hour an install has for usernames.

**A link** is one relay dialling another's hub address and saying, in place of an app's hello:

    {"fed":1, "id", "key", "sig", "url": its own hub address (where it claims one), "c": <64 hex> it made up, "stay": true (to stay linked)}
      sig over "ghost-fed-dial v1 " | the hub's number (32) | its own name (16) | the answering relay's name (16) | c (32) | url
    {"ok":true, "fed":1, "id", "key", "sig"}
      sig over "ghost-fed v1 " | c (32) | the dialler's name (16) | its own name (16)
    {"ok":false, "err"}: fed off, busy, bad hello, self, bad address, blocked, not listed, address; then closed (4403)

Each proves it holds its key, over a number the other made up and over both names, so what is signed for one link is no
use on another. A relay that claims a `url` is believed only once this relay has dialled that address itself and seen
the same key in the hub's hello there (remembered for a day; looked at again after five minutes where another key was
seen). A link is opened when first needed, kept while used, closed after ten minutes idle, and a relay that can't be
reached is tried again after 5 seconds, then twice as long each time, ten minutes at most; one that answered no is not
asked again for ten minutes. At most 64 links, and 30 hellos a minute.

**What crosses a link:**

    [5][number: 4][to: 16][from: 16][packet]             -> {"ack": number, "here": bool} or {"nak": number, "err"}
    [6][number: 4][to: 16][from: 16][relay: 16][packet]  the same, for someone on a relay that stays linked to this one
    {"fed":"home", "rec": record}                        a record given: whom the sender speaks for, or where someone lives
    {"fed":"whois", "q": n, "name"}                      -> {"fed":"whois", "q": n, "id", "key", "home"} or {"fed":"whois", "q": n, "none": true}
    {"ping": n}                                          -> {"pong": n}

- **Passing on.** A packet from someone signed in here, for someone not connected here whose record names another relay
  (and not this one), goes to that relay as a `[5]`, after the sender's own record. That relay hands it to their
  connected devices or keeps it in their mailbox exactly as it would its own, under the same limits, stamped with the
  `from` it was given.
- **A relay speaks only for its own people.** A `[5]` whose `from` has no record naming the sending relay (its
  address, which this relay has seen its key at) is refused: `nak` `home`. The sender gives the record and sends once
  more; with none to give, the packet waits for its sender's own (their app gives it as it signs in).
- **One hop.** What another relay passed here is never passed to a third. For someone not here whose record names
  another relay, this relay says that record and answers `nak` `moved`, and the sender routes it there itself, once.
- **`via`.** A relay with no address of its own (`GHOST_FED_VIA`, as one hosted from an app has) dials a public relay
  and stays linked, and sends everything not for its own people through that link. Its people's records say
  `ghost-relay://<its name>?…&via=<that relay>`: they are reached over the standing link, and another relay reaches them
  by sending the public one a `[6]` naming the hosted one, which is passed only to that relay, linked now or kept for
  it, and only for someone whose own record says so (`nak` `to` otherwise). The public relay passes on what the hosted
  one's people send, to the relay their friend lives on and no further: two links at most. The hosted relay believes
  the relay it stays linked to as an app believes its relay.
- **Unreachable.** With the other relay down the packet waits here and the sender is told it is kept: 2,000 packets or
  16 MB for one relay, seven days, 64 MB for all relays together (a quarter of it at most for what other relays asked
  to be kept), 256 relays waited on. A sender hears within four seconds either way.
- **Other `nak`s:** `limit` (over what this relay takes from that one: the sender keeps it and sends again in 15
  seconds), `full` (their mailbox, or what is kept, is full), `big`, `far` (it would take a third link).

**Dialling out.** The addresses dialled come from other people (a record, a name typed after an `@`, the address a
relay claims), so each is held to this before anything is dialled: `wss://` only, port 443, a path ending `/hub`, no
user, query or fragment; the name is looked up here and **every** answer must be a public address (not loopback,
private, link-local, unique-local, carrier NAT, a documentation or reserved range, nor an IPv4 one of those written as
IPv6); the connection is then made to the address that was checked, never looked up a second time, with TLS still
checking the name; no redirect is followed elsewhere; ten seconds to connect, 30 dials a minute.

| Variable | Default | What |
|---|---|---|
| `GHOST_FED` | `off` | `off`: an island. `open`: links with any relay that proves its key, but those blocked. `list`: only those in `GHOST_FED_ALLOW` |
| `GHOST_PUBLIC_HUB` | none | This relay's own hub address as the world reaches it (`wss://relay.example.com/hub`). Without it the relay claims none: it can ask other relays who someone is, but can't pass its people's packets to them |
| `GHOST_FED_ALLOW` | none | With `list`: hosts (`relay.example.org`, or with a port) or relays' names (32 hex), commas between |
| `GHOST_FED_BLOCK` | none | Never linked with, whatever the mode: hosts or relays' names |
| `GHOST_FED_PACKETS_A_MINUTE` | 1200 | Packets one linked relay may pass here in a minute |
| `GHOST_FED_BYTES_A_DAY` | 536870912 | Bytes one linked relay may pass here in a day |
| `GHOST_FED_LOOKUPS_AN_HOUR` | 600 | Usernames one linked relay may ask after in an hour |
| `GHOST_FED_PORTS` | none | Ports dialled besides 443, commas between |
| `GHOST_FED_PLAIN` | `0` | `1` lets `ws://` (no TLS) be dialled: only between machines you run yourself |
| `GHOST_FED_VIA` | none | For a relay with no address of its own: the public relay it dials and stays linked to |

What it adds to what a relay can see: which of its people talk to people on which other relay, and when. Never what.
What waits for another relay, the links, and others' records are in memory: a restart loses them, as it loses what the
hub held, and each app says where its friends live again as it signs in.

**Not built:** rooms across relays (circles, spaces, calls stay on the relay they were made on), who is here across
relays, and an account signing in on another relay than the one it was made on.

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
