/// What a search finds, in the order worth reading, and where in each note it found it. The port's own, past the
/// page's rule (lib/core/search.dart, where a note either has every word or has not): Matt asked on 2026-10-11 for
/// a search that forgives a slip, puts the nearest note first and shows the words it matched.
///
/// Every word typed must still be found in the note, but a word is found in one of four ways, the nearest first:
/// written in the note's name, nearly written in its name, written in its words, nearly written in its words.
/// "Nearly" is one slip (a letter wrong, missing, added, or two swapped) in a word of four letters or more, two in
/// a word of eight or more, and the first letter right: "cluade" finds Claude, "cl" finds nothing it does not hold.
/// A word still being typed is nearly the start of a longer one, so "calud" finds Claude too.
///
/// A note found by its name stands over one found by its words, and among equals the newest first. Each found note
/// says what it matched as [Found.needles], the letters as the note has them, from which a row inks them in the
/// name ([marksIn]) and cuts the line of the note they stand in ([snippetOf]).
library;

import 'note.dart';
import 'note_facts.dart';
import 'note_text.dart';

/// A note a search found: how near ([score], more is nearer), and what it matched, a needle for each word typed, in
/// lower case as the note has it (the word itself where it is written, the note's own word where it is nearly).
class Found {
  Found(this.note, this.score, this.needles, {required this.byName});
  final Note note;
  final int score;
  final List<String> needles;

  /// Every word was found in the name: the row needs no line of the note under it.
  final bool byName;

  /// The line of the note the words stand in, read once, when a row first draws it.
  late final Snippet? snippet = byName ? null : snippetOf(note, needles);
}

/// A stretch of a note's words with what was matched in it, as ranges of [text].
class Snippet {
  const Snippet(this.text, this.marks);
  final String text;
  final List<(int, int)> marks;
}

final RegExp _letters = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// What a search reads of a note beyond its words, by its id, for the words it was read from: its name in lower
/// case, the name's different words, and the note's, which are only read for a note that does not hold a word as
/// typed.
class _Kept {
  _Kept(this.text, this.name);
  final String text;
  final String name;
  late final Map<int, List<String>> nameWords = _wordsIn(name);
  late final Map<int, List<String>> textWords = _wordsIn(text);
}

final Map<String, _Kept> _kept = <String, _Kept>{};

_Kept _keptOf(Note note) {
  final text = searchText(note);
  final had = _kept[note.id];
  if (had != null && identical(had.text, text)) return had;
  if (_kept.length >= 32768) _kept.clear();
  return _kept[note.id] = _Kept(text, NoteFacts.of(note).shownTitle.toLowerCase());
}

/// The different words of [text], three letters or more, under the letter each begins with.
Map<int, List<String>> _wordsIn(String text) {
  final seen = <String>{};
  final byFirst = <int, List<String>>{};
  for (final match in _letters.allMatches(text)) {
    final word = match[0]!;
    if (word.length < 3 || word.length > 32 || !seen.add(word)) continue;
    (byFirst[word.codeUnitAt(0)] ??= <String>[]).add(word);
  }
  return byFirst;
}

/// How many slips a word of this length is forgiven.
int _slips(int length) => length >= 8 ? 2 : (length >= 4 ? 1 : 0);

/// The slips between [a] and [b] (a letter wrong, missing, added, or two neighbours swapped), or more than [most].
int _distance(String a, String b, int most) {
  final n = a.length, m = b.length;
  if ((n - m).abs() > most) return most + 1;
  var before = List<int>.filled(m + 1, 0), row = List<int>.generate(m + 1, (j) => j), next = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i += 1) {
    next[0] = i;
    var least = i;
    for (var j = 1; j <= m; j += 1) {
      final same = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1);
      var cost = row[j - 1] + (same ? 0 : 1);
      if (row[j] + 1 < cost) cost = row[j] + 1;
      if (next[j - 1] + 1 < cost) cost = next[j - 1] + 1;
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) && before[j - 2] + 1 < cost) cost = before[j - 2] + 1;
      next[j] = cost;
      if (cost < least) least = cost;
    }
    if (least > most) return most + 1;
    final spare = before;
    before = row;
    row = next;
    next = spare;
  }
  return row[m];
}

/// The word among [tokens] that [word] nearly is, or nearly begins: the nearest, and null where none is near.
String? _near(String word, Map<int, List<String>> tokens) {
  final most = _slips(word.length);
  if (most == 0) return null;
  final list = tokens[word.codeUnitAt(0)];
  if (list == null) return null;
  final has = _lettersOf(word);
  String? best;
  var least = most + 1;
  for (final token in list) {
    if (token.length < word.length - most) continue;
    // A word short of more of these letters than the slips allowed is not near, and is not measured.
    if (_ones(has & ~_lettersOf(token)) > most) continue;
    // The whole word, or as much of a longer one as was typed (give or take a letter).
    var slips = _distance(word, token, most);
    if (slips > most && token.length > word.length) {
      for (var cut = word.length - 1; cut <= word.length + 1 && cut <= token.length && slips > most; cut += 1) {
        slips = _distance(word, token.substring(0, cut), most);
      }
    }
    if (slips < least) {
      least = slips;
      best = token;
      if (slips == 1) break;
    }
  }
  return best;
}

/// Which letters a word has, a bit each (every other sign shares one), kept for each word asked about.
final Map<String, int> _lettersHad = <String, int>{};

int _lettersOf(String word) {
  final had = _lettersHad[word];
  if (had != null) return had;
  var bits = 0;
  for (var i = 0; i < word.length; i += 1) {
    final unit = word.codeUnitAt(i);
    bits |= 1 << (unit >= 97 && unit <= 122 ? unit - 97 : 26 + (unit & 3));
  }
  if (_lettersHad.length >= 262144) _lettersHad.clear();
  return _lettersHad[word] = bits;
}

int _ones(int bits) {
  var count = 0;
  while (bits != 0) {
    bits &= bits - 1;
    count += 1;
  }
  return count;
}

bool _letter(int unit) => unit > 127 || (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 122);

/// Where [word] stands in [text] and how well: 3 at its start, 2 at the start of a word, 1 inside one, 0 not at all.
int _place(String text, String word) {
  var at = text.indexOf(word);
  if (at < 0) return 0;
  if (at == 0) return 3;
  // The first few places it stands are looked at, not every one: a letter or two stand all through a long note.
  for (var looked = 0; at >= 0 && looked < 6; looked += 1) {
    if (!_letter(text.codeUnitAt(at - 1))) return 2;
    at = text.indexOf(word, at + 1);
  }
  return 1;
}

/// Of [notes], those the query finds, the nearest first; none for a blank query.
List<Found> findNotes(Iterable<Note> notes, String query) {
  final words = queryWords(query);
  if (words.isEmpty) return const <Found>[];
  final found = <Found>[];
  for (final note in notes) {
    final kept = _keptOf(note);
    final name = kept.name, text = kept.text;
    var score = 0, byName = true;
    final needles = <String>[];
    var held = true;
    for (final word in words) {
      final inName = _place(name, word);
      if (inName > 0) {
        score += 60 + inName * 15;
        needles.add(word);
        continue;
      }
      final nearName = _slips(word.length) == 0 ? null : _near(word, kept.nameWords);
      if (nearName != null) {
        score += 50;
        needles.add(nearName);
        continue;
      }
      byName = false;
      // Asked of the note's pairs of letters first (note_text.dart): most notes without the word are not read.
      final inText = hasWords(note, [word]) ? _place(text, word) : 0;
      if (inText > 0) {
        score += inText > 1 ? 30 : 22;
        needles.add(word);
        continue;
      }
      final nearText = _slips(word.length) == 0 ? null : _near(word, kept.textWords);
      if (nearText == null) {
        held = false;
        break;
      }
      score += 10;
      needles.add(nearText);
    }
    if (held) found.add(Found(note, score + (note.starred ? 3 : 0), needles, byName: byName));
  }
  final indexed = found.indexed.toList();
  indexed.sort((a, b) {
    final by = b.$2.score.compareTo(a.$2.score);
    if (by != 0) return by;
    final when = b.$2.note.updatedAt.compareTo(a.$2.note.updatedAt);
    return when != 0 ? when : a.$1.compareTo(b.$1);
  });
  return [for (final (_, one) in indexed) one];
}

/// Where the [needles] stand in [shown], whatever the case, as ranges in order with none over another.
List<(int, int)> marksIn(String shown, List<String> needles) {
  final lower = shown.toLowerCase();
  if (lower.length != shown.length) return const <(int, int)>[];
  final marks = <(int, int)>[];
  for (final needle in needles) {
    if (needle.isEmpty) continue;
    var at = lower.indexOf(needle);
    while (at >= 0) {
      marks.add((at, at + needle.length));
      at = lower.indexOf(needle, at + needle.length);
    }
  }
  marks.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
  final joined = <(int, int)>[];
  for (final mark in marks) {
    if (joined.isNotEmpty && mark.$1 <= joined.last.$2) {
      if (mark.$2 > joined.last.$2) joined[joined.length - 1] = (joined.last.$1, mark.$2);
    } else {
      joined.add(mark);
    }
  }
  return joined;
}

/// What a line of Markdown opens with, which a snippet leaves out: a heading's signs, a quote's, a list's, a box.
final RegExp _lead = RegExp(r'^\s*(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)*');
final RegExp _spaces = RegExp(r'\s+');

/// The line of [note] the [needles] stand in, past its name: the first line with one that is not the name's own,
/// cut to about a hundred and forty letters around the first, with every needle in it marked. Null where the words
/// are only in the name.
Snippet? snippetOf(Note note, List<String> needles, {int before = 36, int most = 140}) {
  // The words as written, where lower case is letter for letter the same; else in lower case.
  final plain = plainFills(note.body);
  final lowered = plain.toLowerCase();
  final text = lowered.length == plain.length ? plain : lowered;
  final read = lowered;
  final name = NoteFacts.of(note).title.toLowerCase();
  final nameAt = name.isEmpty ? -1 : read.indexOf(name);
  final nameEnd = nameAt < 0 ? 0 : nameAt + name.length;

  // The first needle past the name; else the first before it (the note's front matter).
  var at = -1;
  for (final from in [nameEnd, 0]) {
    for (final needle in needles) {
      if (needle.isEmpty) continue;
      final here = read.indexOf(needle, from);
      if (here >= 0 && (from > 0 || here < nameAt || nameAt < 0) && (at < 0 || here < at)) at = here;
    }
    if (at >= 0) break;
  }
  if (at < 0 || at >= text.length) return null;

  var start = text.lastIndexOf('\n', at) + 1;
  var end = text.indexOf('\n', at);
  if (end < 0) end = text.length;
  final lead = _lead.matchAsPrefix(text.substring(start, end));
  if (lead != null && start + lead.end <= at) start += lead.end;
  var opens = false, runs = false;
  if (at - start > before) {
    // Back to the start of a word.
    var from = at - before;
    final space = text.indexOf(' ', from);
    if (space >= 0 && space < at) from = space + 1;
    start = from;
    opens = true;
  }
  if (end - start > most) {
    end = start + most;
    runs = true;
  }
  final cut = text.substring(start, end).replaceAll(_spaces, ' ').trim();
  if (cut.isEmpty) return null;
  final shown = '${opens ? '…' : ''}$cut${runs ? '…' : ''}';
  return Snippet(shown, marksIn(shown, needles));
}
