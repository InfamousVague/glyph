// Meetings on the app's record of running work (docs/ACTIVITY.md): the Mac's write-ups (lib/meet/tape.dart
// `CoreWriteUps`), the core's job stood in for; and the meeting bot's meetings (lib/meet/meet_in.dart `meetBotJobs`).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/tape.dart';

void main() {
  late Activity record;
  setUp(() => useActivity(record = Activity(store: () => MemoryStored())));
  tearDown(() => useActivity(Activity()));

  test('a write-up is a job while the core runs it, ending as Written up; a hold goes quietly', () async {
    final answers = <String, Completer<Object?>>{};
    final done = <String>[];
    final ups = CoreWriteUps(
      startJob: (command, args) async => (answers[args['id']! as String] = Completer<Object?>()).future,
      onDone: done.add,
      retry: const Duration(hours: 1),
    );
    addTearDown(ups.dispose);
    ups.run('m1');
    await pumpEventQueue();
    final job = record['write-up:m1']!;
    expect((job.kind, job.liveLine), (JobKind.audio, 'Transcribing'));
    final ended = <Job>[];
    final hearing = record.events.where((e) => e.kind == JobEventKind.ended).listen((e) => ended.add(e.job!));
    answers['m1']!.complete({'done': true});
    await pumpEventQueue();
    expect(done, ['m1']);
    expect(ended.single.result!.words, 'Written up');
    ups.run('m2');
    await pumpEventQueue();
    answers['m2']!.complete({'retry': 'busy'});
    await pumpEventQueue();
    expect(record.value, isEmpty);
    expect(ended, hasLength(2));
    expect(ended.last.result, isNull, reason: 'held, and tried again later: quietly');
    expect(record.log.today.words, '1 meeting written up');
    await hearing.cancel();
  });

  test('the meeting bot\'s meetings joining, in or leaving are its jobs, not this device\'s; booked, over or failed are none', () {
    MeetBooking at(String id, MeetState state, {String? title}) => MeetBooking(id: id, title: title, startsAt: 1000, endsAt: 2000, state: state);
    final jobs = meetBotJobs([
      at('a', MeetState.booked, title: 'Later'),
      at('b', MeetState.joining, title: 'Standup'),
      at('c', MeetState.inCall),
      at('d', MeetState.done, title: 'Retro'),
      at('e', MeetState.failed, title: 'Review'),
    ]);
    expect(jobs.map((job) => (job.id, job.title, job.liveLine)), [('meet:b', 'Ghost in Standup', 'Joining'), ('meet:c', 'Ghost in a meeting', 'In the meeting')]);
    expect(jobs.first.kind, JobKind.meetings);
    expect(jobs.first.here, isFalse, reason: 'dimmed in the ring');
    expect(jobs.first.deviceWords, 'with Ghost’s meeting bot');
    record.elsewhere(meetBotJobsSource, jobs);
    expect(record.value, hasLength(2));
    record.elsewhere(meetBotJobsSource, meetBotJobs([at('b', MeetState.done)]));
    expect(record.value, isEmpty);
    expect(record.log.today.isEmpty, isTrue);
  });
}
