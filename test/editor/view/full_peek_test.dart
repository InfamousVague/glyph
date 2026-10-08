// The home page's preview held to the web's whole editor in its `peek` mode (fixtures/full/, the web `Editor`
// component with every extension): the stand-ins lib/home/note_peek.dart keeps for a heading's count, until
// `headingProgress.ts` is ported, put a heading's line where the page has it.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/home/note_peek.dart';

import '../../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a card’s preview: each line as tall as the web editor’s, a heading with its count after it', (tester) async {
    final fixture = Fixture.read('full/mixed-peek');
    await pumpApp(
      tester,
      prefs: const AppPreferences(theme: 'light'),
      ratio: 2,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
          child: Align(
            alignment: Alignment.topLeft,
            // The preview draws a note after its title: a line stands in for one.
            child: SizedBox(width: fixture.width, child: SingleChildScrollView(child: NotePeek(body: 'A title\n${fixture.doc}'))),
          ),
        ),
      ),
    );
    await tester.pump();
    final lines = drawnLines(tester);
    // The card is given the note's first fourteen lines (`PEEK_SOURCE_LINES`).
    expect(lines.length, 14);
    for (var i = 0; i < lines.length; i++) {
      final want = Fixture.rect(fixture.lines[i]['rect'] as Map<String, dynamic>);
      final box = borderBox(lines[i]);
      expect(box.height, closeTo(want.height, 0.5), reason: 'line $i, "${fixture.lines[i]['text']}"');
    }
    expect(find.text('1 of 2'), findsNWidgets(2));
    debugDisableShadows = true;
  });
}
