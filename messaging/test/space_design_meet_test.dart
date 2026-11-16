import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/hangout_screen.dart';
import 'package:ghost_messaging/ui/space_designs/meet.dart';

import 'support/space_call_harness.dart';

/// The space call drawn after Google Meet (lib/ui/space_designs/meet.dart): its pictures on a phone and a computer,
/// light and dark, and its buttons doing what they say. Matt, 2026-11-16: "give me 6 alternate designs for the calling
/// chat and video screens for spaces".
void main() {
  void ok(WidgetTester tester) {
    final e = tester.takeException();
    if (e is FlutterError) debugPrint(e.toStringDeep());
    expect(e, isNull);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final f = find.bySemanticsLabel(label);
    expect(f, findsWidgets, reason: label);
    await tester.tap(f.last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('pictures: phone, computer, alone, chat, video; light and dark', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await h.shoot(tester, MeetCall(call: h.call()), 'space-meet-phone', dark: dark);
      ok(tester);
      await h.shoot(tester, MeetCall(call: h.call()), 'space-meet-computer', size: SpaceHarness.computer, dark: dark);
      ok(tester);
      await h.shoot(tester, MeetCall(call: h.call(people: 0, video: const {})), 'space-meet-alone', dark: dark);
      ok(tester);
      await h.shoot(tester, MeetCall(call: h.call(people: 0, video: const {})), 'space-meet-alone-computer', size: SpaceHarness.computer, dark: dark);
      ok(tester);
      await h.shoot(tester, MeetCall(call: h.call(video: const {'a', 'c'}, myVideo: true)), 'space-meet-video', size: SpaceHarness.computer, dark: dark);
      ok(tester);

      // The chat as a page of its own on a phone.
      await h.shoot(tester, MeetCall(call: h.call()), 'space-meet-chat-check-before', dark: dark);
      await tap(tester, 'Chat');
      await h.again(tester, 'space-meet-chat', dark: dark);
      expect(find.byType(HangoutChat), findsOneWidget);
      expect(find.text('In-call messages'), findsOneWidget);
      ok(tester);

      // People and chat side by side with the tiles on a computer.
      await h.shoot(tester, MeetCall(call: h.call()), 'space-meet-computer-people-check-before', size: SpaceHarness.computer, dark: dark);
      await tap(tester, 'People');
      await h.again(tester, 'space-meet-computer-people', dark: dark);
      expect(find.text('Search for people'), findsWidgets);
      ok(tester);
      await tap(tester, 'Chat');
      await h.again(tester, 'space-meet-computer-chat', dark: dark);
      expect(find.byType(HangoutChat), findsOneWidget);
      ok(tester);

      // More options open over the bar.
      await h.shoot(tester, MeetCall(call: h.call()), 'space-meet-more-check-before', dark: dark);
      await tap(tester, 'More options');
      await h.again(tester, 'space-meet-more', dark: dark);
      ok(tester);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
    final where = size == SpaceHarness.phone ? 'phone' : 'computer';
    testWidgets('$where: the buttons write what they say', (tester) async {
      final h = await SpaceHarness.load(tester);
      addTearDown(tester.view.reset);
      final log = <String>[];
      await h.shoot(tester, MeetCall(call: h.call(log: log)), 'space-meet-check-buttons-$where', size: size);
      await tap(tester, 'Mute');
      await tap(tester, 'Video');
      await tap(tester, 'Deafen');
      await tap(tester, 'Leave call');
      await tap(tester, 'Maya Chen');
      await tap(tester, 'More options');
      await tap(tester, 'Settings');
      await tap(tester, 'More options');
      await tap(tester, 'Devices');
      await tap(tester, 'More options');
      await tap(tester, 'Invite');
      await tap(tester, 'More options');
      await tap(tester, 'Minimise');
      expect(log, ['mute', 'video', 'deafen', 'leave', 'person a', 'settings', 'devices', 'invite', 'minimize']);
      // People panel: a person's row presses through to them.
      log.clear();
      await tap(tester, 'People');
      await tap(tester, 'Sam Ortiz');
      expect(log, contains('person b'));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the mic is held off when the mic is locked', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, MeetCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-meet-check-locked', size: SpaceHarness.computer);
    expect(find.text('Muted for you'), findsOneWidget);
    await tap(tester, 'You can\'t unmute here');
    expect(log, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alone: your own tile is drawn and moves with your voice; Invite people opens the invite', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, MeetCall(call: h.call(people: 0, video: const {}, log: log)), 'space-meet-check-alone');
    expect(find.text('Me (You)'), findsOneWidget);
    expect(find.text('You\'re the only one here'), findsOneWidget);
    // Talking: the tile is outlined blue. Quiet: not.
    BoxBorder? border() {
      final box = tester.widget<AnimatedContainer>(find.ancestor(of: find.text('Me (You)'), matching: find.byType(AnimatedContainer)).first);
      return (box.decoration as BoxDecoration?)?.border;
    }

    h.levels.value = const {'me': 0.5};
    await tester.pump(const Duration(milliseconds: 200));
    expect((border() as Border).top.width, 3);
    h.levels.value = const {'me': 0};
    await tester.pump(const Duration(milliseconds: 200));
    expect((border() as Border).top.width, 1);
    await tap(tester, 'Invite people');
    expect(log, ['invite']);
    await tester.pumpWidget(const SizedBox());
  });
}
