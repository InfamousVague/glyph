# Ghost Messaging

An SMS and MMS app for Android that replaces the phone's default messaging app, drawn with **Glacier**, the same
UI kit Ghost.md and Ghost Keyboard use.

Started 2026-11-13 at Matt's ask: "Sketch out a project and load it on my phone, use the same glacier UI we use for
other projects like ghost MARKDOWN and ghost KBD include basic functionality so i can replace my current sms today".
It lives in Ghost.md's repository for now, in its own folder, and can be moved to a repository of its own whole.

## What it does

- **Becomes the default SMS app**: the first screen asks Android for the SMS role. Every existing conversation is
  there straight away, because messages live in Android's own SMS/MMS database (the Telephony provider), not the
  app. Switching back to another SMS app loses nothing.
- **Conversations**: newest first, with contact names and photos, unread dots, a "Not sent" mark, search over
  names, numbers and the last message, long press to mark as read, archive (this app's own list) or delete.
- **A conversation**: bubbles grouped by sender and minute, day headings, sender names and faces in a group,
  Sending / Sent / Delivered / Not sent (tap to try again), pictures inline (tap to zoom), links underlined, long press
  to copy, delete or send again, a call button, and a counter once a text runs to more than one SMS.
- **Sending**: one person gets an SMS (split into parts when it's long). Several people, or a picture (up to five,
  scaled to the carrier's MMS size limit), get an MMS.
- **Receiving**: SMS, and MMS downloaded through Android's MMS service, decoded and stored, including group MMS. Group
  MMS leaves this phone's own number out of the list of people; when Android won't say what the number is, it can be
  typed in Settings.
- **Notifications**: one per conversation with its unread messages (MessagingStyle), with Reply and Mark as read.
- **Other apps**: `sms:` / `smsto:` / `mms:` links, shared text, and "respond via message" from the call screen.
- **Reactions** (0.2.0): texts like `❤️ to "See you at 7"` (Google Messages) or `Loved “See you at 7”` (iPhone)
  are folded onto the message they name, as a chip on its corner, instead of a bubble of their own: hearts, likes,
  laughs, `Reacted 🎉 to …`, reactions to a picture (`Loved an image`), and `Removed … from …` taking one off. A press
  on the chip lists who reacted with what. A quote cut short with "…" still finds its message; a reaction that names
  no message in the conversation stays an ordinary bubble. It works on old messages too, because it is read as the
  conversation is drawn (`lib/reactions.dart`, tested by `test/reactions_test.dart`).
- **Editing** (0.2.0): long press one of your messages, Edit. SMS can't change a text on the other person's phone, so
  saving asks whether to send the change as a follow-up text ("Correction: …") or change it on this phone only. The
  bubble says "Edited" (or "Edited · correction sent", with the correction's own bubble folded away), and a press on
  that shows what it first said. Editing a message that failed sends it again with the new words. The first text is
  kept in the app's own record (`Store.editMessage`, `lib/edits.dart`).
- **Sending reactions** (0.3.0): long press a message and pick ❤️ 👍 👎 😂 ‼️ ❓ or more. It goes as the iPhone's
  wording ("Loved “…”"), which Google Messages and Samsung Messages turn back into a reaction on the other phone and
  this app folds too. A press on one that is already yours takes it off ("Removed a heart from “…”").
- **Effects** (0.3.0; [docs/effects.md](docs/effects.md)): twenty screen effects set off by a phrase or by a message of
  key emoji: the iPhone's eight (echo, spotlight, balloons, confetti, love, lasers, fireworks, celebration), the ones
  Google Messages plays on a phrase (snow, kisses, wow, thank you, good night, good morning, get well soon, bye bye,
  hungry, sorry, party time), and ghosts for "Boo". An iPhone's "(sent with Lasers)" is read, played and not shown,
  and so are its bubble effects (slam, loud, gentle, invisible ink). One to three emoji alone are drawn large. An
  animated WebP in `assets/effects/` named for an effect plays in place of the one drawn. Settings › Effects turns
  them off, and lists every one with what sets it off; a tap plays it there.
- **Emoji sets** (0.3.0; `lib/emoji_sets.dart`, `assets/emoji/LICENSES.md`): the phone's own, Noto, Twemoji, OpenMoji
  or Noto's outline face, chosen in Settings and drawn everywhere in the app. `test/emoji_sets_test.dart` holds each
  set to drawing joined emoji (families, skin tones, flags, keycaps) as one glyph.
- **Ticks** (0.3.0): one for sent, two for delivered, two in colour for read, on every message of yours. Delivered is
  the carrier's delivery report (SMS and MMS). Read is an MMS read report, which is asked for on picture and group
  messages (Settings › Receipts) and which only some phones send; a plain text has no way to say it was read.
- **Pin, mute, block** (0.3.0): from a conversation's long press. Pinned ones stay on top; muted ones arrive without a
  notification; a blocked number goes on Android's own blocked list, which stops its texts and calls for every app.
- **Drafts** (0.3.0): what is typed and not sent is kept for its conversation and shown in the list.
- **Sign-in codes** (0.3.0): a notification for a text with a code in it has a "Copy 482913" button.
- **Updates** (0.3.0): the app looks at https://ghost-sms.com/apk.json as it opens (at most twice a day), downloads a
  newer release, checks its size, hash and signing certificate, and installs it (`Updater.kt`, Ghost Keyboard's).
  Settings › Updates has the switch, "Check for updates" and "Update now". It is the only connection the app opens.
- **Your bubbles** (0.3.1): Ghost Keyboard's primary by default (its accent: #51FCFB under dark teal on the dark
  page, #008B8A under white on the light), or the page's ink, or (0.4.0) the accent Android takes from the phone's
  wallpaper, in Settings › Appearance.
- **Encryption** (0.4.0; Matt, 2026-11-13: "enable an option for an additional level of E2E encryption by allowing
  users to exchange keys somehow and then encrypt all messages so only others with the app can read them"). With one
  person who also has Ghost Messaging, texts go sealed so only the two phones can read them. It is turned on from a
  conversation's header (tap the name, Encryption): that sends one text with this phone's key, and the other person
  gets a bar over their composer, "Maya wants to encrypt this conversation", with Turn on, which sends theirs back.
  From then the header says "Encrypted" with a lock, the composer "Encrypted message", each sealed message has a small
  lock by its time, the conversation has one after its name in the list, and the two key texts are drawn as lines
  ("You sent your encryption key"), not bubbles. The header's Encryption also shows the safety number, thirty digits
  that are the same on both phones when nobody swapped a key on the way, with "They match: mark as verified". A
  DIFFERENT key from someone already exchanged with turns encryption off until it is looked at and accepted. A sealed
  text whose key is gone (a reinstall, a new key) says "Encrypted message that can't be opened on this phone".
  What it is and is not, as Settings › Encryption says it: one person at a time (groups and pictures are MMS and go
  as they always have, and attaching a picture says so); the keys travel by SMS, so the safety number is what rules
  out a swapped key; no forward secrecy (no ratchet: it is not Signal's protocol); a sealed text is longer, so the
  composer counts the texts it will cost; to any other app a sealed text is a line of letters. The cryptography is
  `E2eCrypto.kt` (P-256, ECDH, HKDF-SHA256, AES-256-GCM; `E2eCryptoTest`), what the phone keeps is `E2e.kt`, and the
  screens are `lib/ui/thread.dart` and `lib/ui/encryption.dart`.
- **Chat backgrounds** (0.4.0; Matt, 2026-11-13: "allow changing the backgrounds for chats, there should be a standard
  way to have the backgrounds sync between apps as my google background syncs with samsung messenger"). One for every
  chat (Settings › Chat background) and one a conversation may have of its own (its header › Chat background): none,
  eight washes made for the app (pale in light, deep in dark), a colour (twelve offered, or mixed), a picture from
  the phone (a copy the app keeps, drawn under a veil, with the small words on pills), or **Match my wallpaper**.
  There is no standard by which texting apps share a background: Google Messages keeps its own on the phone that set
  it, for RCS chats only, where no other app can read it. What every app can share is the palette Android takes from
  the wallpaper (Material You, Android 12 on), and that is what Match my wallpaper wears, so it follows the phone as
  Google's and Samsung's apps do (`lib/backgrounds.dart`, `MainActivity.systemPalette`).
- **Synced backgrounds** (0.5.0; Matt, 2026-11-13: "I want the background to sync for everyone in a chat if they're
  all using ghost messaging"). A conversation's own background (its header › Chat background) has a switch, "Sync
  with Maya" ("with everyone here" in a group). On, what the conversation wears is sent to its people as the page is
  left, once, and their Ghost Messaging wears it too; what they choose comes back the same way, so the newest choice
  is everyone's. There is no server, so it goes as a text in the conversation (`BackgroundWire.kt`:
  `ghost:bg1:preset:dusk`, `color:#RRGGBB`, `none`, a wash's four colours for Match my wallpaper, since the other
  phone's wallpaper is its own, or `image` with the picture in the same message as an MMS, at the size the carrier
  allows). Both phones draw that text as a line, "Maya changed the chat background", not a bubble. It is sealed with
  the rest where encryption is on. The switch is on by itself only where everyone is known to have the app, which is
  once a text only the app writes has come from them (a key, a sealed text, a background: `Backgrounds.kt`); to
  anyone else it would arrive as a line of letters, and the page says so before it is switched on by hand. Settings ›
  Chat background › Wear backgrounds shared with you turns the receiving off. Every chat's background (the one in
  Settings) is this phone's alone.
- **Sign-in codes for Ghost Keyboard** (0.5.0; Matt, 2026-11-13: "The messaging app should also work with ghost kbd to
  proxy verification codes"). Ghost Keyboard shows a one-time code above its keys to tap in, but reading texts itself
  needs a permission Android 15 refuses apps from outside a store, and Android 17 holds code texts back from every
  app but the default SMS app. This app is the default SMS app, so it answers the keyboard instead (`Codes.kt`):
  a content provider, `content://com.infamousvague.ghostmessaging.codes/latest`, which looks through the texts of
  the last ten minutes with the finder the notification's Copy button uses and answers with the codes and when they
  arrived: three at most, never the words or who sent them, and nothing is kept for it. It answers Ghost Keyboard
  alone, known by its package and the SHA-256 of its release certificate; the keyboard pins this app's in turn (its
  `GhostMessagingCodes.kt`, docs/ghost-messaging-codes.md there). When a text with a code arrives, a keyboard that is
  watching is told to ask. Settings › Ghost Keyboard has the switch (on to start) and says whether the keyboard is on
  the phone. Needs Ghost Keyboard 0.18.0 or later.
- **Settings** (0.4.0; Matt, 2026-11-13: "make the settings page more like ghost kbd where it's nested sections and
  expand on the settings available"): a home of sections in groups with a search over every setting, each opening its
  own page, as Ghost Keyboard's does (`lib/ui/settings.dart` is the frame, `lib/ui/settings_panes.dart` the pages).
  Appearance (theme, your bubbles, text size), Chat background, Emoji (the sets, large emoji), Effects; Messages
  (Enter sends, attach reactions to messages), Receipts (delivery reports, read receipts, the ticks explained),
  Notifications (Android's permission, message previews, the copy-code button, sound and vibration); Encryption (what
  it is, the people, this phone's key, a new key), Blocked numbers (tap to unblock), Archived; Your number, Android
  (default SMS app, contacts, phone number), Ghost Keyboard (0.5.0); Updates, About. Settings › Updates says "ghost-sms.com isn't serving
  updates yet" where the site has no certificate, no such name, nothing answering or no release, and "This phone is
  offline" where that is why, in place of Java's own error.

Not yet: RCS and iMessage (no API exists for apps other than Google's and Apple's own, so no typing indicators and
no read receipts for plain texts), sending video or audio, scheduled messages, search inside messages, dual-SIM
choice (the phone's default SMS SIM is used), and a backup.

## How it is built

| Part | Where | What |
| --- | --- | --- |
| The screens | `lib/` | Flutter, drawn with Glacier (`packages/glacier`, copied from Ghost Keyboard's copy of Ghost.md's kit: `packages/glacier/VENDORED.md`), Ghost.md's stylesheets (`assets/css`), Ghost Keyboard's settings kit (`lib/kit`) and Lucide icons drawn as Ghost.md draws them (`lib/art`). |
| The bridge | `lib/sms.dart` and `MainActivity.kt` | `ghost_messaging/sms` (calls) and `ghost_messaging/events` (a conversation changed; a notification asked for one). |
| The messages | `Store.kt` | Android's SMS/MMS provider: conversations, messages, parts, contacts, and writing what arrives or is sent. |
| Sending and receiving | `Messaging.kt` | `SmsManager` for SMS and MMS, and the receivers Android requires of a default SMS app (`SMS_DELIVER`, `WAP_PUSH_DELIVER`). |
| MMS bytes | `Pdu.kt` | The MMS wire format, reading m-notification-ind and m-retrieve-conf and writing m-send-req and m-notifyresp-ind. Android does the radio and the carrier's HTTP but leaves the bytes to the app. Tests: `android/app/src/test/.../PduTest.kt`. |
| Notifications | `Notifier.kt` | Notifications with Reply and Mark as read, the "respond via message" service, and the file provider Android's MMS service reads and writes through. |

## Building

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64   # build/app/outputs/flutter-apk/app-release.apk
flutter test                                                  # reactions, edits, effects, emoji sets, settings and backgrounds; builds every screen
flutter test --update-goldens test/screens_test.dart          # every screen, light and dark, written to test/shots/
cd android && ./gradlew :app:testDebugUnitTest                # the MMS encoder and decoder, the encryption, a background as a text, the codes offered
```

The emoji sets' picture (`test/shots/7-emoji-sets.png`) is compared on Linux only: a Mac's test engine draws fonts
with Core Text, which leaves Twemoji's row blank, where Linux's and Android's draw it with FreeType.

## Releasing (ghost-sms.com)

Matt, 2026-11-13: "add auto update and serve it over ghost-sms.com I'll point the domain to the same server ghost kbd
uses". Both scripts are Ghost Keyboard's, for this app, and use Ghost.md's box account (`tauri/.env`) through
Ghost.md's own `box.mjs`, so they run where that file is: on the Mac, not in a cloud session.

```sh
node tool/deploy-site.mjs --caddy   # once: site/ into /opt/ghost-sms-site, and ghost-sms.com's block in the Caddyfile
node tool/release.mjs               # each release: build, sign, check, upload to /opt/ghost-sms-release, verify it is served
node tool/deploy-site.mjs           # when site/ changes
```

Both ran for the first time on 2026-11-13 (one box login, 19:56:05 UTC, held for both: `--keep-connection` on each
after Ghost.md's `build/diag/hold-box.mjs`): the Caddy block went in with every other site answering as before
(backup `/etc/caddy/Caddyfile.bak-20261113-195607`), and 0.3.1 (code 6) was the first release. From a worktree of
this repository the scripts need `--glyph ~/Development/Apps/glyph`: the box's `.env` is only in the main checkout.
`www.ghost-sms.com` has no DNS record yet, so its redirect has no certificate (ghostkbd.com's www is the same).

- **The release key** is made by the first `tool/release.mjs` in `~/.config/ghostmessaging/` (back it up) and its
  certificate is pinned there; `android/app/build.gradle.kts` signs release builds with it when it is present.
- **A build made without the key** (every APK so far: they were built in a cloud session and are signed with that
  machine's debug key) can't be updated to the release, since Android wants the same certificate. Such a copy says so
  in Settings › Updates. It is uninstalled and the release installed from ghost-sms.com once; no messages are lost,
  because they are Android's. Its settings, archive, pins and drafts are the app's own and start again.
- The domain must point at the box before `--caddy`, or Caddy can't get its certificate.

## What hasn't been tried on a phone

Every version so far was built in a cloud container with no phone and no emulator (no KVM). The screens and a frame
of each effect are drawn in Flutter's test harness with made-up conversations (`test/shots/`), the MMS format, its
reports and the sign-in code finder are checked by `PduTest`, reactions, effects and emoji sets by the Dart tests, and
the manifest was checked for every component Android looks for before it offers an app as the default SMS app.
Sending, receiving, MMS download and reports through a real carrier, notifications, blocking and the updater's
install have not run on a device; nor has 0.4.0's encryption between two phones, a picture as a chat background, or
Match my wallpaper, nor 0.5.0's synced background between two phones (a picture one above all: it is an MMS). `docs/HANDOFF.md` section 3 is the list to go through on a phone.
