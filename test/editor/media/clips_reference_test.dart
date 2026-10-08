// Voice memos held to the web page: the cases test/editor/media/fixtures/reference.mjs measured in Chromium with
// editor/clips.ts in the editor (a note with its tape, one without, and the caret on a memo's line), drawn here with
// lib/editor/media/clips.dart, and each line's box (a memo's player is taller than the words and makes its line so),
// each player's, its mark's and its length's compared with the page's.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/clips.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final name in MediaFixture.names(const <String>['clips'])) {
    testWidgets('$name: lines, players and quiet marks where the page has them', (tester) async {
      final fixture = MediaFixture.read(name);
      final tape = fixture.tape;
      await pumpMedia(tester, fixture, <Extension>[clips(), if (tape != null) tapeSource.of(Tape(src: tape['src'] as String?, id: tape['id'] as String?))]);
      // A quiet mark in a list item is NOT held to the page's width: the page's is a bug. The item's line hangs its
      // wrapped lines with a negative `text-indent`, which the mark's inline-flex box inherits and applies to its own
      // words, so on the page they start the hang's width to the left of the pill, over its border, and the pill is
      // that much narrower (links.ts took the same thing off its own pill with `text-indent: 0`; clips.ts did not).
      // Its left edge, top and bottom are held.
      final hung = tape == null ? const <String>{'cm-clipQuiet 0'} : const <String>{};
      final held = heldToPage(tester, fixture, const <String>['cm-clip', 'cm-clipMark', 'cm-clipLength', 'cm-clipQuiet'], notHeld: hung);
      if (hung.isNotEmpty) {
        final drawn = partRects(tester, 'cm-clipQuiet').first, want = MediaFixture.rect(fixture.partsNamed('cm-clipQuiet').first['rect'] as Map<String, dynamic>);
        expect((drawn.left - want.left).abs() <= tolerance && (drawn.top - want.top).abs() <= tolerance && (drawn.bottom - want.bottom).abs() <= tolerance, isTrue, reason: '$drawn, the page $want');
      }
      // ignore: avoid_print
      print('$name: worst ${held.worst.toStringAsFixed(3)}');
      expect(held.problems, isEmpty, reason: held.problems.join('\n'));
      await shot(tester, name);
    });
  }
}
