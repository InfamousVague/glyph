/// Where an answer goes in the note, as changes to its text (docs/DESIGN.md §145, 6.2), the same for a note open in
/// its editor (the editor's fill landing, one transaction) and one closed (ai/fills/queue.dart, one write). A port of
/// `src/app/ai/fills/edits.ts`. Pure.
///
/// - A model's answer replaces its blank as an Unsure mark whose hidden bracket says where it came from.
/// - Items: one item a line with the list's own lead, the first where the blank was, each marked with its place.
/// - A title never holds a mark: a title blank lands as plain words, a question that is the whole first line stays the
///   title with its answer under it, and a blank among the title's words lands as plain words. So the note's name and
///   its file's name never carry a bracket.
/// - An answer asked again replaces the mark it was asked for.
///
/// What differs: a [Landing] and a [TextChange] are classes, a change with value equality. JavaScript's sort keeps
/// the order of changes that compare equal and Dart's promises nothing, so both sorts here keep it by hand. A change
/// that reaches past the text's end is cut to the text, as `slice` cut it. `AI_AUTHOR` and `withAuthor` come from
/// ai/support/authors.dart and `commonEnds` from the editor's wisp (editor/marks/wisp_motion.dart), where each was
/// ported first.
library;

import 'package:flutter/foundation.dart';

import '../../core/blanks.dart';
import '../../editor/marks/wisp_motion.dart' show commonEnds;
import '../support/authors.dart';
import 'message.dart';
import 'shape.dart';

/// One answer ready to land: where, what, and whose (`Landing`).
@immutable
class Landing {
  const Landing({
    required this.from,
    required this.to,
    required this.question,
    required this.info,
    required this.words,
    required this.source,
    required this.model,
    required this.date,
  });

  /// The target's span in the text as it reads now: a blank's braces, or an asked-again fill's whole span.
  final int from;
  final int to;
  final String question;
  final ShapeInfo info;

  /// The checked answer: one text, or an items blank's items.
  final List<String> words;
  final FillSource source;
  final String model;

  /// ISO, `2026-09-28`.
  final String date;

  @override
  String toString() => 'Landing($from, $to, $question, ${info.shape.name}, $words, $source, $model, $date)';
}

/// One change to a text: what is between [from] and [to] becomes [insert] (`TextChange`).
@immutable
class TextChange {
  const TextChange({required this.from, required this.to, required this.insert});

  final int from;
  final int to;
  final String insert;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => {'from': from, 'to': to, 'insert': insert};

  @override
  bool operator ==(Object other) => other is TextChange && other.from == from && other.to == to && other.insert == insert;

  @override
  int get hashCode => Object.hash(from, to, insert);

  @override
  String toString() => 'TextChange($from, $to, $insert)';
}

final RegExp _heading = RegExp(r'^\s*#{1,6}\s');

/// [text] between two offsets, each kept inside it, as JavaScript's `slice` keeps them.
String _slice(String text, int from, [int? to]) {
  final start = from.clamp(0, text.length);
  final end = (to ?? text.length).clamp(0, text.length);
  return end <= start ? '' : text.substring(start, end);
}

/// [list] sorted by [compare], the ones that compare equal left in the order they came, as JavaScript's sort leaves
/// them.
List<T> _sorted<T>(Iterable<T> list, int Function(T a, T b) compare) {
  final all = list.toList();
  final order = [for (var i = 0; i < all.length; i += 1) i]
    ..sort((a, b) {
      final by = compare(all[a], all[b]);
      return by != 0 ? by : a - b;
    });
  return [for (final i in order) all[i]];
}

/// The changes one answer makes, in the text's own offsets.
List<TextChange> landingChanges(String text, Landing answer) {
  final meta = (model: answer.model, source: answer.source, date: answer.date);
  final before = _slice(text, answer.from - 1 < 0 ? 0 : answer.from - 1, answer.from);
  final lineStart = answer.from <= 0 ? 0 : text.lastIndexOf('\n', answer.from - 1) + 1;
  final lineEndAt = answer.to > text.length ? -1 : text.indexOf('\n', answer.to);
  final lineEnd = lineEndAt == -1 ? text.length : lineEndAt;
  final line = _slice(text, lineStart, lineEnd);
  final words = answer.words.isNotEmpty ? answer.words[0] : '';
  final info = answer.info;
  if (info.shape == Shape.title) return [TextChange(from: answer.from, to: answer.to, insert: words)];
  if (info.titleLine && info.shape == Shape.line) {
    // The question stays as the title, plain, and the answer goes under it: on the next line after a heading, after an
    // empty line otherwise. The title does not change, so neither does the file's name.
    final heading = _heading.hasMatch(line);
    final mark = filledMark(words, meta, answer.question);
    return [
      TextChange(from: answer.from, to: answer.to, insert: answer.question),
      TextChange(from: lineEnd, to: lineEnd, insert: '${heading ? '\n' : '\n\n'}$mark'),
    ];
  }
  if (info.titleLine) return [TextChange(from: answer.from, to: answer.to, insert: words)];
  if (info.shape == Shape.items) {
    final count = answer.words.length;
    final marks = [
      for (var i = 0; i < count; i += 1) filledMark(answer.words[i], meta, answer.question, i == 0 ? before : '', count > 1 ? (n: i + 1, of: count) : null),
    ];
    final rest = [for (var i = 1; i < marks.length; i += 1) '\n${nextLead(line, i)}${marks[i]}'];
    return [TextChange(from: answer.from, to: answer.to, insert: '${marks.isNotEmpty ? marks[0] : 'undefined'}${rest.join()}')];
  }
  return [TextChange(from: answer.from, to: answer.to, insert: filledMark(words, meta, answer.question, before))];
}

/// Every answer's changes, sorted and never overlapping, for one transaction or one write.
List<TextChange> allChanges(String text, List<Landing> answers) =>
    _sorted([for (final answer in answers) ...landingChanges(text, answer)], (a, b) => a.from != b.from ? a.from - b.from : a.to - b.to);

/// The text with changes applied.
String applyChanges(String text, List<TextChange> changes) {
  var out = text;
  for (final change in _sorted<TextChange>(changes, (a, b) => b.from - a.from)) {
    out = '${_slice(out, 0, change.from)}${change.insert}${_slice(out, change.to)}';
  }
  return out;
}

/// The AI's signature as a change of its own at the top, in the text's own offsets: it touches only the front matter,
/// so it lands in the same transaction as the answers without crossing them. Null when the note is signed already.
TextChange? signatureChange(String text, [String? owner]) {
  final signed = withAuthor(text, aiAuthor, owner);
  if (signed == text) return null;
  final (:prefix, :suffix) = commonEnds(text, signed);
  return TextChange(from: prefix, to: text.length - suffix, insert: signed.substring(prefix, signed.length - suffix));
}
