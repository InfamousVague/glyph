/// The sheet an "Out of date?" mark opens (docs/CONTRADICTIONS.md, "What the person sees"; Matt, 2026-11-02: "flags the
/// stale one inline, 'superseded by …'"): the newer note's title and words, what disagrees, and three rows: Open the
/// newer note, Mark superseded, Not a conflict.
///
/// Mark superseded writes through the open note's editor ([NoteEditing.replaceLine]), so it is one undo step and saves
/// as typing does: the stale line, then `> Superseded by [[Newer]] (day): “…”` under it (findings.dart
/// [supersededLine]). Drawn in the app's overlay as the cost question is (lib/activity/activity_cost.dart).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ai/contradictions/findings.dart';
import '../../ai/contradictions/runner.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../types.dart' show NoteEditing;
import 'contradictions.dart' show contradictionOpenNote;

/// Writes [finding]'s superseded line under its stale line in the open note, and settles it; false where the line is
/// not there any more (edited since), which is said on the note.
Future<bool> markSupersededIn(NoteEditing editing, Finding finding, ContradictionRunner runner, {DateTime? now}) async {
  final at = lineOfQuote(editing.body(), finding.olderQuote);
  final written = at != null && editing.replaceLine((text, line) => line == at, (text) => '$text\n${supersededLine(finding, text, now ?? DateTime.now())}');
  if (!written) {
    editing.say('That line has changed since, so nothing was marked.');
    return false;
  }
  await runner.superseded(finding);
  return true;
}

/// Opens the sheet for [finding] over the app; answers when it is put away.
Future<void> showContradictionSheet(BuildContext context, Finding finding, {required ContradictionRunner runner, NoteEditing? editing, void Function(String noteId)? openNote}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value();
  final shut = Completer<void>();
  late final OverlayEntry entry;
  void close() {
    if (shut.isCompleted) return;
    entry.remove();
    shut.complete();
  }

  entry = OverlayEntry(builder: (_) => ContradictionSheet(finding: finding, runner: runner, editing: editing, openNote: openNote ?? contradictionOpenNote, onClose: close));
  overlay.insert(entry);
  return shut.future;
}

class ContradictionSheet extends StatelessWidget {
  const ContradictionSheet({super.key, required this.finding, required this.runner, this.editing, this.openNote, required this.onClose});

  final Finding finding;
  final ContradictionRunner runner;
  final NoteEditing? editing;
  final void Function(String noteId)? openNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final newer = finding.newerTitle.trim().isEmpty ? 'A newer note' : finding.newerTitle.trim();
    final open = openNote;
    return Sheet(
      key: const ValueKey('contradiction-sheet'),
      label: 'May be out of date',
      onClose: onClose,
      children: [
        SheetTitle.text('May be out of date'),
        SheetNote('This line says “${finding.olderQuote}”. $newer says “${finding.newerQuote}”.'),
        if (finding.what.trim().isNotEmpty) SheetNote(finding.what.trim()),
        SheetGroup(
          children: [
            if (open != null)
              SheetRow(
                key: const ValueKey('contradiction-open'),
                label: 'Open $newer',
                onPress: () {
                  onClose();
                  open(finding.newerId);
                },
              ),
            SheetRow(
              key: const ValueKey('contradiction-superseded'),
              label: 'Mark superseded',
              hint: 'Writes “Superseded by [[$newer]]” under this line',
              onPress: () {
                onClose();
                final editing = this.editing;
                unawaited(editing != null ? markSupersededIn(editing, finding, runner) : runner.markSuperseded(finding));
              },
            ),
            SheetRow(
              key: const ValueKey('contradiction-dismiss'),
              label: 'Not a conflict',
              hint: 'It won’t be shown again',
              onPress: () {
                onClose();
                unawaited(runner.dismiss(finding));
              },
            ),
          ],
        ),
      ],
    );
  }
}
