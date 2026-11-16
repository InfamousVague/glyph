import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/space_designs/telegram.dart';

import 'support/space_call_harness.dart';

/// The Telegram-like voice chat (lib/ui/space_designs/telegram.dart): drawn on a phone and a computer, full, alone,
/// with the chat open and with video; its buttons do what they say; your own face is there and moving when alone.
void main() {
  Future<void> both(WidgetTester tester, SpaceHarness h, Widget Function() page, String name, {Size size = SpaceHarness.phone}) async {
    for (final dark in [false, true]) {
      await h.shoot(tester, page(), name, size: size, dark: dark);
      expect(tester.takeException(), isNull, reason: '$name dark: $dark');
    }
  }

  testWidgets('pictures: phone, computer, alone, chat, video', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await both(tester, h, () => TelegramCall(call: h.call()), 'space-telegram-phone');
    await both(tester, h, () => TelegramCall(call: h.call()), 'space-telegram-computer', size: SpaceHarness.computer);
    await both(tester, h, () => TelegramCall(call: h.call(people: 0, video: const {})), 'space-telegram-alone');
    await both(tester, h, () => TelegramCall(call: h.call(people: 0, video: const {})), 'space-telegram-alone-computer', size: SpaceHarness.computer);
    await both(tester, h, () => TelegramCall(call: h.call(people: 5, video: const {'a', 'c', 'd'}, myVideo: true)), 'space-telegram-video');
    for (final dark in [false, true]) {
      await h.shoot(tester, TelegramCall(call: h.call()), 'space-telegram-chat-closed', dark: dark);
      await tester.tap(find.bySemanticsLabel('Chat'));
      await h.again(tester, 'space-telegram-chat', dark: dark);
      expect(find.text('Saving you a seat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('the buttons write what they say', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, TelegramCall(call: h.call(log: log)), 'space-telegram-buttons');
    Future<void> tap(String label) async {
      await tester.tap(find.bySemanticsLabel(label).first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tap('Mute');
    await tap('Video');
    await tap('Deafen');
    await tap('Leave');
    await tap('Minimise');
    await tap('Invite members');
    await tap('Maya Chen');
    await tap('More: invite, devices, settings, leave');
    await tap('Settings');
    await tap('More: invite, devices, settings, leave');
    await tap('Devices');
    await tap('More: invite, devices, settings, leave');
    await tap('Invite');
    expect(log, ['mute', 'video', 'deafen', 'leave', 'minimize', 'invite', 'person a', 'settings', 'devices', 'invite']);

    // Held, a person opens too.
    log.clear();
    await tester.longPress(find.bySemanticsLabel('Sam Ortiz').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(log, ['person b']);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a moderator\'s mute disables the microphone and says why', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, TelegramCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-telegram-locked');
    expect(find.text('Muted by a moderator'), findsOneWidget);
    await tester.tap(find.text('Muted by a moderator'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(log, isEmpty);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('deafened, the big button undeafens rather than muting you', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, TelegramCall(call: h.call(log: log, deafened: true)), 'space-telegram-deafened');
    expect(find.text('Undeafen'), findsWidgets);
    expect(find.text('Tap to listen and speak'), findsOneWidget);
    expect(find.text('Unmute'), findsNothing);
    await tester.tap(find.text('Tap to listen and speak'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(log, ['deafen']);
    // The words a screen reader hears are the ones on the button.
    expect(find.bySemanticsLabel('Undeafen'), findsNWidgets(2));
    expect(find.bySemanticsLabel('Mute'), findsNothing);

    // Muted as well, undeafening brings back hearing only, and says so.
    await h.shoot(tester, TelegramCall(call: h.call(log: log, deafened: true, muted: true)), 'space-telegram-deafened-muted');
    expect(find.text('Tap to listen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('alone, your own face is drawn and its blob follows your voice', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await h.shoot(tester, TelegramCall(call: h.call(people: 0, video: const {})), 'space-telegram-alone-check');
    expect(find.byKey(const ValueKey('tg-face-me')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('speaking'), findsOneWidget);
    expect(find.text('Waiting for others to join'), findsOneWidget);
    expect(find.text('You\'re live'), findsOneWidget);
    h.levels.value = const {'me': 0};
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('listening'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
