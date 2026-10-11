// The effects' marks kept across a change that leaves the effects alone (lib/editor/marks/text_effects.dart
// `_TextEffects._redraw`): a letter typed anywhere in a note made a mark again for every letter of every effect on
// screen. Each case makes a change in a view that has drawn its effects and holds two things: whether the marks
// were made again or kept, and that either way they are the marks a view made afresh on the same document, the
// same selection and the same focus draws.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/text_effects.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/marks.dart';

const heat = GlyphFormat(name: 'Heat', delimiter: '🔥🔥', look: EffectLook('heat'));
const wave = GlyphFormat(name: 'Wave', delimiter: '🌊🌊', look: EffectLook('wave'));
const shimmer = GlyphFormat(name: 'Shimmer', delimiter: '✨✨', look: EffectLook('shimmer'));
const formats = [heat, wave, shimmer];

const doc = 'A first line of the note.\n'
    '\n'
    'Then so 🔥🔥hot🔥🔥 a day, and 🌊🌊out to sea🌊🌊 we went.\n'
    '\n'
    'A last line, with ✨✨silver✨✨ in it.\n'
    'And one after.';

EditorView viewOf(String text, {int caret = 0, bool focused = false}) {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: text, selection: EditorSelection.single(caret), extensions: noteExtensions(formats: formats, more: [textEffects(formats)])),
  );
  if (focused) view.setFocused(true);
  return view;
}

/// Every effect mark the view draws, as what it says and where: the stretches' own and each letter's.
List<String> marksOf(EditorView view) {
  final found = <String>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if (value is MarkDecoration && (value.attrs['class'] ?? '').contains('cm-textEffect') || value is MarkDecoration && (value.attrs['class'] ?? '').contains('cm-effectLetter')) {
        // Less the editor's own number in a stretch's name (`data-fx`: `heat@0.3@<editor>.<stretch>@<letter>`).
        found.add('$from-$to ${(value.attrs.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value.replaceAll(RegExp(r'@\d+\.(\d+@\d+)'), r'@$1')}').join(' ')}');
      }
      return null;
    });
  }
  return found..sort();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final views = <EditorView>[];
  tearDown(() {
    for (final view in views) {
      view.destroy();
    }
    views.clear();
  });

  /// Makes [spec] in a view of [doc] and answers how many times the marks were made and kept for it, having held
  /// them to a view made afresh.
  ({int made, int kept}) after(TransactionSpec spec, {int caret = 0, bool focused = false}) {
    final view = viewOf(doc, caret: caret, focused: focused);
    views.add(view);
    expect(marksOf(view), isNotEmpty);
    debugEffectsMade = 0;
    debugEffectsKept = 0;
    view.dispatch(spec);
    final made = debugEffectsMade, kept = debugEffectsKept;
    final fresh = viewOf(view.state.doc.toString(), caret: view.state.selection.main.head, focused: focused);
    views.add(fresh);
    expect(marksOf(view), marksOf(fresh), reason: 'the marks after the change are not the marks a fresh view draws');
    return (made: made, kept: kept);
  }

  final hot = doc.indexOf('hot'), sea = doc.indexOf('out to sea'), silver = doc.indexOf('silver');

  test('a letter typed on a line with no effect on it keeps every mark, moved with the letter', () {
    // Before them all, between two of them, and after them all.
    for (final at in [3, doc.indexOf('A last'), doc.length]) {
      final did = after(TransactionSpec(changes: ChangeSpec(from: at, insert: 'x'), selection: EditorSelection.single(at + 1)), caret: at, focused: true);
      expect(did, (made: 0, kept: 1), reason: 'typed at $at');
    }
  });

  test('a letter typed on an effect\'s own line, outside its words, keeps them', () {
    final at = doc.indexOf('Then so') + 4;
    expect(after(TransactionSpec(changes: ChangeSpec(from: at, insert: 'x'), selection: EditorSelection.single(at + 1)), caret: at, focused: true), (made: 0, kept: 1));
    // And a line taken out above them.
    expect(after(TransactionSpec(changes: ChangeSpec(from: 0, to: doc.indexOf('Then so')))), (made: 0, kept: 1));
  });

  test('the caret moved, and the focus taken, outside any effect keep them', () {
    expect(after(TransactionSpec(selection: EditorSelection.single(5)), caret: 2, focused: true), (made: 0, kept: 1));
  });

  test('a change inside an effect\'s words makes the marks again', () {
    // Not from the keyboard, which would have the caret in the words and the effect lifted: another device's.
    expect(after(TransactionSpec(changes: ChangeSpec(from: hot + 1, insert: 'o'))).made, 1);
    expect(after(TransactionSpec(changes: ChangeSpec(from: sea, to: sea + 4))).made, 1);
    // At the very edge of the words, which is a letter more of them.
    expect(after(TransactionSpec(changes: ChangeSpec(from: silver, insert: 's'))).made, 1);
  });

  test('the caret going into an effect\'s words lifts it, and coming out lays it again', () {
    expect(after(TransactionSpec(selection: EditorSelection.single(hot + 1)), caret: 2, focused: true).made, 1);
    expect(after(TransactionSpec(selection: EditorSelection.single(2)), caret: hot + 1, focused: true).made, 1);
  });

  test('a change far off that takes an effect away, or brings one, makes the marks again', () {
    // A fence opened on the first line: everything under it is code.
    final fenced = after(TransactionSpec(changes: ChangeSpec(from: 0, insert: '```\n')));
    expect(fenced.made, 1);
    // A delimiter typed that closes a new effect on a line that had none.
    final at = doc.indexOf('And one after.');
    expect(after(TransactionSpec(changes: ChangeSpec(from: at, to: doc.length, insert: '🌊🌊And one after.🌊🌊'))).made, 1);
  });
}
