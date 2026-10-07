import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/css_effects.dart';
import 'package:glacier/src/components/pressable.dart';
import 'package:glacier/src/components/switch.dart';
import 'package:glacier/src/tokens/css_value.dart';
import 'package:glacier/src/tokens/sheet.dart';
import 'package:glacier/src/tokens/theme.dart';
import 'package:glacier/src/tokens/tokens.dart';

import 'support/harness.dart';

/// Clears the tree first: the harness's Overlay keeps its first entry, so a second [pumpKit] in one test would
/// otherwise show the first widget again.
Future<void> repumpKit(WidgetTester tester, Widget child, {String theme = 'light'}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpKit(tester, child, theme: theme);
}

/// The kit's tokens alone, without Ghost.md's ink over them: the glass highlight and the see-through surfaces the
/// app's stylesheet flattens are still there.
final TokenSheet kitSheet = TokenSheet.parse(File('assets/css/tokens.css').readAsStringSync());

Widget kitThemed(Widget child, {String theme = 'light'}) => GlacierTheme(sheet: kitSheet, attrs: {'theme': theme}, child: child);

/// The box inside [of] that a decoration paints in [color].
Finder painted(Finder of, Color color) => find.descendant(
      of: of,
      matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color),
    );

void main() {
  final t = testTokens();
  final thumbColor = t.colorOf('oklch(0.995 0 0)');
  final control = find.byType(GlacierSwitch);

  testWidgets('the track is the size the stylesheet gives, at both sizes', (tester) async {
    await pumpKit(tester, const GlacierSwitch());
    expect(tester.getSize(control), Size(t.lenOf('2.75rem'), t.lenOf('1.625rem')));
    expect(tester.getSize(control), const Size(44, 26));
    expect(tester.getSize(painted(control, thumbColor)), Size.square(t.lenOf('1.375rem')));

    await repumpKit(tester, const GlacierSwitch(size: GlacierSwitchSize.sm));
    expect(tester.getSize(control), Size(t.lenOf('2.25rem'), t.lenOf('1.25rem')));
    expect(tester.getSize(control), const Size(36, 20));
    expect(tester.getSize(painted(control, thumbColor)), Size.square(t.lenOf('1rem')));
  });

  testWidgets('the label sits a space-2 gap after the track, in the small text', (tester) async {
    await pumpKit(tester, const GlacierSwitch(label: Text('Wi-Fi')));
    final label = find.text('Wi-Fi');
    expect(tester.getTopLeft(label).dx, closeTo(44 + t.space(2), 0.001));
    final style = DefaultTextStyle.of(tester.element(label)).style;
    expect(style.fontSize, t.fontSize('sm'));
    expect(style.color, t.color('glacier-text'));
    // Centred on the track, which is the taller of the two.
    expect(tester.getSize(control).height, 26);
    expect(tester.getCenter(label).dy, closeTo(13, 0.001));
  });

  testWidgets('a tap turns it on, and the thumb springs across its travel', (tester) async {
    final changes = <bool>[];
    await pumpKit(tester, GlacierSwitch(label: const Text('Wi-Fi'), onCheckedChange: changes.add));
    final thumb = painted(control, thumbColor);
    final pad = t.lenOf('0.125rem');
    expect(tester.getTopLeft(thumb).dx, pad);

    await tester.tap(find.text('Wi-Fi')); // the label is part of the press target
    await tester.pump();
    expect(changes, [true]);
    await tester.pump(const Duration(milliseconds: 40));
    final midway = tester.getTopLeft(thumb).dx;
    expect(midway, greaterThan(pad));
    expect(midway, lessThan(pad + 18));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb).dx, pad + 18);
    // Thumb and both paddings fill the track exactly.
    expect(tester.getTopRight(thumb).dx, 44 - pad);

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.getTopLeft(thumb).dx, pad);
  });

  testWidgets('the small thumb travels 16', (tester) async {
    await pumpKit(tester, const GlacierSwitch(size: GlacierSwitchSize.sm, defaultChecked: true));
    final thumb = painted(control, thumbColor);
    expect(tester.getTopLeft(thumb).dx, 2 + 16);
    expect(tester.getTopRight(thumb).dx, 36 - 2);
  });

  testWidgets('controlled, it reports the press and waits for its parent', (tester) async {
    var checked = false;
    final asked = <bool>[];
    late StateSetter rebuild;
    await pumpKit(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return GlacierSwitch(checked: checked, onCheckedChange: asked.add);
      }),
    );
    final thumb = painted(control, thumbColor);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(asked, [true]);
    expect(tester.getTopLeft(thumb).dx, 2, reason: 'the parent has not agreed yet');

    rebuild(() => checked = true);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb).dx, 20);
  });

  testWidgets('Space toggles it from the keyboard and shows the focus ring', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final node = FocusNode();
    addTearDown(node.dispose);
    final changes = <bool>[];
    await pumpKit(tester, GlacierSwitch(focusNode: node, onCheckedChange: changes.add));
    expect(find.descendant(of: control, matching: find.byType(CustomPaint)), findsNothing);

    node.requestFocus();
    await tester.pumpAndSettle();
    final ring = find.descendant(of: find.byType(GlacierFocusRing), matching: find.byType(CustomPaint));
    expect(ring, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });

  testWidgets('disabled, it dims to half and ignores a press', (tester) async {
    final changes = <bool>[];
    await pumpKit(tester, GlacierSwitch(disabled: true, onCheckedChange: changes.add));
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(tester.widget<Opacity>(find.descendant(of: control, matching: find.byType(Opacity))).opacity, 0.5);
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('the track is the border token off and the accent on, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      await pumpKit(tester, const GlacierSwitch(), theme: theme);
      expect(painted(control, tokens.color('glacier-border')), findsOneWidget);
      // The kit's thumb is one literal near-white in both themes.
      expect(painted(control, tokens.colorOf('oklch(0.995 0 0)')), findsOneWidget);

      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(painted(control, tokens.color('glacier-accent-solid')), findsOneWidget);
      expect(painted(control, tokens.color('glacier-border')), findsNothing);
    });

    testWidgets('thumbColor repaints the thumb, as ink.css does, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      final paper = tokens.color('app-paper');
      await pumpKit(tester, GlacierSwitch(thumbColor: paper), theme: theme);
      expect(tester.getSize(painted(control, paper)), const Size.square(22));
    });
  }

  testWidgets('on the kit\'s own tokens the thumb carries its inset highlight over shadow-2', (tester) async {
    final kit = Tokens.root(kitSheet, attrs: const {'theme': 'light'}, css: const CssContext(vw: 390, vh: 844));
    await pumpKit(tester, kitThemed(const GlacierSwitch()));
    final thumb = painted(control, kit.colorOf('oklch(0.995 0 0)'));
    expect((tester.widget<DecoratedBox>(thumb).decoration as BoxDecoration).boxShadow, kit.shadow('glacier-shadow-2'));
    expect(kit.color('glacier-glass-highlight').a, greaterThan(0));
    expect(find.descendant(of: thumb, matching: find.byType(CustomPaint)), findsOneWidget, reason: 'the highlight is painted');
    expect(painted(control, kit.color('glacier-border')), findsOneWidget);
  });

  testWidgets('glass frosts the unchecked track, and a checked one is the accent all the same', (tester) async {
    final kit = Tokens.root(kitSheet, attrs: const {'theme': 'light'}, css: const CssContext(vw: 390, vh: 844));
    await pumpKit(tester, kitThemed(const GlacierSwitch(glass: true)));
    expect(find.descendant(of: control, matching: find.byType(BackdropFilter)), findsOneWidget);
    expect(painted(control, kit.color('glacier-glass-regular')), findsOneWidget);
    expect(tester.getSize(control), const Size(44, 26));
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(painted(control, kit.color('glacier-accent-solid')), findsOneWidget);
    expect(painted(control, kit.color('glacier-glass-regular')), findsNothing);
  });

  testWidgets('an inset shadow is drawn inside the box: a band under the top edge, within the corners', (tester) async {
    const base = Color(0xFF204060), light = Color(0xFFFFFFFF);
    await tester.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: SizedBox(
            width: 40,
            height: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(color: base, borderRadius: BorderRadius.all(Radius.circular(10))),
              child: GlacierInsetShadows(
                radius: 10,
                shadows: [
                  CssShadow(offset: Offset(0, 2), blur: 0, spread: 0, color: light, inset: true),
                  // An outer layer in the same list is not this widget's to draw.
                  CssShadow(offset: Offset(0, 4), blur: 0, spread: 0, color: Color(0xFFFF0000)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
    final bytes = (await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }))!;
    List<int> at(int x, int y) => [for (var c = 0; c < 4; c++) bytes.getUint8((y * 40 + x) * 4 + c)];
    expect(at(20, 0), [255, 255, 255, 255], reason: 'the band, under the top edge');
    expect(at(20, 1), [255, 255, 255, 255]);
    expect(at(20, 3), [0x20, 0x40, 0x60, 255], reason: 'two pixels deep and no more');
    expect(at(20, 18), [0x20, 0x40, 0x60, 255], reason: 'nothing along the bottom');
    expect(at(1, 10), [0x20, 0x40, 0x60, 255], reason: 'nor down the side, where the offset is straight down');
    expect(at(0, 0)[3], 0, reason: 'and nothing outside the rounded corner');
    expect(at(20, 19), [0x20, 0x40, 0x60, 255], reason: 'the outer layer was left alone');
  });

  testWidgets('it is a switch to a screen reader, named by its label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(tester, const GlacierSwitch(label: Text('Wi-Fi')));
    expect(
      tester.getSemantics(control),
      isSemantics(label: 'Wi-Fi', hasToggledState: true, isToggled: false, hasEnabledState: true, isEnabled: true, isFocusable: true, hasTapAction: true),
    );
    expect(tester.getSemantics(control), isNot(isSemantics(isButton: true)));

    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(control), isSemantics(label: 'Wi-Fi', isToggled: true));

    await repumpKit(tester, const GlacierSwitch(ariaLabel: 'Airplane mode', disabled: true));
    expect(tester.getSemantics(control), isSemantics(label: 'Airplane mode', hasEnabledState: true, isEnabled: false, hasTapAction: false));
    handle.dispose();
  });
}
