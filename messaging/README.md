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
  animated WebP in `assets/effects/` named for an effect plays in place of the one drawn. Settings › Look turns
  effects off.
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
- **Settings**: theme, effects, emoji, receipts, this phone's number, the state of the SMS role, contacts and
  notifications, and updates.

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
flutter test --update-goldens                                 # reactions and edits; every screen, light and dark, to test/shots/
cd android && ./gradlew :app:testDebugUnitTest                # the MMS encoder and decoder
```

## Releasing (ghost-sms.com)

Matt, 2026-11-13: "add auto update and serve it over ghost-sms.com I'll point the domain to the same server ghost kbd
uses". Both scripts are Ghost Keyboard's, for this app, and use Ghost.md's box account (`tauri/.env`) through
Ghost.md's own `box.mjs`, so they run where that file is: on the Mac, not in a cloud session.

```sh
node tool/deploy-site.mjs --caddy   # once: site/ into /opt/ghost-sms-site, and ghost-sms.com's block in the Caddyfile
node tool/release.mjs               # each release: build, sign, check, upload to /opt/ghost-sms-release, verify it is served
node tool/deploy-site.mjs           # when site/ changes
```

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
install have not run on a device. Nothing has been published to ghost-sms.com yet.
