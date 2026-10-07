import 'dart:ui' show PointerDeviceKind, SemanticsRole;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

import 'support/harness.dart';

/// GlacierPopover against organisms/Popover/Popover.tsx: where the panel lands, what closes it, how it comes and
/// goes, and what it says to a screen reader. The window is the harness's 390 x 844.
void main() {
  const window = Size(390, 844);
  final t = testTokens();
  final fast = t.duration('glacier-duration-fast');

  /// The panel as it is laid out: the presence, which is the one child the positioner places.
  final panel = find.descendant(of: find.byType(GlacierAnchored), matching: find.byType(Opacity)).first;
  final trigger = find.byKey(const ValueKey('trigger'));

  /// A trigger [size] big, [at] from the window's corner, with the popover hung from it.
  Widget popover({
    Offset at = const Offset(100, 10),
    Size size = const Size(100, 20),
    Placement placement = Placement.bottomStart,
    bool? open,
    bool defaultOpen = false,
    ValueChanged<bool>? onOpenChange,
    PopoverOpenOn openOn = PopoverOpenOn.press,
    VoidCallback? onTriggerPressed,
    double? minWidth,
    Widget content = const SizedBox(width: 120, height: 80),
  }) {
    return Padding(
      padding: EdgeInsets.only(left: at.dx, top: at.dy),
      child: GlacierPopover(
        ariaLabel: 'Details',
        placement: placement,
        open: open,
        defaultOpen: defaultOpen,
        onOpenChange: onOpenChange,
        openOn: openOn,
        minWidth: minWidth,
        trigger: (context, handle) => GlacierPressable(
          key: const ValueKey('trigger'),
          semanticLabel: 'Open',
          onPressed: openOn == PopoverOpenOn.press ? handle.toggle : (onTriggerPressed ?? () {}),
          builder: (context, state) => SizedBox(width: size.width, height: size.height),
        ),
        child: content,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(const Duration(milliseconds: 20));

  /// The harness keeps the first child it is given, so a test that changes what is shown changes this instead.
  Future<ValueNotifier<Widget>> stage(WidgetTester tester, Widget first) async {
    final shown = ValueNotifier<Widget>(first);
    addTearDown(shown.dispose);
    await pumpKit(tester, ValueListenableBuilder<Widget>(valueListenable: shown, builder: (context, child, _) => child));
    return shown;
  }

  /// A fresh harness, for a test that mounts more than one thing in turn.
  Future<void> remount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, child);
  }

  /// The focus node of the trigger's own pressable.
  FocusNode triggerFocus(WidgetTester tester) => Focus.of(tester.element(find.descendant(of: trigger, matching: find.byType(SizedBox))));

  double opacity(WidgetTester tester) => tester.widget<Opacity>(panel).opacity;

  // `.panel { min-width: 12rem; padding: var(--glacier-space-2) }` round a 120 x 80 child
  final panelSize = Size(192, 80 + 2 * t.space(2));

  group('placing', () {
    testWidgets('opens on press, anchored where the maths says', (tester) async {
      await pumpKit(tester, popover());
      expect(find.byType(GlacierAnchored), findsNothing);

      await tester.tap(trigger);
      await tester.pump();
      // In place from the first frame it is in the tree, before it has faded in at all.
      expect(tester.getRect(trigger), const Rect.fromLTWH(100, 10, 100, 20));
      expect(tester.getSize(panel).width, 192);
      expect(tester.getSize(panel).height, moreOrLessEquals(panelSize.height, epsilon: 0.01));
      expect(tester.getTopLeft(panel), const Offset(100, 42)); // trigger left; trigger bottom 30 + offset 12

      await settle(tester);
      final expected = computeAnchoredPosition(trigger: tester.getRect(trigger), floating: tester.getSize(panel), viewport: window, offset: 12);
      expect(tester.getTopLeft(panel), expected.offset);
      expect(expected.placement, Placement.bottomStart);
    });

    testWidgets('the glass points its tip at the trigger\'s centre', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true));
      await settle(tester);
      final glass = tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass));
      expect(glass.placement, Placement.bottomStart);
      expect(glass.tipAt, 50); // trigger centre 150 - panel left 100
      expect(find.descendant(of: find.byType(GlacierArrowGlass), matching: find.byType(BackdropFilter)), findsOneWidget);
    });

    testWidgets('turns above a trigger at the foot of the window', (tester) async {
      await pumpKit(tester, popover(at: const Offset(100, 800)));
      await tester.tap(trigger);
      await settle(tester);
      // 820 + 12 + panel is past 844 - 8; above, 800 - 12 - panel
      expect(tester.getTopLeft(panel).dy, (800 - 12 - panelSize.height + 0.5).floorToDouble());
      expect(tester.getTopLeft(panel).dx, 100);
      expect(tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass)).placement, Placement.topStart);
      // and grows out of its foot
      expect(tester.widget<Transform>(find.descendant(of: panel, matching: find.byType(Transform)).first).alignment, Alignment.bottomCenter);
    });

    testWidgets('is pushed back inside the window\'s edge, the tip staying on the trigger', (tester) async {
      await pumpKit(tester, popover(at: const Offset(280, 10)));
      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(190, 42)); // 390 - 192 - 8
      expect(tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass)).tipAt, 140); // trigger centre 330 - 190
    });

    testWidgets('bottom-end hangs from the trigger\'s far edge', (tester) async {
      await pumpKit(tester, popover(at: const Offset(250, 10), placement: Placement.bottomEnd));
      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(158, 42)); // trigger right 350 - 192
    });

    testWidgets('start is the trigger\'s right edge under RTL', (tester) async {
      await pumpKit(tester, Directionality(textDirection: TextDirection.rtl, child: popover(at: const Offset(150, 10))));
      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(58, 42)); // trigger right 250 - 192
    });

    testWidgets('right-start stands beside the trigger', (tester) async {
      await pumpKit(tester, popover(at: const Offset(20, 300), placement: Placement.rightStart));
      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(132, 300)); // trigger right 120 + 12
      final glass = tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass));
      expect(glass.placement, Placement.rightStart);
      expect(glass.tipAt, 10); // trigger centre 310 - panel top 300
    });

    testWidgets('follows its trigger when the trigger moves, in the same frame', (tester) async {
      final shown = await stage(tester, popover(defaultOpen: true));
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(100, 42));
      shown.value = popover(defaultOpen: true, at: const Offset(60, 200));
      await tester.pump();
      expect(tester.getTopLeft(panel), const Offset(60, 232));
    });

    testWidgets('tracks its trigger as the page scrolls, in the frame the page moves', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpKit(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: SingleChildScrollView(
            controller: scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [const SizedBox(height: 760), popover(defaultOpen: true, at: const Offset(100, 0)), const SizedBox(height: 2000)],
            ),
          ),
        ),
      );
      await settle(tester);
      // at the foot of the window it stands above its trigger: 760 - 12 - panel
      final above = (760 - 12 - panelSize.height + 0.5).floorToDouble();
      expect(tester.getTopLeft(panel), Offset(100, above));
      expect(tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass)).placement, Placement.topStart);

      scroll.jumpTo(40);
      await tester.pump();
      expect(tester.getTopLeft(panel), Offset(100, above - 40)); // no frame behind

      // far enough up the window that there is room below, it turns; the place is right at once, and the tip and the
      // edge it grows from follow a frame later, as the React's did a commit later
      scroll.jumpTo(100);
      await tester.pump();
      expect(tester.getTopLeft(panel), const Offset(100, 692)); // trigger bottom 680 + 12
      await tester.pump();
      expect(tester.widget<GlacierArrowGlass>(find.byType(GlacierArrowGlass)).placement, Placement.bottomStart);
      expect(tester.getTopLeft(panel), const Offset(100, 692));
    });

    testWidgets('hangs from a widget elsewhere, a rectangle or a point', (tester) async {
      final elsewhere = GlobalKey();
      Widget from(GlacierAnchor anchor) => Stack(
            children: [
              Positioned(left: 40, top: 300, child: SizedBox(key: elsewhere, width: 60, height: 30)),
              GlacierPopover(anchor: anchor, open: true, child: const SizedBox(width: 120, height: 80)),
            ],
          );
      await pumpKit(tester, SizedBox(width: 390, height: 844, child: from(GlacierAnchor.key(elsewhere))));
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(40, 342)); // the widget's left; its bottom 330 + 12

      await remount(tester, SizedBox(width: 390, height: 844, child: from(const GlacierAnchor.rect(Rect.fromLTWH(150, 100, 20, 20)))));
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(150, 132));

      await remount(tester, SizedBox(width: 390, height: 844, child: from(GlacierAnchor.point(const Offset(90, 500)))));
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(90, 512));
    });

    testWidgets('hangs from a layer link\'s target', (tester) async {
      final link = LayerLink();
      await pumpKit(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Positioned(left: 70, top: 200, child: CompositedTransformTarget(link: link, child: const SizedBox(width: 50, height: 40))),
              GlacierPopover(anchor: GlacierAnchor.link(link), open: true, child: const SizedBox(width: 120, height: 80)),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(tester.getTopLeft(panel), const Offset(70, 252)); // its left; its bottom 240 + 12
    });

    testWidgets('on a dense screen the places are still logical pixels, for a key and for a layer link', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final link = LayerLink();
      final card = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: window, devicePixelRatio: 3),
            child: GlacierTheme(
              sheet: testSheet,
              attrs: const {...testAttrs, 'theme': 'light'},
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => Stack(
                      children: [
                        Positioned(left: 70, top: 200, child: CompositedTransformTarget(link: link, child: const SizedBox(width: 50, height: 40))),
                        Positioned(left: 200, top: 500, child: SizedBox(key: card, width: 50, height: 40)),
                        GlacierPopover(anchor: GlacierAnchor.link(link), open: true, child: const SizedBox(width: 120, height: 80)),
                        GlacierPopover(anchor: GlacierAnchor.key(card), open: true, placement: Placement.bottomEnd, child: const SizedBox(width: 120, height: 80)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final panels = find.byType(GlacierAnchored);
      expect(tester.getTopLeft(find.descendant(of: panels.at(0), matching: find.byType(Opacity)).first), const Offset(70, 252));
      expect(tester.getTopRight(find.descendant(of: panels.at(1), matching: find.byType(Opacity)).first), const Offset(250, 552));
    });

    testWidgets('the panel\'s width is the kit\'s unless it is told otherwise', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true, content: const SizedBox(width: 600, height: 20)));
      await settle(tester);
      expect(tester.getSize(panel).width, 358); // min(24rem, 100vw - 2rem) of a 390 window
      // app's `.panel { min-inline-size: min(17rem, calc(100vw - 2rem)) }`
      await remount(tester, popover(defaultOpen: true, minWidth: 272));
      await settle(tester);
      expect(tester.getSize(panel).width, 272);
    });
  });

  group('closing', () {
    testWidgets('closes on an outside press, once', (tester) async {
      final changes = <bool>[];
      await pumpKit(tester, popover(onOpenChange: changes.add));
      await tester.tap(trigger);
      await settle(tester);
      expect(changes, [true]);

      await tester.tapAt(const Offset(350, 700));
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
      expect(changes, [true, false]);
    });

    testWidgets('a press inside the panel is not a press outside', (tester) async {
      await pumpKit(tester, popover());
      await tester.tap(trigger);
      await settle(tester);
      await tester.tapAt(tester.getCenter(panel));
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsOneWidget);
    });

    testWidgets('a press on the trigger closes it by the trigger\'s own toggle, not twice over', (tester) async {
      final changes = <bool>[];
      await pumpKit(tester, popover(onOpenChange: changes.add));
      await tester.tap(trigger);
      await settle(tester);
      await tester.tap(trigger);
      await settle(tester);
      expect(changes, [true, false]);
      expect(find.byType(GlacierAnchored), findsNothing);
    });

    testWidgets('closes on Escape and hands focus back to the trigger', (tester) async {
      await pumpKit(tester, popover());
      await tester.tap(trigger);
      await settle(tester);
      // a press-opened panel is where the keyboard went
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'GlacierPopover panel');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
      expect(triggerFocus(tester).hasPrimaryFocus, isTrue);
    });

    testWidgets('the system\'s back closes it, with no navigator and under one', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);

      final navigator = GlobalKey<NavigatorState>();
      await remount(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Navigator(
            key: navigator,
            onGenerateRoute: (settings) => PageRouteBuilder<void>(
              settings: settings,
              pageBuilder: (context, _, _) => Align(alignment: Alignment.topLeft, child: popover(defaultOpen: true)),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsOneWidget);
      expect(await navigator.currentState!.maybePop(), isTrue); // the route stays; the popover took the gesture
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
      expect(find.byKey(const ValueKey('trigger')), findsOneWidget);
    });

    testWidgets('controlled: it opens and closes as it is told, and only reports', (tester) async {
      final changes = <bool>[];
      final shown = await stage(tester, popover(open: false, onOpenChange: changes.add));
      await tester.tap(trigger);
      await settle(tester);
      expect(changes, [true]);
      expect(find.byType(GlacierAnchored), findsNothing); // the owner did not follow

      shown.value = popover(open: true, onOpenChange: changes.add);
      await tester.pump();
      expect(find.byType(GlacierAnchored), findsOneWidget); // the frame it was told
      await settle(tester);
      await tester.tapAt(const Offset(350, 700));
      await settle(tester);
      expect(changes, [true, false]);
      expect(find.byType(GlacierAnchored), findsOneWidget); // still open until told otherwise

      shown.value = popover(open: false, onOpenChange: changes.add);
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
    });
  });

  group('coming and going', () {
    testWidgets('fades and grows in over --glacier-duration-fast, eased out', (tester) async {
      expect(fast, const Duration(milliseconds: 150));
      final ease = t.curve('glacier-ease-out');
      await pumpKit(tester, popover());
      await tester.tap(trigger);
      await tester.pump();
      Matrix4 transform() => tester.widget<Transform>(find.descendant(of: panel, matching: find.byType(Transform)).first).transform;
      // initial={{ opacity: 0, scale: 0.96, y: -4 }}
      expect(opacity(tester), 0);
      expect(transform().entry(0, 0), moreOrLessEquals(0.96));
      expect(transform().entry(1, 3), moreOrLessEquals(-4));

      await tester.pump(fast ~/ 2);
      final half = ease.transform(0.5);
      expect(opacity(tester), moreOrLessEquals(half, epsilon: 1e-6));
      expect(transform().entry(0, 0), moreOrLessEquals(0.96 + 0.04 * half, epsilon: 1e-6));
      expect(transform().entry(1, 3), moreOrLessEquals(-4 + 4 * half, epsilon: 1e-6));

      await tester.pump(fast ~/ 2 - const Duration(milliseconds: 1));
      expect(opacity(tester), lessThan(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacity(tester), 1);
      expect(transform(), Matrix4.identity());
      // One frame more for the animation to say it is done, and then it asks for no frames at rest.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 1); // the positioner's look at the next frame, whenever that is
    });

    testWidgets('stays in the tree while it fades out, to { opacity: 0, scale: 0.98, y: -2 }, and is then taken out', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true));
      await settle(tester);
      await tester.tapAt(const Offset(350, 700));
      await tester.pump();
      expect(opacity(tester), 1);
      await tester.pump(fast - const Duration(milliseconds: 1));
      expect(find.byType(GlacierAnchored), findsOneWidget);
      expect(opacity(tester), lessThan(0.01));
      final transform = tester.widget<Transform>(find.descendant(of: panel, matching: find.byType(Transform)).first).transform;
      expect(transform.entry(0, 0), moreOrLessEquals(0.98, epsilon: 1e-3));
      expect(transform.entry(1, 3), moreOrLessEquals(-2, epsilon: 1e-2));
      // The animation says it is done on the frame after its last, and the panel is out of the tree by the next.
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(find.byType(GlacierAnchored), findsNothing);
    });

    testWidgets('reopened while it is going, it comes back from where it had got to', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true));
      await settle(tester);
      await tester.tap(trigger);
      await tester.pump();
      await tester.pump(fast ~/ 2);
      final going = opacity(tester);
      expect(going, inExclusiveRange(0, 1));
      await tester.tap(trigger);
      await tester.pump();
      expect(opacity(tester), moreOrLessEquals(going, epsilon: 1e-6));
      await settle(tester);
      expect(opacity(tester), 1);
      expect(find.byType(GlacierAnchored), findsOneWidget);
    });

    testWidgets('with reduced motion it only fades, in no time', (tester) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: window, disableAnimations: true),
            child: GlacierTheme(
              sheet: testSheet,
              attrs: const {...testAttrs, 'theme': 'light'},
              child: Overlay(
                initialEntries: [OverlayEntry(builder: (context) => Align(alignment: Alignment.topLeft, child: popover()))],
              ),
            ),
          ),
        ),
      );
      await tester.tap(trigger);
      await tester.pump();
      expect(opacity(tester), 0);
      expect(tester.widget<Transform>(find.descendant(of: panel, matching: find.byType(Transform)).first).transform, Matrix4.identity());
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacity(tester), 1);
    });
  });

  group('opened on hover', () {
    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(350, 700));
      addTearDown(gesture.removePointer);
      return gesture;
    }

    testWidgets('opens under the pointer and leaves the trigger its own press', (tester) async {
      var presses = 0;
      await pumpKit(tester, popover(openOn: PopoverOpenOn.hover, onTriggerPressed: () => presses++));
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(trigger));
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsOneWidget);
      // the pointer went to it, the keyboard did not
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('GlacierPopover panel'));

      await tester.tap(trigger);
      await settle(tester);
      expect(presses, 1);
      expect(find.byType(GlacierAnchored), findsOneWidget);
    });

    testWidgets('stays open while the pointer crosses to the panel, and closes a moment after it leaves', (tester) async {
      await pumpKit(tester, popover(openOn: PopoverOpenOn.hover));
      final pointer = await mouse(tester);
      await pointer.moveTo(tester.getCenter(trigger));
      await settle(tester);

      // the gap between the two is a place the pointer passes through, not one it left for
      await pointer.moveTo(const Offset(150, 36));
      await tester.pump(const Duration(milliseconds: 100));
      await pointer.moveTo(tester.getCenter(panel));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(GlacierAnchored), findsOneWidget);

      await pointer.moveTo(const Offset(350, 700));
      await tester.pump(const Duration(milliseconds: 149));
      expect(tester.widget<GlacierAnchoredLayer>(find.byType(GlacierAnchoredLayer)).open, isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.widget<GlacierAnchoredLayer>(find.byType(GlacierAnchoredLayer)).open, isFalse);
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
    });

    testWidgets('opens on focus without taking it, and hands it over on Tab', (tester) async {
      await pumpKit(tester, popover(openOn: PopoverOpenOn.hover));
      final node = triggerFocus(tester);
      node.requestFocus();
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsOneWidget);
      expect(node.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'GlacierPopover panel');
      // Escape, wherever the keyboard is, closes it and goes back to the trigger
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets('a finger\'s tap opens it, and the tap\'s end does not shut it', (tester) async {
      await pumpKit(tester, popover(openOn: PopoverOpenOn.hover));
      await tester.tap(trigger);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GlacierAnchored), findsOneWidget);
      await tester.tapAt(const Offset(350, 700));
      await settle(tester);
      expect(find.byType(GlacierAnchored), findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('the panel is a dialog by its label, and the trigger says whether it is open', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKit(tester, popover(content: const Text('Panel content')));
      expect(tester.getSemantics(trigger), isSemantics(label: 'Open', isButton: true, hasExpandedState: true, isExpanded: false));

      await tester.tap(trigger);
      await settle(tester);
      expect(tester.getSemantics(trigger), isSemantics(label: 'Open', isButton: true, hasExpandedState: true, isExpanded: true));
      final dialog = tester.getSemantics(find.bySemanticsLabel('Details').first);
      expect(dialog, isSemantics(label: 'Details', role: SemanticsRole.dialog));
      expect(tester.getSemantics(trigger).controlsNodes, {dialog.identifier});
      expect(find.bySemanticsLabel('Panel content'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the glass', () {
    testWidgets('blurs by the token\'s own number, which is the Gaussian\'s sigma, and saturates', (tester) async {
      final config = glacierGlassFilter(t);
      expect(t.len('glacier-blur-lg'), 32);
      expect(config.toString(), contains('32.0'));
      final resolved = config.resolve(const ImageFilterContext(bounds: Rect.fromLTWH(0, 0, 192, 96)));
      expect(resolved.toString(), allOf(contains('blur'), contains('32.0')));
    });

    testWidgets('paints its underlay, glass and outline in the box the tip reaches into', (tester) async {
      await pumpKit(tester, popover(defaultOpen: true));
      await settle(tester);
      final glass = find.byType(GlacierArrowGlass);
      final layers = find.descendant(of: glass, matching: find.byType(Positioned));
      // the host, then the three layers
      expect(layers, findsNWidgets(4));
      final box = tester.getRect(find.descendant(of: glass, matching: find.byType(ClipPath)));
      final panelRect = tester.getRect(panel);
      // placed bottom: the tip strip is the 6px above the panel
      expect(box, Rect.fromLTRB(panelRect.left, panelRect.top - 6, panelRect.right, panelRect.bottom));
    });
  });
}
