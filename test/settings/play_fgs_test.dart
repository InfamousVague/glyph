// Google Play's build keeps two foreground service types, microphone and the write-up (Matt, 2026-11-09, after Play's
// rejection of 2026-11-06 under "Permissions for Foreground Services"; docs/store/play/forms.md). Its manifest
// (android/app/src/play/AndroidManifest.xml) removes special use, media projection, the long-jobs service and
// WorkManager's foreground types; the app hides "Include sound from other apps" and never asks for it; the Kotlin
// reads what is declared (glyph/capture/ForegroundTypes.kt, pinned by ForegroundTypesTest on the JVM). The sideload
// APK keeps everything.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/meeting_host.dart';
import 'package:ghost_md/capture/meeting_live_words.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/settings/panes/recording_pane.dart';
import 'package:ghost_md/settings/panes/settings_host.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  String read(String path) => File(path).readAsStringSync();
  String uncommented(String xml) => xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  Widget page(Widget child) => SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child));
  const features = SettingsFeatures(meetings: true, meetingSound: true);

  group('the manifests', () {
    test('Play’s removes special use, media projection, the job service and WorkManager’s types, media processing (2026-11-11), and keeps the microphone', () {
      final play = uncommented(read('android/app/src/play/AndroidManifest.xml'));
      expect(play, contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE" tools:node="remove"'));
      expect(play, contains('android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" tools:node="remove"'));
      expect(play, isNot(contains('FOREGROUND_SERVICE_MICROPHONE')), reason: 'the microphone permission is kept from src/main');
      expect(play, contains('android.permission.FOREGROUND_SERVICE_MEDIA_PROCESSING" tools:node="remove"'));
      final meeting = RegExp(r'<service\s+android:name="com\.mattssoftware\.glyph\.capture\.MeetingService"(.*?)</service>', dotAll: true).firstMatch(play)!.group(1)!;
      expect(meeting, contains('android:foregroundServiceType="microphone"'));
      expect(meeting, contains('tools:replace="android:foregroundServiceType"'));
      expect(meeting, contains('android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" tools:node="remove"'));
      expect(play, contains(RegExp(r'android:name="com\.mattssoftware\.ghost_md\.BackgroundJobService"\s+tools:node="remove"')));
      final work = RegExp(r'<service\s+android:name="androidx\.work\.impl\.foreground\.SystemForegroundService"(.*?)</service>', dotAll: true).firstMatch(play)!.group(1)!;
      expect(work, contains('tools:remove="android:foregroundServiceType"'));
      expect(work, contains('android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" tools:node="remove"'));
    });

    test('the sideload APK’s manifest is untouched: all four types, the job service, the worker’s types', () {
      final main = read('android/app/src/main/AndroidManifest.xml');
      for (final permission in ['MICROPHONE', 'MEDIA_PROCESSING', 'SPECIAL_USE', 'MEDIA_PROJECTION']) {
        expect(main, contains('android.permission.FOREGROUND_SERVICE_$permission"'));
      }
      expect(main, contains('android:foregroundServiceType="microphone|mediaProjection|mediaProcessing|specialUse"'));
      expect(main, contains('android:name="com.mattssoftware.ghost_md.BackgroundJobService"'));
      expect(main, contains('android:foregroundServiceType="mediaProcessing|specialUse"'));
    });

    test('the Kotlin asks the manifest before every foreground start', () {
      final meeting = read('android/app/src/main/kotlin/com/mattssoftware/glyph/capture/MeetingService.kt');
      expect(meeting, isNot(contains('FOREGROUND_SERVICE_TYPE_SPECIAL_USE')));
      expect(meeting, isNot(contains('FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION')));
      expect(meeting, contains('ForegroundTypes.writeUpType(this) == null'));
      final worker = read('android/app/src/main/kotlin/com/mattssoftware/glyph/recordings/RecordingWorker.kt');
      expect(worker, contains('val type = ForegroundTypes.workerType(context)'));
      expect(worker, contains('val foregrounded = type != null &&'));
      final jobs = read('android/app/src/main/kotlin/com/mattssoftware/ghost_md/BackgroundJobs.kt');
      expect(jobs, contains('if (!ForegroundTypes.jobServiceDeclared(context)) return "inApp"'));
      final other = read('android/app/src/main/kotlin/com/mattssoftware/glyph/capture/OtherApps.kt');
      expect(other, contains('!ForegroundTypes.otherAppsAllowed(context) -> NOT_IN_THIS_BUILD'));
    });
  });

  group('Include sound from other apps', () {
    testWidgets('is not on Play’s Recording page, and the rest of Meetings is', (tester) async {
      await pumpSettings(tester, page(RecordingPane(android: true, playStore: true, features: features, liveWords: LiveWordsSetting(phone: true))));
      expect(find.text('Include sound from other apps'), findsNothing);
      expect(find.text('Live transcript during meetings'), findsOneWidget);
      expect(find.text('Write up straight away'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('is still on the sideload APK’s', (tester) async {
      await pumpSettings(tester, page(RecordingPane(android: true, playStore: false, features: features, liveWords: LiveWordsSetting(phone: true))));
      expect(find.text('Include sound from other apps'), findsOneWidget);
      await endSettings(tester);
    });

    test('is not found by searching Settings in Play’s build', () {
      expect(recordingFindable(android: true, playStore: true).map((f) => f.name), isNot(contains('Include sound from other apps')));
      expect(recordingFindable(android: true, playStore: true).map((f) => f.name), contains('Write up straight away'));
      expect(recordingFindable(android: true, playStore: false).map((f) => f.name), contains('Include sound from other apps'));
    });

    testWidgets('Play’s phone is never asked about it, and a meeting never asks for it', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(DeviceMeetingHost.channel, (call) async {
        calls.add(call);
        return call.method == 'meetingSound' ? '{"supported": true, "reason": null}' : 'started';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(DeviceMeetingHost.channel, null));

      final play = await DeviceMeetingHost.attach(playStore: true);
      expect(await play.meetingSound(), isNull, reason: 'no switch drawn anywhere: the + sheet, Settings, the meeting screen');
      expect(await play.startMeeting('n1', 'Standup', otherApps: true), 'started');
      expect(calls.map((c) => c.method), ['startMeeting'], reason: 'never startMeetingWith, so no screen-share consent');
      expect((calls.single.arguments as Map)['otherApps'], isFalse);

      calls.clear();
      final side = await DeviceMeetingHost.attach(playStore: false);
      expect((await side.meetingSound())?.supported, isTrue);
      await side.startMeeting('n2', 'Standup', otherApps: true);
      expect(calls.map((c) => c.method), ['meetingSound', 'startMeetingWith']);
    });
  });
}
