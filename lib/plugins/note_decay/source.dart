/// Note decay alerts as a source of the one "May be out of date" mark (lib/plugins/out_of_date/; Matt, 2026-11-02:
/// "Yes, fold them", of this plugin's chip and the Contradiction finder's "Out of date?" word): each signal a reason on
/// its line, or at the page's head, with Update with AI and Still right under it.
library;


import '../out_of_date/out_of_date.dart';
import 'decay.dart';
import 'manifest.dart' show noteDecayId;
import 'sheets.dart';

/// The line of [lines] (from 0) whose words are [quote], nearest [near]; null where none is: a reason found again by its
/// line's words, so lines typed above move it and a line edited away takes it along.
int? decayLineOf(List<String> lines, String quote, int? near) {
  if (quote.isEmpty) return null;
  int? best;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != quote) continue;
    if (best == null || (near != null && (i - near).abs() < (best - near).abs())) best = i;
  }
  return best;
}

/// The marks [decay] gives [noteId] as [body] reads.
List<OutOfDateMark> decayMarks(NoteDecay decay, String noteId, String body) {
  final lines = body.split('\n');
  final model = decay.model;
  return [
    for (final signal in decay.signalsFor(noteId, body: body))
      if (signal.line == null || decayLineOf(lines, signal.quote, signal.line) != null)
        OutOfDateMark(
          source: noteDecayId,
          id: signal.token,
          line: signal.line == null ? null : decayLineOf(lines, signal.quote, signal.line),
          reason: signal.reason,
          actions: [
            OutOfDateAction(
              key: 'decay-update',
              label: 'Update with AI',
              hint: model.ready ? 'Asks ${model.name} for the edit; nothing changes until you accept it' : 'Connect an AI in Settings › AI first',
              disabled: !model.ready,
              run: (use) => use.context.mounted ? updateWithAi(use.context, use.view, decay: decay, noteId: noteId, signals: [signal]) : null,
            ),
            OutOfDateAction(key: 'decay-still-right', label: 'Still right', hint: 'Keeps this away until it changes again', run: (use) => stillRight(use.view, [signal])),
          ],
        ),
  ];
}

/// The source, over the app's [noteDecay] unless [decay] says.
OutOfDateSource decayOutOfDate({NoteDecay? Function()? decay}) {
  NoteDecay? of() => decay != null ? decay() : noteDecay;
  return OutOfDateSource(
    id: noteDecayId,
    on: () => of()?.on ?? false,
    marks: (noteId, body) => switch (of()) { final d? => decayMarks(d, noteId, body), null => const [] },
  );
}
