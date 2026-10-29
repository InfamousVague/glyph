// The app's record of running work and its log (lib/core/background_jobs.dart, lib/core/activity_log.dart;
// docs/ACTIVITY.md).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart';

void main() {
  late DateTime now;
  late MemoryStored store;
  late Activity record;
  late List<JobEvent> heard;
  late StreamSubscription<JobEvent> listening;

  setUp(() {
    now = DateTime(2026, 10, 29, 9);
    store = MemoryStored();
    record = Activity(clock: () => now, store: () => store);
    heard = [];
    listening = record.events.listen(heard.add);
  });

  tearDown(() => listening.cancel());

  test('a job goes through its states, and the listenable and the stream say each', () {
    var told = 0;
    record.addListener(() => told += 1);
    expect(record.idle, isTrue);
    final job = record.begin('summary:n1', kind: JobKind.ai, title: 'Summary of Standup', line: 'Writing the summary');
    expect(record.value.single.state, JobState.running);
    expect(record.value.single.fraction, isNull, reason: 'indeterminate until it says how far');
    job.progress(done: 2, total: 3, unit: 'parts');
    expect(record.value.single.fraction, closeTo(2 / 3, 1e-9));
    expect(record.value.single.liveLine, 'Writing the summary, 2 of 3 parts');
    job.waiting(WaitingOn.wifi);
    expect(record.value.single.state, JobState.waiting);
    expect(record.value.single.liveLine, 'Waiting for Wi-Fi');
    expect(record.value.single.look, JobLook.waiting);
    job.progress(done: 3, total: 3);
    expect(record.value.single.state, JobState.running, reason: 'told how far, it runs again');
    expect(record.value.single.look, JobLook.ai);
    job.done(result: const JobResult('Summary ready', action: 'Open'), tally: const JobTally('summary', 'summaries'));
    expect(record.value, isEmpty);
    expect(record.idle, isTrue);
    expect(told, greaterThan(4));
    expect(heard.map((e) => e.kind), [JobEventKind.started, JobEventKind.changed, JobEventKind.changed, JobEventKind.changed, JobEventKind.ended, JobEventKind.allDone]);
    expect(heard[4].job!.result!.words, 'Summary ready');
    expect(record.blooms, 1);
    // A handle whose job ended does nothing.
    job.progress(done: 1, total: 2);
    expect(record.value, isEmpty);
  });

  test('a second start of the same work is the same job', () {
    final a = record.begin('sync', kind: JobKind.sync, title: 'Syncing');
    final b = record.begin('sync', kind: JobKind.sync, title: 'Syncing notes');
    expect(record.value, hasLength(1));
    expect(record.value.single.title, 'Syncing notes');
    expect(a.id, b.id);
  });

  test('a failed job stays red with its cause and fix until dismissed or begun again, and needs you', () {
    var fixed = 0;
    final job = record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images');
    job.failed('Lovart is out of credits', fix: JobFix(JobFixKind.topUp, () => fixed += 1));
    expect(record.value.single.state, JobState.failed);
    expect(record.value.single.liveLine, 'Lovart is out of credits');
    expect(record.value.single.fix!.label, 'Top up');
    expect(record.needsYou, isTrue);
    expect(record.idle, isTrue, reason: 'nothing runs; the dot stays');
    expect(record.blooms, 0, reason: 'a failure is no bloom');
    record.value.single.fix!.onPress();
    expect(fixed, 1);
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images');
    expect(record.value.single.state, JobState.running);
    expect(record.needsYou, isFalse);
    record.handle('lovart-banners')!.failed('Lovart could not be reached');
    record.dismiss('lovart-banners');
    expect(record.value, isEmpty);
  });

  test('waiting on a sign-in or on credits needs you', () {
    record.begin('slack', kind: JobKind.ai, title: 'Posting to Slack').waiting(WaitingOn.signIn);
    expect(record.value.single.look, JobLook.needsYou);
    expect(record.needsYou, isTrue);
  });

  test('the other devices\' jobs are shown, labelled, replaced by their source, never logged here', () {
    record.elsewhere('handoff', [Job(id: 'summary:n2', kind: JobKind.ai, title: 'Summary of Retro', device: 'mac1', deviceName: 'Mac', startedAt: now)]);
    expect(record.value.single.here, isFalse);
    expect(record.value.single.deviceWords, 'on your Mac');
    expect(record.idle, isFalse);
    record.elsewhere('handoff', const []);
    expect(record.value, isEmpty);
    expect(record.blooms, 1, reason: 'the last live job ended');
    expect(record.log.today.isEmpty, isTrue);
    expect(heard.map((e) => e.kind), [JobEventKind.started, JobEventKind.ended, JobEventKind.allDone]);
  });

  test('one bloom when all finish, not one per job', () {
    final a = record.begin('a', kind: JobKind.images, title: 'A');
    final b = record.begin('b', kind: JobKind.audio, title: 'B');
    a.done();
    expect(record.blooms, 0);
    b.done();
    expect(record.blooms, 1);
  });

  test('a chime only for a job the person started that ran over 30 s, never sync, never quiet', () {
    final chimed = <String>[];
    record.onChime = (job) => chimed.add(job.id);
    record.begin('short', kind: JobKind.images, title: 'Short', personStarted: true);
    now = now.add(const Duration(seconds: 10));
    record.handle('short')!.done();
    record.begin('auto', kind: JobKind.images, title: 'On its own');
    now = now.add(const Duration(minutes: 2));
    record.handle('auto')!.done();
    record.begin('sync', kind: JobKind.sync, title: 'Syncing', personStarted: true);
    now = now.add(const Duration(minutes: 2));
    record.handle('sync')!.done();
    record.begin('quiet', kind: JobKind.images, title: 'Quiet', personStarted: true);
    now = now.add(const Duration(minutes: 2));
    record.handle('quiet')!.done(quiet: true);
    record.begin('long', kind: JobKind.images, title: 'Long', personStarted: true);
    now = now.add(const Duration(seconds: 31));
    record.handle('long')!.done();
    record.begin('failed', kind: JobKind.ai, title: 'Failed', personStarted: true);
    now = now.add(const Duration(seconds: 31));
    record.handle('failed')!.failed('No');
    expect(chimed, ['long', 'failed']);
  });

  test('the estimate asks over 20 credits or 2 minutes, and says itself', () {
    const run = JobEstimate(credits: 72, provider: 'Lovart', duration: Duration(minutes: 4), count: 12, one: 'banner', many: 'banners');
    expect(run.asks, isTrue);
    expect(run.words, '12 banners · ~72 Lovart credits · ~4 min');
    expect(const JobEstimate(credits: 18, provider: 'Lovart', count: 3, one: 'banner').asks, isFalse);
    expect(const JobEstimate(credits: 21).asks, isTrue);
    expect(const JobEstimate(duration: Duration(minutes: 2)).asks, isFalse);
    expect(const JobEstimate(duration: Duration(minutes: 2, seconds: 1)).asks, isTrue);
  });

  test('spend counts the credits live', () {
    final job = record.begin('run', kind: JobKind.images, title: 'Run', estimate: const JobEstimate(credits: 12, provider: 'Lovart'));
    job.spend(6);
    job.spend(6);
    expect(record.value.single.spent, 12);
  });

  group('retrying', () {
    test('a network blip is tried again on the backoff, the job waiting for the network meanwhile, and then succeeds', () async {
      final job = record.begin('post', kind: JobKind.ai, title: 'Posting');
      final waits = <Duration>[];
      final lines = <String>[];
      var tries = 0;
      final answer = await retrying(job, () async {
        tries += 1;
        if (tries < 3) throw TimeoutException('slow');
        return 'ok';
      }, wait: (d) async {
        waits.add(d);
        lines.add(record.value.single.liveLine);
        expect(record.value.single.state, JobState.waiting);
      });
      expect(answer, 'ok');
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 8)]);
      expect(lines, ['Trying again in 2 s', 'Trying again in 8 s']);
      expect(record.value.single.state, JobState.running);
      expect(record.value.single.attempt, 2);
    });

    test('a blip past the last try, or anything else at once, is thrown on', () async {
      final job = record.begin('post', kind: JobKind.ai, title: 'Posting');
      var tries = 0;
      await expectLater(retrying(job, () async {
        tries += 1;
        throw TimeoutException('slow');
      }, wait: (_) async {}), throwsA(isA<TimeoutException>()));
      expect(tries, 4);
      tries = 0;
      await expectLater(retrying(job, () async {
        tries += 1;
        throw StateError('no key');
      }, wait: (_) async {}), throwsA(isA<StateError>()));
      expect(tries, 1);
    });
  });

  group('the log', () {
    test('today counts what ended, in words', () {
      for (var i = 0; i < 3; i += 1) {
        record.begin('s$i', kind: JobKind.ai, title: 'Summary $i').done(tally: const JobTally('summary', 'summaries'));
      }
      record.begin('run', kind: JobKind.images, title: 'Header images').done(tally: const JobTally('banner', 'banners', 12));
      record.begin('sync', kind: JobKind.sync, title: 'Syncing').done(tally: const JobTally('note synced', 'notes synced', 40));
      record.begin('x', kind: JobKind.ai, title: 'Post').failed('Slack said no');
      expect(record.log.today.words, '3 summaries, 12 banners, 40 notes synced, 1 failed');
      expect(record.log.today.rows.map((r) => r.title), ['Post', 'Header images', 'Summary 2', 'Summary 1', 'Summary 0'], reason: 'sync is a count, not a row');
      expect(record.log.today.rows.first.cause, 'Slack said no');
    });

    test('is kept in the stored settings and read back', () {
      record.begin('run', kind: JobKind.images, title: 'Header images').done(tally: const JobTally('banner', 'banners', 2));
      expect(jsonDecode(store.getItem(ActivityLog.key)!), isA<List>());
      final again = Activity(clock: () => now, store: () => store);
      expect(again.log.today.words, '2 banners');
    });

    test('rolls over the days: yesterday goes to the past, a day older than seven is let go', () {
      record.begin('a', kind: JobKind.ai, title: 'A').done(tally: const JobTally('summary', 'summaries'));
      now = now.add(const Duration(days: 1));
      expect(record.log.today.isEmpty, isTrue);
      expect(record.log.past.single.words, '1 summary');
      record.begin('b', kind: JobKind.images, title: 'B').done(tally: const JobTally('banner', 'banners', 5));
      expect(record.log.today.words, '5 banners');
      for (var day = 0; day < 8; day += 1) {
        now = now.add(const Duration(days: 1));
        record.begin('c$day', kind: JobKind.audio, title: 'C').done(tally: const JobTally('voice-over', 'voice-overs'));
      }
      expect(record.log.kept, hasLength(ActivityLog.days));
      expect(record.log.past, hasLength(7));
      expect(record.log.kept.any((d) => d.words.contains('summary') || d.words.contains('banner')), isFalse);
      expect((jsonDecode(store.getItem(ActivityLog.key)!) as List), hasLength(ActivityLog.days));
    });

    test('is capped: rows and counts a day', () {
      for (var i = 0; i < 40; i += 1) {
        record.begin('j$i', kind: JobKind.ai, title: 'J$i').done(tally: JobTally('thing $i', 'things $i'));
      }
      expect(record.log.today.rows, hasLength(ActivityLog.rowsADay));
      expect(record.log.today.counts, hasLength(ActivityLog.talliesADay));
      expect(store.getItem(ActivityLog.key)!.length, lessThan(4000));
    });

    test('a store that refuses is a log of this run', () {
      final refusing = Activity(clock: () => now, store: () => _Refusing());
      refusing.begin('a', kind: JobKind.ai, title: 'A').done(tally: const JobTally('summary', 'summaries'));
      expect(refusing.log.today.words, '1 summary');
    });
  });
}

class _Refusing extends Stored {
  @override
  String? getItem(String key) => throw StateError('no');

  @override
  void setItem(String key, String text) => throw StateError('no');

  @override
  void removeItem(String key) => throw StateError('no');

  @override
  Iterable<String> get allKeys => throw StateError('no');
}
