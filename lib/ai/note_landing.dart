/// The note's run, landed: this watches the note's latest run and hands its lines to the lander as they finish,
/// then, when it is done, signs the note with the AI as an author (Matt: the AI is an author; ai/support/authors.dart)
/// and records the words before and after in the log, for Undo. A port of `src/app/ai/useLanding.ts`.
///
/// A run that ended before this note was opened is left alone: its lines are in the note already, or it never wrote
/// any.
///
/// What differs: the hook is a [NoteLanding], made for a note's editor once it has one and disposed of as the note
/// is left or its editor is replaced (the hook's `[run, view, noteId]`). It hears the engine itself
/// (ai/runs.dart `subscribeRuns`), so a line lands in the same turn the engine says it, where the page landed it in
/// the effect after the draw; the words before and after go in the log a moment later, once the engine has written
/// the run's own line there. The options are asked as they are needed, as the hook's ref gave them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../editor/marks/wisp_motion.dart' show commonEnds;
import '../editor/state/change.dart';
import '../editor/state/state.dart';
import 'ai_changes.dart';
import 'kinds.dart';
import 'land.dart';
import 'log.dart';
import 'runs.dart';
import 'start.dart' show landingAt;
import 'support/authors.dart';

/// What a landing is told as it goes (the hook's `options`).
class LandingOptions {
  const LandingOptions({required this.wisp, required this.haptic, required this.owner, this.onDropped});

  /// Whether the lines arrive from smoke, and whether each ticks under the thumb: asked as a run's first line lands.
  final bool Function() wisp;
  final bool Function() haptic;

  /// The handle the note is the person's under, for the signature; null signed out.
  final String? Function() owner;

  /// How many of the model's lines were dropped because the person had written over their place: told once, when
  /// the run has ended.
  final void Function(int count)? onDropped;
}

/// See the header (`useLanding`).
class NoteLanding {
  NoteLanding(this.noteId, this._view, this._options) {
    _stop = subscribeRuns((run) {
      if (run.noteId == noteId) _follow(run);
    });
    final run = runFor(noteId);
    if (run != null) _follow(run);
  }

  final String noteId;
  final StateCommandTarget _view;
  final LandingOptions _options;
  late final VoidCallback _stop;
  ({String runId, Lander lander, String before})? _current;
  bool _disposed = false;

  void _follow(RunState run) {
    if (_disposed) return;
    final view = _view;
    // The review's answer is its findings, which it lands itself (ai/note_review.dart), and a fill's answers go
    // where its blanks are, which the fills' queue lands itself (ai/fills/fill_landing.dart).
    if (run.kind == RunKind.review || run.kind == RunKind.fill) return;
    final was = _current;
    if (was != null && was.runId != run.id) {
      // Another run took this one's place: what landed stays.
      was.lander.abandon();
      _current = null;
    }
    if (_current == null) {
      if (ended(run)) {
        // Ended before a line landed (stopped while waiting, or failed to load): its bookmark, if it is still the
        // note's, goes.
        final landing = view.state.field(landingField);
        if (landing != null && landing.runId == run.id) view.dispatch(TransactionSpec(effects: setLanding.of(null), annotations: aiEdit.of(AiEdit.land)));
        return;
      }
      if (run.phase == RunPhase.queued || run.phase == RunPhase.loading || run.phase == RunPhase.prefill) return;
      final scope = run.scope;
      if (view.state.field(landingField) == null && scope == null) return;
      // A reopened note mid-run, before a line had landed: the landing is decided again as it was at the start
      // (ai/start.dart), against the note as it reads now, which is as it read then, since it was closed in between.
      if (view.state.field(landingField) == null && scope != null) {
        final at = landingAt(run.kind, scope, view.state.doc.length, run.placement);
        view.dispatch(TransactionSpec(effects: setLanding.of(LandingSpot(runId: run.id, start: at.start, cursor: at.cursor, oldEnd: at.oldEnd))));
      }
      final lander = Lander(view, run.id, LanderOptions(wisp: _options.wisp(), haptic: _options.haptic()), view.state.doc.toString());
      _current = (runId: run.id, lander: lander, before: lander.before);
    }
    final (runId: _, :lander, :before) = _current!;
    if (run.phase == RunPhase.generating) {
      lander.land(run.lines);
      return;
    }
    if (!ended(run)) return;
    final text = run.text;
    if (run.phase == RunPhase.done) {
      lander.finish(text != null ? allLines(text) : run.lines);
    } else {
      lander.abandon();
    }
    if (lander.dropped > 0) _options.onDropped?.call(lander.dropped);
    // The AI signs what it co-wrote.
    if (run.phase == RunPhase.done) {
      final now = view.state.doc.toString();
      final signed = withAuthor(now, aiAuthor, _options.owner());
      if (signed != now) {
        final ends = commonEnds(now, signed);
        view.dispatch(
          TransactionSpec(
            changes: ChangeSpec(from: ends.prefix, to: now.length - ends.suffix, insert: signed.substring(ends.prefix, signed.length - ends.suffix)),
            annotations: aiEdit.of(AiEdit.sign),
          ),
        );
      }
    }
    final after = view.state.doc.toString();
    // A moment later: the engine tells its listeners that a run has ended before it writes the run's line in the
    // log, and the words go on that line.
    if (after != before) scheduleMicrotask(() => recordChange(noteId, run.id, before, after));
    _current = null;
  }

  /// Leaving the note mid-run: the lander goes with the editor; the run keeps its place (ai/land.dart's progress).
  void dispose() {
    _disposed = true;
    _current = null;
    _stop();
  }
}
