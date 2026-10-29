// A table's words stand on the rows of pixels the page's stand on: each cell's words are a paragraph set on the
// page's baseline, by where the paragraph inks its baseline and not where it says it is (lib/editor/looks/look.dart
// `inkBaseline`; test/editor/view/ink_rows_test.dart holds a line's own words the same way).
//
// Against the page's own picture of each case (test/editor/tables/fixtures/<name>.png): the bands of rows its ink
// is on are found there, and the ink drawn here over the same rows is compared with each by where its weight is
// centred. With a cell placed by what the paragraph says, the cases in Inter stood 1.8 device pixels off the
// page, and the larger text 0.8; they are within 0.3.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/tables/tables.dart' show GlyphTable, RenderGlyphTable;

import '../../support/ink.dart';
import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  final only = Platform.environment['EDITOR_CASE'];
  for (final name in TableFixture.names()) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    // The cases under phone/ are a phone's own page, drawn by their own harness at its density: not held here.
    if (name.contains('caret') || name.contains('inside') || name.contains('selection') || name.startsWith('phone/')) continue;
    testWidgets('$name: the words are on the rows the page\'s are', (tester) async {
      final fixture = TableFixture.read(name);
      await pumpTableFixture(tester, fixture);
      final own = await Pixels.screen(tester);
      final page = await Pixels.file(tester, 'test/editor/tables/fixtures/$name.png');
      final height = page.height < own.height ? page.height : own.height;
      // A link in a cell is underlined here and plain on the page (table_box.dart: links in cells are added), so
      // the columns under a link are left out of both pictures: the words beside it are what is compared.
      final scale = own.width / (tester.view.physicalSize.width / tester.view.devicePixelRatio);
      final skip = <(int, int)>[
        for (final table in tester.renderObjectList<RenderGlyphTable>(find.byType(GlyphTable)))
          for (final row in table.table.cells)
            for (final cell in row)
              for (final boxes in cell.linkBoxes)
                for (final box in boxes) (((table.localToGlobal(box.topLeft).dx) * scale).floor() - 2, ((table.localToGlobal(box.topRight).dx) * scale).ceil() + 2),
      ];
      var worst = 0.0, count = 0;
      final faults = <String>[];
      for (final band in bands(page, 0, height)) {
        final top = band.first - 3 < 0 ? 0 : band.first - 3, bottom = band.last + 4 > height ? height : band.last + 4;
        final theirs = inked(page.ink(top, bottom, skip: skip), top), ours = inked(own.ink(top, bottom, skip: skip), top);
        if (theirs == null || ours == null) continue;
        count += 1;
        final by = ours.centre - theirs.centre;
        if (by.abs() > worst) worst = by.abs();
        if (by.abs() > 0.5) faults.add('the page\'s rows ${theirs.first}-${theirs.last}: here ${ours.first}-${ours.last}, ${by >= 0 ? '+' : ''}${by.toStringAsFixed(2)}');
      }
      // ignore: avoid_print
      print('$name: $count bands of words, the worst ${worst.toStringAsFixed(2)} device px off the page');
      expect(count, greaterThan(1));
      expect(faults, isEmpty);
      debugDisableShadows = true;
    });
  }
}
