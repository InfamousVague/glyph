/// The AI's half of Note decay alerts (docs/NOTE_DECAY.md §1.2, §2; Matt, 2026-11-02: "docs and pages that reference
/// things that have since changed … get a quiet 'may be out of date' mark with the reason"): whether a page the
/// signals flagged is out of date and on which lines, and Update with AI's edits, both as JSON whose quotes are
/// checked against the page, so a model can neither mark a line the page does not have nor change one it does not.
///
/// [DecayModel] is the one seam: the app's asks whatever AI is connected, or the phone's own model under Local only
/// (note_decay.dart wires it); a test's answers what it is given, so no test reaches a network or a model.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'signals.dart';

/// An AI the plugin can ask: one prompt, one answer.
abstract interface class DecayModel {
  /// Who answers, as a person reads it: "Claude", "the phone's model".
  String get name;

  /// Whether it can be asked now.
  bool get ready;

  /// Whether it runs on the phone (what Local only allows).
  bool get onDevice;

  /// One answer to [prompt] under [system]. Throws where it cannot.
  Future<String> ask({required String system, required String prompt});
}

/// Nobody to ask.
class NoDecayModel implements DecayModel {
  const NoDecayModel();
  @override
  String get name => 'No AI';
  @override
  bool get ready => false;
  @override
  bool get onDevice => true;
  @override
  Future<String> ask({required String system, required String prompt}) => Future.error(StateError('No AI is connected.'));
}

/// What one of the page's sources says now, for the model to read beside the page.
@immutable
class DecaySource {
  const DecaySource({required this.what, required this.says});

  /// "GHO-12", "[[Spec v2]]", "PR #12 in owner/repo".
  final String what;

  /// Its reason, and what it says now: its first lines.
  final String says;
}

/// Whitespace and quotes folded, for a quote to be found whatever its spaces or its curly marks.
String _folded(String text) => text.replaceAll(RegExp('[‘’]'), "'").replaceAll(RegExp('[“”]'), '"').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// The line of [body] holding [quote], from 0, or null where none does: a model's quote checked.
int? lineOfQuote(String body, String quote) {
  final want = _folded(quote);
  if (want.length < 4) return null;
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_folded(lines[i]).contains(want)) return i;
  }
  return null;
}

/// The first JSON object in [text]: a model's answer, fences and words round it left off.
Map<String, Object?>? _jsonIn(String text) {
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final parsed = jsonDecode(text.substring(start, end + 1));
    return parsed is Map ? parsed.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

const String _checkSystem =
    'You check whether a page in someone\'s notes is out of date. You are given the page and what has changed in the things it refers to. '
    'Answer only JSON: {"outOfDate": true|false, "lines": [{"quote": "exact words from the page", "why": "one short sentence"}]}. '
    'Quote each line\'s words exactly as the page has them. Mark only lines that the changes make wrong or misleading; leave the rest. If nothing is out of date, answer {"outOfDate": false, "lines": []}.';

/// The prompt for whether [note] is out of date, given [sources].
String checkPrompt(DecayNote note, List<DecaySource> sources) => [
      'The page, titled "${note.title}", last edited ${note.edited.toIso8601String().substring(0, 10)}:',
      '<page>',
      note.body,
      '</page>',
      if (sources.isNotEmpty) ...['', 'What has changed since:', for (final source in sources) '- ${source.what}: ${source.says}'],
    ].join('\n');

/// The AI pass over [note]: the lines it says are out of date, each a signal of kind [DecayKind.ai] whose reason is
/// the model's, said as the AI's, its quote checked against the page. A quote the page does not have is dropped.
Future<List<DecaySignal>> aiSignalsOf(DecayNote note, List<DecaySource> sources, DecayModel model) async {
  if (!model.ready) return const [];
  final answer = _jsonIn(await model.ask(system: _checkSystem, prompt: checkPrompt(note, sources)));
  if (answer == null || answer['outOfDate'] != true) return const [];
  final lines = answer['lines'];
  if (lines is! List) return const [];
  final out = <DecaySignal>[];
  final seen = <int>{};
  for (final item in lines) {
    if (item is! Map) continue;
    final quote = item['quote'], why = item['why'];
    if (quote is! String || why is! String || why.trim().isEmpty) continue;
    final line = lineOfQuote(note.body, quote);
    if (line == null || !seen.add(line)) continue;
    // Its stamp is the line's own words: edited, the line is another, and a Still right is asked again.
    final words = note.body.split('\n')[line].trim();
    out.add(DecaySignal(kind: DecayKind.ai, key: 'line:${stableHash(_folded(words))}', stamp: sources.map((s) => s.what).join(','), reason: 'AI: ${why.trim()}', line: line, quote: words));
  }
  return out;
}

/// One edit Update with AI proposes: a line's words, and what it suggests in their place.
@immutable
class DecayEdit {
  const DecayEdit({required this.line, required this.before, required this.after, this.why = ''});

  /// The page's line, from 0.
  final int line;

  /// That line's words as the page has them now.
  final String before;

  /// What the line becomes once accepted; empty to take the line out.
  final String after;
  final String why;
}

const String _updateSystem =
    'You update a page in someone\'s notes that has gone out of date. You are given the page, the lines that may be out of date with why, and what has changed. '
    'Answer only JSON: {"edits": [{"quote": "the exact line as the page has it", "replacement": "the line as it should read now", "why": "one short sentence"}]}. '
    'Change only what the changes make wrong, keep the page\'s voice, its Markdown and its links, and leave every other line alone. An empty replacement removes the line.';

/// The prompt for Update with AI on [note], for [signals].
String updatePrompt(DecayNote note, List<DecaySignal> signals, List<DecaySource> sources) => [
      'The page, titled "${note.title}":',
      '<page>',
      note.body,
      '</page>',
      '',
      'Lines that may be out of date:',
      for (final signal in signals) '- ${signal.line == null ? '(the page as a whole)' : '"${signal.quote}"'}: ${signal.reason}',
      if (sources.isNotEmpty) ...['', 'What has changed:', for (final source in sources) '- ${source.what}: ${source.says}'],
    ].join('\n');

/// Update with AI: the edits the model proposes for [signals] on [note], each checked: its quote a line the page has,
/// once, and its replacement not the same words. Nothing is applied here ([applyEdits] is, once accepted).
Future<List<DecayEdit>> proposeEdits(DecayNote note, List<DecaySignal> signals, List<DecaySource> sources, DecayModel model) async {
  final answer = _jsonIn(await model.ask(system: _updateSystem, prompt: updatePrompt(note, signals, sources)));
  final edits = answer?['edits'];
  if (edits is! List) return const [];
  final lines = note.body.split('\n');
  final out = <DecayEdit>[];
  final seen = <int>{};
  for (final item in edits) {
    if (item is! Map) continue;
    final quote = item['quote'], replacement = item['replacement'], why = item['why'];
    if (quote is! String || replacement is! String) continue;
    final line = lineOfQuote(note.body, quote);
    if (line == null || !seen.add(line)) continue;
    final before = lines[line];
    // A replacement for part of the line stands in for that part; one for the whole line, for the line.
    final at = before.indexOf(quote);
    final after = replacement.trim().isEmpty
        ? ''
        : at >= 0 && quote.trim() != before.trim()
            ? before.replaceRange(at, at + quote.length, replacement)
            : _keepIndent(before, replacement);
    if (after == before) continue;
    out.add(DecayEdit(line: line, before: before, after: after, why: why is String ? why.trim() : ''));
  }
  out.sort((a, b) => a.line - b.line);
  return out;
}

final RegExp _lead = RegExp(r'^(\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)?)');

/// [replacement] with [before]'s indent and list sign, where the model left them off.
String _keepIndent(String before, String replacement) {
  if (replacement.isEmpty) return '';
  return _lead.firstMatch(replacement)![1]!.isNotEmpty ? replacement : '${_lead.firstMatch(before)![1]!}$replacement';
}

/// A short hash of [text] that is the same on every device and every run (FNV-1a, 32 bits): an AI mark's key, kept
/// in a page's `decay-ok:`.
String stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// [body] with the [accepted] edits made, each where its line still reads as it did; an empty replacement takes its
/// line out. One whose line has changed since is left, so an accepted edit never writes over a newer line.
String applyEdits(String body, List<DecayEdit> accepted) {
  final lines = body.split('\n');
  final out = <String>[];
  final byLine = {for (final edit in accepted) edit.line: edit};
  for (var i = 0; i < lines.length; i++) {
    final edit = byLine[i];
    if (edit == null || lines[i] != edit.before) {
      out.add(lines[i]);
    } else if (edit.after.isNotEmpty) {
      out.add(edit.after);
    }
  }
  return out.join('\n');
}
