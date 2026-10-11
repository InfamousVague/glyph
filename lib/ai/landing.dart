/// How a line the model has finished finds its place in the note: the pure rules behind the editor's AI changes and
/// ai/land.dart. A port of `src/app/ai/landing.ts`.
///
/// Matt: lines land as they finish, and the note shows what changed as tracked changes, struck words in faint ink,
/// added words tinted. A model rewriting a note writes it top to bottom, and most lines of a tidy-up come back as
/// they were, so the rules are a reader's, not a diff's: each new line is looked for among the next few old lines.
/// Found, the old lines it passed over are what the model dropped; a line that is nearly the same is that line
/// rewritten, and only the words that differ are marked; anything else is a line the model added. The decisions are
/// made once, in order, and never revisited, which is what lets a line land the moment it arrives and stay where it
/// landed.
///
/// What differs: two names. The page's `Segment` is [DiffSegment] here, since core/note.dart has a `Segment` of its
/// own (a recording's), and its `Match` is [LineMatch], since `Match` is dart:core's word for what a RegExp finds.
/// Their kinds are enums with the web's words.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/item_syntax.dart' show jsTrim;

/// How far ahead an old line is looked for (`LOOKAHEAD`). Past this a match is more likely a coincidence than the
/// same line.
const int lookahead = 8;

/// One word of a line (`Token`).
@immutable
class Token {
  const Token({required this.lead, required this.word});

  /// The whitespace before the word.
  final String lead;
  final String word;

  @override
  bool operator ==(Object other) => other is Token && other.lead == lead && other.word == word;

  @override
  int get hashCode => Object.hash(lead, word);

  @override
  String toString() => 'Token("$lead", "$word")';
}

final RegExp _token = RegExp(r'(\s*)(\S+)');

/// A line as its words, each with the space before it; trailing whitespace is nobody's (`tokens`).
List<Token> tokens(String line) => [for (final m in _token.allMatches(line)) Token(lead: m[1] ?? '', word: m[2] ?? '')];

/// What a piece of a line is to the line before it (`Segment['kind']`); [name] is the web's word.
enum SegmentKind { same, added, removed }

/// A run of words that stayed, came or went (`Segment`).
@immutable
class DiffSegment {
  const DiffSegment({required this.kind, required this.text});

  final SegmentKind kind;
  final String text;

  @override
  bool operator ==(Object other) => other is DiffSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'DiffSegment(${kind.name}, "$text")';
}

final RegExp _endPunctuation = RegExp(r'[.,;:!?]+$');

/// A word for comparing: its case kept (a capital is a change), the punctuation on its end not (a comma is not).
bool _sameWord(String a, String b) => a.replaceFirst(_endPunctuation, '') == b.replaceFirst(_endPunctuation, '');

/// Two lines, word by word: what stayed, what came, what went (`wordDiff`). Words are compared with their case,
/// since a rewrite that changes a capital changed a word, and without the punctuation on their end, since a comma
/// added after one is not worth striking the word for. The new line's trailing whitespace rides on its last piece,
/// so the pieces that are not `removed` join back to exactly the new line.
List<DiffSegment> wordDiff(String oldLine, String newLine) {
  final a = tokens(oldLine);
  final b = tokens(newLine);
  final cols = b.length + 1;
  final table = List<int>.filled((a.length + 1) * cols, 0);
  for (var i = a.length - 1; i >= 0; i -= 1) {
    for (var j = b.length - 1; j >= 0; j -= 1) {
      table[i * cols + j] = _sameWord(a[i].word, b[j].word) ? table[(i + 1) * cols + j + 1] + 1 : math.max(table[(i + 1) * cols + j], table[i * cols + j + 1]);
    }
  }
  final kinds = <SegmentKind>[];
  final texts = <StringBuffer>[];
  void push(SegmentKind kind, String text) {
    if (kinds.isNotEmpty && kinds.last == kind) {
      texts.last.write(text);
    } else {
      kinds.add(kind);
      texts.add(StringBuffer(text));
    }
  }

  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && _sameWord(a[i].word, b[j].word)) {
      push(SegmentKind.same, b[j].lead + b[j].word);
      i += 1;
      j += 1;
    } else if (j >= b.length || (i < a.length && table[(i + 1) * cols + j] >= table[i * cols + j + 1])) {
      push(SegmentKind.removed, a[i].lead + a[i].word);
      i += 1;
    } else {
      push(SegmentKind.added, b[j].lead + b[j].word);
      j += 1;
    }
  }
  var covered = 0;
  for (final token in b) {
    covered += token.lead.length + token.word.length;
  }
  final tail = newLine.substring(covered);
  if (tail.isNotEmpty) {
    final last = kinds.lastIndexWhere((kind) => kind != SegmentKind.removed);
    if (last >= 0) {
      texts[last].write(tail);
    } else {
      push(SegmentKind.added, tail);
    }
  }
  return [for (var n = 0; n < kinds.length; n += 1) DiffSegment(kind: kinds[n], text: texts[n].toString())];
}

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String _bare(String word) => word.toLowerCase().replaceAll(_notWord, '');

/// Whether a new line is an old line rewritten rather than a different line (`similar`): half its words or more are
/// the old line's (the words themselves, not their marks or punctuation), and at least two of them, or the one word
/// each line has, for a title made a heading.
bool similar(String oldLine, String newLine) {
  final a = {for (final t in tokens(oldLine)) _bare(t.word)}..remove('');
  final b = {for (final t in tokens(newLine)) _bare(t.word)}..remove('');
  if (a.isEmpty || b.isEmpty) return false;
  var shared = 0;
  for (final word in b) {
    if (a.contains(word)) shared += 1;
  }
  final score = shared / math.max(a.length, b.length);
  return score >= 0.5 && (shared >= 2 || (a.length == 1 && b.length == 1 && shared == 1));
}

/// What a finished line is to the old lines ahead (`Match['kind']`); [name] is the web's word.
enum MatchKind { keep, replace, insert }

/// Where a finished line belongs (`Match`).
@immutable
class LineMatch {
  /// The old line [at] is this line: the lines before it were dropped.
  const LineMatch.keep(int this.at) : kind = MatchKind.keep;

  /// The old line [at] rewritten: the lines before it were dropped, and only the words that differ are marked.
  const LineMatch.replace(int this.at) : kind = MatchKind.replace;

  /// A line the model added.
  const LineMatch.insert()
      : kind = MatchKind.insert,
        at = null;

  final MatchKind kind;

  /// The old line it is, counted from the first still ahead; null for a line the model added.
  final int? at;

  @override
  bool operator ==(Object other) => other is LineMatch && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => at == null ? 'LineMatch(${kind.name})' : 'LineMatch(${kind.name}, $at)';
}

final RegExp _trailingSpace = RegExp(r'\s+$');

String _trimEnd(String line) => line.replaceFirst(_trailingSpace, '');

/// Where a finished line belongs among the old lines still ahead (`matchLine`). A blank line is looked for only at
/// the very next line, since blank lines are everywhere and matching one further on would drop the words between
/// for nothing.
LineMatch matchLine(List<String> oldLines, String line) {
  final words = jsTrim(line).isNotEmpty;
  final look = math.min(words ? lookahead : 1, oldLines.length);
  final wanted = _trimEnd(line);
  for (var i = 0; i < look; i += 1) {
    if (_trimEnd(oldLines[i]) == wanted) return LineMatch.keep(i);
  }
  if (words) {
    for (var i = 0; i < look; i += 1) {
      if (similar(oldLines[i], line)) return LineMatch.replace(i);
    }
  }
  return const LineMatch.insert();
}
