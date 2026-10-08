// The commands (lib/editor/commands/commands.dart) held to what @codemirror/commands itself did: every case of
// fixtures/commands.json, which tool/command_fixtures.mjs records from the real library with a real EditorView
// under jsdom. A case is a document, a selection and a command; the port must return the same, and when CodeMirror
// dispatched: make the same document, the same selection (anchor, head, the side a caret holds to, its bidi level,
// whether a range has a direction, which range is the main one), with the same user event and scrollIntoView.
// Then the keymaps, against the source's own lists.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/commands.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';

/// Every command the fixture names, under CodeMirror's name.
final Map<String, StateCommand> commands = <String, StateCommand>{
  'cursorCharLeft': cursorCharLeft,
  'cursorCharRight': cursorCharRight,
  'cursorCharForward': cursorCharForward,
  'cursorCharBackward': cursorCharBackward,
  'cursorCharForwardLogical': cursorCharForwardLogical,
  'cursorCharBackwardLogical': cursorCharBackwardLogical,
  'cursorGroupLeft': cursorGroupLeft,
  'cursorGroupRight': cursorGroupRight,
  'cursorGroupForward': cursorGroupForward,
  'cursorGroupBackward': cursorGroupBackward,
  'cursorGroupForwardWin': cursorGroupForwardWin,
  'cursorSyntaxLeft': cursorSyntaxLeft,
  'cursorSyntaxRight': cursorSyntaxRight,
  'cursorLineBoundaryForward': cursorLineBoundaryForward,
  'cursorLineBoundaryBackward': cursorLineBoundaryBackward,
  'cursorLineBoundaryLeft': cursorLineBoundaryLeft,
  'cursorLineBoundaryRight': cursorLineBoundaryRight,
  'cursorLineStart': cursorLineStart,
  'cursorLineEnd': cursorLineEnd,
  'cursorDocStart': cursorDocStart,
  'cursorDocEnd': cursorDocEnd,
  'cursorMatchingBracket': cursorMatchingBracket,
  'selectCharLeft': selectCharLeft,
  'selectCharRight': selectCharRight,
  'selectCharForward': selectCharForward,
  'selectCharBackward': selectCharBackward,
  'selectCharForwardLogical': selectCharForwardLogical,
  'selectCharBackwardLogical': selectCharBackwardLogical,
  'selectGroupLeft': selectGroupLeft,
  'selectGroupRight': selectGroupRight,
  'selectGroupForward': selectGroupForward,
  'selectGroupBackward': selectGroupBackward,
  'selectGroupForwardWin': selectGroupForwardWin,
  'selectSyntaxLeft': selectSyntaxLeft,
  'selectSyntaxRight': selectSyntaxRight,
  'selectLineBoundaryForward': selectLineBoundaryForward,
  'selectLineBoundaryBackward': selectLineBoundaryBackward,
  'selectLineBoundaryLeft': selectLineBoundaryLeft,
  'selectLineBoundaryRight': selectLineBoundaryRight,
  'selectLineStart': selectLineStart,
  'selectLineEnd': selectLineEnd,
  'selectDocStart': selectDocStart,
  'selectDocEnd': selectDocEnd,
  'selectMatchingBracket': selectMatchingBracket,
  'selectAll': selectAll,
  'selectLine': selectLine,
  'selectParentSyntax': selectParentSyntax,
  'simplifySelection': simplifySelection,
  'deleteCharBackward': deleteCharBackward,
  'deleteCharBackwardStrict': deleteCharBackwardStrict,
  'deleteCharForward': deleteCharForward,
  'deleteGroupBackward': deleteGroupBackward,
  'deleteGroupForward': deleteGroupForward,
  'deleteGroupForwardWin': deleteGroupForwardWin,
  'deleteToLineStart': deleteToLineStart,
  'deleteToLineEnd': deleteToLineEnd,
  'deleteLineBoundaryBackward': deleteLineBoundaryBackward,
  'deleteLineBoundaryForward': deleteLineBoundaryForward,
  'deleteLine': deleteLine,
  'deleteTrailingWhitespace': deleteTrailingWhitespace,
  'splitLine': splitLine,
  'transposeChars': transposeChars,
  'insertNewline': insertNewline,
  'insertNewlineAndIndent': insertNewlineAndIndent,
  'insertNewlineKeepIndent': insertNewlineKeepIndent,
  'insertBlankLine': insertBlankLine,
  'indentMore': indentMore,
  'indentLess': indentLess,
  'indentSelection': indentSelection,
  'insertTab': insertTab,
  'moveLineUp': moveLineUp,
  'moveLineDown': moveLineDown,
  'copyLineUp': copyLineUp,
  'copyLineDown': copyLineDown,
  'toggleComment': toggleComment,
  'toggleLineComment': toggleLineComment,
  'toggleBlockComment': toggleBlockComment,
  'toggleBlockCommentByLine': toggleBlockCommentByLine,
  'lineComment': lineComment,
  'lineUncomment': lineUncomment,
  'blockComment': blockComment,
  'blockUncomment': blockUncomment,
};

/// The fixture's selection: a number is one caret; a list is the main index, then five numbers a range (anchor,
/// head, assoc, bidi level or -1, undirectional).
EditorSelection selectionIn(Object? spec) {
  if (spec is int) return EditorSelection.single(spec);
  final list = (spec! as List).cast<int>();
  final ranges = <SelectionRange>[];
  for (var i = 1; i < list.length; i += 5) {
    final anchor = list[i], head = list[i + 1], assoc = list[i + 2], bidi = list[i + 3];
    final level = bidi < 0 ? null : bidi;
    if (list[i + 4] != 0) {
      ranges.add(EditorSelection.undirectionalRange(anchor < head ? anchor : head, anchor < head ? head : anchor));
    } else if (anchor == head) {
      ranges.add(EditorSelection.cursor(anchor, assoc, level));
    } else {
      ranges.add(EditorSelection.range(anchor, head, null, level, assoc == 0 ? null : assoc));
    }
  }
  return EditorSelection.create(ranges, list[0]);
}

/// A selection the way the fixture writes one.
Object selectionOut(EditorSelection sel) {
  final main = sel.main;
  if (sel.ranges.length == 1 && main.empty && main.assoc == 0 && main.bidiLevel == null && !main.undirectional) return main.head;
  return <int>[
    sel.mainIndex,
    for (final r in sel.ranges) ...<int>[r.anchor, r.head, r.assoc, r.bidiLevel ?? -1, r.undirectional ? 1 : 0],
  ];
}

String show(Object? value) => jsonEncode(value);

void main() {
  final fixture = jsonDecode(File('test/editor/commands/fixtures/commands.json').readAsStringSync()) as Map<String, dynamic>;
  final docs = (fixture['docs'] as List).cast<String>();
  final recorded = fixture['commands'] as Map<String, dynamic>;

  test('the fixture and the port name the same commands', () {
    expect(recorded.keys.toSet().difference(commands.keys.toSet()), isEmpty, reason: 'recorded and not ported');
    expect(commands.keys.toSet().difference(recorded.keys.toSet()), isEmpty, reason: 'ported and not recorded');
  });

  group('as CodeMirror does', () {
    for (final name in recorded.keys) {
      final cases = recorded[name] as List;
      test('$name (${cases.length} cases)', () {
        final command = commands[name]!;
        final failures = <String>[];
        for (var i = 0; i < cases.length; i++) {
          final c = cases[i] as List;
          final doc = docs[c[0] as int];
          final options = c[2] is Map ? c[2] as Map<String, dynamic> : const <String, dynamic>{};
          final atoms = <({int from, int to})>[
            for (final a in (options['atoms'] as List?) ?? const <Object?>[]) (from: (a as List)[0] as int, to: a[1] as int),
          ];
          final state = EditorState.create(
            doc: doc,
            selection: selectionIn(c[1]),
            extensions: Extension.list(<Extension>[
              EditorState.allowMultipleSelections.of(true),
              markdownLanguageData,
              // The stand-in the fixture gave `view.moveVertically`, said out loud.
              verticalMotion.of(moveVerticallyByColumn),
              if (atoms.isNotEmpty) atomicRangesFor.of((_) => atoms),
              if (options['ro'] == 1) EditorState.readOnlyFacet.of(true),
              if (options['unit'] != null) indentUnit.of(options['unit'] as String),
              if (options['tab'] != null) EditorState.tabSizeFacet.of(options['tab'] as int),
            ]),
          );
          final sent = <Transaction>[];
          Object? got;
          try {
            final returned = command(StateCommandTarget(state, sent.add));
            Object result = 0;
            if (sent.length > 1) {
              result = 'dispatched ${sent.length} transactions';
            } else if (sent.length == 1) {
              final tr = sent[0];
              final after = tr.newDoc.toString();
              Object change = 0;
              if (after != doc) {
                final expected = (c[4] is List ? (c[4] as List)[0] : 0);
                // Written as the fixture writes it when it is the same document, so a failure reads side by side.
                if (expected is List && doc.substring(0, expected[0] as int) + (expected[2] as String) + doc.substring(doc.length - (expected[1] as int)) == after) {
                  change = expected;
                } else {
                  change = after;
                }
              }
              final announced = tr.effects.map(announce.cast).whereType<StateEffect<String>>().toList();
              result = <Object?>[
                change,
                selectionOut(tr.newSelection),
                tr.annotation(Transaction.userEvent) ?? 0,
                tr.scrollIntoView ? 1 : 0,
                tr.selection != null ? 1 : 0,
                announced.isEmpty ? 0 : announced[0].value,
              ];
            }
            got = <Object?>[returned ? 1 : 0, result];
          } catch (error, stack) {
            got = 'threw $error\n${stack.toString().split('\n').take(6).join('\n')}';
          }
          final want = <Object?>[c[3], c[4]];
          if (show(got) != show(want)) {
            failures.add('case $i: ${show(doc)} selection ${show(c[1])} options ${show(c[2])}\n    CodeMirror ${show(want)}\n    here       ${got is String ? got : show(got)}');
          }
        }
        expect(failures, isEmpty, reason: '${failures.length} of ${cases.length} cases differ:\n${failures.take(12).join('\n')}');
      });
    }
  });

  group('keymaps', () {
    String line(KeyBinding b) =>
        '${b.key ?? '-'} ${b.mac ?? '-'} ${b.run != null || b.viewCommand != null} ${b.shift != null || b.shiftViewCommand != null} ${b.preventDefault}';

    test('emacsStyleKeymap is the source\'s thirteen bindings', () {
      expect(emacsStyleKeymap.map((b) => b.key), <String>[
        'Ctrl-b', 'Ctrl-f', 'Ctrl-p', 'Ctrl-n', 'Ctrl-a', 'Ctrl-e', 'Ctrl-d', 'Ctrl-h', 'Ctrl-k', 'Ctrl-Alt-h', 'Ctrl-o', 'Ctrl-t', 'Ctrl-v', //
      ]);
      expect(emacsStyleKeymap[2].viewCommand, 'cursorLineUp');
      expect(emacsStyleKeymap[2].shiftViewCommand, 'selectLineUp');
      expect(emacsStyleKeymap[12].viewCommand, 'cursorPageDown');
    });

    test('standardKeymap ends with the emacs bindings as mac keys', () {
      expect(standardKeymap.length, 26 + 13);
      expect(line(standardKeymap[0]), 'ArrowLeft - true true true');
      expect(line(standardKeymap[1]), 'Mod-ArrowLeft Alt-ArrowLeft true true true');
      expect(line(standardKeymap[18]), 'Enter - true true false');
      final tail = standardKeymap.sublist(26);
      expect(tail.map((b) => b.mac), emacsStyleKeymap.map((b) => b.key));
      expect(tail.every((b) => b.key == null && !b.preventDefault), isTrue);
    });

    test('defaultKeymap is its twenty bindings, then the standard ones', () {
      expect(defaultKeymap.length, 20 + standardKeymap.length);
      expect(defaultKeymap.sublist(20), standardKeymap);
      expect(defaultKeymap.take(20).map((b) => b.key), <String>[
        'Alt-ArrowLeft', 'Alt-ArrowRight', 'Alt-ArrowUp', 'Shift-Alt-ArrowUp', 'Alt-ArrowDown', 'Shift-Alt-ArrowDown', 'Mod-Alt-ArrowUp', //
        'Mod-Alt-ArrowDown', 'Escape', 'Mod-Enter', 'Alt-l', 'Mod-i', 'Mod-[', 'Mod-]', 'Mod-Alt-\\', 'Shift-Mod-k', 'Shift-Mod-\\', 'Mod-/', 'Alt-A', 'Ctrl-m',
      ]);
    });

    test('a binding has a command or names the view\'s, never both and never neither', () {
      const viewCommands = <String>{
        'cursorLineUp', 'cursorLineDown', 'selectLineUp', 'selectLineDown', 'cursorPageUp', 'cursorPageDown', 'selectPageUp', 'selectPageDown', //
        'addCursorAbove', 'addCursorBelow', 'toggleTabFocusMode',
      };
      for (final b in <KeyBinding>[...defaultKeymap, ...emacsStyleKeymap, indentWithTab]) {
        expect((b.run != null) != (b.viewCommand != null), isTrue, reason: '${b.key ?? b.mac}');
        expect(b.shift != null && b.shiftViewCommand != null, isFalse, reason: '${b.key ?? b.mac}');
        if (b.viewCommand != null) expect(viewCommands, contains(b.viewCommand));
        if (b.shiftViewCommand != null) expect(viewCommands, contains(b.shiftViewCommand));
        expect(b.key != null || b.mac != null, isTrue);
      }
    });
  });

  group('what the view supplies', () {
    test('verticalMotion is asked by deleteLine', () {
      final asked = <int>[];
      final state = EditorState.create(
        doc: 'one\ntwo\nthree',
        selection: EditorSelection.single(1),
        extensions: Extension.list(<Extension>[
          verticalMotion.of((state, range, forward) {
            asked.add(range.head);
            return EditorSelection.cursor(7);
          }),
        ]),
      );
      final sent = <Transaction>[];
      expect(deleteLine(StateCommandTarget(state, sent.add)), isTrue);
      expect(asked, <int>[1]);
      expect(sent.single.newDoc.toString(), 'two\nthree');
      expect(sent.single.newSelection.main.head, 3);
    });

    test('markdownLanguageData answers the comment tokens and nothing else', () {
      final state = EditorState.create(doc: 'x', extensions: markdownLanguageData);
      final tokens = state.languageDataAt<Object?>('commentTokens', 0).single! as CommentTokens;
      expect(tokens.line, isNull);
      expect(tokens.block!.open, '<!--');
      expect(tokens.block!.close, '-->');
      expect(state.languageDataAt<Object?>('wordChars', 0), isEmpty);
      expect(state.languageDataAt<Object?>('closeBrackets', 0), isEmpty);
    });

    test('with no language data there is nothing to comment with', () {
      final state = EditorState.create(doc: 'x');
      expect(toggleComment(StateCommandTarget(state, (_) => fail('dispatched'))), isFalse);
      expect(toggleBlockComment(StateCommandTarget(state, (_) => fail('dispatched'))), isFalse);
    });

    test('a line comment language toggles by line', () {
      final state = EditorState.create(
        doc: '  a\n\n    b',
        selection: EditorSelection.single(0, 10),
        extensions: EditorState.languageData.of((state, pos, side) => const <Map<String, Object?>>[
          <String, Object?>{'commentTokens': CommentTokens(line: '//')},
        ]),
      );
      final sent = <Transaction>[];
      expect(toggleComment(StateCommandTarget(state, sent.add)), isTrue);
      expect(sent.single.newDoc.toString(), '  // a\n\n  //   b');
      final again = <Transaction>[];
      expect(toggleLineComment(StateCommandTarget(sent.single.state, again.add)), isTrue);
      expect(again.single.newDoc.toString(), '  a\n\n    b');
    });

    test('an indent unit must be one whitespace character repeated', () {
      expect(() => EditorState.create(extensions: indentUnit.of(' \t')).facet(indentUnit), throwsArgumentError);
      expect(getIndentUnit(EditorState.create(extensions: Extension.list(<Extension>[indentUnit.of('\t\t'), EditorState.tabSizeFacet.of(3)]))), 6);
    });
  });
}
