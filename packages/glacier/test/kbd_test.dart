import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/src/components/field_core.dart';
import 'package:glacier/src/components/kbd.dart';
import 'package:glacier/src/tokens/line_height.dart';

import 'support/harness.dart';

KitBoxPainter capOf(WidgetTester tester) =>
    tester.widgetList<CustomPaint>(find.descendant(of: find.byType(GlacierKbd), matching: find.byType(CustomPaint))).map((p) => p.painter).whereType<KitBoxPainter>().single;

TextStyle textOf(WidgetTester tester) => tester.widget<RichText>(find.descendant(of: find.byType(GlacierKbd), matching: find.byType(RichText))).text.style!;

void main() {
  group('GlacierKbd', () {
    testWidgets('is a key cap: mono at 0.8em on a sunken chip, a hairline round it and 2px under it', (tester) async {
      await pumpKit(tester, const GlacierKbd(child: Text('esc')));
      final t = testTokens();
      final em = 16 * 0.8; // of the root's 1rem, nothing around it having set a size
      final style = textOf(tester);
      expect(style.fontSize, moreOrLessEquals(em));
      expect(style.fontFamily, t.families('glacier-font-mono').first);
      expect(style.height, 1);
      expect(style.color, t.color('glacier-text-muted'));

      final cap = capOf(tester);
      expect(cap.fill, t.color('glacier-surface-sunken'));
      expect(cap.border, t.color('glacier-border'));
      expect(cap.borderWidth, t.len('glacier-hairline'));
      expect(cap.borderBottomWidth, 2);
      expect(cap.radius, t.radius('sm'));

      // inline-block: as big as its words and its padding (0.25em 0.5em) and its border, and no bigger. The line is
      // the font size to the fraction, as `line-height: 1` is on the page.
      final box = tester.getSize(find.byType(GlacierKbd));
      final words = tester.getSize(find.text('esc'));
      expect(box.width, moreOrLessEquals(words.width + em + 2));
      expect(box.height, moreOrLessEquals(em + em * 0.5 + 1 + 2));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('measures by the text it sits in', (tester) async {
      await pumpKit(tester, const DefaultTextStyle(style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600), child: GlacierKbd(child: Text('⌘K'))));
      expect(textOf(tester).fontSize, 16);
      expect(textOf(tester).fontWeight, FontWeight.w600, reason: 'the weight is inherited, as a <kbd>’s is');
      expect(tester.getSize(find.byType(GlacierKbd)).height, moreOrLessEquals(16 + 8 + 1 + 2));
    });

    testWidgets('glass is the frosted material, with the full ink', (tester) async {
      await pumpKit(tester, const GlacierKbd(glass: true, child: Text('Shift')), theme: 'dark');
      final t = testTokens(theme: 'dark');
      expect(textOf(tester).color, t.color('glacier-text'));
      final cap = capOf(tester);
      expect(cap.fill, t.color('glacier-glass-regular'));
      expect(cap.border, t.color('glacier-glass-border'));
      expect(cap.highlight, t.color('glacier-glass-highlight'));
      expect(find.descendant(of: find.byType(GlacierKbd), matching: find.byType(BackdropFilter)), findsOneWidget);
    });

    testWidgets('takes an app’s own style over the kit’s, as Ghost.md’s typefaces.css sets one on kbd', (tester) async {
      const features = [FontFeature('calt'), FontFeature('liga')];
      await pumpKit(tester, const GlacierKbd(style: TextStyle(letterSpacing: 0, fontFeatures: features), child: Text('->')));
      expect(textOf(tester).fontFeatures, features);
      expect(textOf(tester).letterSpacing, 0);
      expect(textOf(tester).fontFamily, testTokens().families('glacier-font-mono').first, reason: 'what it does not set stays the kit’s');
    });

    testWidgets('is read as its words', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKit(tester, const GlacierKbd(child: Text('esc')));
      expect(find.bySemanticsLabel('esc'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the browser’s line-height: normal', () {
    testWidgets('is the ascent and the descent each rounded, as measured on the page with Inter', (tester) async {
      // Inter as the app ships it. Chromium laid a palette heading (11.1342px) out 14px tall and a row (13.3948px)
      // 16px; Flutter's own line for the first is 13.
      await tester.runAsync(() async {
        final loader = FontLoader('Inter Variable')..addFont(Future.value(ByteData.view(File('../../assets/fonts/InterVariable-latin.ttf').readAsBytesSync().buffer)));
        await loader.load();
      });
      await pumpKit(tester, const SizedBox.shrink());
      final t = testTokens();
      expect(t.families('glacier-font-sans').first, 'Inter Variable');
      final heading = kitFont(t, fontSize: 11.1342, color: t.color('glacier-text'));
      final row = kitFont(t, fontSize: 13.3948, color: t.color('glacier-text'));
      final body = kitFont(t, fontSize: 16, color: t.color('glacier-text'));
      expect(normalLineHeight(heading), 14);
      expect(normalLineHeight(row), 16);
      expect(normalLineHeight(body), 20);
      // On the phone the pixel that is rounded to is the device's: Chromium at the emulator's 2.625 laid a 16.26px
      // title out 51 device pixels tall (19.43px), and a Settings row's 13.01px detail 42 (16px), where rounding in
      // logical pixels gives 20 and 16.
      final title = kitFont(t, fontSize: 16.26, color: t.color('glacier-text'));
      expect(normalLineHeight(title), 20);
      expect(normalLineHeight(title, dpr: 2.625) * 2.625, closeTo(51, 1e-9));
      expect(normalLineHeight(body, dpr: 2) * 2, closeTo(39, 1e-9));

      double laidOut(TextStyle style) {
        final painter = TextPainter(text: TextSpan(text: 'File', style: style), textDirection: TextDirection.ltr)..layout();
        final height = painter.height;
        painter.dispose();
        return height;
      }

      expect(laidOut(heading), 14);
      expect(laidOut(row), 16);
      expect(laidOut(body), 20);
      // What it corrects: left to itself the engine rounds the sum.
      expect(laidOut(heading.copyWith(height: kTextHeightNone)), 13);
    });
  });
}
