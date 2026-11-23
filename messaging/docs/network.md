# Ghost Messaging's network: routes

Matt, 2026-11-14: "implement a full relay system for the app that's replacable and swappable so that for right now
we can use our servers to negotiate calls through the app, video chats andre but in the future id like to be able to
use a P2P decentralized relay. Look up Satellite.im on google for information (look at github) for what this will
look like", "everything should habe the option for encryption", "At its core id also like to be able to send almost
all chat data and negotiate calls when both parties have sms enabled. The goal will be to have multiple sources to
feed data to eachother from wifi locally, p2p, internet, sms, etc".

What Satellite's Warp does that this takes: the parts are interfaces first, and what stands behind an interface can
be changed without the app above knowing (their messaging, identity and calls modules sit on IPFS and libp2p today
and were written so they need not). Here the interface is a **route**.

| Part | Where | What |
| --- | --- | --- |
| A route | `lib/net/carrier.dart` (`Carrier`) | One way of getting bytes to another install: start, stop, "do you reach them", send, what arrived, and what it is like (how long a packet, does it cost money, does it wake a closed app) |
| The switchboard | `lib/net/switchboard.dart` | Chooses a route for each thing sent, falls back, seals, opens, tells copies apart, answers |
| The relay server's hub | `relay/lib/hub.dart`, `lib/net/hub_carrier.dart` | The route through a server: names, held packets, who is here, rooms |
| The direct route | `lib/net/p2p/` (`P2pCarrier`, `P2p`, `DeviceCard`, `P2pNode`) | Straight between a person's own devices and their friends', with no server in between: the way through when the relay can't carry something ([OPEN_NETWORK.md](OPEN_NETWORK.md), section 2) |
| Checking the relay | `lib/net/ledger.dart` (`Ledger`, `LedgerCheck`), `lib/net/name_watch.dart` | What went to each friend and came from them, compared over direct links to find what the relay dropped or kept back; and friends' usernames asked of the relay again ([below](#checking-the-relay)) |
| SMS | `lib/net/sms_carrier.dart`, `android/…/NetSms.kt` | The route through the phone network: data texts |
| The phone's keys | `android/…/Net.kt`, `E2e.kt` | Who this phone is, who it can reach, a signature for a hub |
| The app's hold on it all | `lib/net/net.dart` (`Net`), `lib/ui/network.dart` | Set up as the app opens; Settings › Network |

The **peer-to-peer** route this made room for is built: `p2p`, shown as "Direct" (Matt, 2026-11-22: "p2p delivery
with the relay as a primary source but have p2p as a secondary back up"). [OPEN_NETWORK.md](OPEN_NETWORK.md) is its
plan and its reference: device cards, who a device links with, when its node runs, link helpers. Its rules are all
Dart (`lib/net/p2p/`), tested against a stand-in node (`test/support/fake_p2p.dart`, `test/p2p_test.dart`); the
node itself is the core (`native/p2p/`, Rust on iroh), behind `lib/net/p2p/node.dart`. A build without the core has
no direct route at all (`Net.p2pNode` is null) and Settings › Routes shows none. Devices tell each other their cards
and where they are in envelopes of one more kind, `p2p`, which go by the other routes and never by a text.

**The direct route's limits** (the second review, 2026-11-23). The ones that count (meets, cards looked at, things
said, streams and frames) are kept in memory and start over each time the app starts: enough while each is small
against an hour, and an app started over and over is a cost of its own.

- **Who is a friend** to it is decided by account id from the records that say so, never by an address: friends by
  username in the state `yes` (by their id, where their key makes it) and friends by number whose record says so (by
  the id the key on that record makes, which android `E2e.state` gives Dart). On Android the people the routes reach
  include the members of every group, whose addresses are whatever the group's admin wrote; none of them is a friend
  for it.
- **A stream proves whose it is** with a nonce from each end and then `HMAC(link key, "ghost-p2p link v2\n" | from
  account | from node | to account | to node | the other's nonce | its own)`, the one that dialled first.
- **What is known of a dial** (failed, under way) is kept for each account at each node: a friend who names another
  friend's node as his costs only his own route. Up to two streams not yet proved and two proved are held with a node,
  and one not yet proved never takes the place of one proved.
- **A phone's node** is up only for a reason of its own (a send of its own, a meet it asked for or answered, the relay
  gone with the app in use) and stops two minutes after the last, whatever streams are open. Only a packet from the
  account a stream proved to be counts as something said on it.
- **Meets** are answered at most six times an hour for one friend and twelve for all; a phone with the app put away is
  not brought up for one, and tells where it is only while the app is in use. A computer's node stays up, as before.
- **What one stream may bring**: 100 frames at once and 10 a second after; an account's devices together, 150 and 15.
  At most ten streams a minute are taken from one node. A frame is given at least a second to go, and a stream slow to
  take one is not closed for it.
- **What is said to friends** (cards, asks, meets) goes only while the relay says one of their devices is connected
  (the hub's presence), the rest told when they come; someone who never answers is asked three times and no more.
  Switching "Only through link helpers" tells them at once, and anything newer that says nothing of where a device is
  clears the addresses held for it.
- **Cards**: one for another node that is older than the one held for that device is taken (a device whose clock went
  back), and the account asked at once in case it is a copy from before; a send dials no device of a friend's unheard
  from (card, meet, proved stream) in sixteen days while another of theirs has been, an install from before. Addresses
  that are loopback, unspecified, multicast, broadcast or link-local, in any form, are never taken or dialled.
- **What is kept**: the node key with the account it was made under, in the secret store; the cards held, with the
  app's choices, under a seal (an HMAC keyed from the node key) that spares checking their signatures again at each
  start; where friends' devices are, in the secret store (`p2p_where`), out of any backup. Choices restored from another
  device's backup (they name a node id with no node key here) give the device a name (`hub_device`) of its own.
- A core that fails to load costs the direct route alone; Settings › Routes says why. What the core itself must
  guarantee is written in `lib/net/p2p/node.dart`.

Not built yet: a **local network** route (`lan`: finds the other install on the same Wi-Fi and connects straight to
it). It is one more `Carrier` handed to `Switchboard.add`; `test/net_test.dart` takes the hub out and puts a
stand-in in its place to hold that true.

## Checking the relay

What checks what the relay says ([OPEN_NETWORK.md](OPEN_NETWORK.md), section 3; Matt, 2026-11-22: "p2p as a secondary
back up that validates everything our relay says"). Two parts: the **ledger**, compared over direct links, which
waits for the direct route's core and is built and tested against the stand-in node; and the **name watch**, which
needs no direct route and runs now. Both were reviewed on 2026-11-23 and changed for what the review found (its probes
are tests now).

**The ledger** (`lib/net/ledger.dart`, `Ledger`). The switchboard tells it, through a small interface (`SendLog`),
what each route took and what the route said (passed on, or kept for someone away), what came and by which route,
what was answered, and that something came that could not be opened here (sealed for another device of the account).
For each friend it lists what was **sent** (the envelope's name, when, the route, passed or kept, answered) and what
was **got** (name, when, route), for seven days and at most 500 of each. Only what asks for an answer: never a test
(`ping`), typing, a card (`p2p`) or its own messages (`ldg`), never anyone who is not a friend or the account's own
devices (later), and never a word of any message. Sent again, the relay's word is the one kept: another route's never
takes its place, and the relay's latest does.

Beside the lists: this device's connections to the relay (when each signed in, when anything last came on it, and when
the relay said it had started: `HubCarrier.signedInAt`, `heardAt`, `relayStartedAt`), when each friend was first known
here as one (what they sent before is not compared), what a friend's device said it sent that never came, and what each
relay was found to do. Kept in **files of its own, out of any backup**, in a folder that is the build's own
(`lib/net/kept_files.dart`): Android's no-backup folder as Android gives it (`getNoBackupFilesDir`), the app's Caches
folder in its container on an iPhone, the person's Caches folder under the build's bundle id on a Mac, the local app
data on Windows and the cache folder on Linux, each under the app's name; on a computer, a build other than a release
(a `flutter run`) keeps its own beside the release's (`ledger-debug`). Never the app's choices, which Android's backup
copies. Written twenty seconds after a change and as the app is put away, books before connections, one write after
another (a flush waits for one still writing, and signing out for both). The index names the device it was kept on
all the same. Signing out deletes all of it, a book a flush was writing as it came too.
It exists only where the build has the direct route: without one nothing could compare it, so nothing is listed.

**Comparing** (`LedgerCheck`). When a direct stream to a friend's device is proved, and every fifteen minutes while it
stays open, each device says on that stream alone (`Switchboard.sendOn`; never through the relay, never by a dial) an
envelope of kind `ldg` that asks for no answer:

    {"t":"sum", "w":[from, now], "s":[[name, when, "p"|"k"|"o"], …], "g":[name, …],
     "h":{"u": my relay, "up": whether I'm connected to it, "t": since when, "heard": when it last heard from it}}
    {"t":"dif", "want":[name, …]}

`s` is what was sent to the other account, each with when and what the relay said as it took it (`p` passed, `k`
kept, `o` another route took it); `g` the names of what came from them. OPEN_NETWORK.md's `was` is folded into `s`:
the times are needed anyway, to compare only what both lists cover and to leave out the last two minutes (what may
still be on its way), and with the relay's word beside each nothing waits on a second round. The other device's
clock is taken from `w`'s second time and allowed for; one more than a day off is not compared. `up` is left out while
the person chose Invisible: the relay hides them from friends then, on purpose. Then:

- What they sent that never came here is asked for (`dif`, 64 at most) and sent again straight, on the stream that
  asked, by whoever still holds it: the switchboard's unanswered (`Switchboard.held`, five minutes, never a call that
  has stopped ringing) and Friends' own list (`Friends.heldFor`, given to `LedgerCheck.holders` through
  `Net.addHolder`).
- What came there and was never answered here is taken as answered (`Switchboard.answeredBy`): the answer was lost,
  and Friends stops sending it again.
- Each thing that never came here is put down once, as one of: **nobody's doing** (another route took it, their relay
  is another, it came and could not be opened here, this device was not connected when the relay passed it, or the
  relay kept it and may have handed it to another device of the account); **lost when the relay started again** (it
  kept it, and at the next sign-in said it had started since: the hub's `ok` says its time and its start); **the
  relay said it passed it on, and it never came**, where this device was connected then, which is proved, not assumed
  (the connection signed in ten seconds before and something came on it ten seconds after, and the relay's frames come
  in order on one connection); or **the relay said this device was away**, where it said it kept it while this device
  was connected so. "Kept it and never handed it over" is not put down for now: the relay hands what it kept to
  whichever of the account's devices signs in first, and nothing here can yet prove none did.
- **Only what then comes straight counts.** A friend's device can say anything of what it sent; what it then sends
  straight shows it was so. Only then is a thing counted as having come straight (Settings says so of no other), and
  only then is a wrong put down against the relay, and put down as that device's word ("Maya's device says the relay
  passed on a message to you, and it never came by the relay").
- A friend whose device says, in two sums in a row, that it is connected to the same relay and heard from it in the two
  minutes before, while the relay has told this one (connected and watching them a minute or more) that they are gone,
  is put down as the relay being wrong about who is here; once in six hours for one friend.

**What a friend's device can make this one do:** a `sum` of more than 500 names in either list, a name longer than 32,
or a `dif` of more than 64, is refused whole; one `sum` from a device every ten minutes and twelve from an account in an
hour; six `dif`s and two hundred things sent again for one account in an hour. What it puts down is the ledger's,
capped there (500 missing, 50 wrongs and 64 comparisons for a relay, 300 connections). `LedgerCheck.refused` counts
what was turned away.

**Checking by hand, and by itself.** "Check now" (Settings › Routes) dials the friends the relay says are here, at
most twelve, asking each to meet, once a minute at most. With no direct link in use, a round runs by itself while the
app is in use: up to five friends the relay says are here and not compared in a day, every hour on a computer and every
six on a phone. Both bring a phone's node up as a send does; what is said on a link keeps nothing up.

**The name watch** (`lib/net/name_watch.dart`, `NameWatch`). A friend added by username was found by asking the relay
who has the name. The account asks about each again once a day, at a time of its own through the day (when each friend
was first seen is kept, so a phone that never runs a whole day still comes to each), and ten minutes on where the relay
can't be reached. With several devices it is the days that are shared out, not the friends: of n devices forward
secrecy has heard from this week, each asks about every friend every n days, the days going round the devices in turn
from one of each friend's own, so every device sees what the relay says of every friend, and each asks about an n-th of
them a day. What a device shows of a friend it asks again a day on, whatever its turn, so it goes once nobody holds the
name; a device asks about a friend no sooner than a day after it last did.

**Lookups made of the app's own accord** (`lib/me/lookup_budget.dart`, `LookupBudget`). The relay answers **an account**
120 lookups an hour, counted for all its devices together (they sign in as one: `relay/lib/handles.dart`). The name
watch's lookups and the friend requests' checks (`Buddies`: each request as it comes, and again) are held to one budget
of thirty an hour for the whole account, shared out among its devices, and the rest are the person's: their adds and
Accepts, which always ask, and the add-friend drawer's lookups as a name is typed. The requests' checks leave the watch
a third of a device's share, so strangers' requests can't stop it; the watch's are a minute apart; and once the relay
says too many to either, neither looks anything up for the hour. Accept, refused so, says the relay's hourly limit and
by when one frees up at the latest (an hour after the first lookup the relay was still counting that this device made).
One lookup goes at a time, and two of one name share one question (`Me.whois`).

- **Each relay is its own directory**, and what the watch knows is kept for each apart. Another account under a
  friend's username means something only on a relay that has named their own key under it before (the lookup that
  added them, `Buddies.add` telling the watch, or a daily one); a relay of one's own, or a name the relay never gave
  them, is another directory, where someone else holding the name is nothing to say. There it is shown on that
  friend's card and in Settings › Routes, in the screens' own ink: "@maya now belongs to another account on the relay.
  If Maya changed or gave up their username, that's why. You're still talking to the Maya you added." It goes when the
  relay says nobody holds the name, or names their key again.
- **A friend who changes their username is followed**: the new one they say in their sealed profile is looked up, and
  where the relay names their key for it, asked about from then on in place of the old one, which may be anyone's now.
  (Their record, and so their conversation's address, keeps the name they were added under: moving that is left for a
  decision of its own.)
- The friend is told, sealed, by the relay and over a direct link where one is open (`Switchboard.sendEveryWay`, which
  dials nothing and starts nothing), at most once a day while it lasts, in an envelope of kind `name`:

      {"u": the username, "i": the account name the relay gave it to, "at": ms}

  Their app takes it only from a friend by username, sealed, for its own username and another account, once an hour
  from one friend, keeps it a week, and says it at once only where it is new that week.
- **Its own username** is asked at each sign-in, every ten minutes at most (and as soon as a friend's lookup under way
  ends, never skipped for it), only on a relay where this device has held it: the relay says this key holds it there
  (`{"dir":"name"}`, answered with the name's hash: `Me.heldName`), or it was claimed there. What comes back is said
  calmly, once for each name and account, with what usually causes it: given up or changed on another device (this
  key holds no name, or another, there), a new key ("still held by this device's old key": the keys this device held
  its names under are kept, across identities), or another relay. Only where the relay says this key holds the name
  and gives it to another account when others ask does it contradict itself. It goes when this device's username
  changes or is given up, or nobody holds the name.
- An add-me link (`lib/friends/add_link.dart`) carries the account's whole name, 32 hex digits, after `#`, which no
  browser sends to a server (`site/add` carries it into the app's own `ghostmsg://add/` address). The app refuses a
  `whois` answer whose key doesn't make that name (`Buddies.add`'s `keyPrefix`), and keeps and sends nothing. A link
  from before, with eight, is still taken as it says.
- Nothing changes who a friend is: a friend stays the key that was added, whatever the relay says after. What the watch
  keeps (`name_watch`) is of friends only (a name confirmed as someone was asked to be a friend, thirty days), is kept
  for one identity (signing in to another account drops it, but which keys this device held its names under), and goes
  at sign-out.

**What is live with the direct route switched off** (no core in any build yet): the name watch, the add-me link's key
check, and Settings › Routes saying the relay is checked only by the name watch, with what it found; nothing is dialled
and no ledger is kept. The ledger, the comparing, "Check now" and the rounds come with the core.

`test/ledger_test.dart` (the lists, comparing between installs over a real hub in memory that a test can make drop
what it says, and a stand-in node), `test/name_watch_test.dart`, `test/name_lookups_relay_test.dart` (Me.whois against
a real relay over a socket), `test/kept_files_test.dart`, `test/relay_check_settings_test.dart`, and parts of
`test/add_me_test.dart`, `test/p2p_net_test.dart`, `test/profile_open_test.dart` and `relay/test/hub_socket_test.dart`.

## Who is who

An install is a P-256 key pair. On a phone it is the pair its encryption already has (`E2e.kt`, private half under
the Android Keystore), so **the people the routes reach are the people encryption is on with**, and exchanging keys
by text is what introduces two phones. An install's **name** is the first 16 bytes of the SHA-256 of its public key,
in hex: a hub and a stranger learn no number from it.

Two installs seal with a key made from their conversation key and used for nothing else
(`HMAC(conversation key, "ghost-net pair" 01)`): AES-256-GCM, a random nonce, "ghost-net-v1" bound in. Kotlin makes
it on the phone and hands it to Dart; `lib/net/crypto.dart` makes the same in Dart for a computer and the tests
(`NetCryptoTest.kt` and `test/net_test.dart` hold both to the same bytes from the same two key pairs).

## What crosses

An **envelope** (`lib/net/packet.dart`): a name of 16 hex digits made by the sender, a kind (`text`, `read`,
`typing`, `call`, `room`, `hello`, `ping`, `ack`), when, a body, and whether an answer is wanted. JSON, so a newer
build can say more and an older one passes over what it does not know.

A **packet** is an envelope as a route carries it:

    [version and flags][from: 16 bytes][the envelope, sealed or not]
    [version and flags | part][from][which packet: 4 bytes][part number][how many][a piece of the above's last field]

A call's ring, sealed, is 123 bytes: one data text. Longer ones cross a short route in pieces.

## How the switchboard chooses

- The routes are tried in order: `hub`, `p2p`, `lan`, `sms` where the person has not said otherwise. The relay
  comes first: it is the fast path, and the one that keeps things for someone who is away. (Until 2026-11-22 the
  order was `lan`, `p2p`, `hub`, `sms`, with only `hub` and `sms` built; no install keeps an order of its own.)
- One is passed over when it is switched off, not up, does not reach that person, cannot hold the packet even in
  pieces, or costs money and this is not something allowed to (`metered`: only a ring, a greeting, a test).
- On a route where an answer comes at once the answer is waited for (4 s); with none the next is tried. The other
  end knows the second copy by the envelope's name and passes it on once, answering both.
- Kept by a hub for someone who is away is good enough, unless it is urgent (a call ringing): then the routes after
  are tried too, so the one that wakes a closed app gets its turn.
- Once a route has only kept it, a route that holds links of its own (`LiveLinks`: the direct route) is given it
  only where a link to one of their devices is open right now, by that link alone. Nothing is dialled and nothing
  started for someone who is away; where it was not urgent that copy is not waited for.
- The same where a route passed it on and no answer came in time (their app is slow, not away: nothing is started or
  dialled for that), and for something urgent while a route that wakes a closed app comes after the direct one (that
  one goes at once, not after a dial). With the relay down and no such route after it, the direct route dials as any
  route would.
- An answer (`ack`, `fsk`) goes back by the route the thing it answers came by, and on the direct route on the very
  stream it came on (`Arrived.line`, `LiveLinks.sendOn`), else by another stream open to them: never to every device
  of the sender, never by a dial.
- What a route of live links brings waits its turn with the rest, one at a time and in order, but no more than 128 of
  its arrivals wait at once; the rest are dropped and counted (`Switchboard.droppedArrivals`), so a flood from someone's
  device never holds the relay's arrivals up for long.
- Sealed unless the sender says not to. Nothing unsealed is taken from someone a key is held for; from a name no
  key is held for, only a `hello` in the clear is shown to the app.
- An answer never goes back by a route that costs money.

## The hub

`relay/` serves it at any address ending `/hub`, beside the pairings' relay (`/relay/<channel>`): on our server
that is `wss://ghost-sms.com/hub`, live since 2026-11-14 (`relay/README.md`, "On our server"). Anyone can run
one; Settings › Network takes its address.

1. The hub says `{"hello": <64 hex digits>}`. The app answers `{"id", "key", "sig"}`: its name, its public key
   (33 bytes, base64) and its signature over `"ghost-hub v1 "` and those 32 bytes (r then s, base64). The hub
   checks the name is that key's and the signature is that key's (`relay/lib/p256.dart`, Dart's BigInt and nothing
   else, held to RFC 6979's example), then `{"ok": true, "held": n, "now": ms, "since": ms}` (its time, and when it
   started: what it kept before then went with a restart; a hub that keeps what it holds on disk, `GHOST_HUB_KEEP_HELD`,
   says the start of the one before it after a clean restart) and whatever was kept. Where the relay was
   given link helpers for the direct route (`GHOST_LINK_HELPERS`), the same answer names them: `"helpers":
   ["https://…"]`, four at most.

   **Bound to the relay (v2, since 2026-11-23).** A v1 signature says nothing of where it was made: a relay the app
   was pointed at, or asked a name of, could hand the app the number of the app's own relay and sign in there as the
   app with the answer (found in the review of relays that talk). A hub that knows the names it is reached at
   (`GHOST_HUB_NAMES`) says `"v2": true` in its hello, and the app answers `{"id", "key", "sig", "v": 2, "host"}`, the
   signature over `"ghost-hub v2 "`, the length of the host (one byte), the host the app dialled (lower case, its port
   only where it is not the scheme's own: `gogho.st`, `relay.example.com:8443`), then the 32 bytes. The hub takes it
   only for a host in its own names, and from a key that has signed in with v2 it takes no v1 again (kept across
   restarts), so a v1 signature an app of this build gives anywhere else is worth nothing at its own relay. A hub that
   says nothing of v2 is signed v1, as ever; Android's background check (`HubPeek.kt`) signs as the app does. A name
   looked up on another relay itself (`lib/net/relay_ask.dart`) signs in there under a key made for that one question,
   with no device's name, and takes nothing it is handed.
2. `[1][a number: 4 bytes][to: 16 bytes][packet]` goes to that name as `[1][from: 16 bytes][packet]`, answered
   `{"ack": number, "here": true}`; or is kept (200 packets or 1 MB a person, seven days, in memory, and on the relay's disk too where its keeper set
   `GHOST_HUB_KEEP_HELD=1`: sealed, with who it is for and from, `relay/README.md`, "What it keeps") and answered
   `"here": false`; or refused, `{"nak": number, "err": "full"}`. For someone who lives on another relay (where this
   one talks to others: `relay/README.md`, "Other relays") the answer carries `"fed": true` and never says whether they
   are connected (`"here": false`, taken), `"waiting": true` where it waits on this relay for theirs, or `nak` with
   `home`, `busy`, `far` or `refused`, which the app says as the reason in the conversation.
3. `{"watch": [names]}` is answered `{"here": [those connected]}`, then `{"came": name}` and `{"went": name}`.
4. Rooms: `{"join": <32 hex>, "token": <64 hex>}`, both made by the members from a key only they hold; the first to
   name a room sets its token. `{"room", "ok", "members"}` to the one joining, `{"room", "came"}` to the rest;
   `[2][room: 16 bytes][packet]` goes to the others as `[2][room][from][packet]`; `{"leave": room}`, or the
   connection dropping, tells them `{"room", "went"}`. A room nobody is in is forgotten. Up to 64 in one.

It sees which names talk to which, when and how much. It holds no account, number or name, logs no address, and
cannot open a packet.

## SMS

A packet goes as a **data text**: an SMS addressed to a port (16962), which Android hands to the app that listens
there and to no other. It is never written to the phone's messages and no texting app shows it, so it works whether
or not Ghost Messaging is the phone's texting app. 133 bytes each, up to six for one packet, each a text on the
person's plan. One that comes with the app closed is kept (sixty, a day) and handed over when it opens.

## Trying it

`test/net_test.dart` (17 tests): the cryptography against fixed keys and against the hub's own arithmetic; a packet
in pieces; the switchboard's choosing with stand-in routes; and two installs through the real hub on this machine
(kept while away and handed over, a name only its key holder can use, a room joined and left).

On two throwaway emulators, 2026-11-14, with the release build:

    dart run relay/bin/relay.dart --port 8788 --verbose        # the hub, on the Mac
    emulator -avd ghostflutter2 -read-only -no-window -port 5590   # and another on 5592

Each app made its key pair as it opened. Each was then given the other's public key by writing a `peer:` entry
into its `shared_prefs/e2e.xml` as root (what turning encryption on does, without the taps), and
`net_hub = ws://10.0.2.2:8788/hub` into `ui.xml`. Both signed in to the hub with keys held by the Android Keystore
(`hub 1fd7b9 came`, `hub 06f920 came`); Settings › Network said "1 person · 2 routes ready"; "Send a test" from one
said "Reached them by Relay server in 12 ms" and the other listed "A test came from 5590 · Relay server". By SMS
only, the first emulator's modem took the data text (98 bytes, `SEND_SMS` answered without error), and a data text
handed to the second through Android's own telephony (`tool/mms/Inject.java`, port 16962) reached the app ("data
text in"). **Not seen:** a data text crossing between two phones. The emulators' modems do not pass them to each
other, and some carriers do not either; that needs two real phones.
