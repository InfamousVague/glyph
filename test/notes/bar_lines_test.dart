// A line of the top bar's text (lib/notes/tabs/bar_parts.dart `normalLine`, `baselineIn`) is rounded in the screen's
// own pixels. Held by the page itself.
//
// The page: the Tauri app's WebView (Chrome 133) on an emulator at 1248 x 1972 and 2.625, a note's tab, 2026-10-09.
// `.title` is Inter at 16.2569px, `line-height: normal`: its box is 51.00 device pixels tall (19.43px), where the
// ascent and descent rounded in CSS pixels are 16 and 4, a line of 20 (52.5 device pixels). Of the 51 the ascent is
// 40: 41.3 and 10.3 round to 41 and 10, and a descent rounded down takes one from the ascent on Android. The tab's
// name stood two to three device pixels low beside the page in the Classic, Ledger and Islands bars.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/notes/tabs/bar_parts.dart';
import 'package:ghost_md/notes/tabs/tab_row.dart' show TabShape;
import 'package:glacier/glacier.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

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

  // The page there: a tab is 108.37 device pixels tall (`--app-tab-h`, 41.28px), and one that wears a workspace's
  // pill 109.08: the pill is its 13.47px line, 0.52em above and below and a border of two device pixels each side
  // (76.11), in the name's padding of 5.90px, under the tab's own top border of two device pixels. With borders of a
  // whole CSS pixel the row came to 111 and the tab's outline stood two device pixels high.
  testWidgets('a row of tabs is as tall as the page’s on a phone, a border counted as the phone draws it', (tester) async {
    late Tokens t;
    await pumpApp(tester, size: const Size(1248 / ratio, 1972 / ratio), ratio: ratio, measuredAt: ratio, prefs: const Preferences(theme: 'dark', textSize: 'large'), home: Builder(builder: (context) {
      t = context.tokens;
      return const SizedBox.expand();
    }));
    expect(NoteTabs.rowHeight(t, TabShape.tab, pills: false) * ratio, closeTo(108.37, 0.05));
    expect(NoteTabs.rowHeight(t, TabShape.tab, pills: true) * ratio, closeTo(109.08, 0.05));
    debugDisableShadows = true;
  });
}
