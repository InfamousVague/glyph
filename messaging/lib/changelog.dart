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
  ReleaseNotes('0.10.2', '2026-11-20', [
    'Texts are optional on a phone: Skip this step in the walkthrough, and Ghost works with friends, circles, Telegram and Signal. Turn texts on any time in Settings › Texts.',
    'Circles: a circle\'s picture fills its round in the rail, with only the halo round the open one.',
    'Messages: Mark all read\'s count is a small circle.',
    'Sign up with Discord opens your browser on a computer or an iPhone.',
    'On a Mac or Windows, signing up or in happens in a small window of its own, as Discord\'s does.',
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
