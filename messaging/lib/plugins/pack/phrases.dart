/// The phrase language a pack matches texts with (A.10): literal words, separators and a few vetted tokens such as
/// `{digits:4-8}`, compiled by the app into regular expressions whose every quantifier is its own and bounded. A
/// stranger's pattern never reaches Dart's RegExp, whose backtracking one nested quantifier once ran for 17.8 seconds
/// on a 29-character text.
library;

import 'format.dart';

/// The tokens a phrase may hold.
const Set<String> phraseTokenNames = {'digits', 'number', 'amount', 'code', 'word', 'words', 'url', 'email', 'phone', 'date', 'time'};

/// [text] with the look-alikes texts are typed with made plain, one for one, so its length doesn't change: the
/// spaces that don't break as a space, curly apostrophes and quotes as straight ones, the dashes as a hyphen. Both a
/// text and a phrase's words go through it, so "don't forget" matches "Don’t forget".
String normalizeForPhrases(String text) {
  final units = text.codeUnits;
  List<int>? out;
  for (var i = 0; i < units.length; i++) {
    final plain = _plainUnit(units[i]);
    if (plain == units[i]) continue;
    (out ??= List.of(units))[i] = plain;
  }
  return out == null ? text : String.fromCharCodes(out);
}

int _plainUnit(int unit) => switch (unit) {
      0x00A0 || 0x2007 || 0x202F => 0x20,
      0x2018 || 0x2019 || 0x201B || 0x02BC => 0x27,
      0x201C || 0x201D || 0x201F => 0x22,
      >= 0x2010 && <= 0x2014 => 0x2D,
      _ => unit,
    };

/// A text as phrases are matched against it: made plain ([normalizeForPhrases]) and cut to its first
/// [PackLimits.scan] code units, which bounds what any phrase can cost, and lower-cased for the anchors' quick look.
class PreparedText {
  PreparedText(String raw) : this._(_cut(normalizeForPhrases(raw)));

  PreparedText._(this.text) : lower = text.toLowerCase();

  final String text;

  /// [text] lower-cased, for anchors.
  final String lower;

  // Cut to the scan, and never ending on half of a character: a high surrogate whose low half was cut off goes too.
  static String _cut(String s) {
    final cut = s.length > PackLimits.scan ? s.substring(0, PackLimits.scan) : s;
    if (cut.isEmpty) return cut;
    final last = cut.codeUnitAt(cut.length - 1);
    return last >= 0xD800 && last <= 0xDBFF ? cut.substring(0, cut.length - 1) : cut;
  }
}

/// Why a phrase isn't one: a phrase_* code (A.14) and plain words for the developer.
class PhraseError implements Exception {
  const PhraseError(this.code, this.message);

  /// A phrase_* code of A.14.
  final String code;
  final String message;

  @override
  String toString() => 'PhraseError($code): $message';
}

/// Where a phrase matched a text: the whole match, and the first token's capture.
class PhraseHit {
  const PhraseHit(this.match, this.token);

  /// The whole match, trimmed.
  final String match;

  /// The first token's capture, trimmed; null where the phrase has no token.
  final String? token;
}

/// One compiled phrase. [Phrase.compile] checks it (A.10.2 to A.10.4) and writes its RegExp (A.10.5); [find] runs it
/// only where the text holds its anchor (A.10.6).
class Phrase {
  /// A.10.2 to A.10.5; throws PhraseError.
  factory Phrase.compile(String source) => throw UnimplementedError('Phrases come with the Marketplace\'s runtime (lib/plugins/pack/phrases.dart).');

  /// The person's own words (A.10.10): braces doubled, then compiled.
  factory Phrase.literal(String words) => Phrase.compile(words.replaceAll('{', '{{').replaceAll('}', '}}'));

  // Made only by compile, from a phrase it has checked, with the pattern it wrote: never from a stranger's RegExp.
  // ignore: unused_element
  Phrase._(this.source, this.pattern, this.anchor, this.hasToken, this._regExp);

  final String source;

  /// The RegExp source, shown to the reviewer and pinned by tests.
  final String pattern;
  final String? anchor;
  final bool hasToken;
  final RegExp _regExp;

  bool get anchorless => anchor == null;

  /// A.10.6 and A.10.7: null where it doesn't match.
  PhraseHit? find(PreparedText text) {
    final anchor = this.anchor;
    if (anchor != null && !text.lower.contains(anchor)) return null;
    final m = _regExp.firstMatch(text.text);
    if (m == null) return null;
    return PhraseHit(m[0]!.trim(), hasToken ? m[1]?.trim() : null);
  }

  bool matches(PreparedText text) => find(text) != null;
}
