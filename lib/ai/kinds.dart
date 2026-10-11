/// What the AI can do to a note: the kinds of run. A port of `src/app/ai/kinds.ts`.
///
/// The robot had three (format/modes.dart: Format, Summarize, Enhance), which the More sheet still runs. A spoken
/// instruction adds three more a person reaches for daily (fix the spelling, make a shape of it, carry on writing)
/// and a free-text Ask for everything else (ai/instruction.dart). The review after a recording is a kind too, and so
/// are the blanks a note asks the AI to fill (ai/fills/queue.dart). Each kind is a set of words the screen says; its
/// prompt and budget live with the prompts (format/prompt.dart, ai/prompts.dart), and the run itself is the same
/// machine for all of them (ai/runs.dart).
///
/// What differs: `RunKind` is an enum whose [RunKind.id] is the web's word, since `continue` is not a name Dart
/// allows; what is kept on the device and sent anywhere is the id.
library;

import 'package:flutter/foundation.dart';

/// A kind of run (`RunKind`).
enum RunKind {
  format('format'),
  summarize('summarize'),
  enhance('enhance'),
  fix('fix'),
  shape('shape'),
  continueWriting('continue'),
  ask('ask'),
  review('review'),
  fill('fill');

  const RunKind(this.id);

  /// The web's word for it, which is what is stored.
  final String id;

  /// The kind with this id, or null for a word this build does not know.
  static RunKind? of(Object? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// The words a kind is said in (`KindWords`).
@immutable
class KindWords {
  const KindWords({required this.id, required this.label, required this.hint, required this.doing, required this.done});

  final RunKind id;

  /// Its name, in the menu and the log.
  final String label;

  /// What it does, under the word.
  final String hint;

  /// "Formatting with Qwen 4B": the verb while it runs.
  final String doing;

  /// "Formatted by Qwen 4B": once it has.
  final String done;
}

/// `KINDS`.
const List<KindWords> kinds = [
  KindWords(id: RunKind.format, label: 'Format', hint: 'Tidy and organise, keeping every word that matters.', doing: 'Formatting', done: 'Formatted'),
  KindWords(id: RunKind.summarize, label: 'Summarize', hint: 'The point of the note and its tasks, in far fewer words.', doing: 'Summarizing', done: 'Summarized'),
  KindWords(id: RunKind.enhance, label: 'Enhance', hint: 'Every thought finished and the note made fuller, without inventing.', doing: 'Enhancing', done: 'Enhanced'),
  KindWords(id: RunKind.fix, label: 'Fix spelling', hint: 'Spelling, grammar and punctuation, and not a word more.', doing: 'Fixing', done: 'Fixed'),
  KindWords(id: RunKind.shape, label: 'Make a list', hint: 'Tasks, a list or a table out of what is there.', doing: 'Shaping', done: 'Shaped'),
  KindWords(id: RunKind.continueWriting, label: 'Continue', hint: 'Carries on from the last line in the note’s own voice.', doing: 'Writing', done: 'Written'),
  KindWords(id: RunKind.ask, label: 'Ask', hint: 'Whatever you tell it to do with the note.', doing: 'Working', done: 'Done'),
  KindWords(id: RunKind.review, label: 'Review', hint: 'Listens again with the careful model and checks what was heard.', doing: 'Reviewing', done: 'Reviewed'),
  // Blanks the AI fills (docs/DESIGN.md §145): the questions written {?like this}, answered where they stand.
  KindWords(id: RunKind.fill, label: 'Fill the blanks', hint: 'Answers the questions written {?like this}.', doing: 'Filling', done: 'Filled'),
];

/// `kindWords`.
KindWords kindWords(RunKind kind) => kinds.firstWhere((k) => k.id == kind, orElse: () => kinds.first);
