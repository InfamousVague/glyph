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
  and so are its bubble effects (slam, loud, gentle, invisible ink). One to three emoji alone are drawn large. Since
  0.6.0 each effect moves pictures drawn for it (below). Settings › Effects turns
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
- **Coming from Google Messages or Samsung Messages** (0.6.0; `Arriving.kt`; Matt, 2026-11-13, of a friend whose
  chats "didn't load into ghost messaging" and whose texts stopped arriving: "can you detect this somehow and then
  instruct the user how to fix it?"). Two things catch people, and neither is this app's doing. RCS chats are kept
  inside the app that made them, where Android lets no other app read them: they do not appear here, and they are not
  deleted (the app deletes only on Delete conversation, Delete message, and resending a failed one). And while RCS
  chats are on, the number stays registered for RCS, so people whose phones use RCS go on sending chats that never
  arrive as texts. Android tells no app whether RCS is on for a number, so that is never claimed; what is seen is the
  default SMS app before this one, whether it is still on the phone, how many texts Android's store holds and how few
  are recent, and whether this copy came from a file. The setup screen names the app being left and has "Open Google
  Messages settings" (its General settings, RCS chats first) before the switch; after it, a dismissible notice heads
  the list ("Texts from some people not arriving?") and Settings › Android has the two ways out: Google's page that
  turns RCS off with a code it texts (`messages.google.com/disable-chat`; the text arrives here), or handing the role
  back for a moment. The list's empty state says where RCS chats are, and Settings › Android says what Android's store
  holds, so "nothing was read" can be told from "there was little to read". **This app does SMS and MMS only: no app
  but Google's can do RCS on Android.**
- **Allow restricted settings** (0.6.0; Matt: "until we get on the play store add a link to open the app in settings
  to allow elevated access"). Android 13 and later may refuse a copy installed from a file the SMS role or a
  permission. Where the switch is refused, the setup screen leads to Android's page for the app (⋮ › Allow restricted
  settings), and Settings › Android has the same link while the copy is one from a file.
- **Loading, and reading that fails** (0.6.0; Matt: "Show a loading indicator when messages are syncing"). The list
  says "Loading your conversations…" under an arc the first time, shows a thin bar under the search when a later
  read takes a moment, and a conversation says "Loading messages…". A read that fails is said, with Try again, never
  shown as an empty list; a store that will not list its conversations is read from the texts themselves
  (`Store.conversationsFromTexts`), and a conversation whose count the store says is nothing is checked before it is
  left out.
- **Several conversations at once** (0.6.0; Matt: "allow selecting multiple convos to delete them"). A conversation's
  long press has Select; then a tap adds or takes away, the bar counts them, and they are deleted (asked first, with
  how many) or archived together. Android's Back leaves choosing first.
- **Finding each other, and the encryption banner** (0.6.0; `GhostMark.kt`; Matt: "detect if both users are using
  ghost messaging", "it should show a banner that can be dismissed asking the user to enable encryption for better
  security"). With no server to ask, a copy of the app says it is there in its texts: three invisible characters at
  the end of one, at most once a day to a person, only while nothing has been exchanged with them, only where the
  text stays the same number of SMS, and never on a reaction or one of the app's own `ghost:` texts. Every other app
  draws them as nothing; another copy remembers the person has the app. Their conversation then shows a banner over
  the composer, "Maya has Ghost Messaging too. Encrypt this conversation for better security?", with Turn on (which
  sends this phone's key; the other person's bar then has Turn on too) and a cross that puts it away for that
  conversation. Nothing is sent because of the hello. Settings › Encryption › Find people who have Ghost Messaging
  turns the hello off.
- **Bubble colours** (0.6.0; Matt: "a suite of colors to pick for the chat bubbles including white and gray"):
  Ghost, Ink, Wallpaper, White, Silver, Gray, Graphite, Blue, Indigo, Purple, Pink, Red, Orange, Yellow, Green and
  Mint, the words on each black or white, whichever reads, and a line round a bubble the page would swallow.
  Settings › Appearance for every conversation, and a conversation's own in its settings.
- **Each conversation's own settings** (0.6.0; `lib/ui/chat_settings.dart`; Matt: "each chat should get it's own
  settings cog"): a cog at the conversation's top (and a tap on the name) opens its people, its background, your
  bubbles in it, its encryption, and mute, pin and archive.
- **The keyboard comes back** (0.6.0; Matt: "tabbing in and out of the app again makes it so the keyboard dissapears
  but the input stays selected so there is no way to re open the keyboard"). A tap on a field that already has the
  cursor where it was tapped changes nothing, so Flutter asked for no keyboard. Any tap on the message field asks
  for it now, and coming back to the app with the cursor in the field brings the keys back.
- **The icon** (0.6.0; Matt: "update the icon to use the one from the desktop"): the white ghost that is a speech
  bubble, on black (`art/app-icon.png`; `python3 tool/app_icon.py` makes the adaptive icon, the themed layer, the
  notification's icon, the setup screen's mark and the site's icons from it).
- **Speed** (0.6.0; Matt: "work on improving speed and performance"). Who a number is is kept until Android says the
  contacts changed, where it was asked again for every conversation on every text that came or went; Android's
  blocked list is read once for the whole list; a conversation's picture messages are read in one question, and who
  sent each is remembered; pictures are read apart from everything else and only the last forty are kept in memory;
  typing no longer redraws the messages; the app's start asks for its stylesheets, choices and wallpaper colours
  together. On an emulator with 161 conversations the list's first read took 697 ms and each one after 7 to 9 ms
  (before, every read was a first read). `adb shell setprop log.tag.GhostPerf VERBOSE` before the app starts writes
  each call's time and the frames' to Android's log.
- **The effects' characters move** (0.6.2; Matt, 2026-11-13: "i'm going to include 6 frame animations for each
  asset in a sprite sheet", then "Push an update and release after you've sliced all the animated pictures sprites
  and the sticker pack from the desktop"). Seventy-eight of the eighty characters came drawn six times each, three
  across and two down, in files named for the effect and the character's place on its sheet
  (`bye_r1c2 · wave right hand.png`). `python3 tool/effect_anims.py ~/Desktop/Animated` finds each drawing by its
  shape (`effect_sprites.cut_grid`) and lays the six side by side as they stood in their places, so what moves
  between drawings moves and what keeps still keeps still: `assets/effects/<effect>-a<N>.webp`, 5.5 MB in all, with
  a picture of each strip in `build/effect-anims/`. The app plays a character's strip at eight drawings a second
  where it has one, each character starting on a drawing of its own, and shows the still where it has none
  (`EffectSprite`; balloons' first and confetti's second character are not drawn yet). The drawings themselves, a
  quarter of a gigabyte, are not in the repository: they are in the folder Matt keeps them in.
- **Mischief, a fifth sticker pack** (0.6.2): the dark-cute one, drawn for itself: our ghost with little horns and a
  heart-tipped tail in black, purple and hot pink. Its sheet of sixteen (`art/stickers/mischief.webp`) is cut by the
  same tool as the other packs (`python3 tool/sticker_packs.py mischief="<the sheet>"`). With five packs the
  sheet's tabs slide, and the pack it opens on is brought into view.
- **Mischief moves** (0.7.1; Matt, 2026-11-14: "Update the sticker pack to use the animated sprites from the
  desktop"). `~/Desktop/AnimatedStickers` held each of the pack's sixteen stickers drawn six times;
  `python3 tool/sticker_packs.py mischief=~/Desktop/AnimatedStickers` cuts each into its drawings, lays them in one
  frame as they stood, gives each the white edge and writes an animated PNG (`assets/stickers/mischief/07.png`,
  320 pixels, 130 ms a drawing, 157 to 217 KB): one file that is the sticker in the app and what is sent. An
  animated PNG moves on an iPhone and in this app and is an ordinary still picture, its first drawing, to an app
  that does not know the kind, with its clear edge kept either way; a GIF would move everywhere but has no soft edge
  and few colours. The colours are chosen for it (`few_colours`: median cut and dithering for what is solid, a few
  greys at a few strengths for the soft edge), since the first attempt banded. `Sender.sendSticker` sends one that
  moves as it is (`Stickers.moves` looks for the animation's mark). The other four packs are stills as before; the
  drawings themselves (44 MB) are not in the repository.
- **Picture messages that keep trying** (0.7.0; Matt, 2026-11-14: "let's focus on reliability of sending pictures
  and whatnot"). A picture message that fails for want of a connection, or because the carrier's server is in
  trouble, is sent again by the app itself after twenty seconds and again after ninety (`MmsWhy.worthAnotherTry`,
  an alarm to `MmsResultReceiver.RETRY`), standing as Sending meanwhile; the person is told only if the third try
  fails too. Not where they have to do something first (mobile data off) or the carrier said no to the message. A
  picture message that was fetched and could not be read used to be gone, since a carrier lets go of a message once
  it is fetched: its bytes are now kept (`files/mms-kept/`) and read again each time the app comes forward, which
  is after every update, when the reading may have been mended; the Developer log says why it could not be read and
  how it begins. And a message left on Sending for a quarter of an hour (the phone switched off, the app stopped
  before Android answered) is marked not sent, so it can be tried again (`Store.failStale`). Tried against the
  stand-in carrier: with its server refusing the first four attempts, the first try failed, the app tried again
  unasked and the sticker went; a message it could not read was put by and logged.
- **Picture messages that say why** (0.6.2; Matt, 2026-11-13: "It seems like picture sending is also not working at
  all almost like MMS isn't working"). Picture messages had never run anywhere, so they were run: on an emulator
  with a stand-in for a carrier ([tool/mms/](tool/mms/README.md)) a sticker and a 4000×3000 photo went out, both
  read back whole by Android's own parser (`PduParser`), and a picture message announced to the phone was fetched,
  stored and shown. So what stops one on a real phone is the phone's or the carrier's, and the app now says which.
  A picture message that fails says why under it ("Not sent: mobile data is off. Picture messages need it, even on
  Wi-Fi."; `MmsWhy.kt`, from Android's result code and the carrier's HTTP answer). A carrier that takes a message and
  refuses it in its answer (X-Mms-Response-Status), which Android reports as sent and the app used to show as Sent,
  is shown as not sent with the carrier's own words. The message field says what would stop one before it is tried
  (mobile data off, the carrier's settings disallowing it, no SIM). A picture message announced and not fetched used
  to be lost; now it waits and is asked for again each time the app comes forward, for five days (`MmsDiag.kt`).
  Settings › Android › Picture messages shows all of it, how the last one sent and the last one received went, and
  copies a report with no messages, names or numbers in it.
- **Photographs** (0.6.2; Matt: "Stickers seem to work fine its specifically media messages like pictures"). What a
  photograph goes through and a sticker does not was read again and tried, and four things were wrong. Trying a
  failed picture message again sent its words alone as a text and deleted it, so the picture was gone: it now goes
  again with its own pictures, read back from Android's store (`Sender.resendMms`). On a message that was a picture
  and no words, "Tap to try again" did nothing, because the picture's own tap (open it) won and the red line took
  none: both send it again now. A picture that could not be read was left out without a word and the message went
  with nothing in it: now nothing goes, and the screen says why, with the pictures put back in the field. And the
  JPEG made from a phone's HDR photograph carried a second picture inside it (a gain map), which a carrier's server
  is not known to take: a plain eight-bit JPEG is made (`shrink`). A message is never made larger than 1 MB whatever
  the carrier's settings say, and one the carrier refused goes again with its pictures under 300 KB in all.
- **Settings › Developer** (0.6.2; Matt: "Maybe it would be good to include a developer setting with copying errors
  and reporting"): the app's own log (`DevLog.kt`, the last 300 lines, kept in the app's files): every call that
  failed, every error on the screens' side, and each picture message as it went (what the picture was, what it was
  made into, the carrier's limit, Android's result, the carrier's HTTP answer and status). Copy the report, Share
  the report (Android's share sheet: an email, a note), Clear the log. No message's words go in it and what looks
  like a phone number is struck out.
- **A phone with a great many messages** (0.6.1; Matt, 2026-11-13: "Users with a ton of messages stored on their
  phone are taking forever to load, see if we can load by most recent first so that things are faster"). Measured on
  an emulator filled by `python3 tool/seed_store.py emulator-5586` with 3,000 conversations, 126,000 texts and 19,600
  picture messages: 0.6.0 showed nothing for 21 seconds, read the whole list again for 5 seconds every time a text
  came or went, and held a conversation's messages behind that read. Now the list is read the newest first
  (`Store.conversationsPage`, `_load` in `lib/ui/conversations.dart`): the newest forty and the pinned ones at once,
  which is the screen, in about a tenth of a second, then the rest 250 at a time behind them (4.6 seconds for all
  3,000 the first time, under a tenth after), with "Loading older conversations…" at the list's foot. A text that
  comes or goes reads only the newest again (13 ms). What made it slow was a question to Android for each
  conversation where one does for all: every conversation's address (`readCanonical`), every contact's numbers
  (`knownNumbers`, found by `ContactKey` and then compared whole as before), and the summary of a conversation whose
  newest message is a picture, which is now read once and kept until the conversation changes (`latestSnippet`). The
  list is read on a thread of its own, so nothing waits behind it. A conversation opens on its newest 120 messages
  and reads 300 more each time the reader nears the oldest held; before, the newest 300 were all it could show.
  Settings and a conversation's own settings no longer read the whole list to learn one thing.
- **The effects' own pictures** (0.6.0; Matt: "the ghost messages assets are on the desktop, please wire them all and
  slice them up"). Each of the twenty effects has a sheet of about twelve sprites drawn for it
  ([docs/effect-sprites-prompt.md](docs/effect-sprites-prompt.md)): four ghost characters and eight props.
  `python3 tool/effect_sprites.py <folder>` keeps the sheets in `art/effects/` (lossless, the background remover's
  halo cleared) and cuts each into its sprites by shape, not by a grid, into `assets/effects/<effect>-h1.webp…` (the
  characters) and `-p1.webp…` (the props), with a picture of every sheet's cuts in `build/effect-sprites/` to look
  over. The app moves them (`EffectSprites` and `_spritePlans` in `lib/effects.dart`): props many and small,
  characters few and large, rising, falling or bursting as the effect does. What only the app can draw stays under
  them: the fireworks' and lasers' light, the spotlight, Echo's copies of the message's words. An effect with no
  pictures is drawn as before. 240 sprites, 2.6 MB.
- **Reactions under the message, and effects as reactions** (not released; Matt: "I want the message reactions to
  pop up under the message like imessage does", "I'd like to be able to react with full screen effects by pressing
  and holding on a message as well"). A long press on a bubble dims the page round it and brings up, beside it, the
  reactions, then the twenty screen effects, then Copy, Edit and Delete (`lib/ui/message_popover.dart`). An effect
  chosen there goes as a reaction with the effect's own emoji (`Reacted 🎈 to “…”`), which every phone can read; this
  app hangs it on the message and plays the effect over the conversation, on both phones, once.
- **A picture that could not be downloaded** (not released; Matt: "the message app said that a photo could not be
  downloaded… when I tap it I'd like it to take me to the associated chat and show the failed image with a retry if
  needed"). A picture message is announced by the carrier first and fetched after. The announcement is now kept in
  the sender's conversation until the picture is here (`Store.insertMmsNotice`): "Downloading picture…" while it
  comes, and where it cannot be fetched, "This picture couldn't be downloaded" with Try again, which asks the
  carrier for it once more (`MmsPushReceiver.retry`). The notification opens that conversation. Before this the
  notification led nowhere and nothing was kept to try again from.
- **The update banner** (not released; Matt: "the app should auto check for updates on load of any page so it pops
  the banner"). Every page that opens asks for a look for a newer version, made no oftener than every five minutes,
  and while one is waiting a banner over every page says which, with Update now (`lib/ui/update_banner.dart`).
- **Voice messages** (not released; `Voice.kt`, `lib/ui/voice.dart`; Matt: "I also want to have the ability to send
  audio messages"). With nothing written, a microphone stands where Send would. Tap it and the composer becomes the
  recording: a clock, how loud it hears you, how long one may run, a bin to throw it away, Send. It goes as a
  picture message does, an MMS with one sound in it (AAC in an `.m4a`, about three kilobytes a second), so any phone
  can play it and it is not encrypted, which an encrypted conversation says before it goes. How long one may run is
  what the carrier lets a message weigh: about a minute and a half at 300 KB, about five minutes at 1 MB; the
  recorder stops itself there. One that comes or goes is drawn as a player: play and pause, how far through, how
  long. Android gives the default SMS app the microphone along with the role, so it is asked for only where that was
  taken back; it is open only while a recording is under way with the app in front, and leaving the app throws the
  recording away. One that did not go is sent again whole by 0.6.2's `Sender.resendMms`, as a picture is. On a Mac a
  voice message is named and not played.
- **Stickers** (0.6.0; Matt: "generate 4 sticker packs using our ghost mascot we've developed including a sanrio
  one"). Four packs of sixteen, made by `python3 tool/sticker_packs.py` from the ghost's poses on the effects' sheets,
  each with a sticker's white edge: **Ghost** (hello, boo, wow, sorry, coffee, asleep), **Love**, **Party**, and
  **Sweet**, the pastel one: the ghost in soft pink, lilac, mint, butter and sky with little hearts, flowers and
  sparkles. Sweet is our own ghost in that cute pastel manner; none of Sanrio's characters, names or drawings are in
  it, since those are Sanrio's. The sticker button is in the message field while it is empty; the sheet
  (`lib/ui/sticker_picker.dart`) has a tab for each pack and opens on the one last used, and a tap sends. A sticker
  goes as a picture message (`Sender.sendSticker`: a PNG of 55 to 130 KB, so its clear background survives and any
  phone can show it), which means it is never encrypted, and the sheet says so in an encrypted conversation. Its
  file's name (`ghost-sticker-love-03.png`, `Stickers.kt`) is all that makes this app draw it small on the page with
  no bubble, and call it "Sticker" in the list; any other app shows a picture. 64 stickers, 1.3 MB.
- **Videos** (not released; `Video.kt`, `lib/ui/video.dart`, `macos/Runner/DeskVideo.swift`; Matt, 2026-11-14: "mp4
  files are not loading it just shows up as a string of text for the filename"). A video in a message is drawn as a
  picture of where it starts, with Play over it and how long it runs, where it was its file's name and no more. A
  tap plays it: the whole screen on the phone (Android's own player and controls), a window of its own on the Mac
  (the Mac's). The phone makes the picture from the message's own part; the Mac brings the video's bytes over the
  link as it does a picture's, and keeps them in a file only while the picture is made or the window is open (its
  folder in the temporary directory is removed as the app opens and quits). One no picture can be made of (a kind
  the device cannot read) is still named, and can still be tried. Sending a video is not part of this.
- **The Mac app updates itself** (built 2026-11-14; Matt: "install the app on my mac and make sure it has OTA
  updates so we don't need to reinstall again"). It reads `https://ghost-sms.com/mac.json` as it opens and every six
  hours, brings the newer app down, takes it only if it is whole and signed by its own team (Matt's Developer ID),
  puts it beside itself and swaps the two on Restart to update or on quitting. Ghost.md's Mac updater, carried
  over. `node tool/release-mac.mjs` makes a release (`--install`, `--notarize`, `--publish`). Nothing is published
  yet ([docs/desktop.md](docs/desktop.md), "Updating itself").
- **On a Mac** (built 2026-11-13, not released; [docs/desktop.md](docs/desktop.md); Matt: "a companion desktop app
  that can proxy messages encrypted from my phone to my desktop and then send back to the phone to send again", and
  "I'd like to support both a relay server and local networking, it should attempt to use local networking by
  default and show the option for both in the setup wizard"). Ghost Messaging for the Mac shows the phone's
  conversations beside the one open, shows a new text as it arrives, and sends what is typed there through the
  phone, which stays the only thing that texts. The two are paired by a QR code the Mac shows: the phone's own
  camera opens it in the app, which asks first ("Pair with Matt's MacBook Pro?"), or Settings › Computers › Pair a
  computer scans it or takes it pasted; both then show six digits to compare. Everything
  between them is sealed with a key made in the pairing (the phone-to-phone encryption's construction, with a key
  for each connection and a counter on every frame, so nothing can be replayed). They reach each other on the local
  network (the phone announces itself, the Mac finds it) or through a relay that passes the sealed frames and keeps
  none: both wizards offer local network then relay (the default), local only, or relay only. Settings › Computers
  lists the paired computers, how each is connected, and Unpair; the Mac unpairs too. While a computer is paired the
  phone shows a quiet permanent notification, which is what lets Android keep it reachable. What is typed on the Mac
  while the phone cannot be reached waits there, "Waiting for your phone". The Mac keeps no texts on its disk. A
  computer can read, send text, mark read, pin, mute and archive; it cannot delete, block, change encryption or
  send pictures. The relay is not on any server yet: it runs on the Mac until Matt says.
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
| Paired computers, on the phone | `Desk.kt`, `DeskService.kt`, `DeskSession.kt`, `DeskCrypto.kt`, `WsClient.kt`, `ScanActivity.kt` | Who is paired and each one's key (under an Android Keystore key), the foreground service that listens on the local network (NSD) and dials the relay, one connection as the phone answers it, the sealing, a WebSocket client written out, and the QR scanner (Camera2 and ZXing). Tests: `DeskCryptoTest`, `DeskSessionTest`, `WsClientTest`, `ScanTest`. |
| The Mac app | `macos/`, `lib/desktop/` | The same Flutter project with a macOS runner: `lib/main.dart` goes to `lib/desktop/main.dart` on a computer. `link/` is the sealing (pointycastle), a connection, the relay's socket and `PhoneLink` (pairing, local first, the relay when it fails); `remote.dart` answers the phone's screens' calls from the phone; `ui/` is the wizard, the two panes and Settings; `macos/Runner/DeskChannels.swift` is Bonjour, the Keychain and the Mac's name. |
| The relay | `relay/` | A WebSocket server in Dart's own library alone (`relay/README.md`). Not on a server. |

## Building

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64   # build/app/outputs/flutter-apk/app-release.apk
flutter test                                                  # reactions, edits, effects, emoji sets, settings and backgrounds; builds every screen;
                                                              # the Mac's sealing and its link to a stand-in phone through the real relay
flutter test --update-goldens test/screens_test.dart          # every screen, light and dark, written to test/shots/
flutter test --update-goldens test/desk_screens_test.dart     # the Mac's screens, written to test/shots/mac-*
cd android && ./gradlew :app:testDebugUnitTest                # the MMS encoder and decoder, the encryption, a background as a text, the codes offered,
                                                              # the sealing with a computer, a computer's connection, the WebSocket client, a QR code read
flutter build macos                                           # the Mac app: build/macos/Build/Products/Release/Ghost Messaging.app
(cd relay && dart test && dart run bin/relay.dart)            # the relay: its tests, then ws://127.0.0.1:8787
flutter test integration_test/desk_live_test.dart -d macos    # the real Mac app against the phone app on an emulator (the file says how)
```

`flutter build apk` builds the phone app exactly as before: the Mac app is the same project's other platform, and
nothing of it is in the APK but the Settings page and the phone's half (`Desk*.kt`).

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
python3 tool/app_icon.py            # every icon from art/app-icon.png, when the icon changes
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
Match my wallpaper, nor 0.5.0's synced background between two phones (a picture one above all: it is an MMS), nor a
0.6.0 sticker through a carrier (it is an MMS too). Since 0.6.2 picture messages have run both ways on an emulator
against a stand-in carrier (tool/mms/), which is not a carrier: a real one may still refuse what a stand-in takes. A
voice message was recorded on an emulator (whose microphone hears nothing), kept, played back, sent again after it
failed, and thrown away on leaving the app mid-recording; it has not gone through a carrier, been heard, or been
played on another phone. `docs/HANDOFF.md` section 3 is the list to go through on a phone.

The Mac app and the phone's half of it were tried against each other on an emulator, by each way of connecting
([docs/desktop.md](docs/desktop.md), "Trying it"). Not on the Fold: the two finding each other on a real network
(Bonjour and NSD), the camera reading the Mac's QR code, the Keychain in a signed build, and the phone staying
reachable through deep sleep.
