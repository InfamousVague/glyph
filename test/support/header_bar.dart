import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/shell/header_toolbar.dart';

/// Whether the test under way is on today's bar ([pinTodaysBar]): [pumpApp] (test/support/render.dart) starts the
/// preferences again, which puts the device's words back to their defaults, and chooses today's bar again after it.
bool todaysBarPinned = false;

/// Today's bar for the test this is called in, and the default again after it: for a test about today's bar itself
/// (its rings by what they say, the home page's own search field, the web page's measurements of a bar that is
/// today's), since Grouped command became the default (Matt, 2026-10-29: "make the grouped command the default header
/// layout"). It holds through [pumpApp]; an app launched over SharedPreferences reads the device's kept word instead,
/// so there `glyph-header-toolbar` is kept as `today` before the launch.
void pinTodaysBar() {
  todaysBarPinned = true;
  headerToolbarChoice.set(HeaderToolbarVersion.today.id);
  addTearDown(() {
    todaysBarPinned = false;
    headerToolbarChoice.set(HeaderToolbarVersion.fallback.id);
  });
}

/// Presses the bar's control [id] (lib/shell/header_toolbar.dart's `HeaderAct.id`: `more`, `aside`, `links` …)
/// whichever version draws the bar: today's ring by its [label], a version's own button by its key, or its row under
/// the bar's ••• where the version puts it away (Grouped command, the default, on a phone).
Future<void> pressInBar(WidgetTester tester, String id, {required String label}) async {
  Future<void> beat() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  final ring = find.bySemanticsLabel(label);
  final own = find.byKey(HeaderAct.keyOf(id));
  if (ring.evaluate().isNotEmpty) {
    await tester.tap(ring.first);
  } else if (own.evaluate().isNotEmpty) {
    await tester.tap(own.last);
  } else {
    await tester.tap(find.byKey(HeaderAct.keyOf('overflow')).last);
    await beat();
    await tester.tap(find.byKey(HeaderAct.keyOf(id)).last);
  }
  await beat();
}
