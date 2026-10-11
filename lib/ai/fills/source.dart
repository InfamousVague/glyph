/// Where a model's answer came from, decided by code when it lands (docs/DESIGN.md §145, 2.5): from this note, or from
/// memory. A port of `src/app/ai/fills/source.ts`. Never by the model: asked to label its own answers NOTE, KNOWN or
/// UNKNOWN, the 4B kept the format 9 times in 17 and called an invented 2026 World Cup winner KNOWN.
///
/// "From this note" needs the answer's words beside what was asked. A note that says `We watched France play in
/// Qatar.` above `The 2022 World Cup was won by {?}` got the measured wrong answer France: every word of it is in the
/// note, but the one sentence holding "France" holds none of 2022, World, Cup or won, so it is from memory and dotted
/// as it can be wrong. Pure.
///
/// What differs: the accents come off by the app's table of JavaScript's own decompositions (ai/support/unaccent.dart)
/// where the page asked `normalize('NFD')`, with that file's one caveat about a run of combining marks.
library;

import '../../core/blanks.dart';
import '../../core/fill_live.dart';
import '../../core/item_syntax.dart' show jsTrim;
import '../support/unaccent.dart';
import 'shape.dart';

final Set<String> _stop = 'a an the of to in on at and or is are was be it for with by from as that this i we you he she they who what when where which how why whom whose'.split(' ').toSet();

final RegExp _digitCommaDigit = RegExp(r'(\d),(\d)');
final RegExp _lettersAndNumbers = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _aDigit = RegExp(r'\d');
final RegExp _trailingS = RegExp(r's$');

/// A text's content words: lower case, accents folded, punctuation off, a trailing s aside, stop words and short words
/// out, numbers kept.
List<String> contentWords(String text) {
  final folded = unaccented(text.toLowerCase()).replaceAllMapped(_digitCommaDigit, (m) => '${m.group(1)}${m.group(2)}');
  return [
    for (final match in _lettersAndNumbers.allMatches(folded))
      if (_aDigit.hasMatch(match.group(0)!) || (match.group(0)!.length >= 3 && !_stop.contains(match.group(0))))
        _aDigit.hasMatch(match.group(0)!) ? match.group(0)! : match.group(0)!.replaceFirst(_trailingS, ''),
  ];
}

/// The note as a source reads it: no blanks, and no earlier fill's words or bracket, so a memory answer never vouches
/// for another.
String noteForSource(String text) {
  var out = text;
  for (final fill in fillsIn(text).reversed) {
    out = '${out.substring(0, fill.from)}${out.substring(fill.to)}';
  }
  return out.replaceAll(blankPattern, ' ');
}

final RegExp _tableLine = RegExp(r'^\s*\|');
final RegExp _sentenceGap = RegExp(r'(?<=[.?!])\s+');

/// The note's sentences: each line split at its sentence ends, a table row one sentence.
List<String> _sentencesOf(String text) => [
      for (final line in text.split('\n'))
        if (_tableLine.hasMatch(line)) line else ...line.split(_sentenceGap),
    ];

/// Whether an answer is from this note: for a title or a summary, every content word of it is in its scope; for any
/// other shape, one sentence of the note, not on the blank's own line, holds every content word of the answer and
/// every one of what was asked. An answer with no content words at all ("no", "A") is from memory.
///
/// Both rules came from the review of §145. The blank's own line always holds the asking words, so "Australia" for
/// `The capital of Australia is {?}` counted as the note's: that line is left out. And words side by side are not the
/// note giving the answer: under `We watched the World Cup final in 2022: France against Argentina.`, "France" for
/// `The 2022 World Cup was won by {?}` stood beside 2022, World and Cup, but no sentence says who won. So every asking
/// word must be there, "won" included.
bool fromThisNote(String answer, Blank blank, Shape shape, String text, String scope) {
  final words = contentWords(answer);
  if (words.isEmpty) return false;
  if (shape == Shape.title || shape == Shape.summary) {
    final have = contentWords(noteForSource(scope)).toSet();
    return words.every(have.contains);
  }
  final asked = askingWords(blank, text);
  final question = jsTrim(asked.question);
  final asking = contentWords(question.isNotEmpty ? question : askingClause(asked));
  if (asking.isEmpty) return false;
  final lineStart = blank.from <= 0 ? 0 : text.lastIndexOf('\n', blank.from - 1) + 1;
  final lineEnd = text.indexOf('\n', blank.to);
  final others = '${text.substring(0, lineStart)}${lineEnd < 0 ? '' : text.substring(lineEnd)}';
  return _sentencesOf(noteForSource(others)).any((sentence) {
    final have = contentWords(sentence).toSet();
    return words.every(have.contains) && asking.every(have.contains);
  });
}
