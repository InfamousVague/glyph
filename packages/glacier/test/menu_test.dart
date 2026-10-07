import 'dart:ui' show PointerDeviceKind, SemanticsRole;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/harness.dart';

/// GlacierMenu and its rows against organisms/Menu/Menu.tsx and the kit's own react/test/menu.test.tsx: where the
/// panels land, the keyboard's round of the rows, choosing, flyouts, what closes the stack, and what it all says to
/// a screen reader. The window is the harness's 390 x 844.
void main() {
  const window = Size(390, 844);
  final t = testTokens();
  final fast = t.duration('glacier-duration-fast');

  final trigger = find.byKey(const ValueKey('trigger'));

  /// Every panel that is up, the menu's own first and then each flyout in the order it opened.
  final panels = find.byType(GlacierAnchored);

  /// A panel as it is laid out: the presence, which is the one child its positioner places.
  Finder panel([int index = 0]) => find.descendant(of: panels.at(index), matching: find.byType(Transform)).first;

  /// The box of the row that shows [label].
  Finder row(String label) => find.ancestor(of: find.text(label), matching: find.byType(GlacierPressable)).first;

  FocusNode focusOf(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label)));

  /// The style [label] is drawn in.
  TextStyle typeOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.descendant(of: find.text(label), matching: find.byType(RichText))).text.style!;

  String? focused() {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    if (context == null) return node?.debugLabel;
    String? label;
    void visit(Element element) {
      if (label != null) return;
      final widget = element.widget;
      if (widget is Text) {
        label = widget.data;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return label ?? node?.debugLabel;
  }

  /// A menu hung from a 100 x 20 trigger [at] from the window's corner.
  Widget menu({
    Offset at = const Offset(100, 10),
    Placement placement = Placement.bottomStart,
    bool? open,
    bool defaultOpen = false,
    ValueChanged<bool>? onOpenChange,
    GlacierMenuStyle? style,
    required List<Widget> children,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: at.dx, top: at.dy),
      child: GlacierMenu(
        ariaLabel: 'Actions',
        placement: placement,
        open: open,
        defaultOpen: defaultOpen,
        onOpenChange: onOpenChange,
        style: style,
        trigger: (context, handle) => GlacierPressable(
          key: const ValueKey('trigger'),
          semanticLabel: 'Actions',
          onPressed: handle.toggle,
          builder: (context, state) => const SizedBox(width: 100, height: 20),
        ),
        children: children,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 20));

  Future<void> remount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, child);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  List<Widget> share() => const [
        GlacierMenuItem(child: Text('Rename')),
        GlacierMenuSub(
          label: Text('Share'),
          children: [
            GlacierMenuItem(child: Text('Email')),
            GlacierMenuItem(child: Text('Copy link')),
          ],
        ),
      ];

  group('placing', () {
    testWidgets('opens on press, anchored where the maths says, as wide as the kit\'s least', (tester) async {
      await pumpKit(tester, menu(children: const [GlacierMenuItem(child: Text('Rename')), GlacierMenuItem(child: Text('Delete'))]));
      expect(panels, findsNothing);
      await tester.tap(trigger);
      await tester.pump();
      expect(tester.getTopLeft(panel()), const Offset(100, 38)); // trigger left; trigger bottom 30 + offset 8
      expect(tester.getSize(panel()).width, 192); // min-width: 12rem

      await settle(tester);
      final expected = computeAnchoredPosition(trigger: tester.getRect(trigger), floating: tester.getSize(panel()), viewport: window);
      expect(tester.getTopLeft(panel()), expected.offset);
    });

    testWidgets('the panel and its rows are the stylesheet\'s sizes', (tester) async {
      await pumpKit(
        tester,
        menu(
          defaultOpen: true,
          children: const [
            GlacierMenuLabel(child: Text('Edit')),
            GlacierMenuItem(child: Text('Rename')),
            GlacierMenuSeparator(),
            GlacierMenuItem(danger: true, child: Text('Delete')),
          ],
        ),
      );
      await settle(tester);
      final hairline = t.len('glacier-hairline');
      final inset = t.space(1) + hairline; // padding inside the border
      final box = tester.getRect(panel());
      // a row: full width inside the padding, its line at --glacier-leading-sm and --glacier-space-2 above and below
      final rename = tester.getRect(row('Rename'));
      expect(rename.left, moreOrLessEquals(box.left + inset, epsilon: 0.01));
      expect(rename.right, moreOrLessEquals(box.right - inset, epsilon: 0.01));
      expect(rename.height, moreOrLessEquals(t.fontSize('sm') * t.len('glacier-leading-sm') + 2 * t.space(2), epsilon: 0.01));
      // the label starts --glacier-space-3 in
      expect(tester.getTopLeft(find.text('Rename')).dx, moreOrLessEquals(rename.left + t.space(3), epsilon: 0.01));
      expect(tester.getTopLeft(find.text('EDIT')).dx, moreOrLessEquals(box.left + inset + t.space(3), epsilon: 0.01));
      // the divider: a hairline, --glacier-space-2 in from each side, --glacier-space-1 and the 1px gap from each row
      final divider = tester.getRect(find.descendant(of: find.byType(GlacierMenuSeparator), matching: find.byType(ColoredBox)));
      expect(divider.height, hairline);
      expect(divider.left, moreOrLessEquals(box.left + inset + t.space(2), epsilon: 0.01));
      expect(divider.top, moreOrLessEquals(rename.bottom + 1 + t.space(1), epsilon: 0.01));
      expect(tester.getRect(row('Delete')).top, moreOrLessEquals(divider.bottom + t.space(1) + 1, epsilon: 0.01));
      // and the panel ends its padding below the last row
      expect(box.bottom, moreOrLessEquals(tester.getRect(row('Delete')).bottom + inset, epsilon: 0.01));
    });

    testWidgets('grows to its widest row, and no wider than the kit\'s most', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, at: Offset.zero, children: const [GlacierMenuItem(child: Text('A longer row name'))]));
      await settle(tester);
      // the test face is a square to the letter: 17 of them, the row's padding, and the panel's padding and border
      final natural = 17 * t.fontSize('sm') + 2 * t.space(3) + 2 * (t.space(1) + t.len('glacier-hairline'));
      expect(natural, inExclusiveRange(192, 352));
      expect(tester.getSize(panel()).width, moreOrLessEquals(natural, epsilon: 0.01));

      await remount(tester, menu(defaultOpen: true, at: Offset.zero, children: [GlacierMenuItem(child: Text('A row whose name runs on ' * 4))]));
      await settle(tester);
      expect(tester.getSize(panel()).width, 352); // max-width: min(22rem, 100vw - 2rem)
      expect(tester.getSize(find.textContaining('A row whose')).height, lessThan(t.fontSize('sm') * 2)); // one line, cut short
    });

    testWidgets('turns above a trigger at the foot of the window', (tester) async {
      await pumpKit(tester, menu(at: const Offset(100, 800), children: const [GlacierMenuItem(child: Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      final box = tester.getRect(panel());
      expect(box.top, (800 - 8 - box.height + 0.5).floorToDouble());
      expect(tester.widget<Transform>(panel()).alignment, Alignment.bottomCenter);
    });

    testWidgets('hangs from a point, as a context menu does, and from a widget elsewhere', (tester) async {
      await pumpKit(
        tester,
        GlacierMenu(anchor: GlacierAnchor.point(const Offset(120, 80)), open: true, children: const [GlacierMenuItem(child: Text('Copy'))]),
      );
      await settle(tester);
      expect(tester.getTopLeft(panel()), const Offset(120, 88));

      final card = GlobalKey();
      await remount(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Positioned(right: 20, top: 200, child: SizedBox(key: card, width: 32, height: 32)),
              GlacierMenu(anchor: GlacierAnchor.key(card), placement: Placement.bottomEnd, open: true, children: const [GlacierMenuItem(child: Text('Copy'))]),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(tester.getTopRight(panel()), const Offset(370, 240)); // the card's right edge; its bottom 232 + 8
    });
  });

  group('keyboard', () {
    testWidgets('the first row takes focus as it opens; the arrows wrap and skip a disabled row', (tester) async {
      await pumpKit(
        tester,
        menu(
          children: const [
            GlacierMenuItem(child: Text('Rename')),
            GlacierMenuItem(disabled: true, child: Text('Locked')),
            GlacierMenuItem(child: Text('Duplicate')),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      expect(focused(), 'Rename');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Duplicate'); // disabled 'Locked' is skipped
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Rename'); // wraps to the start
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'Duplicate'); // and back round the top
      await press(tester, LogicalKeyboardKey.home);
      expect(focused(), 'Rename');
      await press(tester, LogicalKeyboardKey.end);
      expect(focused(), 'Duplicate');
      // Left and Right are not the menu's, and do not carry the keyboard out of it
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'Duplicate');
    });

    testWidgets('a focused row wears the hover wash, and the others none', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, children: const [GlacierMenuItem(child: Text('Rename')), GlacierMenuItem(danger: true, child: Text('Delete'))]));
      await settle(tester);
      Color? wash(String label) =>
          (tester.widget<AnimatedContainer>(find.descendant(of: row(label), matching: find.byType(AnimatedContainer))).decoration! as BoxDecoration).color;
      // a key puts the page in the keyboard's way of showing focus
      await press(tester, LogicalKeyboardKey.home);
      await settle(tester);
      expect(wash('Rename'), t.color('glacier-hover'));
      expect(wash('Delete')!.a, 0);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await settle(tester);
      expect(wash('Rename')!.a, 0);
      expect(wash('Delete'), t.color('glacier-danger-soft'));
    });

    testWidgets('Enter chooses the focused row, runs onSelect and closes', (tester) async {
      final chosen = <String>[];
      final changes = <bool>[];
      await pumpKit(
        tester,
        menu(
          onOpenChange: changes.add,
          children: [
            GlacierMenuItem(onSelect: () => chosen.add('rename'), child: const Text('Rename')),
            GlacierMenuItem(onSelect: () => chosen.add('duplicate'), child: const Text('Duplicate')),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);
      expect(chosen, ['duplicate']);
      expect(changes, [true, false]);
      expect(panels, findsNothing);
      // and focus is back where it came from
      expect(Focus.of(tester.element(find.descendant(of: trigger, matching: find.byType(SizedBox)))).hasPrimaryFocus, isTrue);
    });

    testWidgets('Space chooses too', (tester) async {
      var chosen = 0;
      await pumpKit(tester, menu(children: [GlacierMenuItem(onSelect: () => chosen++, child: const Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.space);
      await settle(tester);
      expect(chosen, 1);
      expect(panels, findsNothing);
    });

    testWidgets('Escape closes and hands focus back to the trigger', (tester) async {
      await pumpKit(tester, menu(children: const [GlacierMenuItem(child: Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(panels, findsNothing);
      expect(Focus.of(tester.element(find.descendant(of: trigger, matching: find.byType(SizedBox)))).hasPrimaryFocus, isTrue);
    });

    testWidgets('Tab closes', (tester) async {
      await pumpKit(tester, menu(children: const [GlacierMenuItem(child: Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await settle(tester);
      expect(panels, findsNothing);
    });

    testWidgets('with every row disabled the panel takes focus, so Escape still closes', (tester) async {
      await pumpKit(
        tester,
        menu(children: const [GlacierMenuItem(disabled: true, child: Text('Archive')), GlacierMenuItem(disabled: true, child: Text('Delete'))]),
      );
      await tester.tap(trigger);
      await settle(tester);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'GlacierMenu panel');
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(panels, findsNothing);
    });
  });

  group('choosing and closing', () {
    testWidgets('a press on a row runs onSelect and closes', (tester) async {
      var chosen = 0;
      await pumpKit(tester, menu(children: [GlacierMenuItem(onSelect: () => chosen++, child: const Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      expect(chosen, 1);
      expect(panels, findsNothing);
    });

    testWidgets('a disabled row does nothing, by press or by key', (tester) async {
      var chosen = 0;
      final changes = <bool>[];
      await pumpKit(
        tester,
        menu(
          onOpenChange: changes.add,
          children: [
            GlacierMenuItem(disabled: true, onSelect: () => chosen++, child: const Text('Export')),
            const GlacierMenuItem(child: Text('Rename')),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      expect(focused(), 'Rename'); // focus went past it
      await tester.tap(find.text('Export'));
      await settle(tester);
      expect(chosen, 0);
      expect(changes, [true]); // and the press on it, being inside the menu, did not close it
      expect(panels, findsOneWidget);
      expect(focusOf(tester, 'Export').canRequestFocus, isFalse);
      // it is drawn at half strength
      expect(tester.widget<Opacity>(find.descendant(of: row('Export'), matching: find.byType(Opacity))).opacity, 0.5);
    });

    testWidgets('closes on an outside press, and a press on its own padding is not one', (tester) async {
      final changes = <bool>[];
      await pumpKit(tester, menu(onOpenChange: changes.add, children: const [GlacierMenuItem(child: Text('Rename'))]));
      await tester.tap(trigger);
      await settle(tester);
      await tester.tapAt(tester.getTopLeft(panel()) + const Offset(2, 2));
      await settle(tester);
      expect(panels, findsOneWidget);

      await tester.tapAt(const Offset(350, 700));
      await settle(tester);
      expect(panels, findsNothing);
      expect(changes, [true, false]);
    });

    testWidgets('the system\'s back closes it', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, children: const [GlacierMenuItem(child: Text('Rename'))]));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(panels, findsNothing);
    });

    testWidgets('controlled and held open, it reports each way of closing to its owner and stays', (tester) async {
      // Ghost.md's PopMenu: `<Menu open onOpenChange={(open) => { if (!open) dismiss(); }}>`, hung from an anchor
      final changes = <bool>[];
      final anchor = GlobalKey();
      await pumpKit(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Positioned(left: 100, top: 10, child: SizedBox(key: anchor, width: 100, height: 20)),
              GlacierMenu(
                anchor: GlacierAnchor.key(anchor),
                open: true,
                onOpenChange: changes.add,
                children: const [GlacierMenuItem(child: Text('Rename'))],
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(tester.getTopLeft(panel()), const Offset(100, 38));
      await tester.tap(find.text('Rename'));
      await settle(tester);
      expect(changes, [false]);
      await tester.tapAt(const Offset(350, 700));
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(changes, [false, false, false]);
      expect(panels, findsOneWidget);
    });
  });

  group('inside an app', () {
    // WidgetsApp brings what a bare tree lacks: a navigator and its route, and shortcuts of its own for the arrow
    // keys, Tab and Escape, which must not take those keys from an open menu.
    Future<GlobalKey<NavigatorState>> app(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        WidgetsApp(
          navigatorKey: navigator,
          color: const Color(0xFF000000),
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
          builder: (context, child) => GlacierTheme(sheet: testSheet, attrs: const {...testAttrs, 'theme': 'light'}, child: child!),
          home: Align(alignment: Alignment.topLeft, child: home),
        ),
      );
      return navigator;
    }

    List<Widget> rows(List<String> chosen) => [
          GlacierMenuItem(onSelect: () => chosen.add('rename'), child: const Text('Rename')),
          GlacierMenuItem(onSelect: () => chosen.add('duplicate'), child: const Text('Duplicate')),
          const GlacierMenuSub(label: Text('Share'), children: [GlacierMenuItem(child: Text('Email'))]),
        ];

    testWidgets('the arrow keys are the menu\'s, over the app\'s own focus travel', (tester) async {
      final chosen = <String>[];
      await app(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            menu(children: rows(chosen)),
            GlacierPressable(onPressed: () => chosen.add('beside'), builder: (context, state) => const SizedBox(width: 60, height: 20, child: Text('Beside'))),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getTopLeft(panel()), const Offset(100, 38));
      expect(focused(), 'Rename');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Duplicate');
      await press(tester, LogicalKeyboardKey.arrowRight); // toward the button beside the trigger: stays put
      expect(focused(), 'Duplicate');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(focused(), 'Email');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), 'Share');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);
      expect(chosen, ['duplicate']);
      expect(panels, findsNothing);
    });

    testWidgets('Escape closes the menu and not the page under it; back does the same', (tester) async {
      final navigator = await app(tester, const SizedBox.shrink());
      navigator.currentState!.push(
        PageRouteBuilder<void>(pageBuilder: (context, _, _) => Align(alignment: Alignment.topLeft, child: menu(children: rows([])))),
      );
      await settle(tester);
      await tester.tap(trigger);
      await settle(tester);
      expect(panels, findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(panels, findsNothing);
      expect(trigger, findsOneWidget); // the route is still there

      await tester.tap(trigger);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(panels, findsNothing);
      expect(trigger, findsOneWidget);
      // and with nothing open, back is the page's again
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(trigger, findsNothing);
    });

    testWidgets('Tab closes the menu and goes on its way', (tester) async {
      await app(tester, menu(children: rows([])));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await settle(tester);
      expect(panels, findsNothing);
    });

    testWidgets('an outside press closes it and still presses what it landed on', (tester) async {
      final chosen = <String>[];
      await app(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            menu(children: rows(chosen)),
            GlacierPressable(onPressed: () => chosen.add('beside'), builder: (context, state) => const SizedBox(width: 60, height: 20, child: Text('Beside'))),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      await tester.tap(find.text('Beside'));
      await settle(tester);
      expect(panels, findsNothing);
      expect(chosen, ['beside']);
    });
  });

  group('coming and going', () {
    testWidgets('fades and grows in over --glacier-duration-fast, and out again before it is taken away', (tester) async {
      final ease = t.curve('glacier-ease-out');
      await pumpKit(tester, menu(children: const [GlacierMenuItem(child: Text('Rename'))]));
      await tester.tap(trigger);
      await tester.pump();
      // The menu is its own glass, and fades itself: its backdrop filter, its fill and its rows as one.
      double opacity() => tester.widget<FadeTransition>(find.descendant(of: panels.first, matching: find.byType(FadeTransition)).first).opacity.value;
      expect(find.descendant(of: find.byType(FadeTransition), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(find.ancestor(of: find.byType(BackdropFilter), matching: find.byType(Opacity)), findsNothing);
      expect(opacity(), 0);
      await tester.pump(fast ~/ 2);
      expect(opacity(), moreOrLessEquals(ease.transform(0.5), epsilon: 1e-6));
      await tester.pump(fast ~/ 2);
      expect(opacity(), 1);
      await settle(tester);

      await tester.tapAt(const Offset(350, 700));
      await tester.pump();
      await tester.pump(fast - const Duration(milliseconds: 1));
      expect(panels, findsOneWidget);
      expect(opacity(), lessThan(0.01));
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(panels, findsNothing);
    });
  });

  group('the glass', () {
    testWidgets('blurs the page behind it all the way in, as an element that fades with its own backdrop filter does', (tester) async {
      // Drawn for real and read back as pixels. Behind the menu, stripes of black and white; through glass at rest
      // they are one grey, since the blur is far wider than a stripe. Part-way in, a browser shows the page and that
      // blurred glass mixed by the opacity. Were the opacity a layer round the glass instead, the glass would have
      // nothing behind it to blur until it had arrived, and the stripes would show through its fill, sharper.
      await pumpKit(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    for (var i = 0; i < 106; i++)
                      Expanded(child: ColoredBox(color: i.isEven ? const Color(0xFF000000) : const Color(0xFFFFFFFF), child: const SizedBox.expand())),
                  ],
                ),
              ),
              menu(at: const Offset(10, 10), children: const [GlacierMenuItem(child: Text('A')), GlacierMenuItem(child: Text('B')), GlacierMenuItem(child: Text('C'))]),
            ],
          ),
        ),
      );

      /// How far apart the darkest and lightest pixels are down a column of the window, from y 60 to 140.
      Future<int> contrast(int x) async {
        late int spread;
        await tester.runAsync(() async {
          final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final image = await layer.toImage(const Rect.fromLTWH(0, 0, 390, 200));
          final data = (await image.toByteData())!;
          final reds = [for (var y = 60; y < 140; y++) data.getUint8((y * 390 + x) * 4)]..sort();
          spread = reds.last - reds.first;
          image.dispose();
        });
        return spread;
      }

      await tester.tap(trigger);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final a = t.curve('glacier-ease-out').transform(20 / fast.inMilliseconds);
      final box = tester.getRect(panel());
      expect(box.top, lessThan(60));
      expect(box.bottom, greaterThan(140));
      final page = await contrast(300); // beside the menu
      final coming = await contrast(170); // through it, clear of its words
      await settle(tester);
      final arrived = await contrast(170);

      final fill = t.color('glacier-glass-thick').a;
      expect(fill, lessThan(0.97), reason: 'the fill must let something through for this to tell the two apart');
      expect(page, greaterThan(240));
      expect(arrived, lessThanOrEqualTo(3)); // one grey: blurred
      final mixed = (1 - a) * page; // the page, and a glass with no stripes left in it
      final unblurred = mixed + a * (1 - fill) * page; // the page, and a glass the stripes still show through
      expect(unblurred - mixed, greaterThan(8), reason: 'the two must be far enough apart to tell');
      expect((coming - mixed).abs(), lessThan(4), reason: 'coming in: $coming, a blurring glass $mixed, an unblurred one $unblurred');
    });
  });

  group('submenus', () {
    testWidgets('the row is shut until asked, and a press opens its flyout beside it', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, at: Offset.zero, children: share()));
      await settle(tester);
      expect(panels, findsOneWidget);
      expect(find.text('Email'), findsNothing);

      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(panels, findsNWidgets(2));
      // inline-end-start of the row, 2px off it
      final shareRow = tester.getRect(row('Share'));
      final expected = computeAnchoredPosition(
        trigger: shareRow,
        floating: tester.getSize(panel(1)),
        viewport: window,
        placement: Placement.inlineEndStart,
        offset: 2,
      );
      expect(tester.getTopLeft(panel(1)), expected.offset);
      expect(expected.placement, Placement.rightStart);
      expect(tester.getTopLeft(panel(1)), Offset((shareRow.right + 2 + 0.5).floorToDouble(), (shareRow.top + 0.5).floorToDouble()));
      expect(focused(), 'Email'); // a press goes into it
      // a press in the flyout is inside the menu
      await tester.tapAt(tester.getTopLeft(panel(1)) + const Offset(2, 2));
      await settle(tester);
      expect(panels, findsNWidgets(2));
    });

    testWidgets('turns to the row\'s other side at the window\'s edge, where that side holds it', (tester) async {
      // A flyout as wide as the kit's least fits on neither side of a menu in a 390 window, and then it stays on
      // the side it was asked for, running off the edge, as the kit's does. This one is let be narrower.
      await pumpKit(
        tester,
        menu(
          defaultOpen: true,
          at: const Offset(280, 10),
          children: const [
            GlacierMenuSub(
              label: Text('Share'),
              menuStyle: GlacierMenuStyle(minWidth: 100),
              children: [GlacierMenuItem(child: Text('Email')), GlacierMenuItem(child: Text('Copy link'))],
            ),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Share'));
      await settle(tester);
      final shareRow = tester.getRect(row('Share'));
      final flyout = tester.getRect(panel(1));
      expect(flyout.width, inExclusiveRange(100, 192));
      final expected = computeAnchoredPosition(trigger: shareRow, floating: flyout.size, viewport: window, placement: Placement.inlineEndStart, offset: 2);
      expect(expected.placement, Placement.leftStart);
      expect(flyout.topLeft, expected.offset);
      expect(flyout.right, lessThanOrEqualTo(shareRow.left - 2 + 0.5)); // 2px short of the row, to the whole pixel
      expect(tester.widget<Transform>(panel(1)).alignment, Alignment.centerRight);
    });

    testWidgets('stays on its side, running off the window, where neither side holds it', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, at: const Offset(280, 10), children: share()));
      await settle(tester);
      await tester.tap(find.text('Share'));
      await settle(tester);
      final shareRow = tester.getRect(row('Share'));
      expect(tester.getTopLeft(panel(1)).dx, (shareRow.right + 2 + 0.5).floorToDouble());
      expect(tester.getTopRight(panel(1)).dx, greaterThan(window.width));
    });

    testWidgets('ArrowRight opens it and focuses its first row; the arrows rove inside; ArrowLeft steps back', (tester) async {
      await pumpKit(tester, menu(children: share()));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Share');
      await press(tester, LogicalKeyboardKey.arrowLeft); // points away from the flyout: nothing
      expect(panels, findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(panels, findsNWidgets(2));
      expect(focused(), 'Email');
      // arrows rove inside the flyout without leaking into the parent panel
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Copy link');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Email');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focused(), 'Share');
      await settle(tester);
      expect(panels, findsOneWidget);
    });

    testWidgets('Enter on the row opens it, and choosing in the flyout closes the whole menu', (tester) async {
      final chosen = <String>[];
      await pumpKit(
        tester,
        menu(
          children: [
            GlacierMenuSub(
              label: const Text('Share'),
              children: [GlacierMenuItem(onSelect: () => chosen.add('email'), child: const Text('Email'))],
            ),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      expect(focused(), 'Share');
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);
      expect(focused(), 'Email');
      await press(tester, LogicalKeyboardKey.enter);
      await settle(tester);
      expect(chosen, ['email']);
      expect(panels, findsNothing);
    });

    testWidgets('nests, and Escape from the deepest flyout closes the whole stack and refocuses the trigger', (tester) async {
      await pumpKit(
        tester,
        menu(
          at: Offset.zero,
          children: const [
            GlacierMenuSub(
              label: Text('Share'),
              children: [
                GlacierMenuItem(child: Text('Email')),
                GlacierMenuSub(label: Text('Social'), children: [GlacierMenuItem(child: Text('Mastodon'))]),
              ],
            ),
          ],
        ),
      );
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Social');
      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(focused(), 'Mastodon');
      expect(panels, findsNWidgets(3));

      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(panels, findsNothing);
      expect(Focus.of(tester.element(find.descendant(of: trigger, matching: find.byType(SizedBox)))).hasPrimaryFocus, isTrue);
    });

    testWidgets('under RTL it opens toward the left, with ArrowLeft, and ArrowRight steps back', (tester) async {
      await pumpKit(tester, Directionality(textDirection: TextDirection.rtl, child: menu(at: const Offset(280, 10), children: share())));
      await tester.tap(trigger);
      await settle(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      // ArrowRight points AWAY from an inline-end flyout in RTL: it must not open
      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(panels, findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(panels, findsNWidgets(2));
      expect(focused(), 'Email');
      final shareRow = tester.getRect(row('Share'));
      expect(tester.getTopRight(panel(1)).dx, (shareRow.left - 2 + 0.5).floorToDouble());

      await press(tester, LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(panels, findsOneWidget);
      expect(focused(), 'Share');
    });

    testWidgets('a mouse opens it after the intent delay, may cross to the flyout, and leaving closes it after its own delay', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, at: Offset.zero, children: share()));
      await settle(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(350, 700));
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(row('Share')));
      await tester.pump(const Duration(milliseconds: 119));
      expect(panels, findsOneWidget); // intent delay pending
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(panels, findsNWidgets(2));
      await settle(tester);
      expect(focused(), 'Rename'); // the pointer opened it: the keyboard stays where it was

      // leaving the row toward the flyout does not close it: the close delay is cancelled the moment the pointer
      // arrives on the panel
      await mouse.moveTo(tester.getCenter(row('Share')) + const Offset(120, 30));
      await tester.pump(const Duration(milliseconds: 200));
      await mouse.moveTo(tester.getCenter(panel(1)));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(panels, findsNWidgets(2));

      // leaving the panel for good closes after the delay
      await mouse.moveTo(const Offset(350, 700));
      await tester.pump(const Duration(milliseconds: 299));
      expect(tester.widget<GlacierAnchoredLayer>(find.byType(GlacierAnchoredLayer).last).open, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(tester.widget<GlacierAnchoredLayer>(find.byType(GlacierAnchoredLayer).last).open, isFalse);
      await settle(tester);
      expect(panels, findsOneWidget);
    });

    testWidgets('a pointer that only passes over the row opens nothing', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, at: Offset.zero, children: share()));
      await settle(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(350, 700));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row('Share')));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(tester.getCenter(row('Rename')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(panels, findsOneWidget);
    });

    testWidgets('a disabled one stays shut', (tester) async {
      await pumpKit(
        tester,
        menu(
          defaultOpen: true,
          children: const [
            GlacierMenuItem(child: Text('Rename')),
            GlacierMenuSub(label: Text('Share'), disabled: true, children: [GlacierMenuItem(child: Text('Email'))]),
          ],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(panels, findsOneWidget);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focused(), 'Rename'); // the only row the arrows have
    });

    testWidgets('its flyout goes with the menu', (tester) async {
      await pumpKit(tester, menu(at: Offset.zero, children: share()));
      await tester.tap(trigger);
      await settle(tester);
      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(panels, findsNWidgets(2));
      await tester.tapAt(const Offset(350, 700));
      await tester.pump();
      // both are on their way out together
      expect(tester.widgetList<GlacierAnchoredLayer>(find.byType(GlacierAnchoredLayer)).map((layer) => layer.open), [false, false]);
      await settle(tester);
      expect(panels, findsNothing);
    });
  });

  group('rows', () {
    testWidgets('an icon leads and a shortcut trails, in their own inks', (tester) async {
      await pumpKit(
        tester,
        menu(
          defaultOpen: true,
          children: const [
            GlacierMenuItem(icon: Icon(LucideIcons.pencil), shortcut: Text('⌘E'), child: Text('Edit')),
            GlacierMenuItem(danger: true, icon: Icon(LucideIcons.trash2), child: Text('Delete')),
          ],
        ),
      );
      await settle(tester);
      final edit = tester.getRect(row('Edit'));
      final em = t.fontSize('sm');
      // `.icon { width: 1em; height: 1em }` then the row's gap, then the label
      final icon = tester.getRect(find.byIcon(LucideIcons.pencil));
      expect(icon.width, moreOrLessEquals(16));
      expect(icon.height, moreOrLessEquals(16));
      expect(icon.center.dx, moreOrLessEquals(edit.left + t.space(3) + em / 2, epsilon: 0.01));
      expect(icon.center.dy, moreOrLessEquals(edit.center.dy, epsilon: 0.01));
      expect(tester.getTopLeft(find.text('Edit')).dx, moreOrLessEquals(edit.left + t.space(3) + em + t.space(3), epsilon: 0.01));
      // the shortcut ends at the row's padding
      expect(tester.getTopRight(find.text('⌘E')).dx, moreOrLessEquals(edit.right - t.space(3), epsilon: 0.01));

      expect(typeOf(tester, 'Edit').color, t.color('glacier-text'));
      expect(typeOf(tester, '⌘E').color, t.color('glacier-text-subtle'));
      expect(typeOf(tester, 'Delete').color, t.color('glacier-danger-text'));
      expect(IconTheme.of(tester.element(find.byIcon(LucideIcons.pencil))).color, t.color('glacier-text-muted'));
      expect(IconTheme.of(tester.element(find.byIcon(LucideIcons.trash2))).color, t.color('glacier-danger-text'));
      expect(typeOf(tester, '⌘E').fontSize, t.fontSize('xs'));
      expect(typeOf(tester, '⌘E').fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('a heading is small capitals in the quiet ink', (tester) async {
      await pumpKit(tester, menu(defaultOpen: true, children: const [GlacierMenuLabel(child: Text('Organizations')), GlacierMenuItem(child: Text('Acme'))]));
      await settle(tester);
      final style = typeOf(tester, 'ORGANIZATIONS');
      expect(style.color, t.color('glacier-text-subtle'));
      expect(style.fontSize, t.fontSize('xs'));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, moreOrLessEquals(0.04 * t.fontSize('xs')));
      // it is not one of the rows the arrows visit
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focused(), 'Acme');
    });

    testWidgets('the panel and its rows take an app\'s overrides', (tester) async {
      // Ghost.md's PopMenu.module.css: a height the panel may take, with its rows scrolling inside; rows a thumb's
      // height in the + list's type; and NoteMenu.module.css's red for a danger row
      final red = t.color('glacier-red-11');
      await pumpKit(
        tester,
        menu(
          defaultOpen: true,
          style: GlacierMenuStyle(
            maxHeight: 160,
            maxWidth: 171,
            item: GlacierMenuItemStyle(
              minHeight: 44,
              iconSize: 1.15 * t.fontSize('md'),
              textStyle: TextStyle(fontSize: t.fontSize('md'), fontWeight: t.weight('medium')),
            ),
          ),
          children: [
            for (var i = 0; i < 8; i++) GlacierMenuItem(icon: const Icon(LucideIcons.pin), child: Text('Row $i')),
            GlacierMenuItem(danger: true, style: GlacierMenuItemStyle(color: red, iconColor: red), child: const Text('Delete')),
          ],
        ),
      );
      await settle(tester);
      expect(tester.getSize(panel()), const Size(192, 160)); // min-width has the last word over a narrower max-width
      expect(tester.getSize(row('Row 0')).height, 44);
      final type = typeOf(tester, 'Row 0');
      expect(type.fontSize, t.fontSize('md'));
      expect(type.fontWeight, FontWeight.w500);
      expect(tester.getSize(find.byIcon(LucideIcons.pin).first).width, moreOrLessEquals(1.15 * t.fontSize('md'), epsilon: 0.01));
      expect(typeOf(tester, 'Delete').color, red);

      // the last row is below the fold of the panel, and the arrows bring it into view
      final box = tester.getRect(panel());
      expect(tester.getRect(row('Delete')).top, greaterThan(box.bottom));
      await press(tester, LogicalKeyboardKey.end);
      await tester.pump();
      expect(focused(), 'Delete');
      expect(tester.getRect(row('Delete')).bottom, lessThanOrEqualTo(box.bottom));
      await press(tester, LogicalKeyboardKey.home);
      await tester.pump();
      expect(tester.getRect(row('Row 0')).top, greaterThanOrEqualTo(box.top));
    });
  });

  group('semantics', () {
    testWidgets('a menu of menuitems by their names, and a trigger that says whether it is open', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKit(
        tester,
        menu(
          children: const [
            GlacierMenuLabel(child: Text('Edit')),
            GlacierMenuItem(child: Text('Rename')),
            GlacierMenuItem(disabled: true, child: Text('Export')),
            GlacierMenuSeparator(),
            GlacierMenuItem(ariaLabel: 'Add to Work', child: Text('Work')),
            GlacierMenuSub(label: Text('Share'), children: [GlacierMenuItem(child: Text('Email'))]),
          ],
        ),
      );
      expect(tester.getSemantics(trigger), isSemantics(label: 'Actions', isButton: true, hasExpandedState: true, isExpanded: false));

      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getSemantics(trigger), isSemantics(isExpanded: true));
      SemanticsNode nodeOf(String label) => tester.getSemantics(find.bySemanticsLabel(label).first);

      // the heading is read as it was written, not in the capitals it is shown in
      expect(find.text('EDIT'), findsOneWidget);
      final menuNode = nodeOf('Edit').parent!;
      expect(menuNode, isSemantics(label: 'Actions', role: SemanticsRole.menu));
      expect(tester.getSemantics(trigger).controlsNodes, {menuNode.identifier});

      expect(nodeOf('Rename'), isSemantics(role: SemanticsRole.menuItem, hasEnabledState: true, isEnabled: true, hasTapAction: true, isFocused: true));
      expect(nodeOf('Export'), isSemantics(role: SemanticsRole.menuItem, hasEnabledState: true, isEnabled: false, hasTapAction: false));
      // a row's whole name, in place of what it shows
      expect(nodeOf('Add to Work'), isSemantics(role: SemanticsRole.menuItem, label: 'Add to Work'));
      expect(find.bySemanticsLabel('Work'), findsNothing);
      expect(nodeOf('Share'), isSemantics(role: SemanticsRole.menuItem, hasExpandedState: true, isExpanded: false));
      for (final label in ['Rename', 'Export', 'Add to Work']) {
        expect(nodeOf(label).parent, menuNode, reason: label);
      }
      // A row with a flyout is one node further in: the node the framework gives a portal's child, so that a
      // screen reader goes from the row straight on into its flyout.
      expect(nodeOf('Share').parent!.parent, menuNode);

      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(nodeOf('Share'), isSemantics(role: SemanticsRole.menuItem, isExpanded: true));
      final flyout = nodeOf('Email').parent!;
      expect(flyout, isSemantics(label: 'Share', role: SemanticsRole.menu));
      expect(nodeOf('Email'), isSemantics(role: SemanticsRole.menuItem, isFocused: true));
      handle.dispose();
    });
  });
}
