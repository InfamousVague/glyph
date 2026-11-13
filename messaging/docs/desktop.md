# Ghost Messaging on the desktop

Matt, 2026-11-13: "Is it possible for us to make a companion desktop app that can proxy messages encrypted from my
phone to my desktop and then send back to the phone to send again?", then "I'd like to support both a relay server
and local networking, it should attempt to use local networking by default and show the option for both in the setup
wizard". This was written as a design first; he read it and said "Yes, build it". It now says what was built, the
same day, and what has and has not been tried.

The phone stays the only thing that texts. The Mac shows what the phone has and asks the phone to send.

| Part | Where | What |
| --- | --- | --- |
| The phone's half | `android/…/Desk*.kt`, `WsClient.kt`, `ScanActivity.kt`; `lib/ui/computers.dart` | Answers the Mac from Android's own messages, sends what it asks; Settings › Computers |
| The Mac app | `macos/` and `lib/desktop/` (the same Flutter project, so the phone's screens, fonts and Glacier are its own) | The wizard, the conversations beside the one open, a composer, Settings |
| The relay | `relay/` (Dart's own library and nothing else) | Passes sealed frames between the two when they are on different networks |

## Pairing

1. The Mac's wizard asks how to connect: **Local network, then relay** (the default), **Local network only**, or
   **Relay only**, and for the relay's address, saying whether a relay answers there. Then it shows a QR code.
2. The code holds a public key made for this pairing, sixteen random bytes (the secret), the Mac's name, the choice
   and the relay's address (`GHOSTPAIR1:` and base64). It crosses no network: it goes from the screen to the camera.
3. The phone: Settings › Computers › Pair a computer. It scans the code (the camera and ZXing, on the phone), or
   takes the same code pasted. Its page shows the same three choices, set as the Mac had them, and can change them:
   the phone's choice is the pairing's.
4. The phone makes its own key pair and listens; the Mac, which is looking (the local network first, then the
   relay, as it chose), connects and is given the phone's public key.
5. Both make the pairing's key the way `E2eCrypto.kt` makes a conversation's: P-256 ECDH, then HKDF-SHA256 salted
   with both public keys. The secret goes in too, so whoever swaps a key on the way ends up with nothing.
6. Both show six digits made from that key. "They match" on both, and they are paired. The two private keys are
   thrown away; each side keeps only the pairing's key (the phone under an Android Keystore key, as `E2e.kt` keeps
   its own; the Mac in its Keychain, or in a file only the account can read where the build is not properly signed).

## Sealing

Everything after pairing is sealed, on the local network as much as through the relay (`DeskCrypto.kt`,
`lib/desktop/link/crypto.dart`).

- Each connection starts with a hello each way, in the clear: which pairing (a name made from the key, that says
  nothing of it), a fresh random number and a throwaway public key. The connection's two keys, one for each
  direction, come from the pairing's key, both random numbers and what the throwaway keys agree on.
- Each frame is AES-256-GCM with a counter as its nonce, never sent. A frame that is repeated, dropped, out of order
  or changed does not open, and the connection ends.
- Why more than `E2eCrypto.seal` as it is: a relay that replayed "send this text" would text someone twice. The
  throwaway keys also mean a pairing key taken later does not open what was recorded earlier.
- The first sealed frame each way is `ready`: it is what shows each side that the other holds the key. Nothing is
  answered before it.

## What they say to each other

JSON inside the seal, shaped like `lib/sms.dart`'s channel: on the Mac the phone's own screens run, and their calls
go to the phone (`lib/desktop/remote.dart`). The Mac asks (`req`), the phone answers (`res`), either says what
happened (`ev`).

| The Mac asks | The phone (`DeskCalls`) |
| --- | --- |
| `conversations`, `messages`, `people`, `searchContacts`, `contact`, `threadFor`, `e2e` | answers from `Store.kt` and `E2e.kt` |
| `part` (in pieces), `photo` | a picture's or a face's bytes |
| `send` (a name for the text, the numbers, the words) | `Sender.send`, once for each name |
| `markRead`, `threadFlag` (pinned, muted), `archive`, `draft`, `setDraft` | does it on the phone |
| | `changed` (a conversation), whenever a text arrives, is sent or changes state |

- Anything else is refused: a computer cannot delete, block, change encryption, read the phone's settings or send a
  picture. The Mac's screens do not offer those.
- `send` carries a name the Mac made. The phone remembers the last five hundred and never sends one twice, so a
  retry after a dropped connection cannot double a text.
- A conversation encrypted phone to phone works as it does on the phone: the phone opens and seals those texts, and
  they cross to the Mac under the pairing's seal.
- Either side says `mode` when how to connect is changed, and `unpaired`.
- Later: sending pictures and stickers, editing and deleting from the Mac, Mac notifications, Windows and Linux.

## Local network

- The phone listens on a port (the same one each time, when it is free) and announces `_ghostmsg._tcp` (Android
  NSD), again when its network changes. The Mac looks for it (Bonjour, `macos/Runner/DeskChannels.swift`) and
  connects, trying where it reached the phone last first.
- The phone listens, not the Mac, because a phone announcing is the dependable direction with its screen off, and
  the Mac then opens no port. macOS asks once to let the app find devices on the local network.
- Where a network keeps the two from finding each other, the phone's address (Settings › Computers on the phone)
  can be typed in the Mac's Settings.
- Anything else that connects cannot finish the hello and learns nothing.

## The relay

- A WebSocket server both ends dial out to (`relay/README.md` has what is said to it). A pairing has a channel and a
  token, both made from the pairing's key. The relay keeps the token's hash from the first connection and lets in
  only those who hold it, one phone and one computer, and passes frames from one to the other. If the other end is
  not there the frame is dropped and the sender is told.
- **What it stores:** for each pairing, the channel, the token's SHA-256 and the day it was last used. No texts, not
  even sealed ones; no queue; no names or numbers; no log of addresses.
- **What it can see:** that two addresses share a channel, when, and how much they send.
- Unpairing from either side removes the channel. One unused for ninety days is removed.
- Pairing through the relay uses a channel made from the QR code's secret in the same way, which goes as soon as
  both have left it and after ten minutes at most.
- **It is not on any server.** It runs on the Mac (`dart run relay/bin/relay.dart`). The wizard starts with
  `wss://ghost-sms.com/relay`, where it would live when Matt says, and says plainly that nothing answers there yet.

## Which way a message goes

With both allowed, the Mac tries the local network first: where the phone was last, what Bonjour finds, an address
given by hand. Only when none answers does it connect through the relay, which it holds ready meanwhile. While the
relay carries the connection it tries the local network again every fifteen seconds and takes it when it answers.
The choice can be changed later from either side, and the change is sent to the other, sealed.

## When the phone is asleep, or Android stops the app

- While a computer is paired, or being paired, the phone runs a foreground service (`DeskService`, Android's
  "remote messaging" kind) with a quiet permanent notification, "Paired with Matt's MacBook". It holds the port and
  the relay connection, and starts again after a restart or an update. It stops when no computer is paired.
- If Android stops it anyway, a new text starts it again, and the Mac reads what it missed when it reconnects.
- In deep sleep (still, unplugged, screen off a long while) Android cuts the app's network. What is typed on the
  Mac waits there, drawn as "Waiting for your phone", and goes when the phone is back. Settings › Computers leads to
  Android's battery setting for those who want the phone reachable in deep sleep.
- Nothing waits on the relay, ever. The Mac keeps the pairing and its own choices and nothing else: texts are held
  in memory and read from the phone again each time it opens.

## Unpairing

- The phone: Settings › Computers lists each one (its name, how it is connected now or when it was last seen, how
  it connects); a press chooses among the three ways, or Unpair. The Mac: Settings › Unpair this phone.
- Either one deletes its key, tells the other if it is connected, and has the relay forget the channel.
- A side that was away: through the relay, the Mac hears from the phone that the pairing is gone and says so. On the
  local network alone the Mac goes on waiting, and is unpaired there by hand.

## What changed in the phone app

- The camera permission (asked for when scanning), a foreground service, starting at boot.
- "The updater is the only connection the app opens" is true only while no computer is paired.
- One library, ZXing, to read the QR code on the phone. Nothing from Google Play.

## Trying it

```sh
flutter test                                    # sealing held to test/desk_vectors.json; the Mac's link against a
                                                # stand-in phone and the real relay; every screen, phone and Mac
cd android && ./gradlew :app:testDebugUnitTest  # the phone's sealing (the same examples), its session, its WebSocket
                                                # client, a QR code read from a frame
cd relay && dart test                           # the relay
flutter build macos                             # build/macos/Build/Products/Release/Ghost Messaging.app
```

Against an emulator, the real Mac app and the real phone app (`integration_test/desk_live_test.dart` says how):
Bonjour cannot cross the emulator's network, so the Mac is given the phone's address through `adb forward`, and the
relay on the Mac is reached from the emulator through `adb reverse`.

**Tried on 2026-11-13**, the Mac app and the phone app on the spare emulator: paired over the local network, through
the relay, and with both allowed (where the local network was taken first); the six digits the same on both each
time; the conversations listed; a text arriving on the phone shown on the Mac within a second or two; a text typed
on the Mac in the phone's own store as sent; unpaired from the Mac and from the phone, the other told and the relay's
channel removed; the service and its notification there while paired and gone after. The scanner opens and shows the
camera.

**Not tried**, since they need the Fold or a signed build: the two finding each other by Bonjour and NSD on a real
network; reading the QR code with a real camera; the Keychain (the builds here kept the key in a file); the service
through a night of deep sleep, and whether a text arriving brings it back; anything on a carrier.

## Matt has not said

The design asked three things, and "Yes, build it" answered none by name, so it is built as the design had it:

1. The permanent notification on the phone while a computer is paired.
2. The Mac keeps no texts on its disk, so it opens empty until the phone answers.
3. The relay at `ghost-sms.com/relay` when he says, and on the Mac until then.
