// The sync on the app's record of running work (lib/sync/engine.dart `syncJobId`; docs/ACTIVITY.md, Matt 2026-10-29:
// "Sync is frequent: show it as one rolling Syncing job, not one per pass, and only when a pass actually moves something
// or takes over ~1 s"): through the real engine, with its passes stood in for as engine_test.dart stands them in.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart' show ApiError;
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/notes.dart' show Outcome, forgetPictureAsks;

import 'engine_test.dart' show Rig;

void main() {
  late Activity record;
  late List<JobEvent> heard;
  late StreamSubscription<JobEvent> hearing;

  setUp(() {
    forgetPictureAsks();
    record = Activity(store: () => MemoryStored());
    useActivity(record);
    heard = [];
    hearing = record.events.listen(heard.add);
  });
  tearDown(() async {
    await hearing.cancel();
    useActivity(Activity());
  });

  test('a quick pass that moves nothing is never shown: no event, no bloom, nothing counted', () async {
    final rig = await Rig.make();
    await rig.engine.syncNow();
    expect(heard, isEmpty);
    expect(record.value, isEmpty);
    expect(record.blooms, 0);
    expect(record.log.today.isEmpty, isTrue);
  });

  test('a pass that brings notes is shown, blooms once, and counts them', () async {
    final rig = await Rig.make();
    rig.notesPass = (_) async => Outcome(changed: 3);
    await rig.engine.syncNow();
    expect(heard.map((e) => e.kind), [JobEventKind.started, JobEventKind.ended, JobEventKind.allDone]);
    expect(heard.first.job!.kind, JobKind.sync);
    expect(heard.first.job!.title, 'Syncing');
    expect(record.blooms, 1);
    expect(record.log.today.words, '3 notes synced');
    expect(record.log.today.rows, isEmpty, reason: 'a sync is a count, never a row');
  });

  test('the passes queued behind one are the same job: one start, one end', () async {
    final rig = await Rig.make();
    final held = rig.heldPass();
    final first = rig.engine.syncNow();
    await pumpEventQueue();
    expect(record[syncJobId], isNotNull, reason: 'on the record, kept out of sight');
    expect(record.value, isEmpty);
    unawaited(rig.engine.syncNow());
    rig.notesPass = (_) async => Outcome(changed: 2);
    held.complete(Outcome(changed: 1));
    await first;
    await rig.engine.syncSettled();
    expect(rig.passes, hasLength(2));
    expect(heard.where((e) => e.kind == JobEventKind.started), hasLength(1));
    expect(heard.where((e) => e.kind == JobEventKind.ended), hasLength(1));
    expect(record.log.today.words, '3 notes synced');
  });

  test('a pass that takes over a second is shown though it has moved nothing yet', () async {
    final rig = await Rig.make();
    final held = rig.heldPass();
    final pass = rig.engine.syncNow();
    await pumpEventQueue();
    expect(record.value, isEmpty);
    await Future<void>.delayed(syncShownAfter + const Duration(milliseconds: 150));
    expect(record.value.single.id, syncJobId);
    expect(record.value.single.liveLine, 'Syncing');
    held.complete(Outcome());
    await pass;
    expect(record.value, isEmpty);
    expect(record.blooms, 1);
  });

  test('a blip, or the service a moment away, goes quietly: the next pass is its try again', () async {
    final rig = await Rig.make();
    rig.notesPass = (_) async {
      await Future<void>.delayed(Duration.zero);
      throw const SocketException('lookup failed');
    };
    await rig.engine.syncNow();
    rig.notesPass = (_) async => throw const ApiError(503, 'Service unavailable');
    await rig.engine.syncNow();
    expect(record.needsYou, isFalse);
    expect(record.value, isEmpty);
  });

  test('anything else is red in the tray with its step and Retry, which syncs again', () async {
    final rig = await Rig.make();
    rig.notesPass = (_) async => throw const ApiError(400, 'The note was refused.');
    await rig.engine.syncNow();
    final failed = record.value.single;
    expect(failed.state, JobState.failed);
    expect(failed.cause, startsWith('Notes: '));
    expect(failed.fix!.kind, JobFixKind.retry);
    rig.notesPass = (_) async => Outcome(changed: 1);
    failed.fix!.onPress();
    await rig.engine.syncSettled();
    await pumpEventQueue();
    expect(record.value, isEmpty, reason: 'begun again, and done');
    expect(rig.passes, hasLength(2));
  });

  test('a look at the notifications alone is never a job', () async {
    final rig = await Rig.make();
    await rig.engine.syncNotificationsNow();
    expect(record[syncJobId], isNull);
    expect(heard, isEmpty);
  });
}
