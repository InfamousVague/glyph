// Code in a note as it is drawn, in each of the seven code themes: a block of JavaScript with every kind of token
// the themes colour (a keyword, a name defined and called, a property, a type, a string, a number, a comment, a
// decorator, a label, punctuation), a line of prose with HTML in it, and a block with no language beside them.
// The pictures are in shots/; what each colour should be is the theme's custom property in
// tauri/src/app/editor/codeThemes.css, by the class glyphHighlight.ts gives the token's tag.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/code/code_highlight.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

const String note = '''
A block of JavaScript:

```js
// Adds up.
@logged
class Sum extends Base {
  static total = 0;
  add(n) { return this.total += n * 2; }
}
loop: for (const x of [1, "two", null]) {
  if (typeof x === 'number') new Sum().add(x);
}
```

HTML in a line, <b class="x">bold</b> and <br/>, and a block with no language:

```
plain code
```
''';

void main() {
  setUpAll(loadAppFonts);
  int? apply;
  setUp(() {
    apply = CodeWorkBudget.apply;
    CodeWorkBudget.apply = null;
  });
  tearDown(() => CodeWorkBudget.apply = apply);

  Future<void> draw(WidgetTester tester, AppPreferences prefs) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: note, extensions: noteExtensions(readOnly: true)));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      size: const Size(390, 520),
      prefs: prefs,
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(alignment: Alignment.topLeft, child: SingleChildScrollView(child: EditorColumn(view: view))),
        ),
      ),
    );
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  for (final theme in const <String>['pastel', 'ink', 'github', 'solarized']) {
    testWidgets('on the light page: $theme', (tester) async {
      await draw(tester, AppPreferences(theme: 'light', codeLight: theme));
      await shot(tester, 'code-light-$theme');
    });
  }
  for (final theme in const <String>['pastel', 'ink', 'one-dark', 'dracula', 'nord']) {
    testWidgets('on the dark page: $theme', (tester) async {
      await draw(tester, AppPreferences(theme: 'dark', codeDark: theme));
      await shot(tester, 'code-dark-$theme');
    });
  }
}
