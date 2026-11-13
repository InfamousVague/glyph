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
- **Settings**: theme (system, light, dark), this phone's number, and the state of the SMS role, contacts and
  notifications.

Not yet: RCS and iMessage (no API exists for apps other than Google's and Apple's own), sending video or
audio, scheduled messages, blocking, dual-SIM choice (the phone's default SMS SIM is used), and a backup.

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

Builds are signed with the build machine's debug key for now, so a build from another machine has to be installed
over an uninstall. No messages are lost that way, because they are Android's, not the app's.

## What hasn't been tried on a phone

0.1.0 was built in a cloud container with no phone and no emulator (no KVM). The screens were drawn in Flutter's test
harness with made-up conversations (`test/shots/`), the MMS format was checked by `PduTest`, and the manifest was
checked for every component Android looks for before it offers an app as the default SMS app. Sending, receiving,
MMS download through a real carrier, and notifications have not run on a device.
