// Link cards held to the web page: the cases test/editor/media/fixtures/reference.mjs measured in Chromium with
// editor/links.ts and editor/linkCards.ts in the editor and one page's preview put in the page's own store, drawn
// here with lib/editor/media/link_cards.dart and the same preview, and each line's box, each card's and what is on it
// compared with the page's.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_preview.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/link_cards.dart';
import 'package:ghost_md/editor/media/links.dart';

import '../../support/render.dart';
import 'support.dart';

/// What reference.mjs put in the page's store.
class Known extends ChangeNotifier implements LinkPreviewer {
  final Map<String, LinkPreview> known = <String, LinkPreview>{
    'https://www.airbnb.com/rooms/1234': const LinkPreview(
      url: 'https://www.airbnb.com/rooms/1234',
      title: 'The cabin by the lake, with a porch that looks over the water and a stove',
      site: 'Airbnb',
      description: 'Sleeps four. A wood stove, a canoe and no signal, an hour from the nearest town on a gravel road.',
    ),
  };
  final List<String> wanted = <String>[];

  @override
  LinkPreview? previewFor(String url) => known[url];

  @override
  void wantPreview(String url) => wanted.add(url);

  void arrive(LinkPreview preview) {
    known[preview.url] = preview;
    notifyListeners();
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['cards'])) {
    testWidgets('$name: lines, cards and what is on them where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      await pumpMedia(tester, fixture, <Extension>[shortLinks(), linkCards(previewer: Known())]);
      const parts = <String>['cm-shortLink', 'cm-linkCard', 'cm-linkCard-badge', 'cm-linkCard-body', 'cm-linkCard-title', 'cm-linkCard-about', 'cm-linkCard-where'];
      final held = heldToPage(tester, fixture, parts);
      final blocks = blocksHeld(tester, fixture, (block) => 'cm-linkCardWrap');
      // ignore: avoid_print
      print('$name: worst ${held.worst.toStringAsFixed(3)}');
      expect(<String>[...held.problems, ...blocks], isEmpty, reason: <String>[...held.problems, ...blocks].join('\n'));
      await shot(tester, name);
    });
  }
}
