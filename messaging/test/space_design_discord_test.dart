import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/space_designs/discord.dart';

import 'support/space_call_harness.dart';

/// The voice channel design, modelled on Discord (lib/ui/space_designs/discord.dart): its pictures on a phone and a
/// computer, alone, with the chat open and with video; its buttons doing what they say; your own tile drawn and lit
/// when alone. Matt, 2026-11-16: "give me 6 alternate designs for the calling chat and video screens for spaces".
void main() {
  testWidgets('pictures: phone, computer, alone, chat, video, light and dark', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await h.shoot(tester, DiscordCall(call: h.call()), 'space-discord-phone', dark: dark);
      await h.shoot(tester, DiscordCall(call: h.call()), 'space-discord-computer', size: SpaceHarness.computer, dark: dark);
      await h.shoot(tester, DiscordCall(call: h.call(people: 0, video: const {})), 'space-discord-alone', dark: dark);
      await h.shoot(tester, DiscordCall(call: h.call(people: 0, video: const {})), 'space-discord-alone-computer', size: SpaceHarness.computer, dark: dark);
      await h.shoot(tester, DiscordCall(call: h.call(people: 3, video: const {'a', 'c'}, myVideo: true, muted: true)), 'space-discord-video', size: SpaceHarness.computer, dark: dark);
      final semantics = tester.ensureSemantics();
      await h.shoot(tester, DiscordCall(call: h.call()), 'space-discord-chat', dark: dark);
      await tester.tap(find.bySemanticsLabel('Chat'));
      await h.again(tester, 'space-discord-chat', dark: dark);
      expect(find.text('Text in voice'), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the buttons say what they do', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
      final log = <String>[];
      await h.shoot(tester, DiscordCall(call: h.call(log: log)), 'space-discord-buttons', size: size);
      for (final label in ['Mute', 'Video', 'Deafen', 'Devices', 'Leave', 'Invite', 'Settings', 'Minimise']) {
        await tester.tap(find.bySemanticsLabel(label));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('discord-tile-a')));
      await tester.pump();
      expect(log, ['mute', 'video', 'deafen', 'devices', 'leave', 'invite', 'settings', 'minimize', 'person a']);
    }

    // A locked mic is shown as locked and cannot be pressed.
    final log = <String>[];
    await h.shoot(tester, DiscordCall(call: h.call(log: log, micLocked: true, muted: true)), 'space-discord-buttons');
    expect(find.text('Mic locked'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Mic locked').first, warnIfMissed: false);
    expect(log, isEmpty);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alone, your own tile is drawn and lights green as you talk', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, DiscordCall(call: h.call(people: 0, video: const {}, log: log)), 'space-discord-buttons');
    expect(find.byKey(const ValueKey('discord-tile-me')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Waiting for others to join'), findsOneWidget);

    Color? outline() {
      final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byKey(const ValueKey('discord-tile-me')), matching: find.byType(AnimatedContainer)));
      return ((box.decoration! as BoxDecoration).border! as Border).top.color;
    }

    h.levels.value = const {'me': 0.5};
    await tester.pump(const Duration(milliseconds: 200));
    expect(outline(), const Color(0xFF23A55A));
    h.levels.value = const {'me': 0.0};
    await tester.pump(const Duration(milliseconds: 200));
    expect(outline(), isNot(const Color(0xFF23A55A)));

    await tester.tap(find.text('Invite friends'));
    expect(log, ['invite']);
    await tester.pumpWidget(const SizedBox());
  });
}
