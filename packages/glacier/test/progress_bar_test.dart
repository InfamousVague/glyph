import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/progress_bar.dart';
import 'package:glacier/src/tokens/theme.dart';
import 'package:glacier/src/tokens/tokens.dart';

import 'support/harness.dart';

/// The box inside [of] that a decoration paints in [color].
Finder painted(Finder of, Color color) => find.descendant(
      of: of,
      matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color),
    );

/// [child] as the page is under `prefers-reduced-motion: reduce`.
Widget reduced(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
      child: GlacierTheme(sheet: testSheet, attrs: const {...testAttrs, 'theme': 'light'}, child: child),
    );

void main() {
  final t = testTokens();
  final bar = find.byType(GlacierProgressBar);
  Finder fill([Tokens? tokens, String token = 'glacier-accent-solid']) => painted(bar, (tokens ?? t).color(token));

  testWidgets('the track fills the row at the thickness the stylesheet gives', (tester) async {
    await pumpKit(tester, const GlacierProgressBar(value: 40));
    expect(tester.getSize(bar), Size(390, t.lenOf('0.625rem')));
    expect(tester.getSize(bar).height, 10);
    expect(tester.getSize(fill()), const Size(390 * 0.4, 10));
    expect(tester.getTopLeft(fill()), Offset.zero);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(value: 40, size: GlacierProgressBarSize.sm));
    expect(tester.getSize(bar), Size(390, t.lenOf('0.375rem')));
    expect(tester.getSize(bar).height, 6);
  });

  testWidgets('the fill is value over max, clamped to the track', (tester) async {
    await pumpKit(tester, const GlacierProgressBar(value: 3, max: 4));
    expect(tester.getSize(fill()).width, 390 * 0.75);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(value: 250));
    expect(tester.getSize(fill()).width, 390);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(value: -5));
    expect(tester.getSize(fill()).width, 0);
  });

  testWidgets('a new value eases the width over the normal duration', (tester) async {
    var value = 20.0;
    late StateSetter rebuild;
    await pumpKit(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return GlacierProgressBar(value: value);
      }),
    );
    expect(tester.getSize(fill()).width, 78);
    rebuild(() => value = 80);
    await tester.pump();
    expect(tester.getSize(fill()).width, 78, reason: 'it sets out from where it was');
    await tester.pump(t.duration('glacier-duration-normal') ~/ 2);
    final midway = tester.getSize(fill()).width;
    expect(midway, greaterThan(78));
    expect(midway, lessThan(312));
    // Eased out: more than half the way there by half the time.
    expect(midway, greaterThan((78 + 312) / 2));
    await tester.pump(t.duration('glacier-duration-normal') ~/ 2);
    expect(tester.getSize(fill()).width, 312);
    // A known bar runs no ticker: this would never settle if the sweep's were still going.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('with no value, a 40% fill sweeps from before the track to past it every 1.4s', (tester) async {
    await pumpKit(tester, const GlacierProgressBar());
    expect(tester.getSize(fill()).width, closeTo(156, 0.001));
    expect(tester.getTopLeft(fill()).dx, closeTo(-156, 0.001), reason: 'inset-inline-start: -40%');
    await tester.pump(const Duration(milliseconds: 700));
    // Halfway through an in-out easing is halfway along: -40% + 140% / 2 = 30%.
    expect(tester.getTopLeft(fill()).dx, closeTo(390 * 0.3, 0.5));
    await tester.pump(const Duration(milliseconds: 690));
    expect(tester.getTopLeft(fill()).dx, greaterThan(380));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.getTopLeft(fill()).dx, lessThan(-150), reason: 'and round again');
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('indeterminate wins over a value, and a value given later stops the sweep', (tester) async {
    var indeterminate = true;
    late StateSetter rebuild;
    await pumpKit(
      tester,
      StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return GlacierProgressBar(value: 50, indeterminate: indeterminate);
      }),
    );
    expect(tester.getSize(fill()).width, closeTo(156, 0.001));
    rebuild(() => indeterminate = false);
    await tester.pumpAndSettle();
    expect(tester.getSize(fill()).width, 195);
    expect(tester.getTopLeft(fill()).dx, 0);
  });

  testWidgets('under reduced motion the unknown bar stands full and pulses instead', (tester) async {
    await pumpKit(tester, reduced(const GlacierProgressBar()));
    final accent = t.color('glacier-accent-solid');
    Color shade() {
      final boxes = tester.widgetList<DecoratedBox>(find.descendant(of: bar, matching: find.byType(DecoratedBox))).toList();
      return (boxes.last.decoration as BoxDecoration).color!;
    }

    expect(tester.getSize(find.descendant(of: bar, matching: find.byType(DecoratedBox)).last), const Size(390, 10));
    expect(shade().a, closeTo(accent.a * 0.3, 0.005));
    await tester.pump(const Duration(milliseconds: 700));
    expect(shade().a, closeTo(accent.a * 0.7, 0.005));
    await tester.pump(const Duration(milliseconds: 350));
    expect(shade().a, closeTo(accent.a * 0.5, 0.005));
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('track and fill are the tokens in $theme, for every tone', (tester) async {
      final tokens = testTokens(theme: theme);
      for (final (tone, token) in [
        (GlacierProgressBarTone.accent, 'glacier-accent-solid'),
        (GlacierProgressBarTone.success, 'glacier-success-solid'),
        (GlacierProgressBarTone.warning, 'glacier-warning-solid'),
        (GlacierProgressBarTone.danger, 'glacier-danger-solid'),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpKit(tester, GlacierProgressBar(value: 40, tone: tone), theme: theme);
        final track = tester.widget<Container>(find.descendant(of: bar, matching: find.byType(Container))).decoration! as BoxDecoration;
        expect(track.color, tokens.color('glacier-segment-track'));
        expect(track.borderRadius, BorderRadius.circular(tokens.radius('full')));
        final box = tester.widget<DecoratedBox>(find.descendant(of: bar, matching: find.byType(DecoratedBox)).last).decoration as BoxDecoration;
        expect(box.color, tokens.color(token), reason: tone.name);
        expect(tester.getSize(find.descendant(of: bar, matching: find.byType(DecoratedBox)).last).width, 156);
      }
    });
  }

  testWidgets('it is a progress bar with its range and value to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(tester, const GlacierProgressBar(value: 40, ariaLabel: 'Uploading'));
    expect(tester.getSemantics(bar), isSemantics(role: SemanticsRole.progressBar, label: 'Uploading', value: '40', minValue: '0', maxValue: '100'));

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(value: 7.5, max: 8));
    expect(tester.getSemantics(bar), isSemantics(role: SemanticsRole.progressBar, value: '7.5', minValue: '0', maxValue: '8'));

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(value: 400));
    expect(tester.getSemantics(bar), isSemantics(value: '100'), reason: 'aria-valuenow is the clamped value');

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpKit(tester, const GlacierProgressBar(ariaLabel: 'Loading'));
    expect(tester.getSemantics(bar), isSemantics(role: SemanticsRole.loadingSpinner, label: 'Loading', value: ''));
    handle.dispose();
  });
}
