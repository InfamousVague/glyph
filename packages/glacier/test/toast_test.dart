import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The kit's files are imported one by one rather than through glacier.dart, so this reads the same before and after
// the library exports the component.
import 'package:glacier/src/components/css_effects.dart';
import 'package:glacier/src/components/pressable.dart';
import 'package:glacier/src/components/toast.dart';
import 'package:glacier/src/tokens/css_value.dart';
import 'package:glacier/src/tokens/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/harness.dart';

/// A provider over a button that calls [show] with the toast controls, as a screen under `ToastProvider` would.
Widget app(void Function(GlacierToastController toast) show) => GlacierToastProvider(
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => show(GlacierToast.of(context)),
          child: const SizedBox(width: 80, height: 40, child: Text('show')),
        ),
      ),
    );

/// The same with the page's reduced-motion setting on.
Widget reduced(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
      child: GlacierTheme(sheet: testSheet, attrs: const {...testAttrs, 'theme': 'light'}, child: child),
    );

void main() {
  final t = testTokens();
  final pill = find.byType(GlacierToast);
  BoxDecoration decoration(WidgetTester tester) =>
      tester.widget<DecoratedBox>(find.descendant(of: pill, matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
  double opacity(WidgetTester tester) => tester.widget<Opacity>(find.ancestor(of: pill, matching: find.byType(Opacity)).first).opacity;

  Future<void> show(WidgetTester tester) async {
    await tester.tap(find.text('show'));
    await tester.pump();
  }

  testWidgets('a toast appears at the bottom centre, as wide as its content', (tester) async {
    await pumpKit(tester, app((toast) => toast.toast(message: const Text('Saved'))));
    expect(pill, findsNothing);
    await show(tester);
    expect(find.text('Saved'), findsOneWidget);
    await tester.pumpAndSettle();

    final rect = tester.getRect(pill);
    // One line of the small text on the body leading, which Flutter sets on whole pixels: 20, where the page's is
    // 20.09. The 1.25rem dismiss control beside it is 20 as well.
    final text = tester.getSize(find.text('Saved'));
    expect(text.height, closeTo(t.fontSize('sm') * t.len('glacier-leading-md'), 0.5));
    expect(text.height, 20);
    expect(rect.height, closeTo(text.height + t.space(2) * 2 + t.len('glacier-hairline') * 2, 0.001));
    // Border, padding, message, the row's gap and the dismiss control's own margin, the control, padding, border.
    final width = 1 + t.space(4) + text.width + t.space(3) + t.space(2) + t.lenOf('1.25rem') + t.space(4) + 1;
    expect(rect.width, closeTo(width, 0.001));
    expect(text.width, closeTo(t.fontSize('sm') * 5, 0.5));
    expect(rect.center.dx, closeTo(195, 0.001));
    expect(rect.bottom, closeTo(844 - t.space(6), 0.001));
    expect(opacity(tester), 1);
  });

  testWidgets('it rises 12 into place on the spring, and leaves the same way', (tester) async {
    await pumpKit(tester, app((toast) => toast.toast(message: const Text('Saved'))));
    await show(tester);
    final bottom = 844 - t.space(6);
    expect(opacity(tester), 0);
    expect(tester.getRect(pill).bottom, closeTo(bottom + 12, 0.001));
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity(tester), inExclusiveRange(0, 1));
    expect(tester.getRect(pill).bottom, inExclusiveRange(bottom, bottom + 12));
    await tester.pumpAndSettle();
    expect(tester.getRect(pill).bottom, closeTo(bottom, 0.001));

    GlacierToast.of(tester.element(find.text('show'))).dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(pill, findsOneWidget, reason: 'it is still leaving');
    expect(opacity(tester), inExclusiveRange(0, 1));
    expect(tester.getRect(pill).bottom, inExclusiveRange(bottom, bottom + 12));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });

  testWidgets('it dismisses itself after its tone\'s time', (tester) async {
    var tone = GlacierToastTone.neutral;
    await pumpKit(tester, app((toast) => toast.toast(tone: tone, message: const Text('Saved'))));
    for (final (next, ms) in [
      (GlacierToastTone.neutral, 4500),
      (GlacierToastTone.info, 4500),
      (GlacierToastTone.success, 3500),
      (GlacierToastTone.warning, 4500),
      (GlacierToastTone.danger, 7000),
    ]) {
      tone = next;
      await show(tester);
      await tester.pump(Duration(milliseconds: ms - 10));
      expect(pill, findsOneWidget, reason: '${next.name} stands until $ms');
      expect(opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(pill, findsNothing, reason: '${next.name} goes at $ms');
    }
  });

  testWidgets('duration overrides the tone, and zero keeps it up', (tester) async {
    Duration? duration = const Duration(milliseconds: 800);
    await pumpKit(tester, app((toast) => toast.toast(message: const Text('Saved'), duration: duration)));
    await show(tester);
    await tester.pump(const Duration(milliseconds: 790));
    expect(pill, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);

    duration = Duration.zero;
    await show(tester);
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(pill, findsOneWidget);
  });

  testWidgets('a new toast replaces the current one and starts its own clock', (tester) async {
    var n = 0;
    await pumpKit(tester, app((toast) => toast.toast(message: Text('Toast ${++n}'))));
    await show(tester);
    await tester.pump(const Duration(milliseconds: 4000));
    await show(tester);
    // Both stand in the same spot while the first fades out under the second.
    expect(pill, findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Toast 1'), findsNothing);
    expect(find.text('Toast 2'), findsOneWidget, reason: 'the first toast\'s clock does not take the second down');
    await tester.pump(const Duration(milliseconds: 3490));
    expect(find.text('Toast 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });

  testWidgets('a press on the pill or its close control dismisses it', (tester) async {
    await pumpKit(tester, app((toast) => toast.toast(message: const Text('Saved'), duration: Duration.zero)));
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);

    await show(tester);
    await tester.pumpAndSettle();
    final close = find.descendant(of: pill, matching: find.byType(GlacierPressable));
    expect(tester.getSize(close), Size.square(t.lenOf('1.25rem')));
    expect(tester.getSize(find.descendant(of: close, matching: find.byType(CustomPaint)).last), const Size.square(12));
    expect(tester.widget<Opacity>(find.descendant(of: close, matching: find.byType(Opacity))).opacity, 0.6);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });

  testWidgets('the action runs its handler and dismisses; dismissible false drops the close control', (tester) async {
    var undone = 0;
    await pumpKit(
      tester,
      app((toast) => toast.toast(
            message: const Text('Deleted'),
            action: GlacierToastAction(label: 'Undo', onPress: () => undone++),
            dismissible: false,
            duration: Duration.zero,
          )),
    );
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.descendant(of: pill, matching: find.byType(GlacierPressable)), findsOneWidget);
    final undo = find.text('Undo');
    final style = tester.widget<Text>(undo).style!;
    expect(style.color, t.color('glacier-accent-text'));
    expect(style.fontVariations, const [FontVariation('wght', 650)]);
    // The row's gap and the action's margin before its padded hit area.
    final hit = find.descendant(of: pill, matching: find.byType(GlacierPressable));
    expect(tester.getTopLeft(hit).dx - tester.getTopRight(find.text('Deleted')).dx, closeTo(t.space(3) + t.space(1), 0.001));
    expect(tester.getTopLeft(undo).dx - tester.getTopLeft(hit).dx, closeTo(t.space(2), 0.001));

    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(pill, findsNothing);
  });

  testWidgets('a long message wraps inside the room the row leaves it', (tester) async {
    await pumpKit(tester, app((toast) => toast.toast(message: Text('word ' * 20), icon: const Icon(LucideIcons.info), duration: Duration.zero)));
    await show(tester);
    await tester.pumpAndSettle();
    // A space-4 in from either side of a 390 window, which is less than the 28rem cap.
    expect(tester.getRect(pill).left, closeTo(t.space(4), 0.001));
    expect(tester.getRect(pill).right, closeTo(390 - t.space(4), 0.001));
    expect(tester.getSize(find.textContaining('word')).height, greaterThan(40), reason: 'more than one line');
    expect(tester.getTopLeft(find.byType(Icon)).dx, lessThan(tester.getTopLeft(find.textContaining('word')).dx));
    expect(tester.getRect(pill).bottom, closeTo(844 - t.space(6), 0.001));
  });

  testWidgets('in a wide window the pill stops at 28rem, centred', (tester) async {
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(900, 844)),
          child: GlacierTheme(
            sheet: testSheet,
            attrs: const {...testAttrs, 'theme': 'light'},
            child: app((toast) => toast.toast(message: Text('word ' * 20), duration: Duration.zero)),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.getSize(pill).width, closeTo(448, 0.001)); // 28rem, whatever the window
    expect(tester.getRect(pill).center.dx, closeTo(450, 0.001));
    expect(tester.getSize(find.textContaining('word')).height, greaterThan(40));
  });

  testWidgets('with no Overlay above it, the provider stacks the toast over its child', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: GlacierTheme(
            sheet: testSheet,
            attrs: const {...testAttrs, 'theme': 'light'},
            child: app((toast) => toast.toast(message: const Text('Saved'))),
          ),
        ),
      ),
    );
    expect(find.byType(OverlayPortal), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(tester.getRect(pill).center.dx, closeTo(195, 0.001));
    expect(tester.getRect(pill).bottom, closeTo(844 - t.space(6), 0.001));
    await tester.pump(const Duration(milliseconds: 4500));
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });

  testWidgets('under reduced motion it appears and goes at once', (tester) async {
    await pumpKit(tester, reduced(app((toast) => toast.toast(message: const Text('Saved')))));
    await show(tester);
    expect(opacity(tester), 1);
    expect(tester.getRect(pill).bottom, closeTo(844 - t.space(6), 0.001));
    GlacierToast.of(tester.element(find.text('show'))).dismiss();
    await tester.pump();
    await tester.pump();
    expect(pill, findsNothing);
  });

  for (final theme in ['light', 'dark']) {
    testWidgets('each tone paints its surface, border and text tokens in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      for (final tone in GlacierToastTone.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpKit(tester, GlacierToast(tone: tone, message: const Text('Saved')), theme: theme);
        final neutral = tone == GlacierToastTone.neutral;
        final box = decoration(tester);
        expect(box.color, tokens.color(neutral ? 'glacier-surface-raised' : 'glacier-${tone.name}-soft'), reason: tone.name);
        expect((box.border! as Border).top.color, tokens.color(neutral ? 'glacier-border-subtle' : 'glacier-${tone.name}-border'), reason: tone.name);
        expect(tester.widget<GlacierOuterShadows>(find.descendant(of: pill, matching: find.byType(GlacierOuterShadows))).shadows.outer, tokens.shadow('glacier-shadow-4'));
        expect(box.boxShadow, isNull, reason: 'the shadow is drawn round the pill, not under it');
        expect(box.borderRadius, BorderRadius.circular(tokens.radius('full')));
        final style = DefaultTextStyle.of(tester.element(find.text('Saved'))).style;
        expect(style.color, tokens.color(neutral ? 'glacier-text' : 'glacier-${tone.name}-text'), reason: tone.name);
        expect(style.fontWeight, tokens.weight('medium'));
      }
    });

    testWidgets('glass outranks the tone, in $theme', (tester) async {
      final tokens = testTokens(theme: theme);
      await pumpKit(tester, const GlacierToast(tone: GlacierToastTone.danger, glass: true, message: Text('Saved')), theme: theme);
      expect(find.descendant(of: pill, matching: find.byType(BackdropFilter)), findsOneWidget);
      final box = tester.widget<DecoratedBox>(find.descendant(of: pill, matching: find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).border != null))).decoration as BoxDecoration;
      expect(box.color, tokens.color('glacier-glass-regular'));
      expect((box.border! as Border).top.color, tokens.color('glacier-glass-border'));
      expect(DefaultTextStyle.of(tester.element(find.text('Saved'))).style.color, tokens.color('glacier-text'));
    });
  }

  testWidgets('a shadow falls round a see-through box and not under it', (tester) async {
    // A half-clear red box with a black shadow straight down, on nothing.
    const fill = Color(0x80FF0000);
    await tester.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: GlacierOuterShadows(
              radius: 4,
              shadows: [CssShadow(offset: Offset(0, 6), blur: 0, spread: 0, color: Color(0xFF000000))],
              child: SizedBox(width: 40, height: 20, child: DecoratedBox(decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.all(Radius.circular(4))))),
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
    final width = boundary.size.width.round();
    List<int> at(int x, int y) => [for (var c = 0; c < 4; c++) bytes.getUint8((y * width + x) * 4 + c)];
    // The box is at 20..60 by 20..40, its shadow at 20..60 by 26..46.
    final inside = at(40, 34);
    expect(inside[3], closeTo(128, 1), reason: 'the fill alone: a shadow under it would make this opaque');
    expect(inside[0], greaterThan(120), reason: 'and still red');
    expect(at(40, 43), [0, 0, 0, 255], reason: 'the shadow, where it shows below the box');
    expect(at(40, 48)[3], 0, reason: 'and nothing past it');
    expect(at(40, 15)[3], 0);
  });

  testWidgets('on its own the pill fills its row, up to 28rem', (tester) async {
    await pumpKit(tester, const GlacierToast(message: Text('Saved')));
    expect(tester.getSize(pill).width, 390);
  });

  testWidgets('it is announced, and its controls are named buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpKit(
      tester,
      app((toast) => toast.toast(message: const Text('Deleted'), action: GlacierToastAction(label: 'Undo', onPress: () {}), duration: Duration.zero)),
    );
    await show(tester);
    await tester.pumpAndSettle();
    // Off the web the status role says nothing, so the pill is a live region (the web build carries the role).
    expect(tester.getSemantics(pill), isSemantics(label: 'Deleted', isLiveRegion: true, hasTapAction: false));
    final buttons = find.descendant(of: pill, matching: find.byType(GlacierPressable));
    expect(tester.getSemantics(buttons.first), isSemantics(label: 'Undo', isButton: true, hasTapAction: true, isEnabled: true));
    expect(tester.getSemantics(buttons.last), isSemantics(label: 'Dismiss', isButton: true, hasTapAction: true, isEnabled: true));
    handle.dispose();
  });

  testWidgets('a toast asked for while the tree is building is shown once the frame is done', (tester) async {
    await pumpKit(
      tester,
      GlacierToastProvider(
        child: Builder(builder: (context) {
          GlacierToast.of(context).toast(message: const Text('Welcome'), duration: Duration.zero);
          return const SizedBox(width: 10, height: 10);
        }),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('GlacierToast.of outside a provider is an error', (tester) async {
    await pumpKit(tester, const SizedBox(width: 10, height: 10));
    expect(() => GlacierToast.of(tester.element(find.byType(SizedBox).last)), throwsFlutterError);
  });
}
