// The anchor on a line, and a pointer at one (lib/editor/items/anchors.dart, ports
// `src/app/editor/boards/anchors.ts`). The web has no test of this file alone; these hold its behaviour as the
// source has it: which words get `cm-itemAnchor`, which `cm-itemRef`, which `cm-itemRef cm-itemRefGone`, and what a
// press on a pointer does. A press is the handler called on a view told which position it lands on.
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/anchors.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// A view told where a press lands, since nothing is laid out.
class ToldView extends EditorView {
  ToldView(EditorState state) : super(state: state, wholeDocument: true);

  int? lands;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => lands;
}

ToldView open(String doc) {
  final view = ToldView(EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[itemAnchors])));
  addTearDown(view.destroy);
  return view;
}

/// The words given each of the anchors' classes, in the note's order: the words, and the classes as written.
List<(String, String)> marked(EditorView view) {
  final found = <({int from, String text, String className})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final className = value.spec.className ?? '';
      if (className.contains('cm-itemAnchor') || className.contains('cm-itemRef')) found.add((from: from, text: view.state.sliceDoc(from, to), className: className));
      return null;
    });
  }
  found.sort((a, b) => a.from - b.from);
  return <(String, String)>[for (final mark in found) (mark.text, mark.className)];
}

bool press(ToldView view, int pos) {
  view.lands = pos;
  return view.eventHandlers.any((h) => h.pointerDown?.call(const PointerDownEvent(position: Offset(10, 10)), view) ?? false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('anchors and their pointers, drawn', () {
    test('draws the anchor naming a list item quiet, and none on a line that is not one', () {
      final view = open('- [ ] Ship the page ^ship-page\n1. Book the cabin ^cabin\nJust words ^loose\n- No anchor here');
      expect(marked(view), <(String, String)>[('^ship-page', 'cm-itemAnchor'), ('^cabin', 'cm-itemAnchor')]);
    });

    test('finds the anchor with an item’s mark or counter after it, and leaves a caret in the words alone', () {
      final view = open('- [ ] Ship it ^ship-it [notion](https://notion.so/a)\n- Water ^water [3/8]\n- E = mc^2^ and x^2');
      expect(marked(view), <(String, String)>[('^ship-it', 'cm-itemAnchor'), ('^water', 'cm-itemAnchor')]);
    });

    test('draws a pointer at an item that is there as a link, and one at nothing as gone', () {
      const doc = '- [ ] Ask Sam ^ask-sam\n\nThe copy waits on [[#^ask-sam]], and [[#^nobody]] is gone.';
      final view = open(doc);
      expect(marked(view), <(String, String)>[('^ask-sam', 'cm-itemAnchor'), ('[[#^ask-sam]]', 'cm-itemRef'), ('[[#^nobody]]', 'cm-itemRef cm-itemRefGone')]);
    });

    test('draws a pointer on the item’s own line too, before its anchor', () {
      final view = open('- [ ] After [[#^two]] ^one\n- [ ] Second ^two');
      expect(marked(view), <(String, String)>[('[[#^two]]', 'cm-itemRef'), ('^one', 'cm-itemAnchor'), ('^two', 'cm-itemAnchor')]);
    });

    test('follows the note: a pointer is gone once its item is, and there again when it is named', () {
      final view = open('- [ ] Ask Sam ^ask-sam\nSee [[#^ask-sam]].');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: view.state.doc.line(1).to, insert: '- [ ] Ask Sam')));
      expect(marked(view), <(String, String)>[('[[#^ask-sam]]', 'cm-itemRef cm-itemRefGone')]);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.line(1).to, insert: ' ^ask-sam')));
      expect(marked(view), <(String, String)>[('^ask-sam', 'cm-itemAnchor'), ('[[#^ask-sam]]', 'cm-itemRef')]);
    });
  });

  group('a press on a pointer', () {
    const doc = 'The copy waits on [[#^ask-sam]], and [[#^nobody]] is gone.\n\n- [ ] Ask Sam ^ask-sam';

    test('puts the caret at the end of its item’s words, before the anchor', () {
      final view = open(doc);
      expect(press(view, doc.indexOf('[[#^ask-sam]]') + 4), isTrue);
      expect(view.state.selection.main.head, view.state.doc.line(3).from + '- [ ] Ask Sam'.length);
      expect(view.state.selection.main.empty, isTrue);
    });

    test('is the editor’s on a pointer at nothing, and beside one', () {
      final view = open(doc);
      expect(press(view, doc.indexOf('[[#^nobody]]') + 4), isFalse);
      expect(press(view, 3), isFalse);
      expect(view.state.selection.main.head, 0);
    });
  });

  test('goToLine goes nowhere for a line that is not there', () {
    final view = open('- [ ] Ask Sam ^ask-sam');
    goToLine(view, 9);
    goToLine(view, 0);
    expect(view.state.selection.main.head, 0);
    goToLine(view, 1);
    expect(view.state.selection.main.head, '- [ ] Ask Sam'.length);
  });
}
