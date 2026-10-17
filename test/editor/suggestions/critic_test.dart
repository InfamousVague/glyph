// Suggested edits read out of a note's words, and settled (lib/editor/suggestions/critic.dart): the three kinds
// with their author, never in code or front matter, adjacent and "nested" ones, and Keep and Revert as one edit and
// one undo each.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/suggestions/critic.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// Each suggestion as its kind, old words, new words and author.
List<String> read(String text) => <String>[
  for (final one in suggestionsIn(text)) '${one.kind.name}|${one.oldText}|${one.newText}|${one.author}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading suggestions', () {
    test('finds an insertion, a deletion and a replacement, each with its author', () {
      expect(read('a {++new++}{>>Claude<<} b {--old--}{>>Claude<<} c {~~was~>is~~}{>>Claude<<} d'), <String>[
        'insert||new|Claude',
        'delete|old||Claude',
        'replace|was|is|Claude',
      ]);
    });

    test('knows where every part is, the author’s note included', () {
      const text = 'x {~~was~>is~~}{>>Claude<<} y';
      final one = suggestionsIn(text, 10).single;
      expect(one.from, 12);
      expect(one.to, 10 + text.indexOf(' y'));
      expect(text.substring(one.oldFrom - 10, one.oldTo - 10), 'was');
      expect(text.substring(one.newFrom - 10, one.newTo - 10), 'is');
      expect(<String>[for (final mark in one.marks) text.substring(mark.from - 10, mark.to - 10)], <String>['{~~', '~>', '~~}', '{>>Claude<<}']);
    });

    test('reads one with no author, and a note apart from it as no author', () {
      expect(read('{++new++} and {--old--} {>>Claude<<}'), <String>['insert||new|null', 'delete|old||null']);
      expect(suggestionsIn('{++new++}').single.marks.length, 2);
    });

    test('reads adjacent suggestions apart', () {
      expect(read('{--four--}{>>Claude<<}{++five++}{>>Claude<<}'), <String>['delete|four||Claude', 'insert||five|Claude']);
      expect(read('{++a++}{++b++}'), <String>['insert||a|null', 'insert||b|null']);
    });

    test('does not nest: what is inside one is its words, marks and all', () {
      expect(read('{++a {--b--} c++}{>>Claude<<}'), <String>['insert||a {--b--} c|Claude']);
      expect(read('{~~a {++b++}~>c~~}'), <String>['replace|a {++b++}|c|null']);
    });

    test('runs over a line’s end, and reads an empty side of a replacement', () {
      expect(read('{++one\ntwo++}{>>Claude<<}'), <String>['insert||one\ntwo|Claude']);
      expect(read('{~~~>new~~} {~~old~>~~}'), <String>['replace||new|null', 'replace|old||null']);
    });

    test('is never in fenced code, a span of code or the front matter', () {
      const text = '---\ntitle: {++x++}\n---\n'
          '```\n{++in a fence++}\n```\n'
          '~~~md\n{--in tildes--}\n```\nstill fenced {++y++}\n~~~\n'
          'Run `{++z++}` as written, and {++this one++}{>>Claude<<}.\n'
          '``a `{--b--}` c`` {--that one--}';
      expect(read(text), <String>['insert||this one|Claude', 'delete|that one||null']);
    });

    test('holds code inside one, but never reaches into a fence', () {
      expect(read('{++run `npm i`++}'), <String>['insert||run `npm i`|null']);
      expect(read('{++start\n```\ncode++}\n```'), isEmpty);
    });

    test('is nothing in words without its marks, or with them half written', () {
      expect(suggestionsIn('plain words'), isEmpty);
      expect(read('{++open and {--never closed'), isEmpty);
      expect(read('{++++} {----}'), isEmpty);
    });

    test('says who suggested them all, where one author did', () {
      expect(soleAuthor(suggestionsIn('{++a++}{>>Claude<<} {--b--}{>>Claude<<}')), 'Claude');
      expect(soleAuthor(suggestionsIn('{++a++}{>>Claude<<} {--b--}{>>Sam<<}')), isNull);
      expect(soleAuthor(suggestionsIn('{++a++}')), isNull);
    });
  });

  group('settling suggestions', () {
    EditorView open(String doc, [bool readOnly = false]) {
      final view = EditorView(state: EditorState.create(doc: doc, extensions: noteExtensions(readOnly: readOnly, more: <Extension>[history()])), wholeDocument: true);
      addTearDown(view.destroy);
      return view;
    }

    const doc = 'The deposit is {--four hundred--}{>>Claude<<}{++five hundred++}{>>Claude<<}, {~~due~>paid~~}{>>Claude<<} Friday.';

    test('keeps one: its new words, without the marks, as one edit one undo takes back', () {
      final view = open(doc);
      final all = suggestionsOf(view.state.doc);
      expect(settleSuggestion(view, all[1].from, keep: true), isTrue);
      expect(view.state.doc.toString(), 'The deposit is {--four hundred--}{>>Claude<<}five hundred, {~~due~>paid~~}{>>Claude<<} Friday.');
      undo(view);
      expect(view.state.doc.toString(), doc);
    });

    test('reverts one: its old words, without the marks, as one edit one undo takes back', () {
      final view = open(doc);
      final all = suggestionsOf(view.state.doc);
      expect(settleSuggestion(view, all[2].from, keep: false), isTrue);
      expect(view.state.doc.toString(), 'The deposit is {--four hundred--}{>>Claude<<}{++five hundred++}{>>Claude<<}, due Friday.');
      undo(view);
      expect(view.state.doc.toString(), doc);
    });

    test('keeps a deletion as nothing, and reverts an insertion as nothing', () {
      final view = open('a {--b --}{>>Claude<<}c {++d++}{>>Claude<<}');
      final all = suggestionsOf(view.state.doc);
      settleSuggestion(view, all[0].from, keep: true);
      settleSuggestion(view, suggestionsOf(view.state.doc).single.from, keep: false);
      expect(view.state.doc.toString(), 'a c ');
    });

    test('keeps them all at once, as one edit one undo takes back', () {
      final view = open(doc);
      expect(settleAllSuggestions(view, keep: true), isTrue);
      expect(view.state.doc.toString(), 'The deposit is five hundred, paid Friday.');
      undo(view);
      expect(view.state.doc.toString(), doc);
    });

    test('reverts them all at once, as one edit one undo takes back', () {
      final view = open(doc);
      expect(settleAllSuggestions(view, keep: false), isTrue);
      expect(view.state.doc.toString(), 'The deposit is four hundred, due Friday.');
      undo(view);
      expect(view.state.doc.toString(), doc);
    });

    test('takes out a whole line a kept deletion leaves with nothing but its lead, one undo back', () {
      const list = '- [ ] Pram\n- [ ] {--Old item--}{>>Claude<<}\n- [ ] Cot';
      final view = open(list);
      settleSuggestion(view, suggestionsOf(view.state.doc).single.from, keep: true);
      expect(view.state.doc.toString(), '- [ ] Pram\n- [ ] Cot');
      undo(view);
      expect(view.state.doc.toString(), list);
      // A heading, a quote, a numbered item and a bare paragraph the same; the last line takes the break before it.
      for (final (before, after) in <(String, String)>[
        ('# Plan\n## {--Old--}{>>Claude<<}\nWords', '# Plan\nWords'),
        ('> a\n> {--b--}{>>Claude<<}\n> c', '> a\n> c'),
        ('1. a\n  2. {--b--}{>>Claude<<}', '1. a'),
        ('{--Gone--}{>>Claude<<}\nStays', 'Stays'),
        ('Only {--this--}', 'Only '),
      ]) {
        final one = open(before);
        settleAllSuggestions(one, keep: true);
        expect(one.state.doc.toString(), after, reason: before);
      }
    });

    test('takes out a whole line a reverted insertion leaves with nothing but its lead, one undo back', () {
      const list = '- [ ] Pram\n- [ ] {++Buy a crib++}{>>Claude<<}\n- [ ] Cot';
      final view = open(list);
      settleSuggestion(view, suggestionsOf(view.state.doc).single.from, keep: false);
      expect(view.state.doc.toString(), '- [ ] Pram\n- [ ] Cot');
      undo(view);
      expect(view.state.doc.toString(), list);
      // Kept, the line stays with its new words.
      settleSuggestion(view, suggestionsOf(view.state.doc).single.from, keep: true);
      expect(view.state.doc.toString(), '- [ ] Pram\n- [ ] Buy a crib\n- [ ] Cot');
    });

    test('reads a line’s suggestions together, and keeps a line one not settled is still on', () {
      const doc = '- a\n- {--b--}{>>Claude<<} {--c--}{>>Claude<<}\n- {--d--}{>>Claude<<}{++e++}{>>Claude<<}\n- f';
      final all = open(doc);
      settleAllSuggestions(all, keep: true);
      expect(all.state.doc.toString(), '- a\n- e\n- f');
      undo(all);
      expect(all.state.doc.toString(), doc);
      // One of the two kept alone: the other is still on the line, so the line stays.
      final one = open(doc);
      settleSuggestion(one, suggestionsOf(one.state.doc).first.from, keep: true);
      expect(one.state.doc.toString(), '- a\n-  {--c--}{>>Claude<<}\n- {--d--}{>>Claude<<}{++e++}{>>Claude<<}\n- f');
      // Reverted all, every line has its old words.
      final back = open(doc);
      settleAllSuggestions(back, keep: false);
      expect(back.state.doc.toString(), '- a\n- b c\n- d\n- f');
    });

    test('leaves code alone when settling them all', () {
      final view = open('`{++x++}` {++y++}\n```\n{--z--}\n```');
      settleAllSuggestions(view, keep: true);
      expect(view.state.doc.toString(), '`{++x++}` y\n```\n{--z--}\n```');
    });

    test('settles nothing where there is nothing, or the note is read only', () {
      expect(settleAllSuggestions(open('plain'), keep: true), isFalse);
      expect(settleSuggestion(open('{++a++}'), 5, keep: true), isFalse);
      final locked = open('{++a++}', true);
      expect(settleAllSuggestions(locked, keep: true), isFalse);
      expect(settleSuggestion(locked, 0, keep: true), isFalse);
      expect(locked.state.doc.toString(), '{++a++}');
    });
  });
}
