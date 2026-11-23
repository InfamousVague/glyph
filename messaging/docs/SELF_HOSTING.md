# Running your own relay

GMFB-25, "Self-hosting the relay, documented", from the gap review against Uplink. Ghost Messaging's relay is one
small Dart program with no dependencies beyond Dart's own library (`relay/`). Anyone can run it and point their app at
it in **Settings › Routes › Relay server**. This page covers how to run it, what it needs, and, before you start,
what you give up by moving to it.

## Read this first: relays are islands

Relays don't connect to each other. Nothing is passed between your relay and Ghost Messaging's (gogho.st), and the
app talks to one relay at a time for everything that goes through a relay.

| | On your own relay |
|---|---|
| Friends, groups of friends, sealed messages through the relay | Only with people whose app uses **the same relay**. Someone on gogho.st can't reach you there, and you can't reach them, through a relay. |
| Texts (SMS, including encrypted texts and data texts) | Unchanged: they go over the phone network, not through any relay. |
| Your username | Kept on each relay apart. `@maya` on your relay and `@maya` on gogho.st can be two different people, and a username you claimed on gogho.st isn't yours on your relay until you claim it there. |
| Add-me links (`gogho.st/add/<name>`) | The link always says gogho.st, but the app looks the name up on **the relay it uses**. On your relay that may be someone else, or nobody: the app says so before it sends a friend request. |
| Your account (username and password, the sealed backup) | Kept on the relay you made it on. Signing in on a new device works only with that device on the same relay. |
| Circles and spaces | A circle's link works anywhere, but each member's app joins the circle's rooms on its own relay: members on different relays don't see each other's messages or who is in a space. |
| Circle invite words (`gogho.st/c/<word>`) | Kept on each relay apart. A word made on your relay works typed into **Join a circle** by people on your relay; the gogho.st/c/ page only knows gogho.st's words. |
| Files spaces | Kept on your relay's disk, for people on your relay. |
| Held messages, presence (online, away, last seen) | Per relay, in memory. |
| Calls | Set up through your relay. Without a TURN server of your own (below), a call between two devices that can't reach each other directly doesn't connect. |
| The Marketplace (browsing, installing, reporting a plugin or a person) | Always Ghost Messaging's, read from gogho.st whatever relay you use. Submitting a plugin needs a username claimed on gogho.st, so it doesn't work from your relay. |
| Verifying your number, linking Discord, X, Telegram | Off unless you set up your own Twilio Verify service and your own apps with those networks (the env file below). |
| Waking a closed iPhone | Not possible: it needs Apple's push key for the app's bundle id, which only the app's publisher holds. An iPhone gets what was held for it the next time the app is opened. |
| Share feedback | Goes to the relay in use, so to yours, where it isn't filed anywhere unless you set up a Notion board for it. |
| A computer paired to the phone | Messages go through the phone, so through your relay; but the computer's own key for voice spaces still uses gogho.st. |
| App updates, docs, the website | From gogho.st, as before. |

So a relay of your own suits a group that moves together: a family, a team, friends who all set the same address.
Anyone you want to reach through a relay has to use yours.

### Not done yet: reaching people on both

The app could also keep a connection to gogho.st for friends who aren't on your relay. It isn't a small change:
every part of the app that uses the relay (friends, usernames, circles, rooms, invites, accounts, presence) asks
**the** relay, not one per person; the switchboard counts a packet held for someone away as delivered, so it never
learns that the friend was on the other relay; and each friend would need to carry which relay they use, kept in step
when they move. It's recorded here as future work rather than done halfway.

## What it serves

One program on one port (8787 unless told otherwise), plain HTTP and WebSockets:

| Path | What |
|---|---|
| `/hub` (WebSocket) | The hub: apps sign in with their key, find each other, pass sealed packets, hold packets for people away (in memory, 96 MB at most), presence, rooms for circles, spaces and calls, usernames, sealed account backups, invites by number, invite words. |
| `/relay/<channel>` (WebSocket) | A phone and its paired computer when they're on different networks. |
| `/files/...` | Files spaces' sealed files, on disk. |
| `/word/<hash>` | A circle's invite word, for a web page like gogho.st's /c/. |
| `/link/...` | The pages a network sign-in comes back to (only with those networks set up). |
| `/market/...` | A Marketplace. The apps never read yours (above); the sample env file closes it. |
| `/feedback`, `/bounty` | Ghost Messaging's own feedback board and bug bounty; off without their variables. |
| `/app/...` | The app in a browser, as plain files, with `--web` (or `GHOST_WEB_DIR`); `/app/clear-site-data` answers `Clear-Site-Data: "storage"`, which the page asks for as it signs out. None without it. |
| anything else | `Ghost Messaging relay` as plain text: a quick check that it is up. |

It writes only under its data folder (`--data`): pairings, usernames and linked handles, sealed account backups,
Files, invites, invite words, the Marketplace. Back that folder up if you care about any of it. Nothing it holds can
be read without the apps' keys, but which installs talk to which is visible to whoever runs it, as with any server.

## Running it

You need a server with a domain name pointed at it, ports 80 and 443 open, and a few hundred MB of memory. Every file
mentioned is in `relay/deploy/` (and `relay/Dockerfile`).

### The environment: nothing is required

`relay/deploy/relay.env.example` lists every variable the relay reads, grouped by what each switches on. **None is
required**: with no file at all it runs the hub, pairings, Files and invite words with their defaults. The sample sets
three things, and you should keep them:

- `GHOST_PUBLIC_URL`: your relay's https address (its built-in default is not yours).
- `GHOST_ADMIN_NAMES=` empty (its built-in default is someone else's username).
- `GHOST_MARKET_ON=0` (the apps never read your Marketplace).

Optional groups: a TURN server for calls (`GHOST_TURN_*`), link helpers for the apps' direct links between devices
(`GHOST_LINK_HELPERS`: without one they link only on one network), the app in a browser (`GHOST_WEB_DIR`; and
`GHOST_APP_ORIGIN`, the address it is served from where that is one of its own, whose page may then read the answers
to the reports and feedback it sends, and nothing else), Files limits (`GHOST_FILES_*`, lower
`GHOST_FILES_TOTAL` to fit your disk), Twilio Verify for number checks (`GHOST_TWILIO_*`), network sign-ins
(`GHOST_DISCORD_*`, `GHOST_X_*`, `GHOST_TELEGRAM_*`, `GHOST_GITHUB_TOKEN`). The rest (`GHOST_APNS_*`, `GHOST_NOTION_*`, `GHOST_BOUNTY_KEY`) only
Ghost Messaging's own relay can use; leave them empty.

```sh
cp relay/deploy/relay.env.example relay.env   # edit; keep it readable by root (or the relay's user) only
```

### With Docker Compose (relay and Caddy, TLS included)

```sh
cd messaging/relay/deploy
cp relay.env.example relay.env               # and edit
cp Caddyfile.example Caddyfile               # put your domain in place of relay.example.com
docker compose up -d
curl https://relay.example.com/              # Ghost Messaging relay
```

Caddy gets and renews the certificate by itself once your domain's DNS points at the server. The relay isn't
published on any port of its own; only Caddy reaches it. What it keeps is in the `relay-data` volume. Needs Docker
Compose 2.24 or later (for the optional `env_file`).

The image alone, without Compose:

```sh
docker build -t ghost-relay messaging/relay
docker run -d --name ghost-relay --restart unless-stopped -p 127.0.0.1:8787:8787 \
  -v ghost-relay-data:/data --env-file relay.env ghost-relay
```

It runs as an unprivileged user in an image with nothing but the program, the C library and certificates.

### With systemd (no containers)

Build the program (on the server with Dart 3.11 or later installed, or on another machine with
`--target-os linux --target-arch x64`), then follow the steps at the top of `relay/deploy/ghost-relay.service`:

```sh
cd messaging/relay
dart compile exe bin/relay.dart -o ghost-relay
sudo useradd --system --no-create-home --shell /usr/sbin/nologin ghost-relay
sudo install -d -m 755 /opt/ghost-relay && sudo install -m 755 ghost-relay /opt/ghost-relay/ghost-relay
sudo install -d -o ghost-relay -g ghost-relay -m 700 /var/lib/ghost-relay
sudo install -o root -g ghost-relay -m 640 relay.env /etc/ghost-relay.env
sudo cp deploy/ghost-relay.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now ghost-relay
```

It listens on `127.0.0.1:8787` only, writes only to `/var/lib/ghost-relay`, and restarts if it stops. Then put a web
server in front of it for TLS:

- **Caddy**: `relay/deploy/Caddyfile.example`, with `relay:8787` changed to `127.0.0.1:8787`.
- **nginx**: `relay/deploy/nginx.conf.example` (WebSocket upgrade headers, a 10 MB body limit, long read timeouts,
  no buffering), with a certificate from certbot or similar.

Whichever you use, it must pass WebSockets on, let a 10 MiB request body through (Files' pieces are up to 8 MiB),
and not cut an open WebSocket off after a minute.

To update: build again, `sudo install -m 755 ghost-relay /opt/ghost-relay/ghost-relay`, `sudo systemctl restart
ghost-relay`. A restart drops whoever is connected (the apps reconnect by themselves) and loses held packets and
presence, which are only in memory.

### Calls through your own TURN server (optional)

Calls go straight between the two devices where they can. Where they can't (two strict NATs, some mobile networks),
they need a TURN server to relay through. Without one on your relay such calls don't connect.

1. Install coturn (`apt install coturn`, or `docker compose --profile calls up -d` with the compose file).
2. Copy `relay/deploy/turnserver.conf.example` to `/etc/turnserver.conf` (or `deploy/turnserver.conf` for Compose)
   and fill in the secret (`openssl rand -hex 32`), your domain as the realm, and your public address. If clients may
   relay to each other through this same machine, allow its own public address with `allowed-peer-ip`.
3. Open UDP and TCP 3478, and UDP 49160 to 49200.
4. In the relay's env file set `GHOST_TURN_SECRET` to the same secret and `GHOST_TURN_URLS` to
   `turn:relay.example.com:3478?transport=udp,turn:relay.example.com:3478?transport=tcp`, and restart the relay.
   It then hands each call short-lived credentials made with that secret.

### A link helper for direct links (optional)

The apps also make direct links between a person's own devices and their friends' devices (`OPEN_NETWORK.md`, section
2): a second way through beside the relay, and how an app checks what the relay tells it. Two devices on one network
link by themselves. Across networks they need a **link helper**: a server both can reach, which tells each the address
the internet sees it at, passes their first packets, and carries their traffic for as long as no straight path can be
made. It is iroh's relay server, `iroh-relay`. It is not the Ghost Messaging relay, and the two know nothing of each
other.

iroh's makers run public ones, for "development and hobby use only", so the app ships with none: it uses the ones its
relay names, and with none named its devices link only on one network. A link helper sees which device ids link, from
which addresses, and how much they send. It never sees an account's name or what is said: the traffic is sealed
between the two devices.

1. **Build it.** `tool/build-link.sh host` on the server itself (Rust 1.91 or later) gives
   `build/link/host/iroh-relay`. From another machine with zig and cargo-zigbuild, `tool/build-link.sh` gives
   `build/link/iroh-relay` for Linux on x86-64 (glibc 2.31 or later: Ubuntu 20.04, Debian 11, and newer). Either way
   it is `iroh-relay` 1.5.0's source as crates.io holds it, taken by its checksum and built with the lock file its
   authors published. Nothing prebuilt is fetched.
2. **Its settings.** Copy `relay/deploy/link-helper.toml.example` to `/etc/ghost-link/config.toml` and put your
   relay's name in it. Each line says why it is there. As written the helper shares a machine with the web server
   that has ports 80 and 443, so it takes a port of its own and apps reach it at `https://relay.example.com:7843`.
   The server passes over a setting it does not know without a word: copy the names, don't retype them.
3. **A certificate** for that name, as two PEM files where the settings say
   (`/etc/ghost-link/certs/relay.example.com.crt` and `.key`, readable by the helper's user). The web server already
   has one. Caddy keeps it in `/var/lib/caddy/.local/share/caddy/certificates/<issuer>/<name>/` (with the Compose
   file, under `/data/caddy/certificates/` in the `caddy-data` volume); certbot in `/etc/letsencrypt/live/<name>/`
   (`fullchain.pem` and `privkey.pem`). Copy the pair, and copy it again whenever it is renewed, each file by
   renaming a finished copy over the old one: the helper reads the two files again once a day, so nothing needs
   restarting. `node tool/deploy-link.mjs --print` shows the few lines of shell and the daily timer that do it on
   our own server.
4. **The service.** `relay/deploy/ghost-link.service`, with the steps at its top: a user of its own with no shell,
   nothing writable but its own folder, 300 MB and one processor at most.
5. **Ports.** Open TCP 7843 (where apps reach it) and UDP 7842 (where it tells a device its address; keep that
   number, apps look for it there). 7844 and 7845 are for the machine itself and stay closed.
6. **Tell the relay.** In the relay's env file, `GHOST_LINK_HELPERS=https://relay.example.com:7843`, and restart the
   relay. Its hub hands the address to each app as it signs in.

Then check it:

```sh
curl https://relay.example.com:7843/healthz          # {"status":"ok","version":"1.5.0","git_hash":"unknown"}
cd messaging/native/link-check
cargo run -- https://relay.example.com:7843          # two devices sign in, link through it and straight; exits 0
cargo run                                            # the same against one started on this machine (needs `build-link.sh host`)
curl -s http://127.0.0.1:7845/metrics                # on the server: what it has carried, and for how many devices
```

What to know before relying on it:

- **Anyone who knows the address can link through it**, Ghost Messaging or not: the apps' device ids are known to no
  server, so there is no list to hold a caller to. What bounds it is the limit in the settings (one device may send
  256 KiB a second through it, after a first megabyte) and the service's memory and processor. A device that sends
  more than that is slowed, not cut off, and whatever else it is sending through the helper waits behind the load
  while it lasts. The server can ask for a token instead (`access.shared_token`); the apps have no way to be handed
  one yet.
- **A network that lets nothing out but ports 80 and 443** cannot reach a helper on 7843. Devices there link only
  where they can reach each other's addresses as they are; the relay carries everything else, as it always did.
- **A name of its own instead.** Where the helper can have a name whose ports 80 and 443 are its own (another
  address, or a machine with no web server), it can get its own certificate: in the settings,
  `http_bind_addr = "[::]:80"`, and under `[tls]` `https_bind_addr = "[::]:443"`, `cert_mode = "LetsEncrypt"`,
  `hostname`, `contact` and `cert_dir = "/var/lib/ghost-link"`; in the service,
  `AmbientCapabilities=CAP_NET_BIND_SERVICE`. Apps then reach it at `https://link.example.com`. We don't run ours
  that way: this much is read from `iroh-relay`'s source, not from use.
- **Updating** is building again, installing the program over the old one and `sudo systemctl restart ghost-link`.
  A restart drops every device signed in to it at that moment; each signs in again by itself.

## Pointing the app at it

On each phone: **Settings › Routes › Relay server**. Type your relay's address (`relay.example.com` is enough; it
becomes `wss://relay.example.com/hub`) and press **Check it and use it**. The app connects and waits for the hub's
greeting; if a Ghost Messaging relay doesn't answer, nothing changes and it says why. If one does, it says what moving
means (above) and switches only when you say so. The section always shows which relay is in use, and on your own a
**Go back to Ghost Messaging's relay** row switches back in one press.

Everyone you want to reach through a relay has to set the same address.

## Checking it

```sh
curl https://relay.example.com/                 # Ghost Messaging relay
curl https://relay.example.com/market           # {"ok":true,"open":false,...} with GHOST_MARKET_ON=0
journalctl -u ghost-relay -f                    # or: docker compose logs -f relay
```

The program says on start what it has: pairings and handles kept, Files spaces, whether a TURN server is set, and
which sign-ins are on. `dart test` in `relay/` includes `test/self_host_test.dart`, which starts the program with an
empty environment and checks the sample env file lists every variable the relay reads.
