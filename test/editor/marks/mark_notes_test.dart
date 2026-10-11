// Ports src/app/editor/markNotes.test.ts (../glyph), case for case and in its order, onto
// lib/editor/marks/mark_notes.dart.
//
// What is read differently: a `MarkNote`'s `words` and `brackets` are `wordsFrom`/`wordsTo` and
// `bracketsFrom`/`bracketsTo`. The page's `mousedown` is the plugin's `mouseDown`, and its panel
// (`.cm-markNotePanel`, `aria-label`) is the view's text panel of that class and label
// (lib/editor/view/text_panel.dart). As on the web, nothing is laid out, so where the tap lands is said by the test:
// a view whose `posAtCoords` answers what it is told (the web's `vi.spyOn(view, 'posAtCoords')`).
//
// Left out: nothing.
import 'package:flutter/gestures.dart' show PointerDownEvent;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/mark_notes.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/text_panel.dart';
import 'package:ghost_md/plugins/marks.dart';

RegExp pattern() => notePattern(marks)!;

/// A view that is told where a tap lands.
class _TapView extends EditorView {
  _TapView({required super.state}) : super(wholeDocument: true);

  int? at;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => at;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a note written after a mark', () {
    test('finds the words, the brackets and what the note says', () {
      const line = 'The deposit is ??four hundred??(Sam said 400, the email says 450) and needs checking.';
      final found = notesIn(line, pattern());
      expect(found, isNotEmpty);
      final note = found.first;
      expect(line.substring(note.wordsFrom, note.wordsTo), 'four hundred');
      expect(line.substring(note.bracketsFrom, note.bracketsTo), '(Sam said 400, the email says 450)');
      expect(note.text, 'Sam said 400, the email says 450');
    });

    test('works for every mark, not only a doubt', () {
      final found = notesIn('==this==(why it matters) and ^^that^^(said twice) and ++new++(added Friday)', pattern());
      expect([for (final note in found) note.text], ['why it matters', 'said twice', 'added Friday']);
    });

    test('leaves a mark with no brackets, and brackets with no mark, alone', () {
      expect(notesIn('??just a doubt?? and (a plain aside)', pattern()), isEmpty);
      expect(notesIn('nothing here at all', pattern()), isEmpty);
    });

    test('counts positions from where the text starts in the note', () {
      final found = notesIn('??x??(y)', pattern(), 100);
      expect(found, hasLength(1));
      expect(found.first.from, 100);
      expect(found.first.wordsFrom, 102);
    });

    test('answers which note a tap landed in: its words or its hidden brackets, not the words before them', () {
      const line = 'Ask ??Sam??(before Friday) today';
      final notes = notesIn(line, pattern());
      expect(noteAt(notes, line.indexOf('Sam') + 1)?.text, 'before Friday');
      expect(noteAt(notes, line.indexOf('(before') + 2)?.text, 'before Friday');
      expect(noteAt(notes, 1), isNull);
      expect(noteAt(notes, line.length - 1), isNull);
    });

    test('takes the shorter of two marks on a line rather than running them together', () {
      final found = notesIn('??one??(first) then ??two??(second)', pattern());
      expect([for (final note in found) note.text], ['first', 'second']);
    });

    test('has no pattern at all when every mark is switched off', () {
      expect(notePattern(const <GlyphFormat>[]), isNull);
    });
  });

  group('brackets that name a colour', () {
    final tinted = <GlyphFormat>[
      GlyphFormat(name: 'Highlight', delimiter: '==', look: const StyleLook(''), tint: (name) => name == 'green' ? 'background: green;' : null),
      const GlyphFormat(name: 'Unsure', delimiter: '??', look: StyleLook('')),
    ];

    test('are a colour on the mark that takes one, and a note anywhere else', () {
      final pattern = notePattern(tinted)!;
      final colour = notesIn('the ==key==(green) is under the mat', pattern).first;
      expect(colour.delimiter, '==');
      expect(isTint(colour, tinted), isTrue);
      // The same word on a mark that takes no colours is what it always was: a note.
      final note = notesIn('the ??key??(green) is under the mat', pattern).first;
      expect(isTint(note, tinted), isFalse);
    });

    test('are still a note when the name is not one the mark knows', () {
      final pattern = notePattern(tinted)!;
      final note = notesIn('the ==key==(Sam has one) is under the mat', pattern).first;
      expect(note.text, 'Sam has one');
      expect(isTint(note, tinted), isFalse);
    });
  });

  group('a tap on noted words', () {
    const line = 'The ??deposit??(Sam said 400) and the ==key==(green) are sorted.';
    _TapView? view;

    tearDown(() {
      view?.destroy();
      view = null;
    });

    /// A tap landing at `pos`; nothing is laid out, so where the words are is said here.
    _TapView tapAt(int pos) {
      final on = view ??= _TapView(state: EditorState.create(doc: line, extensions: noteExtensions(formats: marks, more: [markNotes(marks)])));
      on.at = pos;
      for (final handlers in on.eventHandlers) {
        handlers.mouseDown?.call(const PointerDownEvent(position: Offset(45, 10)), on);
      }
      return on;
    }

    TextPanel? panel(EditorView on) {
      for (final shown in textPanels(on).value) {
        if (shown.className == markNotePanel) return shown;
      }
      return null;
    }

    test('shows what the note says, and a tap anywhere else closes it', () {
      final on = tapAt(line.indexOf('deposit') + 2);
      expect(markNotePanel, 'cm-markNotePanel');
      expect(panel(on)?.text, 'Sam said 400');
      expect(panel(on)?.label, 'Note');
      tapAt(1);
      expect(panel(on), isNull);
    });

    test('shows nothing for a colour named in the brackets, where there is nothing to say', () {
      final on = tapAt(line.indexOf('deposit') + 2);
      expect(panel(on), isNotNull);
      tapAt(line.indexOf('key') + 1);
      expect(panel(on), isNull);
    });
  });
}
