import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/ui/ripple_avatar.dart';
import 'package:ghost_messaging/ui/space_designs/stage.dart';

import 'support/space_call_harness.dart';

/// The audio stage design (lib/ui/space_designs/stage.dart), after Clubhouse and X Spaces: its pictures on a phone and
/// a computer, light and dark, and its buttons doing what they say.
void main() {
  testWidgets('stage: pictures', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    for (final dark in [false, true]) {
      await h.shoot(tester, StageCall(call: h.call()), 'space-stage-computer', size: SpaceHarness.computer, dark: dark);
      await h.shoot(tester, StageCall(call: h.call(people: 0, video: const {})), 'space-stage-alone', dark: dark);
      await h.shoot(tester, StageCall(call: h.call(people: 0, video: const {})), 'space-stage-alone-computer', size: SpaceHarness.computer, dark: dark);
      await h.shoot(tester, StageCall(call: h.call(people: 6, video: const {'a', 'c', 'e'}, myVideo: true)), 'space-stage-video', dark: dark);
      await h.shoot(tester, StageCall(call: h.call()), 'space-stage-phone', dark: dark);
      await tester.tap(find.bySemanticsLabel('Comments'));
      await h.again(tester, 'space-stage-chat', dark: dark);
      expect(find.text('Saving you a seat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stage: the buttons do what they say', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    final log = <String>[];
    await h.shoot(tester, StageCall(call: h.call(log: log)), 'space-stage-buttons');
    for (final label in ['Mute', 'Camera', 'Invite', 'Deafen', 'Devices', 'Settings', 'Minimise', 'Leave quietly']) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
    }
    await tester.tap(find.text('Maya Chen'));
    await tester.pump();
    expect(log, ['mute', 'video', 'invite', 'deafen', 'devices', 'settings', 'minimize', 'leave', 'person a']);

    // Muted by a moderator: the mic says so and does nothing.
    log.clear();
    await h.shoot(tester, StageCall(call: h.call(log: log, muted: true, micLocked: true)), 'space-stage-buttons');
    expect(find.text('Muted by a moderator'), findsOneWidget);
    await tester.tap(find.text('Muted by a moderator'));
    await tester.pump();
    expect(log, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stage: on a 412-wide phone every label in the header and the bar shows whole', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    await h.shoot(tester, StageCall(call: h.call()), 'space-stage-buttons');
    for (final words in ['Leave quietly', 'Minimise', 'Comments', 'Invite', 'Mute', 'Camera', 'Deafen', 'Devices', 'Settings']) {
      final text = find.text(words);
      expect(text, findsOneWidget, reason: words);
      expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$words is cut off');
      // Not squeezed onto two lines either: one line tall.
      final line = tester.renderObject<RenderParagraph>(text).getFullHeightForCaret(const TextPosition(offset: 0));
      expect(tester.getSize(text).height, lessThan(line * 1.5), reason: '$words wraps');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stage: alone, your own face is on stage and moves with your voice', (tester) async {
    final h = await SpaceHarness.load(tester);
    addTearDown(tester.view.reset);
    await h.shoot(tester, StageCall(call: h.call(people: 0, video: const {})), 'space-stage-buttons');
    expect(find.text('You'), findsOneWidget);
    expect(find.textContaining('just you'), findsOneWidget);
    RippleAvatar face() => tester.widget<RippleAvatar>(find.byType(RippleAvatar));
    h.levels.value = const {'me': 0.0};
    await tester.pump();
    expect(face().level, 0.0);
    h.levels.value = const {'me': 0.5};
    await tester.pump();
    expect(face().level, 0.5);
    await tester.pumpWidget(const SizedBox());
  });
}
