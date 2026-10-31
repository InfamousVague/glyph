/// A note being spoken. A port of `src/app/capture/CaptureScreen.tsx` and CaptureScreen.module.css.
///
/// One screen for both ways in - the Speak button and the held side key - and it shows one thing: the note taking
/// shape as you say it, on its own page (live_page.dart), the spoken cues turning into its marks as they land. A small
/// line at the top says where the words are going; a counter says how long; Discard and Done are the only buttons.
/// Until the first words arrive, a card of things to say (say_card.dart) and the ghost listening are the page, so the
/// microphone being live is visible before a word has been understood.
///
/// The microphone opens before anything else is ready, and the model loads while it listens (capture_session.dart):
/// the first words of a voice note are usually its subject. It is opened by this screen being on screen and let go
/// by Done, Discard or the screen going: there is no always-on microphone, and "Hey Ghost" is read only from what
/// this screen hears.
///
/// Each committed phrase is read by the live reader (live_route.dart) for one family of command, words for a note
/// you name: "Hey Ghost, add a note to House TODOs" switches the page to that note and writes what is said into its
/// list as it is said; "add … to X" mid-take sends those words to X. A partial phrase never routes anything. Nothing
/// is stored before Done: each note is then read fresh and written once, through the store's command mutation for a
/// note that already existed (take_writer.dart `writeInto`). Anything else a recording asks for is read once, from
/// the final transcript, at Done (read_instruction.dart), when the live reader did nothing. The sound is kept as it
/// is recorded, under the id of the note it goes with at the stop; a cancel deletes it. Every write to a note goes
/// through one chain (take_writer.dart).
///
/// A recording from the Speak button or the side key is a new note, or the note its first command named; a note's
/// own Speak adds to that note. Done hands back the note the words went into, with what the recording left in it
/// (landing.dart), for whoever opened the recorder to open; a locked phone has already stepped back behind its lock
/// screen. A take over three minutes (`longNoteMs`) is given no review, and the Done line says why.
///
/// A MEETING in this recorder ([CaptureScreen.meeting], the Mac) is recorded, not read: no live reader, no reader at
/// Done, no "hey Ghost", no quiet stop, no review, no title from the first sentence, and no card of things to say.
/// The page shows the transcript as paragraphs under the date title (meeting.dart), and Done writes that note,
/// records it as a meeting, and queues its better words and its summary. The card's "Meeting instead", before the
/// first word, turns this recorder into that on the Mac; on a phone with the service it lets the microphone go and
/// hands over ([CaptureScreen.onMeeting]).
///
/// The pieces are their own files, as on the web: the cards (capture_cards.dart), the chip (route_chip.dart), the
/// lines of words that are not the note (`screen_text.dart`), the diagnostics line (`diagnostics.dart`), the last
/// words of a stopped decode (`final_words.dart`) and where the take sits on its note's tape (`timeline.dart`).
///
/// What differs:
/// - Every module the web's screen imports is a field of the [Recorder] it is given (recorder.dart): the store, the
///   host, the preferences, the engine's `startCapture`, `enqueueRefine`, the review, the summaries, the plugins.
/// - A React component's state and refs are this State's fields; the `hostImpl`/`applyRef`/`finishRef` indirections,
///   there so handlers registered once reach the newest render, are not needed: there is one State.
/// - `onFinish`'s optional third to fifth arguments are named ([CaptureFinish]).
/// - The level on Done's ring and the rings behind the mic take the level from a notifier and `voice_level.dart`,
///   where the web writes a custom property; the top line's height is measured after layout (`--recorder-top`).
/// - The page's words for a test are [LivePageState.document]; the buttons carry keys ([CaptureScreen.doneKey],
///   [CaptureScreen.discardKey], [CaptureScreen.whereKey], [CaptureScreen.actionKey], [CaptureScreen.counterKey]) where the web's tests find them by role and name.
/// - The web's `aria-live` on the top line and the cards is `Semantics(liveRegion: true)`; Done's `aria-label` is its
///   semantic label.
/// - A whole screen has no tab bar over it: whoever shows this takes the `tabs` stamp off the root
///   (shell/root_stamps.dart), as the page's shell does, or the top line pads by a bar that is not there.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' hide Placement;

import '../../app/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../art/app_icon.dart';
import '../../art/ghost.dart';
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../../core/book.dart' show chaptersOf, isBookBody;
import '../../core/item_syntax.dart' show withoutLead;
import '../../core/note.dart';
import '../../meet/meeting_mark.dart' show MeetingMark, withMeetingMark;
import '../../core/note_text.dart' show noteTitle;
import '../../core/preferences.dart' show longNoteMs;
import '../../core/text.dart' show capitalise;
import '../../core/title_key.dart' show sameTitle;
import '../../shell/desktop/mac_lights.dart';
import '../../shell/header_pane.dart';
import '../candidates.dart';
import '../capture_session.dart';
import '../chip.dart';
import '../command.dart' show Placement, PlacementHow, findKeyword, findMisheard;
import '../diagnostics.dart';
import '../engine.dart';
import '../final_words.dart';
import '../instruction_mutation.dart' show listTitle;
import '../landing.dart';
import '../list_append.dart' show appendToList, placeWords;
import '../live_route.dart';
import '../markdown.dart';
import '../meeting.dart';
import '../meeting_turns.dart' show meetingTranscript;
import '../offers.dart' show placingOf;
import '../place.dart';
import '../quiet.dart';
import '../recorder.dart';
import '../refine.dart' show RefineJob;
import '../refine_text.dart' show withoutCommands;
import '../screen_text.dart';
import '../spoken/extras.dart' show setLinkTitles;
import '../spoken/inline.dart' show setSpokenFormats;
import '../take.dart';
import '../take_back.dart' show opensSend, takeBackAt;
import '../take_host.dart';
import '../take_types.dart';
import '../take_writer.dart';
import '../tape.dart' show counter;
import '../timeline.dart';
import '../tips.dart';
import '../trailing_echo.dart' show segmentsWithoutTrailingEcho;
import '../voice_log.dart' show settleRecording, traceRecording;
import '../voice_plan.dart' show VoiceAction, VoiceAppend, VoiceCreate;
import '../voice_level.dart';
import 'capture_cards.dart';
import 'computer_sound.dart';
import '../../editor/ai/wisp_ripples.dart' show RippleSource;
import 'live_page.dart';
import 'opening.dart';
import 'read_instruction.dart';
import 'route_chip.dart';
import 'say_card.dart';
import 'voice_waves.dart';
import '../../sounds/sound_pack.dart' show SoundEvent;
import '../../sounds/sounds.dart' show sounds;

/// How long a quiet after words has to last before "Stop when I go quiet" saves the take (`QUIET_STOP_MS`).
const int quietStopMs = 4000;

/// How long the recorder stays up at Done for a line saying why nothing was kept, so it can be read (`SAID_MS`).
const Duration saidFor = Duration(milliseconds: 1500);

/// What was said before "New note", for the note it was said for: written at Done with everything else.
class _Part {
  const _Part({required this.note, required this.title, required this.placing, required this.markdown, required this.titled, required this.noteId});

  final Note? note;

  /// The note it was written into had been switched to by a command, or was the note's own Speak.
  final String? title;
  final Placing placing;
  final String markdown;

  /// The same words titled, for a note of their own if the note they were for changed too much to write into.
  final String titled;
  final String noteId;
}

/// A one-shot's words for another note ("hey Ghost, add call Sam to House TODOs"), written at Done.
class _Insert {
  _Insert({required this.note, required this.title, required this.placing, required this.segments});

  final Note note;
  final String title;
  final Placing placing;
  List<Segment> segments;
}

/// A stopped command awaiting its explicit confirmation; its words never become a note.
class _FinalCommand {
  const _FinalCommand({
    required this.actions,
    this.rest,
    this.trace,
    this.keep,
    required this.locked,
    required this.temporaryId,
    required this.recordedMs,
    required this.ownTape,
  });

  /// The changes the recording asked for, checked (final_instruction.dart), carried out on confirmation.
  final List<VoiceAction<TakeCandidate<Note>>> actions;

  /// The rest of what was said, kept as its own note on confirmation; null for none.
  final String? rest;

  /// Its entry in the voice log (voice_log.dart), for what the person chose.
  final int? trace;

  /// A command found inside dictation: declined, the recording is saved as a note instead of let go.
  final Future<void> Function()? keep;
  final bool locked;
  final String temporaryId;
  final int? recordedMs;

  /// The continued note whose own tape the take was added to the end of, or null: its sound is never moved or
  /// removed (`_letGo`).
  final Note? ownTape;
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.recorder,
    required this.fromAssistant,
    this.stopRequests = 0,
    this.noteId,
    this.placing,
    this.meeting = false,
    this.onMeeting,
    required this.onFinish,
  });

  /// Done, Discard and the line at the top, for a test to press.
  static const Key doneKey = Key('capture-done');
  static const Key discardKey = Key('capture-discard');
  static const Key whereKey = Key('capture-where');
  static const Key actionKey = Key('capture-top-action');
  static const Key counterKey = Key('capture-counter');

  /// Everything the recorder reaches (recorder.dart).
  final Recorder recorder;

  /// Opened by the side key, where the OS has already buzzed.
  final bool fromAssistant;

  /// Counts side-key presses during this capture: each one after the first means "stop and save".
  final int stopRequests;

  /// Talking into this note (its Speak): the words go on its end.
  final String? noteId;

  /// Where in that note the words go, when its opener knows better than its title (place.dart `placingFor`): a
  /// journal's entry said aloud goes on from its time, or into its to-do list. Absent, the note's own.
  final Placing? placing;

  /// A meeting from the start: recorded, not read (the Mac; meeting.dart).
  final bool meeting;

  /// Where a meeting can be recorded: the card offers "Meeting instead" before the first word. On a phone it is
  /// called once this page has let the microphone go, and the caller starts the service; on the Mac the recorder
  /// turns into a meeting itself and this is not called.
  final VoidCallback? onMeeting;

  /// The take is over. The note is the saved one, or null when the capture was cancelled or nothing was said;
  /// `review` is set when the review after a recording should look at it, `ask` when the words were an instruction
  /// about the note being continued, to run once it is open.
  final CaptureFinish onFinish;

  @override
  State<CaptureScreen> createState() => CaptureScreenState();
}

class CaptureScreenState extends State<CaptureScreen> implements TakeHost<Note> {
  Recorder get _r => widget.recorder;

  /// The note this capture is being added to, if it continues one, as the page shows it (`_writer.target` is the
  /// truth).
  Note? _target;

  /// A meeting: from the start, or turned into one from the card before the first word (the Mac).
  late bool _meeting = widget.meeting;

  /// A meeting from the start with its live transcript off (Settings › Recording › Live transcript during meetings;
  /// Matt, 2026-10-30): its page shows no words while it records, and none are guessed at; Done writes the same note.
  late final bool _meetingQuiet = widget.meeting && !_r.meetingLiveWords();

  /// When the meeting began, and the date title it is made with.
  late final int _meetingStartedAt = _r.wallNow();
  late final String _meetingTitled = meetingTitle(_meetingStartedAt, _r.locale);
  List<Segment> _segments = const [];
  String _partial = '';

  /// Milliseconds on the recording, copied from the session a few times a second.
  num _recorded = 0;
  Diagnostics _diagnostics = emptyDiagnostics;
  bool _showDiagnostics = false;

  /// Set when "Stop when I go quiet" is on: watches for the end of talking. Never for a meeting, whose pauses are the
  /// room's.
  QuietWatch? _quiet;

  /// Whether this phone stops a recording when the side key is pressed.
  bool _pressStops = false;

  /// The mic drawn in the top line: where the voice's rings rise from (voice_waves.dart).
  final GlobalKey _mic = GlobalKey();
  final GlobalKey _top = GlobalKey();
  double _topHeight = 0;
  final ValueNotifier<double> _level = ValueNotifier<double>(0);

  /// The voice's level, as the page's arriving words follow it.
  late final RippleSource _ripples = _LevelRipples(_level);

  /// The notes a spoken "add to …" can name, most recent first; loaded as the capture opens.
  List<NamedNote> _candidates = [];

  /// The routing chip: a note being named while it is still being said, then the note the words moved to (or a name
  /// that matched nothing).
  RouteView? _route;
  Timer? _lingering;

  /// Bumped when words move to another note, to replay the lines writing out.
  int _moves = 0;

  /// What a command read at Done will do once its card is tapped.
  Offer<Note>? _pending;

  /// The tape this take writes to: the continued note's, or a new one. Read once, when it is first needed.
  String? _takeTape;

  /// Every phrase the fast model heard, commands and all, for the review to check against a second listen.
  final List<String> _heard = [];

  /// What each command did, or didn't, in words: the review checks them.
  final List<String> _commandLog = [];

  /// When words were last heard, for the tips in a pause.
  late double _lastHeard = _r.now();
  Tip? _tip;

  /// The notes have been read into `_candidates`: the card of things to say can name one.
  bool _notesRead = false;
  int _tipTurn = 0;
  bool _finished = false;

  /// Done could not keep the words anywhere ([_doneFailed]): the recorder stays up with them, says so, and Done tries
  /// again. Until then, what Done had got to: the note it had saved before whatever failed ([_keptAtDone]), and the
  /// take's sound as the stop left it ([_soundAtDone]).
  bool _doneFailed = false;
  Note? _keptAtDone;
  ({String recordedAs, int? recordedMs, Note? ownTape})? _soundAtDone;
  _FinalCommand? _finalCommand;

  /// The live reader: each committed phrase read for a note named (live_route.dart).
  final LiveRoute<Note> _live = LiveRoute<Note>();

  /// Every committed phrase, commands and all, for the stop's last words to be told apart from.
  final List<Segment> _committed = [];

  /// How many of them came before the last "New note": the reader at Done reads only what was said after it.
  int _forkedAt = 0;

  /// Phrases committed before the notes a command can name were read: read once they are.
  List<Segment>? _queued = [];

  /// Where the words go in the note the page shows, and the document it starts from after a switch.
  Placing _placing = end;
  String? _pageFrom;

  /// A card asking which note.
  LiveCard<Note>? _choice;

  /// The take was switched to a note by a command, not opened from its own Speak.
  bool _routed = false;

  /// "New note “House chores”" chosen on a card: the note the take goes to is made at Done, with this title.
  String? _pendingTitle;

  /// The note whose own Speak this is: where Not this note goes back to.
  Note? _home;
  final List<_Part> _parts = [];
  final Map<int, _Insert> _inserts = {};

  /// A run or an ask said mid-take, for the note that opens after Done, and its words as said.
  SpokenAsk? _pendingAsk;
  String _pendingAskSaid = '';

  /// The lines a confirmed card after Done put in its note, for the note's Undo.

  /// While an item for another note is being said, its words show in the chip, not in this note.
  String _itemWords = '';

  late final Take<Note> _take = Take<Note>(this);
  late final TakeWriter _writer = TakeWriter(
    TakeWriterHost(
      markdown: (titled) => _take.markdown(titled: titled),
      // For the mid-take drafts, which nothing writes now: any phrase at all, where Done asks `take.hasContent`.
      hasWords: () => _take.segments.isNotEmpty,
      candidates: () => _candidates,
      targetChanged: (note) => _set(() => _target = note),
    ),
    store: _r.store,
  );
  late final CaptureSessionState _session;
  Timer? _ticking;
  VoidCallback? _offScreenOff;
  bool _alive = true;

  void _set(VoidCallback change) {
    if (mounted && _alive) {
      setState(change);
    } else {
      change();
    }
  }

  int _now() => _r.now().round();
  bool get _locked => _r.host.isLocked();

  @override
  void initState() {
    super.initState();
    _quiet = _r.preferences().quietStop && !widget.meeting ? QuietWatch(quietStopMs) : null;
    // The switched-on plugins' formattings can be said like bold ("spoiler … end spoiler"); read as the recorder
    // opens, before the first build lays the page out with them.
    setSpokenFormats(_r.spokenFormats());
    // No background pass over an earlier recording while this one is live: same cores.
    _r.setRecorderLive(true);
    // The screen stays on while this runs, and pressing the side key (which turns it off) stops it: the only sign of
    // the key Android gives an app.
    _pressStops = _r.host.setCapturing(true);
    // The side key pressed: the screen went off, so the take is saved as Done would save it.
    _offScreenOff = _r.host.onScreenOff(() => unawaited(finish()));
    _session = CaptureSessionState(
      fromAssistant: widget.fromAssistant,
      isFinished: () => _finished,
      // A microphone that closed by itself hears no more: the take is saved as Done would save it, as it is when the
      // screen goes off.
      events: SessionEvents(onPartial: _onPartial, onSegment: _onSegment, onLevel: _onLevel, onMicrophoneLost: (_) => unawaited(finish())),
      native: _r.native && _r.openMicrophone != null,
      simulate: _r.simulate,
      openMicrophone: _r.openMicrophone ?? (_) => Future<Never>.error(StateError('This build has no microphone.')),
      startCapture: _r.startCapture,
      fireNativeHaptic: _r.host.haptic,
      info: _r.warn,
      warn: _r.warn,
      // A meeting with its live transcript off guesses at nothing: each phrase is heard once (Matt, 2026-10-30).
      guesses: !_meetingQuiet,
    )..addListener(_sessionChanged);
    // The recorder's start sound (Settings › Sounds; Matt, 2026-10-27), as the microphone is asked for, so it is heard
    // before the first word; and from here until the screen goes, no other sound of the app's plays over the take.
    sounds.play(SoundEvent.recordStart);
    sounds.recording = true;
    _session.start();
    _aim();
    _readNotes();
  }

  @override
  void didUpdateWidget(CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The side key held again: Done. Only a new press acts.
    if (widget.stopRequests != oldWidget.stopRequests && widget.stopRequests != 0) unawaited(finish());
  }

  @override
  void dispose() {
    _alive = false;
    _ticking?.cancel();
    _lingering?.cancel();
    _offScreenOff?.call();
    _session
      ..removeListener(_sessionChanged)
      ..close();
    _r.setRecorderLive(false);
    _r.host.setCapturing(false);
    sounds.recording = false;
    publishVoiceLevel(0);
    _level.dispose();
    super.dispose();
  }

  // ---- which note --------------------------------------------------------------------------------------------------

  /// A note's own Speak aims the recording at that note; otherwise it is a new one. Decided once, as the capture
  /// opens.
  void _aim() {
    final aimedAt = widget.noteId;
    if (aimedAt == null) return;
    unawaited(() async {
      Note? found;
      try {
        found = await _r.store.getNote(aimedAt);
      } catch (_) {
        found = null;
      }
      // Found after a draft was already written to a new note, or after a command switched the take: stay there.
      if (!_alive || found == null || _writer.savedDraft || _finished || _live.engaged) return;
      final own = widget.placing ?? placingFor(found.body, own: true);
      _home = found;
      _writer.aim(found, own);
      _set(() => _placing = own);
    }());
  }

  /// The notes "add to …" can name (candidates.dart). Read once: a capture lasts minutes, and a note made meanwhile
  /// is not one someone will name mid-sentence.
  void _readNotes() {
    unawaited(() async {
      final List<Note> all;
      try {
        all = await _r.store.listNotes();
      } catch (_) {
        return;
      }
      if (!_alive) return;
      _candidates = [for (final c in commandCandidates(all)) NamedNote(id: c.id, title: c.title, note: c.note)];
      // "Note link weekend trip end link" takes the note's own spelling.
      setLinkTitles([for (final c in _candidates) c.title]);
      _set(() => _notesRead = true);
      // Phrases said while the notes were read: read now, in order.
      final waiting = _queued ?? const <Segment>[];
      _queued = null;
      for (final segment in waiting) {
        _applySteps(_live.phrase(segment, _liveContext(), _now()));
      }
    }());
  }

  /// "New note", tapped: a fresh one from here, the words so far kept for the note they were said for.
  void _startNewNote() {
    // The reader first, so the tap and the spoken cue leave it in one state: a take-back open settles.
    _applySteps(_live.forked());
    _sealAndFork();
    route(const RouteViewMoved(title: 'New note'));
    _r.host.haptic('selection');
  }

  /// Words arrived: a tip showing goes, and the next pause gets the next one.
  void _heardWords() {
    _lastHeard = _r.now();
    if (_tip != null) {
      _tipTurn += 1;
      _set(() => _tip = null);
    }
  }

  // ---- the microphone and the transcriber (capture_session.dart) ----------------------------------------------------

  void _onPartial(String text) {
    if (text.isNotEmpty) {
      _quiet?.words(_r.now());
      _heardWords();
    }
    // A meeting is recorded, not read: the guess goes on the page as it is.
    if (_meeting) {
      _set(() => _partial = text);
      return;
    }
    // A partial is display only: it routes nothing. While a command is being said, or a note just named waits for
    // its words, it shows in the chip rather than on the page; "scratch that" being said never flashes onto it,
    // wherever it starts in the phrase (the words before it stay on the page), and nor does the send a bare drop is
    // waiting for.
    final takeBack = takeBackAt(text);
    final commanding = _live.hearingCommand ||
        takeBack == 0 ||
        (_live.sendOpen && opensSend(text)) ||
        (text != '' && (findKeyword(text) != null || findMisheard(text, (_) => true) != null));
    _set(() {
      _itemWords = commanding
          ? text
          : takeBack > 0
              ? text.substring(takeBack)
              : '';
      _partial = commanding
          ? ''
          : takeBack > 0
              ? text.substring(0, takeBack).trim()
              : text;
    });
  }

  void _onSegment(Segment raw) {
    _quiet?.words(_r.now());
    _heardWords();
    _heard.add(raw.text);
    _committed.add(raw);
    _set(() {
      _partial = '';
      _itemWords = '';
    });
    // A meeting's phrases go straight to the take, unread: no command, no keyword, no take-back.
    if (_meeting) {
      _take.listen(raw);
      _syncTake();
      return;
    }
    final queued = _queued;
    if (queued != null) {
      queued.add(raw);
      return;
    }
    // Applied at once, with nothing awaited: a phrase committed straight after a switch lands in the new note.
    _applySteps(_live.phrase(raw, _liveContext(), _now()));
  }

  void _onLevel(double level, double rms) {
    // Straight to a notifier: five updates a second is too many builds for a meter nobody reads precisely.
    _level.value = level;
    publishVoiceLevel(level);
    _quiet?.level(rms, _r.now());
  }

  void _sessionChanged() {
    if (!_alive) return;
    if (_session.phase == Phase.listening) {
      _ticking ??= Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    } else {
      _ticking?.cancel();
      _ticking = null;
    }
    _set(() {});
  }

  // ---- the card after Done: words for a note, once tapped (take.dart) -----------------------------------------------

  /// Add, tapped on the card after Done: the words go into the note they were read for, its last list growing by
  /// them in its own style. The chip and the landing preview show the lines arriving.
  Future<void> _addItems(Note note, String spoken, Placement placement) async {
    try {
      // The offer was made from this exact note snapshot. Confirmation is a compare-and-swap, so a later edit or
      // delete wins instead of being overwritten by the voice command.
      final placed = placeWords(note.body, spoken, placingOf(placement));
      if (placed.added.isEmpty) return;
      final result = await _r.store.applyCommandMutation(CommandMutationRequest(
        mutationId: _r.store.newNoteId(),
        noteId: note.id,
        kind: 'append',
        beforeRevision: note.revision,
        beforeBody: note.body,
        afterBody: placed.body,
        source: note.source,
      ));
      if (result is! CommandMutationResultApplied) {
        final title = noteTitle(note.body);
        route(RouteViewSaid(text: '${title.isEmpty ? 'That note' : title} changed after the preview, so nothing was added.'));
        _r.host.haptic('warning');
        return;
      }
      final saved = result.note;
      _writer.remember(saved);
      _writer.rebase(saved);
      final savedTitle = noteTitle(saved.body);
      if (_writer.target?.id == saved.id) {
        route(RouteViewDone(text: 'Added “${withoutLead(placed.added.first)}”${placed.added.length > 1 ? ' and ${placed.added.length - 1} more' : ''}'));
      } else {
        route(RouteViewAdded(title: savedTitle.isEmpty ? 'that note' : savedTitle, body: saved.body, added: placed.added));
      }
      _r.host.haptic('success');
    } catch (failure) {
      _r.warn?.call('[glyph] item not added: $failure');
      final title = noteTitle(note.body);
      route(RouteViewMissed(title: title.isEmpty ? 'that note' : title));
    }
  }

  /// Which tape this take is part of: the one a continued note holds, or a fresh one for a new file.
  String _tapeOfTake() {
    final had = _takeTape;
    if (had != null) return had;
    final continued = _writer.target;
    final appending = continued != null && (continued.recordingMs ?? 0) > 0;
    return _takeTape = (appending ? _r.tapes?.tapeId(continued.id) : null) ?? _r.newTapeId();
  }

  /// The take's segments, copied to what the screen draws.
  void _syncTake() => _set(() => _segments = _take.segments);

  // The take's host (take_host.dart): the chip, the card, the feel, the words, and Add.
  @override
  void route(RouteView? view) {
    _lingering?.cancel();
    _lingering = null;
    // A settled chip has its moment, then goes.
    final ms = lingerMs(view);
    if (ms != null && _alive) {
      _lingering = Timer(Duration(milliseconds: ms), () {
        _lingering = null;
        _set(() => _route = null);
      });
    }
    _set(() => _route = view);
  }

  @override
  void offer(Offer<Note>? offer) => _set(() => _pending = offer);

  @override
  void haptic(Haptic kind) => _r.host.haptic(kind.name);

  @override
  void changed() => _syncTake();

  // On the writer's chain, so a confirmed card's note is read back after its words are in it (`_confirmPending`). A
  // new list is made by `_confirmPending` itself.
  @override
  void addItems(Note note, String spoken, Placement placement) => unawaited(_writer.queue(() => _addItems(note, spoken, placement)));

  // ---- the live reader (live_route.dart) ----------------------------------------------------------------------------

  /// Whether a note is shared, or is a chapter of a shared book: over the lock screen, never written to.
  bool _published(String id) {
    if (_r.published(id)) return true;
    String? title;
    for (final c in _candidates) {
      if (c.id == id) title = c.title;
    }
    if (title == null) return false;
    final named = title;
    return _candidates.any((book) => isBookBody(book.note.body) && _r.published(book.id) && chaptersOf(book.note.body).any((chapter) => sameTitle(chapter.title, named)));
  }

  LiveContext<Note> _liveContext() => LiveContext<Note>(
        notes: [for (final c in _candidates) LiveCandidate<Note>(id: c.id, title: c.title, note: c.note)],
        aim: _writer.target,
        own: _home != null,
        locked: _locked,
        published: _published,
      );

  /// The take goes to `note` from here, the words so far with it: the page starts from its text and they wisp in.
  void _switchTo(Note note, Placing into) {
    _writer.aim(note, into, true);
    _writer.refresh(note.id);
    _takeTape = null;
    _set(() {
      _pendingTitle = null;
      _routed = true;
      _placing = into;
      _pageFrom = _locked ? '' : note.body;
      _moves += 1;
    });
  }

  /// The take goes to a note made at Done with `title` ("New note “House chores”" on a card).
  void _switchToNew(String title, bool task) {
    final into = placingFor(listTitle(title), said: Said(task: task));
    _writer.aim(null, into);
    _takeTape = null;
    _set(() {
      _pendingTitle = title;
      _routed = true;
      _placing = into;
      _pageFrom = _locked ? '' : listTitle(title);
      _moves += 1;
    });
  }

  /// Not this note: back to the take's own note, a new one or the note whose Speak this is. Nothing was stored.
  void _goHome() {
    final own = _home;
    final aimed = widget.placing;
    final into = own != null ? (own.id == widget.noteId && aimed != null ? aimed : placingFor(own.body, own: true)) : end;
    _writer.aim(own, into);
    _takeTape = null;
    _set(() {
      _pendingTitle = null;
      _routed = false;
      _placing = into;
      _pageFrom = null;
      _moves += 1;
    });
  }

  /// "New note", said or tapped: what was said so far is kept for the note it was said for, written at Done with the
  /// rest, and the take starts afresh in a new note (take.fork). Discard now takes back the whole take, this part
  /// too.
  void _sealAndFork() {
    final aimedAt = _writer.target;
    final title = _pendingTitle;
    _parts.add(_Part(
      note: aimedAt,
      title: title,
      placing: _writer.placing,
      markdown: _take.markdown(titled: aimedAt == null && title == null),
      titled: _take.markdown(titled: true),
      noteId: _writer.noteId,
    ));
    _take.fork();
    _forkedAt = _committed.length;
    _home = null;
    _writer.aim(null);
    _takeTape = null;
    _set(() {
      _pendingTitle = null;
      _routed = false;
      _placing = end;
      _pageFrom = null;
      _moves += 1;
    });
  }

  /// A one-shot's words landing in its note: the chip shows them under the list's last lines.
  void _showInsert(int id) {
    final insert = _inserts[id];
    if (insert == null || insert.segments.isEmpty) return;
    final placed = placeTake(insert.note.body, renderNote(insert.segments, '', const RenderOptions(titled: false)).markdown, insert.placing);
    final added = [for (final block in placed.blocks) ...block.split('\n')];
    route(_locked ? const RouteViewDone(text: 'Added to the note you named') : RouteViewAdded(title: insert.title, body: placed.body, added: added, insert: id));
  }

  /// What the live reader said to do with a phrase, done now, in order. Nothing here awaits.
  void _applySteps(List<LiveStep<Note>> steps) {
    for (final step in steps) {
      switch (step) {
        case LiveStepWords<Note>():
          _take.listen(step.segment);
          // A card's words land when it settles, after what was said while it was up: back in the order they were
          // said.
          final ordered = inOrder(_take.segments);
          if (!_sameSegments(ordered, _take.segments)) {
            _take.segments = ordered;
            _syncTake();
          }
        case LiveStepUnword<Note>():
          _take.segments = withoutWords(_take.segments, step.segments);
          _syncTake();
        case LiveStepCommand<Note>():
          _take.commandSpans.add(step.span);
        case LiveStepKeyword<Note>():
          _take.keywordSpans.add(step.span);
        case LiveStepRoute<Note>():
          _switchTo(step.note, step.placing);
        case LiveStepRouteNew<Note>():
          _switchToNew(step.title, step.task);
        case LiveStepHome<Note>():
          _goHome();
        case LiveStepPlacing<Note>():
          _writer.setPlacing(step.placing);
          _set(() => _placing = step.placing);
        case LiveStepInsert<Note>():
          _inserts[step.id] = _Insert(note: step.note, title: step.title, placing: step.placing, segments: [...step.segments]);
        case LiveStepInsertWords<Note>():
          _inserts[step.id]?.segments.addAll(step.segments);
        case LiveStepInsertUnword<Note>():
          final insert = _inserts[step.id];
          if (insert != null) insert.segments = withoutWords(insert.segments, step.segments);
        case LiveStepInsertEnd<Note>():
          _showInsert(step.id);
        case LiveStepInsertDrop<Note>():
          final insert = _inserts.remove(step.id);
          if (insert != null) {
            _take.segments = inOrder([..._take.segments, ...insert.segments]);
            _syncTake();
          }
        case LiveStepNewNote<Note>():
          _sealAndFork();
        case LiveStepCard<Note>():
          _set(() => _choice = step.card);
        case LiveStepAsk<Note>():
          final run = step.run;
          _pendingAsk = run != null ? SpokenAsk(kind: run) : SpokenAsk(kind: 'ask', instruction: step.instruction);
          _pendingAskSaid = step.instruction;
        case LiveStepChip<Note>():
          route(step.view);
        case LiveStepHaptic<Note>():
          haptic(step.haptic);
        case LiveStepLog<Note>():
          _commandLog.add(step.line);
      }
    }
  }

  static bool _sameSegments(List<Segment> a, List<Segment> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (!identical(a[i], b[i]) && a[i] != b[i]) return false;
    }
    return true;
  }

  /// Not this note, from the top line: the take goes home, and the card offers the others.
  void _notThisNote() => _applySteps(_live.decline(_liveContext(), _now()));

  Future<Note?> _fresh(Note note) async {
    try {
      return await _r.store.getNote(note.id) ?? note;
    } catch (_) {
      return note;
    }
  }

  void _confirmPending() {
    _take.confirm();
    final command = _finalCommand;
    if (command == null) return;
    _finalCommand = null;
    final trace = command.trace;
    if (trace != null) settleRecording(trace, 'confirmed');
    unawaited(_writer.settled().then((_) async {
      final done = await _runFinalActions(command.actions, command.rest);
      var saved = done.keeper;
      final ownTape = command.ownTape;
      final recordedMs = command.recordedMs;
      if (ownTape != null) {
        // The take is on the end of the continued note's own tape, and stays there: moving the file would move the
        // whole of that note's recording onto the command's note.
        await _letGo(command.temporaryId, recordedMs, ownTape);
        if (saved != null && saved.id == ownTape.id) saved = await _fresh(saved);
      } else if (saved != null && recordedMs != null) {
        int? kept;
        try {
          kept = await _r.engine.reassignRecording(command.temporaryId, saved.id, (saved.recordingMs ?? 0) > 0);
        } catch (_) {
          kept = null;
        }
        if (kept != null) {
          try {
            saved = await _r.store.setNoteRecording(saved.id, kept, saved.segments ?? const []) ?? saved;
          } catch (_) {}
        }
      } else if (recordedMs != null) {
        unawaited(_r.engine.discardRecording(command.temporaryId).catchError((Object _) {}));
      }
      _r.host.endCapture(command.locked);
      // The note the card wrote to opens, with an Undo for the lines it put in and for the other notes it changed.
      if (saved != null && !command.locked) {
        widget.onFinish(
          saved,
          command.locked,
          landing: CaptureLanding(noteId: saved.id, title: noteTitle(saved.body), blocks: done.blocks, others: done.others, into: done.into, made: done.made),
        );
        return;
      }
      widget.onFinish(saved, command.locked);
    }));
  }

  /// A confirmed recording's changes, one after another, each a guarded write against the note as it is now. The note
  /// that opens is the rest-of-what-was-said note when there is one, else the first note changed (`runFinalActions`).
  Future<({Note? keeper, List<String> blocks, List<String> others, List<String> into, List<String> made})> _runFinalActions(
    List<VoiceAction<TakeCandidate<Note>>> actions,
    String? rest,
  ) async {
    Note? first;
    var firstAdded = const <String>[];
    final appended = <({Note note, String mutation, List<String> added})>[];
    final made = <String>[];
    for (final action in actions) {
      switch (action) {
        case VoiceCreate<TakeCandidate<Note>>():
          final created = await _createFinal(action.title, action.items, action.tasks, action.body, template: action.template, place: action.place);
          if (created != null) {
            made.add(created.id);
            if (first == null) {
              first = created;
              firstAdded = const [];
            }
          }
        case VoiceAppend<TakeCandidate<Note>>():
          final fresh = await _fresh(action.note.note) ?? action.note.note;
          final placed = placeWords(fresh.body, action.text, placingOf(action.placement));
          if (placed.added.isEmpty) continue;
          final mutation = _r.store.newNoteId();
          CommandMutationResult? result;
          try {
            result = await _r.store.applyCommandMutation(CommandMutationRequest(
              mutationId: mutation,
              noteId: fresh.id,
              kind: 'append',
              beforeRevision: fresh.revision,
              beforeBody: fresh.body,
              afterBody: placed.body,
              source: fresh.source,
            ));
          } catch (_) {
            result = null;
          }
          if (result is CommandMutationResultApplied) {
            _writer.remember(result.note);
            _writer.rebase(result.note);
            appended.add((note: result.note, mutation: mutation, added: placed.added));
            if (first == null) {
              first = result.note;
              firstAdded = placed.added;
            }
          } else {
            route(RouteViewSaid(text: '${action.note.title} changed after the preview, so nothing was added to it.'));
          }
      }
    }
    var keeper = first;
    var blocks = firstAdded;
    if (rest != null && rest.isNotEmpty) {
      final kept = await _createFinalNote(rest);
      if (kept != null) {
        made.add(kept.id);
        keeper = kept;
        blocks = const [];
      }
    }
    // Every other note the recording wrote to is the landing's "other": its Undo reverses that write by its id.
    final others = <String>[];
    final into = <String>[];
    var keeperSkipped = false;
    for (final one in appended) {
      if (!keeperSkipped && keeper != null && one.note.id == keeper.id && blocks.isNotEmpty) {
        keeperSkipped = true;
        continue;
      }
      others.add(one.mutation);
      into.add(noteTitle(one.note.body));
    }
    return (keeper: keeper, blocks: blocks, others: others, into: into, made: made);
  }

  /// The confirmed new list or note of a finished recording: its title, then its items as a list, or its words.
  Future<Note?> _createFinal(String title, List<String> items, bool tasks, String? body, {String? template, String? place}) async {
    // "New bug in Kiln": the template's words, filed there once made (Recorder.fromTemplate).
    final from = template == null || place == null ? null : _r.fromTemplate(template, place, title);
    if (from != null) {
      final made = await _createFinalNote(from.body);
      if (made != null) from.file(made.id);
      return made;
    }
    final named = listTitle(title.isEmpty ? (template ?? '') : title);
    if (body != null && body.isNotEmpty) return _createFinalNote('$named\n\n$body');
    return _createFinalNote(items.isNotEmpty ? appendToList(named, items, asTasks: tasks).body : named);
  }

  Future<Note?> _createFinalNote(String body) async {
    CommandMutationResult? result;
    try {
      result = await _r.store.applyCommandMutation(CommandMutationRequest(
        mutationId: _r.store.newNoteId(),
        noteId: _r.store.newNoteId(),
        kind: 'create',
        beforeRevision: null,
        beforeBody: null,
        afterBody: body,
        source: NoteSource.capture,
      ));
    } catch (_) {
      result = null;
    }
    if (result is! CommandMutationResultApplied) {
      route(const RouteViewSaid(text: 'That note could not be created safely.'));
      return null;
    }
    return result.note;
  }

  /// Cancel tapped on the card: nothing is written. A command found inside dictation ([_FinalCommand.keep]) leaves
  /// the recording as the note it may have been; Discard ([keep] false) lets all of it go, and the take's sound goes
  /// as the command's words do.
  void _cancelPending({bool keep = true}) {
    _take.cancel();
    final command = _finalCommand;
    if (command == null) return;
    _finalCommand = null;
    final trace = command.trace;
    final kept = keep ? command.keep : null;
    if (trace != null) settleRecording(trace, kept != null ? 'cancelled, kept as a note' : 'cancelled');
    if (kept != null) {
      unawaited(_keptAfterCancel(kept));
      return;
    }
    unawaited(_letGo(command.temporaryId, command.recordedMs, command.ownTape));
    _r.host.endCapture(command.locked);
    widget.onFinish(null, command.locked);
  }

  /// What Done does for a failure on the way, for the recording a declined card leaves as a note: the words are not
  /// lost ([finish]).
  Future<void> _keptAfterCancel(Future<void> Function() keep) async {
    try {
      await keep();
    } catch (failure) {
      _r.warn?.call('[glyph] done failed: $failure');
      try {
        await _keepWords();
      } catch (again) {
        _r.warn?.call('[glyph] the words were not kept: $again');
        _doneFailed = true;
        _finished = false;
        _session.setError('The note could not be saved. Tap Done to try again.');
        _session.setPhase(Phase.failed);
      }
    }
  }

  /// The sound of a take that is not being kept: an instruction, a refused command, a command sent elsewhere or
  /// cancelled. Its file goes, unless the take was put on the end of a continued note's own tape ([ownTape]): the
  /// stop has already added it there, and that file is the whole of the note's tape, not the take's. There the sound
  /// stays, and the note is told the tape's new length with its phrases as they were, so the next take's words still
  /// line up with their sound - the same as a take that said nothing.
  Future<void> _letGo(String recordedAs, int? recordedMs, Note? ownTape) async {
    if (ownTape == null) {
      try {
        await _r.engine.discardRecording(recordedAs);
      } catch (_) {}
      return;
    }
    if (recordedMs == null) return;
    try {
      await _r.store.setNoteRecording(ownTape.id, recordedMs, ownTape.segments ?? const []);
    } catch (failure) {
      _r.warn?.call('[glyph] recording not kept: $failure');
    }
  }

  // ---- the counter -------------------------------------------------------------------------------------------------

  void _tick() {
    if (!_alive) return;
    final now = _r.now();
    _set(() {
      _recorded = _session.session?.positionMs() ?? 0;
      _diagnostics = _session.counts.copyWith();
    });
    // A command held for its note's name holds the recording open. Once the recording is over, the card of the
    // command read from it waits for a tap, however long it is up.
    final commanding = _live.holding;
    if (!_finished) _applySteps(_live.tick(now.round(), _liveContext()));
    if (!commanding && (_quiet?.due(now) ?? false)) unawaited(finish());
    // A pause, once there are words: one tip, until words come again. Before the first word the card of things to
    // say is up instead, and a tip picked under it would be spent unseen. A meeting takes no cues.
    if (!_meeting && _heard.isNotEmpty && now - _lastHeard > tipAfterMs && _tip == null) {
      final tip = tipInPause(
        notes: [for (final c in _candidates) TipNote(id: c.id, title: c.title, body: c.note.body)],
        own: _writer.noteId,
        target: _writer.target?.body,
        pluginTips: _r.pluginTips,
        turn: _tipTurn,
      );
      if (tip != null) _set(() => _tip = tip);
    }
  }

  // ---- ending ------------------------------------------------------------------------------------------------------

  Future<void> _said(String text) async {
    route(RouteViewSaid(text: text));
    await Future<void>.delayed(saidFor);
  }

  /// A meeting's Done (the Mac; meeting.dart): the transcript's phrases, the stop's last words among them, into a
  /// note titled with the date, its recording kept under it, its place in the preferences' meetings, and its better
  /// words and summary queued behind the recorder. Nothing said is nothing kept.
  Future<void> _finishMeeting(List<Segment> heardAll, Stopped stopped) async {
    final locked = _locked;
    final recordedAs = _writer.noteId;
    final segments = [
      for (final segment in heardAll)
        if (segment.text.trim().isNotEmpty) segment,
    ];
    if (segments.isEmpty) {
      if (stopped.recordedMs != null) {
        try {
          await _r.engine.discardRecording(recordedAs);
        } catch (_) {}
      }
      await _writer.undoDraft();
      _r.host.endCapture(locked);
      widget.onFinish(null, locked);
      return;
    }
    // A meeting before it has words or a recording: a sync pass that lists the note from here on must already find
    // it among the meetings, or it would send the audio that is kept on this device.
    _r.setPreferences((now) => now.copyWith(meetings: {...now.meetings, recordedAs: _meetingStartedAt}));
    // And written into the note itself (lib/meet/meeting_mark.dart), so a Library folder restored elsewhere knows it.
    final marked = withMeetingMark(meetingBody(_meetingTitled, segments), MeetingMark(startMs: _meetingStartedAt, kind: 'phone'));
    var saved = await _writer.queue(() => _writer.persist(recordedAs, marked, NoteSource.capture));
    final recordedMs = stopped.recordedMs;
    if (recordedMs != null && (_session.session?.keepsAudio ?? false)) {
      try {
        saved = await _r.store.setNoteRecording(saved.id, recordedMs, [...segments]) ?? saved;
      } catch (failure) {
        _r.warn?.call('[glyph] recording not kept: $failure');
      }
      _r.tapes?.setTapeId(saved.id, _tapeOfTake());
      _r.enqueueRefine(RefineJob(id: saved.id, fromMs: 0, recordingMs: recordedMs, baseBody: '', savedBody: saved.body, titled: false, priorSegments: const [], promptTail: '', meeting: true));
    }
    if (_r.preferences().summaries != 'off') _r.enqueueSummary(saved.id, 'meeting');
    _r.host.haptic('success');
    _r.host.endCapture(locked);
    if (!locked) await _said('Keep Ghost.md open while it is written up.');
    widget.onFinish(saved, locked);
  }

  /// Done: the take is stopped, read, written and handed back.
  ///
  /// Whatever fails on the way (a disk with no room, a library folder that has gone, a core that answers with an
  /// error), the words are not lost and the recorder is not left dead: they are kept as a note of their own, and if
  /// even that cannot be written the recorder stays up with them and Done tries again ([_doneFailed]). The original
  /// has no such net: its `finish` is one promise, and a rejection in it leaves `finished` set and the page up for
  /// good.
  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    try {
      if (_doneFailed) {
        _session.setPhase(Phase.finishing);
        await _keepWords();
      } else {
        await _finishTake();
      }
    } catch (failure) {
      _r.warn?.call('[glyph] done failed: $failure');
      try {
        await _keepWords();
      } catch (again) {
        _r.warn?.call('[glyph] the words were not kept: $again');
        _doneFailed = true;
        _finished = false;
        _session.setError('The note could not be saved. Tap Done to try again.');
        _session.setPhase(Phase.failed);
      }
    }
  }

  /// What Done falls back to: the note it had already saved, opened; or the take's words as a note of their own. The
  /// sound goes the way a take's does when its words end up elsewhere ([_letGo]). Throws when the words cannot be
  /// written at all.
  Future<void> _keepWords() async {
    final locked = _locked;
    var kept = _keptAtDone;
    if (kept == null) {
      var words = _take.markdown(titled: true);
      // A meeting's transcript is not a take's: its phrases as they were heard.
      if (words.trim().isEmpty) words = [for (final segment in _committed) segment.text].join(' ').trim();
      if (words.trim().isNotEmpty) {
        kept = await _r.store.createNote(_r.store.newNoteId(), words, NoteSource.capture);
        _keptAtDone = kept;
      }
      final sound = _soundAtDone;
      if (sound != null && sound.recordedAs != kept?.id) await _letGo(sound.recordedAs, sound.recordedMs, sound.ownTape);
      // What a draft wrote mid-take is undone, as it is when a take keeps nothing: the words are in their own note
      // now. Never after Done's own save, whose note the draft became.
      try {
        await _writer.undoDraft();
      } catch (_) {
        // The draft is the store's too; what was kept is kept.
      }
    }
    _session.setError(null);
    _r.host.endCapture(locked);
    if (kept != null) await _said('That could not be saved where it was going, so the words are a note of their own.');
    widget.onFinish(kept, locked);
  }

  Future<void> _finishTake() async {
    _r.host.setCapturing(false);
    _session.setPhase(Phase.finishing);
    _session.microphone?.stop();
    // The start's answer, once the microphone has let go, so the tape ends before it (Settings › Sounds).
    sounds.play(SoundEvent.recordStop);
    // Every command held, every card up and every one-shot open is settled before anything is composed.
    for (final segment in _queued ?? const <Segment>[]) {
      _take.listen(segment);
    }
    _queued = null;
    _applySteps(_live.close(_liveContext(), _now()));
    await _writer.refreshed();
    // The tape is kept under the id of the note the take is aimed at now, added to the end of that note's tape when
    // there is one, so its words and its sound stay one timeline (timeline.dart).
    final continued = _writer.target;
    final append = appendsTo(continued == null ? null : TapedNote.ofNote(continued));
    final ownTape = continued != null && append ? continued : null;
    final recordedAs = _writer.noteId;
    final session = _session.session;
    var stopped = const Stopped(recordedMs: null, transcript: null);
    final stopAt = _r.now();
    String? stopFailure;
    try {
      stopped = await session?.stop(StopOptions(recordAs: recordedAs, append: append)) ?? stopped;
    } catch (failure) {
      stopFailure = _failureText(failure);
      _session.setError(stopFailure);
    }
    final stopMs = (_r.now() - stopAt).round();
    _soundAtDone = (recordedAs: recordedAs, recordedMs: (session?.keepsAudio ?? false) ? stopped.recordedMs : null, ownTape: ownTape);

    // The stop's own result includes words whose phrase event was still in flight when `stop()` stopped listening:
    // compared with every phrase committed, commands and all, what it adds is read as one more phrase, so a command
    // still being said at Done is still carried out, and last words are kept (final_words.dart).
    final committed = [..._committed];
    final heardAll = withFinalWords(committed, stopped.transcript, (session?.positionMs() ?? (committed.isEmpty ? 0 : committed.last.endMs)).round());
    // A meeting: nothing is read from it.
    if (_meeting) {
      await _finishMeeting(heardAll, stopped);
      return;
    }
    for (final segment in heardAll.sublist(committed.length)) {
      _committed.add(segment);
      _heard.add(segment.text);
      _applySteps(_live.final_(segment, _liveContext(), _now()));
    }
    // Whisper's echo of the last words on the quiet after them ("…to Go. Go. Go.") is not speech (trailing_echo.dart).
    _take.segments = segmentsWithoutTrailingEcho(_take.segments);
    await _writer.refreshed();
    final locked = _locked;

    /// The note the take is aimed at now: where its words are written, which a command only the stop heard may have
    /// changed.
    final aimed = _writer.target;

    // A command's change still landing, or the take carrying on elsewhere: written before the note is.
    await _writer.settled();
    final named = _pendingTitle;

    /// Notes this recording made, and writes to other notes, for the note that opens to know.
    final made = <String>[];
    final others = <String>[];

    /// The titles of the notes written to besides the one that opens, for its toast to name.
    final intoTitles = <String>[];
    ({Note note, List<String> blocks})? lastInsert;
    void changedMeanwhile(String title) => route(RouteViewSaid(text: '$title changed as you spoke, so the words are a note of their own.'));
    String titleOr(String body, String otherwise) {
      final title = noteTitle(body);
      return title.isEmpty ? otherwise : title;
    }

    // What was said before "New note", each for the note it was said for: written first, whatever the rest of the
    // recording turns out to be, so a refused command or an ask after it takes none of it with it.
    for (final part in _parts) {
      if (part.markdown.trim().isEmpty) continue;
      final into = part.note;
      if (into != null) {
        final written = await _writer.writeInto(into.id, part.markdown, part.placing, () => part.titled);
        if (written.own) {
          made.add(written.saved.id);
          changedMeanwhile(titleOr(into.body, 'That note'));
        } else if (written.mutationId != null) {
          others.add(written.mutationId!);
          intoTitles.add(noteTitle(written.saved.body));
        }
      } else {
        final title = part.title;
        final body = title != null && title.isNotEmpty ? placeTake(listTitle(title), part.markdown, part.placing).body : part.markdown;
        made.add((await _r.store.createNote(part.noteId, body, NoteSource.capture)).id);
      }
    }

    // The reader at Done, when the live reader did nothing: a command said without the keyword, a run or an ask, a
    // new list by name (read_instruction.dart), read once from the whole transcript; after "New note", from what was
    // said after it, which is the take being finished.
    // The rest of Done: this recording's words saved as a note of their own, and whatever else it left. A declined card
    // for a command found inside dictation comes back to it (`_FinalCommand.keep`).
    late final Future<void> Function() keepAsNote;
    if (!_live.engaged) {
      final since = heardAll.sublist(_forkedAt);
      // Something was taken back: the phrases as the take kept them, by the rule the better words use (a dropped
      // stretch cut, a replacement on the same stretch kept), never the raw transcript with the taken-back words in
      // it.
      final String transcript;
      if (_live.changedWords) {
        transcript = withoutCommands(since, skip: _take.commandSpans, keywordAt: _take.keywordSpans, live: _take.segments).map((segment) => segment.text).join(' ').trim();
      } else if (_forkedAt == 0) {
        transcript = stopped.transcript ?? committed.map((segment) => segment.text).join(' ').trim();
      } else {
        transcript = since.map((segment) => segment.text).join(' ').trim();
      }
      // What happened to this recording, step by step, for Settings › Recording › Voice log.
      final voiceTrace = traceRecording(transcript);
      voiceTrace.step(
        stopFailure != null
            ? 'stop failed after $stopMs ms: $stopFailure'
            : 'stopped in $stopMs ms: ${stopped.recordedMs == null ? 'no audio kept' : '${(stopped.recordedMs! / 1000).toStringAsFixed(1)} s of audio'}, ${transcript.length} characters from ${stopped.transcript == null ? 'the live phrases (no final transcript)' : 'the final transcript'}',
      );
      final read = await readInstruction<TakeCandidate<Note>>(
        transcript,
        [for (final c in _candidates) TakeCandidate<Note>(id: c.id, title: c.title, note: c.note)],
        _r.voiceStep,
        voiceTrace,
        _r.diagnostics,
      );
      switch (read) {
        case ReadCommand<TakeCandidate<Note>>(:final actions, note: final rest, :final conversational, :final trace):
          // The stopped audio is already kept under this capture's id. The changes stay pending until this card is
          // explicitly confirmed.
          final said = [..._take.segments];
          final card = _changesCard(actions, rest);
          _take.offerChanges(heading: card.heading, action: card.action, lines: card.lines, detail: card.detail);
          // Found inside dictation: declined, the recording is kept as the note it may have been.
          final Future<void> Function()? keep = conversational
              ? () async {
                  for (final segment in said) {
                    _take.listen(segment);
                  }
                  await keepAsNote();
                }
              : null;
          _finalCommand = _FinalCommand(
            actions: actions,
            rest: rest,
            trace: trace,
            keep: keep,
            locked: locked,
            temporaryId: recordedAs,
            recordedMs: stopped.recordedMs,
            ownTape: ownTape,
          );
          _session.setPhase(Phase.listening);
          return;
        case ReadReject<TakeCandidate<Note>>(:final reason):
          // Unsupported, destructive, ambiguous, and missing-target command shapes fail closed: no note is made of
          // the command's words.
          route(RouteViewSaid(text: reason));
          await _letGo(recordedAs, stopped.recordedMs, ownTape);
          await _writer.undoDraft();
          _r.host.endCapture(locked);
          widget.onFinish(null, locked);
          return;
        case ReadRun<TakeCandidate<Note>>() || ReadAsk<TakeCandidate<Note>>() when continued != null && !locked:
          // "Hey Ghost, fix the spelling", said into a note: the words are an instruction, not the note's, and the
          // note opens with the run on it. The recording of the instruction goes, unless it went on the end of the
          // note's own tape (`_letGo`).
          await _letGo(recordedAs, stopped.recordedMs, ownTape);
          await _writer.undoDraft();
          _r.host.endCapture(locked);
          widget.onFinish(continued, locked, ask: read is ReadRun<TakeCandidate<Note>> ? SpokenAsk(kind: read.run) : SpokenAsk(kind: 'ask', instruction: (read as ReadAsk<TakeCandidate<Note>>).instruction));
          return;
        case ReadAsk<TakeCandidate<Note>>(:final instruction):
          // An ask a recording cannot carry out ("make a book called …"): its words are the note, without the
          // keyword.
          if (_take.segments.isNotEmpty) {
            final first = _take.segments.first;
            final rest = _take.segments.sublist(1);
            final bare = bareWords(first.text);
            if (bare != null && bare.keyed) {
              _take.segments = [if (bare.words.isNotEmpty) Segment(text: '${capitalise(bare.words)}.', startMs: first.startMs, endMs: first.endMs), ...rest];
              changed();
            }
          }
          final said = capitalise(instruction);
          route(RouteViewSaid(text: "“${said.length > 30 ? '${said.substring(0, 30)}…' : said}” isn't something a recording can do, so the words are saved as a note."));
        case ReadWords<TakeCandidate<Note>>(:final notice):
          if (notice != null && notice.isNotEmpty) route(RouteViewSaid(text: notice));
        case ReadRun<TakeCandidate<Note>>():
          break;
      }
    }

    keepAsNote = () async {
      // The one-shots: "add call Sam to House TODOs" said mid-take.
      for (final insert in _inserts.values) {
        final markdown = renderNote(insert.segments, '', const RenderOptions(titled: false)).markdown;
        if (markdown.trim().isEmpty) continue;
        final written = await _writer.writeInto(insert.note.id, markdown, insert.placing, () => renderNote(insert.segments).markdown);
        if (written.own) {
          made.add(written.saved.id);
          changedMeanwhile(insert.title);
          continue;
        }
        if (written.mutationId != null) {
          others.add(written.mutationId!);
          intoTitles.add(insert.title);
        }
        lastInsert = (note: written.saved, blocks: written.blocks);
        _take.touched.add(written.saved.id);
        _commandLog.add('Added “${written.blocks.map(withoutLead).join('”, “')}” to ${insert.title}${written.spot != null ? ', ${written.spot}' : ''}');
      }

      // Nothing that lays out as anything leaves nothing behind for the take's own note. Asked of the laid-out words
      // (take.hasContent), not the transcript: a cue said alone ("Bullet point.", or Whisper echoing its prompt on
      // silence) is held for a sentence that never comes, and saved from the transcript it made an empty note.
      if (!_take.hasContent) {
        // The stop has already kept the take's sound. On the end of a note's tape it stays, and the tape's new length
        // is kept with the note's phrases as they were, so the next take's words still line up with their sound; a new
        // note's goes with the note that is not made. A note's own file is never removed here: it is the whole of that
        // note's tape.
        final recordedMs = stopped.recordedMs;
        if (recordedMs != null) {
          if (continued != null && append) {
            try {
              await _r.store.setNoteRecording(continued.id, recordedMs, continued.segments ?? const []);
            } catch (failure) {
              _r.warn?.call('[glyph] recording not kept: $failure');
            }
          } else if (continued == null || _writer.routed) {
            try {
              await _r.engine.discardRecording(recordedAs);
            } catch (_) {}
          }
        }
        final opened = lastInsert?.note;
        // Why nothing was kept, where the recorder would otherwise leave before it could be read: a note named with
        // nothing said for it, or an ask said mid-take with no words of this note to run on.
        final String? why = _writer.routed && aimed != null && lastInsert == null && made.isEmpty
            ? 'Nothing was said for ${locked ? 'the note you named' : titleOr(aimed.body, 'that note')}, so nothing was added.'
            : _pendingAsk != null
                ? "Nothing was said for “${capitalise(_pendingAskSaid)}” to run on, so it didn't run."
                : null;
        if (why != null) route(RouteViewSaid(text: why));
        await _writer.undoDraft();
        _r.host.endCapture(locked);
        if (why != null && !(opened != null && !locked)) await Future<void>.delayed(saidFor);
        if (opened != null && !locked) {
          widget.onFinish(
            opened,
            locked,
            landing: CaptureLanding(
              noteId: opened.id,
              title: noteTitle(opened.body),
              blocks: lastInsert!.blocks,
              others: others.sublist(0, others.length - 1),
              into: intoTitles.sublist(0, intoTitles.isEmpty ? 0 : intoTitles.length - 1),
              made: made,
            ),
          );
        } else if (made.isNotEmpty) {
          Note? last;
          try {
            last = await _r.store.getNote(made.last);
          } catch (_) {
            last = null;
          }
          widget.onFinish(last, locked);
        } else {
          widget.onFinish(null, locked);
        }
        return;
      }

      final markdown = _take.markdown(titled: aimed == null && named == null);
      Note saved;

      /// The note's text the words were composed onto, for the better words: '' for a new note.
      var base = '';
      var blocks = <String>[];

      /// The take went into a note that already existed, switched to by a command: it opens, with no review.
      var into = false;
      if (_writer.routed && aimed != null) {
        final written = await _writer.writeInto(aimed.id, markdown, _writer.placing, () => _take.markdown(titled: true));
        saved = written.saved;
        if (written.own) {
          made.add(saved.id);
          changedMeanwhile(titleOr(aimed.body, 'That note'));
        } else {
          into = true;
          base = written.before ?? aimed.body;
          blocks = written.blocks;
          _commandLog.add('Wrote to ${noteTitle(saved.body)}${written.spot != null ? ', ${written.spot}' : ''}');
        }
      } else if (named != null) {
        // "New note “House chores”", chosen on a card: made now, titled, with the words where its title says.
        final body = placeTake(listTitle(named), markdown, _writer.placing).body;
        CommandMutationResult? result;
        try {
          result = await _r.store.applyCommandMutation(CommandMutationRequest(mutationId: _r.store.newNoteId(), noteId: _writer.noteId, kind: 'create', beforeRevision: null, beforeBody: null, afterBody: body, source: NoteSource.capture));
        } catch (_) {
          result = null;
        }
        saved = result is CommandMutationResultApplied ? result.note : await _r.store.createNote(_r.store.newNoteId(), body, NoteSource.capture);
        made.add(saved.id);
        // The better words go under its title, where the words were written.
        base = listTitle(named);
      } else {
        saved = await _writer.queue(() async => _writer.persist(_writer.noteId, await _writer.compose(markdown), NoteSource.capture));
        base = aimed != null ? (await _writer.baseBody ?? aimed.body) : '';
      }
      // From here the words are in the library: whatever fails after this opens that note ([_keepWords]).
      _keptAtDone = saved;

      RefineJob? refineJob;
      final keptMs = stopped.recordedMs;
      if (keptMs != null && (session?.keepsAudio ?? false)) {
        /// The note whose tape the take's sound goes on the end of, as it was before this take; null for a tape of its
        /// own.
        Note? tapeOf = into || saved.id == aimed?.id ? aimed : null;
        int? recordedMs = keptMs;
        if (saved.id != recordedAs) {
          // The take ended up in another note than the one its sound was kept under: a command only the stop heard, or
          // a note that changed too much to write into. Sound on the end of a note's own tape stays on it (`_letGo`).
          if (ownTape != null) {
            await _letGo(recordedAs, keptMs, ownTape);
            recordedMs = null;
          } else {
            if (!into) tapeOf = null;
            try {
              recordedMs = await _r.engine.reassignRecording(recordedAs, saved.id, appendsTo(tapeOf == null ? null : TapedNote.ofNote(tapeOf)));
            } catch (_) {
              recordedMs = null;
            }
          }
        }
        if (recordedMs != null) {
          // New phrases sit after the continued tape's, shifted by its length.
          final tape = onTape(tapeOf == null ? null : TapedNote.ofNote(tapeOf), TakeSpans(commandSpans: _take.commandSpans, keywordSpans: _take.keywordSpans), _take.segments);
          try {
            saved = await _r.store.setNoteRecording(saved.id, recordedMs, tape.segments) ?? saved;
          } catch (failure) {
            _r.warn?.call('[glyph] recording not kept: $failure');
          }
          // The tape this take wrote to, so the voice memos already in the note know it again when it is opened.
          _r.tapes?.setTapeId(saved.id, _tapeOfTake());
          // The better words: the larger model over this take's recording, later, or now in the review after a
          // recording when that runs.
          final placing = _writer.placing;
          final plainEnd = placing is PlacingEnd && (placing.lead == null || placing.lead!.isEmpty);
          refineJob = RefineJob(
            id: saved.id,
            fromMs: tape.fromMs,
            recordingMs: recordedMs,
            baseBody: base,
            savedBody: saved.body,
            titled: tapeOf == null && !into && named == null && aimed == null,
            priorSegments: tape.prior,
            promptTail: _tail(renderNote(tape.prior).plain),
            skip: tape.skip,
            keywordAt: tape.keywordAt,
            // Not the end, or the end with a line the words go on from: the better words are placed the same way.
            placing: plainEnd ? null : placing,
            // The take's own phrases whenever they are not the transcript's: a command carried out, or a take-back.
            live: _live.changedWords ? shifted(_take.segments, tape.fromMs) : null,
          );
        }
      }
      _r.host.haptic('success');
      _r.host.endCapture(locked);
      // A long take: the review's prompt would not fit the model's window, and its job is dictation's.
      final long = refineJob != null && refineJob.recordingMs - refineJob.fromMs > longNoteMs;
      final ask = _pendingAsk;
      // What the recording left in notes that were there already, and the notes it made, for the note that opens. Its
      // Undo drops the better words only for words it takes out of the note that opens: a take written into it.
      final tookBack = _live.tookBackAtDone;
      final CaptureLanding? landing = into || others.isNotEmpty || made.isNotEmpty
          ? CaptureLanding(
              noteId: saved.id,
              title: noteTitle(saved.body),
              blocks: blocks,
              others: others,
              into: intoTitles,
              made: made,
              fromMs: refineJob != null && into ? refineJob.fromMs : null,
              tookBack: tookBack.isNotEmpty ? [...tookBack] : null,
            )
          : null;
      // A take written into a note that already existed opens it with its Undo, and no review: the words are in it as
      // they were said. The better words land after the note is left (refine.dart `holdNote`).
      if (into) {
        if (refineJob != null) _r.enqueueRefine(refineJob);
        widget.onFinish(saved, locked, ask: ask, landing: landing);
        return;
      }
      // The review after a recording: it runs the better words and the formatting when it is done. Not over a locked
      // phone, whose note is not shown to whoever is holding it, and not for a long take.
      if (!locked && !long && await _r.reviewAvailable()) {
        widget.onFinish(saved, locked, review: ReviewHandoff(noteId: saved.id, job: refineJob, heard: _heard.join(' '), commands: [..._commandLog], touched: [..._take.touched]), ask: ask, landing: landing);
        return;
      }
      if (refineJob != null) _r.enqueueRefine(refineJob);
      // A long voice note's summary, when Settings says so: the recorder's own new note, behind its better words.
      // Never for a take into a note that was there, whose tape is not the note.
      final summarized = long && aimed == null && saved.source == NoteSource.capture && _r.preferences().summaries == 'long';
      if (summarized) _r.enqueueSummary(saved.id, 'recording');
      if (long && !locked) {
        // The Done line says why the note is not opened for a review, and stays long enough to be read.
        await _said(summarized ? 'Long recording. The better words come later. The summary comes later.' : 'Long recording. The better words come later.');
      }
      widget.onFinish(saved, locked, ask: ask, landing: landing);
  
    };
    return keepAsNote();
  }

  static String _tail(String text) => text.length > 200 ? text.substring(text.length - 200) : text;

  /// "Meeting instead", from the card before the first word. On the Mac this recorder becomes the meeting: the quiet
  /// stop goes, and what is heard from here is transcript. On a phone the service records it, and its `AudioRecord`
  /// cannot open while this page holds the microphone, so the take is let go first and the caller then starts it.
  void _meetingInstead() {
    if (!_r.host.isAndroid) {
      _quiet = null;
      _set(() => _meeting = true);
      _r.host.haptic('selection');
      return;
    }
    if (_finished) return;
    _finished = true;
    _r.host.setCapturing(false);
    final session = _session.session;
    if (session != null) unawaited(Future<void>.sync(session.cancel));
    _session.microphone?.stop();
    unawaited(_r.engine.discardRecording(_writer.noteId).catchError((Object _) {}));
    unawaited(_writer.undoDraft());
    _r.host.endCapture(false);
    widget.onMeeting?.call();
  }

  /// Discard: nothing of the take is kept.
  Future<void> cancel() async {
    // With the card after Done up, Discard is its Cancel: the take was finished, and its sound goes as a Cancel's
    // does.
    if (_finished) {
      if (_finalCommand != null) _cancelPending(keep: false);
      return;
    }
    // Nothing was stored mid-take, so there is nothing to take back: the holds and cards are settled and dropped.
    _live.close(_liveContext(), _now());
    _finished = true;
    _r.host.setCapturing(false);
    final session = _session.session;
    if (session != null) unawaited(Future<void>.sync(session.cancel));
    _session.microphone?.stop();
    sounds.play(SoundEvent.recordStop);
    await _writer.undoDraft();
    final locked = _locked;
    _r.host.endCapture(locked);
    widget.onFinish(null, locked);
  }

  // ---- the screen --------------------------------------------------------------------------------------------------

  void _measureTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _top.currentContext?.findRenderObject();
      if (!mounted || box is! RenderBox || !box.hasSize) return;
      // `top.offsetHeight`, a whole number: the page pads by 142px under a line of 141.70, and 130 under 130.22.
      final height = box.size.height.roundToDouble();
      if ((height - _topHeight).abs() > 0.01) setState(() => _topHeight = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phase = _session.phase;
    final locked = _locked;
    final target = _target;
    final meeting = _meeting;
    final titled = target == null && _pendingTitle == null;
    // The page as it is spoken: the take's markdown, from what the screen holds of it, with the phrase still being
    // guessed. A meeting's page is its transcript, paragraphs under the heading, with no cues read into it.
    final note = meeting
        ? (_meetingQuiet ? '## Transcript\n\nRecording. Its transcript comes when you press Done.' : meetingTranscript(_segments, _partial))
        : takeMarkdown(_segments, titled: titled, partial: _partial).markdown;
    /*
     * The card of things to say while the microphone waits (say_card.dart, tips.dart `starters`). Worked out at
     * build rather than once: which note it names must not be the one being written to (the note's own Speak, or the
     * one the take just moved to), over the lock screen it names none, and the asks are offered only where an ask
     * said first is run - a note's own Speak, unlocked.
     */
    final own = target?.id ?? _writer.noteId;
    String? sendTo;
    if (!locked && _notesRead) {
      for (final c in _candidates) {
        if (c.id != own && !isBookBody(c.note.body)) {
          sendTo = c.title;
          break;
        }
      }
    }
    final say = starters(noteTitle: sendTo, asking: target != null && !locked);
    final status = statusLine(phase: phase, error: _session.error, download: _session.download, heardWords: _segments.isNotEmpty);
    // A capture that has heard a while and produced nothing is the one worth explaining without being asked.
    final silent = soundsSilent(_session.engine, _diagnostics);
    // A note switched to shows its own text already: the card of things to say and the hint under an empty page are
    // done. A meeting's page carries its heading before a word is said, so its words are its phrases.
    final hasWords = meeting ? _segments.isNotEmpty || _partial != '' : note.isNotEmpty || _routed;
    // "Meeting instead" is offered before the first word, where a meeting can be recorded, and not for a note's own
    // Speak or over the lock screen, where a fresh recording of a meeting is not what the key asked for.
    final offerMeeting = widget.onMeeting != null && widget.noteId == null && !(widget.fromAssistant && locked) && !meeting;
    final route = _route;
    final choice = _choice;
    final pending = _pending;
    final tip = _tip;
    final gutters = EdgeInsets.only(left: t.len('app-gutter-start'), right: t.len('app-gutter-end'));
    final small = t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'));
    final shortWindow = MediaQuery.sizeOf(context).height <= 560;
    // A line of `line-height: normal` as tall as the page's and its words on the page's baseline, which the engine
    // would round to a whole pixel (the kit's `ExactLines`): the top line's words stood two device pixels high.
    Widget line(Text text) => ExactLines.of(text, normal: true, dpr: t.css.lineDpr);
    _measureTop();

    // ---- the line at the top ----
    final sound = _r.systemSound;
    final Widget? action = meeting
        ? (sound == null
            ? null
            : ComputerSound(
                live: phase == Phase.listening && _session.engine == EngineKind.whisper,
                sound: sound,
                wanted: _r.preferences().meetingSound,
                onWanted: (on) => _r.setPreferences((now) => now.copyWith(meetingSound: on)),
                onSay: (text) => this.route(RouteViewSaid(text: text)),
                style: t.textAt(t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink')),
              ))
        : _routed
            ? _topWord(t, small, 'Not this note', _notThisNote)
            : target != null
                ? _topWord(t, small, 'New note', _startNewNote)
                : null;
    final top = HeaderPane(
      key: _top,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Padding(
          // `.top { padding-block: calc(var(--app-safe-top) + var(--glacier-space-3)) var(--glacier-space-2) }`; the
          // pane pads by the safe top itself.
          // On the Mac the window's three buttons sit at the window's top left, where this line begins: the line
          // starts after their room, and says where its centre is so they are set on it (the tab bar's rule,
          // `--app-traffic-lights`; the page has none for the recorder, and its first words are under the buttons).
          padding: gutters.copyWith(left: gutters.left + trafficLightsRoom(t), top: t.space(3), bottom: t.space(2)),
          child: _lightsRow(t, Row(
            children: [
              // `.mic { align-self: center; color: var(--app-ink-2) }`
              KeyedSubtree(key: _mic, child: ExcludeSemantics(child: AppIcon(Lucide.mic, size: 14, strokeWidth: 2.4, color: t.color('app-ink-2')))),
              SizedBox(width: t.space(4)),
              // `.where { min-inline-size: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`, the word
              // after it, and `.counter { margin-inline-start: auto }` at the line's end.
              Expanded(
                child: Row(
                  children: [
                    if (status != null)
                      Flexible(child: line(Text(status, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: small)))
                    else
                      // Tapping the line shows what the pipeline has done, for diagnosing a silent capture.
                      Flexible(
                        child: AppWord(
                          key: CaptureScreen.whereKey,
                          onPressed: () => setState(() => _showDiagnostics = !_showDiagnostics),
                          child: line(
                            Text(
                              whereLine(target?.body, locked, routed: _routed, named: _pendingTitle, meeting: meeting),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: t.textAt(t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-3')),
                            ),
                          ),
                        ),
                      ),
                    if (status == null && action != null) ...[SizedBox(width: t.space(4)), action],
                  ],
                ),
              ),
              SizedBox(width: t.space(4)),
              Semantics(
                label: 'Recorded ${counter(_recorded)}',
                excludeSemantics: true,
                child: line(Text(counter(_recorded), key: CaptureScreen.counterKey, style: small.copyWith(color: t.color('app-ink-2'), fontFeatures: const [FontFeature.tabularFigures()]))),
              ),
            ],
          )),
        ),
      ),
    );

    // ---- the body ----
    final List<Widget> body;
    final livePage = route is! RouteViewAdded && !(phase == Phase.failed && !hasWords);
    if (route is RouteViewAdded) {
      body = [
        const Spacer(),
        Padding(
          padding: gutters,
          child: ListLanding(
            key: ValueKey('landing-${route.added.join('|')}'),
            title: route.title,
            body: route.body,
            added: route.added,
            // Not once Done is writing: the one-shot may be in its note already.
            onUndo: route.insert != null && phase != Phase.finishing && !_finished
                ? () {
                    _applySteps(_live.dropInsert(route.insert!));
                    this.route(RouteViewSaid(text: 'Not added to ${route.title}.'));
                  }
                : null,
          ),
        ),
        SizedBox(height: t.space(4)),
      ];
    } else if (!livePage) {
      body = [
        const Spacer(),
        Padding(
          padding: gutters,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Opening(failed: true),
              SizedBox(height: t.space(4)),
              // `.lead`: the display size, bold, close-set, in the faintest ink.
              Text(
                'Nothing was recorded.',
                style: t.textAt(t.len('app-display'), weight: 'bold', color: t.color('app-ink-4'), height: 0.95).copyWith(letterSpacing: t.len('app-tracking-display', em: t.len('app-display'))),
              ),
            ],
          ),
        ),
        SizedBox(height: t.space(4)),
      ];
    } else {
      body = [
        // The note's own page, its older text above and the words written onto its end. Over the lock screen the
        // note being continued shows none of its text.
        KeyedSubtree(
          child: LivePage(
            // Appearance › Motion › Ripples while recording (`ripples={rippling ? ripples : undefined}`).
            ripples: _r.preferences().ripples ? _ripples : null,
            // The page is remade when the note it shows changes, and when the recorder is up: "Start talking." after
            // "Starting…".
            key: ValueKey('page-${target?.id ?? _pendingTitle ?? 'new'}-$_moves-${meeting ? 'meeting' : 'take'}-${phase == Phase.starting ? 'starting' : 'up'}'),
            base: meeting
                ? '# $_meetingTitled\n'
                : locked
                    ? ''
                    : target != null
                        ? target.body
                        : _pendingTitle != null
                            ? listTitle(_pendingTitle!)
                            : '',
            markdown: note,
            placing: locked ? end : _placing,
            from: locked ? null : _pageFrom,
            under: _topHeight,
            placeholder: phase == Phase.starting ? 'Starting…' : 'Start talking.',
            arrivals: _r.preferences().wisp,
          ),
        ),
        // Listening, before the first word: the ghost leaning toward the sound, under the page and over the hint.
        // A short window (a folded phone on its side) has no room for it.
        if (!hasWords && phase == Phase.listening && route == null && !shortWindow)
          Padding(
            padding: gutters.copyWith(top: t.space(3), bottom: t.space(2)),
            child: IgnorePointer(child: Ghost(scene: GhostScene.listening, align: GhostAlign.center, heightShare: 0.2, maxWidth: t.lenOf('28rem'))),
          ),
      ];
    }
    final hint = !hasWords && phase != Phase.failed && route is! RouteViewAdded
        ? Padding(
            // `.pageHint { margin: 0 0 var(--glacier-space-3); font-size: sm; color: var(--app-ink-3) }`
            padding: gutters.copyWith(bottom: t.space(3)),
            child: Align(alignment: Alignment.centerLeft, child: line(Text(stopHint(widget.fromAssistant, _pressStops, _quiet != null), style: small))),
          )
        : null;

    // ---- the card, the chip or the tip, just above the buttons ----
    Widget? foot;
    if (choice != null && !locked) {
      foot = NoteChoiceCard<Note>(card: choice, onChoose: (chosen) => _applySteps(_live.answer(choice.id, chosen, _liveContext())));
    } else if (pending != null) {
      foot = ConfirmCard<Note>(offer: pending, onConfirm: _confirmPending, onCancel: _cancelPending);
    } else if (route != null) {
      foot = RouteChip(
        route: route,
        itemWords: _itemWords,
        // A take-back's Undo, withheld once Done is writing, as a one-shot's Not this note is.
        onUndo: route is RouteViewTookBack && route.undo != null && phase != Phase.finishing && !_finished ? () => _applySteps(_live.undoTakeBack(route.undo!)) : null,
      );
    } else if (!hasWords && phase == Phase.listening && !meeting) {
      // Before the first word: the whole of what can be said, as a card; once talking has begun, one tip at a time
      // in a pause.
      foot = SayCard(starters: say, onMeeting: offerMeeting ? _meetingInstead : null);
    } else if (tip != null && phase == Phase.listening && !meeting) {
      foot = PauseTip(key: ValueKey(tip.say), tip: tip);
    }

    final showDiagnostics = _showDiagnostics || silent || _diagnostics.errors > 0;
    final busy = phase == Phase.finishing;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.body { flex: 1; min-block-size: 0; overflow: hidden }`. With the page in it, it is the page from the top
        // of the screen, the page padding itself under the top line; otherwise it keeps clear of the line.
        Expanded(
          child: ClipRect(
            child: Padding(
              padding: EdgeInsets.only(top: livePage ? 0 : _topHeight + t.space(4)),
              // With the page in it, the page is never shorter than the top line's pane it pads itself under
              // (`.livePage { flex: 1; min-block-size: 0; padding-block-start: var(--wisp-under) }`), and what
              // stands under it, the ghost and the hint, keeps its size: in a window too short for all three the
              // body runs over its own foot and is cut there (`.body { overflow: hidden }`), the ghost still whole
              // under the top line. Flexed like any column, the page gave up all its room and the ghost stood
              // under the top line's glass (the Fold on its side, with the card of things to say).
              child: livePage
                  ? CustomMultiChildLayout(
                      delegate: _PageOverTail(least: _topHeight),
                      children: [
                        LayoutId(id: _BodySlot.page, child: body.first),
                        LayoutId(id: _BodySlot.tail, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [...body.skip(1), ?hint])),
                      ],
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...body, ?hint]),
            ),
          ),
        ),
        if (foot != null) Padding(padding: gutters, child: foot),
        if (showDiagnostics)
          Padding(
            // `.diagnostics { margin: 0 0 var(--glacier-space-2); font-size: xs; color: ink-3; text-align: center }`
            padding: gutters.copyWith(bottom: t.space(2)),
            child: line(Text(diagnosticsLine(_session.engine, _diagnostics), textAlign: TextAlign.center, style: t.textAt(t.fontSize('xs'), color: t.color('app-ink-3')))),
          ),
        Padding(
          // `.footer { padding-block: var(--glacier-space-2) calc(var(--app-safe-bottom) + var(--glacier-space-4)) }`
          padding: gutters.copyWith(top: t.space(2), bottom: t.len('app-safe-bottom') + t.space(4)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppWord(key: CaptureScreen.discardKey, onPressed: busy ? null : () => unawaited(cancel()), child: const PageWord('Discard')),
              Semantics(
                label: 'Stop and save',
                button: true,
                excludeSemantics: true,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppPill(
                      key: CaptureScreen.doneKey,
                      // A recorder that could not start has nothing to finish; one whose save failed tries again.
                      onPressed: (phase == Phase.failed && !_doneFailed) || busy ? null : () => unawaited(finish()),
                      icon: const AppIcon(Lucide.square, size: 16),
                      child: const Text('Done'),
                    ),
                    // The level ring on Done: proof the microphone hears you, without a meter to read. Scale, not
                    // size, so it composites instead of laying out five times a second.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _level,
                          builder: (context, level, _) => AnimatedScale(
                            scale: 1 + level * 0.18,
                            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : t.duration('glacier-duration-fast'),
                            curve: t.curve('glacier-ease-out'),
                            child: DecoratedBox(
                              decoration: BoxDecoration(border: Border.all(color: t.color('app-ink').withValues(alpha: 0.25), width: 2), borderRadius: BorderRadius.circular(t.radius('full'))),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    // The phone's back gesture ends the take the way Done does: what was said is kept, and a take with nothing in it
    // leaves nothing behind.
    return OnBack(
      onBack: () => unawaited(finish()),
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: Stack(
          children: [
            Positioned.fill(child: column),
            // The rings, over the page, its tips and its buttons, under the top line, so the mic sits in front of
            // them; never in the way of a touch.
            if (phase == Phase.starting || phase == Phase.listening) Positioned.fill(child: VoiceWaves(anchor: _mic)),
            top,
          ],
        ),
      ),
    );
  }

  /// `.app-word.newNote`: the word after the line, in ink, semibold, at the line's size.
  /// The top line as the row the Mac's window buttons are set on, where the page is under the Mac's title bar.
  Widget _lightsRow(Tokens t, Widget row) => titlebarOverlay(t) ? MacLightsRow(child: row) : row;

  Widget _topWord(Tokens t, TextStyle small, String word, VoidCallback onPressed) =>
      AppWord(
        key: CaptureScreen.actionKey,
        onPressed: onPressed,
        child: ExactLines.of(Text(word, maxLines: 1, softWrap: false, style: t.textAt(t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))), normal: true, dpr: t.css.lineDpr),
      );
}

enum _BodySlot { page, tail }

/// The body with the note's page in it: the page takes what the ghost and the hint under it leave, and never less
/// than [least], the top line's pane it pads itself under; in less room than that the two under it run over the
/// body's foot, which cuts them (CaptureScreen.module.css `.body:has(> .livePage)`, `.livePage`).
class _PageOverTail extends MultiChildLayoutDelegate {
  _PageOverTail({required this.least});

  final double least;

  @override
  void performLayout(Size size) {
    final tail = layoutChild(_BodySlot.tail, BoxConstraints.tightFor(width: size.width));
    final page = math.max(least, size.height - tail.height);
    layoutChild(_BodySlot.page, BoxConstraints.tight(Size(size.width, page)));
    positionChild(_BodySlot.page, Offset.zero);
    positionChild(_BodySlot.tail, Offset(0, page));
  }

  @override
  bool shouldRelayout(_PageOverTail old) => old.least != least;
}

/// A caught thing as words (`core/failure.ts` `failureText`): an error's message, or the thing itself as text.
String _failureText(Object failure) {
  if (failure is String) return failure;
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}

/// The microphone's level as a [RippleSource]: each change of the level told to whoever follows it.
class _LevelRipples implements RippleSource {
  const _LevelRipples(this.level);
  final ValueListenable<double> level;

  @override
  void Function() subscribe(void Function(double level) listener) {
    void told() => listener(level.value.clamp(0.0, 1.0));
    level.addListener(told);
    return () => level.removeListener(told);
  }
}

final RegExp _escaped = RegExp(r'\\(.)');

/// What the card says a finished recording's changes are: the lines as they will land (`changesCard`).
({String heading, String action, List<String> lines, String? detail}) _changesCard(List<VoiceAction<TakeCandidate<Note>>> actions, String? rest) {
  String show(String line) => withoutLead(line).replaceAllMapped(_escaped, (m) => m[1]!);
  final one = actions.length == 1 && (rest == null || rest.isEmpty) ? actions.first : null;
  final lines = <String>[];
  for (final action in actions) {
    final added = switch (action) {
      VoiceCreate<TakeCandidate<Note>>() => (action.body != null && action.body!.isNotEmpty) ? [action.body!] : action.items,
      VoiceAppend<TakeCandidate<Note>>() => placeWords(action.note.note.body, action.text, placingOf(action.placement)).added,
    };
    if (one == null) {
      lines.add(switch (action) {
        VoiceCreate<TakeCandidate<Note>>() => 'New ${action.body != null && action.body!.isNotEmpty ? 'note' : 'list'}: ${listTitle(action.title)}',
        VoiceAppend<TakeCandidate<Note>>() => 'Add to ${action.note.title}:',
      });
    }
    for (final line in added) {
      lines.add('${one != null ? '' : '  '}${show(line)}');
    }
  }
  if (rest != null && rest.isNotEmpty) {
    final shown = show(rest);
    lines.add('Keep as a note: “${shown.length > 120 ? shown.substring(0, 120) : shown}${rest.length > 120 ? '…' : ''}”');
  }
  switch (one) {
    case VoiceCreate<TakeCandidate<Note>>():
      return (
        heading: 'Create ${listTitle(one.title).replaceAllMapped(_escaped, (m) => m[1]!)}',
        action: 'Create',
        lines: lines,
        detail: (one.body != null && one.body!.isNotEmpty) ? 'As a new note' : (one.items.isNotEmpty ? 'As a new list' : null),
      );
    case VoiceAppend<TakeCandidate<Note>>():
      return (heading: 'Add to ${one.note.title}', action: 'Add', lines: lines, detail: one.placement.how == PlacementHow.item ? 'In its list' : 'Where it fits');
    case null:
      return (heading: actions.length > 1 ? '${actions.length} changes' : 'This change', action: 'Do it', lines: lines, detail: null);
  }
}
