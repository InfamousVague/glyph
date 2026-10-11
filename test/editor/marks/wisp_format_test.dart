// Ports src/app/editor/wispFormat.test.ts (tauri/), case for case and in its order, onto
// lib/editor/marks/wisp_format.dart (and, for its one case about a styled formatting, format_looks.dart).
//
// Every case is about what is smoked, not how: the functions are called with a state, as on the web.
//
// Left out: nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/marks/wisp_format.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/plugins/marks.dart';

const spoiler = GlyphFormat(name: 'Spoiler', delimiter: '||', look: WispLook());
const shout = GlyphFormat(name: 'Shout', delimiter: '!!', look: StyleLook('text-transform: uppercase'));
const Map<String, int> names = <String, int>{'Spoiler': 2};

EditorState state(String doc, [int? selection]) => EditorState.create(doc: doc, selection: selection == null ? null : EditorSelection.single(selection), extensions: noteExtensions(formats: const [spoiler, shout]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('words in smoke', () {
    test('smokes every letter between the pipes, and neither the pipes nor the spaces', () {
      final s = state('The key is ||under the stone|| by the door.');
      final letters = smokeLetters(s, names, 0, s.doc.length, true);
      expect([for (final l in letters) s.doc.sliceString(l.from, l.to)].join(), 'underthestone');
      expect(letters.every((l) => l.to - l.from == 1), isTrue);
    });

    test('clears the words while the caret is in them, and only then', () {
      final inside = state('a ||secret|| here', 6);
      expect(smokeLetters(inside, names, 0, inside.doc.length, true), hasLength(0));
      // A view that can't be edited never clears.
      expect(smokeLetters(inside, names, 0, inside.doc.length, false), hasLength(6));
      final outside = state('a ||secret|| here', 0);
      expect(smokeLetters(outside, names, 0, outside.doc.length, true), hasLength(6));
    });

    test('keeps a letter of more than one code unit whole', () {
      final s = state('||🙂 ok||');
      final letters = smokeLetters(s, names, 0, s.doc.length, false);
      expect([for (final l in letters) s.doc.sliceString(l.from, l.to)], ['🙂', 'o', 'k']);
    });

    test('styles the words of a styled formatting, delimiters aside', () {
      final s = state('say !!hello!! there');
      const looks = <String, StyleLookSpec>{'Shout': StyleLookSpec(length: 2, css: 'text-transform: uppercase')};
      expect([for (final r in styledRanges(s, looks, 0, s.doc.length)) s.doc.sliceString(r.from, r.to)], ['hello']);
    });
  });

  group('hidden lines', () {
    test('smokes every letter after >| on a run of lines, and clears the run while the caret is in it', () {
      const doc = 'Q\n>| the answer\n>|is 42\n> plain quote';
      final away = EditorState.create(doc: doc, selection: EditorSelection.single(0));
      final letters = spoilerLineLetters(away, 0, doc.length, true);
      expect([for (final l in letters) doc.substring(l.from, l.to)].join(), 'theansweris42');
      final inside = EditorState.create(doc: doc, selection: EditorSelection.single(doc.indexOf('42')));
      expect(spoilerLineLetters(inside, 0, doc.length, true), isEmpty);
      expect(spoilerLineLetters(inside, 0, doc.length, false), hasLength(13));
    });
  });
}
