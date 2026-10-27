// Snippets as they are typed (lib/editor/input/snippets.dart; Matt, 2026-10-27: "build ... snippets"): a trigger and a
// space, Enter or Tab becomes the snippet's words, as one step Undo takes back to the trigger; never in code, nor in
// the front matter, nor while the keyboard composes.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/editor/commands/commands.dart' show defaultKeymap;
import 'package:ghost_md/editor/input/keymap.dart';
import 'package:ghost_md/editor/input/snippets.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';

import '../commands/support.dart';

final DateTime now = DateTime(2026, 10, 27, 16, 5);

const List<Snippet> mine = [
  Snippet(id: 's1', trigger: ';sig', text: 'Matt\nGhost.md'),
  Snippet(id: 's2', trigger: ';dear', text: 'Dear {cursor},'),
  Snippet(id: 'date', trigger: ';date', text: '{date}'),
];

/// The keys a note has under the snippets': lang-markdown's Enter, then the defaults.
final List<Extension> keys = [Prec.high(editorKeymap.of(markdownBindings)), editorKeymap.of(defaultKeymap)];

TestView viewOf(String doc, [int? caret]) => TestView.of(doc, caret ?? doc.length, null, [history(), snippetExpansion(() => mine, clock: () => now), ...keys]);

/// Types [text] at the caret as a keyboard does: one change, `input.type` (or composing).
void type(TestView view, String text, {String event = 'input.type', int? from}) {
  final at = view.head;
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: from ?? at, to: at, insert: text), selection: EditorSelection.single((from ?? at) + text.length), userEvent: event));
}

/// Presses a key the editor's keymaps bind, as runKey does: each binding in turn until one takes it.
bool press(TestView view, String key) {
  for (final command in Keymap.forState(view.state).byKey[key] ?? const <BoundCommand>[]) {
    if (command.run != null && command.run!(view)) return true;
  }
  return false;
}

/// The note with the caret as `|`.
String shown(TestView view) => '${view.text.substring(0, view.head)}|${view.text.substring(view.head)}';

void main() {
  test('a trigger and a space becomes its words, the space after them', () {
    final view = viewOf('Thanks, ;sig');
    type(view, ' ');
    expect(shown(view), 'Thanks, Matt\nGhost.md |');
    expect(view.dispatched.last.isUserEvent(snippetEvent), isTrue);
  });

  test('one Undo brings the trigger back as it was typed, and the words before it stay', () {
    final view = viewOf('');
    for (final letter in 'Thanks, ;sig'.split('')) {
      type(view, letter);
    }
    type(view, ' ');
    expect(view.text, 'Thanks, Matt\nGhost.md ');
    expect(view.undo_(), isTrue);
    expect(shown(view), 'Thanks, ;sig|');
    // And Redo writes it again.
    expect(view.redo_(), isTrue);
    expect(view.text, 'Thanks, Matt\nGhost.md ');
  });

  test('a keyboard committing the word with its space, as Gboard does, is the same', () {
    final view = viewOf(';s');
    type(view, 'sig ', from: 1);
    expect(shown(view), 'Matt\nGhost.md |');
  });

  test('the placeholders are filled at the moment, and {cursor} places the caret and takes the space', () {
    final date = viewOf(';date');
    type(date, ' ');
    expect(shown(date), '27 October 2026 |');
    final dear = viewOf(';dear');
    type(dear, ' ');
    expect(shown(dear), 'Dear |,');
  });

  test('Enter writes the words and then goes on as Enter would, a list going on, in one step', () {
    final view = viewOf('- ;date');
    expect(press(view, 'Enter'), isTrue);
    expect(shown(view), '- 27 October 2026\n- |');
    expect(view.undo_(), isTrue);
    expect(shown(view), '- ;date|');
    // Without a trigger Enter is Enter.
    final plain = viewOf('- lunch');
    expect(press(plain, 'Enter'), isTrue);
    expect(shown(plain), '- lunch\n- |');
  });

  test('Tab writes the words and nothing after them', () {
    final view = viewOf(';sig');
    expect(press(view, 'Tab'), isTrue);
    expect(shown(view), 'Matt\nGhost.md|');
    final dear = viewOf('Hi ;dear');
    expect(press(dear, 'Tab'), isTrue);
    expect(shown(dear), 'Hi Dear |,');
  });

  test('whatever the case it was typed in', () {
    final view = viewOf(';Sig');
    type(view, ' ');
    expect(view.text, 'Matt\nGhost.md ');
  });

  test('not inside a word, nor a trigger that is no snippet', () {
    for (final doc in ['x;sig', ';nope', ';sigs']) {
      final view = viewOf(doc);
      type(view, ' ');
      expect(view.text, '$doc ', reason: doc);
    }
  });

  test('not in code: a code span, a fence, an indented block', () {
    final span = viewOf('`;sig`', 5);
    type(span, ' ');
    expect(span.text, '`;sig `');
    final fence = viewOf('```\n;sig\n```', 8);
    type(fence, ' ');
    expect(fence.text, '```\n;sig \n```');
    expect(press(viewOf('```\n;sig\n```', 8), 'Tab'), isFalse);
    final block = viewOf('Words\n\n    ;sig');
    type(block, ' ');
    expect(block.text, 'Words\n\n    ;sig ');
  });

  test('not in the front matter, and at once after it', () {
    final front = viewOf('---\ntitle: ;sig\n---\nBody', 15);
    type(front, ' ');
    expect(front.text, '---\ntitle: ;sig \n---\nBody');
    final body = viewOf('---\ntitle: x\n---\n;sig');
    type(body, ' ');
    expect(body.text, '---\ntitle: x\n---\nMatt\nGhost.md ');
  });

  test('not while the keyboard composes, nor for a paste', () {
    final composing = viewOf(';sig');
    type(composing, ' ', event: 'input.type.compose');
    expect(composing.text, ';sig ');
    final pasted = viewOf(';sig');
    type(pasted, ' ', event: 'input.paste');
    expect(pasted.text, ';sig ');
  });

  test('the list is asked as a trigger is typed: one added in Settings works in a note already open', () {
    var list = <Snippet>[];
    final view = TestView.of(';sig', 4, null, [history(), snippetExpansion(() => list, clock: () => now)]);
    type(view, ' ');
    expect(view.text, ';sig ');
    list = [mine.first];
    for (final letter in ';sig'.split('')) {
      type(view, letter);
    }
    type(view, ' ');
    expect(view.text, ';sig Matt\nGhost.md ');
  });
}
