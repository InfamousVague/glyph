// Buttons in a note, drawn and pressed (lib/editor/buttons; lib/core/note_buttons.dart; Matt, 2026-10-30, of a list of
// plain-Markdown features: "add all 12"): a set written into the front matter as one change, a post and Claude asked
// first and run as a job with their plugin's mark, a failure said, an open and a make through the screen, a read-only
// view running only an open, the line as written on the caret's line, and the builder that writes one.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/buttons/button_builder.dart';
import 'package:ghost_md/editor/buttons/buttons.dart';
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/sheet/ask_first.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

late List<FirstAsk> asks;
bool answer = true;
late List<String> said;
late List<(String, String?, String?)> posts;
late List<(String, String?, String?)> claudes;
late List<String> opened;
late List<(String, String?, String?)> made;
late List<Job> ended;
Object? failWith;

ButtonWorld world() => ButtonWorld(
  post: (service, channel, text, body) async {
    if (failWith != null) throw failWith!;
    posts.add((service, channel, text));
    return channel == null ? '#general' : '#$channel';
  },
  claude: (noteId, title, {rule, prompt}) async {
    claudes.add((title, rule, prompt));
  },
  openNote: opened.add,
  openLink: opened.add,
  make: (template, place, title) {
    made.add((template, place, title));
    return template != 'Nothing';
  },
);

Future<EditorView> pumpNote(WidgetTester tester, String doc, {bool readOnly = false, double width = 390, int? caret}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(readOnly: readOnly, more: <Extension>[noteButtons(ButtonHooks(noteId: () => 'n1', title: () => 'Launch', world: world, say: said.add))]),
    ),
  );
  addTearDown(view.destroy);
  view.focusRequest = () => view.setFocused(true);
  await pumpApp(
    tester,
    size: Size(width, 844),
    prefs: AppPreferences(theme: 'light'),
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: SingleChildScrollView(child: EditorColumn(view: view)))),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  await tester.pump();
  return view;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder button(String label) => find.byKey(ValueKey<String>('note-button:$label'));

void main() {
  setUpAll(loadAppFonts);
  late StreamSubscription<JobEvent> heard;
  setUp(() {
    asks = [];
    answer = true;
    said = [];
    posts = [];
    claudes = [];
    opened = [];
    made = [];
    ended = [];
    failWith = null;
    debugAskFirst = (ask) async {
      asks.add(ask);
      return answer;
    };
    final record = Activity(clock: () => DateTime(2026, 10, 30, 10), store: () => MemoryStored());
    useActivity(record);
    heard = record.events.listen((event) {
      if (event.kind == JobEventKind.ended && event.job != null) ended.add(event.job!);
    });
  });
  tearDown(() async {
    debugAskFirst = null;
    await heard.cancel();
    useActivity(Activity());
  });

  for (final (where, width) in [('a phone', 390.0), ('a Mac', 1100.0)]) {
    testWidgets('a set writes its fields into the front matter as one change, on $where', (tester) async {
      final view = await pumpNote(tester, '---\ntype: ticket\nStatus: In progress\n---\n# Launch\n\n[Move to done](ghost:set?status=Done&assignee=Sam)\n', width: width);
      expect(button('Move to done'), findsOneWidget);
      await tester.tap(button('Move to done'));
      await settle(tester);
      expect(view.state.doc.toString(), '---\ntype: ticket\nStatus: Done\nassignee: Sam\n---\n# Launch\n\n[Move to done](ghost:set?status=Done&assignee=Sam)\n', reason: 'the key keeps the case it was written in');
      expect(asks, isEmpty, reason: 'a set reaches nothing past the note');
    });
  }

  testWidgets('a post asks first, posts nothing on Cancel, and runs as a job with Slack’s mark on Post', (tester) async {
    await pumpNote(tester, '# Launch\n\n[Tell the team](ghost:post?to=slack&channel=launch&text=Shipped%20it)\n');
    answer = false;
    await tester.tap(button('Tell the team'));
    await settle(tester);
    expect(asks.single.title, 'Post to Slack?');
    expect(asks.single.note, '“Shipped it” goes to launch.');
    expect(posts, isEmpty);
    expect(ended, isEmpty, reason: 'nothing begun before the yes');
    answer = true;
    await tester.tap(button('Tell the team'));
    await settle(tester);
    expect(posts, [('slack', 'launch', 'Shipped it')]);
    expect(said, ['Posted to #launch.']);
    expect(ended.single.plugin, 'slack');
    expect(ended.single.state, JobState.done);
    expect(ended.single.title, 'Tell the team');
  });

  testWidgets('a post that fails is said, and its job is the red row with the cause', (tester) async {
    await pumpNote(tester, '# Launch\n\n[Tell Discord](ghost:post?to=discord)\n');
    failWith = 'Discord has no channels on this device yet.';
    await tester.tap(button('Tell Discord'));
    await settle(tester);
    expect(asks.single.title, 'Post to Discord?');
    expect(said, ['Not posted. Discord has no channels on this device yet.']);
    expect(ended.single.state, JobState.failed);
    expect(ended.single.plugin, 'discord');
    expect(activity.value.single.cause, 'Not posted. Discord has no channels on this device yet.', reason: 'a failed job stays on the record, its red row, until it is dismissed');
  });

  testWidgets('Claude asks first, as it spends, and runs the rule on this note as a job with Claude’s mark', (tester) async {
    await pumpNote(tester, '# Launch\n\n[Tidy](ghost:claude?rule=Tidy%20my%20notes)\n');
    await tester.tap(button('Tidy'));
    await settle(tester);
    expect(asks.single.title, 'Ask Claude?');
    expect(asks.single.note, contains('It uses your Claude credits.'));
    expect(claudes, [('Launch', 'Tidy my notes', null)]);
    expect(ended.single.plugin, 'claude');
    expect(ended.single.kind, JobKind.ai);
  });

  testWidgets('an open and a make go through the screen, and a make with no such template says so', (tester) async {
    await pumpNote(tester, '# Launch\n\n[Roadmap](ghost:open?note=Roadmap) [Site](ghost:open?url=https%3A%2F%2Fghostmarkdown.com) [Bug](ghost:new?template=Bug%20report&in=Kiln) [None](ghost:new?template=Nothing)\n');
    await tester.tap(button('Roadmap'));
    await tester.tap(button('Site'));
    await tester.tap(button('Bug'));
    await tester.tap(button('None'));
    await settle(tester);
    expect(opened, ['Roadmap', 'https://ghostmarkdown.com']);
    expect(made, [('Bug report', 'Kiln', null), ('Nothing', null, null)]);
    expect(said, ['There is no template called “Nothing”.']);
    expect(asks, isEmpty);
  });

  testWidgets('a view that cannot be edited runs an open and nothing else', (tester) async {
    final view = await pumpNote(tester, '# Launch\n\n[Move to done](ghost:set?status=Done) [Tell](ghost:post?to=slack) [Roadmap](ghost:open?note=Roadmap)\n', readOnly: true);
    final before = view.state.doc.toString();
    await tester.tap(button('Move to done'));
    await tester.tap(button('Tell'));
    await tester.tap(button('Roadmap'));
    await settle(tester);
    expect(view.state.doc.toString(), before);
    expect(asks, isEmpty);
    expect(posts, isEmpty);
    expect(opened, ['Roadmap']);
    expect(tester.widget<NoteButtonChip>(find.ancestor(of: button('Tell'), matching: find.byType(NoteButtonChip))).runs, isFalse);
  });

  testWidgets('on the caret’s line the button is its words as written; inside code it is code', (tester) async {
    const doc = '# Launch\n\n[Move to done](ghost:set?status=Done)\n\n`[Not](ghost:set?status=Done)`\n';
    await pumpNote(tester, doc, caret: doc.indexOf('[Move'));
    expect(button('Move to done'), findsNothing);
    expect(button('Not'), findsNothing);
  });

  testWidgets('the builder writes the line a button is, the label suggested from what it does', (tester) async {
    String? wrote;
    await pumpApp(tester, size: const Size(390, 844), home: BackScope(child: ButtonBuilderSheet(onDone: (line) => wrote = line)));
    debugDisableShadows = true;
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('button-kind:set')));
    await settle(tester);
    expect(find.byKey(const ValueKey('button-preview')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('button-field:Value')), matching: find.byType(EditableText)), 'In review');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('button-add')));
    await settle(tester);
    expect(wrote, '[Move to In review](ghost:set?status=In%20review)');
  });

  test('the + and the / palette offer A button, under More, where the screen can build one', () {
    AddGates gates({required bool button, bool simple = false}) => readGates(picture: false, video: false, place: false, note: true, canvas: false, button: button, simple: simple);
    expect(moreRows(gates(button: true)).map((row) => row.id), contains('button'));
    expect(moreRows(gates(button: false)).map((row) => row.id), isNot(contains('button')));
    expect(topRows(gates(button: true), DateTime(2026, 10, 30)).map((row) => row.id), isNot(contains('button')), reason: 'behind More');
    expect(moreRows(gates(button: true, simple: true)).map((row) => row.id), contains('button'), reason: 'simple mode has it behind More too');
  });
}
