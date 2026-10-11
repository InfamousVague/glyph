// Places in the words held to the web page: the cases test/editor/media/fixtures/reference.mjs measured in Chromium
// with editor/placeCards.ts in the editor (the quiet card with each reason, the reader's "Show the map", no cards at
// all, the caret on a place's line, and a place at the note's top as its header), drawn here with
// lib/editor/media/place_cards.dart and map_card.dart, and each line's box, each card's and its mark's and chips'
// compared with the page's.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/place_cards.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['places', 'place-top'])) {
    testWidgets('$name: lines, cards, marks and chips where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      final mode = PlaceMode.values.byName(fixture.places);
      await pumpMedia(tester, fixture, <Extension>[
        placeCards(mode, switches: () => (localOnly: fixture.prefs['localOnly'] == true, mapTiles: fixture.prefs['mapTiles'] != false)),
      ]);
      const parts = <String>['cm-placeCardBox', 'card', 'quiet', 'mark', 'chip-why', 'chip-show', 'chip-credit'];
      final held = heldToPage(tester, fixture, parts);
      final blocks = blocksHeld(tester, fixture, (block) => 'cm-placeCard');
      // What each line reads as: its name off the caret's line, as written on it.
      for (var i = 0; i < fixture.lines.length; i++) {
        expect(shownOf(tester, i), fixture.lines[i]['shown'], reason: 'line $i reads as the page\'s');
      }
      // ignore: avoid_print
      print('$name: worst ${held.worst.toStringAsFixed(3)}');
      expect(<String>[...held.problems, ...blocks], isEmpty, reason: <String>[...held.problems, ...blocks].join('\n'));
      await shot(tester, name);
    });
  }
}
