import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/ui/live_page.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/editor/marks/wisp_motion.dart' show wispNow;

import '../support/render.dart';
import 'support/harness.dart';

/// The recorder's page by itself (`src/app/capture/LivePage.tsx` has no test of its own on the web; its behaviour
/// is held there through CaptureScreen.test.tsx's `page()`): what was heard written in as the smallest edit, the
/// words arriving through the wisp and settling, a rewrite's old letters leaving, words for a list landing in the
/// list, and the placeholder on an empty page.
void main() {
  setUpAll(loadAppFonts);

  Future<void> show(WidgetTester tester, {required String base, required String markdown, Placing placing = end, bool arrivals = true, String? from}) async {
    wispNow = () => tester.binding.clock.now().microsecondsSinceEpoch / 1000;
    await pumpScreen(
      tester,
      Align(alignment: Alignment.topCenter, child: SizedBox(height: 600, child: LivePage(base: base, markdown: markdown, placeholder: 'Start talking.', placing: placing, arrivals: arrivals, from: from))),
      prefs: const Preferences(theme: 'light'),
      insets: EdgeInsets.zero,
    );
  }

  LivePageState page(WidgetTester tester) => tester.state<LivePageState>(find.byType(LivePage));

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('writes what was heard onto the end of the note’s own text, each new word arriving through the wisp and then set', (tester) async {
    await show(tester, base: '# Daily Life\n\nWent for a walk.', markdown: '');
    expect(page(tester).document, '# Daily Life\n\nWent for a walk.');
    expect(page(tester).inMotion, isEmpty);

    await show(tester, base: '# Daily Life\n\nWent for a walk.', markdown: 'Oat milk too.');
    expect(page(tester).document, '# Daily Life\n\nWent for a walk.\n\nOat milk too.');
    // Three words, each in turn; none of the note's older text moves.
    final arriving = page(tester).inMotion.where((piece) => piece.gone.isEmpty).toList();
    expect([for (final piece in arriving) page(tester).document.substring(piece.from, piece.to)], ['Oat', 'milk', 'too.']);
    expect(arriving.map((piece) => piece.at), orderedEquals([...arriving.map((piece) => piece.at)]..sort()));

    // Drawn through their smoke for a moment, then let go of.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    for (var waited = 0; waited < 1500; waited += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(page(tester).inMotion.where((piece) => piece.gone.isEmpty), isEmpty);
    await away(tester);
  });

  testWidgets('rewrites a guess with the smallest edit: the word that changed leaves into smoke and its better one arrives', (tester) async {
    await show(tester, base: '', markdown: 'The meeting is at tree');
    for (var waited = 0; waited < 1500; waited += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await show(tester, base: '', markdown: 'The meeting is at three');
    expect(page(tester).document, 'The meeting is at three');
    final pieces = page(tester).inMotion;
    // What left is the letters that really went, and what arrives the letters that really came: the shared start and
    // end stay put.
    expect(pieces.where((piece) => piece.gone.isNotEmpty).map((piece) => piece.gone), isNot(contains(contains('meeting'))));
    expect(pieces.where((piece) => piece.gone.isEmpty).length, lessThanOrEqualTo(1));
    await away(tester);
  });

  testWidgets('sets nothing in motion with the ghostly typing switched off', (tester) async {
    await show(tester, base: '', markdown: '', arrivals: false);
    await show(tester, base: '', markdown: 'Pick up the parcel.', arrivals: false);
    expect(page(tester).document, 'Pick up the parcel.');
    expect(page(tester).inMotion, isEmpty);
    await away(tester);
  });

  testWidgets('writes words for a list into the list, where Done will save them', (tester) async {
    const house = '# House TODOs\n\n- [ ] Fix the gutter\n\nNotes below.';
    final placing = placingFor(house, said: const Said(task: true));
    await show(tester, base: house, markdown: '', placing: placing);
    await show(tester, base: house, markdown: 'Call Sam.', placing: placing);
    final lines = page(tester).document.split('\n');
    expect(lines[lines.indexOf('- [ ] Fix the gutter') + 1], '- [ ] Call Sam');
    expect(lines.last, 'Notes below.');
    await away(tester);
  });

  testWidgets('starts from the note switched to, and brings the words already said in through the wisp', (tester) async {
    const groceries = '# Groceries\n\n- Eggs';
    await show(tester, base: groceries, markdown: 'Oat milk.', placing: placingFor(groceries, own: true), from: groceries);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(page(tester).document, '# Groceries\n\n- Eggs\n- Oat milk');
    expect(page(tester).inMotion.where((piece) => piece.gone.isEmpty), isNotEmpty);
    await away(tester);
  });

  testWidgets('says to start talking on an empty page, in the note’s own face, and no longer once there is a word', (tester) async {
    await show(tester, base: '', markdown: '');
    expect(page(tester).document, '');
    expect(page(tester).lineRects, hasLength(1));
    expect(find.byType(ShaderMask), findsOneWidget);
    await show(tester, base: '', markdown: 'Hello.');
    expect(find.byType(ShaderMask), findsNothing);
    await away(tester);
  });
}
