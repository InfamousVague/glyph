/// The phone's side of the watch, as the app reaches it (docs/WATCH.md): the takes a Wear OS watch sent, waiting in the
/// phone's inbox to be made voice notes, and which watches are connected, for Settings › Recording › Watch.
///
/// Android's half is android/…/ghost_md/watch/WatchBridge.kt, over `ghost_md/watch`:
/// - `waiting` -> JSON `[{id, recordedAt, durationMs, watch, bytes, wav}]`, oldest first;
/// - `done {id}` -> null: the take is a note (or let go), and its files go;
/// - `status` -> JSON `{watches: [{name, nearby}], last: {id, recordedAt, durationMs, watch, receivedAt} | null,
///   waiting}`;
///
/// and `ghost_md/watch/events`, a take's id each time one arrives while the app runs, in front or not.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One take from the watch, waiting on the phone.
@immutable
class WatchTake {
  const WatchTake({required this.id, required this.recordedAt, required this.durationMs, required this.watch, required this.wav});

  /// The watch's own id for it, from which the note's is made (watch_notes.dart `watchNoteId`).
  final String id;

  /// When it started, in ms since the epoch, on the watch's clock.
  final int recordedAt;
  final int durationMs;

  /// The watch's name ("Galaxy Watch9").
  final String watch;

  /// Where its WAV is in the inbox: gone already when the app had moved it to the note before it was stopped.
  final String wav;

  static WatchTake? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final wav = raw['wav'];
    if (id is! String || id.isEmpty || wav is! String) return null;
    int whole(Object? n) => n is num ? n.toInt() : 0;
    return WatchTake(id: id, recordedAt: whole(raw['recordedAt']), durationMs: whole(raw['durationMs']), watch: raw['watch'] is String ? raw['watch'] as String : '', wav: wav);
  }

  @override
  bool operator ==(Object other) => other is WatchTake && other.id == id && other.recordedAt == recordedAt && other.durationMs == durationMs && other.watch == watch && other.wav == wav;

  @override
  int get hashCode => Object.hash(id, recordedAt, durationMs, watch, wav);
}

/// A watch connected now that has Ghost.md on it.
typedef ConnectedWatch = ({String name, bool nearby});

/// What Settings › Recording › Watch says.
@immutable
class WatchStatus {
  const WatchStatus({this.watches = const [], this.lastAt, this.lastWatch, this.lastMs, this.waiting = 0});

  final List<ConnectedWatch> watches;

  /// When the last take came, in ms since the epoch; null before the first.
  final int? lastAt;
  final String? lastWatch;
  final int? lastMs;

  /// How many takes wait to be made notes.
  final int waiting;

  /// Whether there is anything to show: a watch with Ghost.md connected, or one that ever sent a take.
  bool get any => watches.isNotEmpty || lastAt != null;

  static WatchStatus fromJson(Object? raw) {
    if (raw is! Map) return const WatchStatus();
    final watches = <ConnectedWatch>[
      if (raw['watches'] case final List list)
        for (final w in list)
          if (w is Map && w['name'] is String) (name: w['name'] as String, nearby: w['nearby'] == true),
    ];
    final last = raw['last'];
    int? whole(Object? n) => n is num ? n.toInt() : null;
    return WatchStatus(
      watches: watches,
      lastAt: last is Map ? whole(last['receivedAt']) : null,
      lastWatch: last is Map && last['watch'] is String ? last['watch'] as String : null,
      lastMs: last is Map ? whole(last['durationMs']) : null,
      waiting: whole(raw['waiting']) ?? 0,
    );
  }
}

/// The phone's inbox, as [WatchNotes] asks it (lib/watch/watch_notes.dart). A test's own in tests.
abstract interface class WatchHost {
  /// The takes waiting, oldest first.
  Future<List<WatchTake>> waiting();

  /// Take [id] is a note now, or let go: its files go.
  Future<void> done(String id);

  /// A take's id each time one arrives while the app runs.
  Stream<String> get arrivals;

  /// What Settings shows.
  Future<WatchStatus> status();
}

/// [WatchHost] over the phone's own bridge.
class ChannelWatchHost implements WatchHost {
  ChannelWatchHost({MethodChannel channel = const MethodChannel('ghost_md/watch'), EventChannel events = const EventChannel('ghost_md/watch/events')})
      : _channel = channel,
        _events = events;

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Future<List<WatchTake>> waiting() async {
    final said = await _channel.invokeMethod<String>('waiting');
    if (said == null) return const [];
    final list = jsonDecode(said);
    return [if (list is List) for (final raw in list) ?WatchTake.fromJson(raw)];
  }

  @override
  Future<void> done(String id) => _channel.invokeMethod<void>('done', {'id': id});

  @override
  late final Stream<String> arrivals = _events.receiveBroadcastStream().where((id) => id is String).cast<String>();

  @override
  Future<WatchStatus> status() async {
    final said = await _channel.invokeMethod<String>('status');
    return said == null ? const WatchStatus() : WatchStatus.fromJson(jsonDecode(said));
  }
}

/// The watch as Settings reads it: null where this build has no watch to hear from (anything but an Android phone,
/// a test); set by voice (lib/root/voice_wiring.dart).
WatchLink? watchLink;

/// What Settings › Recording › Watch draws, read again each time the page is put up ([refresh]).
class WatchLink extends ValueNotifier<WatchStatus> {
  WatchLink(this.host) : super(const WatchStatus());

  final WatchHost host;

  /// Asks the phone again; quiet where it will not say (no Play services, say).
  Future<void> refresh() async {
    try {
      value = await host.status();
    } catch (failure) {
      debugPrint('[watch] the watch could not be asked about: $failure');
    }
  }
}
