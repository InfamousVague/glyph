/// The phone's meeting service, as the app asks it: the [MeetingHost] meeting_live.dart is written against, and
/// the rest of what `window.GlyphHost` gave the web app's meetings (`core/host.ts`): starting and stopping one,
/// its write-up, the notification prompt, and what a launch was for. Over the `ghost_md/meeting` channel and its
/// events (android/…/ghost_md/MeetingBridge.kt, which lists every method and event with its answer).
///
/// A meeting is recorded by a foreground service with its own notification, started by a person and stoppable
/// from that notification the whole time: no always-on microphone. It keeps recording with the screen off and the
/// app left; swiping the app away stops it and what was recorded is written up.
///
/// What differs from the web's host:
///
/// - **The bridge is asynchronous.** `GlyphHost.meetingState()` answered at once on the page's thread; a channel
///   answers a moment later. [MeetingHost]'s two questions are still answered at once, from what was last heard:
///   every ask starts a fresh read, and when a fresh read differs from what was said, [onStateChanged] is called
///   so the store asks again (`MeetingLive.readMeetingState`). The state is read once before [attach] returns, so
///   the first answer is a real one.
/// - **A push is delivered after the state it speaks of.** The web's `window.__glyph.meeting(json)` handler read
///   `meetingState()` in the same breath; here the state is read first, then the push is handed on ([bind]), so
///   `MeetingLive.heard` finds the service's own account when it looks.
///
/// ```dart
/// final host = await DeviceMeetingHost.attach();
/// final live = MeetingLive(host: host, writeUpRunningNow: () => false);
/// host.bind(live);
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'meeting_live.dart';
import 'system_sound.dart' show SoundSupport;

/// One thing the phone said without being asked: [name] is the Tauri page's inbound call (`meeting`,
/// `recordingDone`, `notified`, `capture`, `screenOff`) and [argument] what it was called with (JSON, or null).
typedef HostEvent = ({String name, String? argument});

class DeviceMeetingHost implements MeetingHost {
  DeviceMeetingHost._(this._visible);

  static const MethodChannel channel = MethodChannel('ghost_md/meeting');
  static const EventChannel eventChannel = EventChannel('ghost_md/meeting/events');

  /// Starts listening to the phone and reads the service's state once. Off Android there is no service: the host
  /// answers that it has none, and nothing is ever asked of it.
  static Future<DeviceMeetingHost> attach({bool Function()? visible}) async {
    final host = DeviceMeetingHost._(visible ?? _inFront);
    if (!Platform.isAndroid) return host;
    host._subscription = eventChannel.receiveBroadcastStream().listen(host._pushed);
    try {
      await host.refresh();
      host._has = true;
    } on MissingPluginException {
      host._has = false;
    }
    return host;
  }

  static bool _inFront() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  final bool Function() _visible;
  StreamSubscription<Object?>? _subscription;
  bool _has = false;
  String? _state;
  bool _notify = false;
  Future<void>? _reading;
  final StreamController<HostEvent> _events = StreamController<HostEvent>.broadcast(sync: true);

  /// Called when a fresh read of the service differs from what [meetingStateJson] or [canNotify] last said.
  void Function()? onStateChanged;

  /// Everything the phone says, after the state it speaks of has been read.
  Stream<HostEvent> get events => _events.stream;

  @override
  bool get hasMeetings => _has;

  @override
  bool get visible => _visible();

  /// The service's state as last heard; asking starts a fresh read (see the library's header).
  @override
  String? meetingStateJson() {
    _ask();
    return _state;
  }

  /// Whether Ghost.md may notify, as last heard; asking starts a fresh read.
  @override
  bool canNotify() {
    _ask();
    return _notify;
  }

  /// A fresh read nobody waits for: a phone that will not answer leaves what was last heard.
  void _ask() => unawaited(refresh().then<void>((_) {}, onError: (Object _) {}));

  /// Reads the service's state and whether the app may notify, now. One read at a time: an ask made while one is
  /// under way waits for that one.
  Future<void> refresh() => _reading ??= _read().whenComplete(() => _reading = null);

  Future<void> _read() async {
    final state = await channel.invokeMethod<String>('meetingState');
    final notify = await channel.invokeMethod<bool>('canNotify') ?? false;
    final changed = state != _state || notify != _notify;
    _state = state;
    _notify = notify;
    if (changed) onStateChanged?.call();
  }

  Future<void> _pushed(Object? event) async {
    if (event is! Map) return;
    final name = event['name'];
    if (name is! String) return;
    // The state first, so whoever hears the push finds the service's own account of it.
    final after = onStateChanged;
    onStateChanged = null;
    try {
      await refresh();
    } catch (_) {
      // The push is still worth hearing.
    } finally {
      onStateChanged = after;
    }
    _events.add((name: name, argument: event['argument'] as String?));
  }

  /// Wires a store to this host: its pushes ([MeetingLive.heard], [MeetingLive.notified]) and its re-reads.
  /// Answers the way to stop.
  void Function() bind(MeetingLive live) {
    onStateChanged = () {
      live.readMeetingState();
      live.canNotifyNow();
    };
    final heard = events.listen((event) {
      switch (event.name) {
        case 'meeting':
          if (event.argument != null) live.heard(event.argument!);
        case 'notified':
          live.notified();
      }
    });
    return () {
      onStateChanged = null;
      unawaited(heard.cancel());
    };
  }

  /// Stops listening to the phone.
  Future<void> detach() async {
    await _subscription?.cancel();
    await _events.close();
  }

  // ---- what the app asks of the service (the web's `GlyphHost` methods, each with the bridge's own answer) -------

  /// Start recording a meeting into [noteId]'s tape, with other apps' sound when [otherApps] is set (Android then
  /// asks to share the screen). "started" (`meeting {event: started}` confirms it and `failed` undoes it),
  /// "permission" (the microphone was asked for; retry on `meeting {event: permission, granted: true}`),
  /// "recording" (one is being recorded already), or a reason in the app's words.
  Future<String> startMeeting(String noteId, String title, {bool otherApps = false}) async =>
      await channel.invokeMethod<String>(otherApps ? 'startMeetingWith' : 'startMeeting', {'noteId': noteId, 'title': title, 'otherApps': otherApps}) ?? 'The meeting could not start.';

  /// Done: the service stops recording and carries on as the write-up.
  Future<void> stopMeeting() => channel.invokeMethod<void>('stopMeeting');

  /// Discard: the service stops and deletes the tape; the app deletes the note itself.
  Future<void> discardMeeting() => channel.invokeMethod<void>('discardMeeting');

  /// Whether this phone can put other apps' sound in a meeting (Android 10 and later), and why not.
  Future<SoundSupport?> meetingSound() async {
    final json = await channel.invokeMethod<String>('meetingSound');
    if (json == null) return null;
    final said = (jsonDecode(json) as Map).cast<String, Object?>();
    return SoundSupport(supported: said['supported'] == true, reason: said['reason'] as String?);
  }

  /// Ask to post notifications: "allowed", "asked" (the answer arrives as the `notified` event) or "blocked".
  Future<String> requestNotifications() async => await channel.invokeMethod<String>('requestNotifications') ?? 'blocked';

  /// Write [noteId] up (again): "queued", or a reason. [now] skips the battery rule.
  Future<String> writeUp(String noteId, {bool now = false}) async => await channel.invokeMethod<String>('writeUp', {'noteId': noteId, 'now': now}) ?? 'not queued';

  /// The note went to the trash: its write-up is cancelled.
  Future<void> cancelWriteUp(String noteId) => channel.invokeMethod<void>('cancelWriteUp', {'noteId': noteId});

  /// Before a reset: every write-up cancelled, resolving once any run in hand has let go.
  Future<void> cancelWriteUps() => channel.invokeMethod<void>('cancelWriteUps');

  /// The app has deleted a note the notification's Discard threw away.
  Future<void> forgetDiscarded(String noteId) => channel.invokeMethod<void>('forgetDiscarded', {'noteId': noteId});

  /// What this launch was for, once: "capture" (the side key or the shortcut, only in a build with the assistant
  /// on), "meeting" (the recording notification tapped) or "".
  Future<String> takeLaunch() async => await channel.invokeMethod<String>('takeLaunch') ?? '';

  /// Whether the phone is locked now.
  Future<bool> isLocked() async => await channel.invokeMethod<bool>('isLocked') ?? false;

  /// A dictation started or ended: the screen is kept on while it runs, and its going off is the `screenOff` event.
  Future<void> setCapturing(bool on) => channel.invokeMethod<void>('setCapturing', {'on': on});

  /// The capture is over: the lock-screen permission is taken back, and with [leave] the app steps behind the lock.
  Future<void> endCapture({required bool leave}) => channel.invokeMethod<void>('endCapture', {'leave': leave});

  /// Whether the phone assistant and the side key are there at all: off, unless the build turned them on
  /// (GHOST_ASSISTANT=1) or this phone's developer switch did (lib/core/wip.dart).
  Future<bool> assistantEnabled() async => await channel.invokeMethod<bool>('assistantEnabled') ?? false;

  /// Whether Ghost.md is the phone's digital assistant app.
  Future<bool> isAssistant() async => await channel.invokeMethod<bool>('isAssistant') ?? false;

  /// Opens the settings screen closest to choosing the digital assistant app; whether one opened.
  Future<bool> openAssistantSettings() async => await channel.invokeMethod<bool>('openAssistantSettings') ?? false;

  /// `Build.MANUFACTURER`, such as "samsung".
  Future<String> deviceMaker() async => await channel.invokeMethod<String>('deviceMaker') ?? '';
}
