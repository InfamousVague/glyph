// Where a note's diagrams are (lib/editor/diagrams/fences.dart): `diagramsIn` as src/app/editor/mermaid.test.ts
// holds it, case for case and in its order, and then what the page has no counterpart of: the fences kept with the
// editor's state, held to what reading the whole note again would find, and to how little of the note a change may
// read.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/diagrams/fences.dart';
import 'package:ghost_md/editor/editor.dart';

/// A state that keeps its diagrams.
EditorState _state(String doc) => EditorState.create(doc: doc, extensions: diagramBlocks);

/// The kept diagrams of `state`, as lines: what `diagramsIn` of its words must say.
List<Diagram> _kept(EditorState state) => <Diagram>[
  for (final block in state.field(diagramBlocks)) Diagram(from: state.doc.lineAt(block.from).number, to: state.doc.lineAt(block.to).number, code: block.code),
];

void main() {
  group('mermaid fences in a note', () {
    test('finds a fence and hands back what is between its lines', () {
      final note = ['# Launch', '', '```mermaid', 'flowchart TD', '  A[Write it] --> B[Ship it]', '```', '', 'and then home', ''].join('\n');
      expect(diagramsIn(note), [const Diagram(from: 3, to: 6, code: 'flowchart TD\n  A[Write it] --> B[Ship it]')]);
    });

    test('takes the word however it is written, and squiggles as readily as backticks', () {
      expect(diagramsIn('```Mermaid\nflowchart TD\n```').first.code, 'flowchart TD');
      expect(diagramsIn('~~~mermaid\nflowchart TD\n~~~').first.code, 'flowchart TD');
      expect(diagramsIn('````mermaid\nflowchart TD\n````').first.code, 'flowchart TD');
    });

    test('leaves every other fence alone', () {
      expect(diagramsIn('```js\nconst a = 1;\n```'), isEmpty);
      expect(diagramsIn('```board\nTo do: a\n```'), isEmpty);
      expect(diagramsIn('```\nplain\n```'), isEmpty);
      // The word has to be the whole info string: a note about mermaids is not a diagram.
      expect(diagramsIn('```mermaid charts\nflowchart TD\n```'), isEmpty);
    });

    test('reads several in one note, and skips a fence that never closes', () {
      final two = ['```mermaid', 'flowchart TD', '```', 'words', '```mermaid', 'sequenceDiagram', '```'].join('\n');
      expect(diagramsIn(two).map((found) => found.code), ['flowchart TD', 'sequenceDiagram']);
      expect(diagramsIn('```mermaid\nflowchart TD'), isEmpty);
    });

    test('does not take the inside of a diagram for another one', () {
      final nested = ['```mermaid', 'flowchart TD', '  A --> B', '```', '', '```mermaid', 'flowchart LR', '```'].join('\n');
      expect(diagramsIn(nested).length, 2);
      expect(diagramsIn(nested)[1], const Diagram(from: 6, to: 8, code: 'flowchart LR'));
    });

    test('closes on the same mark, at least as long, alone on its line', () {
      // Tildes do not close backticks, three do not close four, and a fence with words after it closes nothing.
      expect(diagramsIn('```mermaid\na\n~~~\nb\n```').single.code, 'a\n~~~\nb');
      expect(diagramsIn('````mermaid\na\n```\nb\n`````').single.code, 'a\n```\nb');
      expect(diagramsIn('```mermaid\na\n``` js\nb\n  ```  ').single.code, 'a\n``` js\nb');
      expect(diagramsIn('  ```  mermaid  \na\n```').single, const Diagram(from: 1, to: 3, code: 'a'));
    });
  });

  group('the diagrams kept with the state', () {
    test('are where the note has them, from the first backtick to the end of the closing line', () {
      final state = _state('Before\n\n```mermaid\nflowchart TD\n  A --> B\n```\n\nAfter');
      final block = state.field(diagramBlocks).single;
      expect(state.doc.sliceString(block.from, block.to), '```mermaid\nflowchart TD\n  A --> B\n```');
      expect(block.code, 'flowchart TD\n  A --> B');
      // A fence that ends the note ends where the note does.
      final last = _state('```mermaid\ngraph LR\n```');
      expect(last.field(diagramBlocks).single.to, last.doc.length);
    });

    test('are the same list across a change that left every diagram where and as it was', () {
      var state = _state('Before\n\n```mermaid\nflowchart TD\n```\n\nAfter');
      final before = state.field(diagramBlocks);
      // Typed after the diagram: nothing of it moved.
      state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.length, insert: ' words'))).state;
      expect(state.field(diagramBlocks), same(before));
      // The caret moved: the same.
      state = state.update(TransactionSpec(selection: EditorSelection.single(3))).state;
      expect(state.field(diagramBlocks), same(before));
    });

    test('move with what is typed before them, their words the same string', () {
      var state = _state('Before\n\n```mermaid\nflowchart TD\n```\n\nAfter');
      final before = state.field(diagramBlocks).single;
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 6, insert: ' the diagram'))).state;
      final after = state.field(diagramBlocks).single;
      expect(after.from, before.from + 12);
      expect(after.to, before.to + 12);
      expect(after.code, same(before.code));
      expect(_kept(state), diagramsIn(state.doc.toString()));
    });

    test('read a diagram again when its own lines change, and a fence typed, closed or broken reads the note', () {
      var state = _state('```mermaid\nflowchart TD\n```\n\nwords');
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 23, insert: '\n  A --> B'))).state;
      expect(state.field(diagramBlocks).single.code, 'flowchart TD\n  A --> B');
      // The closing fence broken: no diagram.
      final close = state.doc.toString().lastIndexOf('```');
      state = state.update(TransactionSpec(changes: ChangeSpec(from: close, to: close + 1))).state;
      expect(state.field(diagramBlocks), isEmpty);
      // And mended.
      state = state.update(TransactionSpec(changes: ChangeSpec(from: close, insert: '`'))).state;
      expect(state.field(diagramBlocks).single.code, 'flowchart TD\n  A --> B');
      // A second one typed under it, a letter at a time: there once its fence closes.
      const typed = '\n```mermaid\ngraph LR\n```';
      for (var i = 0; i < typed.length; i += 1) {
        state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.length, insert: typed[i]))).state;
        expect(_kept(state), diagramsIn(state.doc.toString()), reason: 'after ${i + 1} letters');
      }
      expect(state.field(diagramBlocks).length, 2);
    });

    test('say what reading the whole note would, through a thousand changes of every kind', () {
      final random = Random(20261010);
      const pieces = <String>['```', '~~~', '````', 'mermaid', '```mermaid', '~~~mermaid', '\n', '\n', '\n', ' ', 'a', 'flowchart TD', '  A --> B', '`', '~', 'words here', '```js'];
      var state = _state(['# Note', '', '```mermaid', 'flowchart TD', '  A --> B', '```', '', 'words', '', '~~~mermaid', 'graph LR', '~~~', '', '```js', 'const a = 1;', '```', ''].join('\n'));
      for (var step = 0; step < 1000; step += 1) {
        final length = state.doc.length;
        final from = random.nextInt(length + 1);
        final to = random.nextInt(3) == 0 ? min(length, from + random.nextInt(12)) : from;
        final insert = random.nextInt(4) == 0 ? '' : List<String>.generate(1 + random.nextInt(2), (_) => pieces[random.nextInt(pieces.length)]).join();
        if (from == to && insert.isEmpty) continue;
        state = state.update(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert))).state;
        expect(_kept(state), diagramsIn(state.doc.toString()), reason: 'step $step: $from-$to <- ${insert.replaceAll('\n', r'\n')}');
        for (final block in state.field(diagramBlocks)) {
          expect(state.doc.lineAt(block.from).from, block.from);
          expect(state.doc.lineAt(block.to).to, block.to);
        }
      }
    });

    test('several changes at once are each looked at', () {
      var state = _state('one\n\n```mermaid\ngraph LR\n```\n\ntwo\n\n```mermaid\ngraph TD\n```\n\nthree');
      final second = state.doc.toString().indexOf('graph TD');
      state = state
          .update(
            TransactionSpec(
              changes: <ChangeSpec>[
                const ChangeSpec(from: 0, insert: 'A line\n'),
                ChangeSpec(from: second + 8, insert: '\n  A --> B'),
                ChangeSpec(from: state.doc.length, insert: '!'),
              ],
            ),
          )
          .state;
      expect(_kept(state), diagramsIn(state.doc.toString()));
      expect(state.field(diagramBlocks).map((block) => block.code), ['graph LR', 'graph TD\n  A --> B']);
    });
  });

  group('what a change reads of the note', () {
    /// A note of two thousand lines with a diagram in the middle of it.
    String long() => [
      for (var i = 0; i < 1000; i += 1) 'A line of the note, number $i, with words enough to be a line.',
      '```mermaid',
      'flowchart TD',
      '  A[Speak] --> B[Note]',
      '```',
      for (var i = 0; i < 1000; i += 1) 'Another line, number $i.',
    ].join('\n');

    test('a letter typed outside a diagram reads its own line and no more; in a note with no diagram, the same', () {
      for (final doc in <String>[long(), long().replaceAll('```', '')]) {
        var state = _state(doc);
        DiagramWork.reset();
        for (var i = 0; i < 50; i += 1) {
          state = state.update(const TransactionSpec(changes: ChangeSpec(from: 20, insert: 'x'))).state;
        }
        // Each change looks at the line it is on, as it was and as it is.
        expect(DiagramWork.scans, 0);
        expect(DiagramWork.reads, 0);
        expect(DiagramWork.lines, 100);
      }
    });

    test('a letter typed inside a diagram reads that diagram again, not the note', () {
      var state = _state(long());
      final at = state.doc.toString().indexOf('flowchart TD') + 12;
      DiagramWork.reset();
      for (var i = 0; i < 20; i += 1) {
        state = state.update(TransactionSpec(changes: ChangeSpec(from: at + i, insert: 'x'))).state;
      }
      expect(DiagramWork.scans, 0);
      expect(DiagramWork.reads, 20);
      expect(state.field(diagramBlocks).single.code, startsWith('flowchart TD${'x' * 20}\n'));
    });

    test('a caret moved, and a change of something else, read nothing', () {
      var state = _state(long());
      DiagramWork.reset();
      for (var i = 0; i < 20; i += 1) {
        state = state.update(TransactionSpec(selection: EditorSelection.single(i * 40))).state;
      }
      expect((DiagramWork.scans, DiagramWork.reads, DiagramWork.lines), (0, 0, 0));
    });

    test('a fence typed reads the note once', () {
      var state = _state(long());
      DiagramWork.reset();
      state = state.update(TransactionSpec(changes: ChangeSpec(from: state.doc.length, insert: '\n```mermaid\ngraph LR\n```'))).state;
      expect(DiagramWork.scans, 1);
      expect(state.field(diagramBlocks).length, 2);
    });
  });
}
