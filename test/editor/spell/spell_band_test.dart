// A misspelled word's suggestions in the note's press-and-hold menu (lib/editor/band/context_band.dart over
// lib/editor/spell): the first rows of the band when it is opened with the caret on a marked word, each writing its
// word in the marked one's place. The page's WebView offered them in a popup of its own on a word it had underlined.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/spell/spell.dart';

import '../../support/render.dart';
import '../band/support.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<BandRig> marked(WidgetTester tester, {int caret = 10, int? head}) async {
    final rig = await pumpBand(tester, doc: 'I will recieve it today', anchor: caret, head: head);
    rig.view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[StateEffect.appendConfig.of(spellMarks)]));
    rig.view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[
      setMisspellings.of((from: 0, to: 23, found: const <Misspelling>[Misspelling(7, 14, <String>['receive', 'relieve', 'recipe', 'receiver'])])),
    ]));
    await tester.pump();
    return rig;
  }

  testWidgets('are the band’s first rows on a marked word, three at most, and the one pressed is written', (tester) async {
    final rig = await marked(tester);
    await hold(tester, rig);
    expect(words(tester).take(3), <String>['receive', 'relieve', 'recipe']);
    expect(words(tester), isNot(contains('receiver')));
    expect(row('Change to receive'), findsOneWidget, reason: 'named for a screen reader by what it does');
    await choose(tester, 'receive');
    expect(rig.view.state.doc.toString(), 'I will receive it today');
    expect(misspellingsOf(rig.view.state), isEmpty);
    expect(rig.view.state.selection.main.head, 14);
    await away(tester);
  });

  testWidgets('are not offered away from a marked word, nor over a selection', (tester) async {
    final elsewhere = await marked(tester, caret: 3);
    await hold(tester, elsewhere);
    expect(words(tester), isNot(contains('receive')));
    await away(tester);

    final selected = await marked(tester, caret: 7, head: 14);
    await hold(tester, selected);
    expect(words(tester).take(2), <String>['Cut', 'Copy']);
    expect(words(tester), isNot(contains('receive')));
    await away(tester);
  });
}
