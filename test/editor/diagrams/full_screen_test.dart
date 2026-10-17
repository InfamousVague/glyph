// A diagram full screen (lib/editor/diagrams/full_screen.dart; Matt, 2026-10-16: "add the ability to view things
// like gantt charts in fullscreen"): the button on a drawn diagram, the layer over the app with a picture of its
// own drawn wider than the note, fitted to the screen, zoomed by a pinch or a double tap, and closed by its close,
// Escape or the phone's back.
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/editor.dart';

import '../../support/render.dart';
import '../media/support.dart' show pumpNote;
import 'support.dart';

late HeldBridge bridge;

const String _gantt = 'gantt\n  dateFormat YYYY-MM-DD\n  section Tests\n  Anatomy scan :2026-12-14, 2027-01-18';

Future<void> open(WidgetTester tester) async {
  await pumpNote(tester, 'Before\n\n```mermaid\n$_gantt\n```\n\nAfter', more: <Extension>[drawnMermaid()]);
  await tester.pump();
  bridge.finish(0, block: const Size(390, 120), at: const Rect.fromLTWH(10, 10, 370, 100));
  await tester.pump();
  await tester.pump();
}

final Finder _button = find.byKey(const ValueKey<String>('diagram-full'));
final Finder _layer = find.byKey(const ValueKey<String>('diagram-layer'));
final Finder _fullPicture = find.byKey(const ValueKey<String>('diagram-full-picture'));

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    bridge = HeldBridge();
    diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
    rememberDiagramHeights = false;
  });

  testWidgets('a drawn diagram has a full-screen button, and an undrawn one none', (tester) async {
    await pumpNote(tester, 'Before\n\n```mermaid\n$_gantt\n```\n\nAfter', more: <Extension>[drawnMermaid()]);
    await tester.pump();
    expect(_button, findsNothing, reason: 'its words, while it is being drawn, have nothing to show larger');
    bridge.finish(0, block: const Size(390, 120), at: const Rect.fromLTWH(10, 10, 370, 100));
    await tester.pump();
    await tester.pump();
    expect(_button, findsOneWidget);
    expect(find.bySemanticsLabel('Full screen'), findsOneWidget);
  });

  testWidgets('opens over the app with the note\'s picture, asks for one at least 760 wide, and shows that fitted', (tester) async {
    await open(tester);
    await tester.tap(_button);
    await tester.pump();
    expect(_layer, findsOneWidget);
    expect(_fullPicture, findsOneWidget, reason: 'the note\'s picture, until the full-size one is made');
    expect(bridge.asked, hasLength(2));
    final wide = bridge.asked.last;
    // A screen 390 across: the page the full-screen picture is drawn on is the least, not the screen.
    expect((wide.room, wide.viewport, wide.code), (fullScreenLeast, fullScreenLeast, _gantt));
    bridge.finish(1, block: const Size(760, 300), at: const Rect.fromLTWH(16, 10, 728, 280));
    await tester.pump();
    await tester.pump();
    final shown = tester.getRect(_fullPicture);
    final screen = tester.getRect(_layer);
    // Fitted whole inside the screen, with its margin, and centred.
    expect(shown.width, lessThan(screen.width));
    expect(shown.left, greaterThan(screen.left));
    expect((shown.center.dx - screen.center.dx).abs(), lessThan(1));
    expect(shown.width / shown.height, closeTo(728 / 280, 0.01));
  });

  testWidgets('a double tap zooms in three times on the whole, and another goes back to the whole', (tester) async {
    await open(tester);
    await tester.tap(_button);
    await tester.pump();
    bridge.finish(1, block: const Size(760, 300), at: const Rect.fromLTWH(16, 10, 728, 280));
    await tester.pump();
    await tester.pump();
    final whole = tester.getRect(_fullPicture).width;
    final at = tester.getRect(_fullPicture).center;
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(tester.getRect(_fullPicture).width, closeTo(whole * 3, 1));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(tester.getRect(_fullPicture).width, closeTo(whole, 1));
  });

  testWidgets('closes on its close, on Escape and on the phone\'s back, and lets its picture go', (tester) async {
    await open(tester);
    await tester.tap(_button);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('diagram-close')));
    await tester.pumpAndSettle();
    expect(_layer, findsNothing);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_layer, findsNothing);

    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(backStack.goBack(), isTrue, reason: 'the layer takes the back before the note does');
    await tester.pumpAndSettle();
    expect(_layer, findsNothing);
  });
}
