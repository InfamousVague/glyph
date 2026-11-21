/// What each release brought, as people read it (Matt, 2026-11-19: "Implement a changelog that pops up ever time a new
/// update is released with release notes").
///
/// The newest first. Each release adds its entry here before it goes out: tool/release.mjs, release-mac.mjs and
/// release-windows.mjs refuse a version with no entry (tool/lib/notes.mjs). Write for the people using the app: what
/// they can now do or what now works, a line each, in plain words, no file names. The first time the app opens after
/// updating, the entries it has not shown yet come up in What's new (lib/ui/whats_new.dart); Settings › About shows
/// them again.
library;

import 'package:flutter/foundation.dart';

@immutable
class ReleaseNotes {
  const ReleaseNotes(this.version, this.date, this.notes);

  /// "0.9.22", as pubspec.yaml's version has it before the "+".
  final String version;

  /// When it went out, "2026-11-19".
  final String date;
  final List<String> notes;
}

const List<ReleaseNotes> changelog = [
  ReleaseNotes('0.12.3', '2026-11-21', [
    'Chat bubbles on Android: a conversation can float on the side of your screen, like Google Messages and Messenger. Turn them on or off in Settings › Notifications.',
    'Plugins sync across your devices: turn one on, or add one from the Marketplace, and your other devices on the same Ghost account follow. Network plugins switch on and offer their sign-in; your sign-ins never leave a device. Settings › Plugins has the switch.',
    'Google Messages in a tap: the browser extension can now sign in to Google for you, in a private window of its own, and Ghost pairs with it from Google Messages\' setup. No copying from the browser\'s developer tools. You still tap Google\'s emoji on your phone.',
    'A computer paired with your phone now shows when RCS already comes through the phone, rather than asking you to set it up again.',
    'Test your microphone and speaker in Settings › Voice and video: a live level bar, and Hear yourself through the speaker you chose.',
    'In a call, each face shows when someone is still connecting, reconnecting, on a slow connection, or can\'t connect.',
    'Reply to a message in circle and space chats: press and hold it, then Reply.',
    'After signing up, your 12 recovery words can wait: choose Later, and a reminder stays in your conversations until you see them.',
  ]),
  ReleaseNotes('0.12.2', '2026-11-21', [
    'Messenger, Instagram and LinkedIn: sign in once, on every device. A new browser extension captures your sign-in for each from a browser you\'re already signed in to and syncs it, sealed, to your Ghost account; your other devices then sign in on their own, so you no longer copy a login onto each one. The relay only ever holds it sealed and cannot read it.',
    'Calls: turning your video off no longer leaves your last frame frozen in your tile on the other side.',
    'Calls: the lines over a call — the recording\'s, a plugin\'s — can be dragged out of the way and folded down to a chip.',
    'Files: a large upload no longer makes the app stutter during a call.',
    'Windows: you can pick files again — a plugin to load, and files and pictures anywhere the app asks for one.',
    'The Archive ring counts only unread archived conversations now, so reading them clears it.',
    'Signal: the code you share to another screen shows properly, or says why it can\'t, instead of a blank bar.',
  ]),
  ReleaseNotes('0.12.1', '2026-11-21', [
    'Record call: open a saved recording in the mixer. In Recordings, tap one and choose Open in the mixer: every voice is a track with its waveform, meter, mute, solo and fader, as during the call. Play it to hear the mix as you set it, tap the tracks to jump around, and Save mix to keep it as a new recording beside the first.',
    'Souls: when you\'re given souls or a badge, you\'re told why ("Bug bounty", say). Straight away if the app is open; if it isn\'t, a card shows what you were given and why the next time you open it.',
  ]),
  ReleaseNotes('0.12.0', '2026-11-21', [
    'Videos from Files spaces can go full screen on your phone too: press the full-screen button and the bars hide and the phone turns to fit the video (upright for a tall one). Back, or the button again, leaves full screen.',
  ]),
  ReleaseNotes('0.11.7', '2026-11-21', [
    'Record call: everyone\'s voice is recorded again, not just yours. Since calls can start through the relay and then reconnect, a person\'s sound could move to a new connection part way, and the recording kept listening to the old one.',
  ]),
  ReleaseNotes('0.11.6', '2026-11-21', [
    'Files spaces: files over 4 GB show in the space again. A big film or backup could finish uploading and still not appear in the list.',
    'Calls: video now shows on both ends. Until now each side saw only their own camera, never the other person\'s. Calls also connect through Ghost\'s relay first, which gets through almost any network, and only try a direct path if the relay can\'t be reached; a call that hasn\'t connected after 15 seconds tries the other way by itself.',
    'Windows: the microphone you pick in a call or in Settings › Voice and video is the one used. Windows used the first microphone it found, whatever you chose.',
    'Windows: calls no longer turn your other sounds down (music, videos, games). If you liked that, switch on Lower other sounds in calls in Settings › Voice and video.',
  ]),
  ReleaseNotes('0.11.5', '2026-11-21', [
    'Files spaces: an upload that stopped part way and can\'t carry on now shows at the top of the space as Unfinished upload, with how much got there and who started it. It held the space\'s room without a word before; now whoever started it or the space\'s owner can remove it to free that room. An upload that does carry on after the app opens again shows how far it had got, and says it is checking the file before going on rather than looking stopped.',
    'Voice changer in calls is instant now: your voice is changed on your own device as you speak, with no delay and nothing sent anywhere. Pick Feminine, Masculine, Deeper, Higher, Child, Older, Monster, Chipmunk, Robot or Radio in the plugin\'s settings: each moves your pitch and the size of your voice separately, so it sounds like a real person of that kind rather than a sped-up recording. ElevenLabs is still there under How calls are changed, for a realistic voice a second or two behind.',
    'Windows: Record call, Live captions and Scribe now work on Windows. Captions and Scribe need Windows\' speech recognition for your language (Settings › Time & language › Speech).',
  ]),
  ReleaseNotes('0.11.4', '2026-11-21', [
    'Calls: when you and someone else can\'t reach each other directly, on a mobile network or a strict workplace, school or hotel network, the call now goes through Ghost\'s relay by itself instead of never connecting. It stays encrypted between you: the relay can\'t hear or see it.',
    'Files spaces: "Getting it ready" is far quicker for a big file, and shows a percentage. Checking a 26 GB file took over twenty minutes; it now takes seconds on a Mac or iPhone and about four minutes on Android and Windows. Checking a download is quicker the same way.',
  ]),
  ReleaseNotes('0.11.3', '2026-11-21', [
    'LinkedIn is no longer a network here: LinkedIn kept signing people out of their own browsers when Ghost used the sign-in. It is gone from the Marketplace and from Settings › Connections, and its saved sign-in and chats are deleted from this device the next time the app starts.',
  ]),
  ReleaseNotes('0.11.2', '2026-11-21', [
    'Networks: one you added (Instagram, LinkedIn and the others) no longer shows as removed after the app starts again while another network is slow to start. Each network now starts on its own.',
  ]),
  ReleaseNotes('0.11.1', '2026-11-20', [
    'Voice changer, live in calls: turn on "Change my voice in calls, live" and everyone in a space\'s call hears you in the voice you chose, a second or two behind as each phrase is changed by ElevenLabs. Your own voice is never heard while it\'s on, nothing is sent while you\'re muted, and a line over the call shows whose voice you have, with a way back to your own.',
    'Record call: the recording no longer floats over the app as a pill. Your red recording line over the call has a Mixer button beside Stop, which opens the tracks, meters and faders full screen.',
  ]),
  ReleaseNotes('0.11.0', '2026-11-20', [
    'Marketplace: WhatsApp, Matrix, Microsoft Teams, Google Chat, Messenger, Instagram and LinkedIn are listed as plugins, on a Networks shelf. Add one and it is switched on in Settings › Connections too, ready to sign in to; remove it and it is signed out.',
  ]),
  ReleaseNotes('0.10.8', '2026-11-20', [
    'Auto leveler: a new plugin that brings everyone in a call to about the same loudness on your device. Quiet voices come up and loud ones come down, a few seconds after each person starts talking, never more than about 9 dB either way. Nothing is sent and nobody else hears a difference. Add it from the Marketplace, or turn it on for a whole circle; press and hold someone in a call to see what it is doing to them.',
    'Soundboard: a new plugin that puts pads in a call. Press one and everyone in the call hears it: an air horn, applause, a sad trombone and nine more. A circle\'s owner and admins can add sounds of the circle\'s own. Add it from the Marketplace, or turn it on for a whole circle in its Settings › Plugins; you choose how loud it is for you, or to hear none of it.',
    'Voice changer: a new plugin that sends your voice messages in another voice, keeping how you said them: your timing, your tone, a laugh or a whisper. It uses your own ElevenLabs account, so each recording goes to ElevenLabs to be changed; if one can\'t be changed it isn\'t sent. In spaces and in chats on other networks, on an Android phone. Add it from the Marketplace, then paste your key and choose a voice in Settings › Voice changer.',
    'Recording a call: the recording\'s pill, with its tracks, meters and mixer, now shows over the call itself (the call\'s page was covering it), and the red line over the call counts the time.',
  ]),
  ReleaseNotes('0.10.7', '2026-11-20', [
    'Connections: Telegram and Signal are Ghost\'s official networks, there and ready to sign in to. The others — WhatsApp, Matrix, Microsoft Teams, Google Chat, Messenger, Instagram and LinkedIn — are now plugins under Connections › Plugins: off until you switch one on, and not run until then. Anything you\'d already connected stays on. Your texts, through Google Messages, are unchanged.',
  ]),
  ReleaseNotes('0.10.6', '2026-11-20', [
    'Spaces and circles: react to messages. Press and hold a message (or right-click on a computer) and pick an emoji; tap a reaction in a circle to add yours or take it off. Everyone can react in read-only spaces.',
    'Circles: a welcome message for new members and a welcome space they land in, read-only spaces where only the owner and admins post, and a system space that shows who joined, was kicked or banned, or became an admin. Set them in a circle\'s Settings › Welcome.',
    'Messenger, Instagram and LinkedIn: your chats on each, among your messages, on a Mac and an Android phone. Connect one in Settings › Connections. None of the three supports other apps, so each asks you to read a warning first; you sign in with the session of a browser signed in to your account.',
    'Faster and smoother everywhere, most of all on Linux: the chat list, long conversations and pictures do far less work, saving chats no longer pauses the screen, changing a setting no longer redraws the whole app, and the call banner no longer keeps the window drawing after a call has ended.',
  ]),
  ReleaseNotes('0.10.5', '2026-11-20', [
    'Game activity: a new plugin that shows friends and the spaces you\'re in which game you\'re playing on your Mac or Windows computer, and for how long. Add it from the Marketplace; it\'s off until you do, and you choose who is told.',
    'Recording a call: every track has a real meter now, with its peaks, its average and a lamp that lights if a voice clips.',
    'Recording a call: a mixer. Press Mixer in the recording to set how loud each voice is in the mix, or mute or solo one, while it records. Each person\'s own track stays as it was recorded.',
    'Recording a call: mark a moment with the flag, and find it again in Recordings.',
    'Signing up is a username and a password. The recovery words\' check can be skipped and done later.',
    'On an Android phone the walkthrough is the texts step, then your username and password.',
    'Circles: owners and admins can kick someone, or ban them so an invite won\'t let them back.',
    'Schedule a message: press and hold Send, or right-click it, to choose when it goes.',
    'Calls: push to talk, and keyboard commands you can set in Settings › Keyboard shortcuts.',
    'On a computer, photos and videos that weren\'t coming through now do, and you can paste a picture into any message field on a Mac.',
  ]),
  ReleaseNotes('0.10.4', '2026-11-20', [
    'Marketplace: plugins have a place of their own now, a storefront on the rail and the dock between Archive and Settings. Settings no longer lists them, and searching Settings for a plugin opens it there.',
    'Plugins from other developers: browse, add and remove reviewed plugins in the Marketplace. Each one says what it can do before you add it, and it only ever sees texts from numbers not in your contacts, on this device.',
    'Make your own: Marketplace › Submit a plugin sends a plugin you\'ve made for review, with its icon, description and tags, and My submissions shows where each one stands.',
    'Developer mode: Settings › Developer › Plugins in development loads a plugin you\'re making from a file, a link or the clipboard, to try it before you submit it.',
    'Report a plugin from its page if something\'s wrong with it.',
    'Profile pictures are sharp: a picture you choose is kept 256 pixels across, not 72. Choose yours again to send friends the sharp one.',
    'Messages: the filter\'s menu stays on the screen on a small phone or in a short window, opening where there\'s room and scrolling its list.',
  ]),
  ReleaseNotes('0.10.3', '2026-11-20', [
    'Messages: Mark all read, Share feedback and the Messages and Codes toggle scroll away with your conversations, so the search stays at the top and the list has more room.',
    'Messages: Clean up is one of those rows now, not a button over the search, so the bar above the search is gone.',
  ]),
  ReleaseNotes('0.10.2', '2026-11-20', [
    'Texts are optional on a phone: Skip this step in the walkthrough, and Ghost works with friends, circles, Telegram and Signal. Turn texts on any time in Settings › Texts.',
    'Circles: a circle\'s picture fills its round in the rail, with only the halo round the open one.',
    'Messages: Mark all read\'s count is a small circle.',
    'Sign up with Discord opens your browser on a computer or an iPhone.',
    'On a Mac or Windows, sign up and sign in are in a small window of their own, as Discord\'s is.',
    'On a Mac or Windows the app keeps your settings and your username across restarts again: since 0.10.0 it forgot them each time it opened, and could send you back to sign up after signing in.',
  ]),
  ReleaseNotes('0.10.1', '2026-11-20', [
    'Circles: give a circle an invite word, so gogho.st/c/bookclub opens it in place of the long link. Set it in its Settings › Invites.',
    'Messages: edit your own messages in spaces and circles, from any of your devices. Edited ones say so.',
    'Profiles: a card like Discord\'s, with a banner in their colour, their badges in a tray and by name, and their status as a bubble.',
    'Badges: choose the one shown beside your name, in your souls. It sits level with the name now.',
    'Messages: Mark all read and Share feedback are a list of rows under the search.',
    'Recording a call: a pill you can move anywhere, opening into each voice\'s track and waveform as it records, like a video editor\'s timeline.',
  ]),
  ReleaseNotes('0.10.0', '2026-11-20', [
    'On a Mac or Windows the app opens on a small splash that checks for updates first, brings one down and restarts into it, then loads the app.',
    'Developer mode: tap Version in Settings › About twelve times to turn it on, on the phone or a computer. Settings › Developer stays hidden until then.',
    'Icons: every icon is Phosphor\'s now, in duotone, in the app and the docs.',
    'Share feedback is in the rail now, just above Settings, on a phone.',
    'Friends: a friend request that didn\'t arrive is sent again until it\'s answered.',
    'Souls: the flame is a soul\'s ghostly white-green now.',
    'Messages: no Circles tab under the rail, which shows your circles; circle invites wait at the top of Messages.',
    'Circles: the rail marks the open circle with a halo in its colour, and something unread with a dot.',
    'Circles: the back arrow sits level with the circle\'s name in its banner.',
    'Circles: less room above the circle\'s name in its banner.',
    'Circles: on a computer, the rail\'s buttons are a little smaller.',
  ]),
  ReleaseNotes('0.9.37', '2026-11-20', [
    'Souls: points with a flame beside Share feedback, a thank-you for reporting bugs. They can\'t be spent yet. Tap them to see yours and your badges.',
    'Badges: some people have a badge or two beside their name, like Bug hunter or Alpha tester.',
    'Circles: a circle\'s picture fills its round in the rail, with no edge of colour round it.',
    'Circles: names in a circle\'s chat take the colour of their highest role, and change as roles are given.',
    'Circles: the back arrow sits in the banner\'s corner, and there\'s a little room before the name\'s arrow.',
  ]),
  ReleaseNotes('0.9.36', '2026-11-20', [
    'Share feedback: report a bug, suggest a feature or tell us anything, with up to three screenshots. Include your username to be in line for bug bounties. On a Mac it\'s in the window\'s top bar, elsewhere beside the search in Messages.',
    'On a Mac the window has its own top bar in the app\'s colours, a little taller, that you drag the window by.',
    'Codes: the tab shows only where codes can come from, your texts or a linked network like Telegram.',
    'Messages: the bar over the search goes when it has nothing in it. Mark all read shows while something is unread, and the cleaner while there\'s something to clean.',
  ]),
  ReleaseNotes('0.9.35', '2026-11-20', [
    'An emoji picker of Ghost\'s own, from the smiley button in any chat: search by name, pick a skin tone, and your recent ones come first. It stays open while you pick a few.',
    'Contacts: Blocked is a button beside Add, not a row of its own.',
  ]),
  ReleaseNotes('0.9.34', '2026-11-19', [
    'Help and docs: step-by-step guides for everything at gogho.st/docs, from Settings › About, and a ? on Pair a computer and Add a Discord server.',
    'Settings › Network is called Routes now, so it isn\'t mixed up with Connections (your linked accounts).',
    'Add a Discord server says what pressing a channel does now: you join it from Ghost, sound and chat both ways.',
  ]),
  ReleaseNotes('0.9.33', '2026-11-19', [
    'Verified numbers: a badge beside the names of people who verified their phone number, in spaces, circles and profiles.',
    'Slow mode: in a circle\'s space settings, let each person write only once in so many seconds. Those who manage spaces don\'t wait.',
    'Recording a call shows as cards in the chat, with icons: who started it, and when it stops, how long it ran, how many voices are in it and where it was saved.',
    'Contacts: tapping a friend you added by username opens your chat with them again.',
  ]),
  ReleaseNotes('0.9.32', '2026-11-19', [
    'Polls in spaces and circles: ask one from the +, with two to ten answers. Tap an answer to vote, tap again to take it back.',
    'A circle\'s back arrow stays inside its banner when you point at it or press it.',
  ]),
  ReleaseNotes('0.9.31', '2026-11-19', [
    'On a computer, Emoji in a space\'s or circle\'s chat opens your computer\'s emoji panel.',
    'A circle\'s name, picture and back arrow sit inside its banner picture, clear of its rounded edges.',
    'Sign up with Discord, Telegram or Signal: your username, name, picture and status are filled in from that account, and it\'s connected to Ghost as you go. Change anything before you continue.',
    'Scrolling down a circle\'s spaces shrinks its banner to just the name and picture as you go, and it grows back at the top.',
  ]),
  ReleaseNotes('0.9.30', '2026-11-19', [
    'Mac download: Ghost Messaging for the Mac is a disk image now, signed and checked by Apple. Open it and drag the app to Applications; it opens on any Mac without a warning.',
    'Friends show once each in Contacts and when you choose people to invite, not twice.',
    'A circle\'s banner starts below your phone\'s clock and battery, not behind them.',
    'A profile\'s message box lines up with the choices under it.',
  ]),
  ReleaseNotes('0.9.29', '2026-11-19', [
    'Profile pictures show by people\'s messages in spaces and circles, and in a space\'s members list.',
    'On a computer, Enter sends in a space\'s or circle\'s chat; Shift+Enter starts a new line.',
    'A circle\'s banner sits a little in from the edges, with rounded corners.',
    'Mentions: an @name\'s highlight sits evenly round its letters.',
  ]),
  ReleaseNotes('0.9.28', '2026-11-19', [
    'Windows: the app and its installer are signed under Matt Wisniewski\'s name, so Windows no longer warns about an unknown publisher when you download or install it.',
  ]),
  ReleaseNotes('0.9.27', '2026-11-19', [
    'When someone new joins a circle you\'re in, you\'re told: a notification on your phone, or a note in the app with a way to the circle. Turn it off in Settings › Notifications › Joins in circles.',
    'A circle\'s invite link works for people without the app: its page offers the right download, and once the app is set up it opens the circle for you. With the app already there, Open in Ghost Messaging opens it, on a computer too.',
  ]),
  ReleaseNotes('0.9.26', '2026-11-19', [
    'The Messages, Codes and Circles tabs are all there the moment the app opens, without Circles jumping along.',
    'Your phone number is set once, with your profile in Settings › Me › Number: the separate Your number setting is gone.',
    'Record call: Record and Stop are in a space\'s header while you\'re in its call. In a circle, recordings are saved to a folder in one of its Files spaces; choose which in Circle settings › Plugins.',
    'A circle\'s banner is softly blurred and shaded behind its name, so the name reads on any picture.',
  ]),
  ReleaseNotes('0.9.25', '2026-11-19', [
    'Pictures in a space\'s or circle\'s chat, and on Telegram and Signal, open full screen over the chat: pinch or scroll to zoom, tap or press Escape to go back.',
    'SMS spaces list their members, you first: who gets the space\'s messages by text, at which number, and who reads them in the app.',
  ]),
  ReleaseNotes('0.9.24', '2026-11-19', [
    'SMS spaces: members whose phone number is linked get the space\'s messages by text by themselves, and what they text back comes into the space. Text STOP to leave.',
    'Tap someone\'s picture or name in a space, or in a members list, to open their profile. Write to a friend right from it, Send inside the box as everywhere else.',
    'Circles: the owner or an admin can remove someone from a circle. Tap them in the members list: their card has their roles to change, admin, and Remove.',
    'Your profile can show friends your number and linked accounts, if you switch it on in Settings › Me › Profile.',
    'Plugins meant for circles have their own section on the Plugins page.',
    'Circles can have a banner across the top of their sidebar: choose one in Circle settings › Overview.',
  ]),
  ReleaseNotes('0.9.23', '2026-11-19', [
    'What\'s new: after each update, a short list of what changed, like this one. Find it again in Settings › About.',
    'Profiles: set a picture and a status in Settings › Me › Profile. Tap an @ anywhere to see someone\'s card, with what you can do from there.',
    'Live captions: in a call, see what everyone says written out as they talk, translated where you have Translate. Turn them on from the call\'s menu.',
    'Watch together: play a video or song from a Files space for everyone in the call, kept in step on each device.',
  ]),
  ReleaseNotes('0.9.22', '2026-11-19', [
    'Record call: record a space\'s call to one video file with a sound track for each person, named for them. Everyone in the call is asked, and only those who say yes are recorded. Add it in Plugins, or turn it on for a whole circle.',
    'Scribe: a recorded call written out on your device, each line with who said it and when, with a summary where your phone can make one.',
    'SMS spaces: a circle\'s texting space that friends without the app join by text, from one member\'s phone.',
    'Circle plugins: whoever can change a circle can turn a plugin on for everyone in it, in Circle settings › Plugins.',
    'A picture or voice message you send always shows what it is, not just "Delivered".',
  ]),
  ReleaseNotes('0.9.21', '2026-11-19', [
    'Names no longer start with "@". Someone without a display name now goes by their username, the same as everyone else\'s name.',
  ]),
  ReleaseNotes('0.9.20', '2026-11-19', [
    'Mentions: type @ in a space or a circle to mention someone. They get a notification, and messages that mention you stand out.',
    'Unread marks show @ when something unread mentions you.',
    'The Codes tab is always there, even before your first code.',
    'Contacts lists friends by username and by number together, under On Ghost Messaging.',
  ]),
];

/// Whether [a] is a later version than [b] ("0.9.10" is later than "0.9.9"); anything unreadable is earliest.
bool laterVersion(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? -1];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

/// The entries after [seen] up to and including [current], newest first, [most] at the most.
List<ReleaseNotes> notesSince(String seen, String current, {List<ReleaseNotes> from = changelog, int most = 5}) => [
      for (final r in from)
        if (laterVersion(r.version, seen) && !laterVersion(r.version, current)) r,
    ].take(most).toList();
