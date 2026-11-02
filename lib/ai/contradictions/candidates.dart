/// Which pairs of notes are worth asking the AI about, found cheaply on the device with no AI (docs/CONTRADICTIONS.md,
/// "Candidates"; Matt, 2026-11-02: "spots when a newer note disagrees with an older one (e.g. 'release is Thursday' in
/// one, 'release moved to Monday' in a later meeting)").
///
/// Each note is read for its keys ([noteKeys]): `[[links]]`, `#tags` and `@people`, the words of its title, dates and
/// weekdays, and numbers that carry a unit or a sign. Two notes of the same scope are a pair when they share enough of
/// them ([pairScore]): a link between them, or a shared link, person or tag, counts 2; a shared title word or date 1;
/// a pair needs [pairNeeds], and a fact (a date, a weekday or a number) in each, since a contradiction is nearly always
/// about when, how much or who. Each note goes to the AI as an excerpt ([excerptOf]): the lines that hold a key or a
/// fact, numbered, at most [excerptChars].
///
/// Scopes never meet: a pair is two notes of one [ContradictionScope] (findings.dart), so a team's notes are compared
/// with the same team's only and never with the person's own.
library;

import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import 'findings.dart';

/// What a pair must score to be asked about.
const int pairNeeds = 3;

/// The most of a note's words that go to the AI.
const int excerptChars = 1200;

/// The most pairs one run asks about.
const int pairsPerRun = 60;

const Set<String> _stop = {
  'a', 'an', 'and', 'the', 'of', 'to', 'in', 'on', 'for', 'with', 'at', 'by', 'from', 'is', 'are', 'was', 'be', 'it',
  'this', 'that', 'my', 'our', 'we', 'i', 'you', 'notes', 'note', 'meeting', 'untitled', 'new', 'about', 'or', 'vs',
};

const List<String> _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const List<String> _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

final RegExp _link = RegExp(r'\[\[([^\]|#\n]+)(?:[#|][^\]\n]*)?\]\]');
final RegExp _tag = RegExp(r'(?:^|\s)#([A-Za-z][\w/-]{1,40})');
final RegExp _person = RegExp(r'(?:^|[\s(])@([A-Za-z][\w.-]{1,40})');
final RegExp _isoDate = RegExp(r'\b(20\d\d)-(\d\d)-(\d\d)\b');
final RegExp _monthDay = RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b', caseSensitive: false);
final RegExp _dayMonth = RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b', caseSensitive: false);
final RegExp _weekday = RegExp(r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b', caseSensitive: false);
final RegExp _number = RegExp(r'(?:[$€£]\s?\d[\d,.]*\s?[kmb]?\b|\b\d[\d,.]*\s?(?:%|k\b|m\b|bn\b|ms\b|gb\b|mb\b|days?\b|weeks?\b|months?\b|hours?\b|people\b|users?\b|seats?\b)|\bv\d+(?:\.\d+)+\b)', caseSensitive: false);
final RegExp _word = RegExp(r"[a-z0-9][a-z0-9'-]*");

/// One note's keys (see the header).
class NoteKeys {
  const NoteKeys({required this.links, required this.tags, required this.people, required this.titleWords, required this.dates, required this.facts});

  /// `[[links]]`' targets, `#tags`, `@people`, each in lower case.
  final Set<String> links, tags, people;

  /// The title's own words, less the small ones.
  final Set<String> titleWords;

  /// Dates as `2026-11-12` or `nov 12`, and weekdays.
  final Set<String> dates;

  /// Dates, weekdays and numbers with a unit: what a disagreement is about.
  final Set<String> facts;
}

/// Whether [line] holds a fact (a date, a weekday, a number with a unit).
bool hasFact(String line) => _isoDate.hasMatch(line) || _monthDay.hasMatch(line) || _dayMonth.hasMatch(line) || _weekday.hasMatch(line) || _number.hasMatch(line);

Set<String> _factsIn(String text) => {
      for (final m in _isoDate.allMatches(text)) m.group(0)!,
      for (final m in _monthDay.allMatches(text)) '${m.group(1)!.toLowerCase().substring(0, 3)} ${int.parse(m.group(2)!)}',
      for (final m in _dayMonth.allMatches(text)) '${m.group(2)!.toLowerCase().substring(0, 3)} ${int.parse(m.group(1)!)}',
      for (final m in _weekday.allMatches(text)) m.group(1)!.toLowerCase(),
      for (final m in _number.allMatches(text)) m.group(0)!.toLowerCase().replaceAll(RegExp(r'\s+'), ''),
    };

/// [body]'s keys.
NoteKeys noteKeys(String body) {
  final title = noteTitle(body).toLowerCase();
  final facts = _factsIn(body);
  return NoteKeys(
    links: {for (final m in _link.allMatches(body)) m.group(1)!.trim().toLowerCase()},
    tags: {for (final m in _tag.allMatches(body)) m.group(1)!.toLowerCase()},
    people: {for (final m in _person.allMatches(body)) m.group(1)!.toLowerCase()},
    titleWords: {
      for (final m in _word.allMatches(title))
        if (!_stop.contains(m.group(0)) && m.group(0)!.length > 2 && !_weekdays.contains(m.group(0)) && !_months.contains(m.group(0)) && int.tryParse(m.group(0)!) == null) m.group(0)!,
    },
    dates: {for (final f in facts) if (_isoDate.hasMatch(f) || _weekdays.contains(f) || RegExp(r'^[a-z]{3} \d+$').hasMatch(f)) f},
    facts: facts,
  );
}

/// One pair to ask about: [older] edited before [newer].
class CandidatePair {
  const CandidatePair({required this.older, required this.newer, required this.score, required this.shared});
  final Note older, newer;
  final int score;

  /// The keys they share, for the excerpts: the lines that hold one go first.
  final Set<String> shared;

  /// The key the file's `checked` keeps it under.
  String get checkKey => '${older.id}|${newer.id}';

  /// The revisions it is asked at.
  String get revisions => '${older.revision}:${newer.revision}';
}

/// How much [a] and [b] share (see the header), and what.
(int, Set<String>) pairScore(Note a, NoteKeys ka, Note b, NoteKeys kb) {
  var score = 0;
  final shared = <String>{};
  final ta = noteTitle(a.body).trim().toLowerCase(), tb = noteTitle(b.body).trim().toLowerCase();
  if ((ta.isNotEmpty && kb.links.contains(ta)) || (tb.isNotEmpty && ka.links.contains(tb))) score += 2;
  for (final (mine, theirs, weight) in [(ka.links, kb.links, 2), (ka.tags, kb.tags, 2), (ka.people, kb.people, 2), (ka.titleWords, kb.titleWords, 1), (ka.dates, kb.dates, 1)]) {
    for (final key in mine.intersection(theirs)) {
      score += weight;
      shared.add(key);
    }
  }
  // One note's title spoken of in the other's words ("Release plan", and "release moved to Monday" in a standup): 1
  // each way, at most.
  for (final (keys, other) in [(ka, b.body.toLowerCase()), (kb, a.body.toLowerCase())]) {
    final spoken = keys.titleWords.where((w) => !shared.contains(w) && RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(other)).firstOrNull;
    if (spoken == null) continue;
    score += 1;
    shared.add(spoken);
  }
  return (score, shared);
}

/// The pairs worth asking about among [notes] (see the header): notes of one scope each, neither archived nor in the
/// trash, ranked by score and then by how new the newer note is, at most [limit]. A pair [checked] at the revisions
/// the two have now is left out. With [touching], only pairs with one of those notes in them (When a note is saved).
List<CandidatePair> candidatePairs(Iterable<Note> notes, {bool byFolder = false, Map<String, String> checked = const {}, Set<String>? touching, int limit = pairsPerRun, bool Function(ContradictionScope scope)? allowed}) {
  final byScope = <ContradictionScope, List<(Note, NoteKeys)>>{};
  for (final note in notes) {
    if (note.archivedAt != null || note.inTrash || note.body.trim().isEmpty) continue;
    final scope = scopeOfPath(note.path, byFolder: byFolder);
    if (allowed != null && !allowed(scope)) continue;
    final keys = noteKeys(note.body);
    if (keys.facts.isEmpty) continue;
    byScope.putIfAbsent(scope, () => []).add((note, keys));
  }
  final pairs = <CandidatePair>[];
  for (final group in byScope.values) {
    for (var i = 0; i < group.length; i += 1) {
      for (var j = i + 1; j < group.length; j += 1) {
        final (a, ka) = group[i];
        final (b, kb) = group[j];
        if (a.updatedAt == b.updatedAt) continue;
        if (touching != null && !touching.contains(a.id) && !touching.contains(b.id)) continue;
        final (score, shared) = pairScore(a, ka, b, kb);
        if (score < pairNeeds) continue;
        final (older, newer) = a.updatedAt < b.updatedAt ? (a, b) : (b, a);
        final pair = CandidatePair(older: older, newer: newer, score: score, shared: shared);
        if (checked[pair.checkKey] == pair.revisions) continue;
        pairs.add(pair);
      }
    }
  }
  pairs.sort((x, y) => x.score != y.score ? y.score.compareTo(x.score) : y.newer.updatedAt.compareTo(x.newer.updatedAt));
  return pairs.length > limit ? pairs.sublist(0, limit) : pairs;
}

/// [note]'s words as the AI is shown them: its title, then the lines that hold one of [shared] or a fact, each with its
/// 1-based line number, until [excerptChars]. Front matter is never sent.
String excerptOf(Note note, Set<String> shared) {
  final lines = note.body.split('\n');
  var start = 0;
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    final end = lines.indexWhere((l) => l.trim() == '---', 1);
    if (end > 0) start = end + 1;
  }
  final out = StringBuffer('Title: ${noteTitle(note.body)}\n');
  for (var i = start; i < lines.length; i += 1) {
    final text = lines[i].trim();
    if (text.isEmpty || text.startsWith('# ')) continue;
    final lower = text.toLowerCase();
    if (!hasFact(text) && !shared.any(lower.contains)) continue;
    final row = '${i + 1}: $text\n';
    if (out.length + row.length > excerptChars) break;
    out.write(row);
  }
  return out.toString().trimRight();
}
