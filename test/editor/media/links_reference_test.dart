// Short links and item marks held to the web page: every case test/editor/media/fixtures/reference.mjs measured in
// Chromium with editor/links.ts in the editor, drawn here with lib/editor/media/links.dart, and each line's box, each
// short address's rectangle and each pill's compared with the page's.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/media/links.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['links'])) {
    testWidgets('$name: lines, short addresses and pills where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      await pumpMedia(tester, fixture, <Extension>[shortLinks()]);
      final held = heldToPage(tester, fixture, const <String>['cm-shortLink', 'cm-itemMark', 'cm-itemMark-name']);
      // The words on each short address are the page's.
      final said = tester.widgetList(find.byKey(const ValueKey<String>('cm-shortLink'))).map((w) => (w as InlineWords).text).toList();
      expect(said, fixture.partsNamed('cm-shortLink').map((p) => p['text']).toList());
      // ignore: avoid_print
      print('$name: worst ${held.worst.toStringAsFixed(3)}');
      expect(held.problems, isEmpty, reason: held.problems.join('\n'));
      await shot(tester, name);
    });
  }
}
