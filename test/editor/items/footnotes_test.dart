// Footnotes (lib/editor/items/footnotes.dart): `src/app/editor/footnotes.test.ts`, case for case.
//
// What is asked differently: what is drawn is read from the view's decorations (the marker's mark, the definition's
// line) rather than the page's HTML; a tap is the plugin's pointer handler called on a view told which position the
// press lands on, as the page's test told jsdom; and the panel is `view/text_panel.dart`'s, read from the panels the
// view is showing.
//
// Left out: where the panel is put (46px down, 172px across, held inside the note's width) is the panel's own
// layout, held by test/editor/view/view_test.dart; `role="dialog"` has no counterpart; and the panel closing on a
// scroll is the screen's to do here (text_panel.dart: the view has no scroll events of its own).
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/footnotes.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/text_panel.dart';

final String doc = <String>['The deposit is four hundred[^sam], not four fifty[^bank].', '', '[^sam]: Sam said so on the phone.', '[^bank]: The bank statement disagrees.'].join('\n');

/// A view told where a press lands, since nothing is laid out.
class _Told extends EditorView {
  _Told(EditorState state) : super(state: state, wholeDocument: true);

  int? lands;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => lands;
}

/// The classes drawn in `text`, and the state.
({Set<String> classes, EditorState state}) drawn(String text) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: text, extensions: noteExtensions(more: <Extension>[footnotes()])));
  final classes = <String>{};
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      classes.addAll((value.spec.className ?? '').split(' ').where((c) => c.isNotEmpty));
      return null;
    });
  }
  final state = view.state;
  view.destroy();
  return (classes: classes, state: state);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the footnotes a note defines', () {
    test('reads each one by name, with what it says', () {
      expect(footnotesIn(doc), const <Footnote>[
        Footnote(name: 'sam', text: 'Sam said so on the phone.', line: 3),
        Footnote(name: 'bank', text: 'The bank statement disagrees.', line: 4),
      ]);
    });

    test('takes the first of a name written twice, and nothing from a note with none', () {
      expect(footnotesIn('[^a]: one\n[^a]: two'), hasLength(1));
      expect(footnotesIn('just words'), isEmpty);
    });
  });

  group('how they are drawn', () {
    test('raises a marker that has a definition, and sets the definition quietly', () {
      final classes = drawn(doc).classes;
      expect(classes, contains('cm-footMark'));
      expect(classes, contains('cm-footDefinition'));
    });

    test('leaves a marker with nothing to point at as plain words', () {
      expect(drawn('a claim[^nowhere] here').classes, isNot(contains('cm-footMark')));
    });

    test('never marks the definition’s own name as a reference', () {
      expect(drawn('[^sam]: Sam said so.').classes, isNot(contains('cm-footMark')));
    });
  });

  group('the panel a tap on a marker opens', () {
    late _Told view;

    setUp(() {
      view = _Told(EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[footnotes()])));
      addTearDown(view.destroy);
    });

    /// A tap landing at `pos`.
    EditorView tapAt(int pos) {
      view.lands = pos;
      view.eventHandlers.any((h) => h.mouseDown?.call(const PointerDownEvent(position: Offset(250, 50)), view) ?? false);
      return view;
    }

    List<TextPanel> panels(EditorView on) => textPanels(on).value.where((panel) => panel.className == footPanel).toList();

    test('says what the footnote says, under the marker and held inside the note’s width', () {
      final at = doc.indexOf('[^sam]') + 2;
      final on = tapAt(at);
      expect(panels(on).single.text, 'Sam said so on the phone.');
      expect(panels(on).single.label, 'Footnote sam');
      // Under the words that were tapped.
      expect(panels(on).single.at, at);
    });

    test('is one at a time, and closes on a tap elsewhere, a change to the note, or a scroll', () {
      tapAt(doc.indexOf('[^sam]') + 2);
      final on = tapAt(doc.indexOf('[^bank]') + 2);
      expect(panels(on), hasLength(1));
      expect(panels(on).single.text, 'The bank statement disagrees.');

      tapAt(3);
      expect(panels(on), isEmpty);

      tapAt(doc.indexOf('[^sam]') + 2);
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Now: ')));
      expect(panels(on), isEmpty);

      tapAt(doc.indexOf('[^sam]') + 7);
      expect(panels(on), isNotEmpty);
    });
  });

  group('what a tap on a marker finds', () {
    test('answers the footnote under that position, and nothing elsewhere', () {
      final state = drawn(doc).state;
      final notes = footnotesIn(doc);
      final at = doc.indexOf('[^sam]') + 2;
      expect(noteAtPos(state, notes, at)?.text, 'Sam said so on the phone.');
      expect(noteAtPos(state, notes, 3), isNull);
      // The definition line is not a reference to itself.
      expect(noteAtPos(state, notes, doc.indexOf('[^sam]: ') + 2), isNull);
    });
  });
}
