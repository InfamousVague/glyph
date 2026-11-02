/// The model's answer, read and checked (docs/ASK_THE_ORG.md, "Receipts: every quote checked"; Matt, 2026-11-02:
/// "every claim linked to the note and line it came from; when notes disagree, it shows both instead of guessing").
///
/// Nothing the model says is drawn as from the notes until its quote is found in the note, at the lines it names,
/// among the passages it was sent. A quote found elsewhere in what was sent of that note has its lines moved to
/// where it is; any other is dropped, and a sentence with no citation left is left out.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import 'ask_retrieve.dart';

/// One receipt: a note, its lines, and the words quoted from them.
@immutable
class AskCitation {
  const AskCitation({required this.note, required this.fromLine, required this.toLine, required this.quote, this.moved = false});

  final Note note;
  final int fromLine;
  final int toLine;
  final String quote;

  /// The model named other lines; these are where the quote is.
  final bool moved;

  String get noteId => note.id;
  String get title {
    final title = NoteFacts.of(note).title.trim();
    return title.isEmpty ? 'Untitled' : title;
  }

  /// Where it is, as the receipts say it: "line 5", "lines 4–6".
  String get lines => fromLine == toLine ? 'line $fromLine' : 'lines $fromLine–$toLine';

  /// What a receipt is told apart by.
  String get place => '$noteId:$fromLine-$toLine';

  /// Where a note is opened to land on these lines (lib/note/land_at.dart).
  String get at => 'lines:$fromLine-$toLine';
}

/// A sentence of the answer and its receipts. [general] is from the model's own knowledge, never the notes.
@immutable
class AskSentence {
  const AskSentence(this.text, this.citations, {this.general = false});

  final String text;
  final List<AskCitation> citations;
  final bool general;
}

/// One side of a disagreement: what that note says, and where.
@immutable
class AskSide {
  const AskSide(this.text, this.citation);

  final String text;
  final AskCitation citation;
}

/// Notes that disagree about [about], newest first.
@immutable
class AskConflict {
  const AskConflict(this.about, this.sides);

  final String about;
  final List<AskSide> sides;
}

/// The answer as drawn.
@immutable
class AskAnswer {
  const AskAnswer({this.sentences = const [], this.conflicts = const [], this.leftOut = 0, this.dropped = 0, this.notFound = false});

  /// The answer when nothing in the scope was found to send.
  const AskAnswer.nothingFound() : this(notFound: true);

  final List<AskSentence> sentences;
  final List<AskConflict> conflicts;

  /// Sentences left out for want of a receipt that held.
  final int leftOut;

  /// Citations dropped: their quote was not in the note, or the note was not among what was sent.
  final int dropped;

  /// The notes do not say: the model said so, or nothing it said held.
  final bool notFound;

  /// Every receipt once, in the order it is first cited, numbered from 1 by its place in this list.
  List<AskCitation> get receipts {
    final seen = <String>{};
    return [
      for (final s in sentences)
        for (final c in s.citations)
          if (seen.add(c.place)) c,
      for (final conflict in conflicts)
        for (final side in conflict.sides)
          if (seen.add(side.citation.place)) side.citation,
    ];
  }

  /// [citation]'s number among the [receipts].
  int numberOf(AskCitation citation) => receipts.indexWhere((c) => c.place == citation.place) + 1;
}

final RegExp _think = RegExp(r'<think>[\s\S]*?</think>');

/// The JSON object in what the model wrote: a fence round it, thinking before it, or words either side forgiven.
/// Null where there is none.
Map<String, Object?>? parseAskJson(String said) {
  final text = said.replaceAll(_think, '');
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final parsed = jsonDecode(text.substring(start, end + 1));
    return parsed is Map ? parsed.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

final RegExp _markSigns = RegExp(r'\*\*|__|`|\[\[|\]\]|==|~~');
final RegExp _space = RegExp(r'\s+');

/// [text] with what a quote may fairly differ by evened out: case, spacing, curly quotes, dashes, Markdown's marks.
String askEven(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[‘’‛′]'), "'")
    .replaceAll(RegExp('[“”‟″]'), '"')
    .replaceAll(RegExp('[‐-―−]'), '-')
    .replaceAll('…', '...')
    .replaceAll(_markSigns, '')
    .replaceAll(_space, ' ')
    .trim();

/// A quote as it is looked for: evened, its own quotation marks, an ellipsis and closing stop off its ends.
String _quoteKey(String quote) => askEven(quote).replaceAll(RegExp(r'^["\x27.…\s]+|["\x27.,;:!?…\s]+$'), '');

int? _int(Object? value) => value is int ? value : (value is num ? value.toInt() : (value is String ? int.tryParse(value.trim()) : null));

/// Reads and checks one citation against what was [sent] (see the library's doc); null where it does not hold.
AskCitation? checkCitation(Object? raw, List<AskPassage> sent) {
  if (raw is! Map) return null;
  final noteId = raw['noteId'] ?? raw['note'];
  final quote = raw['quote'];
  if (noteId is! String || quote is! String) return null;
  final key = _quoteKey(quote);
  if (key.length < 3) return null;
  final mine = [for (final p in sent) if (p.note.id == noteId) p];
  if (mine.isEmpty) return null;
  final note = mine.first.note;
  final lines = note.body.split('\n');
  final from = _int(raw['fromLine']), to = _int(raw['toLine']) ?? from;
  bool covered(int line) => mine.any((p) => line >= p.fromLine && line <= p.toLine);
  String span(int a, int b) => askEven(lines.sublist(a - 1, b).join(' '));
  if (from != null && to != null && from >= 1 && to >= from && to <= lines.length) {
    var all = true;
    for (var line = from; line <= to; line += 1) {
      if (!covered(line)) all = false;
    }
    if (all && span(from, to).contains(key)) return AskCitation(note: note, fromLine: from, toLine: to, quote: quote.trim());
  }
  // The quote elsewhere in what was sent of the note: its lines are where it is, the fewest that hold it.
  for (final p in mine) {
    if (!span(p.fromLine, p.toLine).contains(key)) continue;
    var b = p.fromLine;
    while (!span(p.fromLine, b).contains(key)) {
      b += 1;
    }
    var a = b;
    while (!span(a, b).contains(key)) {
      a -= 1;
    }
    return AskCitation(note: note, fromLine: a, toLine: b, quote: quote.trim(), moved: true);
  }
  return null;
}

/// The model's [raw] answer checked against what was [sent]; [general] whether general knowledge was allowed.
AskAnswer validateAsk(Map<String, Object?> raw, List<AskPassage> sent, {bool general = false}) {
  var dropped = 0, leftOut = 0;
  final sentences = <AskSentence>[];
  final rawSentences = raw['sentences'] ?? raw['answer'];
  if (rawSentences is List) {
    for (final each in rawSentences) {
      if (each is! Map || each['text'] is! String) continue;
      final text = (each['text'] as String).trim();
      if (text.isEmpty) continue;
      final cited = <AskCitation>[];
      final rawCitations = each['citations'];
      if (rawCitations is List) {
        for (final c in rawCitations) {
          final checked = checkCitation(c, sent);
          if (checked == null) {
            dropped += 1;
          } else if (!cited.any((had) => had.place == checked.place)) {
            cited.add(checked);
          }
        }
      }
      final isGeneral = each['general'] == true && cited.isEmpty;
      if (cited.isNotEmpty) {
        sentences.add(AskSentence(text, cited));
      } else if (isGeneral && general) {
        sentences.add(AskSentence(text, const [], general: true));
      } else {
        leftOut += 1;
      }
    }
  }

  final conflicts = <AskConflict>[];
  final rawConflicts = raw['conflicts'];
  if (rawConflicts is List) {
    for (final each in rawConflicts) {
      if (each is! Map || each['sides'] is! List) continue;
      final sides = <AskSide>[];
      for (final side in each['sides'] as List) {
        if (side is! Map || side['text'] is! String) continue;
        final checked = checkCitation(side['citation'] ?? (side['citations'] is List && (side['citations'] as List).isNotEmpty ? (side['citations'] as List).first : null), sent);
        if (checked == null) {
          dropped += 1;
          continue;
        }
        if (sides.any((had) => had.citation.place == checked.place)) continue;
        sides.add(AskSide((side['text'] as String).trim(), checked));
      }
      if (sides.length >= 2) {
        sides.sort((a, b) {
          final by = b.citation.note.createdAt.compareTo(a.citation.note.createdAt);
          return by != 0 ? by : b.citation.note.updatedAt.compareTo(a.citation.note.updatedAt);
        });
        final about = each['about'];
        conflicts.add(AskConflict(about is String ? about.trim() : '', List.unmodifiable(sides)));
      } else if (sides.length == 1) {
        // One side left is no disagreement: what it says is a sentence like any other.
        sentences.add(AskSentence(sides.single.text, [sides.single.citation]));
      }
    }
  }

  final notFound = sentences.where((s) => !s.general).isEmpty && conflicts.isEmpty;
  return AskAnswer(sentences: List.unmodifiable(sentences), conflicts: List.unmodifiable(conflicts), leftOut: leftOut, dropped: dropped, notFound: notFound);
}
