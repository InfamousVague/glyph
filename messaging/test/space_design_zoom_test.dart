import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/space_designs/space_design.dart';
import 'package:ghost_messaging/ui/space_designs/zoom.dart';

import 'support/space_call_harness.dart';

/// The Meeting design, modelled on Zoom (lib/ui/space_designs/zoom.dart): drawn on a phone and a computer, full and
/// alone, with the chat open and with video; its buttons do what they say; and alone your own face still moves with
/// your voice. Pictures in test/shots/space-zoom-*.png with --update-goldens.
void main() {
  Future<void> both(WidgetTester tester, SpaceHarness h, SpaceCall Function() call, String name, {Size size = SpaceHarness.phone, Future<void> Function()? then}) async {
    for (final dark in [false, true]) {
      await h.shoot(tester, ZoomCall(call: call()), name, size: size, dark: dark);
      if (then != null) {
        await then();
        await h.again(tester, name, dark: dark);
      }
      expect(tester.takeException(), isNull);
    }
  }

  testWidgets('draws on a phone and a computer, alone, with the chat, and with video', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await both(tester, h, () => h.call(), 'space-zoom-phone');
    await both(tester, h, () => h.call(), 'space-zoom-computer', size: SpaceHarness.computer, then: () async {
      await tester.tap(find.bySemanticsLabel('Chat'));
      await tester.pump();
    });
    await both(tester, h, () => h.call(people: 0, video: const {}), 'space-zoom-alone');
    await both(tester, h, () => h.call(people: 0, video: const {}), 'space-zoom-alone-computer', size: SpaceHarness.computer);
    await both(tester, h, () => h.call(), 'space-zoom-chat', then: () async {
      await tester.tap(find.bySemanticsLabel('Chat'));
      await tester.pump();
    });
    await both(tester, h, () => h.call(), 'space-zoom-people', size: SpaceHarness.computer, then: () async {
      await tester.tap(find.bySemanticsLabel('Participants'));
      await tester.pump();
    });
    await both(tester, h, () => h.call(video: const {'a', 'c', 'd'}, myVideo: true), 'space-zoom-video', size: SpaceHarness.computer);
    await both(tester, h, () => h.call(video: const {'a', 'c', 'd'}, myVideo: true, muted: true), 'space-zoom-video-phone');
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('the toolbar, the top bar and the tiles do what they say on a computer', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, ZoomCall(call: h.call(log: log)), 'space-zoom-check-buttons', size: SpaceHarness.computer);
    for (final label in ['Mute', 'Start video', 'Deafen', 'Invite', 'Settings', 'Leave', 'Minimise']) {
      await tester.tap(find.bySemanticsLabel(label).first);
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Devices').first);
    await tester.pump();
    expect(log, ['mute', 'video', 'deafen', 'invite', 'settings', 'leave', 'minimize', 'devices']);

    // Gallery to speaker view and back; the toolbar's words are visible.
    expect(find.text('Gallery view'), findsOneWidget);
    expect(find.text('Participants'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Speaker view'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Participants opens the side panel; pressing someone there opens them.
    log.clear();
    await tester.tap(find.bySemanticsLabel('Participants'));
    await tester.pump();
    expect(find.text('Maya Chen'), findsNWidgets(2)); // her tile and her row
    expect(find.text('Moderator'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Participant Maya Chen'));
    await tester.pump();
    expect(log, ['person a']);

    // Pressing a tile opens them too.
    log.clear();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Sam Ortiz, muted')));
    await tester.pump();
    expect(log, ['person b']);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a phone keeps the rest under More, and a locked mic cannot be unmuted', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, ZoomCall(call: h.call(log: log)), 'space-zoom-check-more');
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pump();
    for (final label in ['Deafen', 'Invite', 'Devices', 'Settings']) {
      await tester.tap(find.bySemanticsLabel(label).last);
      await tester.pump();
      if (label != 'Settings') {
        await tester.tap(find.bySemanticsLabel('More'));
        await tester.pump();
      }
    }
    await tester.tap(find.bySemanticsLabel('Leave'));
    await tester.pump();
    expect(log, ['deafen', 'invite', 'devices', 'settings', 'leave']);

    log.clear();
    await h.shoot(tester, ZoomCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-zoom-check-locked');
    await tester.tap(find.bySemanticsLabel('Unmute, not allowed here').first, warnIfMissed: false);
    await tester.pump();
    expect(log, isEmpty);

    // The participants panel says the same, with the same lock, and cannot unmute either.
    await h.shoot(tester, ZoomCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-zoom-check-locked-panel', size: SpaceHarness.computer);
    await tester.tap(find.bySemanticsLabel('Participants'));
    await tester.pump();
    expect(find.bySemanticsLabel('Unmute, not allowed here'), findsNWidgets(2)); // the toolbar's and the panel's
    expect(find.text('Unmute me'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Unmute, not allowed here').last, warnIfMissed: false);
    await tester.pump();
    expect(log, isEmpty);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a locked camera cannot be started, and says why', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    // The harness has no videoLocked, so the call is made again from its parts with the camera locked.
    SpaceCall locked() {
      final c = h.call(log: log);
      return SpaceCall(
        channel: c.channel,
        people: c.people,
        levels: c.levels,
        changes: c.changes,
        room: c.room,
        videoLocked: true,
        since: c.since,
        onMute: c.onMute,
        onVideo: c.onVideo,
        onLeave: c.onLeave,
        onMinimize: c.onMinimize,
        onPerson: c.onPerson,
        onInvite: c.onInvite,
        onDevices: c.onDevices,
        chatBuilder: c.chatBuilder,
      );
    }

    for (final size in [SpaceHarness.computer, SpaceHarness.phone]) {
      await both(tester, h, locked, size == SpaceHarness.phone ? 'space-zoom-video-locked-phone' : 'space-zoom-video-locked', size: size);
      expect(find.bySemanticsLabel('Start video, not allowed here'), findsOneWidget);
      expect(find.text('Start video'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Start video, not allowed here'), warnIfMissed: false);
      await tester.pump();
      expect(log, isEmpty);
      // The mic is not locked, so Mute still works.
      await tester.tap(find.bySemanticsLabel('Mute'));
      await tester.pump();
      expect(log, ['mute']);
      log.clear();
    }
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('fits ordinary computer windows, with and without the panel', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    // Each window size, with no panel, then Participants, then Chat open: nothing may overflow.
    for (final size in const [Size(720, 800), Size(760, 800), Size(800, 800), Size(900, 800), Size(1000, 800), Size(1024, 800), Size(1100, 800), Size(1280, 800)]) {
      // A name of its own each time, so each size starts afresh (with no panel open).
      await h.shoot(tester, ZoomCall(call: h.call()), 'space-zoom-check-size-${size.width.round()}', size: size);
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.tap(find.bySemanticsLabel('Participants'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size, participants');
      await tester.tap(find.bySemanticsLabel('Chat').first);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size, chat');
    }
    // A narrow window folds Invite, Deafen and Settings under More, which still does them.
    final log = <String>[];
    await h.shoot(tester, ZoomCall(call: h.call(log: log)), 'space-zoom-check-more-720', size: const Size(720, 800));
    expect(find.bySemanticsLabel('Invite'), findsNothing);
    await tester.tap(find.bySemanticsLabel('More'));
    await tester.pump();
    for (final label in ['Invite', 'Devices', 'Settings']) {
      await tester.tap(find.bySemanticsLabel(label).last);
      await tester.pump();
      if (label != 'Settings') {
        await tester.tap(find.bySemanticsLabel('More'));
        await tester.pump();
      }
    }
    expect(log, ['invite', 'devices', 'settings']);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('pictures of a small window, and of the panel over a mid-sized one', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await both(tester, h, () => h.call(), 'space-zoom-window-720', size: const Size(720, 800));
    await both(tester, h, () => h.call(), 'space-zoom-window-1000-people', size: const Size(1000, 800), then: () async {
      await tester.tap(find.bySemanticsLabel('Participants'));
      await tester.pump();
    });
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('alone, your own face is drawn and moves with your voice', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await h.shoot(tester, ZoomCall(call: h.call(people: 0, video: const {}, log: log)), 'space-zoom-check-alone');
    expect(find.text("You're the only one here"), findsOneWidget);
    expect(find.byType(SpaceFace), findsOneWidget);
    expect(find.text('Your mic is picking you up'), findsOneWidget);
    h.levels.value = const {'me': 0.0};
    await tester.pump();
    expect(find.text('Your mic is on'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Invite'));
    await tester.pump();
    expect(log, ['invite']);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });
}
