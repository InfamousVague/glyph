import 'dart:io';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/pressable.dart';
import 'package:glacier/src/components/segmented_control.dart';
import 'package:glacier/src/tokens/css_value.dart';
import 'package:glacier/src/tokens/sheet.dart';
import 'package:glacier/src/tokens/theme.dart';
import 'package:glacier/src/tokens/tokens.dart';

import 'support/harness.dart';

const options = [
  GlacierSegmentedOption(value: 'track', label: Text('One')),
  GlacierSegmentedOption(value: 'album', label: Text('Whole')),
  GlacierSegmentedOption(value: 'never', label: Text('Off')),
];

/// The box inside [of] that a decoration paints in [color].
Finder painted(Finder of, Color color) => find.descendant(
      of: of,
      matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color),
    );

/// [control] after something else that takes the keyboard, for a Tab to set out from.
Widget before(Widget control) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const Focus(debugLabel: 'before', child: SizedBox(width: 10, height: 10)), control],
    );

/// What Tab does from the thing before the control: the harness has no app above it to bind the key.
Future<void> tabInto(WidgetTester tester) async {
  final first = Focus.of(tester.element(find.byType(SizedBox).first));
  expect(first.debugLabel, 'before');
  first.requestFocus();
  await tester.pumpAndSettle();
  first.nextFocus();
  await tester.pumpAndSettle();
}

Color labelColor(WidgetTester tester, String text) => DefaultTextStyle.of(tester.element(find.text(text))).style.color!;

void main() {
  final t = testTokens();
  final control = find.byType(GlacierSegmentedControl);
  // The test font draws every glyph one em square, so a label is its letters times its size wide.
  final label = t.fontSize('sm') * 'Whole'.length;
  final column = label + t.space(4) * 2;
  final inset = t.len('glacier-hairline') + t.lenOf('0.1875rem');
  Finder thumb([Tokens? tokens]) => painted(control, (tokens ?? t).color('glacier-segment-thumb'));

  testWidgets('every segment is as wide as the widest label, and the track a control tall', (tester) async {
    await pumpKit(tester, const GlacierSegmentedControl(options: options));
    final size = tester.getSize(control);
    expect(size.width, closeTo(column * 3 + inset * 2, 0.001));
    // The segment gives back the track's padding, and the hairline border sits outside both.
    expect(size.height, closeTo(t.len('glacier-control-height-md') + t.len('glacier-hairline') * 2, 0.001));
    expect(tester.getSize(thumb()).width, closeTo(column, 0.001));
    expect(tester.getSize(thumb()).height, t.lenOf('calc(var(--glacier-control-height-md) - 0.375rem)'));
    expect(tester.getTopLeft(thumb()), Offset(inset, inset));
    // Each label is centred in its own column.
    expect(tester.getCenter(find.text('One')).dx, closeTo(inset + column / 2, 0.001));
    expect(tester.getCenter(find.text('Off')).dx, closeTo(inset + column * 2.5, 0.001));
    expect(tester.getCenter(find.text('Off')).dy, closeTo(size.height / 2, 0.001));
  });

  testWidgets('the sizes follow the control heights and their own paddings and type', (tester) async {
    for (final (size, step, font) in [(GlacierSegmentedSize.sm, 3, 'xs'), (GlacierSegmentedSize.lg, 5, 'md')]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpKit(tester, GlacierSegmentedControl(options: options, size: size));
      final box = tester.getSize(control);
      expect(box.height, closeTo(t.len('glacier-control-height-${size.name}') + 2, 0.001), reason: size.name);
      expect(box.width, closeTo((t.fontSize(font) * 5 + t.space(step) * 2) * 3 + inset * 2, 0.001), reason: size.name);
      expect(DefaultTextStyle.of(tester.element(find.text('Off'))).style.fontSize, t.fontSize(font));
    }
  });

  testWidgets('fullWidth shares the row out equally', (tester) async {
    await pumpKit(tester, const GlacierSegmentedControl(options: options, fullWidth: true));
    expect(tester.getSize(control).width, 390);
    expect(tester.getSize(thumb()).width, closeTo((390 - inset * 2) / 3, 0.001));
  });

  testWidgets('in a row too narrow for it, it keeps its width and its labels whole', (tester) async {
    await pumpKit(tester, const SizedBox(width: 200, child: GlacierSegmentedControl(options: options)));
    expect(tester.takeException(), isNull);
    // The track, its border and all, is as wide as its three columns ask, whatever the row gives it.
    final track = painted(control, t.color('glacier-segment-track'));
    expect(tester.getSize(track).width, closeTo(column * 3 + inset * 2, 0.001));
    expect(tester.getSize(track).width, greaterThan(200));
    expect(tester.getSize(find.text('Whole')).width, closeTo(label, 0.5));
  });

  testWidgets('fullWidth in a row narrower than its labels lets them run over, centred', (tester) async {
    await pumpKit(tester, const SizedBox(width: 120, child: GlacierSegmentedControl(options: options, fullWidth: true)));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(control).width, 120);
    final share = (120 - inset * 2) / 3;
    expect(tester.getSize(find.text('Whole')).width, closeTo(label, 0.5), reason: 'the label is not squeezed');
    expect(label, greaterThan(share));
    expect(tester.getCenter(find.text('Whole')).dx, closeTo(inset + share * 1.5, 0.001), reason: 'and stays centred on its segment');
  });

  testWidgets('a tap selects, and the thumb springs to the segment', (tester) async {
    final changes = <String>[];
    await pumpKit(tester, GlacierSegmentedControl(options: options, onValueChange: changes.add));
    expect(tester.getTopLeft(thumb()).dx, inset);

    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(changes, ['never']);
    await tester.pump(const Duration(milliseconds: 40));
    final midway = tester.getTopLeft(thumb()).dx;
    expect(midway, greaterThan(inset));
    expect(midway, lessThan(inset + column * 2));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb()).dx, closeTo(inset + column * 2, 0.001));

    // The segment that is already selected does not report again.
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(changes, ['never']);
  });

  testWidgets('the label is semibold ink when selected and medium muted ink when not', (tester) async {
    await pumpKit(tester, const GlacierSegmentedControl(options: options, defaultValue: 'album'));
    TextStyle style(String text) => DefaultTextStyle.of(tester.element(find.text(text))).style;
    expect(style('Whole').color, t.color('glacier-text'));
    expect(style('Whole').fontWeight, t.weight('semibold'));
    expect(style('Whole').height, 1);
    expect(style('One').color, t.color('glacier-text-muted'));
    expect(style('One').fontWeight, t.weight('medium'));

    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(style('One').color, t.color('glacier-text'));
    expect(style('Whole').color, t.color('glacier-text-muted'));
  });

  testWidgets('controlled, it reports the press and waits for its parent', (tester) async {
    var value = 'track';
    final asked = <String>[];
    late StateSetter rebuild;
    await pumpKit(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return GlacierSegmentedControl(options: options, value: value, onValueChange: asked.add);
      }),
    );
    await tester.tap(find.text('Whole'));
    await tester.pumpAndSettle();
    expect(asked, ['album']);
    expect(tester.getTopLeft(thumb()).dx, inset, reason: 'the parent has not agreed yet');

    rebuild(() => value = 'album');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(thumb()).dx, closeTo(inset + column, 0.001));
  });

  testWidgets('disabled options are skipped by a press and by the arrows', (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final changes = <String>[];
    await pumpKit(
      tester,
      before(GlacierSegmentedControl(
        onValueChange: changes.add,
        options: const [
          GlacierSegmentedOption(value: 'a', label: Text('One')),
          GlacierSegmentedOption(value: 'b', label: Text('Two'), disabled: true),
          GlacierSegmentedOption(value: 'c', label: Text('Six')),
        ],
      )),
    );
    expect(labelColor(tester, 'Two'), t.color('glacier-text-disabled'));
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    // Tab lands on the selected segment; the arrows carry selection and focus together, round the ends.
    await tabInto(tester);
    expect(find.descendant(of: find.byType(GlacierFocusRing), matching: find.byType(CustomPaint)), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes, ['c']);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'segment 2');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(changes, ['c', 'a']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes, ['c', 'a', 'c']);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'segment 2');
  });

  testWidgets('Tab stops once, on the selection, and Space selects the focused segment', (tester) async {
    final changes = <String>[];
    await pumpKit(tester, before(GlacierSegmentedControl(options: options, defaultValue: 'album', onValueChange: changes.add)));
    await tabInto(tester);
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'segment 1');
    FocusManager.instance.primaryFocus!.nextFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'before', reason: 'the group is one stop, so Tab leaves it');
    FocusManager.instance.primaryFocus!.nextFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'segment 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(changes, ['track']);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, ['track'], reason: 'already selected');
  });

  testWidgets('a disabled control takes no press', (tester) async {
    final changes = <String>[];
    await pumpKit(tester, GlacierSegmentedControl(options: options, disabled: true, onValueChange: changes.add));
    await tester.tap(find.text('Whole'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(labelColor(tester, 'One'), t.color('glacier-text-disabled'));
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('track, border and thumb are the segment tokens in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      await pumpKit(tester, const GlacierSegmentedControl(options: options), theme: theme);
      final track = tester.widget<DecoratedBox>(painted(control, tokens.color('glacier-segment-track'))).decoration as BoxDecoration;
      expect((track.border! as Border).top.color, tokens.color('glacier-glass-border'));
      expect((track.border! as Border).top.width, tokens.len('glacier-hairline'));
      final thumbBox = tester.widget<DecoratedBox>(thumb(tokens)).decoration as BoxDecoration;
      expect(thumbBox.boxShadow, tokens.shadow('glacier-shadow-2'));
      expect(labelColor(tester, 'One'), tokens.color('glacier-text'));
    });

    testWidgets('the selected label and the thumb shadow can be restyled, as ink.css does, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      final paper = tokens.color('app-paper');
      await pumpKit(tester, GlacierSegmentedControl(options: options, selectedLabelColor: paper, thumbShadow: const []), theme: theme);
      expect(labelColor(tester, 'One'), paper);
      expect(labelColor(tester, 'Whole'), tokens.color('glacier-text-muted'));
      expect((tester.widget<DecoratedBox>(thumb(tokens)).decoration as BoxDecoration).boxShadow, isEmpty);
    });
  }

  testWidgets('on the kit\'s own tokens the track is frosted and the thumb carries its highlight', (tester) async {
    // Without Ghost.md's ink over them: a see-through track, a glass highlight, and ink for the selected label.
    final kitSheet = TokenSheet.parse(File('assets/css/tokens.css').readAsStringSync());
    final kit = Tokens.root(kitSheet, attrs: const {'theme': 'light'}, css: const CssContext(vw: 390, vh: 844));
    await pumpKit(tester, GlacierTheme(sheet: kitSheet, attrs: const {'theme': 'light'}, child: const GlacierSegmentedControl(options: options)));
    expect(kit.color('glacier-segment-track').a, lessThan(1));
    expect(find.descendant(of: control, matching: find.byType(BackdropFilter)), findsOneWidget);
    expect(painted(control, kit.color('glacier-segment-track')), findsOneWidget);
    final thumbBox = painted(control, kit.color('glacier-segment-thumb'));
    expect((tester.widget<DecoratedBox>(thumbBox).decoration as BoxDecoration).boxShadow, kit.shadow('glacier-shadow-2'));
    expect(find.descendant(of: thumbBox, matching: find.byType(CustomPaint)), findsOneWidget, reason: 'the inset highlight is painted');
    expect(labelColor(tester, 'One'), kit.color('glacier-text'));
    // The frost is laid under the control, so it takes no room.
    expect(tester.getSize(control).height, closeTo(kit.len('glacier-control-height-md') + 2, 0.001));
  });

  testWidgets('it is a radio group of radios to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(tester, const GlacierSegmentedControl(options: options, ariaLabel: 'Repeat'));
    expect(tester.getSemantics(control), isSemantics(role: SemanticsRole.radioGroup, label: 'Repeat'));
    expect(
      tester.getSemantics(find.text('One')),
      isSemantics(label: 'One', hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, isFocusable: true),
    );
    expect(tester.getSemantics(find.text('Whole')), isSemantics(label: 'Whole', hasCheckedState: true, isChecked: false, isInMutuallyExclusiveGroup: true));

    await tester.tap(find.text('Whole'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Whole')), isSemantics(isChecked: true));
    expect(tester.getSemantics(find.text('One')), isSemantics(isChecked: false));
    handle.dispose();
  });
}
