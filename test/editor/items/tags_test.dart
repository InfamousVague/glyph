// Tags drawn (lib/editor/items/tags.dart, ports `src/app/editor/tags.ts`). The web has no test of the editor's half;
// a tag's grammar is `core/tags.test.ts`, ported as test/core/tags_test.dart. Here is only where a chip is drawn:
// which words get the `cm-tag` mark (with the gap either side that is the chip's padding here), and that none is
// drawn in code, an address or a blank's question. (Front matter is not held: the parser reads it as words on the web
// and here alike, so `tags.ts` draws a `#word` in it whatever its comment says, and so does this.)
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/inline_box.dart';
import 'package:ghost_md/editor/items/tags.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

EditorView open(String doc) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[tags()])));
  addTearDown(view.destroy);
  return view;
}

/// The `cm-tag` marks, in order: where each is.
List<({int from, int to})> marked(EditorView view) {
  final found = <({int from, int to})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if ((value.spec.className ?? '').split(' ').contains('cm-tag')) found.add((from: from, to: to));
      return null;
    });
  }
  return found..sort((a, b) => a.from - b.from);
}

List<String> chips(EditorView view) => <String>[for (final mark in marked(view)) view.state.sliceDoc(mark.from, mark.to)];

/// Where the gaps that are a chip's padding stand.
List<int> gaps(EditorView view) {
  final found = <int>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if (value.widget is GapWidget) found.add(from);
      return null;
    });
  }
  return found..sort();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tags drawn', () {
    test('marks each tag in the words, its # kept, on any kind of line', () {
      const doc = '# Weekend #trip\n- [ ] Ship it #web #Launch-2 (#later)\nBook #work/clients, see issue #42.';
      final view = open(doc);
      expect(chips(view), <String>['#trip', '#web', '#Launch-2', '#later', '#work/clients']);
      expect(marked(view).first, (from: doc.indexOf('#trip'), to: doc.indexOf('#trip') + 5));
    });

    test('puts the chip’s padding either side of each mark', () {
      final view = open('one #a and #bee');
      expect(gaps(view), <int>[for (final mark in marked(view)) ...<int>[mark.from, mark.to]]);
      expect(gaps(view), hasLength(4));
    });

    test('marks none in code', () {
      expect(chips(open('Run `#not` then #yes\n\n```\n#fenced\n```\n\n    #indented code')), <String>['#yes']);
    });

    test('marks none in a blank’s question, and those beside it still', () {
      expect(chips(open('#before {?which #tag is it?} #after')), <String>['#before', '#after']);
    });

    test('marks none in an address', () {
      expect(chips(open('See [the page](https://example.com/a#frag) and <https://example.com/b#c> and https://example.com/#d #real')), <String>['#real']);
    });

    test('follows the words as they change', () {
      final view = open('plain words');
      expect(chips(view), isEmpty);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: ' #new')));
      expect(chips(view), <String>['#new']);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: '`'), sequential: true));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '`')));
      expect(chips(view), isEmpty);
    });
  });
}
