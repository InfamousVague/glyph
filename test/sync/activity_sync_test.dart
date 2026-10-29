// The sync on the app's record of running work (lib/sync/engine.dart `syncJobId`; docs/ACTIVITY.md, Matt 2026-10-29:
// "Sync is frequent: show it as one rolling Syncing job, not one per pass, and only when a pass actually moves something
// or takes over ~1 s"): through the real engine, with its passes stood in for as engine_test.dart stands them in. Its
// bar fills and never sweeps (Matt, 2026-10-29: "Also don't spin the progress bar on the sync just make it fill as it's
// being synced"): the account's pulls and pushes and the teams' rows counted as they go, through two whole engines.
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart' show ApiError;
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/notes.dart' show Outcome, SyncCount, forgetPictureAsks;

import '../support/fake_service.dart';
import '../support/sync_device.dart' show DeviceNotes;
import 'engine_test.dart' show Rig, live;
import 'support.dart' show note, testAccount;

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

  group('the bar fills, never sweeps', () {
    test('at 0 before the pass knows what it will do, with no count in its words', () async {
      final rig = await Rig.make();
      final held = rig.heldPass();
      final pass = rig.engine.syncNow();
      await pumpEventQueue();
      final job = record[syncJobId]!;
      expect(job.fraction, 0, reason: 'an empty bar, not a sweep');
      expect(job.steps, isNull);
      expect(job.liveLine, 'Syncing');
      held.complete(Outcome());
      await pass;
    });

    test('rises through a pass with pulls, pushes and team rows, never back, and says how many', () async {
      final service = await FakeService.start(seed: testAccount);
      final phoneNotes = DeviceNotes(), foldNotes = DeviceNotes();
      final phone = await Rig.make(service: service, standIns: false, as: live(service), notes: phoneNotes);
      for (final id in ['a', 'b', 'c']) {
        phoneNotes.held[id] = note(id, '# Note $id\n\nwords', createdAt: 1, updatedAt: 1);
      }
      await phone.engine.syncNow();
      // The fold: three to pull, two of its own to push, and an organization whose channel takes four rows and finds
      // a fifth as it goes.
      final fold = await Rig.make(
        service: service,
        standIns: false,
        as: live(service),
        notes: foldNotes,
        teamNotes: (pass) async {
          final count = pass.progress!;
          count.found(4);
          count.did();
          count.did();
          count.found(1);
          count.did(3);
          return const TeamOutcome();
        },
      );
      await fold.orgs.createOrg('Ghost');
      for (final id in ['d', 'e']) {
        foldNotes.held[id] = note(id, '# Fold $id\n\nwords', createdAt: 2, updatedAt: 2);
      }
      final seen = <({double? fraction, String line})>[];
      void look() {
        final job = record[syncJobId];
        if (job != null && job.state.live) seen.add((fraction: job.fraction, line: job.liveLine));
      }

      record.addListener(look);
      addTearDown(() => record.removeListener(look));
      await fold.engine.syncNow();
      expect(seen, isNotEmpty);
      expect(seen.every((each) => each.fraction != null), isTrue, reason: 'never a sweep');
      expect(seen.first.fraction, 0);
      for (var at = 1; at < seen.length; at++) {
        expect(seen[at].fraction!, greaterThanOrEqualTo(seen[at - 1].fraction!), reason: 'never back: ${seen.map((e) => e.fraction).toList()}');
      }
      expect(seen.where((each) => each.fraction! > 0 && each.fraction! < 1), isNotEmpty, reason: 'filling as it goes');
      final lines = seen.map((each) => each.line).toSet();
      // Three pulled and two pushed, then the team's five: ten in all.
      expect(lines, contains('Syncing, 3 of 3'));
      expect(lines, contains('Syncing, 5 of 5'));
      expect(lines, contains('Syncing, 5 of 9'), reason: 'the team’s rows found: the bar holds where it was');
      expect(seen.last.line, 'Syncing, 10 of 10');
      expect(seen.last.fraction, 1);
    });

    test('the count holds still when more is found, and tells as more is found, once a percent at most as it goes, and the last', () {
      final told = <(double, String?)>[];
      final count = SyncCount(onChange: (count) => told.add((count.fraction, count.steps)));
      expect((count.fraction, count.steps), (0.0, null));
      count.found(2);
      count.did();
      expect(count.fraction, 0.5);
      count.found(2);
      expect((count.fraction, count.steps), (0.5, '1 of 4'), reason: 'more found: never back');
      count.did(3);
      expect((count.fraction, count.steps), (1.0, '4 of 4'));
      expect(told, [(0.0, '0 of 2'), (0.5, '1 of 2'), (0.5, '1 of 4'), (1.0, '4 of 4')]);
      final many = SyncCount(onChange: (count) => told.add((count.fraction, count.steps)));
      told.clear();
      many.found(1000);
      for (var i = 0; i < 1000; i++) {
        many.did();
      }
      expect(told.length, 101, reason: 'the first, and each whole percent to the last');
      expect(told.last, (1.0, '1000 of 1000'));
    });

    test('no sync job sweeps: one begun with nothing to say of how far is at 0', () {
      for (final id in ['calendar:work', 'fetch:notion', 'sync']) {
        final job = record.begin(id, kind: JobKind.sync, title: 'Reading');
        expect(record[id]!.fraction, 0, reason: id);
        job.done();
      }
      // Any other kind that cannot say how far still turns.
      record.begin('voice', kind: JobKind.audio, title: 'Reading aloud');
      expect(record['voice']!.fraction, isNull);
    });
  });
}
