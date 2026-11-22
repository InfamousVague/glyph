# Forward secrecy and key rotation (GMFB-26)

From the Uplink gap review: "Forward secrecy and key rotation for friends and circles". Approved by Matt on
2026-11-22. This file is the design: what was built, what it protects, what it does not, the wire format, and how it
works with one account on several devices and with builds from before it.

Code: `lib/net/forward_secrecy.dart` (friends and an account's own devices), `lib/circles/circle_keys.dart` (circles),
with the switchboard (`lib/net/switchboard.dart`), the circle's room (`CircleRoom` in `lib/circles/circles.dart`) and a
space's chat (`HangoutRoom` in `lib/voice/hangout.dart`) using them. Tests: `test/forward_secrecy_test.dart`,
`test/circle_keys_test.dart`.

## Where things stood

- **Friends.** A packet between two accounts was sealed with the pair's key (`NetCrypto.netKey`), made by ECDH from
  the two accounts' long-term P-256 keys. Nothing else went into it.
- **An account's own devices.** Copies of conversations between the account's devices (GMFB-21) were sealed with
  `Me.mineKey`, which comes from the account's recovery words.
- **Circles.** A circle's room and its spaces' chat were sealed with keys made from seeds every member holds
  (`Circle.key`, `VoiceChannel.key`). Banning someone stopped their app from joining, but they kept the seeds.

So anyone who kept the packets (the relay, or anyone with a view of its traffic) and later learned an account's
recovery words could open everything that account ever sent or received, back to the first message. And a banned
circle member running a changed app could go on reading the circle silently.

## Threat model

The attacker we design against:

1. **Records traffic** passing through the relay: the operator, someone who breaks into the server, or anyone who can
   see its traffic. Today the relay can already see which ids talk, when, and how much.
2. **Later gets long-term secrets**: the account's recovery words, the account backup and its password, or the
   identity key. Or later **takes a device**, and with it everything stored on it at that moment.
3. **Is an active relay**: it can drop, delay, reorder and replay packets, and stamp any id on a room packet. It
   can't connect as an id without that id's key, because the hub checks a signature at hello.
4. **For circles, is a banned or kicked member**, possibly with a changed app. They keep the circle's seeds and every
   key they were ever given, and they can make new identities.

We do not try to defend against malware running on a device while it is in use, against someone who can read your
screen, or against the network learning who talks to whom. Ghost doesn't hide that today either.

## Friends, and an account's own devices

### Prekeys

Each device makes a P-256 key pair of its own, called a prekey. It is random, it is kept in the device's secret store
(the Keychain, or Android's vault, where the account's words are kept), it never goes into the account backup, and
it can't be worked out from the recovery words. A device:

- makes a new prekey every **day** (`rotateEvery`);
- deletes each prekey's private half **15 days** after making it (`keepFor`). That is 7 days in which others may
  still seal to it, plus the relay's longest hold of 7 days, plus 1 day of margin;
- offers its newest prekey inside every envelope it seals, as `f` in the envelope's JSON:
  `{"d": device, "p": prekey id, "k": public key, "m": made-at}`. A build from before ignores keys it doesn't know.

A prekey is believed because it came inside an envelope sealed by that peer: with the pair's key, or under forward
secrecy. So no signature and no server are needed. A peer holds up to 8 devices per account. It seals to a device's
newest prekey only while that prekey is less than **7 days** old (`useFor`), and it won't take a prekey whose
made-at time is more than a day in the future.

### Sealing a packet

When the other account has at least one device with a prekey this device can use, the packet is sealed like this:

1. Make a fresh P-256 key pair for this one packet. It is never stored and is dropped as soon as sealing finishes.
2. Make a random 32-byte content key, and seal the envelope with AES-256-GCM under it.
3. For each of the other account's devices, wrap the content key:
   `k = HKDF-SHA256(salt = pair's key, ikm = ECDH(one-off, device prekey), info = "ghost fs v1 wrap" | from | to | device | prekey id | one-off public)`,
   then seal the content key with AES-256-GCM under `k`.

The pair's key in the salt is what authenticates the sender, as it did before. The packet's flag byte gets bit 4
(`Packet` flags: 1 sealed, 2 part, 4 forward-secret). The last field is laid out like this:

```
[1: n, the number of devices][33: the one-off public key]
n × [16: device id][4: prekey id][12: nonce][32+16: the content key, sealed]
[12: nonce][the envelope, sealed under the content key][16: tag]
```

The envelope's additional data is `"ghost fs v1" | from | to | everything before it`, so entries can't be swapped,
added or removed. Copies to the account's own devices use the same scheme. There, `from` and `to` are both the
account's id, the salt is the words' key, and the targets are the account's other devices.

The primitives are only ones the app already used: P-256 ECDH (pointycastle), HKDF-SHA256 built from the existing
HMAC, and AES-256-GCM (`FastGcm`). There are no new ciphers. Each EC operation takes about 7 ms in a debug build, so
sealing for three devices takes about 20 ms. The old sealing takes about 0.06 ms.

### Opening, replays, deletion

- A device looks for the entry with its own id and opens it with the matching prekey, if it still holds that prekey
  and it is younger than `keepFor`.
- **Replays.** A tag of each one-off key opened is kept with the app's choices: the newest 5,000, each dropped when its
  prekey is deleted. A packet seen before is acknowledged again but not passed on, even after a restart. This matters
  because the switchboard's in-memory duplicate list is lost when the app starts again.
- **A packet this device can't open.** If there is no entry for it (the sender hadn't heard of it yet) or its prekey
  is gone, the device sends back an `fsk` envelope that carries only its prekey, at most every 10 minutes per peer.
  It doesn't acknowledge the packet, so Friends keeps re-sending it (with the same id, until it is acknowledged), and
  the next try includes this device.
- **Deletion.** The one-off private key is never kept anywhere. A prekey's private half is removed from memory and
  from the secret store at `keepFor`, and it isn't used even before the deletion actually runs. Signing out deletes
  everything (`ForwardSecrecy.wipe`).

### When it falls back to the old sealing

- **A peer that has never offered a prekey** (a build from before, or someone not yet heard from since updating):
  the old pair's-key sealing, exactly as before, with our prekey added. Their answer brings theirs.
- **A peer whose newest prekey is over 7 days old** (no packet from them in a week): one packet goes the old way, and
  its acknowledgement brings their new prekey.
- **Small routes.** Data texts (the SMS route, 133 bytes a part) always get the old sealing, with no prekey added, so
  a ringing call still fits in one text.
- **Receiving.** Packets sealed the old way are always accepted. Otherwise one old device of an account, or a stale
  prekey, would lose messages.

### One identity on several devices

An account is one identity with one id on every device. The relay hands a packet for an id to every connected device
of that id, or holds it for whichever device connects first. That rules out a classic per-device Double Ratchet:
the packet has to open on any device of the account that gets it. So a packet carries one wrapped key for each
device of the account that has offered a prekey. Every device in that list can open it on its own. Out-of-order and
lost packets need no special handling, because each packet stands alone and there is no chain state to fall out of
step.

- A new device, or one the sender hasn't heard of, answers with `fsk` as described above. Until a resend reaches
  it, it gets that message only through GMFB-21 copies from a sibling that could open it.
- A build from before on one of the account's devices never offers a prekey, so packets aren't sealed for it. If it
  is the only device connected, it takes a packet it can't open, doesn't acknowledge it, and Friends re-sends until a
  newer device takes it. Kinds that Friends doesn't re-send (profile updates, typing) can miss that old device. Text
  messages don't get lost.
- Device sync of history (GMFB-21) keeps working. Copies go to the account's own id, sealed to the siblings'
  prekeys, or the old way to siblings that haven't offered one.

## Circles: a new key when someone is put out

### Epochs

When the owner or an admin **bans** (`removeMember`) or **kicks** (`kickMember`) someone, their device does this:

1. Publishes the manifest saying so, sealed under the current key, so the person's own app still sees it and leaves.
2. Makes a random 32-byte key for epoch `e + 1` and signs a header:
   `"ghost-circle epoch v1|seed|epoch|commit|by|byKey|at"`, where `commit = HMAC(key, "ghost-circle commit v1|seed|epoch")`.
   Members believe a header only if it is signed by the owner or an admin of the circle (`CircleManifest.canSign`).
3. Seals the key separately to each eligible member's devices (see "Inboxes" below):
   `HKDF(salt = Circle.key, ikm = ECDH(one-off, inbox), info = "ghost-circle box v1|seed|epoch|commit|id|device")`, then AES-GCM.
   The person put out gets no box.
4. Says it in the circle's room (`rk`, then `kb` for every 200 boxes). The relay keeps these messages for devices
   that come in later.

From then on, the circle's room (manifest, joins, `was`) and the circle's spaces' chat and reactions are sealed under
`HKDF(salt = epoch key, ikm = the seed's own key for that room, info = "ghost-circle epoch v1|purpose|epoch")`, laid
out like this:

```
[3: "GE1"][4: epoch, big-endian][4: commit's first 4 bytes][12: nonce][AES-256-GCM output][16: tag]
```

The additional data is the 11-byte head plus `|purpose` ("circle" for the room, "space" for a space's chat). The seed
alone opens nothing sealed after a change. A key from one epoch opens nothing from a later one. Members keep every
epoch key they've held, so earlier messages still open.

### Inboxes, and coming in later

- Every member's device has a random inbox key pair for circle keys. It is kept in the secret store and isn't made
  from the recovery words. The device announces it in each circle's room as `ik`, signed by its identity, with
  `idOf(key) == from`.
- A device that knows of a newer epoch than it holds a key for asks with `k?` and its inbox. It learns of newer epochs
  from kept `rk` and `kb` messages, from a packet it can't open, or from a header hint (below). A device that holds
  the key answers with a `kb` box. Answers are timed the same way as manifest answers: the lowest id goes first, and
  the others wait a step and drop out if they hear the answer.
- `sync?` now carries `ke`, the newest epoch the asker holds. A device holding a newer one replies with just the
  signed header. That tells the asker to ask, even after the relay's kept messages have expired.
- **Who may be given the key** (`Circles.mayHaveKey`): the owner, admins, the identity's own devices, and anyone the
  circle has seen openly: anyone noted in its members list, or whose join was heard. They must also not be banned,
  and not kicked since they last said they came in. Someone who slips into the room with its token and is never
  seen (a banned member under a new key, for instance) is not given the key. To get it, they have to come in the way
  anyone does, and every member is told about that.
- A box is believed only if its key matches the commitment in a header the owner or an admin signed. So a removed
  member can't hand out a key of their own to people who'd then post under it. They can still replay real headers.
  Cancelling pending answers needs a header signed by the owner or an admin, from someone who may hold the key.
- **A banned member who comes back through the link** can't read the manifest that names them, because it is sealed
  under a key they aren't given. So the owner's or an admin's device answers their `sync?` with `out`: a statement,
  signed by that device and valid for 10 minutes, that this id is banned. Their app leaves, as it did before.
- `inbox`, `rk`, `kb`, `k?` and `out` are sealed with the seed's key, because a device without the newest key has to be able
  to read them. They contain only public keys, signatures and boxes.

### Mixed versions in circles

- A build from before keeps sealing with the seed's keys. Newer builds still open what it sends.
- After a change, a build from before **can't read** what newer builds post in the circle's room or its spaces'
  chat. Once it updates, it asks and is given the key. Messages the relay kept (7 days, 300 per room) then open when
  it next joins the room.
- Browser guests in a circle space (`site/join`) don't know about epochs, so after a change they can't read the
  space's chat.

## What is protected, and what is NOT

**Protected:**

- **Messages between friends, and copies between an account's own devices, sealed with forward secrecy,** against
  someone who recorded them and later gets the account's recovery words, its backup and password, or its identity
  key. Those are not enough to open them, ever. This holds for every envelope kind that goes through the switchboard,
  including friend requests, texts, calls being set up, groups of friends and acknowledgements.
- **The same messages against someone who later takes the device,** once the prekey they were sealed to has been
  deleted. That happens at most 15 days after the prekey was made, and the prekey was made at most a day before the
  message in an ongoing conversation.
- **Passive healing.** Someone who copied a device's secrets but doesn't interfere with traffic loses the ability to
  read new messages once the device has made a new prekey (within a day) and its friends have heard of it.
- **Circles after a ban or kick.** The person put out (and their changed app) can't read what is said afterwards in
  the circle's room or its spaces' chat and reactions. They can't get the new key under a new identity without
  coming in openly. Nobody can slip in a key of their own.
- **Replays** of forward-secret packets are acknowledged but not delivered again, even across restarts, while the
  packet is among the newest 5,000 opened or its prekey still exists. After that its prekey is gone, so it can't be
  opened at all.

**Not protected:**

- **Anything stored on a device.** Your message history is kept on your devices. Whoever takes a device reads what's
  stored there, forward secrecy or not. Forward secrecy protects traffic that was recorded, not your history.
- **Traffic recorded before this release,** and anything sealed the old way: the first message to someone you
  haven't heard from in a week, everything to and from builds from before, data texts (SMS route), and the old
  sealing on an account device that hasn't updated.
- **Active attacks after long-term secrets leak.** With an account's identity key, an attacker can seal messages as
  that account and offer their own prekeys, which makes them a man in the middle from then on. Forward secrecy is
  about the past. It doesn't stop impersonation in the future. Safety numbers are still how you check.
- **Who talks to whom, when, and how much.** A forward-secret packet also shows how many devices it was sealed for,
  and their device ids. The relay already knows those from the hello.
- **Encrypted texts with a phone number** (`E2e.kt`, the "Send my key" encryption for SMS) are a separate system and
  are unchanged.
- **Circles are not forward secret.** Members keep every epoch key they held, and a stolen member's device opens
  every epoch it held. Rotation is about people put out, not about time.
- **Leaving a circle doesn't change its key.** Leaving can't be told apart from going offline, and anyone who keeps
  the link can come back. A scheduled rotation isn't built either.
- **A banned member can still see the circle's traffic:** who is in its rooms, and when and how much is said. They can
  also come back openly under a new identity through the link, if they still have it. Members see them join, and
  can ban them again. Links themselves can't be revoked yet.
- **Not covered in a circle:** files in its Files spaces, and the call signalling of its voice spaces (call audio and
  video were already sealed per call by WebRTC). Spaces that aren't in a circle are also not covered. For all of
  these, the seed is still the key.
- **A member the circle has never seen** come in or write is not given the key until they do.

## Compatibility rules (summary)

| Sender | Receiver | What happens |
| --- | --- | --- |
| New | Old build | Old sealing. Our prekey goes in `f`, which the old build ignores |
| Old build | New | Old sealing, accepted as always |
| New | New, prekey heard within 7 days | Forward-secret sealing for every device of theirs heard from |
| New | New, not heard from for 7 days or more | Old sealing for one packet. The acknowledgement brings their prekey |
| Any | Over data texts (SMS) | Old sealing, nothing added |
| Circle, new, epoch held | Circle, old build | Old build can't read it until it updates and is given the key |
| Circle, old build | Circle, new | Seed's key, accepted |

**Relay:** nothing changes, so there is nothing to deploy. Prekeys travel inside sealed envelopes, and circle keys
travel in the circle's room as kept packets. A relay that knows nothing about this carries all of it.

## Not built yet

- One-time prekeys (per-message deletion on the receiving side), or a ratchet per pair of devices. Both would shorten
  the 15-day window for a stolen device. The multi-device hand-off would need to change for either one.
- Rotating a circle's seed and links, so a banned member can't come back through an old link.
- Epochs for circle Files spaces and voice-space signalling, and for browser guests.
- Scheduled circle rotation.
- A way to see, in Settings, which friends' devices get forward-secret messages.
