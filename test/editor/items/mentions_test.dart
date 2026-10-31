// Mentions in the editor (lib/editor/items/mentions.dart; Matt, 2026-10-30: "add all 12"): a person's chip in their
// colour, a day's in the second ink and red once passed, none in code or the front matter or on an assignee's line;
// a day typed as words written as the day with the space after it, one step Undo takes back; and the at sign's
// question, which the picker's keys answer (lib/mentions/ui/mention_picker.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/commands.dart' show defaultKeymap;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/input/keymap.dart';
import 'package:ghost_md/editor/items/mentions.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/mentions/ui/mention_picker.dart';

import '../commands/support.dart';

final DateTime friday = DateTime(2026, 10, 30, 10);

String? hue(String handle) => const {'sam': 'sea', 'ana': 'rose', 'matt': 'amber'}[handle.toLowerCase()];

EditorView open(String doc, {String? Function(String handle)? hues = hue}) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(more: <Extension>[mentions(MentionHooks(hue: hues, today: () => friday))])));
  addTearDown(view.destroy);
  return view;
}

/// The mentions' marks, in order: the words each covers and what it wears.
List<String> chips(EditorView view) {
  final found = <({int from, String said})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final classes = (value.spec.className ?? '').split(' ');
      if (!classes.contains('cm-mention')) return null;
      final attrs = value.spec.attributes ?? const <String, String>{};
      final wears = classes.contains('cm-mentionDay') ? (attrs.containsKey('data-past') ? 'past' : 'day') : attrs['data-hue'] ?? '?';
      found.add((from: from, said: '${view.state.sliceDoc(from, to)}:$wears'));
      return null;
    });
  }
  found.sort((a, b) => a.from - b.from);
  return [for (final each in found) each.said];
}

/// Types [text] at the caret as a keyboard does: one change, `input.type`.
void type(TestView view, String text) {
  final at = view.head;
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, to: at, insert: text), selection: EditorSelection.single(at + text.length), userEvent: 'input.type'));
}

bool press(TestView view, String key) {
  for (final command in Keymap.forState(view.state).byKey[key] ?? const <BoundCommand>[]) {
    if (command.run != null && command.run!(view)) return true;
  }
  return false;
}

String shown(TestView view) => '${view.text.substring(0, view.head)}|${view.text.substring(view.head)}';

/// The picker as a note has it, with sam and ana in the team and Matt signed in.
MentionPicker picker() => MentionPicker(people: () => const [(handle: 'sam', hue: 'sea'), (handle: 'ana', hue: 'rose')], me: () => 'matt', today: () => friday);

TestView typing(String doc, {MentionPicker? with_, String? owner}) =>
    TestView.of(doc, doc.length, null, [history(), mentions(MentionHooks(hue: hue, today: () => friday, picking: with_, owner: () => owner)), editorKeymap.of(defaultKeymap)]);

/// What the picker was last told, as [TestView] has no update listeners: asked of the state each time.
void tell(MentionPicker p, TestView view, EditorViewLike as) => p.asked(as, view.state.field(mentionAsk));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the chips', () {
    test('a member in their hue, anyone else in the ink, a day in the second ink and red once it has passed', () {
      final view = open('Ask @sam and @Ana, cc @nobody, by @2026-11-06 or @2026-10-29, @today');
      expect(chips(view), ['@sam:sea', '@Ana:rose', '@nobody:ink', '@2026-11-06:day', '@2026-10-29:past', '@today:day']);
    });

    test('in a note of your own every person is the quiet ink', () {
      expect(chips(open('Ask @sam by @2026-11-06', hues: (_) => null)), ['@sam:ink', '@2026-11-06:day']);
    });

    test('none in code, an address, the front matter; an assignee on a list item wears the field’s chip, its day this one', () {
      final view = open('---\nowner: @sam\n---\nRun `@sam` see <https://x.y/@sam>\n- [ ] Ship it @sam @2026-11-02\n> @ana');
      expect(chips(view), ['@2026-11-02:day', '@ana:rose']);
    });

    test('follow the words as they change', () {
      final view = open('plain');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: ' @sam')));
      expect(chips(view), ['@sam:sea']);
    });
  });

  group('a day typed as words', () {
    test('becomes the day as the space after it is typed, and Undo brings the words back as they were before it', () {
      final view = typing('Call by ');
      for (final letter in '@next friday'.split('')) {
        type(view, letter);
      }
      type(view, ' ');
      expect(shown(view), 'Call by @2026-11-06 |');
      expect(undo(view), isTrue);
      expect(shown(view), 'Call by @next friday|');
    });

    test('@today and @tomorrow, and a name is left a name', () {
      final view = typing('');
      for (final letter in '@today @tomorrow @sam '.split('')) {
        type(view, letter);
      }
      expect(view.text, '@2026-10-30 @2026-10-31 @sam ');
    });

    test('not in code', () {
      final view = typing('`');
      for (final letter in '@today '.split('')) {
        type(view, letter);
      }
      expect(view.text, '`@today ');
    });

    test('in a team’s note a bare day is signed with the writer, and one Undo takes the words back (MARKDOWN_FIRST §11 decision 18)', () {
      final view = typing('Call by ', owner: 'matt');
      for (final letter in '@friday '.split('')) {
        type(view, letter);
      }
      expect(shown(view), 'Call by @matt @2026-11-06 |');
      expect(undo(view), isTrue);
      expect(shown(view), 'Call by @friday|');
      // A person named right before the day is the one it is for.
      final sams = typing('Ask ', owner: 'matt');
      for (final letter in '@sam @tomorrow '.split('')) {
        type(sams, letter);
      }
      expect(sams.text, 'Ask @sam @2026-10-31 ');
      // A note of the person's own keeps the bare day.
      final own = typing('Call by ');
      for (final letter in '@friday '.split('')) {
        type(own, letter);
      }
      expect(own.text, 'Call by @2026-11-06 ');
    });
  });

  group('the at sign’s question', () {
    test('asked as an at sign is typed where a mention may open, followed as more is typed, gone with a space after a name', () {
      final view = typing('Ask ');
      type(view, '@');
      expect(view.state.field(mentionAsk), const MentionAsk(4, ''));
      type(view, 's');
      type(view, 'a');
      expect(view.state.field(mentionAsk), const MentionAsk(4, 'sa'));
      type(view, ' ');
      expect(view.state.field(mentionAsk), isNull);
    });

    test('not asked inside a word, as an address is typed', () {
      final view = typing('sam');
      type(view, '@');
      expect(view.state.field(mentionAsk), isNull);
    });

    test('a day on its way keeps it open over its space', () {
      final view = typing('');
      for (final letter in '@next fr'.split('')) {
        type(view, letter);
      }
      expect(view.state.field(mentionAsk)?.query, 'next fr');
    });

    test('the caret leaving the words closes it', () {
      final view = typing('Ask ');
      type(view, '@');
      type(view, 's');
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      expect(view.state.field(mentionAsk), isNull);
    });
  });

  group('the picker', () {
    test('lists the people whose handle starts with what is typed, you among them, then the days', () {
      List<String> rows(String query) => [for (final c in mentionChoices(query, people: const [(handle: 'sam', hue: 'sea'), (handle: 'sandra', hue: null), (handle: 'ana', hue: 'rose')], me: 'matt', today: friday)) c.day ? 'day ${c.label} ${c.value}' : '@${c.value}${c.you ? ' (you)' : ''}'];
      expect(rows(''), ['@matt (you)', '@sam', '@sandra', '@ana', 'day Today 2026-10-30', 'day Tomorrow 2026-10-31']);
      expect(rows('sa'), ['@sam', '@sandra']);
      expect(rows('an'), ['@ana', '@sandra'], reason: 'those whose handle has it after those it starts');
      expect(rows('to'), ['day Today 2026-10-30', 'day Tomorrow 2026-10-31']);
      expect(rows('next friday'), ['day Next friday 2026-11-06']);
      expect(rows('zz'), isEmpty);
    });

    test('a note of your own offers you alone, and the days', () {
      expect([for (final c in mentionChoices('', people: const [], me: 'matt', today: friday)) c.value], ['matt', '2026-10-30', '2026-10-31']);
    });

    test('Enter writes the one lit, the arrows move it, Escape leaves the words as typed', () {
      final p = picker();
      final view = typing('Ask ', with_: p);
      final editor = open('');
      type(view, '@');
      type(view, 's');
      tell(p, view, editor);
      expect(p.open, isTrue);
      expect([for (final c in p.choices) c.value], ['sam']);
      expect(press(view, 'Enter'), isTrue);
      expect(shown(view), 'Ask @sam |');
      expect(view.state.field(mentionAsk), isNull);

      type(view, '@');
      tell(p, view, editor);
      expect(p.choices.first.value, 'matt');
      expect(press(view, 'ArrowDown'), isTrue);
      expect(press(view, 'ArrowDown'), isTrue);
      expect(p.choices[p.index].value, 'ana');
      expect(press(view, 'Tab'), isTrue);
      expect(view.text, 'Ask @sam @ana ');

      type(view, '@');
      type(view, 'z');
      tell(p, view, editor);
      expect(p.open, isFalse);
      expect(press(view, 'Escape'), isTrue);
      expect(view.state.field(mentionAsk), isNull);
      expect(view.text, 'Ask @sam @ana @z');
      // With nothing asked, Enter is the editor's own: a new line.
      press(view, 'Enter');
      expect(view.text, 'Ask @sam @ana @z\n');
    });

    test('a day picked is written as the day', () {
      final p = picker();
      final view = typing('Due ', with_: p);
      type(view, '@');
      type(view, 't');
      type(view, 'o');
      tell(p, view, open(''));
      expect([for (final c in p.choices) c.label], ['Today', 'Tomorrow']);
      press(view, 'ArrowDown');
      press(view, 'Enter');
      expect(view.text, 'Due @2026-10-31 ');
    });
  });
}
