// The keyboard's client against a scripted keyboard (support.dart `FakeIme`): each of the eight rules of
// docs/STAGE4.md ("Piece 0, the keyboard"), every row of the spike's table (typing, suggestions, glide, the
// double-space full stop, Enter, Backspace across the window's start, caret moves, cross-line selections), and
// typing, Enter and Backspace across lines and marks, composition, replacing a selection and paste.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/task_toggle.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/editor_widget.dart';
import 'package:ghost_md/editor/input/ime.dart';

import '../../support/render.dart';
import 'support.dart';

/// Thirty numbered paragraphs.
String paragraphs([int count = 30]) => <String>[for (var i = 0; i < count; i++) 'line $i of the note'].join('\n');

void main() {
  setUpAll(loadAppFonts);

  group('rule 1: the keyboard holds a real range of the note, and is not told what it knows', () {
    testWidgets('attaching shows the caret line and a neighbour each side', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 4);
      expect(rig.ime.attaches, 1);
      expect(rig.ime.text, 'line 9 of the note\nline 10 of the note\nline 11 of the note');
      expect(rig.ime.text, rig.window);
      expect(rig.ime.caret, 'line 9 of the note\n'.length + 4);
      expect(tester.testTextInput.isVisible, isTrue);
      await finish(tester);
    });

    testWidgets('typing pushes nothing: the keyboard already holds what it typed', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 4);
      final pushes = rig.ime.pushes;
      await rig.ime.type(' abc');
      expect(rig.doc, contains('line abc 10 of the note'));
      expect(rig.head, rig.at('line abc 10') + 8);
      expect(rig.ime.pushes, pushes);
      expect(rig.ime.text, rig.window);
      expect(rig.events, everyElement('input.type'));
      await finish(tester);
    });

    testWidgets('a change made elsewhere in the note, off the window, tells the keyboard nothing', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 4);
      final pushes = rig.ime.pushes;
      rig.view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'A title\n')));
      await tester.pump();
      expect(rig.ime.pushes, pushes);
      expect(rig.window, rig.ime.text);
      // And what is typed next still lands where the caret is.
      await rig.ime.type('!');
      expect(rig.doc, contains('line! 10 of the note'));
      await finish(tester);
    });
  });

  group('rule 2: Backspace is a key', () {
    testWidgets('the key deletes, and the keyboard is given the result', (tester) async {
      final rig = await pumpEditor(tester, 'one\ntwo\nthree', caret: 7);
      final pushes = rig.ime.pushes;
      await rig.ime.backspace();
      expect(rig.doc, 'one\ntw\nthree');
      expect(rig.ime.pushes, pushes + 1);
      expect(rig.ime.text, 'one\ntw\nthree');
      expect(rig.ime.caret, 6);
      expect(rig.events, <String>['delete.backward']);
      await finish(tester);
    });

    testWidgets('at a line start it joins the lines, across the window\'s start too', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10'));
      // Walk the caret to the window's first line with the keyboard's own cursor control, then to offset 0.
      await rig.ime.select(0);
      expect(rig.head, rig.at('line 9'));
      await rig.ime.backspace();
      expect(rig.doc, contains('line 8 of the noteline 9 of the note'));
      expect(rig.head, rig.at('line 9'));
      expect(rig.ime.text, rig.window);
      expect(rig.window, startsWith('line 7 of the note\n'));
      await finish(tester);
    });

    testWidgets('through a list marker it takes the marker whole (deleteMarkupBackward)', (tester) async {
      final rig = await pumpEditor(tester, 'Shopping\n- milk\n- ', caret: 18);
      await rig.ime.backspace();
      // lang-markdown: the marker becomes its indentation first, then goes.
      expect(rig.doc, 'Shopping\n- milk\n  ');
      await rig.ime.backspace();
      expect(rig.doc, 'Shopping\n- milk\n');
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });

    testWidgets('a selection is deleted by the key', (tester) async {
      final rig = await pumpEditor(tester, 'one two three');
      await rig.place(4, 8);
      await rig.ime.backspace();
      expect(rig.doc, 'one three');
      expect(rig.events.last, 'delete.selection');
      expect(rig.ime.text, 'one three');
      await finish(tester);
    });

    testWidgets('a deletion delta is accepted too: a selection as it is, one character as the key it stands for', (tester) async {
      final rig = await pumpEditor(tester, 'one two three\n\n- ', caret: 0);
      await rig.place(4, 8);
      rig.events.clear();
      var pushes = rig.ime.pushes;
      await rig.ime.send([rig.ime.edit(4, 8, '')]);
      expect(rig.doc, 'one three\n\n- ');
      expect(rig.events, <String>['delete.selection']);
      expect(rig.ime.pushes, pushes, reason: 'the keyboard deleted it itself');

      // A keyboard that deletes the character before the caret itself (Samsung's does): still Backspace.
      await rig.place(rig.doc.length);
      pushes = rig.ime.pushes;
      await rig.ime.send([rig.ime.edit(rig.ime.caret - 1, rig.ime.caret, '')]);
      expect(rig.doc, 'one three\n\n', reason: 'the marker went whole, not its one space');
      expect(rig.ime.pushes, pushes + 1);
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });
  });

  group('rule 3: Enter is an inserted line break', () {
    testWidgets('in a paragraph it splits the line and pushes nothing', (tester) async {
      final rig = await pumpEditor(tester, 'onetwo', caret: 3);
      final pushes = rig.ime.pushes;
      await rig.ime.enter();
      expect(rig.doc, 'one\ntwo');
      expect(rig.head, 4);
      expect(rig.events, <String>['input']);
      expect(rig.ime.pushes, pushes);
      await finish(tester);
    });

    testWidgets('where the command does more than break the line, the keyboard is given what it did', (tester) async {
      // insertNewlineAndIndent takes the spaces round the caret with it.
      final rig = await pumpEditor(tester, 'one two', caret: 3);
      final pushes = rig.ime.pushes;
      await rig.ime.enter();
      expect(rig.doc, 'one\ntwo');
      expect(rig.ime.pushes, pushes + 1);
      expect(rig.ime.text, 'one\ntwo');
      expect(rig.ime.caret, 4);
      await finish(tester);
    });

    testWidgets('in a list it continues the list (insertNewlineContinueMarkup) and the keyboard is given the marker', (tester) async {
      final rig = await pumpEditor(tester, '- milk', caret: 6);
      final pushes = rig.ime.pushes;
      await rig.ime.enter();
      expect(rig.doc, '- milk\n- ');
      expect(rig.head, 9);
      expect(rig.ime.pushes, pushes + 1);
      expect(rig.ime.text, '- milk\n- ');
      expect(rig.ime.caret, 9);
      await rig.ime.type('eggs');
      expect(rig.doc, '- milk\n- eggs');
      // Enter on an empty item ends the list.
      await rig.ime.enter();
      await rig.ime.enter();
      expect(rig.doc, '- milk\n- eggs\n');
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });

    testWidgets('a to-do continues as an empty to-do, a numbered list with the next number', (tester) async {
      var rig = await pumpEditor(tester, '- [x] done', caret: 10);
      await rig.ime.enter();
      expect(rig.doc, '- [x] done\n- [ ] ');
      await finish(tester);
      rig = await pumpEditor(tester, '1. first', caret: 8);
      await rig.ime.enter();
      expect(rig.doc, '1. first\n2. ');
      expect(rig.ime.text, rig.doc);
      await finish(tester);
    });

    testWidgets('performAction(newline) is the same Enter, for a keyboard that sends it', (tester) async {
      final rig = await pumpEditor(tester, '- milk', caret: 6);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(rig.doc, '- milk\n- ');
      expect(rig.ime.text, '- milk\n- ');
      await finish(tester);
    });
  });

  group('rule 4: a swap the keyboard cannot see', () {
    testWidgets('new text at the same offsets attaches again', (tester) async {
      final rig = await pumpEditor(tester, '- [ ] milk\nwords', caret: 13);
      final attaches = rig.ime.attaches;
      // A box ticked by a tap: one character changes, the caret does not move.
      rig.view.dispatch(toggleBox(rig.view.state, boxAt(rig.view.state, 0)!));
      await tester.pump();
      expect(rig.doc, '- [x] milk\nwords');
      expect(rig.ime.attaches, attaches + 1);
      expect(rig.ime.text, '- [x] milk\nwords');
      expect(rig.ime.caret, 13);
      // The new connection is the one the keyboard types through.
      await rig.ime.type('!');
      expect(rig.doc, '- [x] milk\nwo!rds');
      await finish(tester);
    });

    testWidgets('a window swapped for another whose offsets come out the same attaches again', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 11') + 4);
      final attaches = rig.ime.attaches;
      final offset = rig.ime.caret;
      // Twelve lines on, the same column: every line here is as long, so the offsets in the window are the same.
      await rig.place(rig.at('line 23') + 4);
      expect(rig.ime.caret, offset);
      expect(rig.ime.text, 'line 22 of the note\nline 23 of the note\nline 24 of the note');
      expect(rig.ime.attaches, attaches + 1);
      await finish(tester);
    });

    testWidgets('a caret moved inside the window is an ordinary push', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 4);
      final attaches = rig.ime.attaches, pushes = rig.ime.pushes;
      await rig.place(rig.at('line 10') + 7);
      expect(rig.ime.attaches, attaches);
      expect(rig.ime.pushes, pushes + 1);
      expect(rig.ime.caret, 'line 9 of the note\n'.length + 7);
      await finish(tester);
    });
  });

  group('rule 5: the window is kept lazily', () {
    testWidgets('it stays while the caret is inside it and is made again at its first or last line', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 2);
      final from = rig.client.windowFrom;
      // Enter three times in the middle: the window grows, nothing is pushed.
      final pushes = rig.ime.pushes;
      await rig.ime.enter();
      await rig.ime.enter();
      await rig.ime.enter();
      expect(rig.ime.pushes, pushes);
      expect(rig.client.windowFrom, from);
      expect(rig.window.split('\n').length, 6);
      expect(rig.window, rig.ime.text);
      // To the window's last line: a new window round it.
      await rig.place(rig.at('line 11') + 2);
      expect(rig.window, 'ne 10 of the note\nline 11 of the note\nline 12 of the note');
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });

    testWidgets('past a dozen lines it is made again', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 2);
      final from = rig.client.windowFrom;
      var most = 0;
      for (var i = 0; i < EditorIme.maxLines * 2; i++) {
        await rig.ime.enter();
        final lines = rig.window.split('\n').length;
        if (lines > most) most = lines;
      }
      expect(most, EditorIme.maxLines + 1);
      expect(rig.client.windowFrom, greaterThan(from));
      expect(rig.ime.text, rig.window);
      expect(rig.ime.caret, rig.head - rig.client.windowFrom);
      await finish(tester);
    });

    testWidgets('not in the middle of a composition: a caret on the window\'s last line keeps it', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 2);
      final from = rig.client.windowFrom;
      // A word composed at the end of the caret's line, then Enter typed into the composition's batch: the caret
      // is on a new line, and the keyboard goes on composing on the window's last line.
      await rig.ime.select(rig.ime.text.length);
      expect(rig.head, rig.at('line 11') + 'line 11 of the note'.length);
      expect(rig.client.windowFrom, isNot(from), reason: 'nothing was being composed: the window is made again');
      final kept = rig.client.windowFrom, pushes = rig.ime.pushes;
      await rig.ime.select(rig.ime.text.indexOf('line 11') + 'line 11 of the note'.length);
      await rig.ime.compose('abc');
      // The keyboard's caret goes to the window's very end with the composition still open.
      await rig.ime.send([rig.ime.move(TextSelection.collapsed(offset: rig.ime.text.length), composing: rig.ime.value.composing)]);
      expect(rig.client.composing, isTrue);
      expect(rig.head, rig.at('line 12') + 'line 12 of the note'.length);
      expect(rig.client.windowFrom, kept, reason: 'the window is kept while composing');
      expect(rig.ime.pushes, pushes);
      // Committed: now it is made again round the caret.
      await rig.ime.commit();
      expect(rig.client.windowFrom, isNot(kept));
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });

    testWidgets('a selection too long to show is shown clamped, and what replaces it replaces all of it', (tester) async {
      final doc = paragraphs(1200);
      final rig = await pumpEditor(tester, doc, caret: 0);
      await rig.place(0, doc.length);
      expect(rig.ime.text.length, lessThan(100));
      expect(rig.ime.text, rig.window);
      // The keyboard types over what it thinks is selected.
      final sel = rig.ime.value.selection;
      await rig.ime.send([rig.ime.edit(sel.start, sel.end, 'x')]);
      expect(rig.doc, 'x');
      expect(rig.ime.text, 'x');
      await finish(tester);
    });
  });

  group('rule 6: a batch is applied whole, then the keyboard is synced once', () {
    testWidgets('every delta of a batch lands, in order', (tester) async {
      final rig = await pumpEditor(tester, '- milk', caret: 6);
      final pushes = rig.ime.pushes;
      // "s", Enter, "e" in one batch: the last is made against text the editor has since changed.
      final a = rig.ime.edit(6, 6, 's');
      final b = rig.ime.edit(7, 7, '\n');
      await rig.ime.send([a, b]);
      expect(rig.doc, '- milks\n- ');
      expect(rig.ime.pushes, pushes + 1, reason: 'one push for the batch');
      expect(rig.ime.text, '- milks\n- ');
      await finish(tester);
    });

    testWidgets('a delta made before the last push reached the keyboard is mapped onto the note as it is', (tester) async {
      final rig = await pumpEditor(tester, '- milk', caret: 6);
      // Enter, and before the keyboard hears of the marker it types "e" after its own line break.
      final enter = rig.ime.edit(6, 6, '\n');
      final stale = rig.ime.edit(7, 7, 'e');
      await rig.ime.send([enter]);
      expect(rig.doc, '- milk\n- ');
      final attaches = rig.ime.attaches;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
            rig.ime.client,
            <String, dynamic>{
              'deltas': [stale],
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
      expect(rig.doc, '- milk\n- e');
      expect(rig.head, 10);
      // The keyboard's picture was wrong: the input is restarted on what the note says.
      expect(rig.ime.attaches, attaches + 1);
      expect(rig.ime.text, '- milk\n- e');
      await finish(tester);
    });

    testWidgets('a delta against text the keyboard should not hold is dropped, and the input restarted', (tester) async {
      final rig = await pumpEditor(tester, 'one\ntwo\nthree', caret: 5);
      final attaches = rig.ime.attaches;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.textInput.name,
        SystemChannels.textInput.codec.encodeMethodCall(
          MethodCall('TextInputClient.updateEditingStateWithDeltas', <dynamic>[
            rig.ime.client,
            <String, dynamic>{
              'deltas': [
                <String, dynamic>{
                  'oldText': 'something else entirely',
                  'deltaText': 'x',
                  'deltaStart': 3,
                  'deltaEnd': 3,
                  'selectionBase': 4,
                  'selectionExtent': 4,
                  'selectionAffinity': 'TextAffinity.downstream',
                  'selectionIsDirectional': false,
                  'composingBase': -1,
                  'composingExtent': -1,
                },
              ],
            },
          ]),
        ),
        (_) {},
      );
      await tester.pump();
      expect(rig.doc, 'one\ntwo\nthree');
      expect(rig.ime.attaches, attaches + 1);
      expect(rig.ime.text, 'one\ntwo\nthree');
      expect(rig.ime.caret, 5);
      await finish(tester);
    });
  });

  group('rule 7: composing', () {
    testWidgets('a word composed is typed as it goes, as compose events, and the view knows', (tester) async {
      final rig = await pumpEditor(tester, 'one \nnext', caret: 4);
      final pushes = rig.ime.pushes;
      await rig.ime.compose('hel');
      expect(rig.doc, 'one hel\nnext');
      expect(rig.events, <String>['input.type.compose', 'input.type.compose', 'input.type.compose']);
      expect(rig.view.composing, isTrue);
      expect(rig.client.composingRange, (from: 4, to: 7));
      expect(rig.ime.pushes, pushes);
      // Each letter was one letter's change, not the word written again.
      await rig.ime.compose('lo');
      expect(rig.doc, 'one hello\nnext');
      // Committed: the underline goes, nothing is pushed, and the view is told with an update.
      rig.events.clear();
      await rig.ime.commit();
      expect(rig.view.composing, isFalse);
      expect(rig.client.composing, isFalse);
      expect(rig.events, <String>[''], reason: 'an update with no change, so the caret line is drawn as itself again');
      expect(rig.ime.pushes, pushes);
      await finish(tester);
    });

    testWidgets('a suggestion taken replaces the word', (tester) async {
      final rig = await pumpEditor(tester, '', caret: 0);
      await rig.ime.compose('helo');
      // The keyboard's own correction: the composed word replaced, a space after, composing over.
      await rig.ime.send([rig.ime.edit(0, 4, 'hello ')]);
      expect(rig.doc, 'hello ');
      expect(rig.head, 6);
      expect(rig.events.last, 'input.type');
      expect(rig.view.composing, isFalse);
      await finish(tester);
    });

    testWidgets('a caret the editor moves ends the composition: the next push has none', (tester) async {
      final rig = await pumpEditor(tester, 'one \nnext', caret: 4);
      await rig.ime.compose('hel');
      await rig.place(1);
      expect(rig.client.composing, isFalse);
      expect(rig.view.composing, isFalse);
      expect(rig.ime.value.composing, TextRange.empty);
      expect(rig.ime.caret, 1);
      await finish(tester);
    });

    testWidgets('a change elsewhere keeps the composition, mapped', (tester) async {
      final rig = await pumpEditor(tester, 'one \nnext', caret: 4);
      await rig.ime.compose('hel');
      // Something else writes at the start of the window (a sync from another device).
      rig.view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: '>> ')));
      await tester.pump();
      expect(rig.doc, '>> one hel\nnext');
      expect(rig.client.composingRange, (from: 7, to: 10));
      expect(rig.view.composing, isTrue);
      expect(rig.ime.value.composing, const TextRange(start: 7, end: 10));
      expect(rig.ime.value.composing.textInside(rig.ime.text), 'hel');
      // And the word goes on.
      await rig.ime.compose('p');
      expect(rig.doc, '>> one help\nnext');
      await finish(tester);
    });

    testWidgets('a change to the composing text itself ends the composition', (tester) async {
      final rig = await pumpEditor(tester, 'one \nnext', caret: 4);
      await rig.ime.compose('hel');
      rig.view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 5, to: 6, insert: 'E')));
      await tester.pump();
      expect(rig.doc, 'one hEl\nnext');
      expect(rig.client.composing, isFalse);
      expect(rig.ime.value.composing, TextRange.empty);
      await finish(tester);
    });
  });

  group('rule 8: the keyboard is told where things are', () {
    testWidgets('the editor\'s box, the caret and the composing run, after a frame, when they move', (tester) async {
      final rig = await pumpEditor(tester, 'one two\nthree', caret: 3);
      var calls = rig.ime.takeCalls();
      expect(calls, containsAll(<String>['TextInput.setClient', 'TextInput.setEditingState', 'TextInput.show', 'TextInput.setEditableSizeAndTransform', 'TextInput.setCaretRect', 'TextInput.setMarkedTextRect']));
      final caret = rig.ime.log.lastWhere((c) => c.method == 'TextInput.setCaretRect').arguments as Map;
      final at = rig.view.coordsAtPos(3)!;
      expect(caret['x'], closeTo(at.left, 0.01));
      expect(caret['y'], closeTo(at.top, 0.01));
      expect(caret['height'], closeTo(at.height, 0.01));
      // Typing moves the caret: the caret's rectangle again, the box not.
      await rig.ime.type('x');
      await tester.pump();
      calls = rig.ime.takeCalls();
      expect(calls, contains('TextInput.setCaretRect'));
      expect(calls, isNot(contains('TextInput.setEditableSizeAndTransform')));
      // Nothing moved: nothing sent.
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.ime.takeCalls(), isEmpty);
      await finish(tester);
    });
  });

  group('the spike\'s table', () {
    testWidgets('glide typing: a word and its space at once', (tester) async {
      final rig = await pumpEditor(tester, 'one ', caret: 4);
      final pushes = rig.ime.pushes;
      await rig.ime.send([rig.ime.edit(4, 4, 'quick ')]);
      expect(rig.doc, 'one quick ');
      expect(rig.head, 10);
      expect(rig.ime.pushes, pushes);
      await finish(tester);
    });

    testWidgets('the double-space full stop: a replacement', (tester) async {
      final rig = await pumpEditor(tester, 'one ', caret: 4);
      await rig.ime.send([rig.ime.edit(3, 4, '. ')]);
      expect(rig.doc, 'one. ');
      expect(rig.head, 5);
      expect(rig.events, <String>['input.type']);
      await finish(tester);
    });

    testWidgets('a caret moved by the keyboard, and a selection it makes across lines', (tester) async {
      final doc = paragraphs();
      final rig = await pumpEditor(tester, doc, caret: doc.indexOf('line 10') + 4);
      final pushes = rig.ime.pushes;
      await rig.ime.select(rig.ime.caret + 3);
      expect(rig.head, rig.at('line 10') + 7);
      expect(rig.events, <String>['select']);
      expect(rig.ime.pushes, pushes, reason: 'the keyboard knows where its own caret is');
      // A selection from the line before into the caret's line.
      await rig.ime.select(5, 'line 9 of the note\n'.length + 4);
      expect(rig.anchor, rig.at('line 9') + 5);
      expect(rig.head, rig.at('line 10') + 4);
      // Typed over.
      final sel = rig.ime.value.selection;
      await rig.ime.send([rig.ime.edit(sel.start, sel.end, 'X')]);
      expect(rig.doc, contains('line 8 of the note\nline X 10 of the note\nline 11'));
      await finish(tester);
    });
  });

  group('typing', () {
    testWidgets('marks typed a key at a time, across lines', (tester) async {
      final rig = await pumpEditor(tester, '', caret: 0);
      await rig.ime.type('# Title');
      await rig.ime.enter();
      await rig.ime.type('some **bold** words');
      await rig.ime.enter();
      await rig.ime.type('- a');
      await rig.ime.enter();
      await rig.ime.type('b');
      expect(rig.doc, '# Title\nsome **bold** words\n- a\n- b');
      expect(rig.ime.text, rig.window);
      // Back through the marker and the line start.
      await rig.ime.backspace();
      await rig.ime.backspace();
      expect(rig.doc, '# Title\nsome **bold** words\n- a\n  ');
      await rig.ime.backspace();
      expect(rig.doc, '# Title\nsome **bold** words\n- a\n');
      await rig.ime.backspace();
      expect(rig.doc, '# Title\nsome **bold** words\n- a');
      expect(rig.ime.text, rig.window);
      expect(rig.ime.caret, rig.head - rig.client.windowFrom);
      await finish(tester);
    });

    testWidgets('a selection replaced by what is typed', (tester) async {
      final rig = await pumpEditor(tester, 'one two three');
      await rig.place(4, 7);
      expect(rig.ime.value.selection, const TextSelection(baseOffset: 4, extentOffset: 7));
      await rig.ime.type('2');
      expect(rig.doc, 'one 2 three');
      expect(rig.head, 5);
      expect(rig.events.last, 'input.type');
      await finish(tester);
    });

    testWidgets('undo takes typing back and the keyboard is given the note as it was', (tester) async {
      final rig = await pumpEditor(tester, 'one', caret: 3);
      await rig.ime.type(' two');
      expect(undo(rig.view), isTrue);
      await tester.pump();
      expect(rig.doc, 'one');
      expect(rig.ime.text, 'one');
      expect(rig.ime.caret, 3);
      await finish(tester);
    });
  });

  group('paste', () {
    testWidgets('the controller pastes as input.paste, replacing the selection', (tester) async {
      final rig = await pumpEditor(tester, 'one two three');
      await rig.place(4, 7);
      rig.events.clear();
      expect(await rig.controller.paste('2\nand'), isTrue);
      await tester.pump();
      expect(rig.doc, 'one 2\nand three');
      expect(rig.events, <String>['input.paste']);
      expect(rig.ime.text, rig.window);
      await finish(tester);
    });

    testWidgets('from the clipboard when no text is given; cut and copy fill it', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clipboard};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final rig = await pumpEditor(tester, 'one two three');
      await rig.place(4, 7);
      expect(await rig.controller.copy(), isTrue);
      expect(clipboard, 'two');
      expect(await rig.controller.cut(), isTrue);
      await tester.pump();
      expect(rig.doc, 'one  three');
      expect(rig.events.last, 'delete.cut');
      await rig.place(0);
      expect(await rig.controller.paste(), isTrue);
      await tester.pump();
      expect(rig.doc, 'twoone  three');
      await finish(tester);
    });

    testWidgets('a keyboard that commits several lines at once (its clipboard row) is a paste', (tester) async {
      final rig = await pumpEditor(tester, 'one', caret: 3);
      await rig.ime.send([rig.ime.edit(3, 3, ' two\nthree')]);
      expect(rig.doc, 'one two\nthree');
      expect(rig.events, <String>['input.paste']);
      await finish(tester);
    });

    testWidgets('a plugin\'s paste handler is asked first', (tester) async {
      final seen = <String>[];
      final rig = await pumpEditor(
        tester,
        'one',
        caret: 3,
        more: [
          EditorViewLike.eventHandlers(EditorEventHandlers(paste: (text, view) {
            seen.add(text);
            return true;
          })),
        ],
      );
      await rig.controller.paste('https://example.com');
      expect(seen, <String>['https://example.com']);
      expect(rig.doc, 'one');
      await finish(tester);
    });
  });

  group('the keyboard\'s settings', () {
    testWidgets('prose: corrections, sentences, suggestions, deltas, many lines', (tester) async {
      final rig = await pumpEditor(tester, 'one');
      final config = rig.ime.config;
      expect(config['autocorrect'], isTrue);
      expect(config['enableSuggestions'], isTrue);
      expect(config['textCapitalization'], 'TextCapitalization.sentences');
      expect(config['enableDeltaModel'], isTrue);
      expect((config['inputType'] as Map)['name'], 'TextInputType.multiline');
      expect(config['inputAction'], 'TextInputAction.newline');
      // Turned off in place: the same connection, new settings.
      final attaches = rig.ime.attaches;
      setAssist(rig.view, false);
      await tester.pump();
      expect(rig.ime.attaches, attaches);
      expect(rig.ime.config['autocorrect'], isFalse);
      expect(rig.ime.config['enableSuggestions'], isFalse);
      expect(rig.ime.config['textCapitalization'], 'TextCapitalization.none');
      await finish(tester);
    });

    testWidgets('a note that cannot be edited has no keyboard', (tester) async {
      final rig = await pumpEditor(tester, 'one', readOnly: true);
      expect(rig.ime.log.where((c) => c.method == 'TextInput.setClient'), isEmpty);
      expect(tester.testTextInput.isVisible, isFalse);
      await finish(tester);
    });

    testWidgets('losing focus closes the connection', (tester) async {
      final rig = await pumpEditor(tester, 'one');
      expect(tester.testTextInput.isVisible, isTrue);
      rig.controller.unfocus();
      await tester.pump();
      expect(rig.view.hasFocus, isFalse);
      expect(rig.ime.log.map((c) => c.method), contains('TextInput.clearClient'));
      await finish(tester);
    });
  });

  group('the caret stays in sight', () {
    testWidgets('when the keyboard rises over it, with 56 px to spare', (tester) async {
      final doc = paragraphs(60);
      final rig = await pumpEditor(tester, doc, focus: false);
      // A line near the foot of the screen.
      final line = drawn(tester).lastWhere((l) => l.localToGlobal(Offset.zero).dy < 780);
      await rig.place(line.from + 2);
      await rig.focus();
      expect(rig.scroll.offset, 0);
      final before = rig.view.coordsAtPos(rig.head)!;
      // The keyboard takes 300 px of the foot.
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final after = rig.view.coordsAtPos(rig.head)!;
      expect(rig.scroll.offset, greaterThan(0));
      expect(after.bottom, lessThanOrEqualTo(844 - 300 - 56 + 0.5));
      expect(after.bottom, greaterThan(844 - 300 - 56 - 30), reason: 'no further than it has to go');
      expect(before.bottom, greaterThan(844 - 300));
      tester.view.resetViewInsets();
      await finish(tester);
    });

    testWidgets('typing at the foot scrolls the line up clear of the page\'s foot (footClearAt)', (tester) async {
      final doc = paragraphs(60);
      final rig = await pumpEditor(tester, doc, footClear: 96);
      final line = drawn(tester).lastWhere((l) => l.localToGlobal(Offset.zero).dy < 800);
      await rig.place(line.from + 2);
      await rig.ime.type('x');
      await tester.pump();
      await tester.pump();
      final at = rig.view.coordsAtPos(rig.head)!;
      // 96 px wanted, held to a third of the page.
      expect(at.bottom, lessThanOrEqualTo(844 - 96 - 5 + 0.5));
      expect(rig.scroll.offset, greaterThan(0));
      await finish(tester);
    });
  });
}
