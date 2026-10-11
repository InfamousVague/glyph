// What an open first heading says (lib/editor/items/open_heading.dart): `src/app/editor/openHeading.test.ts`, case
// for case.
//
// What is asked differently: the hint is a widget, read from the view's decorations - its words and the position
// it is given - where the page's test found the `<span>` and asked the view where it stood; a lead line is a line
// given the `cm-lead` line decoration. Nothing is left out.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/open_heading.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

EditorState state(String doc, [int? caret]) => EditorState.create(doc: doc, selection: EditorSelection.single(caret ?? doc.length));

/// The hints a view draws: each one's words and where it stands.
List<({String words, int at})> hints(EditorView view) {
  final found = <({String words, int at})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final widget = value.widget;
      if (widget is HintWidget) found.add((words: widget.words, at: from));
      return null;
    });
  }
  return found;
}

({String words, int at})? hint(String doc) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: openHeading()));
  final found = hints(view);
  view.destroy();
  expect(found.length, lessThan(2));
  return found.isEmpty ? null : found.single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an open first heading', () {
    test('says `A name` after its marks, on the first line of words, under front matter too', () {
      expect(hint('# '), (words: 'A name', at: 2));
      expect(hint('## \n\n- [ ] '), (words: 'A name', at: 3));
      expect(hint('---\nlook: reading\n---\n# \n'), (words: 'A name', at: '---\nlook: reading\n---\n# '.length));
      expect(hint('\n\n# ')?.words, 'A name');
    });

    test('says nothing on a heading with words, or on an empty heading further down', () {
      expect(hint('# Title'), isNull);
      expect(hint('# Title\n\n## '), isNull);
      expect(hint('Words.\n\n# '), isNull);
      expect(hint(''), isNull);
      expect(openFirstHeading(state('- [ ] ')), isNull);
    });
  });

  group('the line that names the note', () {
    test('is a blank note’s line 1, or an open first heading, with the caret on it', () {
      expect(onNamingLine(state('')), isTrue);
      expect(onNamingLine(state('# ')), isTrue);
      expect(onNamingLine(state('\n\n', 2)), isTrue);
      expect(onNamingLine(state('---\nlook: map\n---\n# ')), isTrue);
    });

    test('is not a line after the name, a line with words, a list’s lead, or the front matter', () {
      expect(onNamingLine(state('# Title\n\n')), isFalse);
      expect(onNamingLine(state('Words')), isFalse);
      expect(onNamingLine(state('- [ ] ')), isFalse);
      expect(onNamingLine(state('---\nlook: map\n---\n', 4)), isFalse);
    });
  });

  group('a reading note’s lead line', () {
    /// The lead of `doc`: its lines' words, and the number of the line that says what goes there.
    void expectLead(String doc, {required List<String> lines, required int? hint}) {
      final found = leadOf(state(doc));
      expect(<String>[for (final line in found.lines) line.text], lines, reason: doc);
      expect(found.hint?.number, hint, reason: doc);
    }

    test('is the first paragraph after the title, and stops at a blank line or a line that is not prose', () {
      expectLead('# The long road\n\nIt went on.\nAnd on.\n\nMore.', lines: <String>['It went on.', 'And on.'], hint: null);
      expectLead('---\nlook: reading\n---\n# Road\nStraight under it.', lines: <String>['Straight under it.'], hint: null);
      expectLead('# Road\n\n- a list\n\nWords.', lines: <String>[], hint: null);
      expectLead('# Road\n\n> A quote', lines: <String>[], hint: null);
      expectLead('# Road\n\n![a picture](p.webp)', lines: <String>[], hint: null);
      expectLead('Road, with no title\n\nWords.', lines: <String>[], hint: null);
    });

    test('says what goes there on the empty line under the title while nothing below has words', () {
      expectLead('# \n', lines: <String>[], hint: 2);
      expectLead('# The long road\n\n', lines: <String>[], hint: 2);
      expectLead('# The long road', lines: <String>[], hint: null);
    });

    test('is drawn larger in the reading look only, with its hint quiet and not in the note', () {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: '# Road\n\nIt went on.\n', extensions: leadLine()));
      addTearDown(view.destroy);
      List<int> leads() {
        final found = <int>[];
        for (final set in view.decorations) {
          set.between(0, view.state.doc.length, (from, to, value) {
            if (value is LineDecoration && (value.spec.className ?? '').split(' ').contains('cm-lead')) found.add(view.state.doc.lineAt(from).number);
            return null;
          });
        }
        return found;
      }

      expect(<String>[for (final n in leads()) view.state.doc.line(n).text], <String>['It went on.']);
      expect(hints(view), isEmpty);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: view.state.doc.length, insert: '# \n')));
      // The hint stands on the lead line, the empty one under the title.
      expect(leads(), <int>[2]);
      expect(hints(view), <({String words, int at})>[(words: 'A line that says what it is about.', at: view.state.doc.line(2).from)]);
      expect(view.state.doc.toString(), '# \n');
    });
  });
}
