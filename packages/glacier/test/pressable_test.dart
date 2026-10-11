import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

import 'support/harness.dart';

void main() {
  Future<int> pressesAfter(WidgetTester tester, Duration held, {TargetPlatform platform = TargetPlatform.android}) async {
    debugDefaultTargetPlatformOverride = platform;
    var presses = 0;
    await pumpKit(tester, GlacierPressable(onPressed: () => presses++, builder: (context, _) => const SizedBox(width: 80, height: 40)));
    final finger = await tester.startGesture(tester.getCenter(find.byType(GlacierPressable)));
    await tester.pump(held);
    await finger.up();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    return presses;
  }

  testWidgets('a tap presses', (tester) async {
    expect(await pressesAfter(tester, const Duration(milliseconds: 120)), 1);
  });

  testWidgets('a finger held on a phone is the browser\'s long press, and presses nothing', (tester) async {
    // On Ghost.md's page a 0.9 s hold on a button opens nothing: the WebView asks for a context menu and no click
    // follows.
    expect(await pressesAfter(tester, const Duration(milliseconds: 900)), 0);
  });

  testWidgets('a mouse button held on a desktop is still a click', (tester) async {
    expect(await pressesAfter(tester, const Duration(milliseconds: 900), platform: TargetPlatform.macOS), 1);
  });

  testWidgets('a mouse over it on a phone is its hover, though no key has been pressed', (tester) async {
    // A phone starts in the touch highlight mode, where the framework's own hover highlight says nothing: a mouse in
    // a folding phone's desktop mode lit no button until a key had been pressed.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final said = <bool>[];
    var hovered = false;
    await pumpKit(
      tester,
      Center(
        child: GlacierPressable(
          onPressed: () {},
          onHover: said.add,
          builder: (context, state) {
            hovered = state.hovered;
            return const SizedBox(width: 80, height: 40);
          },
        ),
      ),
    );
    expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(GlacierPressable)));
    await tester.pump();
    expect(hovered, isTrue);
    expect(said, [true]);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(hovered, isFalse);
    expect(said, [true, false]);
    // A finger is no hover.
    final finger = await tester.startGesture(tester.getCenter(find.byType(GlacierPressable)));
    await tester.pump();
    expect(hovered, isFalse);
    await finger.up();
    await mouse.removePointer();
    debugDefaultTargetPlatformOverride = null;
  });
}
