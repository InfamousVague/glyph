/// What scrolls through the phone while the models work (scene/at_work.dart): the transcript's phrases as the careful
/// model listens again, the phrases and then the note's lines as the thinking model reads its prompt, its thought as
/// it thinks, and each thing it finds as it writes. Matt: "scrolling through the thoughts and transcriptions of the
/// AI". Pure: one list, one current line, and a window of it for the screen. A port of `src/app/scene/feed.ts`.
///
/// Every line has an ABSOLUTE index, `at`, which is its key on the screen: a phrase's index in the transcript, a
/// thought line's index in the wrapped thought, a note line's offset past the phrases. So a window sliding over the
/// list never remounts a line it keeps, and the line under the pen only changes its text.
///
/// Two of the modes are placements rather than positions, and say so here. The careful speech model never streams
/// its words (capture/refine.dart reports a percent alone), so while it listens the head is put at that share of the
/// phrases. While the thinking model reads, the prompt starts with the fast transcript and ends with the note, with
/// the careful transcript, the disagreements and the titles between them, which are not scrolled; so the head walks
/// the phrases and then the note's lines at the run's share of its prompt, a little ahead of the model.
///
/// What differs: [FeedLine], [Feed] and [FeedRun] are immutable classes and a mode is an enum whose [Enum.name] is
/// the web's word. `FeedRun` was a `Pick` of the run's fields, which any run fitted; here [FeedRun.of] takes them
/// from a run, and the share of the prompt read is worked out here (ai/words.dart `progressOf`, its reading branch,
/// which wants a whole run). A line that is not `strong` says false where the page left the field out.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/kinds.dart';
import '../ai/review_stage.dart';
import '../ai/runs.dart';
import 'steps.dart';

/// One line of the pane (`FeedLine`).
@immutable
class FeedLine {
  const FeedLine({required this.at, required this.text, this.strong = false});

  /// The line's absolute index, and its key.
  final int at;
  final String text;

  /// A thing the model found: bold.
  final bool strong;

  @override
  bool operator ==(Object other) => other is FeedLine && other.at == at && other.text == text && other.strong == strong;

  @override
  int get hashCode => Object.hash(at, text, strong);

  @override
  String toString() => 'FeedLine($at, $text${strong ? ', strong' : ''})';
}

/// `FeedMode`; [name] is the web's word.
enum FeedMode { transcript, reading, thought, findings, prose }

/// What the pane shows (`Feed`).
@immutable
class Feed {
  const Feed({required this.lines, required this.current, required this.mode});

  final List<FeedLine> lines;

  /// The line being read or written, by its index in [lines]; null with nothing to show.
  final int? current;
  final FeedMode mode;

  @override
  bool operator ==(Object other) => other is Feed && listEquals(other.lines, lines) && other.current == current && other.mode == mode;

  @override
  int get hashCode => Object.hash(Object.hashAll(lines), current, mode);

  @override
  String toString() => 'Feed(${mode.name}, current $current, $lines)';
}

/// The part of a run the feed reads: its words, its phase and its prompt's progress, so a screen can key a memo on
/// those alone (`FeedRun`).
@immutable
class FeedRun {
  const FeedRun({
    required this.kind,
    required this.phase,
    this.thought = '',
    this.lines = const <String>[],
    this.partial = '',
    this.promptTokens = 0,
    this.promptTokensDone = 0,
    this.outputTokens = 0,
    this.maxTokens = 0,
  });

  /// Those fields of [run].
  FeedRun.of(RunState run)
      : kind = run.kind,
        phase = run.phase,
        thought = run.thought,
        lines = run.lines,
        partial = run.partial,
        promptTokens = run.promptTokens,
        promptTokensDone = run.promptTokensDone,
        outputTokens = run.outputTokens,
        maxTokens = run.maxTokens;

  final RunKind kind;
  final RunPhase phase;
  final String thought;
  final List<String> lines;
  final String partial;
  final int promptTokens;
  final int promptTokensDone;
  final int outputTokens;
  final int maxTokens;

  @override
  bool operator ==(Object other) =>
      other is FeedRun &&
      other.kind == kind &&
      other.phase == phase &&
      other.thought == thought &&
      listEquals(other.lines, lines) &&
      other.partial == partial &&
      other.promptTokens == promptTokens &&
      other.promptTokensDone == promptTokensDone &&
      other.outputTokens == outputTokens &&
      other.maxTokens == maxTokens;

  @override
  int get hashCode => Object.hash(kind, phase, thought, lines.length, partial, promptTokens, promptTokensDone, outputTokens, maxTokens);
}

/// About how many words a phrase gets when the speaker never stopped.
const int _wordsAPhrase = 14;

/// A thought's sentence past this many words is cut at a clause end, so no one line is a paragraph.
const int _wordsAThoughtLine = 30;

/// A phrase this short is joined to the next: "1." or "Words." alone is not a line.
const int _shortPhrase = 3;

final RegExp _space = RegExp(r'\s+');

int _wordsIn(String piece) => piece.split(_space).length;

final RegExp _sentenceEnd = RegExp(r'(?<=[^\d\s][.?!]["”’)]?)\s+|\n+');

/// Text as sentences: split at sentence ends (a stop, a question mark or an exclamation, then a space, but not after
/// a bare number, so "1. Words" holds together) and at line breaks.
List<String> _sentencesOf(String text) => text.split(_sentenceEnd).map((piece) => piece.trim()).where((piece) => piece.isNotEmpty).toList();

/// A phrase of a word or two joined to the one after it.
List<String> _joinShort(Iterable<String> pieces) {
  final joined = <String>[];
  for (final piece in pieces) {
    if (joined.isNotEmpty && _wordsIn(joined.last) < _shortPhrase) {
      joined[joined.length - 1] = '${joined.last} $piece';
    } else {
      joined.add(piece);
    }
  }
  return joined;
}

/// Text as phrases: sentences, and, where a stretch has no end, about every fourteen words - a placement for the
/// transcript, whose head walks it at the listen's share. A phrase of a word or two is joined to the one after it.
/// `phrasesOf`.
List<String> phrasesOf(String text) => _joinShort(_sentencesOf(text).expand((piece) {
      final words = piece.split(_space);
      if (words.length <= _wordsAPhrase) return [piece];
      final runs = <String>[];
      for (var i = 0; i < words.length; i += _wordsAPhrase) {
        runs.add(words.sublist(i, math.min(words.length, i + _wordsAPhrase)).join(' '));
      }
      // A tail of a word or two rides with the run before it.
      final tail = runs.last;
      if (runs.length > 1 && tail.isNotEmpty && _wordsIn(tail) < _shortPhrase) {
        final before = runs[runs.length - 2];
        runs
          ..removeRange(runs.length - 2, runs.length)
          ..add('$before $tail');
      }
      return runs;
    }));

/// A line's Markdown marks: a heading's hashes, a list's dash and its checkbox, a number, a quote's chevron.
final RegExp _marks = RegExp(r'^(?:#{1,6}\s+|>\s*|(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)+');

/// The note's lines as words, blanks dropped and the Markdown marks off the front: the pane is for what the model
/// reads, not how it is marked (the review saw "# Planning call" and "- [ ] Fix the seat bar" scrolling through the
/// phone). `noteLines`.
List<String> noteLines(String body) => body.split('\n').map((line) => line.trim().replaceFirst(_marks, '')).where((line) => line.isNotEmpty).toList();

final RegExp _clauseEnd = RegExp(r'(?<=[;:])\s+');

/// A thought wrapped into lines: by sentence, since a reasoning model writes long paragraphs, and left to wrap from
/// there; only a sentence past thirty words is cut, at a clause end. Never every fourteen words, which the review saw
/// leave stubs like "and the" as lines of their own. The last line is the tail under the pen. `thoughtLines`.
List<String> thoughtLines(String thought) => _joinShort(_sentencesOf(thought).expand((piece) => _wordsIn(piece) <= _wordsAThoughtLine ? [piece] : piece.split(_clauseEnd)));

final RegExp _what = RegExp(r'"what"\s*:\s*"((?:[^"\\]|\\.)*)"');
final RegExp _openWhat = RegExp(r'"what"\s*:\s*"((?:[^"\\]|\\.)*)$');

String _unescaped(String raw) {
  try {
    return jsonDecode('"$raw"') as String;
  } on FormatException {
    return raw;
  }
}

/// The model's findings as it writes them: every complete "what" string in the JSON so far, unescaped, and the one
/// still open under the pen, so a finding's words type in as the model writes them and the JSON itself never shows.
/// `findingsSoFar`.
({List<String> done, String? open}) findingsSoFar(String json) {
  final done = <String>[];
  var last = 0;
  for (final match in _what.allMatches(json)) {
    done.add(_unescaped(match[1] ?? ''));
    last = match.end;
  }
  final open = _openWhat.firstMatch(json.substring(last));
  return (done: done, open: open != null ? _unescaped(open[1] ?? '') : null);
}

/// The lines of [texts] numbered from [from].
List<FeedLine> _numbered(List<String> texts, [int from = 0, bool strong = false]) => [for (var i = 0; i < texts.length; i += 1) FeedLine(at: from + i, text: texts[i], strong: strong)];

int? _lastOf(List<FeedLine> lines) => lines.isNotEmpty ? lines.length - 1 : null;

/// How far through its prompt a reading run is, 0 to 1, or null before the first tick (ai/words.dart `progressOf`).
double? _shareRead(FeedRun run) => run.promptTokens != 0 ? math.min(1.0, run.promptTokensDone / run.promptTokens) : null;

/// `feedOf`. [heard] is every phrase the fast model heard, in order, as the recorder handed them over; [body] is the
/// note as the prompt read it.
Feed feedOf({required ReviewStage? stage, required FeedRun? run, required String heard, required String body}) {
  final phrases = phrasesOf(heard);
  final transcript = _numbered(phrases);

  // The stages, and a run not yet reading: the transcript, the head placed at the listen's share of it.
  if (stage != null || run == null || run.phase == RunPhase.queued || run.phase == RunPhase.loading) {
    if (transcript.isEmpty) return const Feed(lines: <FeedLine>[], current: null, mode: FeedMode.transcript);
    final percent = stage?.percent;
    if (stage?.what == 'Listening again' && percent != null) {
      // A placement, not the model's position: the careful model reports a percent and never its words.
      return Feed(lines: transcript, current: math.min(transcript.length - 1, (percent / 100 * transcript.length).floor()), mode: FeedMode.transcript);
    }
    return Feed(lines: transcript, current: _lastOf(transcript), mode: FeedMode.transcript);
  }

  // Reading the prompt: the phrases again from the top, then the note's lines, at the run's share of its prompt.
  if (run.phase == RunPhase.prefill) {
    final lines = [...transcript, ..._numbered(noteLines(body), transcript.length)];
    if (lines.isEmpty) return Feed(lines: lines, current: null, mode: FeedMode.reading);
    // A placement: the prompt holds more between the transcript and the note than is scrolled here.
    final share = _shareRead(run) ?? 0;
    return Feed(lines: lines, current: math.min(lines.length - 1, (share * lines.length).floor()), mode: FeedMode.reading);
  }

  // Writing, other kinds: prose as it lands, the partial line under the pen.
  if (run.kind != RunKind.review) {
    final texts = run.partial.isNotEmpty ? [...run.lines, run.partial] : [...run.lines];
    final lines = _numbered(texts);
    return Feed(lines: lines, current: _lastOf(lines), mode: FeedMode.prose);
  }

  final thought = _numbered(thoughtLines(run.thought));
  // Thinking: the thought wrapped by sentence, the tail the line under the pen.
  if (run.lines.isEmpty && run.partial.isEmpty) return Feed(lines: thought, current: _lastOf(thought), mode: FeedMode.thought);

  // Writing: the thought stays, dimmed, and under it each thing found so far, the open one typing in.
  final so = findingsSoFar(run.lines.join('\n') + run.partial);
  final found = _numbered(so.done, thought.length, true);
  final open = so.open;
  final lines = [...thought, ...found, if (open != null) FeedLine(at: thought.length + found.length, text: open, strong: true)];
  return Feed(lines: lines, current: _lastOf(lines), mode: FeedMode.findings);
}

/// How many lines before the current one the reading modes keep on the screen; the rest of the window comes after it.
const int _before = 16;

/// The lines the screen holds: in the reading modes a window round the current line, sixteen before it and the rest
/// after (seven, of twenty-four); in the streaming modes the last [paneLines], newest at the bottom. `paneWindow`.
List<FeedLine> paneWindow(Feed feed, [int size = paneLines]) {
  final lines = feed.lines;
  final current = feed.current;
  if (lines.length <= size) return lines;
  if ((feed.mode == FeedMode.transcript || feed.mode == FeedMode.reading) && current != null) {
    final from = math.max(0, math.min(current - _before, lines.length - size));
    return lines.sublist(from, from + size);
  }
  return lines.sublist(lines.length - size);
}
