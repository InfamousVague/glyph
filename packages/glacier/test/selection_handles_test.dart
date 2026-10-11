import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

/// The selection's handles (`GlacierTextSelectionControls`): the kit's drop everywhere but an iPhone, where they
/// are the phone's own shapes, a bar the line's height with a knob, in the colour the control is given.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const ink = Color(0xFF123456);

  Future<void> pumpHandle(WidgetTester tester, TextSelectionHandleType type) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Builder(builder: (context) => GlacierTextSelectionControls(color: ink).buildHandle(context, type, 24))),
        ),
      );

  testWidgets('an iPhone’s are the phone’s own shapes, in the colour given, and a caret has none', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controls = GlacierTextSelectionControls(color: ink);
    // A bar the line's height and more, where the kit's drop is a square.
    expect(controls.getHandleSize(24).height, greaterThan(24));
    for (final type in [TextSelectionHandleType.left, TextSelectionHandleType.right]) {
      await pumpHandle(tester, type);
      expect(tester.takeException(), isNull);
      final theme = tester.widget<CupertinoTheme>(find.byType(CupertinoTheme));
      expect(theme.data.selectionHandleColor, ink);
      expect(find.byType(CustomPaint), findsWidgets);
    }
    // Under a caret the phone draws nothing.
    await pumpHandle(tester, TextSelectionHandleType.collapsed);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Center)).isEmpty, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('anywhere else they are the kit’s own drop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controls = GlacierTextSelectionControls(color: ink);
    expect(controls.getHandleSize(24), const Size(22, 22));
    await pumpHandle(tester, TextSelectionHandleType.left);
    expect(find.byType(CupertinoTheme), findsNothing);
    expect(find.byType(CustomPaint), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
