// Events from Rust and the long job (native/src/events.rs, work.rs), through the real C functions on the Mac:
// a `NativeCallable.listener` on the worker isolate, called from Rust's own threads, each event decoded and its
// buffer given back. Needs tool/build-native.sh host (the `test-hooks` feature has `test_emit` and
// `test_long_job`).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';

  late Directory root;
  late GhostCore core;
  final path = File(_library).absolute.path;

  setUpAll(() async {
    if (!built) return;
    root = Directory(Directory.systemTemp.createTempSync('ghost-core-events-').resolveSymbolicLinksSync());
    core = await GhostCore.open(libraryPath: path);
    await core.init(dataDir: '${root.path}/data', cacheDir: '${root.path}/cache');
  });

  tearDownAll(() async {
    if (!built) return;
    await core.close();
    root.deleteSync(recursive: true);
  });

  test('an event emitted on another Rust thread arrives decoded', () async {
    final heard = core.events.where((e) => e.event == 'test://hello').first.timeout(const Duration(seconds: 5));
    expect(await core.invoke('test_emit', {'event': 'test://hello', 'payload': {'text': 'a "quoted" line\n', 'n': [1, 2.5, null], 'né': true}}), isNull);
    final event = await heard;
    expect(event.payload, {'text': 'a "quoted" line\n', 'n': [1, 2.5, null], 'né': true});
    expect(event.map['text'], 'a "quoted" line\n');
    expect(event.jobId, isNull);

    // No payload at all is null, and a great many arrive each once, none of their buffers kept.
    final many = <int>[];
    final all = Completer<void>();
    final sub = core.events.where((e) => e.event == 'test://many').listen((e) {
      many.add(e.map['n'] as int);
      if (many.length == 500) all.complete();
    });
    for (var n = 0; n < 500; n++) {
      unawaited(core.invoke('test_emit', {'event': 'test://many', 'payload': {'n': n, 'pad': 'x' * 2000}}));
    }
    await all.future.timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect(many.toSet().length, 500);
    final bare = core.events.where((e) => e.event == 'test://bare').first.timeout(const Duration(seconds: 5));
    await core.invoke('test_emit', {'event': 'test://bare'});
    expect((await bare).payload, isNull);
  }, skip: skip);

  test('the account\'s lane, opened after the core, does not take the core\'s events', () async {
    // The app's order (lib/main.dart): the core first, then the crypto's lane on the same library. The core has
    // one listener; when the lane took it, a build with an account never heard a job end.
    final crypto = await CoreCrypto.withLane(core, libraryPath: path);
    addTearDown(crypto.close);
    final heard = core.events.where((e) => e.event == 'test://after-lane').first.timeout(const Duration(seconds: 5));
    await core.invoke('test_emit', {'event': 'test://after-lane', 'payload': {'n': 1}});
    expect((await heard).map['n'], 1);
    // And a job started on the core still ends there.
    final job = await core.startJob('test_long_job', {'ms': 200, 'ticks': 2});
    await job.done.timeout(const Duration(seconds: 10));
  }, skip: skip);

  test('a long job answers its id at once, reports in order and ends once', () async {
    final asked = Stopwatch()..start();
    final job = await core.startJob('test_long_job', {'ms': 1200, 'ticks': 8});
    expect(asked.elapsedMilliseconds, lessThan(1200), reason: 'the id comes back before the work');
    expect(job.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    final running = await core.invoke('jobs_running') as List;
    expect(running, contains(equals({'id': job.id, 'kind': 'test'})));

    final ticks = await job.events.toList();
    expect(ticks.map((e) => e.event).toSet(), {'test://tick'});
    expect(ticks.map((e) => e.map['n']), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(await job.done, {'ticks': 8});
    expect(asked.elapsedMilliseconds, greaterThanOrEqualTo(1200));
    expect(await core.invoke('jobs_running'), isNot(contains(equals({'id': job.id, 'kind': 'test'}))));
    expect(await job.cancel(), isFalse, reason: 'nothing to stop once it has ended');
  }, skip: skip);

  test('notes are read as fast as ever while a long job runs', () async {
    final ids = <String>[];
    for (var n = 0; n < 40; n++) {
      final id = await core.newId();
      ids.add(id);
      await core.invoke('create_note', {'id': id, 'body': '# Note $n\n\nSome words for note $n.\n', 'source': 'editor'});
    }
    Future<List<int>> reads(int rounds) async {
      final took = <int>[];
      for (var n = 0; n < rounds; n++) {
        final one = Stopwatch()..start();
        final note = await core.invoke('get_note', {'id': ids[n % ids.length]}) as Map;
        expect(note['id'], ids[n % ids.length]);
        if (n % 10 == 0) expect((await core.invoke('list_notes') as List).length, greaterThanOrEqualTo(40));
        took.add(one.elapsedMicroseconds);
      }
      return took..sort();
    }

    final quiet = await reads(100);
    // The job reads the library itself at every tick, and holds it for no longer than that read.
    final job = await core.startJob('test_long_job', {'ms': 3000, 'ticks': 60});
    final ticks = <int>[];
    final sub = job.events.listen((e) => ticks.add(e.map['notes'] as int));
    final busy = await reads(100);
    final stillRunning = (await core.invoke('jobs_running') as List).any((j) => (j as Map)['id'] == job.id);
    expect(stillRunning, isTrue, reason: 'a hundred reads were answered while the job was still at work');
    expect(await job.done, {'ticks': 60});
    await sub.cancel();
    expect(ticks.length, 60);
    expect(ticks.every((notes) => notes >= 40), isTrue);

    final quietMedian = quiet[quiet.length ~/ 2], busyMedian = busy[busy.length ~/ 2];
    // ignore: avoid_print
    print('get_note: median ${quietMedian}us quiet, ${busyMedian}us during a job; slowest ${quiet.last}us and ${busy.last}us');
    expect(busy.last, lessThan(250000), reason: 'no read waited on the job');
    expect(busyMedian, lessThan(quietMedian * 5 + 5000));
  }, skip: skip);

  test('a job is stopped by its id, and what it says of that is its end', () async {
    final job = await core.startJob('test_long_job', {'ms': 20000, 'ticks': 400});
    final first = await job.events.first.timeout(const Duration(seconds: 5));
    expect(first.map['n'], 1);
    expect(await job.cancel(), isTrue);
    await expectLater(job.done, throwsA(isA<CoreError>().having((e) => e.message, 'message', startsWith('cancelled after '))));
  }, skip: skip);

  test('a command that refuses starts no job, and one that is not a job says so', () async {
    await expectLater(core.startJob('test_long_job', {'ms': 'soon'}), throwsA(isA<CoreError>().having((e) => e.message, 'message', startsWith('invalid args for command `test_long_job`'))));
    await expectLater(core.startJob('new_id'), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'new_id did not answer with a job\'s id.')));
    expect(await core.invoke('job_cancel', {'id': 'nobody'}), isFalse);
  }, skip: skip);

  test('the newest worker hears, and an older one closing does not silence it', () async {
    final second = await GhostCore.open(libraryPath: path);
    final heard = second.events.where((e) => e.event == 'test://second').first.timeout(const Duration(seconds: 5));
    await second.invoke('test_emit', {'event': 'test://second', 'payload': 1});
    expect((await heard).payload, 1);

    final older = await GhostCore.open(libraryPath: path);
    final newer = await GhostCore.open(libraryPath: path);
    final olderDone = expectLater(older.events, emitsDone);
    await older.close();
    await olderDone;
    final still = newer.events.where((e) => e.event == 'test://still').first.timeout(const Duration(seconds: 5));
    await newer.invoke('test_emit', {'event': 'test://still', 'payload': 2});
    expect((await still).payload, 2);
    await newer.close();
    await second.close();
  }, skip: skip);
}
