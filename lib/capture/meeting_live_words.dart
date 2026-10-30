/// A meeting recorded on this phone, its words live while someone is looking (Matt, 2026-10-30: "If possible add real
/// time transcriptions for meetings"; docs/MEET.md, "Live words on this device").
///
/// The phone's meeting service has the microphone and keeps the tape (MeetingService.kt). While the meeting screen,
/// or the meeting's note at its Transcript, is on the screen, the service also hands its samples (other apps' sound
/// mixed in, when the meeting has it: both sides of a call) to the speech model the recorder uses, in the mode a
/// meeting's words are heard in: each phrase transcribed once when it is finished, no guesses at the words still being
/// said, and nothing kept, since the service keeps the tape (native/src/capture.rs `capture_start {partials: false,
/// keep: false}`, whisper/stream.rs `Mode::MEETING`). Each phrase goes into the meeting's live words
/// (lib/meet/live_transcript.dart), timed from the meeting's start and named by nobody, as the write-up names nobody
/// where it cannot.
///
/// - **Only while a meeting the person started is recording**, the app is in front (so the screen is on) and
///   someone is looking ([watch]). The screen going off, the app left, the screen closed, the meeting stopped: the
///   model lets go at once, and the service stops handing samples over. The words already heard stay for the screen to
///   show again. No always-on microphone: this opens none; it listens to the one the meeting service already holds,
///   under its notification.
/// - **What it costs** (measured on the Mac, native/src/capture.rs `what_a_meeting_s_live_words_cost_a_minute_of_talk`):
///   a minute of talk is about thirteen phrases, each one pass of the model over its window, where a dictation's
///   guesses would be five times as many passes more. So it is a setting ([LiveWordsChoice]): on the Mac, on; on a
///   phone, while charging, since even a phrase at a time keeps four cores busy for a fifth to a third of the meeting.
/// - **The write-up still runs after the meeting** and its transcript replaces the live words, as now.
/// - **An older build** (a service that cannot hand samples over, a core that does not know the meeting's mode) has
///   no live words, and says so by answering false; the meeting records as it did.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/stored.dart';
import '../meet/live_transcript.dart';
import 'engine.dart' show CaptureEvent, CaptureEventSegment, dictationCapturing;
import 'meeting_live.dart';
import 'native_backend.dart' show NativeCaptureBackend;

/// When a meeting's words are heard live on this device (Settings › Recording › Live transcript during meetings).
enum LiveWordsChoice {
  off,

  /// Only while the phone is charging: a phone's default.
  charging,

  /// Always, while someone is looking: the Mac's default.
  on,
}

/// The choice's word, as kept.
String liveWordsWord(LiveWordsChoice choice) => choice.name;

/// The choice a device starts with: on a phone, while charging; elsewhere, on.
LiveWordsChoice liveWordsDefault({required bool phone}) => phone ? LiveWordsChoice.charging : LiveWordsChoice.on;

/// This device's own choice, kept on it alone (a phone's and a Mac's differ, as their batteries do).
const String liveWordsKey = 'glyph-meeting-live-words';

/// The setting, this device's ([liveWordsKey]).
class LiveWordsSetting extends ValueNotifier<LiveWordsChoice> {
  LiveWordsSetting({required bool phone, Stored? kept})
      : _kept = kept ?? stored,
        super(_read(kept ?? stored, phone));

  final Stored _kept;

  static LiveWordsChoice _read(Stored kept, bool phone) => kept.read<LiveWordsChoice>(
        liveWordsKey,
        liveWordsDefault(phone: phone),
        (raw) => LiveWordsChoice.values.where((c) => c.name == raw).firstOrNull,
      );

  @override
  set value(LiveWordsChoice next) {
    if (next == value) return;
    _kept.write(liveWordsKey, liveWordsWord(next));
    super.value = next;
  }
}

/// What the meeting service is asked.
abstract interface class LiveWordsHost {
  /// The service starts, or stops, handing its samples to the speech model; false where this build's cannot.
  Future<bool> feed(bool on);
}

/// The speech model, as a meeting's words are heard.
abstract interface class LiveRecogniser {
  /// Listens, a phrase at a time and keeping nothing; false where the core cannot (one from before, which is then let
  /// go at once).
  Future<bool> start();

  /// What it hears: [CaptureEventSegment]s, each a phrase on the capture's own timeline.
  Stream<CaptureEvent> get events;

  /// Lets go.
  Future<void> stop();
}

/// A meeting's words live on this device (see the header).
class MeetingLiveWords extends ChangeNotifier {
  MeetingLiveWords({
    required this.meeting,
    required this.host,
    required this.recogniser,
    required this.setting,
    required this.charging,
    required this.inFront,
    bool Function()? dictating,
    int Function()? now,
    LiveTranscripts? store,
  })  : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        dictating = dictating ?? (() => dictationCapturing),
        store = store ?? liveTranscripts;

  /// Whether a dictation holds the speech model (engine.dart [dictationCapturing]): the meeting's words wait for it,
  /// and never take the model from it or let it go under it.
  final bool Function() dictating;

  final MeetingLive meeting;
  final LiveWordsHost host;
  final LiveRecogniser recogniser;
  final ValueListenable<LiveWordsChoice> setting;

  /// Whether the phone is charging now.
  final bool Function() charging;

  /// Whether the app is in front, which on a phone means its screen is on.
  final bool Function() inFront;
  final int Function() _now;
  final LiveTranscripts store;

  /// The notes someone is looking at: the meeting screen's, or a note at its Transcript.
  final Map<String, int> _watching = {};
  VoidCallback? _offState;

  /// The note whose words are being heard now; null while none are.
  String? _hearing;

  /// When the model began hearing, on the meeting's own clock (ms since it began).
  int _base = 0;
  StreamSubscription<CaptureEvent>? _heard;

  /// A start or a stop under way, so two never overlap.
  Future<void> _turn = Future<void>.value();

  /// Whether this build cannot hear a meeting's words (an older service or core): asked no more.
  bool _cannot = false;

  /// The note being heard now, for tests and the screens.
  String? get hearing => _hearing;

  /// Why note [noteId]'s words are not being heard while it records, in the screens' words; null while they are, or
  /// would be (the model starting).
  String? why(String noteId) {
    if (_hearing == noteId) return null;
    if (_cannot) return 'This build can’t show the words live. The transcript comes when the meeting is written up.';
    return switch (setting.value) {
      LiveWordsChoice.off => 'Live transcript is off. Turn it on in Settings › Recording.',
      LiveWordsChoice.charging when !charging() => 'The live transcript comes on while the phone is charging. Change it in Settings › Recording.',
      _ => dictating() ? 'Back once the recording you started has finished.' : null,
    };
  }

  /// Note [noteId] is on the screen (the meeting screen, or its Transcript). Answers the way to say it is not.
  VoidCallback watch(String noteId) {
    _watching[noteId] = (_watching[noteId] ?? 0) + 1;
    if (_watching.length == 1 && _watching[noteId] == 1) {
      _offState = meeting.subscribe(check);
      setting.addListener(check);
      // The battery and a dictation say nothing when they move: looked at now and then while someone looks.
      _looking = Timer.periodic(lookEvery, (_) => check());
    }
    check();
    var stopped = false;
    return () {
      if (stopped) return;
      stopped = true;
      final left = (_watching[noteId] ?? 1) - 1;
      if (left <= 0) {
        _watching.remove(noteId);
      } else {
        _watching[noteId] = left;
      }
      if (_watching.isEmpty) {
        _offState?.call();
        _offState = null;
        setting.removeListener(check);
        _looking?.cancel();
        _looking = null;
      }
      check();
    };
  }

  /// How often the battery and a dictation are looked at while someone looks.
  static const Duration lookEvery = Duration(seconds: 5);
  Timer? _looking;

  /// Which note's words should be heard now: the meeting recording here, while it is watched, the app in front and
  /// the setting allows it; null for none.
  String? get _wanted {
    if (_cannot) return null;
    final state = meeting.state;
    final id = state?.noteId;
    if (state == null || !state.recording || id == null || !_watching.containsKey(id) || !inFront() || dictating()) return null;
    return switch (setting.value) {
      LiveWordsChoice.off => null,
      LiveWordsChoice.charging => charging() ? id : null,
      LiveWordsChoice.on => id,
    };
  }

  /// Looks again: the meeting, the screen, the setting or the battery moved. Starts or stops the model to match.
  void check() {
    _turn = _turn.then((_) => _settle()).catchError((Object failure) {
      debugPrint('[meeting] its live words stopped: $failure');
    });
  }

  /// Every listener let go: the app's end.
  Future<void> close() async {
    _watching.clear();
    _offState?.call();
    _offState = null;
    _looking?.cancel();
    _looking = null;
    setting.removeListener(check);
    await (_turn = _turn.then((_) => _stop()));
  }

  Future<void> _settle() async {
    // A dictation took the model meanwhile: it is the dictation's now, and the meeting's words wait for it to end.
    if (_hearing != null && dictating()) {
      _hearing = null;
      await host.feed(false);
      unawaited(_heard?.cancel());
      _heard = null;
    }
    final wanted = _wanted;
    if (wanted == _hearing) {
      // The setting or the battery may have moved what the screens say ([why]).
      notifyListeners();
      return;
    }
    if (_hearing != null) await _stop();
    // The meeting has ended: its words stay, not live, until the write-up gives the note its own.
    final state = meeting.state;
    for (final id in store.notes.toList()) {
      final words = store.of(id);
      if (words != null && words.from == LiveFrom.device && words.live && !(state?.recording == true && state?.noteId == id)) store.ended(id);
    }
    if (wanted != null) await _start(wanted);
  }

  Future<void> _start(String noteId) async {
    final state = meeting.state;
    final started = state?.startedAt;
    _base = started != null ? _now() - started.toInt() : (state?.elapsedMs.toInt() ?? 0);
    _heard = recogniser.events.listen((event) {
      if (event is! CaptureEventSegment || _hearing != noteId || dictating()) return;
      final segment = event.segment;
      store.heard(noteId, from: LiveFrom.device, lines: [LiveLine(at: _base + segment.startMs, text: segment.text)]);
    });
    if (!await recogniser.start()) {
      _cannot = true;
      notifyListeners();
      unawaited(_heard?.cancel());
      _heard = null;
      await recogniser.stop();
      return;
    }
    if (!await host.feed(true)) {
      _cannot = true;
      notifyListeners();
      unawaited(_heard?.cancel());
      _heard = null;
      await recogniser.stop();
      return;
    }
    _hearing = noteId;
    notifyListeners();
    // The words so far, and the Live badge, from the first moment it listens.
    store.heard(noteId, from: LiveFrom.device);
  }

  Future<void> _stop() async {
    if (_hearing == null) return;
    _hearing = null;
    notifyListeners();
    await host.feed(false);
    unawaited(_heard?.cancel());
    _heard = null;
    // A dictation that took the model meanwhile keeps it.
    if (!dictating()) await recogniser.stop();
  }
}

/// The speech model in the Rust core, as a meeting's words are heard (native_backend.dart `startMeetingWords`).
class NativeLiveRecogniser implements LiveRecogniser {
  NativeLiveRecogniser(this.backend);
  final NativeCaptureBackend backend;

  @override
  Future<bool> start() => backend.startMeetingWords();

  @override
  Stream<CaptureEvent> get events => backend.events;

  @override
  Future<void> stop() => backend.cancel();
}

/// This device's, where its phone has the meeting service (set by lib/root/voice_wiring.dart): what the meeting screen
/// and a note's Transcript watch with.
MeetingLiveWords? meetingLiveWordsHere;

/// Whether note [noteId] is the meeting the phone's service is recording now.
bool meetingRecordingHere(String noteId) {
  final state = meetingLiveWordsHere?.meeting.state;
  return state != null && state.recording && state.noteId == noteId;
}

LiveWordsSetting? _setting;

/// This device's setting (Settings › Recording › Live transcript during meetings), made on first use: on a phone,
/// while charging, unless chosen otherwise; elsewhere, on.
LiveWordsSetting get liveWordsSetting => _setting ??= LiveWordsSetting(phone: !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// A test's own setting in place of this device's; null to make it afresh.
@visibleForTesting
set liveWordsSettingForTests(LiveWordsSetting? setting) => _setting = setting;
