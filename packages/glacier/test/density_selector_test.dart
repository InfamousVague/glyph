import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/density_selector.dart';
import 'package:glacier/src/components/pressable.dart';
import 'package:glacier/src/tokens/css_value.dart';
import 'package:glacier/src/tokens/theme.dart';
import 'package:glacier/src/tokens/tokens.dart';

import 'support/harness.dart';

/// The selector holding its own value, as a settings screen would, after something else that takes the keyboard.
class Host extends StatefulWidget {
  const Host({super.key, this.initial = GlacierDensityMode.comfortable, this.changes, this.disabled = false, this.labels});
  final GlacierDensityMode initial;
  final List<GlacierDensityMode>? changes;
  final bool disabled;
  final Map<GlacierDensityMode, Widget>? labels;

  @override
  State<Host> createState() => _HostState();
}

class _HostState extends State<Host> {
  late GlacierDensityMode value = widget.initial;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Focus(debugLabel: 'before', child: SizedBox(width: 10, height: 10)),
          RepaintBoundary(
            child: GlacierDensitySelector(
              value: value,
              disabled: widget.disabled,
              labels: widget.labels,
              ariaLabel: 'Density',
              onValueChange: (next) {
                widget.changes?.add(next);
                setState(() => value = next);
              },
            ),
          ),
        ],
      );
}

/// The same tree in a window [width] wide, without the harness's fixed 390.
Future<void> pumpWide(WidgetTester tester, Widget child, double width) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: GlacierTheme(
          sheet: testSheet,
          attrs: const {...testAttrs, 'theme': 'light'},
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}

/// The selector as it is drawn: the alpha of the pixel at [at], 0 to 255, for each place asked.
Future<List<int>> alphaAt(WidgetTester tester, List<Offset> at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.ancestor(of: find.byType(GlacierDensitySelector), matching: find.byType(RepaintBoundary)).first);
  final bytes = (await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!;
  }))!;
  final width = boundary.size.width.round();
  return [for (final p in at) bytes.getUint8((p.dy.floor() * width + p.dx.floor()) * 4 + 3)];
}

/// What Tab does from the thing before the selector: the harness has no app above it to bind the key.
Future<void> tabInto(WidgetTester tester) async {
  final first = Focus.of(tester.element(find.byType(SizedBox).first));
  expect(first.debugLabel, 'before');
  first.requestFocus();
  await tester.pumpAndSettle();
  first.nextFocus();
  await tester.pumpAndSettle();
}

void main() {
  final t = testTokens();
  final selector = find.byType(GlacierDensitySelector);
  final previews = find.descendant(of: selector, matching: find.byType(AnimatedContainer));
  BoxDecoration preview(WidgetTester tester, GlacierDensityMode mode) => tester.widget<AnimatedContainer>(previews.at(mode.index)).decoration! as BoxDecoration;
  ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: selector, matching: find.byType(Scrollable))).position;
  final gap = t.space(2);
  // Five columns share 29rem less the row's 2px edges and four gaps.
  final column = (t.lenOf('29rem') - 4 - gap * 4) / 5;

  testWidgets('in a phone-wide row it is 29rem of cards in a window that scrolls sideways', (tester) async {
    await pumpKit(tester, const Host());
    expect(tester.getSize(selector).width, 390);
    expect(position(tester).maxScrollExtent, closeTo(t.lenOf('29rem') - 390, 0.001));

    expect(column, greaterThan(t.lenOf('5rem')));
    for (final mode in GlacierDensityMode.values) {
      final card = tester.getRect(previews.at(mode.index));
      expect(card.width, closeTo(t.lenOf('5rem'), 0.001), reason: 'width: min(100%, 5rem)');
      expect(card.height, closeTo(t.lenOf('5rem') / 1.08, 0.001), reason: 'aspect-ratio: 1.08');
      // Centred in its column.
      expect(card.center.dx, closeTo(2 + (column + gap) * mode.index + column / 2, 0.001), reason: mode.token);
    }
    final label = tester.getRect(find.text('Default'));
    final card = tester.getRect(previews.first);
    expect(card.top, closeTo(10 + 2 + t.space(1), 0.001));
    expect(label.top - card.bottom, closeTo(gap, 0.001));
    expect(label.center.dx, closeTo(tester.getRect(previews.at(2)).center.dx, 0.001));
    // Under the cards: their padding, the row's edge, and the room the scrollbar takes.
    expect(tester.getRect(selector).bottom - label.bottom, closeTo(t.space(1) + 2 + t.space(4), 0.001));
    final style = DefaultTextStyle.of(tester.element(find.text('Default'))).style;
    expect(style.fontSize, t.lenOf('0.675rem'));
    expect(style.height, t.len('glacier-leading-sm'));
    expect(style.fontWeight, t.weight('medium'));
  });

  testWidgets('where there is room for 29rem it fills the row and has no scrollbar', (tester) async {
    await pumpWide(tester, const Host(), 700);
    expect(tester.getSize(selector).width, 700);
    expect(position(tester).maxScrollExtent, 0);
    expect(find.descendant(of: selector, matching: find.byType(ShaderMask)), findsNothing);
    // The space scale is fluid, so a wider window has its own.
    final w = Tokens.root(testSheet, attrs: const {...testAttrs, 'theme': 'light'}, css: const CssContext(vw: 700, vh: 844));
    final wide = (700 - 4 - w.space(2) * 4) / 5;
    expect(tester.getRect(previews.at(4)).center.dx, closeTo(2 + (wide + w.space(2)) * 4 + wide / 2, 0.001));
    expect(tester.getRect(previews.first).width, closeTo(80, 0.001), reason: 'a card stops at 5rem');
    // No room kept for a scrollbar.
    expect(tester.getRect(selector).bottom - tester.getRect(find.text('Default')).bottom, closeTo(w.space(1) + 2, 0.001));
  });

  testWidgets('a press on a card selects it', (tester) async {
    final changes = <GlacierDensityMode>[];
    await pumpKit(tester, Host(changes: changes));
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(changes, [GlacierDensityMode.compact]);
    await tester.tap(previews.first);
    await tester.pumpAndSettle();
    expect(changes, [GlacierDensityMode.compact, GlacierDensityMode.extraCompact]);
    expect(tester.widget<GlacierDensitySelector>(selector).value, GlacierDensityMode.extraCompact);
  });

  testWidgets('arrows, Home and End move selection and focus, round the ends, and bring the card into view', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final changes = <GlacierDensityMode>[];
    await pumpKit(tester, Host(changes: changes));
    await tabInto(tester);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'density comfortable', reason: 'Tab stops on the selected card');
    expect(find.descendant(of: find.byType(GlacierFocusRing), matching: find.byType(CustomPaint)), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.spacious);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'density spacious');

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.moreSpace);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'density more-space');
    expect(position(tester).pixels, greaterThan(0), reason: 'the last card was off the edge');
    expect(tester.getRect(previews.at(4)).right, lessThanOrEqualTo(390));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.extraCompact, reason: 'past the last is the first');
    // Scrolled no further than shows the card: its own edge at the window's, the row's 2px padding off screen.
    expect(position(tester).pixels, closeTo(2, 0.001));
    expect(tester.getRect(previews.first).left, greaterThanOrEqualTo(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.moreSpace, reason: 'before the first is the last');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.extraCompact);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(changes.last, GlacierDensityMode.spacious);

    // Space presses the focused card like any button.
    final before = changes.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes.length, before + 1);
    expect(changes.last, GlacierDensityMode.spacious);
  });

  testWidgets('the edge that has more beyond it fades, and the scrollbar follows the scroll', (tester) async {
    await pumpKit(tester, const Host());
    final reach = t.lenOf('29rem') - 390;
    final track = find.descendant(
      of: selector,
      matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == t.colorOf('color-mix(in oklch, var(--glacier-border-strong) 50%, var(--glacier-surface))')),
    );
    final thumb = find.descendant(of: track, matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == t.color('glacier-border-strong')));
    // Along the bottom, a space-2 in from either side and a space-2 tall.
    expect(tester.getRect(track), rectMoreOrLessEquals(Rect.fromLTRB(gap, tester.getRect(selector).bottom - gap, 390 - gap, tester.getRect(selector).bottom), epsilon: 0.001));
    final share = 390 / t.lenOf('29rem');
    expect(tester.getSize(thumb).width, closeTo((390 - gap * 2) * share, 0.001));
    expect(tester.getRect(thumb).left, closeTo(gap, 0.001));

    // The fade, read off the pixels: a card's surface is opaque, so its alpha is the mask's. Each probe is 2px in
    // from an edge of the window, level with the middle of a card, where a card is under it at that scroll.
    expect(find.descendant(of: selector, matching: find.byType(ShaderMask)), findsOneWidget);
    final level = tester.getRect(previews.first).center.dy - tester.getRect(selector).top;
    final probes = [Offset(2, level), Offset(195, level), Offset(387, level)];
    final fade = t.space(6);
    int ramp(double inFromEdge) => (255 * inFromEdge / fade).round();

    // At the start the last card runs off the right edge, and dissolves toward it.
    expect(tester.getRect(previews.at(4)).left, lessThan(387));
    var alpha = await alphaAt(tester, probes);
    expect(alpha[1], 255);
    expect(alpha[2], closeTo(ramp(2.5), 6), reason: 'more to the right');

    position(tester).jumpTo(reach / 2);
    await tester.pump();
    expect(tester.getRect(previews.first).right, greaterThan(3));
    alpha = await alphaAt(tester, probes);
    expect(alpha[0], closeTo(ramp(2.5), 6), reason: 'more both ways');
    expect(alpha[2], closeTo(ramp(2.5), 6), reason: 'more both ways');
    expect(tester.getRect(thumb).center.dx, closeTo(195, 0.001));

    position(tester).jumpTo(reach);
    await tester.pump();
    // The last card now ends a few pixels short of the edge, so the right probe moves in onto it.
    expect(tester.getRect(previews.at(4)).right, greaterThan(385));
    alpha = await alphaAt(tester, [probes[0], Offset(384, level)]);
    expect(alpha[0], closeTo(ramp(2.5), 6), reason: 'more to the left');
    expect(alpha[1], 255, reason: 'nothing more to the right, so no fade there (a fade would leave it near ${ramp(5.5)})');
    expect(tester.getRect(thumb).right, closeTo(390 - gap, 0.001));

    // A press along the track scrolls to there, by ScrollArea's own sum: the place along the track, less half the
    // share that is in view, of the whole reach. (So the far end of the track is not the far end of the content; that
    // is the web kit's arithmetic, kept.)
    await tester.tapAt(tester.getRect(track).centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(position(tester).pixels, 0);
    final drag = await tester.startGesture(tester.getRect(track).centerLeft + const Offset(1, 0));
    final width = tester.getRect(track).width;
    await drag.moveTo(tester.getRect(track).centerLeft + Offset(width * 0.8, 0));
    await tester.pump();
    expect(position(tester).pixels, closeTo((0.8 - share / 2) * reach, 0.001));
    expect(position(tester).pixels, greaterThan(0));
    await drag.up();
  });

  testWidgets('a hovered card lifts a pixel and takes the strong border', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await pumpKit(tester, const Host());
    // The card's own box: the lift is a transform inside the animated container.
    final card = find.descendant(of: previews.at(1), matching: find.byType(DecoratedBox)).first;
    final top = tester.getRect(card).top;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(380, 800));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(previews.at(1)));
    await tester.pumpAndSettle();
    expect((preview(tester, GlacierDensityMode.compact).border! as Border).top.color, t.color('glacier-border-strong'));
    expect(tester.getRect(card).top, closeTo(top - t.len('glacier-space-px'), 0.001));
    expect(t.len('glacier-space-px'), 1);
    expect((preview(tester, GlacierDensityMode.extraCompact).border! as Border).top.color, t.color('glacier-border'));
  });

  testWidgets('disabled, no card takes a press, and it is as opaque as the web one', (tester) async {
    final changes = <GlacierDensityMode>[];
    await pumpKit(tester, Host(changes: changes, disabled: true));
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    // `opacity: var(--glacier-opacity-disabled)` names a token no sheet defines.
    expect(t.raw('glacier-opacity-disabled'), isNull);
    for (final opacity in tester.widgetList<Opacity>(find.descendant(of: selector, matching: find.byType(Opacity)))) {
      expect(opacity.opacity, 1);
    }
  });

  testWidgets('labels replace the kit\'s names', (tester) async {
    await pumpKit(tester, const Host(labels: {GlacierDensityMode.comfortable: Text('Normal')}));
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    for (final name in ['Extra Compact', 'Compact', 'Comfortable', 'More Space']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('the selected card wears the accent ring and the rest the border token, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      await pumpKit(tester, const Host(initial: GlacierDensityMode.compact), theme: theme);
      final chosen = preview(tester, GlacierDensityMode.compact);
      expect((chosen.border! as Border).top.color, tokens.color('glacier-accent-solid'));
      expect(chosen.boxShadow, tokens.shadowOf('0 0 0 2px var(--glacier-accent-solid), var(--glacier-shadow-2)'));
      expect(chosen.boxShadow!.first.spreadRadius, 2);
      expect(chosen.boxShadow!.first.color, tokens.color('glacier-accent-solid'));
      final other = preview(tester, GlacierDensityMode.spacious);
      expect((other.border! as Border).top.color, tokens.color('glacier-border'));
      expect((other.border! as Border).top.width, tokens.len('glacier-hairline'));
      expect(other.boxShadow, tokens.shadow('glacier-shadow-2'));
      expect(other.color, tokens.color('glacier-surface'));
      expect(other.borderRadius, BorderRadius.circular(tokens.radius('md')));
      expect(DefaultTextStyle.of(tester.element(find.text('Compact'))).style.color, tokens.color('glacier-text'));
      expect(DefaultTextStyle.of(tester.element(find.text('Comfortable'))).style.color, tokens.color('glacier-text-muted'));
    });
  }

  testWidgets('each density draws its own miniature: tighter lines, and one fewer at the loosest', (tester) async {
    await pumpKit(tester, const Host());
    final ink = t.color('glacier-text-muted');
    final faint = ink.withValues(alpha: ink.a * 0.72);
    List<Rect> lines(GlacierDensityMode mode) => [
          for (final e in find
              .descendant(of: previews.at(mode.index), matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == faint))
              .evaluate())
            tester.getRect(find.byElementPredicate((x) => x == e)),
        ];
    expect(lines(GlacierDensityMode.comfortable).length, 3);
    expect(lines(GlacierDensityMode.moreSpace).length, 2, reason: '.bodyShort is not drawn');
    final normal = lines(GlacierDensityMode.comfortable);
    expect(normal[0].height, closeTo(t.lenOf('0.23rem'), 0.001));
    expect(normal[1].top - normal[0].bottom, closeTo(t.lenOf('0.28rem'), 0.001));
    expect(normal[1].width / normal[0].width, closeTo(0.62, 0.001));
    final tight = lines(GlacierDensityMode.extraCompact);
    expect(tight[0].height, closeTo(t.lenOf('0.18rem'), 0.001));
    expect(tight[1].top - tight[0].bottom, closeTo(t.lenOf('0.1rem'), 0.001));
    final loose = lines(GlacierDensityMode.moreSpace);
    expect(loose[0].height, closeTo(t.lenOf('0.16rem'), 0.001));
    expect(loose[1].top - loose[0].bottom, closeTo(t.lenOf('0.6rem'), 0.001));
    // The toolbar: a 1rem strip with its hairline under it, across the card inside its border.
    final bar = find.descendant(of: previews.first, matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).color == t.color('glacier-surface-sunken')));
    expect(tester.getSize(bar), Size(t.lenOf('5rem') - 2, t.lenOf('1rem')));
  });

  testWidgets('it is a radio group of radios to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(tester, const Host());
    expect(tester.getSemantics(selector), isSemantics(role: ui.SemanticsRole.radioGroup, label: 'Density'));
    expect(
      tester.getSemantics(find.text('Default')),
      isSemantics(label: 'Default', hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, isFocusable: true),
    );
    expect(tester.getSemantics(find.text('Compact')), isSemantics(label: 'Compact', hasCheckedState: true, isChecked: false, isInMutuallyExclusiveGroup: true));

    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Compact')), isSemantics(isChecked: true));
    expect(tester.getSemantics(find.text('Default')), isSemantics(isChecked: false));
    handle.dispose();
  });

  test('a mode carries the data-density value the theme takes', () {
    expect(GlacierDensityMode.values.map((m) => m.token), ['extra-compact', 'compact', 'comfortable', 'spacious', 'more-space']);
    expect(testTokens(attrs: {'density': GlacierDensityMode.compact.token}).len('glacier-control-height-md'), 36);
  });
}
