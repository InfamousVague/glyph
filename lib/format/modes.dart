/// What the model can do to a note: the three asks behind the robot button. A port of `src/app/format/modes.ts`.
///
/// Matt: "add more features around the AI in addition to format, I want a summarize and an enhance; make all of
/// these buttons instead of the segmented toggle, make a robot drop-down button for these options". Each mode is one
/// prompt (format/prompt.dart) and one output budget, and the same run machine as every other kind (ai/runs.dart);
/// the note's cog lists them.
///
/// They are the first three kinds of run, and their words are the kinds' own (ai/kinds.dart). This module names the
/// three as a set: the set the older prompts and budgets serve.
///
/// What differs: the web's `Mode` is the type of three of `RunKind`'s words, which Dart cannot say of an enum's
/// values; [Mode] is another name for [RunKind], [isMode] says whether a kind is one of the three, and whatever takes
/// a mode treats any other kind as Format. ai/kinds.dart is exported, so a caller of a mode has `RunKind` to hand.
library;

import '../ai/kinds.dart';

export '../ai/kinds.dart' show KindWords, RunKind;

/// A mode: [RunKind.format], [RunKind.summarize] or [RunKind.enhance] (`Mode`).
typedef Mode = RunKind;

const Set<RunKind> _ids = {RunKind.format, RunKind.summarize, RunKind.enhance};

/// Whether [kind] is one of the three modes.
bool isMode(RunKind kind) => _ids.contains(kind);

/// The three, in the order the cog shows them: Format, Summarize, Enhance (`MODES`).
final List<KindWords> modes = List.unmodifiable(kinds.where((kind) => _ids.contains(kind.id)));
