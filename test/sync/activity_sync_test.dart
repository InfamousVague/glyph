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
    // The bar filled as it ends, then the end.
    expect(heard.map((e) => e.kind), [JobEventKind.started, JobEventKind.changed, JobEventKind.ended, JobEventKind.allDone]);
    expect(heard[1].job!.fraction, 1);
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
      // Three pulled and two pushed, then the team's five: ten in all. The account's notes done, the bar is under 1, so
      // the team's rows found after them have room to fill (the coordinator, 2026-10-29: "make new work take up the
      // space that's left"): it holds as they are found, rises with each one, and is full only as the pass ends.
      double at(String line) => seen.lastWhere((each) => each.line == line).fraction!;
      final notesDone = at('Syncing, 5 of 5');
      expect(notesDone, lessThan(1), reason: 'the account’s notes done, room kept');
      expect(at('Syncing, 3 of 3'), lessThan(notesDone));
      expect(seen.firstWhere((each) => each.line == 'Syncing, 5 of 9').fraction, notesDone, reason: 'found, not yet done: it holds');
      final team = [for (final line in ['Syncing, 6 of 9', 'Syncing, 7 of 9', 'Syncing, 10 of 10']) at(line)];
      expect(team.first, greaterThan(notesDone));
      expect(team[1], greaterThan(team.first));
      expect(team.last, greaterThan(team[1]));
      for (final each in seen.take(seen.length - 1)) {
        expect(each.fraction, lessThan(1), reason: 'under 1 until the pass ends: ${each.line}');
      }
      expect(seen.last.line, 'Syncing, 10 of 10');
      expect(seen.last.fraction, 1, reason: 'full as it ends');
      expect(record[syncJobId]?.state.live ?? false, isFalse);
    });

    test('more found lays what is left over what is left of the bar, never back, full only at the end', () {
      final told = <(double, String?)>[];
      final count = SyncCount(onChange: (count) => told.add((count.fraction, count.steps)));
      expect((count.fraction, count.steps), (0.0, null));
      count.found(2);
      count.did();
      expect(count.fraction, closeTo(1 / 3, 1e-9), reason: 'one of two, and one more kept room for');
      count.did();
      expect(count.fraction, closeTo(2 / 3, 1e-9), reason: 'all it knows of done: room kept for what it may find');
      count.found(2);
      expect(count.fraction, closeTo(2 / 3, 1e-9), reason: 'found: it holds');
      expect(count.steps, '2 of 4');
      count.did();
      expect(count.fraction, closeTo(2 / 3 + (1 / 3) / 3, 1e-9), reason: 'the new work over the room that was left');
      count.did();
      expect(count.fraction, closeTo(2 / 3 + (1 / 3) * 2 / 3, 1e-9));
      expect(count.fraction, lessThan(1), reason: 'full only as it ends');
      count.finish();
      expect((count.fraction, count.steps), (1.0, '4 of 4'));
      expect([for (final (fraction, _) in told) fraction], orderedEquals([for (final (fraction, _) in told) fraction]..sort()), reason: 'never back');
      expect(told.map((each) => each.$2), ['0 of 2', '1 of 2', '2 of 2', '2 of 4', '3 of 4', '4 of 4', '4 of 4']);
      final many = SyncCount(onChange: (count) => told.add((count.fraction, count.steps)));
      told.clear();
      many.found(1000);
      for (var i = 0; i < 1000; i++) {
        many.did();
      }
      expect(told.length, lessThanOrEqualTo(101), reason: 'once a whole percent at most, not a thousand');
      expect(told.last.$1, closeTo(1000 / 1001, 1e-9));
      expect(told.last.$2, '1000 of 1000');
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
