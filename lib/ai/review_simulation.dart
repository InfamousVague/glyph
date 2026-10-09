/// The review's model, played by a script (`?review` in a browser): a thought streamed, then findings from the word
/// changes in the prompt. A port of `src/app/ai/reviewSimulation.ts`. Handed to the engine (ai/runs.dart
/// `simulateRuns`) for the review's run, so the strip, the card and the landing can all be tried without a phone.
///
/// What differs: the wait between two pieces is a `Timer`'s, which a test's clock moves.
library;

import 'dart:async';
import 'dart:convert';

import '../core/text.dart' show escapeRegExp;
import 'backend.dart';
import 'review.dart' show heardAs, unpunctuated;

final RegExp _pair = RegExp(r'\[([^\]]*?) → ([^\]]*?)\]');
final RegExp _saved = RegExp(r'AS SAVED:\n([\s\S]*)$');

/// See the header (`simulatedReview`).
Run simulatedReview(RunOptions options) {
  var cancelled = false;
  final thought = [
    'Thinking Process:',
    '',
    '1. Words. The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right.',
    '2. Structure. The heading names the note, the to-dos are things to do, nothing else looks like a list.',
    '3. Commands. Each spoken command landed where its words said.',
    '4. Names. HelloTrade is written as one word in the note titles.',
  ].join('\n');
  final note = _saved.firstMatch(options.prompt)?.group(1) ?? '';
  final findings = <Map<String, String>>[];
  for (final pair in _pair.allMatches(options.prompt)) {
    final find = unpunctuated(pair.group(1) ?? '');
    final replace = unpunctuated(pair.group(2) ?? '');
    String? line;
    for (final l in note.split('\n')) {
      if (l.toLowerCase().contains(find.toLowerCase())) {
        line = l;
        break;
      }
    }
    if (find.isEmpty || line == null || line.isEmpty) continue;
    findings.add({
      'check': 'words',
      'what': heardAs(replace, find),
      'why': 'The slower speech model heard it this way, and it fits the note.',
      'find': line,
      'replace': line.replaceFirst(RegExp(escapeRegExp(find), caseSensitive: false), replace),
    });
  }
  final text = '<think>\n$thought\n</think>\n\n${jsonEncode(findings)}';
  Future<Output> play() async {
    final started = DateTime.now().millisecondsSinceEpoch;
    for (var at = 0; at <= text.length; at += 6) {
      if (cancelled) throw Exception('cancelled');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      options.onProgress(
        Progress(
          id: 'sim',
          phase: Phase.generating,
          promptTokens: 0,
          promptTokensDone: 0,
          outputTokens: (at / 4).round(),
          tokensPerSecond: 11,
          elapsedMs: DateTime.now().millisecondsSinceEpoch - started,
          partial: text.substring(0, at),
          thinking: true,
        ),
      );
    }
    return Output(
      text: text,
      promptTokens: 0,
      outputTokens: (text.length / 4).round(),
      ms: DateTime.now().millisecondsSinceEpoch - started,
      cachedTokens: 0,
      prefillMs: 0,
      loadMs: 0,
      tokensPerSecond: 11,
      truncated: false,
      thinking: true,
    );
  }

  return Run(done: play(), cancel: () => cancelled = true);
}
