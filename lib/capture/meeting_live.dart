/// The meeting being recorded, as the app knows it: one store every screen reads. A port of
/// `src/app/capture/meetingLive.ts`.
///
/// A meeting on Android is recorded by a foreground service, which outlives the screen: the screen can go off and
/// the app can be left, and the microphone stays open with only the notification showing (a swipe from Recents stops
/// the meeting, and what was recorded is written up). So the app does not hold the state, it asks for it. The
/// service's state is read once a second while the app is visible and something is listening (the shelf, the meeting
/// screen, the capture route), at once when the app comes back to the front, and whenever the service says something
/// has changed ([MeetingLive.heard], fanned out to whoever asked with [MeetingLive.onMeetingEvent]). Nothing is
/// asked of a host without the service: the poll starts only where it exists, and everywhere else the state is null.
///
/// Whether Ghost.md may notify is read the same way ([MeetingLive.canNotifyNow]), again on the prompt's answer
/// ([MeetingLive.notified]) and on every return to the front, since the person can turn notifications off in the
/// phone's settings while the app is closed. The two questions the rest of the app asks are here too: which note is
/// being recorded, and whether a write-up is running ([MeetingLive.writeUpRunning], for the refine queue, which
/// wants the same speech model).
///
/// This is a meeting the person started and can see in the notification the whole time: no always-on microphone.
///
/// What differs:
/// - The web's module is one store for the page, wired to `window` as it loads. Here it is a [MeetingLive], made
///   with what the web reads from elsewhere: the host ([MeetingHost]: `window.GlyphHost`'s `meetingState` and
///   `canNotify` as `core/host.ts` reads them, and the page's visibility), `core/recordings.ts`'s
///   `writeUpRunningNow`, and the clock. What the web wires to `window` are methods whoever owns the bridge calls:
///   [MeetingLive.heard] (`window.__glyph.meeting`), [MeetingLive.notified] (`window.__glyph.notified`),
///   [MeetingLive.visibilityChanged] (the document's `visibilitychange`) and [MeetingLive.notesChanged] (the notes
///   store's `NOTES_CHANGED`).
/// - `core/externalStore.ts` is [ExternalStore] here, a plain listenable with the web's `get`, `set`, `update` and
///   `subscribe`; its React half (`use`) is whatever widget listens to it. `useMeetingState` is
///   [MeetingLive.subscribe] and [MeetingLive.state]: the poll runs while anyone is subscribed. `useCanNotify` is
///   [MeetingLive.canNotify].
/// - An event's name and a stop's reason stay the words the service said (`MeetingEvent.event`, `.reason`), since the
///   web takes any word there and hands it on; [MeetingEventName] and [MeetingEvent.kind] are the names this build
///   knows.
/// - "The same thing said again" is the web's `JSON.stringify` of two states compared; here it is `==`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A value with listeners (`core/externalStore.ts`): the web's store, without React.
class ExternalStore<T> implements ValueListenable<T> {
  ExternalStore(T initial) : _current = initial;

  T _current;
  final Set<VoidCallback> _listeners = <VoidCallback>{};

  T get() => _current;

  @override
  T get value => _current;

  /// Replaces the value, and tells every listener if it is a different one.
  void set(T next) {
    if (identical(next, _current) || (next is num || next is bool || next is String) && next == _current) return;
    _current = next;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  /// `set` with the value worked out from the one before.
  void update(T Function(T was) fn) => set(fn(_current));

  /// Called after every change; answers the way to stop.
  VoidCallback subscribe(VoidCallback listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);
}

/// The service's state, as it answers it.
@immutable
class MeetingState {
  const MeetingState({
    required this.recording,
    required this.noteId,
    required this.title,
    required this.startedAt,
    required this.elapsedMs,
    required this.silenced,
    this.otherApps,
    this.otherAppsHeard,
    this.otherAppsNote,
    required this.writingUp,
    required this.discarded,
  });

  /// A meeting is being recorded now.
  final bool recording;

  /// Its note, its title and when it began, while one is.
  final String? noteId;
  final String? title;
  final num? startedAt;
  final num elapsedMs;

  /// Another app took the microphone: the file keeps growing with silence.
  final bool silenced;

  /// Other apps' sound is being mixed into the meeting now (native generation 25). Null, as the two below are, in a
  /// state from an older binary, or one a test makes, which has no word on it: that is "no".
  final bool? otherApps;

  /// Something but silence has come through it.
  final bool? otherAppsHeard;

  /// Why other apps' sound was asked for and is not in the meeting (sharing declined, or stopped), or null.
  final String? otherAppsNote;

  /// The note the service is writing up now, or null.
  final String? writingUp;

  /// Notes the notification's Discard threw away that the app has not yet deleted.
  final List<String> discarded;

  /// The web's spread: this state with some of it said again. A field that can be null is given in a function.
  MeetingState copyWith({
    bool? recording,
    String? Function()? noteId,
    String? Function()? title,
    num? Function()? startedAt,
    num? elapsedMs,
    bool? silenced,
    String? Function()? writingUp,
    List<String>? discarded,
  }) =>
      MeetingState(
        recording: recording ?? this.recording,
        noteId: noteId == null ? this.noteId : noteId(),
        title: title == null ? this.title : title(),
        startedAt: startedAt == null ? this.startedAt : startedAt(),
        elapsedMs: elapsedMs ?? this.elapsedMs,
        silenced: silenced ?? this.silenced,
        otherApps: otherApps,
        otherAppsHeard: otherAppsHeard,
        otherAppsNote: otherAppsNote,
        writingUp: writingUp == null ? this.writingUp : writingUp(),
        discarded: discarded ?? this.discarded,
      );

  /// The state by its keys, in the order the web writes them; other apps' three only where the binary said them.
  Map<String, Object?> toJson() => {
        'recording': recording,
        'noteId': noteId,
        'title': title,
        'startedAt': startedAt,
        'elapsedMs': elapsedMs,
        'silenced': silenced,
        if (otherApps != null) ...{'otherApps': otherApps, 'otherAppsHeard': otherAppsHeard, 'otherAppsNote': otherAppsNote},
        'writingUp': writingUp,
        'discarded': discarded,
      };

  @override
  bool operator ==(Object other) =>
      other is MeetingState &&
      other.recording == recording &&
      other.noteId == noteId &&
      other.title == title &&
      other.startedAt == startedAt &&
      other.elapsedMs == elapsedMs &&
      other.silenced == silenced &&
      other.otherApps == otherApps &&
      other.otherAppsHeard == otherAppsHeard &&
      other.otherAppsNote == otherAppsNote &&
      other.writingUp == writingUp &&
      listEquals(other.discarded, discarded);

  @override
  int get hashCode => Object.hash(recording, noteId, title, startedAt, elapsedMs, silenced, otherApps, otherAppsHeard, otherAppsNote, writingUp, Object.hashAll(discarded));

  @override
  String toString() => 'MeetingState(${jsonEncode(toJson())})';
}

/// The events this build knows; `name` is the service's word.
enum MeetingEventName { started, silenced, sounding, stopped, discarded, failed, permission, asked, open }

/// Why a meeting stopped, where this build knows the word; `name` is the service's.
enum MeetingStopReason { done, notification, cap, error, died }

/// What the service says, as its push carries it.
@immutable
class MeetingEvent {
  const MeetingEvent({required this.event, required this.noteId, required this.elapsedMs, this.reason, this.granted, this.message});

  /// The event's name as the service said it. [kind] is the one this build knows it as.
  final String event;

  /// The meeting's note. Null only on the two the activity says without one in hand: the microphone's answer
  /// (`permission`, which is the waiting meeting's) and a tap on the recording notification (`open`).
  final String? noteId;
  final num elapsedMs;

  /// With `stopped`: Done or the notification's Stop, the cap, a read error, or a meeting a kill left that was
  /// finished at launch. The service's word; [stopReason] is the one this build knows it as.
  final String? reason;

  /// With `permission`: whether the microphone was granted.
  final bool? granted;

  /// With `failed`: the app's-voice line to say.
  final String? message;

  /// [event] as a name this build knows, or null for one it does not.
  MeetingEventName? get kind {
    for (final name in MeetingEventName.values) {
      if (name.name == event) return name;
    }
    return null;
  }

  /// [reason] as a reason this build knows, or null.
  MeetingStopReason? get stopReason {
    for (final known in MeetingStopReason.values) {
      if (known.name == reason) return known;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is MeetingEvent &&
      other.event == event &&
      other.noteId == noteId &&
      other.elapsedMs == elapsedMs &&
      other.reason == reason &&
      other.granted == granted &&
      other.message == message;

  @override
  int get hashCode => Object.hash(event, noteId, elapsedMs, reason, granted, message);

  @override
  String toString() => 'MeetingEvent(event: $event, noteId: $noteId, elapsedMs: $elapsedMs, reason: $reason, granted: $granted, message: $message)';
}

/// The keys an event is read from (`keyof MeetingEvent`), for holding the Kotlin to them.
const List<String> meetingEventKeys = ['event', 'noteId', 'elapsedMs', 'reason', 'granted', 'message'];

const MeetingState _none = MeetingState(recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: null, discarded: []);

String? _str(Object? value) => value is String ? value : null;
num? _num(Object? value) => value is num && value.isFinite ? value : null;

/// The service's JSON as a state, or null for anything that is not one: an older host answers nothing this shape.
MeetingState? parseMeetingState(Object? raw) {
  if (raw is! Map) return null;
  final recording = raw['recording'];
  if (recording is! bool) return null;
  // Said only by a binary of generation 25 or later; an older one's state has no word on other apps' sound.
  final says = raw.containsKey('otherApps');
  final discarded = raw['discarded'];
  return MeetingState(
    recording: recording,
    noteId: _str(raw['noteId']),
    title: _str(raw['title']),
    startedAt: _num(raw['startedAt']),
    elapsedMs: _num(raw['elapsedMs']) ?? 0,
    silenced: raw['silenced'] == true,
    otherApps: says ? raw['otherApps'] == true : null,
    otherAppsHeard: says ? raw['otherAppsHeard'] == true : null,
    otherAppsNote: says ? _str(raw['otherAppsNote']) : null,
    writingUp: _str(raw['writingUp']),
    discarded: discarded is List ? discarded.whereType<String>().toList() : const [],
  );
}

/// A `meeting` push as an event, or null for one this build cannot read.
MeetingEvent? parseMeetingEvent(String json) {
  try {
    final got = jsonDecode(json) as Map;
    final event = _str(got['event']);
    final noteId = _str(got['noteId']);
    if (event == null || event.isEmpty || ((noteId == null || noteId.isEmpty) && event != 'permission' && event != 'open')) return null;
    final granted = got['granted'];
    return MeetingEvent(
      event: event,
      noteId: noteId,
      elapsedMs: _num(got['elapsedMs']) ?? 0,
      reason: _str(got['reason']),
      granted: granted is bool ? granted : null,
      message: _str(got['message']),
    );
  } catch (_) {
    return null;
  }
}

/// The host, as this store asks it (`window.GlyphHost` through `core/host.ts`, and the document's visibility).
abstract class MeetingHost {
  /// Whether this host can be asked at all: one with the meeting service (`typeof GlyphHost.meetingState`).
  bool get hasMeetings;

  /// The service's state as JSON, or null where it will not say (`meetingStateJson`).
  String? meetingStateJson();

  /// Whether Ghost.md may notify (`canNotify`): false where there is nobody to ask.
  bool canNotify();

  /// Whether the app is on screen (`document.visibilityState === 'visible'`).
  bool get visible;
}

const Duration _poll = Duration(milliseconds: 1000);

/// The one store of the meeting being recorded.
class MeetingLive {
  MeetingLive({required this.host, required this.writeUpRunningNow, int Function()? now}) : now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final MeetingHost host;

  /// Whether a write-up is listening or summarizing now, by the last look at the jobs (`core/recordings.ts`).
  final bool Function() writeUpRunningNow;

  /// The clock, in milliseconds since the epoch (`Date.now()`).
  final int Function() now;

  final ExternalStore<MeetingState?> _state = ExternalStore<MeetingState?>(null);
  final ExternalStore<bool> _notify = ExternalStore<bool>(false);
  final Set<void Function(MeetingEvent event)> _listeners = <void Function(MeetingEvent event)>{};
  final Set<VoidCallback> _notifiedListeners = <VoidCallback>{};

  /// Ask the service now, keep the answer, and answer it: null where there is no service to ask.
  MeetingState? readMeetingState() {
    if (!host.hasMeetings) return _state.get();
    final json = host.meetingStateJson();
    MeetingState? parsed;
    if (json != null) {
      try {
        parsed = parseMeetingState(jsonDecode(json));
      } catch (_) {
        parsed = null;
      }
    }
    // A new object each read would tell every listener every second; only a change does.
    final was = _state.get();
    final next = parsed ?? _none;
    if (was == null || was != next) _state.set(next);
    return _state.get();
  }

  /// The state as it is now, fresh from the service where there is one: for callers outside a widget.
  MeetingState? meetingStateNow() => readMeetingState();

  /// Whether Ghost.md may notify, fresh from the host, and kept for the screens that follow it.
  bool canNotifyNow() {
    final can = host.canNotify();
    _notify.set(can);
    return can;
  }

  /// Whether Ghost.md may notify, as last read: for a widget to follow (`useCanNotify`).
  ValueListenable<bool> get canNotify => _notify;

  /// Hear the meeting's own notification prompt being answered, whichever way; answers the way to stop.
  VoidCallback onNotified(VoidCallback listener) {
    _notifiedListeners.add(listener);
    return () {
      _notifiedListeners.remove(listener);
    };
  }

  /// Whether a write-up is running, by the last look at the jobs and the service: the refine queue holds while one
  /// is.
  bool writeUpRunning() => writeUpRunningNow() || _state.get()?.writingUp != null;

  /// Hear every `meeting` push; answers the way to stop.
  VoidCallback onMeetingEvent(void Function(MeetingEvent event) listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  /// What a push says about the state, before the service is asked again: enough for a host with no service to ask.
  void _applyEvent(MeetingEvent event) {
    final was = _state.get() ?? _none;
    switch (event.event) {
      case 'started':
        _state.set(was.copyWith(
          recording: true,
          noteId: () => event.noteId,
          startedAt: () => was.startedAt ?? now() - event.elapsedMs,
          elapsedMs: event.elapsedMs,
          silenced: false,
        ));
      case 'silenced' || 'sounding':
        _state.set(was.copyWith(silenced: event.event == 'silenced', elapsedMs: event.elapsedMs));
      case 'stopped':
        _state.set(was.copyWith(recording: false, noteId: () => null, title: () => null, startedAt: () => null, elapsedMs: 0, silenced: false, writingUp: () => event.noteId));
      case 'failed':
        _state.set(was.copyWith(recording: false, noteId: () => null, title: () => null, startedAt: () => null, elapsedMs: 0, silenced: false));
      case 'discarded':
        final noteId = event.noteId;
        _state.set(was.copyWith(
          recording: false,
          noteId: () => null,
          title: () => null,
          startedAt: () => null,
          elapsedMs: 0,
          silenced: false,
          discarded: noteId != null && noteId.isNotEmpty ? <String>{...was.discarded, noteId}.toList() : was.discarded,
        ));
      default:
        break;
    }
  }

  /// The service said something (`window.__glyph.meeting`): the state follows it, the service is asked again, and
  /// every listener hears it. A push this build cannot read is dropped whole.
  void heard(String json) {
    final event = parseMeetingEvent(json);
    if (event == null) return;
    _applyEvent(event);
    readMeetingState();
    for (final listener in _listeners.toList()) {
      listener(event);
    }
  }

  /// The notification prompt was answered (`window.__glyph.notified`).
  void notified() {
    canNotifyNow();
    for (final listener in _notifiedListeners.toList()) {
      listener();
    }
  }

  /// The app went to the back or came to the front (the document's `visibilitychange`): back in front, the service
  /// and the phone's settings are asked again.
  void visibilityChanged() {
    if (!host.visible) return;
    if (host.hasMeetings) {
      readMeetingState();
      canNotifyNow();
    }
  }

  /// The activity's refresh, as the notes store echoes it (`NOTES_CHANGED`): the service may have moved while the app
  /// was away.
  void notesChanged() {
    if (host.hasMeetings) readMeetingState();
  }

  // ---- polling -----------------------------------------------------------------------------------------------------

  int _subscribers = 0;
  Timer? _timer;

  void _pollNow() {
    if (!host.visible || !host.hasMeetings) return;
    readMeetingState();
  }

  void _startPolling() {
    if (_timer != null) return;
    _pollNow();
    _timer = Timer.periodic(_poll, (_) => _pollNow());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// The store's subscribe, with the poll running while anyone listens (what `useMeetingState` subscribes with).
  VoidCallback subscribe(VoidCallback listener) {
    final off = _state.subscribe(listener);
    _subscribers += 1;
    if (_subscribers == 1) _startPolling();
    var stopped = false;
    return () {
      if (stopped) return;
      stopped = true;
      off();
      _subscribers -= 1;
      if (_subscribers == 0) _stopPolling();
    };
  }

  /// The meeting's state as last known: null where nothing can record one. Live for whoever called [subscribe].
  MeetingState? get state => _state.get();

  /// For tests: the store as a test wants it.
  @visibleForTesting
  void setMeetingStateForTests(MeetingState? next) => _state.set(next);
}
