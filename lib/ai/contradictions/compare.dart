/// What the AI is asked about a batch of candidate pairs, and how its answer is read (docs/CONTRADICTIONS.md, "The AI
/// compares" and "Validation"; Matt, 2026-11-02: "flags the stale one inline, 'superseded by …', so old notes stop
/// misleading you or the AI").
///
/// A request is [pairsPerRequest] pairs, each its two notes' excerpts (candidates.dart `excerptOf`) as A (older) and B
/// (newer) with their dates. The answer is JSON only, `{"findings": [{pair, older, older_quote, newer, newer_quote,
/// what, confidence}]}`, and [readFindings] trusts none of it: an unknown pair, an `older` that is not the older note,
/// a quote not in that note's words, a confidence that is not a number from 0 to 1 or is under the threshold, and an
/// empty `what` are each dropped, so an invented disagreement never reaches a note.
library;

import 'dart:convert';

import '../../core/note_text.dart' show noteTitle;
import 'candidates.dart';
import 'findings.dart';

/// Pairs in one request.
const int pairsPerRequest = 6;

/// The confidence a finding needs to be shown, unless the person chose another (0.7 or 0.9).
const double defaultThreshold = 0.8;

/// The most a request may answer with.
const int compareMaxTokens = 1500;

const String compareSystem = '''
You check a person's notes for statements that a newer note contradicts or supersedes: a date, a number, a decision, an owner or a plan that changed.
Each pair is note A (older) and note B (newer), as numbered lines.
Only report a real disagreement about the same thing, where B makes A's statement out of date. Different topics, added detail, or both being true are NOT disagreements.
Quote each statement exactly as it is written in the note (a short span of one line, without the line number).
Answer with JSON only, no other words:
{"findings": [{"pair": 1, "older": "A", "older_quote": "...", "newer": "B", "newer_quote": "...", "what": "one short sentence on what changed", "confidence": 0.0}]}
Use confidence 0.9 or more only when the newer note clearly changes the older statement. Answer {"findings": []} when there are none.''';

String _day(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// The prompt for [batch], pairs numbered from 1.
String comparePrompt(List<CandidatePair> batch) {
  final out = StringBuffer();
  for (var i = 0; i < batch.length; i += 1) {
    final pair = batch[i];
    out
      ..writeln('Pair ${i + 1}')
      ..writeln('A (older, edited ${_day(pair.older.updatedAt)}):')
      ..writeln(excerptOf(pair.older, pair.shared))
      ..writeln('B (newer, edited ${_day(pair.newer.updatedAt)}):')
      ..writeln(excerptOf(pair.newer, pair.shared))
      ..writeln();
  }
  return out.toString().trimRight();
}

/// The JSON object in [text]: the whole of it, inside a code fence, or from its first `{` to its last `}`; null where
/// none parses.
Map<String, Object?>? _jsonIn(String text) {
  final tries = <String>[
    text.trim(),
    ?RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text)?.group(1),
    if (text.contains('{') && text.lastIndexOf('}') > text.indexOf('{')) text.substring(text.indexOf('{'), text.lastIndexOf('}') + 1),
  ];
  for (final candidate in tries) {
    try {
      final json = jsonDecode(candidate.trim());
      if (json is Map) return json.cast<String, Object?>();
    } catch (_) {
      // The next way of finding it.
    }
  }
  return null;
}

/// Whether [quote] is in [body]'s words, as [sameWords] has them, and long enough to mean something.
bool quoteIn(String body, String quote) {
  final want = sameWords(quote);
  return want.length >= 4 && sameWords(body).contains(want);
}

/// The findings in [answer] for [batch] (see the header), found [now], at or over [threshold]. One per older line: the
/// most confident.
List<Finding> readFindings(String answer, List<CandidatePair> batch, {required DateTime now, double threshold = defaultThreshold}) {
  final json = _jsonIn(answer);
  final raw = json?['findings'];
  if (raw is! List) return const [];
  final best = <String, Finding>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final n = item['pair'];
    final index = n is num ? n.toInt() : int.tryParse('$n');
    if (index == null || n is num && n != index || index < 1 || index > batch.length) continue;
    final pair = batch[index - 1];
    // The older is A and the newer is B, as the prompt named them; the other way round is a misreading.
    if ('${item['older']}'.trim().toUpperCase() != 'A' || '${item['newer']}'.trim().toUpperCase() != 'B') continue;
    final olderQuote = item['older_quote'], newerQuote = item['newer_quote'], what = item['what'], confidence = item['confidence'];
    if (olderQuote is! String || newerQuote is! String || what is! String || confidence is! num) continue;
    if (confidence.isNaN || confidence < 0 || confidence > 1 || confidence < threshold) continue;
    if (what.trim().isEmpty) continue;
    if (!quoteIn(pair.older.body, olderQuote) || !quoteIn(pair.newer.body, newerQuote)) continue;
    if (sameWords(olderQuote) == sameWords(newerQuote)) continue;
    final finding = Finding(
      olderId: pair.older.id,
      olderTitle: noteTitle(pair.older.body),
      olderQuote: olderQuote.trim(),
      newerId: pair.newer.id,
      newerTitle: noteTitle(pair.newer.body),
      newerQuote: newerQuote.trim(),
      what: what.trim(),
      confidence: confidence.toDouble(),
      found: now,
    );
    final line = '${pair.older.id}|${lineOfQuote(pair.older.body, olderQuote) ?? sameWords(olderQuote)}';
    final had = best[line];
    if (had == null || had.confidence < finding.confidence) best[line] = finding;
  }
  return best.values.toList();
}
