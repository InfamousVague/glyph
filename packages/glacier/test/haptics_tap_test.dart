// The tap tick is given for a tap and not for the start of a scroll: the app's own rule
// (tauri/src/app/core/haptics.ts `installTapHaptics`: a tap is only a tap in hindsight).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

void main() {
  Future<List<HapticKind>> pump(WidgetTester tester) async {
    final fired = <HapticKind>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: HapticsProvider(
        enabled: true,
        impl: ([kind = HapticKind.light]) => fired.add(kind),
        child: ListView(children: [
          for (var i = 0; i < 30; i += 1) HapticTarget(child: SizedBox(height: 80, child: Text('row $i'))),
        ]),
      ),
    ));
    return fired;
  }

  testWidgets('a finger that lifts where it landed ticks once, as it lifts', (tester) async {
    final fired = await pump(tester);
    final gesture = await tester.startGesture(const Offset(100, 200));
    expect(fired, isEmpty, reason: 'nothing at touch-down');
    await gesture.up();
    expect(fired, [HapticKind.light]);
  });

  testWidgets('a scroll begun on a row ticks nothing', (tester) async {
    final fired = await pump(tester);
    await tester.drag(find.text('row 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(fired, isEmpty);
  });

  testWidgets('a press held past seven tenths of a second is not a tap', (tester) async {
    final fired = await pump(tester);
    final gesture = await tester.startGesture(const Offset(100, 200));
    await tester.pump(const Duration(milliseconds: 900));
    await gesture.up(timeStamp: const Duration(milliseconds: 900));
    expect(fired, isEmpty);
  });
}
