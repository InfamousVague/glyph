import 'dart:math' as math;

/// The plan behind words that arrive from smoke (art/wisp.ts): what a text is made of, which words a new text keeps
/// and which it swaps, and when each letter moves. Pure, so every shape of change is a test; the drawing lives with
/// the widget (wisp_text.dart).
///
/// A text is words and the gaps between them; a change from one text to another is worked out word by word (the
/// longest common run of words stays put, the rest leave and arrive), and within a word the letters go one at a
/// time, at a hand's pace.

enum WispTokenKind { word, gap }

class WispToken {
  const WispToken(this.kind, this.text);
  final WispTokenKind kind;
  final String text;

  @override
  bool operator ==(Object other) => other is WispToken && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}:"$text"';
}

final RegExp _space = RegExp(r'\s');
final RegExp _spaces = RegExp(r'\s+');

/// Words and the whitespace between them, in order; the text is their join.
List<WispToken> tokenize(String text) {
  final tokens = <WispToken>[];
  var at = 0;
  for (final gap in _spaces.allMatches(text)) {
    if (gap.start > at) tokens.add(WispToken(WispTokenKind.word, text.substring(at, gap.start)));
    tokens.add(WispToken(WispTokenKind.gap, gap.group(0)!));
    at = gap.end;
  }
  if (at < text.length) tokens.add(WispToken(WispTokenKind.word, text.substring(at)));
  return tokens;
}

/// Word-level diff: for each old word whether it stays, for each new word whether it was there.
class WordDiff {
  const WordDiff({required this.kept, required this.gone, required this.arriving});

  /// Old token index to new token index, for the words that stay.
  final Map<int, int> kept;

  /// Old token indices of words that leave, in reading order.
  final List<int> gone;

  /// New token indices of words that arrive, in reading order.
  final List<int> arriving;
}

/// Which words of [from] are still in [to], as the longest run of words common to both in the same order, so
/// "Hold. Talk. Done." to "Hold. Talk. Write." keeps the first two and swaps the last, and a word moved elsewhere in
/// the sentence leaves and arrives again rather than sliding.
WordDiff diffWords(List<WispToken> from, List<WispToken> to) {
  final a = [for (var i = 0; i < from.length; i++) if (from[i].kind == WispTokenKind.word) i];
  final b = [for (var i = 0; i < to.length; i++) if (to[i].kind == WispTokenKind.word) i];
  bool same(int i, int j) => from[a[i]].text == to[b[j]].text;
  // Longest common subsequence over the words, bottom-up.
  final cols = b.length + 1;
  final table = List<int>.filled((a.length + 1) * cols, 0);
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      table[i * cols + j] = same(i, j) ? table[(i + 1) * cols + j + 1] + 1 : math.max(table[(i + 1) * cols + j], table[i * cols + j + 1]);
    }
  }
  final kept = <int, int>{};
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (same(i, j)) {
      kept[a[i]] = b[j];
      i++;
      j++;
    } else if (table[(i + 1) * cols + j] >= table[i * cols + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  final keptNew = kept.values.toSet();
  return WordDiff(kept: kept, gone: [for (final index in a) if (!kept.containsKey(index)) index], arriving: [for (final index in b) if (!keptNew.contains(index)) index]);
}

/// One letter's moment: which word, which letter, and when, in milliseconds from the start of its phase.
class WispStep {
  const WispStep(this.token, this.char, this.at);
  final int token, char;
  final double at;

  @override
  String toString() => '$token:$char@$at';
}

/// How long to wait after [ch], with [next] coming.
typedef WispWait = double Function(String ch, String next);

final RegExp _capital = RegExp(r'[A-Z]');

/// The pace of a hand: letters a little uneven, a breath after a comma, longer after a full stop, longer still at a
/// line break, and a beat before a capital. [random] is injectable so the plan is testable.
WispWait cadence(double lettersPerSecond, [double Function()? random]) {
  final roll = random ?? math.Random().nextDouble;
  final base = 1000 / lettersPerSecond;
  return (ch, next) {
    var wait = base * (0.7 + roll() * 0.6);
    if (ch == ',' || ch == ';') wait += base * 2.5;
    if (ch == '.' || ch == '!' || ch == '?') wait += base * 5;
    if (ch == '\n') wait += base * 6;
    if (_space.hasMatch(ch) && next.isNotEmpty && _capital.hasMatch(next)) wait += base * 0.8;
    return wait;
  };
}

/// The letters of a word as the page counts them: whole characters, a pair of surrogates as one.
List<String> lettersOf(String word) => [for (final rune in word.runes) String.fromCharCode(rune)];

/// When each letter of the arriving words appears, in reading order, at the cadence; a gap between words is a
/// pause, not a letter. Words that stay are already there and take no time.
List<WispStep> arrivals(List<WispToken> tokens, List<int> arriving, WispWait wait) {
  final coming = arriving.toSet();
  final steps = <WispStep>[];
  var at = 0.0;
  // As the page has it, the letter after is read by code unit.
  String nextChar(int token, int char) {
    if (token < tokens.length && char + 1 < tokens[token].text.length) return tokens[token].text[char + 1];
    return token + 1 < tokens.length && tokens[token + 1].text.isNotEmpty ? tokens[token + 1].text[0] : '';
  }

  var lastWasNew = false;
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.kind == WispTokenKind.gap) {
      // A pause at a gap only when letters were just placed before it, or come right after.
      if (lastWasNew || coming.contains(index + 1)) at += wait(token.text, nextChar(index, token.text.length - 1));
      lastWasNew = false;
      continue;
    }
    if (!coming.contains(index)) {
      lastWasNew = false;
      continue;
    }
    final letters = lettersOf(token.text);
    for (var char = 0; char < letters.length; char++) {
      steps.add(WispStep(index, char, at));
      at += wait(letters[char], nextChar(index, char));
    }
    lastWasNew = true;
  }
  return steps;
}

/// When each letter of the leaving words goes: the last letter first, the way a word is untyped, a fixed beat apart
/// and quicker than arriving, so a swap reads as one motion: out, then in.
List<WispStep> departures(List<WispToken> tokens, List<int> gone, [double gapMs = 34]) {
  final steps = <WispStep>[];
  var at = 0.0;
  for (final index in gone.reversed) {
    if (index < 0 || index >= tokens.length) continue;
    for (var char = tokens[index].text.length - 1; char >= 0; char--) {
      steps.add(WispStep(index, char, at));
      at += gapMs;
    }
  }
  return steps;
}

/// The whole change from one text to another: what leaves, then what arrives, each with its timing.
class WispSwap {
  const WispSwap({required this.from, required this.to, required this.diff, required this.out, required this.arrive});
  final List<WispToken> from, to;
  final WordDiff diff;

  /// The letters leaving, and (the page's `in`) the letters arriving.
  final List<WispStep> out, arrive;
}

WispSwap planSwap(String fromText, String toText, WispWait wait, [double outGapMs = 34]) {
  final from = tokenize(fromText);
  final to = tokenize(toText);
  final diff = diffWords(from, to);
  return WispSwap(from: from, to: to, diff: diff, out: departures(from, diff.gone, outGapMs), arrive: arrivals(to, diff.arriving, wait));
}

/// How long a run of steps takes, once the last letter's own settling ([settleMs]) is over.
double runLength(List<WispStep> steps, double settleMs) => steps.isEmpty ? 0 : steps.last.at + settleMs;
