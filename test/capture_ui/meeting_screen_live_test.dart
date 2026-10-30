/// The phone's meeting screen with the meeting's words live under the cassette (lib/capture/ui/meeting_screen.dart,
/// lib/capture/meeting_live_words.dart; Matt, 2026-10-30: "If possible add real time transcriptions for meetings"): up
/// on the screen it asks for them, a few lines, the newest last; gone from the screen it lets them go; and with the
/// setting off or the phone off its charger it says why instead. Over a fake recogniser and a fake service.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/meeting_live_words.dart';
import 'package:ghost_md/capture/ui/meeting_screen.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/meet/live_transcript.dart';
import 'package:ghost_md/meet/ui/live_transcript_view.dart';

import '../support/render.dart';

const int clock = 1790000000000;

class _Service implements MeetingHost {
  Map<String, Object?> state = {
    'recording': true,
    'noteId': 'm1',
    'title': 'Meeting, 26 Sep 14:05',
    'startedAt': clock - 754000,
    'elapsedMs': 754000,
    'silenced': false,
    'writingUp': null,
    'discarded': <String>[],
  };

  @override
  bool visible = true;
  @override
  bool get hasMeetings => true;
  @override
  String? meetingStateJson() => jsonEncode(state);
  @override
  bool canNotify() => true;
}

class _Feed implements LiveWordsHost {
  bool on = false;
  @override
  Future<bool> feed(bool on) async {
    this.on = on;
    return true;
  }
}

class _Model implements LiveRecogniser {
  final StreamController<CaptureEvent> said = StreamController<CaptureEvent>.broadcast(sync: true);
  bool listening = false;
  @override
  Stream<CaptureEvent> get events => said.stream;
  @override
  Future<bool> start() async => listening = true;
  @override
  Future<void> stop() async => listening = false;
  void say(int at, String text) => said.add(CaptureEventSegment(Segment(startMs: at, endMs: at + 2000, text: text)));
}

void main() {
  setUpAll(loadAppFonts);

  late _Service service;
  late MeetingLive live;
  late _Feed feed;
  late _Model model;
  late LiveWordsSetting setting;
  late LiveTranscripts store;
  late MeetingLiveWords words;
  var charging = true;

  setUp(() {
    useStored(MemoryStored());
    service = _Service();
    live = MeetingLive(host: service, writeUpRunningNow: () => false, now: () => clock);
    live.readMeetingState();
    feed = _Feed();
    model = _Model();
    setting = LiveWordsSetting(phone: true);
    store = LiveTranscripts();
    charging = true;
    words = MeetingLiveWords(meeting: live, host: feed, recogniser: model, setting: setting, charging: () => charging, inFront: () => true, dictating: () => false, now: () => clock, store: store);
  });

  MeetingScreenHost host() => MeetingScreenHost(
        isLocked: () => false,
        endCapture: (_) {},
        stopMeeting: () {},
        discardMeeting: () {},
        requestNotifications: () => NotificationsAnswer.allowed,
        deleteNote: (_) async {},
        dropSummary: (_) {},
        forgetMeeting: (_) {},
        haptic: (_) {},
      );

  Future<void> screen(WidgetTester tester) => pumpApp(
        tester,
        home: BackScope(key: UniqueKey(), stack: BackStack(), child: MeetingScreen(noteId: 'm1', fromAssistant: false, onLeave: () {}, live: live, host: host(), liveWords: words, words: store)),
      );

  Future<void> beat(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    unawaited(words.close());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('up on the screen, the words come under the cassette as a few lines, timed, the newest last', (tester) async {
    await screen(tester);
    await beat(tester);
    expect((model.listening, feed.on), (true, true));
    expect(find.byType(LiveLines), findsOneWidget);
    expect(find.byType(LiveBadge), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      model.say(i * 6000, 'phrase number $i.');
    }
    await beat(tester);
    // Each six seconds apart, so a turn each; the last three shown, timed from the meeting's start (it began 12:34
    // before the model did).
    final shown = [for (final text in tester.widgetList<RichText>(find.descendant(of: find.byType(LiveLines), matching: find.byType(RichText)))) text.text.toPlainText()];
    expect(shown.where((s) => s.contains('Phrase number')), ['12:46  Phrase number 2.', '12:52  Phrase number 3.', '12:58  Phrase number 4.']);
    await unmount(tester);
    expect((model.listening, feed.on), (false, false), reason: 'off the screen, let go');
  });

  testWidgets('with the setting off or the phone off its charger it says why, and listens to nothing', (tester) async {
    setting.value = LiveWordsChoice.off;
    await screen(tester);
    await beat(tester);
    expect(model.listening, isFalse);
    expect(find.byType(LiveLines), findsNothing);
    expect(find.textContaining('Live transcript is off', findRichText: true), findsOneWidget);
    await unmount(tester);
    setting.value = LiveWordsChoice.charging;
    charging = false;
    words = MeetingLiveWords(meeting: live, host: feed, recogniser: model, setting: setting, charging: () => charging, inFront: () => true, dictating: () => false, now: () => clock, store: store);
    await screen(tester);
    await beat(tester);
    expect(model.listening, isFalse);
    expect(find.textContaining('while the phone is charging', findRichText: true), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no live words when nothing is recording', (tester) async {
    service.state = {...service.state, 'recording': false, 'noteId': null, 'startedAt': null};
    live.readMeetingState();
    await screen(tester);
    await beat(tester);
    expect(model.listening, isFalse);
    expect(find.byType(LiveLines), findsNothing);
    await unmount(tester);
  });
}
