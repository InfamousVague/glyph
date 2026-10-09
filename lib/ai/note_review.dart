/// The review after a recording, run in the note it reviews: listen again, compare, think, land. A port of
/// `src/app/ai/useNoteReview.ts`.
///
/// Matt: "show the AI reasoning dissecting and parsing the note after we hit stop, use slower more detailed models
/// to check if the fast model got stuff right and work with the user to resolve and commit" - and then, folding it
/// into the note: Stop opens the note, listening again and the thinking run in the strip, and each finding lands as
/// a tracked change with Keep and Revert. The recording is already saved when this starts, so leaving at any point
/// loses nothing.
///
/// 1. Listening again: the larger speech model over this take (capture/refine.dart), said in the strip as a stage of
///    its own with its percent.
/// 2. Comparing: where it and the fast model heard different words (ai/support/review_diff.dart).
/// 3. Thinking: the formatting model, reasoning on, as a run of the engine (ai/runs.dart) the strip follows like any
///    other, its thought readable in the strip's card as it streams.
/// 4. Landing: its findings, each checked against the notes (ai/support/review_findings.dart), into this note as
///    tracked changes, and into another note a command changed through the guarded write; the words before and after
///    in the log, for Undo.
///
/// What differs:
/// - The hook is a [NoteReview]: the note's screen makes one, calls [NoteReview.attach] with the handoff and the
///   editor each time either changes (the hook's `[review, view]`), listens to it for the stage, and disposes of it
///   as the note is left (the effect's cleanup).
/// - What the hook imported, a [NoteReview] is given as a [ReviewHost]: the note store's `getNote`, `listNotes` and
///   `updateNote`, and the better-words queue's four (`enqueueRefine`, `holdRefining`, `keepBetterPhrases`,
///   `listenAgain`), which are a `Refining`'s methods.
/// - The handoff's `key` is the second argument of [NoteReview.attach], since the recorder's `ReviewHandoff` has
///   none.
/// - `REVIEW_HANDED_BACK` on `window` is [reviewHandedBack], heard with [onReviewHandedBack].
/// - `fireNativeHaptic('success')` is [reviewFelt]; the plugins' context is format/pipeline.dart's `noteContext`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show HapticFn, HapticKind, fireMotor;

import '../capture/markdown.dart' show Segment, renderNote;
import '../capture/refine.dart' show RefineJob;
import '../core/front_matter.dart' show frontMatterOffset;
import '../core/note.dart' show Note;
import '../core/note_text.dart' show noteTitle;
import '../editor/state/state.dart';
import '../format/pipeline.dart' show noteContext;
import 'backend.dart' show modelName;
import 'kinds.dart';
import 'log.dart';
import 'review.dart';
import 'review_simulation.dart';
import 'review_stage.dart';
import 'runs.dart';
import 'support/failure.dart';
import 'support/review_diff.dart';
import 'support/review_findings.dart';
import 'support/review_prompt.dart';

export 'review_stage.dart';

/// The buzz when the review found something (`fireNativeHaptic('success')`).
HapticFn reviewFelt = fireMotor;

final Set<void Function(String noteId)> _handedBack = <void Function(String noteId)>{};

/// Told, with the note's id, when a review hands its job back: when it ends, or when the note is left
/// (`REVIEW_HANDED_BACK`). The note's tag waits on it (core/location.dart, section 3 of its header): handed back
/// with the better words already in the note, the tag may land; handed back to the queue, `refinePending` says so
/// and the tag keeps waiting. Answers the way to stop.
VoidCallback onReviewHandedBack(void Function(String noteId) listener) {
  _handedBack.add(listener);
  return () => _handedBack.remove(listener);
}

/// Says a review handed its job back.
void reviewHandedBack(String noteId) {
  for (final listener in _handedBack.toList()) {
    listener(noteId);
  }
}

/// What a review asks of the app (see the header).
class ReviewHost {
  const ReviewHost({
    required this.getNote,
    required this.listNotes,
    required this.updateNote,
    required this.enqueueRefine,
    required this.holdRefining,
    required this.keepBetterPhrases,
    required this.listenAgain,
  });

  /// The note store's (`core/store.ts`): a note by id or null, every note, and the guarded write, which fails when
  /// the note has changed since [Note.revision].
  final Future<Note?> Function(String id) getNote;
  final Future<List<Note>> Function() listNotes;
  final Future<void> Function(String id, String body, int expectedRevision) updateNote;

  /// The better-words queue's (`capture/refine.ts`).
  final void Function(RefineJob job) enqueueRefine;
  final void Function(bool on) holdRefining;
  final Future<void> Function(RefineJob job, List<Segment> refined) keepBetterPhrases;
  final Future<List<Segment>?> Function(RefineJob job, void Function(num percent) onPercent) listenAgain;
}

final RegExp _seat = RegExp(r'\bseat\b', caseSensitive: false);
final RegExp _helloTrade = RegExp(r'\bhello trade\b', caseSensitive: false);

/// See the header (`useNoteReview`). Its [value] is the stage, or null when none is on.
class NoteReview extends ChangeNotifier implements ValueListenable<ReviewStage?> {
  NoteReview(this.host, {required this.wisp, required this.say});

  final ReviewHost host;

  /// Whether what lands arrives from smoke, asked as each finding lands.
  final bool Function() wisp;

  /// A line for the person (the note's toast).
  final void Function(String message) say;

  ReviewStage? _stage;
  int? _done;
  bool _disposed = false;

  /// Leaves the review in hand, as the effect's cleanup did.
  VoidCallback? _leave;

  @override
  ReviewStage? get value => _stage;

  void _setStage(ReviewStage? stage) {
    if (_disposed || stage == _stage) return;
    _stage = stage;
    notifyListeners();
  }

  /// The handoff and the editor as they are now. A review runs once for its [key], however often this is called
  /// with it. As the hook's effect did, a call with another handoff or another editor leaves the review in hand
  /// first, and one with the same two changes nothing.
  void attach(ReviewHandoff? review, int key, StateCommandTarget? view) {
    if (identical(review, _review) && identical(view, _view)) return;
    _left();
    _review = review;
    _view = view;
    if (review == null || view == null || _done == key) return;
    _done = key;
    _run(review, key, view);
  }

  ReviewHandoff? _review;
  StateCommandTarget? _view;

  void _left() {
    final leave = _leave;
    _leave = null;
    leave?.call();
  }

  void _run(ReviewHandoff handoff, int key, StateCommandTarget view) {
    var alive = true;
    // While the review runs, nothing queued competes for the cores.
    host.holdRefining(true);
    List<Segment>? refined;
    var listened = false;
    // What the queue would have done with this take still happens, once: when the review ends, or when the note is
    // left before it does. Leaving after it ended hands nothing back again - a second pass over the take, or the
    // queue let go while the recorder holds it.
    var handedBack = false;
    void handBack() {
      if (handedBack) return;
      handedBack = true;
      final job = handoff.job;
      final better = refined;
      if (job != null && better != null && listened) {
        unawaited(host.keepBetterPhrases(job, better));
      } else if (job != null) {
        host.enqueueRefine(job);
      }
      host.holdRefining(false);
      reviewHandedBack(handoff.noteId);
    }

    Future<void> stages() async {
      final note = await host.getNote(handoff.noteId);
      if (!alive || note == null) return;
      final title = noteTitle(note.body);
      final self = NoteText(id: note.id, title: title.isEmpty ? 'This note' : title, body: note.body);
      final others = <NoteText>[];
      for (final id in handoff.touched) {
        if (id == note.id) continue;
        Note? other;
        try {
          other = await host.getNote(id);
        } catch (_) {
          other = null;
        }
        if (other == null) continue;
        final named = noteTitle(other.body);
        others.add(NoteText(id: other.id, title: named.isEmpty ? 'Untitled' : named, body: other.body));
      }

      // 1. Listening again.
      String? careful;
      final job = handoff.job;
      if (simulatingReview()) {
        const detail = 'The slower speech model is listening to the recording again (simulated).';
        _setStage(const ReviewStage(what: 'Listening again', detail: detail, percent: 0));
        for (var percent = 10; percent <= 100 && alive; percent += 15) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (alive) _setStage(ReviewStage(what: 'Listening again', detail: detail, percent: percent));
        }
        careful = handoff.heard.replaceAll(_seat, 'seek').replaceAll(_helloTrade, 'HelloTrade');
      } else if (job != null) {
        const detail = 'The slower speech model is listening to the recording again.';
        _setStage(const ReviewStage(what: 'Listening again', detail: detail, percent: 0));
        try {
          final better = await host.listenAgain(job, (percent) {
            if (alive) _setStage(ReviewStage(what: 'Listening again', detail: detail, percent: percent.round()));
          });
          if (!alive) return;
          if (better != null) {
            refined = better;
            listened = true;
            careful = renderNote(better).plain;
          }
        } catch (failure) {
          if (!alive) return;
          say(failureText(failure));
        }
      }

      // 2. Comparing.
      final changes = careful != null ? wordChanges(handoff.heard, careful) : const <WordChange>[];
      _setStage(
        ReviewStage(
          what: 'Comparing',
          detail: careful == null
              ? 'Nothing to compare against.'
              : changes.isNotEmpty
                  ? '${changes.length} ${changes.length == 1 ? 'place' : 'places'} where the two models heard different words.'
                  : 'Both models heard the same words.',
          percent: null,
        ),
      );

      // 3. Thinking, as a run the strip follows.
      final model = simulatingReview() ? 'qwen3.5-4b' : await thinkingModel();
      if (!alive) return;
      var findings = wordsOnly(changes, self);
      var runId = 'review-${key.toRadixString(36)}';
      RunState? last;
      if (model != null) {
        List<Note> all;
        try {
          all = await host.listNotes();
        } catch (_) {
          all = const <Note>[];
        }
        final titles = [for (final n in all) noteTitle(n.body)].where((t) => t.isNotEmpty).toList();
        // The model reads the words, never the front matter: where a note was written (core/geotag.dart) is not a
        // finding, and the findings land by offsets into `self`, which keeps the whole body.
        String words(String body) => body.substring(frontMatterOffset(body));
        final prompt = reviewMessage(
          ReviewInput(
            title: self.title,
            body: words(self.body),
            heard: handoff.heard,
            careful: careful,
            changes: changes,
            commands: handoff.commands,
            titles: titles,
            touched: [for (final n in others) (title: n.title, body: words(n.body))],
          ),
        );
        final budget = reviewBudget(model, prompt.length);
        _setStage(null);
        if (simulatingReview()) simulateRuns(simulatedReview);
        final context = noteContext(self.id);
        final handle = startRun(
          RunRequest(
            noteId: self.id,
            kind: RunKind.review,
            model: model,
            system: reviewPrompt,
            context: context == null || context.isEmpty ? null : context,
            prompt: prompt,
            maxTokens: budget.total,
            temperature: 0.2,
            think: true,
            thinkBudget: budget.think,
          ),
        );
        runId = handle.id;
        last = await handle.done;
        if (simulatingReview()) simulateRuns(null);
        if (!alive) return;
        final text = last.text;
        if (last.phase == RunPhase.done && text != null) findings = readFindings(text, self, others);
      } else {
        say('No language model on this phone to think it through, so only the words the slower model heard differently are marked.');
      }

      // 4. Landing: this note's findings into its editor, another note's through the guarded write.
      final mine = [for (final f in findings) if (f.noteId == self.id) f];
      final theirs = [for (final f in findings) if (f.noteId != self.id) f];
      final before = view.state.doc.toString();
      final landed = landFindings(view, mine, runId, wisp: wisp());
      final after = view.state.doc.toString();
      if (after != before) recordChange(self.id, runId, before, after);
      var elsewhere = 0;
      if (theirs.isNotEmpty) {
        final fresh = <NoteText>[];
        final revisions = <String, int>{};
        for (final n in others) {
          Note? now;
          try {
            now = await host.getNote(n.id);
          } catch (_) {
            now = null;
          }
          fresh.add(now != null ? n.copyWith(body: now.body) : n);
          revisions[n.id] = now?.revision ?? 1;
        }
        for (final entry in applyFindings(fresh, theirs).entries) {
          final revision = revisions[entry.key];
          if (revision == null) continue;
          try {
            await host.updateNote(entry.key, entry.value, revision);
            elsewhere += 1;
          } catch (_) {
            // The note changed meanwhile: the finding stands down rather than writing over newer words.
          }
        }
      }
      final found = landed + elsewhere;
      if (model != null && last != null && last.phase != RunPhase.done) {
        // Stopped or failed: the word findings alone landed, and the strip already says what happened to the run.
      } else if (found > 0) {
        reviewFelt(HapticKind.success);
        final where = elsewhere > 0 ? ', $elsewhere in ${elsewhere == 1 ? 'another note' : 'other notes'}' : '';
        say('${model != null ? modelName(model) : 'The slower model'} found $found ${found == 1 ? 'thing' : 'things'} to look at$where. ${landed > 0 ? 'Each is marked in the note.' : ''}'.trim());
      } else if (model != null) {
        say('${modelName(model)} found nothing to change.');
      }
    }

    // A stage that throws ends the review as one that finished does: the stage goes and the job is handed back.
    unawaited(
      stages().catchError((Object _) {}).whenComplete(() {
        if (!alive) return;
        _setStage(null);
        handBack();
      }),
    );

    _leave = () {
      alive = false;
      _setStage(null);
      // Left mid-review: what would have run anyway still runs.
      handBack();
      if (simulatingReview()) simulateRuns(null);
    };
  }

  @override
  void dispose() {
    _left();
    _disposed = true;
    super.dispose();
  }
}
