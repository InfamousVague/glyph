# Ghost Messaging on the desktop

A design, written before anything is built (Matt, 2026-11-13: "Is it possible for us to make a companion desktop app
that can proxy messages encrypted from my phone to my desktop and then send back to the phone to send again?", then
"I'd like to support both a relay server and local networking, it should attempt to use local networking by default
and show the option for both in the setup wizard").

The phone stays the only thing that texts. The Mac shows what the phone has and asks the phone to send.

| Part | Where | What |
| --- | --- | --- |
| The phone's half | the existing app (Kotlin, plus a Settings page) | Answers the Mac from Android's own messages, sends what it asks |
| The Mac app | `messaging/desktop/` (Flutter, Glacier, the phone's own bubbles and rows) | The wizard, the conversations, a composer |
| The relay | `messaging/relay/` (Dart, no dependencies, one small program) | Passes sealed bytes between the two when they are on different networks |

## Pairing

1. The Mac's wizard asks how to connect: **Both** (local first, the relay when local fails; the default), **Local
   network only**, or **Relay only**. Then it shows a QR code.
2. The code holds a public key made for this pairing, sixteen random bytes (the secret), the Mac's name, the choice
   and the relay's address. It crosses no network: it goes from the screen to the camera.
3. The phone: Settings › Computers › Pair a computer. It scans the code (read on the phone), or takes the same code
   pasted as text. Its page shows the same three choices, set as the Mac had them, and can change them.
4. The phone makes its own key pair, reaches the Mac (local first, then the relay, as chosen) and sends its public
   key sealed with the secret.
5. Both make the pairing's key the way `E2eCrypto.kt` makes a conversation's: P-256 ECDH, then HKDF-SHA256 salted
   with both public keys. The secret goes in too, so a relay that swaps a key on the way ends up with nothing.
6. Both show six digits made from the two public keys. "They match" on both, and they are paired. The two private
   keys are thrown away; each side keeps only the pairing's key (the phone under Android's Keystore, as `E2e.kt`
   does; the Mac in its Keychain).

## Sealing

Everything after pairing is sealed, on the local network as much as through the relay.

- Each connection starts with both sides sending a fresh random number and a throwaway public key. The connection's
  two keys (one for each direction) come from the pairing's key and those.
- Each frame is AES-256-GCM with a counter. A frame that is repeated, out of order or changed ends the connection.
- Why more than `E2eCrypto.seal` as it is: a relay that replayed "send this text" would text someone twice. The
  throwaway keys also mean a pairing key stolen later can't open what was recorded earlier.

## What they say to each other

JSON inside the seal, shaped like `lib/sms.dart`'s channel. The Mac asks, the phone answers, and the phone says when
something changed.

| The Mac asks | The phone |
| --- | --- |
| `conversations`, `messages` (a conversation, how many), `people`, `searchContacts` | answers from `Store.kt` |
| `part`, `photo` | a picture's or a face's bytes |
| `send` (an id, the numbers, the words) | `Sender.send`, then the new message's id |
| `markRead` | marks it on the phone |
| | `changed` (a conversation), whenever a text arrives, is sent or changes state |

- `send` carries an id the Mac made. The phone remembers the ids it has sent and never sends one twice, so a retry
  after a dropped connection can't double a text.
- A conversation encrypted phone to phone works as it does now: the phone opens and seals those texts, and they
  cross to the Mac under the pairing's seal.
- First version: every conversation and message, pictures shown, new texts live, sending text to a conversation or a
  new number. Later: sending pictures and stickers, reacting, editing and deleting from the Mac, Mac notifications.

## Local network

- The phone listens on a port and announces itself (`_ghostmsg._tcp`, Android NSD). The Mac looks for it (Bonjour)
  and connects, trying the address that worked last first. The phone announces again when its network changes.
- The phone listens, not the Mac, because a phone announcing is the dependable direction with its screen off, and
  the Mac then opens no port. macOS asks once to let the app find devices on the local network.
- Anything else that connects can't finish the handshake and learns nothing.

## The relay

- A WebSocket server both ends dial out to. A pairing has a channel and a token, both made from the pairing's key.
  The relay keeps the token's hash from the first connection and lets in only those who hold it, two at a time, and
  passes frames from one to the other. If the other end isn't there the frame is dropped and the sender is told.
- **What it stores:** for each pairing, the channel's id, the token's hash and the day it was last used. No texts,
  not even sealed ones; no queue; no names or numbers; no log of addresses.
- **What it can see:** that two addresses share a channel, when, and how much they send.
- Unpairing removes the channel. One unused for ninety days is removed.
- Pairing through the relay uses a ten-minute channel made from the QR's secret in the same way.
- It runs on the Mac for now. Its home would be `wss://ghost-sms.com/relay`, when Matt says to put it there.

## Which way a message goes

With Both, the Mac holds a relay connection ready and keeps looking locally. Local is used whenever it is up; the
relay takes over when it drops, and gives way when local comes back. The choice can be changed later from either
side, and the change is sent to the other, sealed.

## When the phone is asleep, or Android stops the app

- While a computer is paired the phone runs a foreground service (Android's "remote messaging" kind, made for this)
  with a quiet permanent notification, "Paired with Matt's MacBook". It holds the port and the relay connection,
  and starts again after a reboot. Without it Android stops the app minutes after the screen goes off.
- If Android stops it anyway, a new text always wakes the default SMS app. The service starts again and the Mac has
  the text within seconds.
- In deep sleep (still, unplugged, screen off a long while) Android cuts the app's network. New texts still reach
  the Mac, since Android lets the SMS app through for each. What is typed on the Mac waits there, marked "Waiting
  for your phone", and goes when the phone wakes. Settings offers Android's unrestricted battery setting for those
  who want the phone reachable in deep sleep.
- Nothing waits on the relay, ever. The Mac keeps the pairing and nothing else: texts are held in memory and read
  from the phone again each time it opens.

## Unpairing

- The phone: Settings › Computers lists each one (its name, when it was paired, when it was last seen, how it is
  connected now) with Unpair. The Mac: Settings › Unpair this phone.
- Either one deletes its key, tells the other if it can reach it, and removes the relay's channel. A side that
  wasn't reachable finds its key refused the next time and says the pairing was removed.

## What changes in the phone app

- The camera permission (asked for when scanning), a foreground service, starting at boot.
- "The updater is the only connection the app opens" stops being true once a computer is paired.
- One library, ZXing, to read the QR code on the phone. Nothing from Google Play.

## Trying it

Kotlin and Dart each open frames the other sealed, from one file of fixed examples (`E2eCryptoTest`'s way). On the
spare emulator: pair, list, an incoming text live, a text sent from the Mac, first direct and then through the relay
on the Mac. Bonjour can't cross the emulator's network, so there the Mac is given the address; finding each other
for real needs the Fold.

## Questions for Matt

1. The permanent notification on the phone while a computer is paired: fine?
2. The Mac keeps no texts on its disk, so it opens empty until the phone answers. Fine for now, or should it keep a
   sealed copy to open with?
3. The relay at `ghost-sms.com/relay` later, on your word; on the Mac until then. Fine?
