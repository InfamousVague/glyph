// Ports src/app/editor/formatLooks.test.ts (tauri/), case for case and in its order, onto
// lib/editor/marks/format_looks.dart.
//
// A plugin formatting drawn as a style: its words carry its CSS, and a name in brackets after it, where the
// formatting takes one, adds that name's CSS.
//
// What is read differently (the Dart file's header, "What differs"): the page gives a stretch one
// `<span class="cm-formatLook">`; here a look with a box is up to three marks of the same class and style
// (`data-edge`), and small capitals a mark a letter. So "one mark with the look" is read as "the words, and only
// the words, are covered by `cm-formatLook` marks carrying the look's CSS", off the view's decoration sets. Where
// the page asks which <span> is inside which, the line's projection is asked (marks outermost first).
//
// Left out: nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/projection.dart';
import 'package:ghost_md/plugins/marks.dart';

String? _green(String name) => name == 'green' ? 'background: green;' : null;

const glow = GlyphFormat(name: 'Glow', delimiter: '~~~', look: StyleLook('color: red;'), tint: _green);

/// A look that hides its words, as a redaction's bar does.
const bar = GlyphFormat(name: 'Bar', delimiter: '@@', look: StyleLook('background: black;', clearAtCaret: true));
const Map<String, StyleLookSpec> looks = <String, StyleLookSpec>{'Glow': StyleLookSpec(length: 3, css: 'color: red;', tint: _green)};

EditorState state(String doc) => EditorState.create(doc: doc, extensions: noteExtensions(formats: const [glow]));

List<({String words, String css})> styled(String doc) => [for (final r in styledRanges(state(doc), looks, 0, doc.length)) (words: doc.substring(r.from, r.to), css: r.css)];

typedef Marked = ({int from, int to, Map<String, String> attrs});

/// The `cm-formatLook` marks the view draws, in document order.
List<Marked> lookMarks(EditorView view) {
  final found = <Marked>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if (value is MarkDecoration && (value.attrs['class'] ?? '').split(' ').contains('cm-formatLook')) found.add((from: from, to: to, attrs: value.attrs));
      return null;
    });
  }
  return found..sort((a, b) => a.from - b.from);
}

/// The stretches those marks cover, pieces of one stretch run together: what the page has as one span each.
List<String> covered(EditorView view) {
  final doc = view.state.doc.toString();
  final runs = <(int, int)>[];
  for (final mark in lookMarks(view)) {
    if (runs.isNotEmpty && runs.last.$2 == mark.from) {
      runs[runs.length - 1] = (runs.last.$1, mark.to);
    } else {
      runs.add((mark.from, mark.to));
    }
  }
  return [for (final run in runs) doc.substring(run.$1, run.$2)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorView? view;
  tearDown(() {
    view?.destroy();
    view = null;
  });

  group('a formatting drawn as a style', () {
    test('adds the CSS of a name it knows in brackets straight after it', () {
      expect(styled('the ~~~key~~~(green) words'), [(words: 'key', css: 'color: red;background: green;')]);
    });

    test('keeps its own look for a name it does not know, or brackets that are not straight after it', () {
      // A name it does not know is a note on the words (editor/marks/mark_notes.dart), not a colour.
      expect(styled('the ~~~key~~~(Sam said so) words'), [(words: 'key', css: 'color: red;')]);
      expect(styled('the ~~~key~~~ (green) words'), [(words: 'key', css: 'color: red;')]);
      // A formatting that takes no name never reads the brackets.
      const plain = <String, StyleLookSpec>{'Glow': StyleLookSpec(length: 3, css: 'color: red;')};
      const doc = 'the ~~~key~~~(green) words';
      expect([for (final r in styledRanges(state(doc), plain, 0, doc.length)) r.css], ['color: red;']);
    });

    test('marks the words in the editor, one mark with the look, and nothing for formattings of other kinds', () {
      final on = view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'say ~~~hello~~~ there', extensions: noteExtensions(formats: const [glow], more: [formatLooks(const [glow])])));
      expect(covered(on), ['hello']);
      final marks = lookMarks(on);
      expect(marks, isNotEmpty);
      expect(marks.every((mark) => (mark.attrs['style'] ?? '').contains('color: red')), isTrue);
      // A look with no box is one mark, as on the page.
      expect(marks, hasLength(1));
      // `formatLooks([...])` is `[]` on the page: no extension at all, so a state made with it runs no plugin.
      const spoiler = [GlyphFormat(name: 'Spoiler', delimiter: '||', look: WispLook())];
      expect(styleLooksOf(spoiler), isEmpty);
      expect(EditorState.create(extensions: formatLooks(spoiler)).facet(viewPlugin), isEmpty);
    });

    test('sits inside the highlighter’s span, so its box is the size of the words it is on (a heading’s, in a heading)', () {
      const doc = '## a ~~~big~~~ heading';
      final on = view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(formats: const [glow], more: [formatLooks(const [glow])])));
      expect(covered(on), ['big']);
      // The line as it is drawn: each piece of text with the marks over it, outermost first.
      final line = LineProjection.build(doc, 0, on.decorations);
      final at = doc.indexOf('big');
      final pieces = [for (final seg in line.segments) if (seg.kind == SegmentKind.text && seg.from >= at && seg.to <= at + 3) seg];
      expect(pieces, isNotEmpty);
      expect(doc.substring(pieces.first.from, pieces.last.to), 'big');
      for (final piece in pieces) {
        final classes = [for (final mark in piece.marks) mark.attrs['class'] ?? ''];
        // The heading's own span wraps the look's, not the other way round: outside it, the bar was the body's height.
        expect(classes.last, 'cm-formatLook', reason: '$classes');
        expect(classes.length, greaterThan(1), reason: 'the look is inside a span of the highlighter: $classes');
        expect(classes.first, isNot(contains('cm-formatLook')));
      }
    });

    test('draws a look inside a look, and nothing under one that hides its words until it is lifted', () {
      const both = <String, StyleLookSpec>{...looks, 'Bar': StyleLookSpec(length: 2, css: 'background: black;', clearAtCaret: true)};
      List<String> words(String doc, [int anchor = 0, bool atCaret = false]) => [
        for (final r in styledRanges(EditorState.create(doc: doc, selection: EditorSelection.single(anchor), extensions: noteExtensions(formats: const [glow, bar])), both, 0, doc.length, atCaret)) doc.substring(r.from, r.to),
      ];
      // The inner look's words come after the outer's, in document order, as a range set wants them. (Not at the start
      // of the line, where three tildes open a code fence.)
      expect(words('so ~~~a glow with @@a bar@@ in it~~~'), ['a glow with @@a bar@@ in it', 'a bar']);
      // Under a bar a glow would show the words, so it is not drawn; lifted, what is under the bar is drawn as it is.
      expect(words('@@a ~~~glow~~~ under a bar@@'), ['a ~~~glow~~~ under a bar']);
      expect(words('@@a ~~~glow~~~ under a bar@@', 4, true), ['glow']);
      // The looks that hide their words, by name, for the rest of the editor (links).
      expect(EditorState.create(extensions: formatLooks(const [glow, bar])).facet(coveringLooks), ['Bar']);
      expect(EditorState.create(extensions: formatLooks(const [glow])).facet(coveringLooks), isEmpty);
    });
  });
}
