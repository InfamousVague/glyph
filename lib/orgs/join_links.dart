/// Invite links on this side (docs/TEAMS.md, "Invite by link"; server/src/store/org_links.rs). A port of
/// `src/app/core/orgs/joinLinks.ts`.
///
/// A link is the reader page with the code in its hash, `https://ghostmarkdown.com/read.html#join=<code>`, as a share
/// link is the reader page with its key (lib/share/share.dart): the hash never reaches a server's logs, and the page
/// is there for anyone, with the app or without. It offers the two ways in - `ghostmd://join/<code>`, which the
/// phone hands to the app, and the web app at `#join=<code>` - and the app asks "Join it?" with the organization's
/// name before anything is joined.
///
/// Signed out, the code is held on this device until an account is signed in, and asked about then: a link followed
/// by someone who has not signed up yet is the commonest way in. Pure apart from the held code.
///
/// What differs: the held code is kept in a [Stored] the caller may give (the app's own otherwise), and the time is
/// a parameter with the clock as its default, as on the page.
library;

import '../core/stored.dart';
import '../share/share.dart' show readerUrl;
import 'types.dart';

/// A code as the service makes one: 22 base64url characters, taken at 16 to 64 as the route does.
final RegExp _code = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// The link that is copied and sent: the reader page, with the code where only the browser reads it (`inviteUrl`).
String inviteUrl(String code) => '$readerUrl#join=$code';

/// The link that opens the app itself, from the reader page's "Open in the Ghost.md app" (`appJoinLink`).
String appJoinLink(String code) => 'ghostmd://join/$code';

final RegExp _appLink = RegExp(r'^ghostmd://join/([^/?#\s]+)/?$');
final RegExp _hashLink = RegExp(r'#join=([^&\s]+)$');

/// The code an invite link carries, from any of the shapes one arrives in: the link as sent, the web app's
/// `#join=<code>`, the app's `ghostmd://join/<code>`, or the code alone, pasted. Null for anything else
/// (`readJoinLink`).
String? readJoinLink(String text) {
  final trimmed = text.trim();
  if (_code.hasMatch(trimmed)) return trimmed;
  final app = _appLink.firstMatch(trimmed)?.group(1);
  if (app != null && app.isNotEmpty) return _code.hasMatch(app) ? app : null;
  final hash = _hashLink.firstMatch(trimmed)?.group(1);
  return hash != null && _code.hasMatch(hash) ? hash : null;
}

/// A link's name on its row: the end of its code, enough to tell two apart, where the whole link would be cut off
/// (`linkName`).
String linkName(String code) => 'Link ending ${code.length > 5 ? code.substring(code.length - 5) : code}';

// --- how long, and how many ------------------------------------------------------------------------------------------

const int _hour = 3600;
const int _day = 24 * _hour;

/// How long a new link lasts: the choices offered, seconds, and null for until it is turned off (`LIFETIMES`).
const List<({String value, String label, int? seconds})> lifetimes = [
  (value: 'day', label: 'A day', seconds: _day),
  (value: 'week', label: 'A week', seconds: 7 * _day),
  (value: 'month', label: '30 days', seconds: 30 * _day),
  (value: 'never', label: 'No end', seconds: null),
];

/// How many may join by a new link: the choices offered, and null for no limit (`USES`).
const List<({String value, String label, int? uses})> uses = [
  (value: 'one', label: 'One person', uses: 1),
  (value: 'five', label: 'Five', uses: 5),
  (value: 'many', label: 'Twenty-five', uses: 25),
  (value: 'any', label: 'No limit', uses: null),
];

/// JavaScript's `Math.round`: halves go up.
int _round(double value) => (value + 0.5).floor();

/// How long is left, in the plainest words: "in 5 hours", "in 6 days".
String _within(int ms) {
  final rounded = _round(ms / (_hour * 1000));
  final hours = rounded < 1 ? 1 : rounded;
  if (hours < 48) return 'in $hours hour${hours == 1 ? '' : 's'}';
  return 'in ${_round(hours / 24)} days';
}

/// What a link's row says under it: how long it lasts and how many have used it (`linkTermsWords`).
String linkTermsWords(InviteLink link, int now) {
  final expiresAt = link.expiresAt, maxUses = link.maxUses;
  final lasts = expiresAt == null ? 'Lasts until turned off' : 'Stops ${_within(expiresAt - now)}';
  final used = maxUses == null ? (link.uses == 0 ? 'none joined yet' : '${link.uses} joined') : '${link.uses} of $maxUses used';
  return '$lasts · $used';
}

// --- a code held across signing in -----------------------------------------------------------------------------------

/// The key the held code is kept under (`HELD`).
const String heldJoinKey = 'glyph-join-held';

/// A code is held at most a week: a link followed and forgotten should not ask a month later.
const int _heldFor = 7 * _day * 1000;

({String code, int at})? _asHeld(Object? raw) {
  if (raw is! Map) return null;
  final code = raw['code'], at = raw['at'];
  return code is String && _code.hasMatch(code) && at is num ? (code: code, at: at.toInt()) : null;
}

int _clock() => DateTime.now().millisecondsSinceEpoch;

/// Keeps a code on this device until it is asked about: followed while signed out (`holdJoin`).
void holdJoin(String code, {int? now, Stored? kept}) => (kept ?? stored).write(heldJoinKey, {'code': code, 'at': now ?? _clock()});

/// The code held, if one is and it is not stale (`heldJoin`).
String? heldJoin({int? now, Stored? kept}) {
  final held = (kept ?? stored).read<({String code, int at})?>(heldJoinKey, null, _asHeld);
  return held != null && (now ?? _clock()) - held.at < _heldFor ? held.code : null;
}

/// The held code let go: joined, or the person said no (`dropHeldJoin`).
void dropHeldJoin({Stored? kept}) => (kept ?? stored).write(heldJoinKey, null);
