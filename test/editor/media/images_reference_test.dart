// Pictures held to the web page: the cases test/editor/media/fixtures/reference.mjs measured in Chromium with
// editor/images.ts in the editor and its pictures lent, drawn here with lib/editor/media/images.dart from the same
// PNGs, and each line's box, each figure's and each picture's compared with the page's.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/images.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['images'])) {
    testWidgets('$name: lines, figures and pictures where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      final store = MemoryPictureStore()..lend(<String, Uint8List>{for (final picture in const <String>['porch.png', 'tall.png']) picture: Uint8List.fromList(MediaFixture.picture(picture))});
      await pumpMedia(tester, fixture, <Extension>[inlineImages(store: store)]);
      await settlePictures(tester);
      final held = heldToPage(tester, fixture, const <String>['figure-img']);
      final blocks = blocksHeld(tester, fixture, (block) => (block['classes'] as List).contains('waiting') ? 'figure-waiting' : 'figure');
      // ignore: avoid_print
      print('$name: worst ${held.worst.toStringAsFixed(3)}');
      expect(<String>[...held.problems, ...blocks], isEmpty, reason: <String>[...held.problems, ...blocks].join('\n'));
      await shot(tester, name);
    });
  }
}
