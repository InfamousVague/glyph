/// The meeting screen (lib/capture/ui/meeting_screen.dart): the cassette turning and the counter, the lines it says,
/// and its two words to the service. Done stops the recording and leaves; Discard stops it, deletes the note and its
/// place in the preferences, and leaves; Back only leaves, with the recording going on.
/// `src/app/capture/MeetingScreen.test.tsx`, case for case.
///
/// What differs: the page's service was a stand-in on the window and its notes, preferences and summaries the real
/// modules; here the service is a stand-in [MeetingHost] under a real [MeetingLive], and everything else the screen
/// asks is a [MeetingScreenHost] that writes down what it was asked. The clock is the test's, standing still at
/// twelve and a half minutes in.
library;

import 'dart:async';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/ui/meeting_screen.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/tapes/tape_art.dart';

import '../support/render.dart';

const int clock = 1790000000000;

/// The service, as the activity's bridge hands it to the app.
class Service implements MeetingHost {
  Map<String, Object?> state = {
    'recording': true,
    'noteId': 'm1',
    'title': 'Meeting, 26 Sep 14:05',
    // Twelve and a half minutes in: the counter runs from when the service says the meeting began.
    'startedAt': clock - 754000,
    'elapsedMs': 754000,
    'silenced': false,
    'writingUp': null,
    'discarded': <String>[],
  };
  int stopped = 0;
  int discarded = 0;
  bool locked = false;
  List<bool> ended = [];
  bool notify = false;
  int asked = 0;
  NotificationsAnswer answer = NotificationsAnswer.asked;

  /// The phone's answer where it comes a moment after it was asked, as its channel's does.
  Future<NotificationsAnswer>? later;
  List<String> deleted = [];
  List<String> forgotten = [];
  List<String> dropped = [];

  /// Everything the screen asked of the phone and the app, in order.
  List<String> calls = [];

  @override
  bool visible = true;

  @override
  bool get hasMeetings => true;

  @override
  String? meetingStateJson() => jsonEncode(state);

  @override
  bool canNotify() => notify;
}

void main() {
  setUpAll(loadAppFonts);

  late Service service;
  late MeetingLive live;
  late BackStack stack;

  setUp(() {
    useStored(MemoryStored());
    service = Service();
    live = MeetingLive(host: service, writeUpRunningNow: () => false, now: () => clock);
    live.readMeetingState();
    stack = BackStack();
  });

  MeetingScreenHost host() => MeetingScreenHost(
        isLocked: () {
          service.calls.add('isLocked');
          return service.locked;
        },
        endCapture: (leave) {
          service.calls.add('endCapture');
          service.ended.add(leave);
        },
        stopMeeting: () {
          service.calls.add('stopMeeting');
          service.stopped += 1;
        },
        discardMeeting: () {
          service.calls.add('discardMeeting');
          service.discarded += 1;
        },
        requestNotifications: () {
          service.calls.add('requestNotifications');
          service.asked += 1;
          return service.later ?? service.answer;
        },
        deleteNote: (id) async {
          service.calls.add('deleteNote');
          service.deleted.add(id);
        },
        dropSummary: (id) {
          service.calls.add('dropSummary');
          service.dropped.add(id);
        },
        forgetMeeting: (id) {
          service.calls.add('forgetMeeting');
          service.forgotten.add(id);
        },
        haptic: (_) {},
      );

  Future<void> screen(WidgetTester tester, {bool fromAssistant = false, VoidCallback? onLeave}) async {
    await pumpApp(
      tester,
      home: BackScope(
        key: UniqueKey(),
        stack: stack,
        child: MeetingScreen(noteId: 'm1', fromAssistant: fromAssistant, onLeave: onLeave ?? () {}, live: live, host: host()),
      ),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// The page's `button('Stop and write up')`: Done, by the name a screen reader says.
  final done = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Stop and write up');

  Finder saying(String words) => find.textContaining(words, findRichText: true);

  group('the meeting screen', () {
    testWidgets('lets the screen go off: none of the recorder’s keep-awake, screen-off or refine holds', (tester) async {
      await screen(tester);
      await tester.pump(const Duration(seconds: 2));
      // FLAG_KEEP_SCREEN_ON and the SCREEN_OFF receiver are the dictation's; the screen going off is this one's
      // point. The screen is given no `setCapturing` and no refine queue to hold (a MeetingScreenHost has neither),
      // and of what it is given it asks nothing by being shown.
      expect(service.calls, isEmpty);
      await unmount(tester);
    });

    testWidgets('shows the cassette turning, the counter and the line that says the screen can go off', (tester) async {
      await screen(tester);
      expect(find.text('Meeting'), findsOneWidget);
      expect(find.text('12:34'), findsOneWidget);
      expect(saying('Recording. The screen can go off and you can leave. Stop here or from the notification.'), findsOneWidget);
      expect(tester.widget<TapeArt>(find.byType(TapeArt)).playing, isTrue);
      // Nothing of the note: the side key can open this over the lock screen.
      expect(saying('26 Sep'), findsNothing);
      await unmount(tester);
    });

    testWidgets('says when another app has muted the microphone', (tester) async {
      await screen(tester);
      expect(saying('Muted by another app.'), findsNothing);
      await unmount(tester);
      service.state = {...service.state, 'silenced': true};
      live.readMeetingState();
      await screen(tester);
      expect(saying('Muted by another app.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('says when other apps’ sound is in the meeting, that calls are not, and when it is the microphone alone', (tester) async {
      // A binary before generation 25 says nothing of it, and nothing is drawn.
      await screen(tester);
      expect(saying('other apps'), findsNothing);
      await unmount(tester);
      service.state = {...service.state, 'otherApps': true, 'otherAppsHeard': false, 'otherAppsNote': null};
      live.readMeetingState();
      await screen(tester);
      expect(saying('Listening for sound from other apps too. Media and games, never calls.'), findsOneWidget);
      await unmount(tester);
      service.state = {...service.state, 'otherAppsHeard': true};
      live.readMeetingState();
      await screen(tester);
      expect(saying('Recording sound from other apps too. Media and games, never calls.'), findsOneWidget);
      await unmount(tester);
      const declined = 'Sharing was not allowed, so only the microphone is recording.';
      service.state = {...service.state, 'otherApps': false, 'otherAppsHeard': false, 'otherAppsNote': declined};
      live.readMeetingState();
      await screen(tester);
      expect(saying(declined), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('on Done asks the service to stop and carry on as the write-up, and leaves', (tester) async {
      var left = 0;
      await screen(tester, onLeave: () => left += 1);
      await tester.tap(done);
      await tester.pump();
      expect(service.stopped, 1);
      expect(service.discarded, 0);
      expect(left, 1);
      // Not opened by the side key: nothing is said to the activity about the lock screen.
      expect(service.ended, isEmpty);
      await unmount(tester);
    });

    testWidgets('on Discard asks the service to throw the recording away, deletes the note itself, forgets it as a meeting, drops its write-up and leaves', (tester) async {
      var left = 0;
      await screen(tester, onLeave: () => left += 1);
      await tester.tap(find.text('Discard'));
      await tester.pump();
      expect(service.discarded, 1);
      expect(service.stopped, 0);
      expect(service.deleted, ['m1']);
      expect(service.forgotten, ['m1']);
      expect(service.dropped, ['m1']);
      expect(left, 1);
      await unmount(tester);
    });

    testWidgets('on Back only leaves: the recording goes on, stoppable here again or from the notification', (tester) async {
      var left = 0;
      await screen(tester, onLeave: () => left += 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(left, 1);
      expect(service.stopped, 0);
      expect(service.discarded, 0);
      await unmount(tester);
    });

    testWidgets('opened by the side key, hands a locked phone back to its lock screen as it leaves, however it leaves', (tester) async {
      service.locked = true;
      var left = 0;
      await screen(tester, fromAssistant: true, onLeave: () => left += 1);
      await tester.tap(done);
      await tester.pump();
      expect(service.ended, [true]);
      expect(left, 1);
      await unmount(tester);
    });

    testWidgets('offers to be told when the meeting is written up, once, and says so only once the phone has answered no', (tester) async {
      await screen(tester);
      expect(saying('Let Ghost.md tell you when it is written up.'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      expect(service.asked, 1);
      // Asked: the offer goes, and nothing is said until the phone answers.
      expect(saying('Let Ghost.md tell you'), findsNothing);
      expect(saying('Notifications are off'), findsNothing);
      // Answered no: the notification's Stop is not coming, and the screen says where to stop.
      live.notified();
      await tester.pump();
      expect(saying('Notifications are off for Ghost.md, so stop it here.'), findsOneWidget);
      await unmount(tester);
      // Remembered on this device: the next meeting is not asked again, and a no that stands is said at once.
      await screen(tester);
      expect(saying('Let Ghost.md tell you'), findsNothing);
      expect(saying('Notifications are off for Ghost.md, so stop it here.'), findsOneWidget);
      await unmount(tester);
      // Allowed since, in the phone's settings: nothing to say.
      service.notify = true;
      await screen(tester);
      expect(saying('Let Ghost.md tell you'), findsNothing);
      expect(saying('Notifications are off'), findsNothing);
      await unmount(tester);
    });

    testWidgets('says yes at once when the phone answers yes', (tester) async {
      await screen(tester);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      service.notify = true;
      live.notified();
      await tester.pump();
      expect(saying('Notifications are off'), findsNothing);
      expect(saying('Let Ghost.md tell you'), findsNothing);
      await unmount(tester);
    });

    // Differs 16 (docs/PARITY.md): the phone's channel answers a moment after it is asked, and the port marked the
    // meeting as asked before it had: a phone that blocks the prompt outright was remembered as asked, and said
    // nothing until a `notified` that never came.
    testWidgets('waits for the phone\'s own answer: blocked a moment later is said as blocked, and a prompt that went up is remembered as asked', (tester) async {
      final answer = Completer<NotificationsAnswer>();
      service.later = answer.future;
      await screen(tester);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      // Asked of the phone, and nothing changed until it says: the offer stands.
      expect(service.asked, 1);
      expect(saying('Let Ghost.md tell you when it is written up.'), findsOneWidget);
      expect(saying('Notifications are off'), findsNothing);
      answer.complete(NotificationsAnswer.blocked);
      await tester.pump();
      await tester.pump();
      expect(saying('Notifications are off for Ghost.md, so stop it here.'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      await unmount(tester);
      // Not remembered as asked: no prompt was ever shown, so the next meeting offers again.
      service.later = Future<NotificationsAnswer>.value(NotificationsAnswer.asked);
      await screen(tester);
      expect(saying('Let Ghost.md tell you when it is written up.'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      await tester.pump();
      // The prompt is up: the offer goes, and nothing is said until it is answered.
      expect(saying('Let Ghost.md tell you'), findsNothing);
      expect(saying('Notifications are off'), findsNothing);
      await unmount(tester);
      service.later = null;
      await screen(tester);
      expect(saying('Let Ghost.md tell you'), findsNothing, reason: 'asked on an earlier meeting');
      await unmount(tester);
    });

    testWidgets('says the notification’s Stop is not coming when the phone blocks the prompt outright', (tester) async {
      service.answer = NotificationsAnswer.blocked;
      await screen(tester);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      expect(saying('Notifications are off for Ghost.md, so stop it here.'), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
      await unmount(tester);
    });
  });
}
