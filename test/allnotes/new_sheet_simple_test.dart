import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../support/render.dart';
import 'support.dart';

/// The + in simple mode (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): Note, then one row,
/// "More…", that opens in place to the rest; closed and opened again, it is back to Note and More. Advanced has
/// the whole list, as test/allnotes/new_sheet_test.dart holds it.
void main() {
  setUpAll(loadAppFonts);

  final at = DateTime(2026, 9, 28, 14, 5);

  Future<({List<String> said, void Function(bool open) set})> host(WidgetTester tester, {required bool simple, bool meeting = true, bool today = true}) async {
    final said = <String>[];
    var open = true;
    late StateSetter redraw;
    await pumpApp(
      tester,
      prefs: const AppPreferences(theme: 'dark'),
      home: BackScope(
        stack: BackStack(),
        child: StatefulBuilder(
          builder: (context, setState) {
            redraw = setState;
            return Stack(
              children: [
                const Positioned.fill(child: SizedBox.expand()),
                NewSheet(
                  open: open,
                  simple: simple,
                  clock: () => at,
                  onClose: () {
                    said.add('close');
                    setState(() => open = false);
                  },
                  onNote: () => said.add('note'),
                  onToday: today ? () => said.add('today') : null,
                  entry: NewSheetEntry(journal: 'Diary', hint: 'Starts with the date and the time.', usual: entryPresets[0].text, onPress: (_) => said.add('entry')),
                  onCanvas: () => said.add('canvas'),
                  onBook: () => said.add('book'),
                  onMeeting: meeting ? () => said.add('meeting') : null,
                  onFromLink: (_) async => said.add('link'),
                ),
              ],
            );
          },
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await settle(tester);
    return (said: said, set: (bool next) => redraw(() => open = next));
  }

  List<String> rows(WidgetTester tester) => [for (final row in tester.widgetList<SheetRow>(find.byType(SheetRow))) (row.key! as ValueKey<String>).value];

  testWidgets('opens on Note and More…, and says on the row what More holds', (tester) async {
    final it = await host(tester, simple: true);
    expect(rows(tester), ['new-note', 'new-more']);
    expect(find.text('More…'), findsOneWidget);
    expect(find.text('Today, an entry in Diary, a canvas, a notebook, a meeting, a shared link.'), findsOneWidget);
    expect(it.said, isEmpty);
    await away(tester);
  });

  testWidgets('names only what this build offers behind More', (tester) async {
    await host(tester, simple: true, meeting: false, today: false);
    expect(find.text('An entry in Diary, a canvas, a notebook, a shared link.'), findsOneWidget);
    await away(tester);
  });

  testWidgets('More… opens the rest in place, the sheet staying up, and each still makes its thing', (tester) async {
    final it = await host(tester, simple: true);
    await tester.tap(find.text('More…'));
    await settle(tester);
    expect(it.said, isEmpty, reason: 'More makes nothing');
    expect(rows(tester), ['new-note', 'new-today', 'new-entry', 'new-canvas', 'new-book', 'new-meeting', 'new-link']);
    expect(find.text('More…'), findsNothing);
    await tester.tap(find.text('Cards on a page with lines between them.'));
    await settle(tester);
    expect(it.said, ['close', 'canvas']);
    await away(tester);
  });

  testWidgets('is back to Note and More the next time it opens', (tester) async {
    final it = await host(tester, simple: true);
    await tester.tap(find.text('More…'));
    await settle(tester);
    expect(rows(tester).length, 7);
    it.set(false);
    await settle(tester);
    it.set(true);
    await settle(tester);
    expect(rows(tester), ['new-note', 'new-more']);
    await away(tester);
  });

  testWidgets('has the whole list in advanced, with no More row', (tester) async {
    await host(tester, simple: false);
    expect(rows(tester), ['new-note', 'new-today', 'new-entry', 'new-canvas', 'new-book', 'new-meeting', 'new-link']);
    expect(find.text('More…'), findsNothing);
    await away(tester);
  });
}
