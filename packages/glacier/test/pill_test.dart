import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/pill.dart';
import 'package:glacier/src/components/pressable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/harness.dart';

Future<void> repumpKit(WidgetTester tester, Widget child, {String theme = 'light'}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpKit(tester, child, theme: theme);
}

void main() {
  final t = testTokens();
  final pill = find.byType(GlacierPill);
  BoxDecoration decoration(WidgetTester tester) =>
      tester.widget<DecoratedBox>(find.descendant(of: pill, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
  TextStyle textStyle(WidgetTester tester, String text) => DefaultTextStyle.of(tester.element(find.text(text))).style;

  testWidgets('it is as tall as its size says and as wide as its text and padding', (tester) async {
    await pumpKit(tester, const GlacierPill(child: Text('Draft')));
    // The test font draws every glyph one em square.
    final text = t.fontSize('sm') * 5;
    expect(tester.getSize(pill).height, t.lenOf('1.75rem'));
    expect(tester.getSize(pill).height, 28);
    expect(tester.getSize(pill).width, closeTo(text + t.space(3) * 2 + t.len('glacier-hairline') * 2, 0.001));
    expect(tester.getCenter(find.text('Draft')).dy, closeTo(14, 0.001));
    expect(textStyle(tester, 'Draft').fontSize, t.fontSize('sm'));
    expect(textStyle(tester, 'Draft').fontWeight, t.weight('medium'));
    expect(textStyle(tester, 'Draft').height, 1);

    await repumpKit(tester, const GlacierPill(size: GlacierPillSize.sm, child: Text('Draft')));
    expect(tester.getSize(pill).height, t.lenOf('1.375rem'));
    expect(tester.getSize(pill).height, 22);
    expect(tester.getSize(pill).width, closeTo(t.fontSize('xs') * 5 + t.space(2) * 2 + 2, 0.001));
    expect(textStyle(tester, 'Draft').fontSize, t.fontSize('xs'));
  });

  testWidgets('the icon leads, tucked half a space-1 toward the edge and a space-1 from the text', (tester) async {
    await pumpKit(tester, const GlacierPill(icon: Icon(LucideIcons.check), child: Text('Done')));
    final icon = find.byType(Icon);
    final side = t.fontSize('sm') * 1.05;
    expect(tester.getSize(icon), Size.square(side));
    expect(IconTheme.of(tester.element(icon)).color, t.color('glacier-text-muted'));
    final start = 1 + t.space(3) - t.space(1) / 2;
    expect(tester.getTopLeft(icon).dx, closeTo(start, 0.001));
    expect(tester.getTopLeft(find.text('Done')).dx, closeTo(start + side + t.space(1), 0.001));
    // The far side keeps its whole padding.
    expect(tester.getSize(pill).width, closeTo(start + side + t.space(1) + t.fontSize('sm') * 4 + t.space(3) + 1, 0.001));
  });

  testWidgets('onRemove adds a remove button that calls it, and fills on hover', (tester) async {
    // Hover and focus styles show in the keyboard-and-mouse highlight mode, which a test on a phone target is not in.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    var removed = 0;
    await pumpKit(tester, GlacierPill(tone: GlacierPillTone.accent, onRemove: () => removed++, child: const Text('Tag')));
    final button = find.descendant(of: pill, matching: find.byType(GlacierPressable));
    // 1.05em of a button's own 13.3333px, not of the pill's text.
    expect(tester.getSize(button).width, closeTo(14, 0.001));
    expect(tester.getSize(button).height, closeTo(14, 0.001));
    final end = tester.getSize(pill).width - 1 - t.space(3) + t.space(1) / 2;
    expect(tester.getTopRight(button).dx, closeTo(end, 0.001));
    expect(tester.getTopLeft(button).dx - tester.getTopRight(find.text('Tag')).dx, closeTo(t.space(1), 0.001));
    expect(tester.getSize(find.descendant(of: button, matching: find.byType(CustomPaint))), const Size.square(10));
    expect(tester.widget<AnimatedOpacity>(find.descendant(of: button, matching: find.byType(AnimatedOpacity))).opacity, 0.65);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(removed, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(button));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.descendant(of: button, matching: find.byType(AnimatedOpacity))).opacity, 1);
    final wash = tester.widget<AnimatedContainer>(find.descendant(of: button, matching: find.byType(AnimatedContainer))).decoration! as BoxDecoration;
    expect(wash.color, isSameColorAs(t.colorOf('color-mix(in oklch, var(--glacier-accent-text) 18%, transparent)')));
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('every tone and variant paints its own tokens in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      final none = tokens.colorOf('transparent');
      String text(GlacierPillTone tone) => tone == GlacierPillTone.neutral ? 'glacier-text-muted' : 'glacier-${tone.name}-text';
      for (final tone in GlacierPillTone.values) {
        await repumpKit(tester, GlacierPill(tone: tone, child: const Text('x')), theme: theme);
        expect(decoration(tester).color, tokens.color(tone == GlacierPillTone.neutral ? 'glacier-hover' : 'glacier-${tone.name}-soft'), reason: 'soft ${tone.name}');
        expect((decoration(tester).border! as Border).top.color, none);
        expect(textStyle(tester, 'x').color, tokens.color(text(tone)), reason: 'soft ${tone.name}');

        await repumpKit(tester, GlacierPill(tone: tone, variant: GlacierPillVariant.solid, child: const Text('x')), theme: theme);
        expect(decoration(tester).color, tokens.color(tone == GlacierPillTone.neutral ? 'glacier-gray-9' : 'glacier-${tone.name}-solid'), reason: 'solid ${tone.name}');
        final contrast = tone == GlacierPillTone.neutral ? 'glacier-accent-contrast' : 'glacier-${tone.name}-contrast';
        expect(textStyle(tester, 'x').color, tokens.color(contrast), reason: 'solid ${tone.name}');

        await repumpKit(tester, GlacierPill(tone: tone, variant: GlacierPillVariant.outline, child: const Text('x')), theme: theme);
        expect(decoration(tester).color, isNull, reason: 'outline ${tone.name}');
        final border = (decoration(tester).border! as Border).top;
        expect(border.color, tokens.color(tone == GlacierPillTone.neutral ? 'glacier-border-strong' : 'glacier-${tone.name}-border'), reason: 'outline ${tone.name}');
        expect(border.width, tokens.len('glacier-hairline'));
        expect(textStyle(tester, 'x').color, tokens.color(text(tone)), reason: 'outline ${tone.name}');
      }
      expect(decoration(tester).borderRadius, BorderRadius.circular(tokens.radius('full')));
    });

    testWidgets('glass lays the blur under it and paints what the cascade leaves it, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      await pumpKit(tester, const GlacierPill(glass: true, tone: GlacierPillTone.success, child: Text('x')), theme: theme);
      expect(find.descendant(of: pill, matching: find.byType(BackdropFilter)), findsOneWidget);
      // A soft pill keeps its tone's fill and text, and takes the glass border.
      expect(decoration(tester).color, tokens.color('glacier-success-soft'));
      expect((decoration(tester).border! as Border).top.color, tokens.color('glacier-glass-border'));
      expect(textStyle(tester, 'x').color, tokens.color('glacier-success-text'));
      expect(tester.getSize(pill).height, 28);

      // An outline pill has no fill of its own, so the glass one shows; its border stays its tone's.
      await repumpKit(tester, const GlacierPill(glass: true, variant: GlacierPillVariant.outline, child: Text('x')), theme: theme);
      expect(decoration(tester).color, tokens.color('glacier-glass-regular'));
      expect((decoration(tester).border! as Border).top.color, tokens.color('glacier-border-strong'));
    });
  }

  testWidgets('a plain pill has no blur and no button', (tester) async {
    await pumpKit(tester, const GlacierPill(child: Text('x')));
    expect(find.descendant(of: pill, matching: find.byType(BackdropFilter)), findsNothing);
    expect(find.descendant(of: pill, matching: find.byType(GlacierPressable)), findsNothing);
  });

  testWidgets('its text is read, its icon is not, and the remove button is a named button', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(tester, GlacierPill(icon: const Icon(LucideIcons.tag, semanticLabel: 'tag glyph'), onRemove: () {}, child: const Text('Design')));
    expect(tester.getSemantics(find.text('Design')), isSemantics(label: 'Design'));
    expect(find.bySemanticsLabel('tag glyph'), findsNothing);
    final button = tester.getSemantics(find.descendant(of: pill, matching: find.byType(GlacierPressable)));
    expect(button, isSemantics(label: 'Dismiss', isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, isFocusable: true));

    await repumpKit(tester, GlacierPill(onRemove: () {}, dismissLabel: 'Remove Design', child: const Text('Design')));
    expect(tester.getSemantics(find.descendant(of: pill, matching: find.byType(GlacierPressable))), isSemantics(label: 'Remove Design', isButton: true));
    handle.dispose();
  });
}
