import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/shell/pop_menu.dart';
import 'package:glacier/glacier.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

/// `editor/PopMenu.test.tsx`: where the app's menu hangs, what closes it, the opened Fold's crease and the rows under
/// a name. What the kit's own menu does - its placing, its keys - is the kit's to test.
void main() {
  setUpAll(loadAppFonts);

  /// A menu hung from a box at [at], owned as the tab row owns one: mounted while open, taken down on dismiss.
  Future<({List<String> said, GlobalKey anchor})> hang(
    WidgetTester tester, {
    Offset at = const Offset(40, 100),
    Size size = const Size(390, 844),
    PopReach reach = PopReach.either,
    Placement placement = Placement.bottomStart,
    bool coarse = true,
    BackStack? stack,
    bool sub = false,
  }) async {
    final said = <String>[];
    final anchor = GlobalKey();
    var open = true;
    await pumpApp(
      tester,
      size: size,
      home: BackScope(
        stack: stack,
        child: StatefulBuilder(
          builder: (context, setState) => Stack(
            children: [
              Positioned(left: at.dx, top: at.dy, child: SizedBox(key: anchor, width: 24, height: 24)),
              if (open)
                PopMenu(
                  anchor: GlacierAnchor.key(anchor),
                  placement: placement,
                  reach: reach,
                  coarse: coarse,
                  ariaLabel: 'Card',
                  onDismiss: () {
                    said.add('dismissed');
                    setState(() => open = false);
                  },
                  children: [
                    GlacierMenuItem(onSelect: () => said.add('rename'), child: const Text('Rename')),
                    if (sub)
                      ...PopSub.rows(context, label: 'Colour', coarse: coarse, children: [
                        GlacierMenuItem(ariaLabel: 'Colour: Ink', onSelect: () => said.add('ink'), child: const Text('Ink')),
                        GlacierMenuItem(ariaLabel: 'Colour: Sea', onSelect: () => said.add('sea'), child: const Text('Sea')),
                      ]),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return (said: said, anchor: anchor);
  }

  Rect panel(WidgetTester tester) {
    final row = tester.getRect(find.ancestor(of: find.text('Rename'), matching: find.byType(GlacierMenuItem)));
    final t = tester.element(find.text('Rename')).tokens;
    final inset = t.space(1) + t.len('glacier-hairline');
    return Rect.fromLTWH(row.left - inset, row.top - inset, row.width + 2 * inset, 0);
  }

  group('where it hangs', () {
    testWidgets('hangs from the element it is given, under it, named for a screen reader', (tester) async {
      await hang(tester);
      expect(find.bySemanticsLabel('Card'), findsOneWidget);
      expect(panel(tester).left, 40);
      // The element's foot, and the kit's 8px.
      expect(panel(tester).top, 100 + 24 + 8);
      await away(tester);
    });

    testWidgets('wears the room it reaches for: down from the top bar, or either way from the page', (tester) async {
      await hang(tester);
      final t = tester.element(find.text('Rename')).tokens;
      // `.pop.down`: the room under the bar, less the kit's offset and its edge.
      expect(PopMenu.styleOf(t, PopReach.down, coarse: true).maxHeight, closeTo(844 - t.len('app-inset-top') - t.len('app-tabs') - 16, 0.01));
      // `.pop.either`: half the room under the status bar.
      expect(PopMenu.styleOf(t, PopReach.either, coarse: true).maxHeight, closeTo((844 - t.len('app-inset-top')) / 2 - 32, 0.01));
      // Under a finger, a thumb's height in the + list's type; a mouse keeps the kit's rows.
      final finger = PopMenu.styleOf(t, PopReach.down, coarse: true).item!, mouse = PopMenu.styleOf(t, PopReach.down, coarse: false).item!;
      expect(finger.minHeight, 44);
      expect(finger.textStyle?.fontSize, t.fontSize('md'));
      expect(finger.textStyle?.fontWeight, t.weight('medium'));
      expect(mouse.minHeight, isNull);
      expect(mouse.textStyle, isNull);
      // The icons follow the row's type, for a finger and a mouse alike.
      expect(finger.iconSize, closeTo(1.15 * t.fontSize('md'), 1e-9));
      expect(mouse.iconSize, closeTo(1.15 * t.fontSize('sm'), 1e-9));
      // On the opened Fold, half the window less the edge and the crease's gap.
      expect(PopMenu.styleOf(t, PopReach.down, coarse: true, creased: true).maxWidth, lessThanOrEqualTo(390 / 2 - 24));
      await away(tester);
    });
  });

  group('what closes it', () {
    testWidgets('the back gesture, taken, with the owner told once', (tester) async {
      final stack = BackStack();
      var under = 0;
      stack.onBack(() {
        under += 1;
        return true;
      });
      final menu = await hang(tester, stack: stack);
      expect(stack.depth, 2);
      expect(stack.goBack(), isTrue);
      // A microtask later, and not before.
      expect(menu.said, isEmpty);
      await tester.pump();
      expect(menu.said, ['dismissed']);
      expect(find.text('Rename'), findsNothing);
      // The gesture went no further down the stack, and the menu's handler went with it.
      expect(under, 0);
      expect(stack.depth, 1);
      await away(tester);
    });

    testWidgets('the system’s own back, once', (tester) async {
      final menu = await hang(tester, stack: BackStack());
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(menu.said, ['dismissed']);
      await away(tester);
    });

    testWidgets('a press anywhere else, heard once; not a press in it', (tester) async {
      final menu = await hang(tester);
      await tester.tap(find.text('Rename'));
      await tester.pump();
      // A row chosen closes it too, after its doing.
      expect(menu.said, ['rename', 'dismissed']);
      await away(tester);
      final again = await hang(tester);
      await tester.tapAt(const Offset(300, 700));
      await tester.pump();
      expect(again.said, ['dismissed']);
      await away(tester);
    });

    testWidgets('its element leaving the screen', (tester) async {
      // Off the window's foot: gone with what it hangs from, a frame after it is looked for.
      final menu = await hang(tester, at: const Offset(40, 900));
      await tester.pump();
      expect(menu.said, ['dismissed']);
      await away(tester);
    });
  });

  group('the opened Fold’s crease', () {
    const widest = 352.0;
    ({Placement placement, bool creased}) at(double x, Placement asked, {double window = 880, bool coarse = true}) =>
        offTheCrease(Rect.fromLTWH(x, 100, 24, 24), asked, window: window, widestPanel: widest, coarse: coarse);

    test('hangs a menu from an element just left of the crease by its end, on the left', () {
      expect(at(396, Placement.bottomStart), (placement: Placement.bottomEnd, creased: true));
    });

    test('hangs one from just right of it by its start, on the right', () {
      expect(at(460, Placement.bottomEnd), (placement: Placement.bottomStart, creased: true));
    });

    test('leaves one alone that fits its side as asked', () {
      expect(at(40, Placement.bottomStart), (placement: Placement.bottomStart, creased: true));
      expect(at(800, Placement.bottomEnd), (placement: Placement.bottomEnd, creased: true));
      // One that hangs beside its element is left as asked, on its side.
      expect(at(396, Placement.rightStart), (placement: Placement.rightStart, creased: true));
    });

    test('is no matter on a phone, or under a mouse', () {
      expect(at(100, Placement.bottomStart, window: 412), (placement: Placement.bottomStart, creased: false));
      expect(at(396, Placement.bottomStart, coarse: false), (placement: Placement.bottomStart, creased: false));
      expect(offTheCrease(null, Placement.bottomStart, window: 880, widestPanel: widest, coarse: true).creased, isFalse);
    });

    testWidgets('keeps the panel on its element’s side of the crease when it opens', (tester) async {
      await hang(tester, at: const Offset(396, 100), size: const Size(880, 790));
      // By its end, on the left: the panel's right edge is the element's.
      final row = tester.getRect(find.ancestor(of: find.text('Rename'), matching: find.byType(GlacierMenuItem)));
      expect(row.right, lessThanOrEqualTo(420));
      expect(row.left, lessThan(396));
      await away(tester);
    });
  });

  group('rows under a name', () {
    testWidgets('are listed in place, under their name, under a finger', (tester) async {
      final menu = await hang(tester, sub: true);
      expect(find.text('COLOUR'), findsOneWidget);
      expect(find.bySemanticsLabel('Colour: Ink'), findsOneWidget);
      await tester.tap(find.text('Sea'));
      await tester.pump();
      expect(menu.said, ['sea', 'dismissed']);
      await away(tester);
    });

    testWidgets('fly out for a mouse on a window with room for a flyout either side of the menu', (tester) async {
      await hang(tester, sub: true, coarse: false, size: const Size(1280, 900));
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Ink'), findsNothing);
      await tester.tap(find.text('Colour'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Ink'), findsOneWidget);
      expect(find.text('Sea'), findsOneWidget);
      await away(tester);
    });

    testWidgets('are in place for a mouse on a window without that room, and under a finger on the opened Fold too', (tester) async {
      await hang(tester, sub: true, coarse: false, size: const Size(1000, 900));
      expect(find.text('Ink'), findsOneWidget);
      final t = tester.element(find.text('Rename')).tokens;
      // 1076px at the app's own interface size.
      expect(flyoutFits(t, 1076, coarse: false), isTrue);
      expect(flyoutFits(t, 1075, coarse: false), isFalse);
      expect(flyoutFits(t, 1280, coarse: true), isFalse);
      await away(tester);
      await hang(tester, sub: true, size: const Size(880, 790));
      expect(find.text('Ink'), findsOneWidget);
      await away(tester);
    });
  });
}
