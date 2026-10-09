import 'package:flutter/foundation.dart';
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
}
