// Links between notes (lib/editor/items/wiki_links.dart): `src/app/editor/wikiLinks.test.ts`, case for case.
//
// What is asked differently: what is drawn is the view's `cm-wiki` marks; `wikiLinks(null)` on the page is
// `wikiLinks()` with nothing in the `wikiOptions` facet here; and a press is the plugin's pointer handler called on
// a view told which position it lands on, the handler answering true where the page's kept the press from the
// editor. Nothing is left out.
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// A view told where a press lands, since nothing is laid out.
class _Told extends EditorView {
  _Told(EditorState state, this.lands) : super(state: state, wholeDocument: true);

  final int? lands;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => lands;
}

/// The `cm-wiki` marks drawn, in order: the words each covers and its classes.
List<({String text, String className})> marks(EditorView view) {
  final found = <({int from, String text, String className})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final className = value.spec.className ?? '';
      if (className.split(' ').contains('cm-wiki')) found.add((from: from, text: view.state.sliceDoc(from, to), className: className));
      return null;
    });
  }
  found.sort((a, b) => a.from - b.from);
  return <({String text, String className})>[for (final mark in found) (text: mark.text, className: mark.className)];
}

/// What `open` was called with.
class Opened {
  final List<(String, String?)> calls = <(String, String?)>[];

  void call(String title, [String? anchor]) => calls.add((title, anchor));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a link between notes', () {
    test('is read out of the words, brackets and all', () {
      const line = 'The deposit is in [[The cabin trip]], not here.';
      expect(wikiLinksIn(line), const <WikiLink>[WikiLink(from: 18, to: 36, title: 'The cabin trip', anchor: null)]);
    });

    test('takes several on a line, and nothing from empty brackets', () {
      expect(wikiLinksIn('[[one]] and [[two]]').map((l) => l.title), <String>['one', 'two']);
      expect(wikiLinksIn('[[]] and [[   ]]'), isEmpty);
    });

    test('matches a title the way a person says it, not the way they type it', () {
      expect(sameTitle('the cabin trip', 'The cabin trip.'), isTrue);
      expect(sameTitle('Weekend  trip', 'weekend-trip'), isTrue);
      expect(sameTitle('cabin', 'cabins'), isFalse);
      expect(sameTitle('', ''), isFalse);
    });
  });

  group('how it is drawn and what a tap does', () {
    EditorView editor(String doc, bool Function(String title) known) {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[wikiLinks(WikiOptions(known: known, open: Opened().call))])));
      addTearDown(view.destroy);
      return view;
    }

    test('draws a link to a note that exists, and one that is waiting to be written', () {
      final view = editor('go to [[Here]] and [[Nowhere]]', (title) => title == 'Here');
      final drawn = marks(view);
      expect(drawn.map((m) => m.text), <String>['[[Here]]', '[[Nowhere]]']);
      expect(drawn[0].className, isNot(contains('cm-wikiNew')));
      expect(drawn[1].className, contains('cm-wikiNew'));
    });

    test('is nothing at all when the note screen cannot open notes', () {
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: '[[Here]]', extensions: noteExtensions(more: <Extension>[wikiLinks()])));
      addTearDown(view.destroy);
      expect(marks(view), isEmpty);
    });
  });

  group('a link that points inside a note', () {
    bool press(EditorView view) => view.eventHandlers.any((h) => h.mouseDown?.call(const PointerDownEvent(position: Offset(10, 10)), view) ?? false);

    test('is not a wiki link at all when there is no title before the hash', () {
      // `[[#^ship-page]]` is a place in this note; editor/boards.ts draws those.
      expect(wikiLinksIn('see [[#^ship-page]] below'), isEmpty);
      expect(wikiLinksIn('[[#heading]]'), isEmpty);
    });

    test('splits a note and a place in it on the first hash, anchor and all', () {
      final link = wikiLinksIn('in [[The cabin trip#^friday]] there').first;
      expect(link.title, 'The cabin trip');
      expect(link.anchor, '^friday');
      // Only the first hash splits: the rest belongs to the anchor.
      expect(wikiLinksIn('[[Note#^a#b]]')[0].anchor, '^a#b');
    });

    test('reads the words after a bar as what the link says, as Obsidian writes it, and the title before it', () {
      final link = wikiLinksIn('in [[The cabin trip#Friday|the cabin]] there').first;
      expect(link.title, 'The cabin trip');
      expect(link.anchor, 'Friday');
      expect(link.label, 'the cabin');
      expect(wikiLinksIn('[[Lisbon|]]').single.label, isNull);
      expect(wikiLinksIn('[[|Lisbon]]'), isEmpty);
    });

    test('hands the anchor to whoever opens the note', () {
      final open = Opened();
      // Nothing is laid out, so where the press lands is said: inside the link's brackets.
      final view = _Told(
        EditorState.create(doc: 'go [[The cabin trip#^friday]]', extensions: noteExtensions(more: <Extension>[wikiLinks(WikiOptions(known: (_) => true, open: open.call))])),
        'go [['.length + 2,
      );
      final taken = press(view);
      view.destroy();
      expect(open.calls, <(String, String?)>[('The cabin trip', '^friday')]);
      // The press was the link's: the caret stays where it was.
      expect(taken, isTrue);
      expect(view.state.selection.main.head, 0);
    });

    test('leaves a press beside a link to the editor', () {
      final open = Opened();
      final view = _Told(EditorState.create(doc: 'go [[The cabin trip]]', extensions: noteExtensions(more: <Extension>[wikiLinks(WikiOptions(known: (_) => true, open: open.call))])), 1);
      final taken = press(view);
      view.destroy();
      expect(open.calls, isEmpty);
      expect(taken, isFalse);
    });

    test('draws a note-and-place link by whether the note exists', () {
      final view = EditorView(
        wholeDocument: true,
        state: EditorState.create(doc: '[[Here#^x]] and [[Gone#^y]]', extensions: noteExtensions(more: <Extension>[wikiLinks(WikiOptions(known: (t) => t == 'Here', open: Opened().call))])),
      );
      addTearDown(view.destroy);
      final drawn = marks(view);
      expect(drawn[0].className, isNot(contains('cm-wikiNew')));
      expect(drawn[1].className, contains('cm-wikiNew'));
    });
  });
}
