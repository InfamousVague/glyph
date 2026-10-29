import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;

/// The one store of the meeting being recorded (lib/capture/meeting_live.dart): what the service's JSON becomes,
/// what a push from it does to the state and to whoever asked to hear it, and the poll that runs once a second while
/// the app is visible and someone is listening, and only on a host with a service to ask. Case for case with the
/// web's `capture/meetingLive.test.tsx`: where that renders `useMeetingState` in a probe, this subscribes to the
/// store as the hook does.

/// A host: with the service when [state] is set, answering it and [notify]; [asked] counts the reads.
class Host implements MeetingHost {
  Object? state;
  bool service = false;
  bool notify = false;
  int asked = 0;

  @override
  bool visible = true;

  @override
  bool get hasMeetings => service;

  @override
  String? meetingStateJson() {
    asked += 1;
    return jsonEncode(state);
  }

  @override
  bool canNotify() => notify;
}

const recording = MeetingState(recording: true, noteId: 'm1', title: 'Meeting, 26 Sep 14:05', startedAt: 1000, elapsedMs: 5000, silenced: false, writingUp: null, discarded: []);
const Map<String, Object?> recordingJson = {
  'recording': true,
  'noteId': 'm1',
  'title': 'Meeting, 26 Sep 14:05',
  'startedAt': 1000,
  'elapsedMs': 5000,
  'silenced': false,
  'writingUp': null,
  'discarded': <String>[],
};

void main() {
  var theHost = Host();
  var jobsRunning = false;
  var live = MeetingLive(host: theHost, writeUpRunningNow: () => jobsRunning);

  /// A host with the service, answering [state] and [canNotify]; the answer counts the reads.
  Host host(Object? state, [bool canNotify = true]) {
    theHost
      ..service = true
      ..state = state
      ..notify = canNotify
      ..asked = 0;
    return theHost;
  }

  /// The push the service makes (`window.__glyph.meeting`).
  void push(Map<String, Object?> event) => live.heard(jsonEncode(event));

  setUp(() {
    theHost = Host();
    jobsRunning = false;
    live = MeetingLive(host: theHost, writeUpRunningNow: () => jobsRunning);
  });

  group('what the service says', () {
    test('is read as a state, whole, and anything else is nothing', () {
      expect(parseMeetingState(recordingJson), recording);
      // The fields a build may lack are answered with their quiet values; one without `recording` is not a state.
      expect(
        parseMeetingState({'recording': false}),
        const MeetingState(recording: false, noteId: null, title: null, startedAt: null, elapsedMs: 0, silenced: false, writingUp: null, discarded: []),
      );
      expect(
        parseMeetingState({
          'recording': true,
          'noteId': 'm',
          'discarded': ['a', 3, 'b'],
        })?.discarded,
        ['a', 'b'],
      );
      expect(parseMeetingState('recording'), isNull);
      expect(parseMeetingState({'noteId': 'm'}), isNull);
      expect(parseMeetingState(null), isNull);
    });

    test('is read as an event, with the extras each kind carries, and not without its name or, but for two, its note', () {
      expect(parseMeetingEvent(jsonEncode({'event': 'stopped', 'noteId': 'm1', 'elapsedMs': 9, 'reason': 'cap'})), const MeetingEvent(event: 'stopped', noteId: 'm1', elapsedMs: 9, reason: 'cap'));
      expect(parseMeetingEvent(jsonEncode({'event': 'permission', 'noteId': 'm1', 'granted': false})), const MeetingEvent(event: 'permission', noteId: 'm1', elapsedMs: 0, granted: false));
      expect(
        parseMeetingEvent(jsonEncode({'event': 'failed', 'noteId': 'm1', 'message': 'The meeting could not start.'})),
        const MeetingEvent(event: 'failed', noteId: 'm1', elapsedMs: 0, message: 'The meeting could not start.'),
      );
      expect(parseMeetingEvent(jsonEncode({'event': 'started'})), isNull);
      // The activity says these two with no note in hand: the microphone's answer and a tap on the notification.
      expect(parseMeetingEvent(jsonEncode({'event': 'permission', 'noteId': null, 'elapsedMs': 0, 'granted': true})), const MeetingEvent(event: 'permission', noteId: null, elapsedMs: 0, granted: true));
      expect(parseMeetingEvent(jsonEncode({'event': 'open', 'noteId': null, 'elapsedMs': 0})), const MeetingEvent(event: 'open', noteId: null, elapsedMs: 0));
      expect(parseMeetingEvent(jsonEncode({'event': 'discarded', 'noteId': null})), isNull);
      expect(parseMeetingEvent(jsonEncode({'noteId': 'm1'})), isNull);
      expect(parseMeetingEvent('not json'), isNull);
    });
  });

  group('the state', () {
    test('is null where there is no service to ask, and the service’s answer where there is', () {
      expect(live.meetingStateNow(), isNull);
      expect(live.readMeetingState(), isNull);
      host(recordingJson);
      expect(live.readMeetingState(), recording);
      expect(live.meetingStateNow(), recording);
    });

    test('keeps the same object while the service says the same thing, so a read a second does not wake every listener', () {
      host(recordingJson);
      final first = live.readMeetingState();
      expect(identical(live.readMeetingState(), first), true);
      host({...recordingJson, 'elapsedMs': 6000});
      expect(identical(live.readMeetingState(), first), false);
      expect(live.readMeetingState()?.elapsedMs, 6000);
    });

    test('is nothing recording, not null, when the service answers something this build cannot read', () {
      host({'something': 'else'});
      final read = live.readMeetingState();
      expect((read?.recording, read?.noteId), (false, null));
    });
  });

  group('a push from the service', () {
    test('moves the state before the service is asked again, and reaches everyone who asked to hear it', () {
      final heard = <String>[];
      final off = live.onMeetingEvent((event) => heard.add(event.event));
      // No service on this host: the push alone is what the page knows.
      push({'event': 'started', 'noteId': 'm1', 'elapsedMs': 0});
      var now = live.meetingStateNow()!;
      expect((now.recording, now.noteId, now.silenced), (true, 'm1', false));
      push({'event': 'silenced', 'noteId': 'm1', 'elapsedMs': 100});
      now = live.meetingStateNow()!;
      expect((now.recording, now.silenced, now.elapsedMs), (true, true, 100));
      push({'event': 'sounding', 'noteId': 'm1', 'elapsedMs': 200});
      now = live.meetingStateNow()!;
      expect((now.recording, now.silenced), (true, false));
      push({'event': 'stopped', 'noteId': 'm1', 'elapsedMs': 300, 'reason': 'done'});
      now = live.meetingStateNow()!;
      expect((now.recording, now.noteId, now.writingUp), (false, null, 'm1'));
      push({'event': 'started', 'noteId': 'm2', 'elapsedMs': 0});
      push({'event': 'discarded', 'noteId': 'm2', 'elapsedMs': 50});
      now = live.meetingStateNow()!;
      expect(now.recording, false);
      expect(now.discarded, ['m2']);
      push({'event': 'started', 'noteId': 'm3', 'elapsedMs': 0});
      push({'event': 'failed', 'noteId': 'm3', 'message': 'The meeting could not start.'});
      now = live.meetingStateNow()!;
      expect((now.recording, now.noteId), (false, null));
      expect(heard, ['started', 'silenced', 'sounding', 'stopped', 'started', 'discarded', 'started', 'failed']);
      off();
      push({'event': 'open', 'noteId': 'm1', 'elapsedMs': 0});
      expect(heard, hasLength(8));
      // A push this build cannot read is dropped whole.
      expect(() => live.heard('{'), returnsNormally);
    });

    test('asks the service again after a push, where there is one, so the state is the service’s and not the guess', () {
      host({...recordingJson, 'elapsedMs': 42});
      push({'event': 'started', 'noteId': 'm1', 'elapsedMs': 0});
      final now = live.meetingStateNow()!;
      expect((now.recording, now.elapsedMs, now.title), (true, 42, 'Meeting, 26 Sep 14:05'));
    });
  });

  group('whether the phone may notify', () {
    test('is read from the host, kept, and read again when the prompt is answered', () {
      expect(live.canNotifyNow(), false);
      host(recordingJson, true);
      expect(live.canNotifyNow(), true);
      host(recordingJson, false);
      live.notified();
      expect(live.canNotifyNow(), false);
    });
  });

  group('the poll', () {
    testWidgets('asks the service once a second while someone listens and the page is visible, and stops when the last listener goes', (tester) async {
      final counts = host(recordingJson);
      MeetingState? seen;
      final unmount = live.subscribe(() => seen = live.state);
      seen = live.state;
      expect(counts.asked, 1);
      expect(seen, recording);
      await tester.pump(const Duration(milliseconds: 3000));
      expect(counts.asked, 4);
      // Hidden, the poll waits; visible again, it reads at once.
      theHost.visible = false;
      await tester.pump(const Duration(milliseconds: 2000));
      expect(counts.asked, 4);
      theHost.visible = true;
      live.visibilityChanged();
      expect(counts.asked, 5);
      unmount();
      await tester.pump(const Duration(milliseconds: 3000));
      expect(counts.asked, 5);
    });

    test('asks again when the activity’s refresh reaches the page, as the notes store echoes it', () async {
      final counts = host(recordingJson);
      expect(counts.asked, 0);
      live.notesChanged();
      expect(counts.asked, 1);
    });

    testWidgets('asks nothing of a host without the service', (tester) async {
      MeetingState? seen;
      final unmount = live.subscribe(() => seen = live.state);
      seen = live.state;
      await tester.pump(const Duration(milliseconds: 3000));
      expect(seen, isNull);
      expect(theHost.asked, 0);
      // The web's `afterEach` unmounts the probe.
      unmount();
    });
  });

  group('whether a write-up is running', () {
    test('is so by the last look at the jobs, or by the service saying which note it is writing up', () {
      expect(live.writeUpRunning(), false);
      jobsRunning = true;
      expect(live.writeUpRunning(), true);
      jobsRunning = false;
      live.setMeetingStateForTests(recording.copyWith(recording: false, writingUp: () => 'm1'));
      expect(live.writeUpRunning(), true);
    });
  });

  // The two sides of the bridge are typed twice, once in Kotlin and once here, and a key misspelt in either is read
  // as nothing without a word. So what the service and the activity build is read out of their sources and held to
  // what this store parses. The Kotlin is the web app's, in the repo beside this one (tauri/), until the meeting
  // service is ported here (piece 8E), when these three should read this repo's own.
  group('what the Kotlin says, and what the page reads', () {
    const android = 'tauri/src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph';
    final service = File('$android/capture/MeetingService.kt').readAsStringSync();
    final activity = File('$android/MainActivity.kt').readAsStringSync();

    /// Every `.put("key"` in [text].
    Set<String> keys(String text) => {for (final match in RegExp(r'\.put\("([A-Za-z]+)"').allMatches(text)) match.group(1)!};

    /// The body of `fun <name>(` up to the next `fun ` at the same indent or deeper, roughly: enough for its puts.
    String body(String text, String name) {
      final from = text.indexOf('fun $name(');
      expect(from, greaterThan(-1), reason: 'fun $name');
      final ends = [
        text.indexOf('\n  fun ', from + 1),
        text.indexOf('\n  private fun ', from + 1),
        text.indexOf('\n    fun ', from + 1),
        text.indexOf('\n    private fun ', from + 1),
      ].where((at) => at > from).toList();
      return text.substring(from, ends.isEmpty ? text.length : ends.reduce(math.min));
    }

    test('has every key of the state the service answers, and no other', () {
      final answered = keys(body(service, 'meetingState'));
      // As a binary of generation 25 answers it: other apps' three keys are read only from one that says them.
      expect(answered.toList()..sort(), parseMeetingState({'recording': false, 'otherApps': false})!.toJson().keys.toList()..sort());
    });

    test('knows every event the service and the activity push, and every key they carry', () {
      final known = [for (final name in MeetingEventName.values) name.name];
      expect(known, ['started', 'silenced', 'sounding', 'stopped', 'discarded', 'failed', 'permission', 'asked', 'open']);
      final pushed = <String>{
        for (final match in RegExp(r'push\("([a-z]+)"').allMatches(service)) match.group(1)!,
        for (final match in RegExp(r'if \(now\) "([a-z]+)" else "([a-z]+)"').allMatches(service)) ...[match.group(1)!, match.group(2)!],
        for (final match in RegExp(r'\.put\("event", "([a-z]+)"\)').allMatches('$service$activity')) match.group(1)!,
      };
      expect(pushed.length, greaterThanOrEqualTo(8));
      for (final name in pushed) {
        expect(known, contains(name), reason: 'the page does not know "$name"');
      }
      final carried = <String>{
        ...keys(body(service, 'push')),
        ...keys(body(service, 'pushStopped')),
        ...keys(body(service, 'pushFailed')),
        ...keys(body(service, 'offerDied')),
        for (final match in RegExp(r'tell\("meeting", ([^\n]+)').allMatches(activity)) ...keys(match.group(1)!),
        ...keys(body(activity, 'deliverMeeting')),
      };
      expect(carried.toList()..sort(), [...meetingEventKeys]..sort());
    });

    test('stops a meeting only for the reasons the page names', () {
      final reasons = <String>{for (final match in RegExp(r'requestStop\("([a-z]+)"\)').allMatches(service)) match.group(1)!};
      reasons.add('died');
      final named = [for (final reason in MeetingStopReason.values) reason.name];
      expect(named, ['done', 'notification', 'cap', 'error', 'died']);
      for (final reason in reasons) {
        expect(named, contains(reason));
      }
    });
  });

  group('on the app\'s record of running work (docs/ACTIVITY.md)', () {
    late Activity record;
    setUp(() => useActivity(record = Activity(store: () => MemoryStored())));
    tearDown(() => useActivity(Activity()));

    test('the recording is a job with the notification\'s Done as its Stop, and its write-up one that ends as Written up', () {
      var stopped = 0;
      host({...recordingJson, 'elapsedMs': 125000});
      final unfollow = live.followOnRecord(stop: () => stopped += 1, titleOf: (id) => 'Standup');
      live.readMeetingState();
      final recordingJob = record[meetingRecordingJobId]!;
      expect((recordingJob.kind, recordingJob.title, recordingJob.liveLine), (JobKind.audio, 'Recording Meeting, 26 Sep 14:05', 'Recording, 2 min'));
      recordingJob.onStop!();
      expect(stopped, 1);
      final ended = <Job>[];
      final hearing = record.events.where((e) => e.kind == JobEventKind.ended).listen((e) => ended.add(e.job!));
      theHost.state = {...recordingJson, 'recording': false, 'noteId': null, 'title': null, 'startedAt': null, 'elapsedMs': 0, 'writingUp': 'm1'};
      push({'event': 'stopped', 'noteId': 'm1', 'elapsedMs': 130000});
      expect(record[meetingRecordingJobId], isNull);
      expect(ended.single.result, isNull, reason: 'the person pressed Done: no chip for it');
      final writing = record[writeUpJobId('m1')]!;
      expect((writing.title, writing.liveLine), ('Writing up Standup', 'Transcribing'));
      theHost.state = {...recordingJson, 'recording': false, 'noteId': null, 'writingUp': null};
      live.readMeetingState();
      expect(record.value, isEmpty);
      expect(ended.last.result!.words, 'Written up');
      expect(record.log.today.words, '1 meeting recorded, 1 meeting written up');
      hearing.cancel();
      unfollow();
    });
  });
}
