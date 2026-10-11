import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/capture/meeting_live.dart';
import 'package:ghost_md/capture/ui/meeting_screen.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences, preferences;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/shell/header_pane.dart';
import 'package:ghost_md/tapes/tape_art.dart';

import '../support/render.dart';
import 'support/harness.dart';

/// The meeting screen held to the page: a meeting twelve and a half minutes in, recorded by a pretended service, its
/// rectangles asserted to half a pixel against what the web app's page gave in Chromium over the same pretended host
/// (`test/capture_ui/reference/capture_reference.mjs`, `fixtures/meeting-<size>.json`), at a phone's size and a wide
/// one, and a picture of it light and dark in `shots/`.
///
/// Not held: a width where one side's element is its words and the other's the room it was given (the line under
/// the cassette, "Meeting" in the top line); its place and its height are.
void main() {
  setUpAll(loadAppFonts);

  const clock = 1790000000000;

  for (final size in const [Size(390, 844), Size(1200, 800)]) {
    final at = '${size.width.round()}x${size.height.round()}';

    testWidgets('a meeting being recorded at $at: the line at the top, the cassette, what it says, Discard and Done', (tester) async {
      useStored(MemoryStored());
      final service = _Service(clock);
      final live = MeetingLive(host: service, writeUpRunningNow: () => false, now: () => clock)..readMeetingState();
      await pumpScreen(
        tester,
        MeetingScreen(
          noteId: 'meeting',
          fromAssistant: false,
          onLeave: () {},
          live: live,
          host: MeetingScreenHost(
            isLocked: () => false,
            endCapture: (_) {},
            stopMeeting: () {},
            discardMeeting: () {},
            requestNotifications: () => NotificationsAnswer.asked,
            deleteNote: (_) async {},
            dropSummary: (_) {},
            forgetMeeting: (_) {},
            haptic: (_) {},
          ),
        ),
        size: size,
        prefs: const Preferences(theme: 'light'),
        insets: EdgeInsets.zero,
      );
      await tester.pump(const Duration(milliseconds: 300));

      final web = (jsonDecode(File('test/capture_ui/fixtures/meeting-$at.json').readAsStringSync()) as Map<String, Object?>)['rects']! as Map<String, Object?>;
      void held(String name, Finder finder, {bool width = true}) {
        final page = web[name]! as Map<String, Object?>;
        final rect = tester.getRect(finder.first);
        final x = (page['x']! as num).toDouble(), y = (page['y']! as num).toDouble(), w = (page['width']! as num).toDouble(), h = (page['height']! as num).toDouble();
        final why = '$name: page ${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)} ${w.toStringAsFixed(2)} x ${h.toStringAsFixed(2)}; here ${rect.left.toStringAsFixed(2)}, ${rect.top.toStringAsFixed(2)} ${rect.width.toStringAsFixed(2)} x ${rect.height.toStringAsFixed(2)}';
        expect(rect.top, closeTo(y, 0.5), reason: why);
        expect(rect.height, closeTo(h, 0.5), reason: why);
        if (!width) return;
        expect(rect.left, closeTo(x, 0.5), reason: why);
        expect(rect.width, closeTo(w, 0.5), reason: why);
      }

      held('top', find.byType(HeaderPane));
      held('where', find.text('Meeting'), width: false);
      held('counter', find.text('12:34'));
      held('tape', find.byType(TapeArt));
      held('line0', find.textContaining('Recording. The screen can go off', findRichText: true), width: false);
      held('discard', find.widgetWithText(AppWord, 'Discard'));
      held('done', find.byType(AppPill));

      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/meeting-$at-light.png'));
      preferences.value = preferences.value.copyWith(theme: 'dark');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/meeting-$at-dark.png'));
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}

/// The phone's meeting service, pretended: a meeting on the note `meeting`, twelve minutes and thirty-four seconds
/// in, and notifications allowed.
class _Service implements MeetingHost {
  _Service(this.clock);

  final int clock;

  @override
  bool visible = true;

  @override
  bool get hasMeetings => true;

  @override
  String? meetingStateJson() => jsonEncode({
        'recording': true,
        'noteId': 'meeting',
        'title': 'Meeting, 8 Oct 15:18',
        'startedAt': clock - 754000,
        'elapsedMs': 754000,
        'silenced': false,
        'writingUp': null,
        'discarded': <String>[],
      });

  @override
  bool canNotify() => true;
}
