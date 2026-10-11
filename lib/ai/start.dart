/// A run asked for on the note on screen: what the model is given, and where its lines will land. A port of
/// `src/app/ai/start.ts`.
///
/// The landing is decided here, before the model has read a word, and written into the editor (ai/ai_changes.dart
/// `setLanding`), so the person's typing while it loads moves the bookmark with it. A rewrite - Format, Enhance,
/// Fix, Make a list, Ask - lands over the words it was given, the whole note; a summary lands above the note (Matt,
/// 29d: a summary belongs on top); Continue lands under it. The front matter is never the model's: a rewrite starts
/// after it, and the model is given the words alone.
///
/// A RECORDING'S SUMMARY is the one run whose landing is not its kind's (docs/DESIGN.md §127 section 2). It is given
/// the tape's words, not the note's, and lands under the title as the section ai/summary_text.dart owns: at the
/// section's place when the note has none, or over the old section when it does, as tracked changes with Keep and
/// Revert. The model's answer is shaped as it streams (`restore`), so the heading it opens with never lands and the
/// section only ever grows; the ticked to-dos of the old section are carried in as it finishes; a note still
/// wearing a meeting's date title takes the model's heading once the run is done, and a note with no words at all
/// gets it as a `# title` line above the section. A section the person edited is not written over unless they asked
/// for that (`replace`): the strip asks first (tapes/note_tape.dart). When the queue already has the model's answer
/// (the note was opened while a closed note's generation ran), the section is landed at once, the same way, with no
/// run.
///
/// What differs:
/// - The page's `EditorView` is a [StateCommandTarget], as the lander's is.
/// - `startNoteRun`'s two overloads are two functions: [startNoteRun] for a kind, which answers a [Started], and
///   [startRecordingRun] for a recording's summary, which answers a [SummaryStarted]. The page told them apart by
///   `options.recording`.
/// - The handle the note is signed with (`accountState().session?.handle`) is asked of [noteOwner], which the app's
///   root sets once it has an account; until then the AI signs with nobody beside it.
/// - The run is asked of [noteRunStarter], which is ai/runs.dart's `startRun` unless a test says.
library;

import 'dart:async';
import 'dart:math' as math;

import '../core/front_matter.dart' show frontMatterOffset;
import '../core/item_syntax.dart' show jsTrim;
import '../editor/marks/wisp_motion.dart' show commonEnds;
import '../editor/state/change.dart';
import '../editor/state/state.dart';
import '../format/pipeline.dart';
import '../format/prompt.dart' show recordingSummaryPrompt, temperature;
import 'ai_changes.dart';
import 'available.dart';
import 'kinds.dart';
import 'land.dart';
import 'log.dart';
import 'prompts.dart';
import 'runs.dart';
import 'summary_ask.dart';
import 'summary_keep.dart';
import 'summary_text.dart';
import 'support/authors.dart';

/// A run to follow, or why it could not start (`Started`).
sealed class Started {
  const Started();

  bool get ok;
}

/// `{ ok: true, handle }`.
final class StartedRun extends Started {
  const StartedRun(this.handle);

  final RunHandle handle;

  @override
  bool get ok => true;
}

/// `{ ok: false, reason }`.
final class NotStarted extends Started {
  const NotStarted(this.reason);

  final String reason;

  @override
  bool get ok => false;

  @override
  bool operator ==(Object other) => other is NotStarted && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'NotStarted($reason)';
}

/// The handle this device is signed in with, or null (`accountState().session?.handle`). The app's root sets it.
String? Function() noteOwner = _nobody;
String? _nobody() => null;

/// Asks for a run (ai/runs.dart `startRun`). A test's own stands in for it.
RunHandle Function(RunRequest request) noteRunStarter = startRun;

/// Where a kind's lines go: over the words it was given, above the note, or under it (`placementOf`).
Placement placementOf(RunKind kind) {
  if (kind == RunKind.summarize) return Placement.prepend;
  if (kind == RunKind.continueWriting) return Placement.append;
  return Placement.replace;
}

/// Where a run's lines land in a note [length] long, given the part it works on: over that part for a rewrite, at
/// its start - after the front matter - for a summary, and at the very end for a continuation (`landingAt`). Decided
/// when the run is asked for, and again, the same way, for a note opened while its run is on (ai/note_landing.dart).
/// A run that carries a placement of its own (a recording's summary, over its scope) is landed by that rather than
/// its kind's.
({int start, int cursor, int oldEnd}) landingAt(RunKind kind, RunScope scope, int length, [Placement? placement]) {
  final placed = placement ?? placementOf(kind);
  final at = placed == Placement.append ? length : math.min(scope.from, length);
  return (start: at, cursor: at, oldEnd: placed == Placement.replace ? math.min(scope.to, length) : at);
}

LandingSpot _spot(String runId, ({int start, int cursor, int oldEnd}) at) => LandingSpot(runId: runId, start: at.start, cursor: at.cursor, oldEnd: at.oldEnd);

/// Asks for a run of [kind] on the note in [view] (`startNoteRun`). [instruction] is the words the person gave, for
/// a kind that takes some.
Started startNoteRun(StateCommandTarget view, String noteId, RunKind kind, Availability availability, {String? instruction}) {
  if (!availability.ok) return NotStarted(availability.reason!);
  final body = view.state.doc.toString();
  final front = frontMatterOffset(body);
  final scope = RunScope(from: front, to: body.length);
  final source = body.substring(front);
  if (jsTrim(source).isEmpty) return const NotStarted('Nothing in the note yet.');
  final trimmed = instruction == null ? '' : jsTrim(instruction);
  final said = trimmed.isEmpty ? null : trimmed;
  if (kind == RunKind.ask && said == null) return const NotStarted('Say what to do with the note.');
  // Continue writes only what comes next, so nothing it leaves out is lost: restored as a summary is, a blank, fill,
  // table or picture it does not repeat is not added again at the note's end (the review of §145 found every blank
  // and answer doubled under a continuation).
  final prepared = prepareNote(source, kind == RunKind.summarize || kind == RunKind.continueWriting ? RunKind.summarize : RunKind.format);
  final text = prepared.prompt;
  final prompt = kind == RunKind.ask && said != null ? askMessage(said, text) : text;
  final context = noteContext(noteId);
  final handle = noteRunStarter(
    RunRequest(
      noteId: noteId,
      kind: kind,
      instruction: said,
      model: availability.model!,
      system: promptForKind(kind),
      context: context == null || context.isEmpty ? null : context,
      prompt: prompt,
      maxTokens: budgetForKind(kind, text.length),
      temperature: temperature,
      restore: prepared.restore,
      hash: noteHash(noteId, body),
      scope: scope,
    ),
  );
  // After the run is asked for: an earlier run on this note ended by it may still put its own bookmark away, and
  // this one is the newer, so it wears the run's id (ai/ai_changes.dart `Landing.runId`).
  view.dispatch(TransactionSpec(effects: setLanding.of(_spot(handle.id, landingAt(kind, scope, body.length)))));
  return StartedRun(handle);
}

/// The recording summarised into the note in [view]: the tape's words, from the queue (ai/summaries.dart). The
/// page's `startNoteRun(view, noteId, 'summarize', availability, { recording })`.
SummaryStarted startRecordingRun(StateCommandTarget view, String noteId, Availability availability, SummaryAsk recording) {
  if (!availability.ok) return SummaryRefused(availability.reason!);
  return _startRecordingSummary(view, noteId, availability.model!, recording);
}

/// The recording's summary as a run in the note: the section's place or the old section as the scope, the answer
/// shaped as it streams, and the title taken at the end where the note still wears a date. Answers 'edited' for a
/// section that is no longer the app's when nobody asked to replace it, and 'nothing' for a tape with no words. With
/// the answer already in hand (`ask.text`), the section is landed at once and answered as landed.
SummaryStarted _startRecordingSummary(StateCommandTarget view, String noteId, String fallbackModel, SummaryAsk ask) {
  if (jsTrim(ask.words).isEmpty) return const SummaryRefused('nothing');
  final body = view.state.doc.toString();
  final section = summarySection(body, keptText(noteId));
  if (section != null && !ask.replace && !summaryUnchanged(noteId, section.text)) return const SummaryRefused('edited');
  final RunScope scope;

  // A blank line lands first when the line above the section is words: the title, or a paragraph.
  var blankFirst = false;
  // Over the old section, its newline included: the lander would otherwise take its last line for the note's and
  // put a newline after it, one more blank line under the section at every remake.
  if (section != null) {
    scope = RunScope(from: section.start, to: section.end < body.length && body[section.end] == '\n' ? section.end + 1 : section.end);
  } else {
    final place = summaryPlace(body);
    // A section that ran straight into the paragraph under it would make that paragraph the last item's; a blank
    // line goes in first, so the section stands on its own. The run's lines land before it.
    if (place < body.length && body[place] != '\n') {
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: place, insert: '\n'), annotations: aiEdit.of(AiEdit.land)));
    }
    scope = RunScope(from: place, to: place);
    blankFirst = place > 0 && body.substring(math.max(0, place - 2), place) != '\n\n';
  }
  final kept = section?.text ?? '';

  // No words in the note: the section's own heading would be its title, so the model's heading goes above it.
  final untitled = !hasWords(body);
  String? title;
  String restore(String text, bool isFinal) {
    final shaped = shapeSummary(text);
    if (isFinal) title = shaped.title;
    var out = shaped.section;
    if (isFinal && kept.isNotEmpty && out.isNotEmpty) out = carryTicked(kept, out);
    // The heading only once its line is complete, so a landed title line never changes under the pen.
    final heading = shaped.title;
    if (untitled && out.isNotEmpty && heading != null && heading.isNotEmpty && text.contains('\n')) out = '# $heading\n\n$out';
    return blankFirst && out.isNotEmpty ? '\n$out' : out;
  }

  // The title, once the lines are in, where the note still wears a meeting's date title.
  void retitle() {
    final named = title;
    if (named == null || named.isEmpty) return;
    final now = view.state.doc.toString();
    final next = retitled(now, named);
    if (next == now) return;
    final ends = commonEnds(now, next);
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: ends.prefix, to: now.length - ends.suffix, insert: next.substring(ends.prefix, next.length - ends.suffix)),
        annotations: aiEdit.of(AiEdit.land),
      ),
    );
  }

  final model = ask.model.isEmpty ? fallbackModel : ask.model;
  final ready = ask.text;
  if (ready != null) return SummaryLanded(_landReady(view, noteId, model, scope, restore(ready, true), retitle));
  final context = ask.context;
  final handle = noteRunStarter(
    RunRequest(
      noteId: noteId,
      kind: RunKind.summarize,
      model: model,
      system: recordingSummaryPrompt,
      prompt: context != null && context.isNotEmpty ? '$context\n\n${ask.words}' : ask.words,
      maxTokens: ask.maxTokens,
      temperature: temperature,
      restore: restore,
      hash: noteHash(noteId, body),
      scope: scope,
      placement: Placement.replace,
    ),
  );
  view.dispatch(TransactionSpec(effects: setLanding.of(_spot(handle.id, landingAt(RunKind.summarize, scope, view.state.doc.length, Placement.replace)))));
  // The title, once the lines are in: the landing has finished with the run by the time its future completes, since
  // the store's listeners are told first (ai/note_landing.dart).
  unawaited(
    handle.done.then((state) {
      if (state.phase == RunPhase.done) retitle();
    }),
  );
  return SummaryRun(handle);
}

/// A finished answer landed at once, with no run: the queue had it before the note was opened. The lander lands it
/// over the scope as tracked changes, as a run's lines would land (ai/note_landing.dart), the AI signs it and the
/// log keeps a record of it with the before and after for Undo. Answers the section as it landed, for the keep.
String _landReady(StateCommandTarget view, String noteId, String model, RunScope scope, String text, void Function() retitle) {
  final at = DateTime.now().millisecondsSinceEpoch;
  final runId = 'ready-${at.toRadixString(36)}';
  recordRun(RunRecord(id: runId, noteId: noteId, kind: RunKind.summarize, instruction: null, model: model, at: at, ms: 0, outputTokens: 0, outcome: RunOutcome.done, message: null, truncated: false));
  view.dispatch(TransactionSpec(effects: setLanding.of(_spot(runId, landingAt(RunKind.summarize, scope, view.state.doc.length, Placement.replace)))));
  final before = view.state.doc.toString();
  final lander = Lander(view, runId, const LanderOptions(wisp: false, haptic: false), before);
  final lines = allLines(text);
  lander.land(lines);
  lander.finish(lines);
  retitle();
  final now = view.state.doc.toString();
  final signed = withAuthor(now, aiAuthor, noteOwner());
  if (signed != now) {
    final ends = commonEnds(now, signed);
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: ends.prefix, to: now.length - ends.suffix, insert: signed.substring(ends.prefix, signed.length - ends.suffix)),
        annotations: aiEdit.of(AiEdit.sign),
      ),
    );
  }
  final after = view.state.doc.toString();
  if (after != before) recordChange(noteId, runId, before, after);
  return summarySection(text)?.text ?? '';
}
