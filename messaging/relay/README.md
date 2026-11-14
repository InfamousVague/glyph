# Ghost Messaging's relay

Passes sealed frames between a phone and the computer it is paired with when they are on different networks
(Matt, 2026-11-13: "I'd like to support both a relay server and local networking"; [../docs/desktop.md](../docs/desktop.md)).
Dart's own library and nothing else. It has not been put on a server: it runs on the Mac until Matt says.

```sh
dart pub get                                   # the test package only; nothing the relay itself runs
dart run bin/relay.dart --port 8787 --verbose  # ws://127.0.0.1:8787
dart test                                      # the relay and its SHA-256
dart compile exe bin/relay.dart -o ghost-relay # one file to run on a server
```

Use the `dart` that comes with Flutter (`$(dirname $(which flutter))/dart`) where another is first on the path.

## The hub

The same program also serves **the hub** at any address ending `/hub`: where two people's apps find each other
through this server (Matt, 2026-11-14: "for right now we can use our servers to negotiate calls through the app").
It is `lib/hub.dart`, with its own signature checking in `lib/p256.dart`, and is described with the rest of the
app's routes in [../docs/network.md](../docs/network.md). Behind a web server it needs one more line beside the
relay's: in Caddy, `handle /hub { reverse_proxy 127.0.0.1:8787 }`. It keeps nothing on disk.

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

## On a server, when Matt says

Listen on 127.0.0.1 and let the web server that holds the certificate pass `/relay/*` to it, so the address the
apps use is `wss://ghost-sms.com/relay`. In Caddy: `handle /relay/* { reverse_proxy 127.0.0.1:8787 }`. It needs no
other setup. Not done: nothing here has been run anywhere but the Mac.
