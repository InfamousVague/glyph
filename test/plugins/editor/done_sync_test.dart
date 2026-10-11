// editor/doneSync.test.ts, case for case.
//
// What is asked differently: `settled()` is a turn of the event loop, as the page's `setTimeout(…, 0)` was, and
// `vi.waitFor` is support.dart's `until`. The views are not drawn: nothing here is.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/done_sync.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/mark_details.dart';

import 'support.dart';

const String a = 'https://www.notion.so/a-1234';
const String b = 'https://www.notion.so/b-5678';

/// What the service was asked to do, and whether it can write tasks at all.
final List<String> sent = <String>[];
bool writable = false;

MarkEntry ready(String url, Stage stage, {int editedAt = 1000, bool gone = false}) =>
    MarkReady(MarkDetails(url: url, title: 'A task', status: MarkStatus(stage == Stage.done ? 'Done' : 'To do', stage), editedAt: editedAt, readAt: 2000, gone: gone));

final StandIn notion = StandIn(readsUrl: (url) => url.startsWith('https://www.notion.so/'));

List<MarkAction> actions(String url, String words) {
  final entry = notion.known[url];
  if (!writable || entry is! MarkReady) return const <MarkAction>[];
  final done = entry.details.status?.stage == Stage.done;
  return <MarkAction>[
    MarkAction(
      id: done ? 'reopen' : 'done',
      label: '',
      busyLabel: '',
      icon: done ? MarkActionIcon.reopen : MarkActionIcon.done,
      run: () async {
        sent.add('${done ? 'reopen' : 'done'} $url');
        notion.known[url] = ready(url, done ? Stage.todo : Stage.done, editedAt: (entry.details.editedAt ?? 0) + 500);
        return null;
      },
    ),
  ];
}

EditorView open(String doc) {
  final view = EditorView(state: EditorState.create(doc: doc, extensions: Extension.list(<Extension>[history(), doneSync()])), wholeDocument: true);
  addTearDown(view.destroy);
  return view;
}

Future<void> settled() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    notion.actionsFor = actions;
    provideMarkDetails('notion', () => notion);
  });

  group('ticking a to-do whose task is done', () {
    setUp(() {
      notion.known.clear();
      sent.clear();
      writable = false;
    });

    test('ticks the box of an item whose task reads as done, and leaves the rest', () async {
      notion.known[a] = ready(a, Stage.done);
      notion.known[b] = ready(b, Stage.doing);
      final view = open('- [ ] milk [notion]($a)\n- [ ] eggs [notion]($b)\n- [ ] bread\n  - [ ] jam [notion]($a)\nplain [notion]($a)\n');
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n- [ ] eggs [notion]($b)\n- [ ] bread\n  - [x] jam [notion]($a)\nplain [notion]($a)\n');
    });

    test('ticks when the answer arrives later, and not for a task in the trash', () async {
      final view = open('- [ ] milk [notion]($a)\n- [ ] eggs [notion]($b)\n');
      await settled();
      expect(view.state.doc.toString(), contains('- [ ] milk'));
      notion.known[a] = ready(a, Stage.done);
      notion.known[b] = ready(b, Stage.done, gone: true);
      markDetailsChanged();
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n- [ ] eggs [notion]($b)\n');
    });

    test('is not undone with typing, and does not fight a box unticked by hand', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('- [ ] milk [notion]($a)\n');
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: 'more'), userEvent: 'input.type'));
      undo(view);
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n');
      // Unticked on purpose: the same answer from Notion does not tick it again.
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, to: 4, insert: ' '), userEvent: 'input.type'));
      markDetailsChanged();
      await settled();
      expect(view.state.doc.toString(), '- [ ] milk [notion]($a)\n');
      // The task changed in Notion since: it does.
      notion.known[a] = ready(a, Stage.done, editedAt: 3000);
      markDetailsChanged();
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n');
    });

    test('ticks an item linked the old way, its words the link', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('- [ ] [milk]($a)\n- [ ] read the [docs](https://example.com/d)\n');
      await settled();
      expect(view.state.doc.toString(), '- [x] [milk]($a)\n- [ ] read the [docs](https://example.com/d)\n');
    });

    test('ticks a linked item pasted into the note', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('plain\n');
      await settled();
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '- [ ] milk [notion]($a)\n')));
      await settled();
      expect(view.state.doc.toString(), 'plain\n- [x] milk [notion]($a)\n');
    });

    test('moves the item\'s card to Done, so a board says what its ticks say', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('# Jobs\n\n```board\nTo do: milk, eggs\nDoing:\nDone:\n```\n\n- [ ] milk [notion]($a) ^milk\n- [ ] eggs ^eggs\n');
      await settled();
      expect(view.state.doc.toString(), contains('- [x] milk'));
      expect(view.state.doc.toString(), contains('To do: eggs\nDoing:\nDone: milk'));
    });

    test('unticks the box of a task reopened in the service', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('- [ ] milk [notion]($a)\n');
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n');
      notion.known[a] = ready(a, Stage.doing, editedAt: 5000);
      markDetailsChanged();
      await settled();
      expect(view.state.doc.toString(), '- [ ] milk [notion]($a)\n');
    });
  });

  group('a box ticked in the note', () {
    setUp(() {
      notion.known.clear();
      sent.clear();
      writable = true;
    });

    test('marks its task done, and reopens it when unticked', () async {
      notion.known[a] = ready(a, Stage.todo);
      final view = open('- [ ] milk [notion]($a)\n- [ ] bread\n');
      await settled();
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, to: 4, insert: 'x'), userEvent: 'input'));
      // The send is a turn of its own and then the run's; however many hops that takes, it lands.
      await until(() => sent.join('|') == 'done $a');
      // A turn after the send, the box is still as it was set.
      await settled();
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n- [ ] bread\n');
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, to: 4, insert: ' '), userEvent: 'input'));
      await until(() => sent.join('|') == 'done $a|reopen $a');
      await settled();
      expect(view.state.doc.toString(), '- [ ] milk [notion]($a)\n- [ ] bread\n');
    });

    test('sends nothing for a plain to-do, or for a box the sync itself set', () async {
      notion.known[a] = ready(a, Stage.done);
      final view = open('- [ ] milk [notion]($a)\n- [ ] bread\n');
      await until(() => view.state.doc.toString() == '- [x] milk [notion]($a)\n- [ ] bread\n');
      final second = view.state.doc.line(2).from;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: second + 3, to: second + 4, insert: 'x'), userEvent: 'input'));
      await settled();
      expect(sent, isEmpty);
    });

    test('follows a numbered or starred to-do both ways, as it does a dashed one (core/itemSyntax.ts)', () {
      // It used to take only a bullet and one space: a numbered to-do never followed its task, nor its task it.
      notion.known[a] = ready(a, Stage.done);
      notion.known[b] = ready(b, Stage.done);
      final doc = Doc.of(<String>['1. [ ] milk [notion]($a)', '*  [ ] eggs [notion]($b)']);
      expect(boxesDue(doc, <String, int>{}).map((change) => (change.url, change.from, change.insert)), <(String, int, String)>[(a, 4, 'x'), (b, doc.line(2).from + 4, 'x')]);
      final state = EditorState.create(doc: '1. [ ] milk [notion]($a)\n');
      final tr = state.update(const TransactionSpec(changes: ChangeSpec(from: 4, to: 5, insert: 'x'), userEvent: 'input'));
      expect(flipsIn(tr), const <Flip>[Flip(name: 'notion', url: a, done: true)]);
    });

    test('keeps a box ticked by hand when its task can’t be written', () async {
      writable = false;
      notion.known[a] = ready(a, Stage.todo);
      final view = open('- [ ] milk [notion]($a)\n');
      await settled();
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, to: 4, insert: 'x'), userEvent: 'input'));
      await settled();
      markDetailsChanged();
      await settled();
      expect(sent, isEmpty);
      expect(view.state.doc.toString(), '- [x] milk [notion]($a)\n');
    });
  });
}
