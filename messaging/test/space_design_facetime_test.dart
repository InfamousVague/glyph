import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:ghost_messaging/ui/ripple_avatar.dart';
import 'package:ghost_messaging/ui/space_designs/facetime.dart';
import 'package:ghost_messaging/ui/space_designs/space_design.dart';

import 'support/space_call_harness.dart';

/// The FaceTime-like space call (lib/ui/space_designs/facetime.dart): pictures on a phone and a computer, full, alone,
/// with the chat open and with video; its buttons do what they say; and alone, your own face is drawn and moves with
/// your own voice.
void main() {
  Finder button(String label) => find.byWidgetPredicate((w) => w is SpaceButton && w.label == label);
  Finder pressable(String label) => find.byWidgetPredicate((w) => w is GlacierPressable && w.semanticLabel == label);

  testWidgets('pictures: phone, computer, alone, chat, video, light and dark', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-phone', dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-computer', size: SpaceHarness.computer, dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call(people: 0, video: const {})), 'space-facetime-alone', dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call(people: 0, video: const {})), 'space-facetime-alone-computer', size: SpaceHarness.computer, dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call(people: 1, video: const {})), 'space-facetime-one', dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call(people: 6, video: const {'a', 'c', 'e'}, myVideo: true)), 'space-facetime-video', dark: dark);
      expect(tester.takeException(), isNull);
      await h.shoot(tester, FaceTimeCall(call: h.call(people: 6, video: const {'a', 'c', 'e'}, myVideo: true)), 'space-facetime-video-computer', size: SpaceHarness.computer, dark: dark);
      expect(tester.takeException(), isNull);

      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-chat-closed', dark: dark);
      await tester.tap(button('Chat'));
      await h.again(tester, 'space-facetime-chat', dark: dark);
      expect(find.text('Starting the movie in 10, hop in'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-chat-computer-closed', size: SpaceHarness.computer, dark: dark);
      await tester.tap(button('Chat'));
      await h.again(tester, 'space-facetime-chat-computer', dark: dark);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the buttons do what they say, on a phone and a computer', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
      final log = <String>[];
      await h.shoot(tester, FaceTimeCall(call: h.call(log: log)), 'space-facetime-buttons', size: size);
      for (final label in ['Mute', 'Video', 'Deafen', 'Invite', 'Leave']) {
        await tester.tap(button(label));
        await tester.pump();
      }
      for (final label in ['Devices', 'Settings', 'Minimise']) {
        await tester.tap(pressable(label).first);
        await tester.pump();
      }
      await tester.tap(pressable('Maya Chen').first);
      await tester.pump();
      expect(log, ['mute', 'video', 'deafen', 'invite', 'leave', 'devices', 'settings', 'minimize', 'person a']);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a locked mic cannot be unmuted, and the header says so', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, FaceTimeCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-facetime-locked');
    expect(tester.widget<SpaceButton>(button('Unmute')).onPressed, isNull);
    expect(find.text('Mic locked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alone, your own face is drawn and moves with your voice', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, FaceTimeCall(call: h.call(people: 0, video: const {}, log: log)), 'space-facetime-alone-check');
    expect(find.text('Waiting for others…'), findsOneWidget);
    final face = find.byType(RippleAvatar);
    expect(face, findsOneWidget);
    h.levels.value = const {'me': 0.5};
    await tester.pump();
    expect(tester.widget<RippleAvatar>(face).level, 0.5);
    expect(find.text('You\'re speaking'), findsOneWidget);
    h.levels.value = const {'me': 0.0};
    await tester.pump();
    expect(tester.widget<RippleAvatar>(face).level, 0.0);
    await tester.tap(find.text('Invite').first);
    expect(log, ['invite']);
    await tester.pumpWidget(const SizedBox());
  });
}
