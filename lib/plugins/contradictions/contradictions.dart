/// The contradiction finder (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder: spots when a newer note
/// disagrees with an older one … and flags the stale one inline, 'superseded by …', so old notes stop misleading you or
/// the AI"). Off until added in the Market.
///
/// Where it shows:
/// - **The older note's line**: the one "May be out of date" mark it shares with Note decay alerts (Matt, 2026-11-02:
///   "Yes, fold them"; lib/plugins/out_of_date/), never written into the note. Its sheet says what the newer note says,
///   with Open it, Mark superseded and Not a conflict under it (contradiction_sheet.dart writes the superseded line); a
///   line Note decay alerts flags too has one chip, and the sheet lists both.
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
import '../out_of_date/out_of_date.dart';
import '../registry.dart' show pluginOn;
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

/// The marks for [body] of [noteId], one a line, at the line that holds an open finding's older words: its reason what
/// the newer note says, its actions Open, Mark superseded and Not a conflict.
List<OutOfDateMark> contradictionMarks(String noteId, String body, {ContradictionRunner? runner}) {
  final finder = runner ?? contradictionRunner.value;
  if (finder == null) return const [];
  final lines = <int>{};
  final open = contradictionOpenNote;
  return [
    for (final finding in finder.openOn(noteId))
      if (lineOfQuote(body, finding.olderQuote) case final line? when lines.add(line))
        () {
          final newer = finding.newerTitle.trim().isEmpty ? 'A newer note' : finding.newerTitle.trim();
          return OutOfDateMark(
            source: manifest.id,
            id: finding.key,
            // lineOfQuote counts from 1; the mark from 0.
            line: line - 1,
            reason: '$newer says “${finding.newerQuote}”',
            detail: finding.what.trim().isEmpty ? null : finding.what.trim(),
            actions: [
              if (open != null) OutOfDateAction(key: 'contradiction-open', label: 'Open $newer', run: (_) => open(finding.newerId)),
              OutOfDateAction(
                key: 'contradiction-superseded',
                label: 'Mark superseded',
                hint: 'Writes “Superseded by [[$newer]]” under this line',
                run: (use) => switch (use.editing) { final editing? => markSupersededIn(editing, finding, finder), null => finder.markSuperseded(finding) },
              ),
              OutOfDateAction(key: 'contradiction-dismiss', label: 'Not a conflict', hint: 'It won’t be shown again', run: (_) => finder.dismiss(finding)),
            ],
          );
        }(),
  ];
}

/// The finder as a source of the one mark, while its plugin is on and the root has made it.
final OutOfDateSource contradictionsOutOfDate = OutOfDateSource(
  id: manifest.id,
  on: () => pluginOn(manifest) && contradictionRunner.value != null,
  marks: (noteId, body) => contradictionMarks(noteId, body),
);

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
);
