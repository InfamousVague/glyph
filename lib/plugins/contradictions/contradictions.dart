/// The contradiction finder (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder: spots when a newer note
/// disagrees with an older one … and flags the stale one inline, 'superseded by …', so old notes stop misleading you or
/// the AI"). Off until added in the Market.
///
/// Where it shows:
/// - **The older note's line**: a quiet "Out of date?" at its end, the registry's line words (`suggest`, drawn by
///   lib/editor/items/suggestions.dart), never written into the note. Pressed, it opens the sheet
///   (contradiction_sheet.dart): what the newer note says, Open it, Mark superseded, Not a conflict.
/// - **Its page in Settings** (contradictions_pane.dart): when it runs, Check now, and what may be out of date.
/// - **The home page**: one quiet line while anything may be out of date (contradictions_notice.dart).
///
/// The run and the findings are lib/ai/contradictions/; the app's root makes the [ContradictionRunner] and puts it here
/// ([contradictionRunner]), with how to open a note ([contradictionOpenNote]).
library;

import 'package:flutter/foundation.dart';

import '../../ai/contradictions/findings.dart';
import '../../ai/contradictions/runner.dart';
import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'contradiction_sheet.dart';
import 'contradictions_pane.dart';
import 'manifest.dart';

export 'contradiction_sheet.dart';
export 'contradictions_notice.dart';
export 'contradictions_pane.dart';
export 'manifest.dart' show manifest;

/// The app's finder, once the root has made it; null before, and in a test that makes none.
final ValueNotifier<ContradictionRunner?> contradictionRunner = ValueNotifier<ContradictionRunner?>(null);

/// How the app opens a note by its id: the root's. Null where nothing can (a test).
void Function(String noteId)? contradictionOpenNote;

/// The word at the end of a stale line.
const String outOfDateWord = 'Out of date?';

/// The marks for [body] of [noteId]: one a line, at the line that holds an open finding's older words.
List<Suggestion> contradictionMarks(String noteId, String body, {ContradictionRunner? runner}) {
  final finder = runner ?? contradictionRunner.value;
  if (finder == null) return const [];
  final lines = <int>{};
  return [
    for (final finding in finder.openOn(noteId))
      if (lineOfQuote(body, finding.olderQuote) case final line? when lines.add(line))
        Suggestion(
          line: line,
          label: outOfDateWord,
          busyLabel: outOfDateWord,
          run: (editing) async {},
          open: (context, editing) => showContradictionSheet(context, finding, runner: finder, editing: editing),
        ),
  ];
}

const List<SettingsFindable> contradictionsFindable = [
  SettingsFindable('Check for contradictions', 'contradiction finder out of date superseded stale newer older note check now'),
  SettingsFindable('When it checks', 'schedule nightly when a note is saved off'),
  SettingsFindable('How sure', 'confidence threshold'),
  SettingsFindable('Organization notes', 'team org organization within each folder'),
];

String _summary() {
  final runner = contradictionRunner.value;
  if (runner == null) return 'Off';
  final stale = runner.staleNotes;
  if (stale > 0) return stale == 1 ? '1 note may be out of date' : '$stale notes may be out of date';
  return runner.settings.schedule.label;
}

final GlyphPlugin contradictionsPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'replace',
  settings: PluginSettings(pane: (context) => const ContradictionsPane(), hue: 'slate', settings: contradictionsFindable, summary: _summary),
  suggest: (noteId, body) => contradictionMarks(noteId, body),
);
