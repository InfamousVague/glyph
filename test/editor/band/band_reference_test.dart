import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/band/band.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

/// The band against the page's own: every case fixtures/reference.mjs measured on the web `ContextMenu`, drawn
/// here the same way, its rectangles held to half a pixel, and a picture of each written to shots/ to be looked at
/// beside the page's (the png of the same name in fixtures/).
void main() {
  setUpAll(loadAppFonts);

  const within = 0.5;

  void near(Rect got, Rect want, String what) {
    for (final (g, w, side) in <(double, double, String)>[(got.left, want.left, 'left'), (got.top, want.top, 'top'), (got.right, want.right, 'right'), (got.bottom, want.bottom, 'bottom')]) {
      expect(g, closeTo(w, within), reason: '$what $side: $got against the page\'s $want');
    }
  }

  for (final name in BandFixture.names()) {
    testWidgets('the band as the page drew it: $name', (tester) async {
      final fixture = BandFixture.read(name);
      void none() {}
      final rig = await pumpBand(
        tester,
        doc: fixture.doc,
        anchor: fixture.anchor,
        head: fixture.head,
        top: fixture.top,
        inset: fixture.inset,
        size: fixture.window,
        theme: fixture.theme,
        readOnly: fixture.readOnly,
        onAddImage: fixture.props.contains('image') ? none : null,
        onFind: fixture.props.contains('find') ? (_) {} : null,
        onComment: fixture.props.contains('comment') ? (_) {} : null,
        send: fixture.props.contains('send') ? BandSend(label: 'Notion', run: (_) {}) : null,
        formats: pageFormats(),
        // The page's list item offered its fields and its board; the rows are drawn, and what they open is not here.
        fields: BandFields(items: (context, request) => const <Widget>[]),
        boards: true,
      );
      // The caret, where the page had it: the band is asked for over it.
      // (Read on the page after its presses: where they wrote, the caret had moved on, and it is not compared.)
      if (fixture.text == fixture.doc) {
        final caret = rig.view.coordsAtPos(fixture.head)!;
        expect(caret.top, closeTo(fixture.caret.top, within), reason: 'the caret\'s top');
        expect((caret.left + caret.right) / 2, closeTo((fixture.caret.left + fixture.caret.right) / 2, within), reason: 'the caret\'s middle');
      }

      await hold(tester, rig, finger: Offset(20, fixture.top + 20));
      for (final label in fixture.press) {
        await choose(tester, label);
      }
      final band = tester.state<MenuBandState>(find.byType(MenuBand));
      final scroll = fixture.scroll;
      if (scroll == 'end') band.scroll.jumpTo(band.scroll.position.maxScrollExtent);
      if (scroll is num) band.scroll.jumpTo(scroll.toDouble());
      await settle(tester);

      expect(rig.controller.page.label, fixture.label);
      expect(rig.text, fixture.text, reason: 'what the presses wrote');
      expect(words(tester), <String>[for (final item in fixture.items) item['label'] as String]);

      // The band: where it sits, how big it is, how far it scrolls and which ends fade.
      near(rig.controller.rect!, fixture.row, 'the band');
      final at = band.scroll.position;
      expect(at.pixels, closeTo((fixture.rowJson['scrollLeft'] as num).toDouble(), 1), reason: 'how far along it is');
      expect(at.maxScrollExtent + at.viewportDimension, closeTo((fixture.rowJson['scrollWidth'] as num).toDouble(), 1), reason: 'how long the band is');
      expect(band.more, fixture.rowJson['more'], reason: 'which ends have more');

      // Every row: its box, its icon's and its word's, and whether it is lit.
      final t = tester.element(find.byType(MenuBand)).tokens;
      final found = find.byType(BandItemBox);
      for (final (index, item) in fixture.items.indexed) {
        final one = found.at(index);
        final label = item['label'] as String;
        near(rowBox(tester, one), BandFixture.rect(item['rect'] as Map<String, dynamic>), label);
        near(iconBox(tester, one), BandFixture.rect(item['icon'] as Map<String, dynamic>), '$label\'s icon');
        near(wordBox(tester, one), BandFixture.rect(item['word'] as Map<String, dynamic>), '$label\'s word');
        final widget = tester.widget<BandItemBox>(one);
        expect(widget.lit, item['lit'], reason: '$label lit');
        expect(widget.group, item['group'], reason: '$label starts a kind');
        expect(widget.icon.name, item['iconName'], reason: '$label\'s icon');
        expect(widget.checkbox, item['role'] == 'menuitemcheckbox', reason: '$label\'s role');
        expect(widget.name, item['name'], reason: '$label\'s name');
        final style = tester.widget<Text>(find.descendant(of: one, matching: find.byType(Text))).style!;
        expect(style.fontSize, closeTo(((item['font'] as Map)['size'] as num).toDouble(), 0.01));
        expect(style.fontWeight, FontWeight.w700);
        expect(style.color, t.color(widget.lit ? 'app-paper' : 'app-ink'));
      }
      await shot(tester, name);
    });
  }

  testWidgets('the band is drawn in the page\'s own paper, rule and ink', (tester) async {
    final rig = await pumpBand(tester, doc: 'some words', anchor: 0, head: 4);
    await hold(tester, rig);
    final t = tester.element(find.byType(MenuBand)).tokens;
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(MenuBand), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
    expect(box.color, t.color('app-paper-2'));
    expect(box.border!.top.color, t.color('app-rule'));
    expect(box.border!.top.width, 1);
    expect(box.borderRadius, BorderRadius.circular(18));
    await away(tester);
  });

  // Not a case of the page's: that the fixtures are there at all, so a missing folder cannot pass for a clean run.
  test('the page was measured', () {
    expect(BandFixture.names().length, greaterThanOrEqualTo(20));
    expect(File('test/editor/band/fixtures/reference.mjs').existsSync(), isTrue);
  });
}
