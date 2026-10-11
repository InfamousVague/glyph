// Films in the words held to the web page: the cases test/editor/media/fixtures/reference.mjs measured in Chromium
// with editor/images.ts and editor/videos.ts in the editor and the posters lent (a still's card as another device
// says it, a shared page's, an upright film at 60vh, the caret on a film's line), drawn here with
// lib/editor/media/videos.dart from the same PNGs, and each line's box, each card's, its frame, poster, length and
// words compared with the page's.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/images.dart';
import 'package:ghost_md/editor/media/videos.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['videos'])) {
    testWidgets('$name: lines, cards, posters, lengths and words where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      final store = MemoryPictureStore()..lend(<String, Uint8List>{for (final picture in const <String>['poster.png', 'upright.png']) picture: Uint8List.fromList(MediaFixture.picture(picture))});
      await pumpMedia(tester, fixture, <Extension>[
        inlineImages(store: store),
        // The page was a browser: a device that never has a film.
        videoCards(VideoMode.values.byName(fixture.videos), seams: FilmSeams(filmsPlay: () async => FilmsPlay.elsewhere)),
      ]);
      await settlePictures(tester);
      final held = heldToPage(tester, fixture, const <String>['frame', 'length', 'words']);
      final blocks = blocksHeld(tester, fixture, (block) => 'cm-videoCard');
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
