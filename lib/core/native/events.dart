/// What the Rust core says without being asked (native/src/events.rs): what `listen` from `@tauri-apps/api/event`
/// was to the web app. The names are the web's own (`capture://partial`, `ai://progress` …), and the payload is
/// the JSON the page's listener was handed, decoded.
///
/// ```dart
/// final sub = core.events.where((e) => e.event == 'capture://partial').listen((e) => show(e.map['text']));
/// ```
///
/// A long job (native/src/work.rs) is a command that answers `{id}` at once and ends with one [jobEnd] event;
/// `GhostCore.startJob` wraps the pair as a [CoreJob].
library;

import 'dart:async';

import 'core.dart';

/// The event every long job ends with: `{id, kind, ok: value}` or `{id, kind, err: sentence}`.
const jobEnd = 'job://end';

/// One event from the core.
class CoreEvent {
  const CoreEvent(this.event, this.payload);

  /// Its name, as the web app's `listen` took it.
  final String event;

  /// Its payload, decoded from JSON: a map for nearly every event, `null` for one that carries nothing.
  final Object? payload;

  /// The payload as a map, or an empty one when it is not.
  Map<String, Object?> get map => payload is Map ? (payload as Map).cast<String, Object?>() : const {};

  /// The job this event is about, when its payload says (`id`, as the web's payloads have it).
  String? get jobId => map['id'] is String ? map['id'] as String : null;

  @override
  String toString() => 'CoreEvent($event, $payload)';
}

/// A long job under way: its id, its own events (those whose payload carries its `id`, the ending one left out),
/// and how it ends.
class CoreJob {
  CoreJob(this.id, this.events, this.done, this._cancel);

  final String id;

  /// This job's events, from its first: none is lost between the command's answer and the first listener.
  /// Single-subscription, and closed when the job ends.
  final Stream<CoreEvent> events;

  /// Completes with the job's `ok` value, or throws [CoreError] with its `err` sentence.
  final Future<Object?> done;

  final Future<bool> Function() _cancel;

  /// Asks the job to stop (`job_cancel`); `false` when it had already ended. [done] still completes, usually
  /// with the job's own sentence about having been stopped.
  Future<bool> cancel() => _cancel();
}
