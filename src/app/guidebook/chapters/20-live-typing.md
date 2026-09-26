# Live typing

_A note open on two of your devices, typed into on either, arriving on the other a character at a time. A trial, and off until you switch it on._

## What it is for

Sync carries a note a few seconds after you save it. Live typing is for the moments a note is open in two places at once: the phone in your hand and the Mac on the desk, say. Each keystroke crosses as it is typed, in the time a message takes to pass through the server.

## Switching it on

Settings › Account › **Live typing (trial)**. The switch says what it does: "A note open on two of your devices shows what is typed on either as it is typed, end to end encrypted like everything else. Starts with the next note you open."

- It is off by default.
- It belongs to the device. It does not travel with your synced settings, so switch it on on each device you want in.
- It starts with the next note you open. A note already open carries on as it opened.
- Off, none of it is loaded at all.

## What it needs

| | |
|---|---|
| An account | signed in on both devices, to the same account |
| The switch | on, on both |
| The note | on both already, by sync, and open on both at once |
| A connection | both online |

It works only between your own account's devices. Nobody else can join a note of yours, and there is no way to invite anyone.

Local only does not hold it off. With the switch on, a note open on two devices goes live even while Local only has stopped sync, so switch Live typing off too if you want nothing to leave the device.

## Using it

Open the same note on both devices and type. Nothing on screen says the note is live: the words arriving are the sign.

- **Both keep what they typed.** Two devices typing into the same line at once are merged, not overwritten.
- **Undo is yours.** Undo takes back this device's typing, never the other's.
- **The first one in brings the words.** The first device to open the note brings it as it has it, and the next takes the note as the first has it. If the second had changes that had not synced yet, they are not lost: its version is kept as a note of its own, the way sync keeps a conflict ([[Accounts, sync and the key you hold]]).
- **A dropped device comes back.** A device that falls asleep or loses signal reconnects by itself and catches up. Where it cannot, the note goes back to ordinary sync.

## Sealed, and kept nowhere

Every keystroke is sealed with your account key before it leaves the device. A relay on the sync service passes it to your other device without being able to read it, stores nothing and logs no message. What the relay can see is that your account has a note open live, which note by its id, when, on how many devices, and the size and timing of the messages. Never a word.

## Sync stays underneath

Live typing sits on top of sync; it does not replace it. While another device is in the note with you, sync leaves that note alone, so a few characters still on their way never look like a conflict. When the session ends, both devices hold the same words, and the next sync sends them as it would any change. Recordings, pictures, and every note that is not open on two devices at once, travel by sync alone.

## Not there yet

- **Carets.** You do not see where the other device's caret is. The message for it is defined in the app and never sent.
- **Peer to peer.** Every keystroke goes through the relay. A direct link between your devices is planned, and not built.
- **Other people.** Live typing is between your own devices. To show someone a note, share a read-only link ([[Sharing a note or a book]]).

## Read next

- [[Accounts, sync and the key you hold]]
- [[Sharing a note or a book]]
- [[Live typing over a relay]]
