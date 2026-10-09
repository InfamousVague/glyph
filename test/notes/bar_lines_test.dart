// A line of the top bar's text (lib/notes/tabs/bar_parts.dart `normalLine`, `baselineIn`) is rounded in the screen's
// own pixels. Held by the page itself.
//
// The page: the Tauri app's WebView (Chrome 133) on an emulator at 1248 x 1972 and 2.625, a note's tab, 2026-10-09.
// `.title` is Inter at 16.2569px, `line-height: normal`: its box is 51.00 device pixels tall (19.43px), where the
// ascent and descent rounded in CSS pixels are 16 and 4, a line of 20 (52.5 device pixels). Of the 51 the ascent is
// 40: 41.3 and 10.3 round to 41 and 10, and a descent rounded down takes one from the ascent on Android. The tab's
// name stood two to three device pixels low beside the page in the Classic, Ledger and Islands bars.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/notes/tabs/bar_parts.dart';

void main() {
  const size = 16.2569, ratio = 2.625;

  test('a phone’s line of the bar is whole device pixels, its baseline with them', () {
    expect(normalLine(size, dpr: ratio) * ratio, closeTo(51, 1e-9));
    expect(baselineIn(size, null, ratio) * ratio, closeTo(40, 1e-9));
    // In a line taller than its face the words start half the difference down, floored to a device pixel.
    expect(baselineIn(size, 24, ratio) * ratio, closeTo(40 + ((24 * ratio - 51) / 2).floorToDouble(), 1e-9));
  });

  test('at a desktop’s ratio, where the tests’ rectangles were measured, they are CSS pixels as before', () {
    expect(normalLine(size), 20);
    expect(baselineIn(size), 16);
    expect(baselineIn(13, 13), 13 + ((13 - 16) / 2).floorToDouble(), reason: 'ascent 13, descent 3: a line of 13 starts two over its face');
  });
}
