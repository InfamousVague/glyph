/// What the summary queue hands a note open in its editor, and what the editor answers. The `SummaryAsk`,
/// `SummaryStarted` and `SummaryStarter` of `src/app/ai/summaries.ts`, in a file of their own: the queue
/// (ai/summaries.dart) and the note's run (ai/start.dart) both name them, and neither has to import the other.
///
/// What differs: `SummaryStarted` is a sealed class with the page's three shapes ([SummaryRun], [SummaryLanded],
/// [SummaryRefused]).
library;

import 'package:flutter/foundation.dart';

import 'runs.dart' show RunHandle;

/// What is asked (`SummaryAsk`).
@immutable
class SummaryAsk {
  const SummaryAsk({required this.words, this.context, required this.model, required this.maxTokens, required this.replace, this.text});

  /// The recording's words, or the notes on its parts joined.
  final String words;

  /// The line before the words, when they are notes on the parts of one recording.
  final String? context;
  final String model;
  final int maxTokens;

  /// Replace the section the note has even if it was edited.
  final bool replace;

  /// The model's finished answer, when the queue already has it: landed as it is, the model not asked again.
  final String? text;

  /// This ask with the finished answer in hand (`{ ...ask, text }`).
  SummaryAsk withText(String text) => SummaryAsk(words: words, context: context, model: model, maxTokens: maxTokens, replace: replace, text: text);

  /// This ask, replacing or not (`{ ...ask, replace }`).
  SummaryAsk replacing(bool replace) => SummaryAsk(words: words, context: context, model: model, maxTokens: maxTokens, replace: replace, text: text);

  /// This ask of other words (`{ ...ask, words }`).
  SummaryAsk ofWords(String words) => SummaryAsk(words: words, context: context, model: model, maxTokens: maxTokens, replace: replace, text: text);
}

/// A run in the editor to follow, or the section landed at once from an answer already in hand, or why not
/// (`SummaryStarted`).
@immutable
sealed class SummaryStarted {
  const SummaryStarted();

  /// The page's `ok`.
  bool get ok;
}

/// `{ ok: true, handle }`.
final class SummaryRun extends SummaryStarted {
  const SummaryRun(this.handle);

  final RunHandle handle;

  @override
  bool get ok => true;
}

/// `{ ok: true, landed }`: the section as it landed.
final class SummaryLanded extends SummaryStarted {
  const SummaryLanded(this.landed);

  final String landed;

  @override
  bool get ok => true;

  @override
  bool operator ==(Object other) => other is SummaryLanded && other.landed == landed;

  @override
  int get hashCode => landed.hashCode;

  @override
  String toString() => 'SummaryLanded($landed)';
}

/// `{ ok: false, reason }`: `edited` for a section that is no longer the app's, `nothing` for a tape with no words,
/// or a sentence.
final class SummaryRefused extends SummaryStarted {
  const SummaryRefused(this.reason);

  final String reason;

  @override
  bool get ok => false;

  @override
  bool operator ==(Object other) => other is SummaryRefused && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'SummaryRefused($reason)';
}

/// What the note screen gives the queue for a note it has open: the summary as a run in its editor
/// (`SummaryStarter`; ai/note_ai.dart).
typedef SummaryStarter = SummaryStarted Function(SummaryAsk ask);
