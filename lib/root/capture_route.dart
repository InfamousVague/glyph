/// How a capture begins and where the app goes when it ends: the shell's half of the recorder
/// (lib/capture/ui/capture_screen.dart is the recorder itself), and of a meeting
/// (lib/capture/ui/meeting_screen.dart). A port of `src/app/shell/useCaptureRoute.ts`.
///
/// A capture can begin several ways, and all of them arrive at the same screen: a Speak button (the home dock's,
/// the sidebar's foot, the palette's, a note's own) and, only in a build with the phone assistant, the side key
/// while the app is closed or open. Each capture is a fresh mount (shell/screen.dart `ScreenCapture.fresh`), so a
/// second press mid-capture cannot inherit the first one's microphone. **No always-on microphone**: nothing here
/// opens one; the capture screen does, while it is on screen.
///
/// Every one of them waits for the deferred deletes first (notes/note_actions.dart): the recorder reads its targets
/// as it mounts, and a note deleted a moment ago must not be one of them (capture/launch.dart).
///
/// A meeting on a phone is the phone's own service, and starting one is the app's to do in order: the note first
/// (its date title, `source: capture`), its tape id, its place in the preferences' `meetings`, and only then the
/// service asked. The service can answer that the microphone has yet to be granted (the app waits for the
/// activity's answer and asks again), that a meeting is already being recorded (the app opens that one), or that
/// it could not start, and the service can fail after saying it started. Whatever the way, THE UNDO HAS ONE OWNER:
/// [CaptureRoute] deletes the note, drops the preference, and says why. The notification's Discard, with the app
/// closed, is remembered by the service until the app has done the same and said so, which happens here as well.
/// And while a meeting is being recorded the microphone is taken, so every way into a capture opens the meeting
/// screen instead.
///
/// What differs:
/// - The hook's options and refs are this object's fields; [CaptureRouteWorld] is what it asks of the app.
/// - **The Mac's recorder in meeting mode** is reached where there is no service and the recorder says a meeting
///   can be recorded, which is the Mac app (lib/root/voice_wiring.dart); the page asked `isAndroid`.
/// - **The place is asked for by the app** ([CaptureRouteWorld.tagNew], an entry's [EntryAim.tag]) once the
///   capture's screen has gone, as `tagAfter` waited for the screen to change: called straight after the next
///   screen is put up, never at [CaptureRoute.start], so no location prompt is raised over the recorder's own.
/// - The guide's "Not yet" for a side key pressed on a page still to be read ([CaptureRouteWorld.tooSoon]) is
///   asked only where a guide is given.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/meeting_sort.dart' show withAppFiled;
import '../ai/summaries.dart' show SummaryKind;
import '../capture/landing.dart';
import '../capture/launch.dart';
import '../capture/meeting.dart' show meetingTitle;
import '../capture/meeting_live.dart';
import '../capture/place.dart' as place;
import '../capture/recorder.dart';
import '../editor/media/clip_refs.dart' show withTapeId;
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/template.dart' show Placing;
import '../core/untouched.dart';
import '../shell/screen.dart';
import 'voice_wiring.dart';

/// Said when the activity refused the microphone, and when the service could not say why it failed.
const String microphoneRefused = 'Ghost.md needs the microphone to record a meeting.';
const String meetingFailed = 'The meeting could not start.';

/// A capture aimed at a journal's entry (`EntryAim`): where in the entry the words go, and where to land when
/// nothing was kept for it.
class EntryAim {
  const EntryAim({required this.id, required this.placing, required this.nothing, this.tag});

  /// The entry's id: the capture is aimed at it.
  final String id;

  /// Where the words go: on from its time, or into its to-do list (core/template.dart `openEnd`).
  final Placing placing;

  /// Where to land when nothing was kept for the entry: the journal, or the entry as it was made.
  final Future<Screen> Function() nothing;

  /// Where the entry was written, asked once the recorder has gone, where its journal keeps that: told whether a
  /// review is live for it, and whether the phone is locked (`tag`).
  final void Function({required bool reviewing, required bool locked})? tag;
}

/// What the route asks of the app (`CaptureRouteOptions`, and the modules the hook imports).
class CaptureRouteWorld {
  const CaptureRouteWorld({
    required this.screen,
    required this.setScreen,
    required this.refresh,
    required this.flushDeletes,
    required this.clearStage,
    required this.say,
    required this.getNote,
    required this.createNote,
    required this.deleteNote,
    required this.fileNewNote,
    required this.untouched,
    this.filedIn,
    this.prefs,
    this.tooSoon,
    this.sayTooSoon,
    this.now,
    this.tagNew,
    this.askAi,
  });

  /// Where a take's own new note was made (core/location.ts `tagNewNotesIfWanted`), asked once the capture's
  /// screen has gone: quiet over a locked phone, and waiting while a review is live for the note. Absent, no note
  /// keeps a place.
  final void Function(String id, {required bool reviewing, required bool quiet})? tagNew;

  /// The screen that is up, and the way to put another up.
  final Screen Function() screen;
  final void Function(Screen next) setScreen;

  /// The notes read again.
  final Future<void> Function() refresh;

  /// Makes every deferred delete final (notes/note_actions.dart `flushDeletes`).
  final Future<void> Function() flushDeletes;

  /// Everything over the screen put away - the sheet, the walkthrough - so the bare recorder is all that is left.
  final VoidCallback clearStage;

  /// A line to the person: why a meeting did not start.
  final void Function(String message) say;

  /// The note store's three, and a new note filed where the list is looking (`fileNewNote`).
  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String body, {required NoteSource source}) createNote;
  final Future<void> Function(String id) deleteNote;
  final void Function(String id) fileNewNote;

  /// The workspace a note is filed in, by id, or null: read after [fileNewNote] files a meeting, so the meetings'
  /// sorting knows the app filed it there and not the person (lib/ai/meeting_sort.dart `withAppFiled`). None, and a
  /// meeting filed so is the person's.
  final String? Function(String id)? filedIn;

  /// The records of the notes nobody has written in (core/untouched.dart).
  final UntouchedNotes untouched;

  /// The preferences; the app's own unless given.
  final PreferencesStore? prefs;

  /// The phone's assistant asked (lib/claude/claude_voice.dart): Claude is talked to, answering whether it was. No,
  /// where Claude cannot answer here (its plugin off, no key, the phone locked), and the assistant records as before.
  /// None, and it always records.
  final Future<bool> Function()? askAi;

  /// The side key pressed while the guide is on a page still to be read: "Not yet", not a recording.
  final bool Function()? tooSoon;
  final VoidCallback? sayTooSoon;
  final int Function()? now;
}

class CaptureRoute {
  CaptureRoute({required this.voice, required this.world}) {
    final live = voice.live;
    if (live != null) {
      _unhear = live.onMeetingEvent(_heard);
      _unwatch = live.subscribe(_discarded);
    }
    _keys = voice.captureKey?.listen((_) => sideKey());
    _assists = voice.assistKey?.listen((_) => assist());
  }

  final Voice voice;
  final CaptureRouteWorld world;

  VoidCallback? _unhear;
  VoidCallback? _unwatch;
  StreamSubscription<void>? _keys;
  StreamSubscription<void>? _assists;
  bool _gone = false;

  PreferencesStore get _prefs => world.prefs ?? preferences;
  int _now() => world.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  void dispose() {
    _gone = true;
    _unhear?.call();
    _unwatch?.call();
    unawaited(_keys?.cancel());
    unawaited(_assists?.cancel());
  }

  /// The meeting screen for the meeting being recorded, when there is one: true when it opened (`showMeeting`).
  bool showMeeting([bool fromAssistant = false]) {
    final live = voice.live?.meetingStateNow();
    final id = live?.noteId;
    if (live == null || !live.recording || id == null) return false;
    final current = world.screen();
    if (current is ScreenMeeting && current.noteId == id) return true;
    world.setScreen(ScreenMeeting.fresh(id, fromAssistant, now: _now()));
    return true;
  }

  /// The entry the capture on screen is aimed at, until it is finished.
  EntryAim? _entryAim;

  /// A capture, from the side key ([fromAssistant]) or a Speak button, into [noteId] when it was one note's; for a
  /// journal's entry, with where the words go in it and what to do after ([entry]) (`start`).
  Future<void> start(bool fromAssistant, {String? noteId, EntryAim? entry}) async {
    // A meeting being recorded holds the microphone: the way to it, not a second recording.
    if (showMeeting(fromAssistant)) return;
    _entryAim = entry != null && entry.id == noteId ? entry : null;
    // Whether the phone is locked is read before the recorder is up: its screen asks at once.
    await voice.readLocked();
    await afterPendingDeletes(world.flushDeletes, () {
      if (!_gone) world.setScreen(ScreenCapture.fresh(fromAssistant, noteId: noteId, placing: entry == null ? null : place.Placing.fromJson(entry.placing.toJson()), now: _now()));
    });
  }

  /// As the app opens (the hook's two boot effects): the side key launched it and a recording is what it asked
  /// for, only in a build with the assistant; else a meeting already being recorded shows its screen, once. The
  /// phone's assistant launched it: Claude is talked to where it can answer ([CaptureRouteWorld.askAi]), else it is
  /// a recording as before.
  void boot() {
    final launched = voice.launch == 'capture' || voice.launch == 'assist';
    if (voice.assistant && launched && !(world.tooSoon?.call() ?? false)) {
      if (voice.launch == 'assist' && !showMeeting(true)) {
        unawaited(_talkOrRecord(() => start(true)));
      } else {
        unawaited(start(true));
      }
    } else {
      showMeeting(false);
    }
  }

  /// Claude talked to, where it can answer; else [otherwise].
  Future<void> _talkOrRecord(FutureOr<void> Function() otherwise) async {
    final ask = world.askAi;
    if (ask != null) {
      try {
        if (await ask()) return;
      } catch (_) {
        // Claude could not be asked: the assistant records, as it always has.
      }
    }
    if (!_gone) await otherwise();
  }

  /// The phone's assistant, while the app is already open: over a capture or a meeting, the side key's own
  /// ([sideKey]); otherwise Claude is talked to where it can answer, else it is the side key's capture.
  void assist() {
    if (_gone || !voice.assistant) return;
    final current = world.screen();
    if (current is ScreenCapture || current is ScreenMeeting) return sideKey();
    if (world.tooSoon?.call() ?? false) return world.sayTooSoon?.call();
    unawaited(_talkOrRecord(sideKey));
  }

  /// The side key, while the app is already open. During a capture it is the stop button; over a meeting's screen
  /// it does nothing (Done and the notification stop a meeting, not the key); otherwise the stage is cleared and a
  /// capture starts.
  void sideKey() {
    if (_gone || !voice.assistant) return;
    final current = world.screen();
    if (current is ScreenCapture) return world.setScreen(current.stopped());
    if (current is ScreenMeeting) return;
    if (world.tooSoon?.call() ?? false) return world.sayTooSoon?.call();
    world.clearStage();
    unawaited(start(true));
  }

  // ---- a meeting on the phone ------------------------------------------------------------------------------------

  /// The meeting waiting for the microphone to be granted, to be asked for again once it is.
  ({String id, String title, bool fromAssistant})? _pendingMeeting;

  /// The meetings this app started, whose failure is this app's to undo.
  final Set<String> _started = {};

  /// Everything the start made, taken back, and the person told why (`undo`).
  Future<void> _undo(String id, String? why) async {
    _started.remove(id);
    if (_pendingMeeting?.id == id) _pendingMeeting = null;
    _prefs.update((now) => now.copyWith(meetings: {...now.meetings}..remove(id)));
    voice.summaries?.dropSummary(id);
    try {
      await world.deleteNote(id);
    } catch (_) {
      // Gone already.
    }
    final current = world.screen();
    if (current is ScreenMeeting && current.noteId == id) world.setScreen(const Screen.list());
    await world.refresh().catchError((Object _) {});
    if (why != null) world.say(why);
  }

  /// The service asked; what it answers decides what happens next (`ask`).
  Future<void> _ask(String id, String title, bool fromAssistant) async {
    final service = voice.service;
    if (service == null) return _undo(id, meetingFailed);
    // Other apps' sound too when the switch is on and this phone can: the activity then asks Android's
    // screen-share consent before the service starts.
    final otherApps = _prefs.value.meetingSound && (voice.sound?.supported ?? false);
    String answer;
    try {
      answer = await service.startMeeting(id, title, otherApps: otherApps);
    } catch (_) {
      answer = meetingFailed;
    }
    if (answer == 'started') {
      _pendingMeeting = null;
      _started.add(id);
      world.setScreen(ScreenMeeting.fresh(id, fromAssistant, now: _now()));
      // The list read again, so the note is there, recording, when Back leaves the meeting screen.
      unawaited(world.refresh().catchError((Object _) {}));
      return;
    }
    if (answer == 'permission') {
      _pendingMeeting = (id: id, title: title, fromAssistant: fromAssistant);
      return;
    }
    if (answer == 'recording') {
      // One is being recorded already: that one, and not a second note for it.
      await _undo(id, null);
      showMeeting(fromAssistant);
      return;
    }
    await _undo(id, answer);
  }

  /// A note a take made, filed where the list is looking; a meeting so filed (the Mac's, whose note is made at its
  /// Done) is remembered as the app's filing, for the meetings' sorting (lib/ai/meeting_sort.dart).
  void _fileNew(String id) {
    world.fileNewNote(id);
    if (!_prefs.value.meetings.containsKey(id)) return;
    final filed = world.filedIn?.call(id);
    if (filed != null) _prefs.update((now) => withAppFiled(now, id, filed));
  }

  /// A press of Meeting while one is being made is the same press.
  bool _making = false;

  /// A meeting: the Mac's recorder in meeting mode, or the phone's service with the meeting screen over it
  /// (`meeting`).
  Future<void> meeting([bool fromAssistant = false]) async {
    // The Mac: the recorder itself, with the dictation features off (lib/capture/ui/capture_screen.dart `meeting`).
    // Its window keeps running behind other apps, so there is no service to start and no note to make first.
    if (voice.service == null && voice.recorder.canRecordMeeting) {
      await afterPendingDeletes(world.flushDeletes, () {
        if (!_gone) world.setScreen(ScreenCapture.fresh(fromAssistant, meeting: true, now: _now()));
      });
      return;
    }
    if (showMeeting(fromAssistant) || _making) return;
    _making = true;
    try {
      final startedAt = _now();
      final title = meetingTitle(startedAt, voice.recorder.locale);
      // The tape's name in the note's own words as well as this device's record (lib/editor/media/clip_refs.dart).
      final tape = voice.recorder.newTapeId();
      final note = await world.createNote(withTapeId('# $title\n', tape), source: NoteSource.capture);
      world.fileNewNote(note.id);
      voice.recorder.tapes?.setTapeId(note.id, tape);
      final filed = world.filedIn?.call(note.id);
      _prefs.update((now) => withAppFiled(now.copyWith(meetings: {...now.meetings, note.id: startedAt}), note.id, filed));
      // Its write-up queued as the phone's own (`enqueueSummary(id, 'meeting', {native: true})`).
      if (_prefs.value.summaries != 'off') voice.summaries?.enqueueSummary(note.id, SummaryKind.meeting, native: true);
      await _ask(note.id, title, fromAssistant);
    } finally {
      _making = false;
    }
  }

  /// What the service says, for the meetings this app started: the microphone's answer, and a start that failed
  /// after it was asked for; and, while its screen is up, a meeting that ended from the notification or the cap.
  void _heard(MeetingEvent event) {
    final pending = _pendingMeeting;
    // The microphone's answer is the waiting meeting's: only one waits, so a push that names no note is its too.
    if (event.event == 'permission' && pending != null && (event.noteId == null || pending.id == event.noteId)) {
      if (event.granted == true) {
        unawaited(_ask(pending.id, pending.title, pending.fromAssistant));
      } else {
        unawaited(_undo(pending.id, microphoneRefused));
      }
      return;
    }
    final id = event.noteId;
    if (id == null) {
      if (event.event == 'open') showMeeting(false);
      return;
    }
    if (event.event == 'failed' && (_started.contains(id) || pending?.id == id)) {
      unawaited(_undo(id, event.message ?? meetingFailed));
      return;
    }
    if (event.event == 'started') _started.remove(id);
    final current = world.screen();
    if ((event.event == 'stopped' || event.event == 'discarded') && current is ScreenMeeting && current.noteId == id) {
      world.setScreen(const Screen.list());
      unawaited(world.refresh().catchError((Object _) {}));
    }
    if (event.event == 'open') showMeeting(false);
  }

  /// A meeting the notification's Discard threw away with the app closed: its note goes, as Discard here would
  /// have taken it, and the service is told so it can stop listing it.
  final Set<String> _handled = {};
  void _discarded() {
    for (final id in voice.live?.meetingStateNow()?.discarded ?? const <String>[]) {
      if (!_handled.add(id)) continue;
      unawaited(_undo(id, null).then((_) => voice.service?.forgetDiscarded(id)).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  /// The meeting screen left: home (`leftMeeting`).
  void leftMeeting() => world.setScreen(const Screen.list());

  /// A capture over: filed, and the app on whatever comes next - the note with its run or review, the note the
  /// words went into ([landing]), the note spoken into, or home (`finished`).
  Future<void> finished(Note? note, bool locked, {ReviewHandoff? review, SpokenAsk? ask, CaptureLanding? landing}) async {
    await _finished(note, locked, review: review, ask: ask, landing: landing);
    // Where the take's new note was made, now that the screen has changed (`tagAfter`).
    final tag = _tagAfter;
    _tagAfter = null;
    tag?.call();
  }

  void Function()? _tagAfter;

  Future<void> _finished(Note? note, bool locked, {ReviewHandoff? review, SpokenAsk? ask, CaptureLanding? landing}) async {
    // A spoken note lands in the workspace the list is showing, unless it is filed already; so do the notes it
    // made. A note that was there already and only had words put into it stays where it was filed, or unfiled: one
    // a command wrote into (`landing.blocks`), or the note whose own mic this was. Read before the first await,
    // while the capture screen is still the one aimed.
    final current = world.screen();
    final aimedAt = current is ScreenCapture ? current.noteId : null;
    final existed = note != null && ((landing != null && landing.blocks.isNotEmpty && !landing.made.contains(note.id)) || (note.id == aimedAt && !(landing?.made.contains(note.id) ?? false)));
    // A journal's entry said into: nothing kept for it lands where its opener says, the journal or the entry as it
    // was made, and the entry nobody wrote in is taken back from there.
    final aim = _entryAim?.id == aimedAt ? _entryAim : null;
    _entryAim = null;
    final kept = aim != null && note != null && note.id == aim.id && !world.untouched.isUntouched(aim.id, note.body, recordingMs: note.recordingMs, starred: note.starred, archivedAt: note.archivedAt);
    if (aim != null && !kept && (note == null || note.id == aim.id)) {
      final where = await aim.nothing();
      await world.refresh();
      world.setScreen(locked ? const Screen.list() : where);
      return;
    }
    if (note != null && !existed) _fileNew(note.id);
    for (final made in landing?.made ?? const <String>[]) {
      _fileNew(made);
    }
    await world.refresh();
    final entryTag = kept ? aim.tag : null;
    if (entryTag != null) _tagAfter = () => entryTag(reviewing: review?.job != null, locked: locked);
    // The take's own new note starts with where the phone was, once the capture screen has gone. Not a note it
    // only wrote into, and not the notes its spoken commands made (`landing.made`), which are the app's doing.
    final own = note != null && !existed && !(landing?.made.contains(note.id) ?? false) ? note.id : null;
    final tagNew = world.tagNew;
    if (own != null && tagNew != null) _tagAfter = () => tagNew(own, reviewing: review?.job != null, quiet: locked);
    Future<Note?> fresh(String id) => world.getNote(id).then<Note?>((found) => found, onError: (Object _) => null);
    // Words a recording put into a note that was already there, or a card after Done confirmed: that note opens,
    // read fresh, with an Undo for what went in. Not over a locked phone.
    if (note != null && landing != null && !locked) {
      final key = _now();
      world.setScreen(ScreenNote(await fresh(note.id) ?? note, landing: Keyed(landing, key), ask: ask == null ? null : Keyed(ask, key), review: review == null ? null : Keyed(review, key)));
      return;
    }
    // An instruction spoken into a note: the note opens with the run on it.
    if (note != null && ask != null) {
      world.setScreen(ScreenNote(await fresh(note.id) ?? note, ask: Keyed(ask, _now())));
      return;
    }
    // The review after a recording runs in the note, read fresh, since its words just changed.
    if (note != null && review != null) {
      world.setScreen(ScreenNote(await fresh(note.id) ?? note, review: Keyed(review, _now())));
      return;
    }
    // Talking into a note from the note: back to that note, read fresh, since its words just changed. Otherwise
    // the list, the new note at its top: reading it back is a tap away, and a locked phone has already stepped
    // back behind its lock screen, so nothing of the note is shown to whoever is holding it.
    if (aimedAt != null && !locked) {
      final back = await fresh(note?.id ?? aimedAt);
      if (back != null) {
        world.setScreen(ScreenNote(back));
        return;
      }
    }
    world.setScreen(const Screen.list());
  }
}
