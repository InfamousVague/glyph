import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:glacier/src/components/field_core.dart';

import 'support/harness.dart';

void main() {
  Future<void> inter(WidgetTester tester) => tester.runAsync(() async {
    final loader = FontLoader('Inter Variable')..addFont(Future.value(ByteData.view(File('../../assets/fonts/InterVariable-latin.ttf').readAsBytesSync().buffer)));
    await loader.load();
  });

  testWidgets('a normal line and its baseline are the page\'s on a phone: the descent rounded down takes a pixel from the ascent', (tester) async {
    await inter(tester);
    await pumpKit(tester, const SizedBox.shrink());
    final t = testTokens();
    // Measured in Ghost.md's page on Android at 2.625 (height and baseline in device pixels): a Settings row's
    // label 51 and 40 where the two rounded alone are 41 and 10, its summary 43 and 34, and three more.
    final measured = <double, (int, int)>{16.2569: (51, 40), 13.4704: (43, 34), 10.0: (31, 24), 11.85: (38, 30), 19.62: (62, 49)};
    for (final entry in measured.entries) {
      final line = normalLineBox(kitFont(t, fontSize: entry.key, color: const Color(0xFF000000)), dpr: 2.625);
      expect(line.height * 2.625, closeTo(entry.value.$1, 1e-6), reason: '${entry.key} height');
      expect(line.baseline * 2.625, closeTo(entry.value.$2, 1e-6), reason: '${entry.key} baseline');
    }
    // A desktop's ratio: whole pixels, and the baseline is the ascent rounded.
    expect(normalLineBox(kitFont(t, fontSize: 16, color: const Color(0xFF000000))), (height: 20.0, baseline: 16.0));
  });

  testWidgets('a line with a height of its own has its words where a phone\'s page has them: half the leading floored to a device pixel', (tester) async {
    await inter(tester);
    await pumpKit(tester, const SizedBox.shrink());
    final t = testTokens();
    // Measured in Ghost.md's page on Android at 2.625: Settings' title, bold at 28.2918px on a line of 32.5356px
    // (85.39 device pixels), has a content area of 90 device pixels that starts 3.00 over the line's top, so its
    // baseline is 72 - 3 = 69 under it.
    final title = kitFont(t, fontSize: 28.2918, color: const Color(0xFF000000)).copyWith(fontWeight: FontWeight.w700);
    expect(normalLineBox(title, dpr: 2.625).height * 2.625, closeTo(90, 1e-6));
    expect(leadedBaseline(title, 32.5356, dpr: 2.625) * 2.625, closeTo(69, 1e-6));
    // A line roomier than its face: 13.8713px on 20.807 (54.62 device pixels) round a content area of 44, the
    // five pixels of half its leading floored from 5.31.
    final small = kitFont(t, fontSize: 13.8713, color: const Color(0xFF000000));
    final area = normalLineBox(small, dpr: 2.625);
    expect(leadedBaseline(small, 20.807, dpr: 2.625) * 2.625, closeTo(area.baseline * 2.625 + ((54.6184 - area.height * 2.625) / 2).floorToDouble(), 1e-6));
  });

  testWidgets('text takes the exact line where the engine rounds it, one line or several', (tester) async {
    await inter(tester);
    const style = TextStyle(fontFamily: 'Inter Variable', fontSize: 16.2569, height: 19.4286 / 16.2569, leadingDistribution: TextLeadingDistribution.even);
    await pumpKit(
      tester,
      SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Account', key: ValueKey('plain'), style: style),
            ExactLines.of(const Text('Account', key: ValueKey('one'), style: style)),
            ExactLines.of(const Text('Where your notes are kept on this phone', key: ValueKey('three'), style: style)),
          ],
        ),
      ),
    );
    // The engine's own line is a whole pixel.
    expect(tester.getSize(find.byKey(const ValueKey('plain'))).height, 19);
    Size box(String key) => tester.getSize(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(ExactLines)));
    expect(box('one').height, closeTo(19.4286, 1e-9));
    final lines = (tester.getSize(find.byKey(const ValueKey('three'))).height / 19).round();
    expect(lines, greaterThan(1));
    expect(box('three').height, closeTo(lines * 19.4286, 1e-9));
  });
}
