/// The AI in the open note: a run started from the More sheet or a spoken instruction (ai/start.dart), whose lines
/// land in the note itself as they finish, as tracked changes (ai/note_landing.dart, editor/ai/ai_changes.dart),
/// with the strip under the header saying what the model is doing (ai/ai_strip.dart). A port of
/// `src/app/editor/useNoteAi.ts`, and with it the one place a note's screen takes the whole of the AI's surface
/// from: [noteAiExtensions] for its editor and [NoteAiLayer] over its page. The robot's own view over the note is
/// gone: Matt chose the note as the one surface, with auto-apply, marks, and Undo.
///
/// What is typed is flushed before a run starts, so the run's Undo has the note as it was. The marks the AI leaves
/// are counted for the strip and kept with the note a moment after they change (ai/marks.dart), so leaving and
/// coming back finds them where they were, as long as the note still reads the same. The review after a recording
/// runs here too: listening again and comparing as a stage in the strip, the thinking as a run, the findings landing
/// as tracked changes (ai/note_review.dart).
///
/// The recording's summary lands here too (docs/DESIGN.md §127 section 2): while the note is open its summary is
/// handed to this screen by the queue (ai/summaries.dart `openForSummaries`) and run in the editor, the one writer
/// of an open note, rather than written plain behind it.
///
/// ## The seam, for lib/root/note_desk.dart
///
/// One [NoteAi] for each open note, made with the note's desk and disposed of with it:
///
///     final ai = NoteAi(
///       noteId: note.id,
///       flush: saving.flush,                          // lib/core/library.dart NoteSaving
///       body: () => view.state.doc.toString(),        // the live document
///       wisp: () => preferences.value.wisp,
///       toast: (said) => toasts.show(...),            // an [AiToast]: its words, its time, its one action
///       onGetModel: () => openSettings('ai', 'Model'),
///       availability: availability,                   // the app's one AvailabilityController
///       reviewHost: ReviewHost(getNote: library.get, listNotes: () async => library.value, updateNote: ...,
///           enqueueRefine: refining.enqueueRefine, holdRefining: refining.holdRefining,
///           keepBetterPhrases: refining.keepBetterPhrases, listenAgain: refining.listenAgain),
///       openForSummaries: summaries.openForSummaries, // the app's one Summaries
///     );
///
/// then, in the order a desk does things:
///
/// 1. `extensions: [...noteAiExtensions(ai, still: t.reducedMotion)]` among the editor's own, in place of
///    `markExtensions(marks, wispTyping: true)`'s departures (see [noteAiExtensions]);
/// 2. `ai.attach(view)` once the editor's view exists, and `ai.attach(null)` as it goes;
/// 3. `ai.ask(NoteAsk(...))` for a spoken instruction the note opened with, and `ai.review(handoff, key)` for the
///    review a recording handed it (the recorder's `onFinish`), each as it arrives;
/// 4. `NoteAiLayer(ai: ai, top: <where the header ends>, onRoom: <the page pads itself by this>)` in the note
///    screen's own stack, covering the editor (`NoteSeams.over`), `ai.closePanels()` whenever the note's page
///    scrolls, and lib/scene's `AtWork` in the window's stack (its own header says where);
/// 5. the More sheet's rows call `ai.runAi(kind)` and mark `ai.runningKind`; the tape's Summarize word is there
///    while `ai.canSummarize`.
///
/// What differs:
/// - The hook is a [NoteAi], a `ChangeNotifier` the screen listens to: it tells when the marks' count or the
///   running kind changes; the review's stage is its own listenable ([NoteAi.reviewStage]).
/// - What the hook imported and a module here cannot reach is given: the availability's controller
///   (`useAvailability()`), the review's host and the summary queue's `openForSummaries`, which are a `Refining`'s
///   and a `Summaries`' methods; the handle the note is signed with is ai/start.dart's [noteOwner]. `toast` takes an
///   [AiToast], the kit's `ToastOptions` as far as the AI uses it.
/// - `isTauri()` is the engine being there, `isIOS` this build's platform; `fireNativeHaptic` is [noteAiFelt].
/// - A review's `key` is [NoteAi.review]'s second argument (the recorder's `ReviewHandoff` has none), and the scene
///   reads it back as [NoteAi.reviewKey].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../editor/ai/ai_changes.dart';
import '../editor/ai/blanks.dart';
import '../editor/ai/fill_panel.dart';
import '../editor/ai/wisp_arrivals.dart';
import '../editor/ai/wisp_ripples.dart';
import '../editor/editor.dart';
import '../editor/view/editor_view.dart' show EditorView;
import '../format/device_facts.dart';
import 'ai_strip.dart';
import 'available.dart';
import 'backend.dart' show aiBackend, learntUntil;
import 'fills/fill_landing.dart';
import 'fills/queue.dart' show FillTarget, lookupsHere, pressFill;
import 'kinds.dart';
import 'log.dart';
import 'marks.dart';
import 'note_landing.dart';
import 'note_review.dart';
import 'review.dart' show ReviewHandoff;
import 'runs.dart';
import 'start.dart';
import 'summary_ask.dart';

/// The buzz of a press that started something, and of an Undo that put the note back (`fireNativeHaptic`).
HapticFn noteAiFelt = fireMotor;

/// A spoken instruction about this note, to run on it as it opens (the app's root, ai/instruction.dart); [key] tells
/// one from the next (`NoteAsk`).
@immutable
class NoteAsk {
  const NoteAsk({required this.kind, this.instruction, required this.key});

  final RunKind kind;
  final String? instruction;
  final int key;
}

/// A line for the person, as the AI asks for one: the kit's `ToastOptions` as far as it uses them.
@immutable
class AiToast {
  const AiToast(this.message, {this.duration, this.actionLabel, this.onAction});

  final String message;

  /// How long it stays, in ms; the kit's own when null.
  final int? duration;

  /// Its one action, a word and what a press does (`action: { label, onPress }`).
  final String? actionLabel;
  final VoidCallback? onAction;
}

final RegExp _newest = RegExp(r'newest Ghost\.md');

/// See the header (`useNoteAi`, `NoteAi`).
class NoteAi extends ChangeNotifier {
  NoteAi({
    required this.noteId,
    required this.flush,
    required this.body,
    required this.wisp,
    required this.toast,
    this.onGetModel,
    required this.availability,
    this.reviewHost,
    this.openForSummaries,
    bool? ios,
  }) : _ios = ios ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    _run = useRun(noteId)..addListener(_runChanged);
    _runningKind = _kindNow();
    availability.addListener(_availabilityChanged);
    final host = reviewHost;
    if (host != null) {
      _review = NoteReview(host, wisp: wisp, say: (message) => toast(AiToast(message, duration: 7000)));
    }
    // The recording's summary, when the queue's turn for this note comes while it is open: a run in this editor.
    openForSummaries?.call(noteId, _summarize);
    blankHooks = BlankHooks(
      noteId: () => noteId,
      canFill: () => _canEverFill,
      learntUntil: () => learntUntil(_model ?? ''),
      lookups: lookupsHere,
      fill: _fill,
      say: (message) => toast(AiToast(message)),
    );
  }

  final String noteId;

  /// Saves what is typed now (lib/core/library.dart `NoteSaving.flush`).
  final VoidCallback flush;

  /// The live document, for the marks kept with it.
  final String Function() body;

  /// Whether what the AI writes arrives from smoke (core/preferences.dart `wisp`).
  final bool Function() wisp;
  final void Function(AiToast toast) toast;

  /// Settings at the Model card, for a press that needs a model on the phone.
  final VoidCallback? onGetModel;

  /// Whether the AI can run here (`useAvailability`).
  final AvailabilityController availability;

  /// What the review after a recording asks of the app; with none, a review handed over is not run.
  final ReviewHost? reviewHost;

  /// The summary queue's `openForSummaries` (ai/summaries.dart): given this note's starter while it is open, and
  /// null as it is left.
  final void Function(String id, SummaryStarter? starter)? openForSummaries;

  final bool _ios;
  late final ValueListenable<RunState?> _run;
  NoteReview? _review;
  EditorViewLike? _view;
  NoteLanding? _landing;
  FillLanding? _fillLanding;
  RunKind? _runningKind;
  NoteAsk? _ask;
  int? _askDone;
  ReviewHandoff? _handoff;
  int? _reviewKey;
  int _marks = 0;
  Timer? _marksTimer;
  bool _disposed = false;

  /// What the editor's blanks need: whose note, whether a Fill pill is drawn, and a press (editor/ai/blanks.dart).
  late final BlankHooks blankHooks;

  /// The kind of run on the note now, for the More sheet to mark, or null.
  RunKind? get runningKind => _runningKind;

  /// The review's stage, for the strip and the scene; one that never says anything where no review can run.
  ValueListenable<ReviewStage?> get reviewStage => _review ?? _noStage;
  static final ValueNotifier<ReviewStage?> _noStage = ValueNotifier<ReviewStage?>(null);

  /// The review handed to this note, and the number it was given: what lib/scene's `AtWork` opens on.
  ReviewHandoff? get handoff => _handoff;
  int? get reviewKey => _reviewKey;

  /// How many of the AI's marks are in the note.
  int get marks => _marks;

  /// The note's editor, once it has one.
  EditorViewLike? get view => _view;

  /// Whether the AI can run here, or is still being looked for: the tape's Summarize word is there only then.
  bool get canSummarize {
    final state = availability.availability;
    return state.ok || state.waiting;
  }

  RunKind? _kindNow() {
    final run = _run.value;
    return run != null && !ended(run) ? run.kind : null;
  }

  void _runChanged() {
    final now = _kindNow();
    if (now == _runningKind) return;
    _runningKind = now;
    if (!_disposed) notifyListeners();
  }

  void _availabilityChanged() {
    if (_disposed) return;
    _runAsk();
    notifyListeners();
  }

  // Where the model can ever run here: not a browser, not iOS, not a binary older than the engine
  // (ai/available.dart). A phone with no model still draws the pill, and a press says why and offers Get a model.
  bool get _canEverFill {
    final state = availability.availability;
    return aiBackend.available && !_ios && (state.ok || !_newest.hasMatch(state.reason ?? ''));
  }

  String? get _model {
    final state = availability.availability;
    return state.ok ? state.model : state.get;
  }

  /// Why the AI cannot run, said with the way to a model where getting one is the fix.
  void _refuse(String reason, String? get) {
    final getModel = onGetModel;
    toast(get != null && get.isNotEmpty && getModel != null ? AiToast(reason, actionLabel: 'Get a model', onAction: getModel) : AiToast(reason));
  }

  /// A press of Fill, handed to the fills' queue with the model that runs, or said why not (docs/DESIGN.md §145).
  void _fill(List<FillTarget> targets) {
    final state = availability.availability;
    if (!state.ok) {
      _refuse(state.reason!, state.get);
      return;
    }
    flush();
    pressFill(noteId, targets, state.model!);
    noteAiFelt(HapticKind.selection);
  }

  /// Starts a run on the note; says why not when it cannot (`runAi`).
  void runAi(RunKind kind, [String? instruction]) {
    final view = _view;
    if (view == null) return;
    if (kind == RunKind.fill) {
      if (fillAll(view) == 0) toast(const AiToast('No blanks for the model in this note.'));
      return;
    }
    flush();
    final started = startNoteRun(view, noteId, kind, availability.availability, instruction: instruction);
    if (started is NotStarted) {
      final state = availability.availability;
      _refuse(started.reason, state.ok ? null : state.get);
    } else {
      noteAiFelt(HapticKind.selection);
    }
  }

  SummaryStarted _summarize(SummaryAsk ask) {
    final view = _view;
    if (view == null) return const SummaryRefused('The note is not open.');
    flush();
    final started = startRecordingRun(view, noteId, availability.availability, ask);
    if (started.ok) noteAiFelt(HapticKind.selection);
    return started;
  }

  /// The note's editor as it is now: given once it exists, and null as it goes. The landing, the fills' landing and
  /// the marks kept with the note follow it, as the hook's effects followed `view`.
  void attach(EditorViewLike? view) {
    if (identical(view, _view)) return;
    _landing?.dispose();
    _fillLanding?.dispose();
    _landing = null;
    _fillLanding = null;
    _view = view;
    _review?.attach(_handoff, _reviewKey ?? 0, view);
    // The layer over the page draws this editor's panel.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
    if (view == null) return;
    // A fill's answers land through this editor while the note is open (ai/fills/fill_landing.dart).
    _fillLanding = FillLanding(noteId, view, wisp: wisp, owner: noteOwner);
    // The AI signs beside the account's handle, where there is one (ai/support/authors.dart).
    _landing = NoteLanding(
      noteId,
      view,
      LandingOptions(
        wisp: wisp,
        haptic: () => true,
        owner: noteOwner,
        onDropped: (count) => toast(AiToast(count == 1 ? 'One line the model wrote was dropped: you had written there.' : '$count lines the model wrote were dropped: you had written there.')),
      ),
    );
    final kept = loadMarks(noteId, view.state.doc.toString());
    if (kept != null && kept.isNotEmpty) view.dispatch(TransactionSpec(effects: restoreAiChanges.of(kept)));
    _runAsk();
  }

  /// A spoken instruction the note opened with: run once the editor and the AI are ready.
  void ask(NoteAsk? ask) {
    _ask = ask;
    _runAsk();
  }

  void _runAsk() {
    final ask = _ask;
    if (ask == null || _view == null || _askDone == ask.key) return;
    final state = availability.availability;
    if (!state.ok) {
      if (state.waiting) return;
      _askDone = ask.key;
      toast(AiToast(state.reason!));
      return;
    }
    _askDone = ask.key;
    runAi(ask.kind, ask.instruction);
  }

  /// The review a recording handed this note (ai/review.dart `ReviewHandoff`), with the number that tells it from
  /// the one before; null for none.
  void review(ReviewHandoff? handoff, [int key = 0]) {
    final changed = !identical(handoff, _handoff) || key != _reviewKey;
    _handoff = handoff;
    _reviewKey = handoff == null ? null : key;
    _review?.attach(handoff, key, _view);
    if (changed && !_disposed) notifyListeners();
  }

  /// The editor's word that the marks changed (`onAiMarks`): [noteAiExtensions] hands it to `aiChanges`.
  void onAiMarks(List<AiChange> changes) {
    if (_disposed) return;
    final count = changes.length;
    _marksTimer?.cancel();
    _marksTimer = Timer(const Duration(milliseconds: 400), () {
      _marksTimer = null;
      saveMarks(noteId, body(), changes);
    });
    if (count == _marks) return;
    _marks = count;
    // Told from inside the editor's own update: the screen draws after it.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  /// The panel a tap on a blank or a filled answer opened is put away (editor/ai/fill_panel.dart): the page calls
  /// this as it scrolls, as the page's editor closed its panel on a scroll.
  void closePanels() {
    final view = _view;
    if (view != null) closeFillPanel(view);
  }

  /// Every change the AI has marked, kept at once: the strip's Keep all.
  void keepAll() {
    final view = _view;
    if (view != null) keepAllChanges(view);
  }

  /// The note back as it was before the run, but only while it still reads as the run left it - a later edit is the
  /// person's, and would be lost under the old words. Undo for a run in the strip's log; false when it cannot be
  /// undone (`undoRun`).
  bool undoRun(RunRecord record) {
    final view = _view;
    final before = record.before, after = record.after;
    if (view == null || before == null || after == null) return false;
    final now = view.state.doc.toString();
    if (now != after) {
      toast(const AiToast('The note has changed since, so that run can’t be undone.'));
      return false;
    }
    view.dispatch(
      TransactionSpec(
        changes: ChangeSpec(from: 0, to: now.length, insert: before),
        selection: EditorSelection.single(0),
        scrollIntoView: true,
        effects: keepAllAiChanges.of(null),
        annotations: aiEdit.of(AiEdit.undo),
      ),
    );
    recordUndone(noteId, record.id);
    noteAiFelt(HapticKind.success);
    toast(const AiToast('Put back as it was.'));
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _marksTimer?.cancel();
    _run.removeListener(_runChanged);
    availability.removeListener(_availabilityChanged);
    openForSummaries?.call(noteId, null);
    _landing?.dispose();
    _fillLanding?.dispose();
    _review?.dispose();
    super.dispose();
  }
}

/// Everything of the AI's a note's editor is made with, in the order the page's `Editor.tsx` lists them:
///
/// - `fillPanel()`: the panel a tap on a blank or a filled answer opens;
/// - `blanks(ai.blankHooks, still: still)`: the blanks drawn, their Fill pill and what a press does;
/// - `wispArrivals(typing: wispTyping)`: what the AI lands arriving out of smoke, and what is taken out leaving
///   into it. It brings lib/editor/marks/wisp_motion.dart's `wispDepartures` with it, so the editor must not also
///   be given them: `markExtensions(marks)` without its `wispTyping`;
/// - `wispRipples(ripples)`, where the screen has a voice to follow (the recorder's page; a note's has none);
/// - `aiChanges(onMarks: ai.onAiMarks)`: the tracked changes, their two fields, and the note told of its marks.
///
/// [still] is reduced motion (`context.tokens.reducedMotion`), which stills the blanks' own squares. The maker of
/// the editor fills `wispStill` and `wispPace` (lib/editor/marks/wisp_motion.dart) as it does for the marks. A page
/// that is only read (a peek, a shared page) takes none of this.
List<Extension> noteAiExtensions(NoteAi ai, {bool still = false, bool wispTyping = true, RippleSource? ripples}) => <Extension>[
      fillPanel(),
      blanks(ai.blankHooks, still: still),
      wispArrivals(typing: wispTyping),
      if (ripples != null) wispRipples(ripples),
      aiChanges(onMarks: ai.onAiMarks),
    ];

/// The AI's one layer over a note's page: the strip under the header, floating over the words and never in the
/// page's smoke (the page's `.stripHolder`, NoteScreen.module.css, and `useStripRoom`), and the panel a tap on a
/// blank or a filled answer opens, beside the words it is about (editor/ai/fill_panel.dart `EditorFillPanel`, which
/// the page's editor drew inside itself).
///
/// It fills the stack it is put in, which must cover the note's editor, and takes no touch but the strip's and the
/// panel's own. [top] is where the header ends
/// (`--ai-strip-top`); the strip stands a `--glacier-space-2` under it. [onRoom] is told the room the page should
/// keep clear under the header for it (`--ai-strip-room`): the strip's height and 8 more, and 0 once it is gone.
/// [deviceFacts] is the phone as the app knows it, for the card (format/device_facts.dart).
class NoteAiLayer extends StatelessWidget {
  const NoteAiLayer({super.key, required this.ai, required this.top, this.onRoom, this.deviceFacts, this.canUndo = true});

  final NoteAi ai;
  final double top;
  final void Function(double room)? onRoom;
  final ValueListenable<DeviceFacts>? deviceFacts;

  /// False where the note cannot be written (a shared page): the strip offers no Undo.
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final room = onRoom;
    // .stripHolder { position: absolute; inset-inline: 0;
    //   inset-block-start: calc(var(--ai-strip-top, 3.6rem) + var(--glacier-space-2)); z-index: 4;
    //   pointer-events: none; }
    // .stripHolder > * { pointer-events: auto; }
    return Stack(
      children: [
        ListenableBuilder(
          listenable: ai,
          builder: (context, _) => switch (ai.view) {
            final EditorView view => Positioned.fill(child: EditorFillPanel(view: view)),
            _ => const SizedBox.shrink(),
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          top: top + t.space(2),
          child: ListenableBuilder(
            listenable: Listenable.merge([ai, ai.reviewStage]),
            builder: (context, _) => AiStrip(
              noteId: ai.noteId,
              onUndo: canUndo ? ai.undoRun : null,
              // screen.style.setProperty('--ai-strip-room', height ? `${height + 8}px` : '0px')
              onHeight: room == null ? null : (height) => room(height > 0 ? height + 8 : 0),
              marks: ai.marks > 0 && ai.view != null ? StripMarks(count: ai.marks, keepAll: ai.keepAll) : null,
              stage: ai.reviewStage.value,
              deviceFacts: deviceFacts,
            ),
          ),
        ),
      ],
    );
  }
}
