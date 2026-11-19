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
