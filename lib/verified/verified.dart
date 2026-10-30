/// A verified page: a note a member vouches for as the team's current truth, until a day (Matt, 2026-10-30: "add all
/// 12", the plain-Markdown list's verified pages, for the Docs folder). Front matter, as YAML writes a map on one
/// line:
///
///     ---
///     verified: {by: "@matt", until: 2026-12-01, words: 3f9a12c07b4e5d61}
///     ---
///
/// `by` is who vouches for it (the owner, whose bell is told when it runs out), `until` the last day it holds, and
/// `words` a fingerprint of the note's words below the front matter as they were when it was verified, so an edit
/// since is seen without the page saying "unverified": the badge stays, with "edited since verified" beside it,
/// until someone verifies it again. The handle is quoted because YAML keeps `@` for itself; a hand-written `{by:
/// @matt, until: 2026-12-01}`, and the plainer `verified: @matt until 2026-12-01`, are read too, and so is one with
/// no `words` (never edited since, as far as anything can say). Another app reads it as a map of three words.
///
/// What it is, on a day ([verifiedStanding]):
/// - **fresh**: green, "Verified by Matt · until Dec 1";
/// - **soon**: amber, the same words, within [soonDays] of its last day;
/// - **expired**: grey, "Needs review", from the day after its last.
///
/// Pure, so every shape is a test (test/verified/verified_test.dart). The badge is verified_badge.dart; the bell's
/// row when one runs out is [expiredNotices].
library;

import '../core/days.dart' show isIsoDay, isoDay, isoDayAfter;
import '../core/front_matter.dart' show frontMatterOffset, frontMatterValue;
import '../core/properties.dart' show withFrontMatterValue;
import '../format/body_hash.dart' show fnvOffsetBasis;

/// The front matter key.
const String verifiedKey = 'verified';

/// The days before its last that a page's badge turns amber.
const int soonDays = 7;

/// The periods Verify… offers, in days.
const List<int> verifyPeriods = [30, 90, 180];

/// What a page's front matter says of who vouches for it, and until when.
class Verified {
  const Verified({required this.by, required this.until, this.words});

  /// The handle, without its at sign.
  final String by;

  /// `2026-12-01`, the last day it holds.
  final String until;

  /// The fingerprint of the note's words when it was verified ([wordsMark]); null where none was written.
  final String? words;

  @override
  bool operator ==(Object other) => other is Verified && other.by == by && other.until == until && other.words == words;

  @override
  int get hashCode => Object.hash(by, until, words);

  @override
  String toString() => 'Verified(@$by until $until${words == null ? '' : ', $words'})';
}

final RegExp _flowPair = RegExp(r'''([\w-]+)\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^,}]*)''');
final RegExp _plain = RegExp(r'^@?([\p{L}][\p{L}\p{N}_.-]*)\s+until\s+(\d{4}-\d{2}-\d{2})$', unicode: true);
final RegExp _quotes = RegExp(r'''^(["'])(.*)\1$''');

String _bare(String value) => value.trim().replaceFirstMapped(_quotes, (m) => m.group(2)!).trim();

/// What a `verified:` value says, or null where it is not one this reads: a flow map with `by` and `until`, or
/// `@handle until 2026-12-01`.
Verified? readVerified(String? value) {
  final said = (value ?? '').trim();
  if (said.isEmpty) return null;
  if (said.startsWith('{') && said.endsWith('}')) {
    final pairs = <String, String>{};
    for (final found in _flowPair.allMatches(said.substring(1, said.length - 1))) {
      pairs[found.group(1)!.toLowerCase()] = _bare(found.group(2)!);
    }
    final by = (pairs['by'] ?? '').replaceFirst(RegExp(r'^@+'), '').trim();
    final until = pairs['until'] ?? '';
    if (by.isEmpty || !isIsoDay(until)) return null;
    final words = pairs['words'];
    return Verified(by: by, until: until, words: words == null || words.isEmpty ? null : words);
  }
  final plain = _plain.firstMatch(_bare(said));
  if (plain == null || !isIsoDay(plain.group(2)!)) return null;
  return Verified(by: plain.group(1)!, until: plain.group(2)!);
}

/// The page's verification, or null where its front matter says none.
Verified? verifiedOf(String body) => readVerified(frontMatterValue(body, verifiedKey));

/// A fingerprint of the note's words below its front matter: FNV-1a over them, 64 bits as 16 hex digits. The front
/// matter is left out, so writing the verification itself, a tag or a title changed there, is not an edit to what
/// the page says.
String wordsMark(String body) {
  final words = body.substring(frontMatterOffset(body)).trimRight();
  var hash = fnvOffsetBasis;
  for (final unit in words.codeUnits) {
    hash ^= unit;
    hash *= 0x100000001b3;
  }
  String half(int bits) => (bits & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(hash >> 32)}${half(hash)}';
}

/// The value front matter writes for [verified].
String verifiedValue(Verified verified) => '{by: "@${verified.by}", until: ${verified.until}${verified.words == null ? '' : ', words: ${verified.words}'}}';

/// [body] verified by [by] for [days] from [today], its words' fingerprint taken now; or, with a null [by], its
/// verification taken off.
String withVerified(String body, {required String? by, int days = 90, DateTime? today}) {
  if (by == null) return withFrontMatterValue(body, verifiedKey, null);
  final until = isoDayAfter(isoDay(today ?? DateTime.now()), days)!;
  return withFrontMatterValue(body, verifiedKey, verifiedValue(Verified(by: by, until: until, words: wordsMark(body))));
}

/// Where a page stands on a day.
enum VerifiedStanding { fresh, soon, expired }

/// How [verified] stands on [today]: expired from the day after its last, soon within [soonDays] of it.
VerifiedStanding verifiedStanding(Verified verified, DateTime today) {
  final day = isoDay(today);
  if (verified.until.compareTo(day) < 0) return VerifiedStanding.expired;
  final soon = isoDayAfter(day, soonDays)!;
  return verified.until.compareTo(soon) <= 0 ? VerifiedStanding.soon : VerifiedStanding.fresh;
}

/// Whether the page's words have changed since it was verified: only where a fingerprint was written.
bool editedSinceVerified(Verified verified, String body) => verified.words != null && verified.words != wordsMark(body);

/// A handle as the badge names its owner: "Matt" for `matt`, "Sam Ortiz" for `sam-ortiz`.
String ownerShown(String handle) {
  final words = handle.replaceAll(RegExp(r'[-_.]+'), ' ').trim().split(' ').where((word) => word.isNotEmpty);
  return words.map((word) => '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A day as the badge says it: "Dec 1", with its year where it is not [today]'s ("Jan 4, 2027").
String untilShown(String iso, DateTime today) {
  final parts = iso.split('-');
  final year = int.parse(parts[0]), month = int.parse(parts[1]), date = int.parse(parts[2]);
  final shown = '${_months[month - 1]} $date';
  return year == today.year ? shown : '$shown, $year';
}

/// What the badge says, and what a screen reader hears: "Verified by Matt · until Dec 1", or "Needs review".
String verifiedWords(Verified verified, DateTime today) {
  if (verifiedStanding(verified, today) == VerifiedStanding.expired) return 'Needs review';
  return 'Verified by ${ownerShown(verified.by)} · until ${untilShown(verified.until, today)}';
}

/// What a query's `verified` field says of a page (lib/core/query/values.dart): `yes` and `fresh` or `soon` while it
/// holds, `expired` and `no` once it has run out; nothing for a page that is not verified, so `verified` alone is
/// every verified page and `verified = expired` the ones that want looking at.
List<String> verifiedQueryWords(String? value, String today) {
  final verified = readVerified(value);
  if (verified == null) return const [];
  final day = DateTime.tryParse(today) ?? DateTime.now();
  return switch (verifiedStanding(verified, day)) {
    VerifiedStanding.fresh => const ['yes', 'fresh'],
    VerifiedStanding.soon => const ['yes', 'soon'],
    VerifiedStanding.expired => const ['expired', 'no'],
  };
}

/// One page whose verification ran out, owed its row in its owner's bell.
class ExpiredPage {
  const ExpiredPage({required this.noteId, required this.title, required this.until, required this.id});
  final String noteId;
  final String title;
  final String until;

  /// The row's id: the same for the same page and the same last day on every device, so the bell has one.
  final String id;

  @override
  String toString() => 'ExpiredPage($noteId until $until)';
}

/// The pages among [notes] that [me] vouches for whose time has run out on [today], each once: those whose id
/// [told] already has are passed over. A page verified again has a new last day, and so a new id.
List<ExpiredPage> expiredNotices(Iterable<({String id, String body, String title})> notes, {required String me, required DateTime today, required bool Function(String id) told}) {
  final out = <ExpiredPage>[];
  final mine = me.toLowerCase();
  for (final note in notes) {
    if (!note.body.startsWith('---') && !note.body.startsWith('+++')) continue;
    final verified = verifiedOf(note.body);
    if (verified == null || verified.by.toLowerCase() != mine) continue;
    if (verifiedStanding(verified, today) != VerifiedStanding.expired) continue;
    final id = 'x${wordsMark('${note.id}\u0000${verified.until}')}';
    if (told(id)) continue;
    out.add(ExpiredPage(noteId: note.id, title: note.title, until: verified.until, id: id));
  }
  return out;
}
