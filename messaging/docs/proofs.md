# Account keys, signed statements and vouches (GMFB-33)

Every Ghost Messaging account is a P-256 key pair; its **name** on the network is the first 16 bytes of the SHA-256
of the compressed public key, in hex (`docs/OPEN_NETWORK.md`, section 1). This page says how that key is shown to the
world, how a statement signed with it is written and checked, and how friends vouch for each other. The code is
`lib/me/identity.dart`, `lib/friends/vouches.dart` and `lib/ui/identity_ui.dart`; `tool/check-proof.mjs` checks a
statement with nothing but Node.

## The account key as a did:key

The app shows the account's public key as a [did:key](https://w3c-ccg.github.io/did-method-key/):

    did:key:z + base58btc( 0x80 0x24 || compressed public key (33 bytes) )

`0x80 0x24` is the varint of multicodec `p256-pub` (0x1200), so every one starts `did:key:zDn`. Nothing is looked up to
read it: the key is inside. It is the key the network knows the account by, the same on every device of the account.
Where the device is signed in to an account made from recovery words, Settings › Me › Profile shows that account's
`0x…` address too (`lib/account/account_crypto.dart`); there is no second DID method.

## A signed statement

Profile › Sign a statement makes a block like this (the statement is up to 280 characters):

    -----BEGIN GHOST PROOF-----
    Account: did:key:zDnaerDaTF5BXEavCrfRZEk316dpbLsfPDZ3WJ5hRTPFU2169
    Signed: 2026-11-23T10:15:07Z
    Signature: 3q2-7w…(86 characters)

    I am @matt on Ghost Messaging
    -----END GHOST PROOF-----

- `Account` is the signer's did:key; `Signed` the time, UTC, to the second, exactly as written.
- `Signature` is ECDSA over P-256 with SHA-256: `r` then `s`, 32 bytes each (IEEE P1363, not DER), in base64url
  without padding. Base64 with `+` and `/` is read the same.
- The **statement** is everything after the blank line, tidied before signing and before checking: line ends made
  `\n`, every line trimmed of spaces at both ends, blank lines at the start and the end dropped. So a site that turns
  line ends into `\r\n` or indents what is pasted doesn't break it.
- What is signed is the UTF-8 of:

      "ghost-proof v1\n" + Account + "\n" + Signed + "\n" + statement

  The first line keeps a proof's signature from being anything else the account signs (a home record, a device card,
  a vouch, a sign-in), each of which starts with words of its own.

Header lines are `Name: value`; their names are read without regard to case, and text before `BEGIN` and after `END`
is passed over, so a proof can be pasted into a longer post.

### Checking one without the app

    node tool/check-proof.mjs proof.txt      # or: pbpaste | node tool/check-proof.mjs

It decodes the did:key, decompresses the point, and verifies the signature with Node's own `crypto.verify('sha256', …,
{dsaEncoding: 'ieee-p1363'})`. Exit status 0 is good, 1 is not. In any other language: base58btc-decode after the `z`,
check the first two bytes are `80 24`, take the 33-byte key, and verify the P1363 signature over the bytes above with
any P-256 ECDSA library (WebCrypto's `ECDSA` with `SHA-256` takes the raw signature as it is).

Profile › Check a statement does the same inside the app, and says whose it is: yours, a friend's (the key is one
the app holds for them), or an account it doesn't know. Nothing is asked of any server.

## Vouches

On a friend's card, **Vouch for @name** signs, with the account key:

    "ghost-vouch v1\n" + voucher's name + "\n" + friend's name + "\n" + friend's public key (base64) + "\n"
      + ("yes" | "no") + "\n" + time in milliseconds

`no` is a vouch taken back. One person's newest word about one account stands; each new one is later than the one
before it, whatever the clock says. A vouch is good for **365 days from its time**: the time is signed and the year
is fixed in the app, so nobody can make one last longer. Vouch for again renews it for a year from then. An expired
vouch is counted by nobody, carried to nobody, and dropped from what the app keeps; a time more than a day ahead of
the viewer's clock isn't believed either. The friend's key is in it, so a vouch for one key says nothing about another key
that later has the same username.

How it travels (`lib/friends/buddies.dart`; every part is something a build from before passes over):

- To the friend, sealed, as an envelope of kind `vouch`: `{"b": voucher, "f": friend, "t": ms, "s": signature, "x": 1
  where taken back}`. The friend keeps it only where it came from the voucher, names this account and its key, checks
  against the key it holds for the voucher, and is newer than that voucher's word before (so an old vouch sent again
  never undoes its withdrawal). It keeps at most 64 vouches and 64 withdrawals.
- With the friend's sealed profile to their friends, as `vo` (`[{"b","t","s","x"?}]`, the friend's name left out
  since it is the profile's) in `buddy` `yes` and `me`, and alone in `buddy` `vo` whenever it changes. Never with a
  friend request, which goes in the clear. A person can hide the vouches they hold (Profile › Vouches); their friends
  are then sent an empty list.
- What a viewer shows: **Vouched for by N of your friends**, counting only vouches whose voucher is one of the
  viewer's own friends, checked against the key the viewer holds for that friend, and the friend's key the viewer
  holds. Never a count of everyone, nothing given to the relay or a directory, and nothing the relay can forge: it
  sees only sealed envelopes. A viewer keeps the withdrawals it has seen, so an older vouch carried again later is still
  taken back.
- Removing or blocking a friend, or their ending it, drops their vouch for you, yours for them, and what their profile
  carried.

What it can't do: someone vouched for who later hides a withdrawal from a viewer who never saw it can go on showing
that viewer the old vouch until the viewer sees the withdrawal (every honest copy of the profile carries it), and at
the latest until the vouch's year runs out.
