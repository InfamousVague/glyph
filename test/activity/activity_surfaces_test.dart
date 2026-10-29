// The record told to the device's own surfaces (lib/activity/activity_surfaces.dart; docs/ACTIVITY.md, OS surfaces):
// what each event says on `ghost_md/jobs`, which jobs each device shows, and Stop and Open coming back.
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_surfaces.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/prefs.dart' show syncedPrefs;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late DateTime now;
  late Activity record;
  late ValueNotifier<Preferences> prefs;
  late List<MethodCall> told;

  setUp(() {
    JobsHeard.reset();
    now = DateTime(2026, 10, 29, 9);
    final store = MemoryStored();
    record = Activity(clock: () => now, store: () => store);
    prefs = ValueNotifier(Preferences());
    told = [];
    messenger.setMockMethodCallHandler(jobsChannel, (call) async {
      told.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(jobsChannel, null);
    JobsHeard.reset();
  });

  ActivitySurfaces surfaces(SurfaceDevice device, {Duration promoteAfter = const Duration(seconds: 10)}) =>
      ActivitySurfaces(record: record, device: device, prefs: prefs, promoteAfter: promoteAfter)..start();

  List<Map<Object?, Object?>> activityCalls() => [for (final call in told) if (call.method == 'activity') call.arguments as Map<Object?, Object?>];
  Map<Object?, Object?> lastJob() => activityCalls().last['job']! as Map<Object?, Object?>;
  List<Object?> lastJobs() => activityCalls().last['jobs']! as List<Object?>;

  /// Says [method] from the device, as the phone's notification or the Mac's menu would.
  Future<Object?> fromDevice(String method, Map<String, Object?> args) async {
    Object? answer;
    await messenger.handlePlatformMessage(jobsChannel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (reply) {
      if (reply != null) answer = const StandardMethodCodec().decodeEnvelope(reply);
    });
    return answer;
  }

  group('on a phone', () {
    test('the look is told first, then a banner run as it starts, with its colour, glyph and Stop', () {
      surfaces(SurfaceDevice.android);
      expect(told.first.method, 'activityLook');
      expect(told.first.arguments, {'calm': false, 'menuBarAlways': false});
      record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', personStarted: true, onStop: () {});
      final call = activityCalls().single;
      expect(call['event'], 'started');
      final job = lastJob();
      expect(job['id'], 'lovart-banners');
      expect(job['kind'], 'images');
      expect(job['look'], 'images');
      expect(job['state'], 'running');
      expect(job['title'], 'Making header images');
      expect(job['line'], 'Making header images');
      expect(job.containsKey('fraction'), isFalse, reason: 'indeterminate until it says how far');
      expect(job['colour'], 0xFFD6336C);
      expect(job['colourDark'], 0xFFFF7AA8);
      expect(job['stoppable'], isTrue);
      expect(job['here'], isTrue);
      expect(lastJobs(), hasLength(1));
    });

    test('progress is told, no more often than the throttle; a wait at once; the end once', () {
      fakeAsync((async) {
        surfaces(SurfaceDevice.android);
        final job = record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images');
        job.progress(done: 1, total: 100);
        job.progress(done: 2, total: 100);
        job.progress(done: 3, total: 100);
        expect(activityCalls(), hasLength(1), reason: 'the moves are held back');
        async.elapse(const Duration(milliseconds: 600));
        expect(activityCalls(), hasLength(2));
        expect(activityCalls().last['event'], 'changed');
        expect(lastJob()['fraction'], closeTo(0.03, 1e-9));
        expect(lastJob()['steps'], '3 of 100');
        expect(lastJob()['line'], 'Making header images, 3 of 100');

        job.waiting(WaitingOn.wifi);
        expect(activityCalls(), hasLength(3), reason: 'a wait is a new state: told at once');
        expect(lastJob()['state'], 'waiting');
        expect(lastJob()['look'], 'waiting');
        expect(lastJob()['line'], 'Waiting for Wi-Fi');
        expect(lastJob()['colour'], 0xFF747474);

        job.done(result: const JobResult('Header images made', action: 'View'));
        expect(activityCalls().last['event'], 'ended');
        expect(lastJob()['state'], 'done');
        expect(lastJob()['result'], 'Header images made');
        expect(lastJobs(), isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(activityCalls(), hasLength(4), reason: 'nothing held back is told after the end');
      });
    });

    test('a failure ends it red, with its cause', () {
      surfaces(SurfaceDevice.android);
      final job = record.begin('share-audio:n1', kind: JobKind.audio, title: 'Sharing the recording of Standup');
      job.failed('The recording did not go: the connection dropped');
      expect(activityCalls().last['event'], 'ended');
      expect(lastJob()['state'], 'failed');
      expect(lastJob()['look'], 'needsYou');
      expect(lastJob()['colour'], 0xFFD1342B);
      expect(lastJob()['cause'], 'The recording did not go: the connection dropped');
      expect(lastJob()['line'], 'The recording did not go: the connection dropped');
      expect(lastJob()['stoppable'], isFalse);
    });

    test('a job the person started shows once it has run ten seconds; sync, the recording and its write-up never', () {
      fakeAsync((async) {
        surfaces(SurfaceDevice.android);
        record.begin('model:gemma', kind: JobKind.downloads, title: 'Downloading Gemma', personStarted: true, fraction: 0);
        record.begin('slack:n1', kind: JobKind.meetings, title: 'Posting Standup to Slack');
        record.begin('sync', kind: JobKind.sync, title: 'Syncing', personStarted: true);
        record.begin('meeting-recording', kind: JobKind.audio, title: 'Recording Standup', personStarted: true);
        record.begin('write-up:n1', kind: JobKind.audio, title: 'Writing up Standup', personStarted: true);
        expect(activityCalls(), isEmpty);
        async.elapse(const Duration(seconds: 9));
        expect(activityCalls(), isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(activityCalls().single['event'], 'started');
        expect(lastJob()['id'], 'model:gemma');
        expect(lastJob()['fraction'], 0.0);
        async.elapse(const Duration(minutes: 1));
        expect(activityCalls(), hasLength(1));
      });
    });

    test('a short job the person started is never told', () {
      fakeAsync((async) {
        surfaces(SurfaceDevice.android);
        record.begin('slack-post:n1', kind: JobKind.meetings, title: 'Posting to Slack', personStarted: true).done();
        async.elapse(const Duration(seconds: 20));
        expect(activityCalls(), isEmpty);
      });
    });

    test('Stop from the notification is the job\'s own Stop; Open opens what it is or what it made', () async {
      surfaces(SurfaceDevice.android);
      var stops = 0, opens = 0, results = 0;
      final job = record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', onStop: () => stops += 1, onOpen: () => opens += 1);
      expect(await fromDevice('activityStop', {'id': 'lovart-banners'}), isTrue);
      expect(stops, 1);
      expect(await fromDevice('activityOpen', {'id': 'lovart-banners'}), isTrue);
      expect(opens, 1);
      job.done(result: JobResult('Header images made', onOpen: () => results += 1));
      // Ended, its Open is the live one it had; a job with only a result's Open opens that.
      expect(await fromDevice('activityOpen', {'id': 'lovart-banners'}), isTrue);
      expect(opens, 2);
      record.begin('share-audio:n2', kind: JobKind.audio, title: 'Sharing').done(result: JobResult('Recording shared', onOpen: () => results += 1));
      expect(await fromDevice('activityOpen', {'id': 'share-audio:n2'}), isTrue);
      expect(results, 1);
      // Stop for an ended job, or one nobody knows, does nothing.
      expect(await fromDevice('activityStop', {'id': 'lovart-banners'}), isFalse);
      expect(stops, 1);
      expect(await fromDevice('activityOpen', {'id': 'nothing'}), isFalse);
    });

    test('the service notification\'s Stop still reaches every one that asked, beside the surfaces', () async {
      surfaces(SurfaceDevice.android);
      final heard = <String>[];
      ChannelBackgroundJobs(here: true).onStop((id) => heard.add('run:$id'));
      ChannelBackgroundJobs(here: true).onStop((id) => heard.add('other:$id'));
      await fromDevice('stop', {'id': 'lovart-banners'});
      expect(heard, ['run:lovart-banners', 'other:lovart-banners']);
    });
  });

  group('on the Mac', () {
    test('every job the ring shows, sync and another device\'s too, and the bloom', () {
      surfaces(SurfaceDevice.mac);
      final sync = record.begin('sync', kind: JobKind.sync, title: 'Syncing');
      record.elsewhere('lovart-claim', [Job(id: 'lovart-banners@mac', kind: JobKind.images, title: 'Making header images', device: 'mac', deviceName: 'Mac', startedAt: now)]);
      expect(lastJobs(), hasLength(2));
      final elsewhere = lastJob();
      expect(elsewhere['here'], isFalse);
      expect(elsewhere['device'], 'on your Mac');
      expect(elsewhere['stoppable'], isFalse);
      record.elsewhere('lovart-claim', const []);
      expect(activityCalls().last['event'], 'ended');
      expect(lastJobs(), hasLength(1));
      sync.done();
      expect(activityCalls().last['event'], 'allDone');
      expect(lastJobs(), isEmpty);
    });

    test('a failed job stays, red, until it is dismissed from the tray', () {
      surfaces(SurfaceDevice.mac);
      record.begin('slack:n1', kind: JobKind.meetings, title: 'Posting Standup to Slack').failed('Slack refused the token');
      expect(lastJobs().single, containsPair('state', 'failed'));
      record.dismiss('slack:n1');
      expect(activityCalls().last['event'], 'changed');
      expect(lastJobs(), isEmpty);
    });

    test('the menu bar switch and Calm are told as they change; Calm takes the colours from what shows', () {
      surfaces(SurfaceDevice.mac);
      record.begin('update', kind: JobKind.downloads, title: 'Downloading the update', fraction: 0.5);
      expect(lastJob()['colour'], 0xFF23873F);
      prefs.value = prefs.value.copyWith(menuBarAlways: true);
      expect(told.where((c) => c.method == 'activityLook').last.arguments, {'calm': false, 'menuBarAlways': true});
      prefs.value = prefs.value.copyWith(calm: true);
      expect(told.where((c) => c.method == 'activityLook').last.arguments, {'calm': true, 'menuBarAlways': true});
      expect(activityCalls().last['event'], 'changed');
      expect(lastJob().containsKey('colour'), isFalse);
      expect(lastJob()['fraction'], 0.5);
    });

    test('what was running before it started is told as begun', () {
      record.begin('update', kind: JobKind.downloads, title: 'Downloading the update');
      surfaces(SurfaceDevice.mac);
      expect(activityCalls().single['event'], 'started');
      expect(lastJob()['id'], 'update');
    });
  });

  group('on an iPhone', () {
    test('write-ups, summaries and uploads are Live Activities; a banner run is not', () {
      surfaces(SurfaceDevice.iphone);
      record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images');
      record.begin('sync', kind: JobKind.sync, title: 'Syncing');
      expect(activityCalls(), isEmpty);
      final up = record.begin('write-up:n1', kind: JobKind.audio, title: 'Writing up Standup', line: 'Transcribing');
      record.begin('share-audio:n2', kind: JobKind.audio, title: 'Sharing the recording of Retro');
      record.begin('summary:n3', kind: JobKind.ai, title: 'Summary of Planning');
      expect(activityCalls().map((c) => (c['job']! as Map)['id']), ['write-up:n1', 'share-audio:n2', 'summary:n3']);
      up.done(result: const JobResult('Written up', action: 'Open'));
      expect(activityCalls().last['event'], 'ended');
      expect(lastJob()['result'], 'Written up');
      expect(lastJobs(), hasLength(2));
    });
  });

  test('"Always show in the menu bar" is kept, and stays on the Mac it was set on', () {
    final on = Preferences().copyWith(menuBarAlways: true);
    expect(Preferences.fromJson(on.toJson()).menuBarAlways, isTrue);
    expect(Preferences.fromJson(Preferences().toJson()).menuBarAlways, isFalse);
    expect(syncedPrefs, isNot(contains('menuBarAlways')));
    expect(syncedPrefs, contains('calm'));
  });

  test('nothing is told on a device with no surfaces', () {
    surfaces(SurfaceDevice.none);
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images');
    expect(told, isEmpty);
  });

  test('the colours are the ones assets/css/app.css gives the ring', () {
    final css = File('assets/css/app.css').readAsStringSync();
    int read(String block, String token) => int.parse('FF${RegExp('--activity-$token: #([0-9a-f]{6});').firstMatch(block)!.group(1)!}', radix: 16);
    final paper = css.substring(css.indexOf(':root {\n  --activity-sync'));
    final dark = css.substring(css.indexOf("[data-theme='dark'] {\n  --activity-sync"));
    const tokens = {JobLook.sync: 'sync', JobLook.ai: 'ai', JobLook.images: 'images', JobLook.audio: 'audio', JobLook.meetings: 'meetings', JobLook.downloads: 'downloads', JobLook.needsYou: 'needs-you'};
    for (final MapEntry(key: look, value: token) in tokens.entries) {
      expect(surfaceColours[look]!.$1, read(paper, token), reason: '$token on paper');
      expect(surfaceColours[look]!.$2, read(dark, token), reason: '$token in the dark');
    }
  });
}
