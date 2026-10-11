/// The review after a recording, folded into the note (Matt): Stop opens the note, the strip says what the slower
/// models are doing, and each thing they find lands in the note as a tracked change with Keep and Revert, instead of
/// a screen of cards to decide on first. A port of `src/app/ai/review.ts`. The pure parts live here; what runs the
/// stages is ai/note_review.dart, and the prompt, the findings' reading and the word diff are ai/support/review_*.
///
/// What differs:
/// - `ReviewHandoff` is the recorder's own class (lib/capture/recorder.dart), which was ported first; this file
///   hands it on under the page's path.
/// - `simulatingReview()` asked the browser's address for `?review`. There is no address here: it is
///   [simulatingReview], false unless a gallery or a test sets it, and `isTauri()` is the engine being there.
/// - The page's `EditorView` is a [StateCommandTarget].
library;

import '../core/preferences.dart';
import '../editor/marks/wisp_motion.dart' show WispKind, commonEnds, wisp;
import '../editor/state/change.dart';
import '../editor/state/state.dart';
import 'ai_changes.dart';
import 'backend.dart';
import 'support/review_diff.dart';
import 'support/review_findings.dart';

export '../capture/recorder.dart' show ReviewHandoff;

/// The binary generation whose model can think out loud (`ai_generate` `think`).
const int reviewGeneration = 13;

/// `?review` in a browser: the review runs with its models played by a script (listening again turns "seat" into
/// "seek", the thinking streams a canned thought), so the flow can be tried without a phone. Here a gallery's or a
/// test's to switch on.
bool Function() simulatingReview = _notSimulating;
bool _notSimulating() => false;

/// Whether this binary can run the review: an older one saves as it always did, and never shows it
/// (`reviewAvailable`).
Future<bool> reviewAvailable() async {
  if (simulatingReview()) return true;
  if (!aiBackend.available || !preferences.value.review) return false;
  return hasNativeGeneration(reviewGeneration);
}

/// The model to think with: the one chosen for formatting if it reasons and is here, else the largest Qwen here
/// (`thinkingModel`).
Future<String?> thinkingModel() async {
  List<ModelInfo> all;
  try {
    all = await listModels();
  } catch (_) {
    all = const <ModelInfo>[];
  }
  final present = [for (final m in all) if (m.present) m];
  final chosen = preferences.value.formatModel;
  if (present.any((m) => m.id == chosen) && chosen.startsWith('qwen')) return chosen;
  ModelInfo? qwen;
  for (final m in present) {
    // The largest, and of two the same size the first, as a stable sort leaves them.
    if (m.id.startsWith('qwen') && (qwen == null || m.bytes > qwen.bytes)) qwen = m;
  }
  if (qwen != null) return qwen.id;
  for (final m in present) {
    if (m.id == chosen) return m.id;
  }
  return null;
}

final RegExp _closingStops = RegExp(r'[.,;:!?]+$');

/// A phrase as it is looked for in the note and put in its place: a speech model ends a phrase with the stop it
/// heard, and the note may have carried on after the word (`unpunctuated`).
String unpunctuated(String phrase) => phrase.replaceFirst(_closingStops, '');

/// What a words finding says: the careful model's words, not the ones the note has (`heardAs`).
String heardAs(String careful, String found) => '“$careful”, not “$found”';

/// Without a model to think, the careful model's words alone: each change the note still has, offered as it heard it
/// (`wordsOnly`).
List<Finding> wordsOnly(List<WordChange> changes, NoteText note) {
  final out = <Finding>[];
  for (final (i, change) in changes.indexed) {
    if (change.heard.isEmpty || change.careful.isEmpty) continue;
    final find = locate(note.body, unpunctuated(change.heard));
    if (find == null || find.isEmpty) continue;
    final replace = unpunctuated(change.careful);
    out.add(
      Finding(
        id: 'w$i',
        check: Check.words,
        what: heardAs(replace, find),
        why: 'The slower speech model heard it this way.',
        noteId: note.id,
        noteTitle: note.title,
        change: ReplaceChange(find: find, replace: replace),
      ),
    );
  }
  return out;
}

final RegExp _trailingNewline = RegExp(r'\n$');

/// A finding as an edit on the note as it now reads: where the words are, what goes in their place, and the change
/// record that marks it (`findingEdit`). Null for a finding whose words are no longer there.
({int from, int to, String insert, AiChange record})? findingEdit(String body, Finding finding, String runId, String id) {
  final change = finding.change;
  if (change is ReplaceChange) {
    final at = locateLast(body, change.find);
    if (at == null) return null;
    final replace = change.replace;
    final block = at.text.contains('\n') || replace.contains('\n');
    return (
      from: at.index,
      to: at.index + at.text.length,
      insert: replace,
      record: AiChange(id: id, runId: runId, from: at.index, to: at.index + replace.length, removed: at.text, block: block),
    );
  }
  final next = addLine(body, (change as AddChange).line);
  if (next == body) return null;
  final ends = commonEnds(body, next);
  final insert = next.substring(ends.prefix, next.length - ends.suffix);
  return (
    from: ends.prefix,
    to: body.length - ends.suffix,
    insert: insert,
    record: AiChange(
      id: id,
      runId: runId,
      from: ends.prefix,
      to: ends.prefix + insert.replaceFirst(_trailingNewline, '').length,
      removed: body.substring(ends.prefix, body.length - ends.suffix),
      block: true,
    ),
  );
}

/// The findings for the note on screen, into its editor one by one as tracked changes, each on the note as the one
/// before left it (`landFindings`). Answers how many landed.
int landFindings(StateCommandTarget view, List<Finding> findings, String runId, {required bool wisp}) {
  var landed = 0;
  for (final (n, finding) in findings.indexed) {
    final edit = findingEdit(view.state.doc.toString(), finding, runId, '$runId-f$n');
    if (edit == null) continue;
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: edit.from, to: edit.to, insert: edit.insert),
        effects: addAiChanges.of([edit.record]),
        annotations: <Annotation<Object?>>[aiEdit.of(AiEdit.land), if (wisp) _wisp.of(WispKind.rewrite)],
        userEvent: 'ai.land',
      ),
    );
    landed += 1;
  }
  return landed;
}

// The annotation, under a name the `wisp` argument above does not hide.
final AnnotationType<WispKind> _wisp = wisp;
