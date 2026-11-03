/// Mark superseded, one of the finder's actions in the one "May be out of date" sheet (lib/plugins/out_of_date/;
/// docs/CONTRADICTIONS.md, "What the person sees"; Matt, 2026-11-02: "flags the stale one inline, 'superseded by …'",
/// then "Yes, fold them" for its word and Note decay alerts' chip). It writes through the open note's editor
/// ([NoteEditing.replaceLine]), so it is one undo step and saves as typing does: the stale line, then `> Superseded by [[Newer]] (day): “…”` under it (findings.dart
/// [supersededLine]).
library;

import '../../ai/contradictions/findings.dart';
import '../../ai/contradictions/runner.dart';
import '../types.dart' show NoteEditing;

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
