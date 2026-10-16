/// How long a note is: its words, its characters and the minutes it takes to read, and the same of the words
/// selected when some are. Shown quietly on the More sheet's Outline row and page (lib/links/note_links.dart), and
/// worked out only while one of them is up: a count is kept for the body it was made from, so the sheet opened
/// twice on the same words counts once, and nothing is counted while the note is being typed in.
///
/// What counts:
/// - **A word** is a run of letters or digits, with an apostrophe inside it ("don't" is one). The front matter is
///   not the note's words, nor a link's address, nor the marks round words, and a `[[link]]` is its words.
/// - **A character** is every character of the note's words with the front matter left out and the line breaks
///   not counted, as Obsidian counts them.
/// - **Reading time** is the words at 238 a minute, the rate most often measured for reading silently, at least a
///   minute where there are any words.
library;

import '../core/front_matter.dart' show frontMatterOffset;

/// A note's length (or a selection's).
typedef WordCount = ({int words, int characters, int minutes});

/// Words read in a minute.
const int wordsAMinute = 238;

final RegExp _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*", unicode: true);
final RegExp _address = RegExp(r'\]\([^)\n]*\)|\b(?:https?|mailto):[^\s)\]>]+', caseSensitive: false);

/// The length of [text], as words. [whole] is a whole note's body, whose front matter is left out.
WordCount countWords(String text, {bool whole = true}) {
  final words = whole ? text.substring(frontMatterOffset(text)) : text;
  final readable = words.contains('](') || words.contains(':') ? words.replaceAll(_address, ' ') : words;
  final count = _word.allMatches(readable).length;
  var characters = 0;
  for (var i = 0; i < words.length; i += 1) {
    final c = words.codeUnitAt(i);
    if (c == 0x0A || c == 0x0D) continue;
    // A pair of surrogates is one character.
    if (c >= 0xDC00 && c <= 0xDFFF && i > 0) {
      final before = words.codeUnitAt(i - 1);
      if (before >= 0xD800 && before <= 0xDBFF) continue;
    }
    characters += 1;
  }
  return (words: count, characters: characters, minutes: count == 0 ? 0 : (count / wordsAMinute).ceil());
}

/// The last few counts, by the body they were made from.
final List<({String body, WordCount count})> _kept = [];

/// [countWords] of a note's [body], kept for that body.
WordCount noteLength(String body) {
  for (final kept in _kept) {
    if (identical(kept.body, body) || kept.body == body) return kept.count;
  }
  final count = countWords(body);
  _kept.add((body: body, count: count));
  if (_kept.length > 8) _kept.removeAt(0);
  return count;
}

/// A number as a person reads it: 1,204.
String grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "1,204 words, 6,830 characters, about 5 minutes to read".
String lengthWords(WordCount count) {
  final words = '${grouped(count.words)} ${count.words == 1 ? 'word' : 'words'}';
  final characters = '${grouped(count.characters)} ${count.characters == 1 ? 'character' : 'characters'}';
  if (count.words == 0) return 'No words yet';
  final minutes = count.minutes <= 1 ? 'a minute to read' : 'about ${count.minutes} minutes to read';
  return '$words, $characters, $minutes';
}
