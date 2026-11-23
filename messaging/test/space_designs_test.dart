import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/space_designs/space_design.dart';
import 'package:ghost_messaging/ui/screen_share.dart';
import 'package:ghost_messaging/voice/voice.dart' show ScreenSource;

import 'support/space_call_harness.dart';

/// Every space call design (lib/ui/space_designs) draws without fault on a phone and on a computer, in a full call, in
/// a call alone (this device's own level still moving its face), and in a group's channel with no chat; and the
/// switch in Settings › Developer names all seven. Each design's own test (space_design_<name>_test.dart) looks
/// closer. Matt, 2026-11-16: "give me 6 alternate designs for the calling chat and video screens for spaces".
void main() {
  for (final d in SpaceDesign.values.where((d) => d != SpaceDesign.standard)) {
    testWidgets('${d.name}: draws on a phone and a computer, full, alone, and without a chat', (tester) async {
      final h = await SpaceHarness.load(tester);
      addTearDown(tester.view.reset);
      for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
        await h.shoot(tester, d.page(h.call()), 'smoke-${d.name}', size: size);
        expect(tester.takeException(), isNull);
        await h.shoot(tester, d.page(h.call(people: 0, video: const {})), 'smoke-${d.name}-alone', size: size);
        expect(tester.takeException(), isNull);
        await h.shoot(tester, d.page(h.call(withChat: false)), 'smoke-${d.name}-nochat', size: size);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  // GMFB-27: the designs without a menu for the plugins (Discord, FaceTime, Stage) have a button of their own for
  // sharing the screen; the others have it first in their menu (SpaceCall.live puts it in the extras).
  for (final d in [SpaceDesign.discord, SpaceDesign.facetime, SpaceDesign.stage]) {
    testWidgets('${d.name}: a button shares the screen, and says Stop sharing while it does', (tester) async {
      final h = await SpaceHarness.load(tester);
      addTearDown(tester.view.reset);
      for (final size in [SpaceHarness.phone, SpaceHarness.computer]) {
        final log = <String>[];
        await h.shoot(tester, d.page(h.call(canShare: true, log: log)), 'share-${d.name}', size: size);
        expect(tester.takeException(), isNull);
        final share = find.bySemanticsLabel(RegExp(r'^(Share screen|Screen)\b'));
        expect(share, findsOneWidget, reason: '${d.name} at $size');
        await tester.tap(share);
        await tester.pump();
        expect(log, contains('screen'));
        await h.shoot(tester, d.page(h.call(sharing: true)), 'share-${d.name}-on', size: size);
        expect(find.bySemanticsLabel(RegExp(r'^Stop sharing')), findsOneWidget);
        // And none where this device can't share.
        await h.shoot(tester, d.page(h.call()), 'share-${d.name}-none', size: size);
        expect(find.bySemanticsLabel(RegExp(r'^(Share screen|Screen|Stop sharing)\b')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the computer\'s choice of screen or window: screens, then windows, and a press picks one', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    String? picked;
    await h.shoot(
      tester,
      // As wide as the sheet it opens in (30rem).
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 480, child: ScreenPicker(
          sources: const [
            ScreenSource(id: 'screen:0', name: 'Entire screen', window: false),
            ScreenSource(id: 'window:1', name: 'Notes', window: true),
            ScreenSource(id: 'window:2', name: 'Safari', window: true),
          ],
          onPick: (id) => picked = id,
        )),
      ),
      'share-picker',
      size: SpaceHarness.computer,
    );
    expect(find.text('Screens'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Entire screen')).dy, lessThan(tester.getTopLeft(find.text('Notes')).dy));
    await tester.tap(find.text('Notes'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 'window:1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('someone\'s screen, large: their name over it, waiting until it arrives, and Back to call', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    var back = 0;
    await h.shoot(tester, ScreenStage(name: 'Maya Chen', stream: null, onBack: () => back++), 'share-stage', size: SpaceHarness.phone);
    expect(find.text('Maya Chen\'s screen'), findsOneWidget);
    expect(find.text('Waiting for Maya Chen\'s screen…'), findsOneWidget);
    await tester.tap(find.text('Back to call'));
    expect(back, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('each design names the app it is modelled on, says what it looks like, and has a picture', () {
    expect(SpaceDesign.values.length, 7);
    for (final d in SpaceDesign.values) {
      expect(d.label, isNotEmpty);
      expect(d.after, isNotEmpty);
      expect(d.description.length, greaterThan(20));
    }
    expect(SpaceDesign.named('zoom'), SpaceDesign.zoom);
    expect(SpaceDesign.named(''), isNull);
  });
}
