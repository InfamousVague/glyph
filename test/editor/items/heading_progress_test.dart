// Progress under a heading (lib/editor/items/heading_progress.dart): `src/app/editor/headingProgress.test.ts`, case
// for case.
//
// What is asked differently: the count is a widget, not a `<span>`, so the last case reads the widget the plugin
// gives the heading's end (its place and its numbers) and then what is drawn of it: its words, and what a screen
// reader hears. The page's `cm-headingCountDone` class has no rule of its own and no counterpart here: "all done" is
// the widget's numbers being equal, and its words.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/heading_progress.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

Doc doc(String text) => Doc.of(text.split('\n'));

/// The counts the view draws: where each is, and the widget.
List<({int at, CountWidget widget})> counts(EditorView view) {
  final found = <({int at, CountWidget widget})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final widget = value.widget;
      if (widget is CountWidget) found.add((at: from, widget: widget));
      return null;
    });
  }
  return found;
}

void main() {
  setUpAll(loadAppFonts);

  group('progress under a heading', () {
    test('counts the to-dos until the next heading of the same level, a section counting its subsections', () {
      final note = doc(<String>['# Trip', '## Packing', '- [x] Tent', '- [ ] Stove', '### Food', '- [X] Oats', '## Plan', '- Just a bullet', '## Chores', '1. [ ] Bins'].join('\n'));
      expect(headingCounts(note), const <HeadingCount>[
        HeadingCount(line: 1, done: 2, total: 4),
        HeadingCount(line: 2, done: 2, total: 3),
        HeadingCount(line: 5, done: 1, total: 1),
        HeadingCount(line: 9, done: 0, total: 1),
      ]);
    });

    test('counts only the boxes the note draws, so a heading never says a to-do is open that has no box to tick', () {
      final note = doc(<String>['## Shop', '- [ ]milk', '- [x](https://example.com/x)', '* [ ] eggs', '+ [X] bread'].join('\n'));
      expect(headingCounts(note), const <HeadingCount>[HeadingCount(line: 1, done: 1, total: 2)]);
    });

    test('counts no box that has no words yet, as the home page’s To do card counts none', () {
      // A journal's day of to-dos, as its template starts an entry.
      expect(headingCounts(doc(<String>['# Monday 28 September', '', '## To do', '', '- [ ] '].join('\n'))), isEmpty);
      expect(headingCounts(doc(<String>['## To do', '- [ ] ', '- [x]   ', '- [ ] Call Sam'].join('\n'))), const <HeadingCount>[HeadingCount(line: 1, done: 0, total: 1)]);
    });

    test('counts no box whose only words are fields (docs/DESIGN.md §158)', () {
      expect(headingCounts(doc(<String>['## To do', '- [ ] 📅 2026-10-03', '- [ ] @sam ⏫', '- [ ] Call Sam 📅 2026-10-03'].join('\n'))), const <HeadingCount>[HeadingCount(line: 1, done: 0, total: 1)]);
    });

    test('ignores boxes and headings inside code', () {
      final note = doc(<String>['## Code', '```', '# not a heading', '- [ ] not a to-do', '```', '- [ ] real'].join('\n'));
      expect(headingCounts(note), const <HeadingCount>[HeadingCount(line: 1, done: 0, total: 1)]);
    });

    testWidgets('says the count at the end of the heading, all done in words of its own, and follows the boxes as they change', (tester) async {
      final semantics = tester.ensureSemantics();
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: '## Shop\n- [x] milk\n- [ ] eggs', extensions: noteExtensions(more: <Extension>[headingProgress()])));
      addTearDown(view.destroy);
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('1 of 2 done'), findsOneWidget);
      // The widget sits after the heading's words, on its line.
      var drawn = counts(view).single;
      expect(drawn.at, view.state.doc.line(1).to);
      expect((drawn.widget.done, drawn.widget.total), (1, 2));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.line(3).from + 3, to: view.state.doc.line(3).from + 4, insert: 'x')));
      await tester.pump();
      expect(find.text('All 2 done'), findsOneWidget);
      expect(find.text('1 of 2'), findsNothing);
      expect(find.bySemanticsLabel('2 of 2 done'), findsOneWidget);
      drawn = counts(view).single;
      expect(drawn.at, view.state.doc.line(1).to);
      expect((drawn.widget.done, drawn.widget.total), (2, 2));
      semantics.dispose();
      debugDisableShadows = true;
    });
  });
}
