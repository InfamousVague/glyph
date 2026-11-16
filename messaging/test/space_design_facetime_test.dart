import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
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
  // The faces ripple for ever, so pumpAndSettle never ends: a sheet's slide is done well inside half a second.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  bool chatOpen(WidgetTester tester) => tester.widget<SpaceButton>(button('Chat')).on;

  /// Draws [page] as SpaceHarness.shoot does, without keeping a picture: for the tests that try things, so their
  /// pictures don't repeat the ones already kept.
  Future<void> mount(WidgetTester tester, SpaceHarness h, Widget page, {Size size = SpaceHarness.phone}) async {
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
    final state = AppState()..setTheme('light');
    await tester.pumpWidget(AppScope(
      state: state,
      child: WidgetsApp(
        color: const Color(0xFF4F5BD5),
        debugShowCheckedModeBanner: false,
        pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
        builder: (context, child) => GlacierTheme(
          sheet: h.sheet,
          attrs: {'platform': 'mobile', 'theme': state.theme},
          typography: ghostTypography('noto'),
          child: InkOverrides(child: GlacierToastProvider(child: child!)),
        ),
        home: page,
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// [c] with its camera locked (its role may not turn video on).
  SpaceCall cameraLocked(SpaceCall c) => SpaceCall(
        channel: c.channel,
        people: c.people,
        levels: c.levels,
        changes: c.changes,
        room: c.room,
        videoLocked: true,
        onVideo: c.onVideo,
        onMute: c.onMute,
        onLeave: c.onLeave,
        chatBuilder: c.chatBuilder,
      );

  testWidgets('pictures: phone, computer, alone, chat, video, light and dark', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-phone', dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(button('Chat'));
      await h.again(tester, 'space-facetime-chat', dark: dark);
      expect(find.text('Starting the movie in 10, hop in'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await h.shoot(tester, FaceTimeCall(call: h.call()), 'space-facetime-computer', size: SpaceHarness.computer, dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(button('Chat'));
      await h.again(tester, 'space-facetime-chat-computer', dark: dark);
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
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the buttons do what they say, on a phone and a computer', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
      final log = <String>[];
      await mount(tester, h, FaceTimeCall(call: h.call(log: log)), size: size);
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
    await mount(tester, h, FaceTimeCall(call: h.call(people: 0, video: const {}, log: log)));
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

  testWidgets('a locked camera cannot be turned on', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
      await mount(tester, h, FaceTimeCall(call: cameraLocked(h.call())), size: size);
      expect(tester.widget<SpaceButton>(button('Video')).onPressed, isNull);
      await mount(tester, h, FaceTimeCall(call: h.call()), size: size);
      expect(tester.widget<SpaceButton>(button('Video')).onPressed, isNotNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on a phone the chat closes from its scrim and its close button; on a computer from its close button', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    await mount(tester, h, FaceTimeCall(call: h.call()));
    expect(chatOpen(tester), isFalse);
    await tester.tap(button('Chat'));
    await settle(tester);
    expect(chatOpen(tester), isTrue);
    // The scrim, above the sheet.
    await tester.tapAt(const Offset(206, 120));
    await settle(tester);
    expect(chatOpen(tester), isFalse);
    await tester.tap(button('Chat'));
    await settle(tester);
    await tester.tap(pressable('Close chat'));
    await settle(tester);
    expect(chatOpen(tester), isFalse);

    await mount(tester, h, FaceTimeCall(call: h.call()), size: SpaceHarness.computer);
    await tester.tap(button('Chat'));
    await settle(tester);
    expect(chatOpen(tester), isTrue);
    await tester.tap(pressable('Close chat'));
    await settle(tester);
    expect(chatOpen(tester), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
