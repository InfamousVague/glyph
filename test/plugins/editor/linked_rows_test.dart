// editor/linkedRows.test.ts, case for case.
//
// What is asked differently: the page's test replaced `markMenuMount.tsx` with a recorder; here the recorder is
// `linkedRows`'s own `mount`. A row's `title` and `aria-label` are the drawn row's `title` and `label` (its
// tooltip and what a screen reader says), `data-stage`, `data-late` and `data-open` what its pills were built
// with, and "a tap on the empty rest of the row is the note's" is also asked of `takesPointer`, which is what the
// editor asks before it places a caret.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/mark_menu.dart';
import 'package:ghost_md/editor/items/mark_reads.dart';
import 'package:ghost_md/editor/media/linked_rows.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/mark_details.dart';

import '../../support/render.dart';
import 'support.dart';

const String task = 'https://www.notion.so/Buy-milk-3db522a4563081298304c129ce6004e4';

/// What the plugin knows about each task now.
final StandIn notion = StandIn(readsUrl: (url) => url.contains('notion.so/'));

void main() {
  setUpAll(() async {
    await loadAppFonts();
    provideMarkDetails('notion', () => notion);
  });

  group('what a line is linked to', () {
    test('finds an item’s mark, with the item’s words', () {
      expect(linkedOn('- [ ] Buy milk [notion]($task)', 40), const Linked(from: 40, name: 'notion', url: task, words: 'Buy milk', kind: LinkedKind.mark, item: true));
    });

    test('finds a link written the old way, and one in a sentence', () {
      final old = linkedOn('- [ ] [Buy milk]($task) on the way home')!;
      expect((old.kind, old.item, old.words), (LinkedKind.link, true, 'Buy milk on the way home'));
      final said = linkedOn('Remember [the task]($task) tomorrow.')!;
      expect((said.kind, said.item, said.words), (LinkedKind.link, false, 'the task'));
    });

    test('leaves lines with no link, or a link no plugin reads', () {
      expect(linkedOn('- [ ] Buy milk'), isNull);
      expect(linkedOn('- [ ] Read [the docs](https://example.com/docs)'), isNull);
    });

    test('unlinks, keeping the words', () {
      expect(unlinked('- [ ] Buy milk [notion]($task)', kind: LinkedKind.mark, url: task), '- [ ] Buy milk');
      // A board's anchor after the mark stays, so the card is still the item (lib/core/boards.dart).
      expect(unlinked('- [ ] Buy milk [notion]($task) ^buy-milk', kind: LinkedKind.mark, url: task), '- [ ] Buy milk ^buy-milk');
      // And a counter typed after it (lib/editor/items/counters.dart).
      expect(unlinked('- [ ] Buy milk [notion]($task) [2/6] ^buy-milk', kind: LinkedKind.mark, url: task), '- [ ] Buy milk [2/6] ^buy-milk');
      expect(unlinked('- [ ] [Buy milk]($task) on the way home', kind: LinkedKind.link, url: task), '- [ ] Buy milk on the way home');
    });
  });

  group('the row of pills under a linked line', () {
    final said = <String>[];
    final opened = <MarkMenuProps>[];
    var closed = 0;

    Future<EditorView> open(WidgetTester tester, String doc, {bool menus = true}) => pumpNote(
      tester,
      doc,
      more: <Extension>[
        linkedRows(
          menus ? LinkMenus(say: said.add) : null,
          mount: (props) {
            opened.add(props);
            return () => closed += 1;
          },
        ),
      ],
    );
    MarkEntry details({String title = 'Buy milk', MarkStatus? status, List<String> brief = const <String>[], bool gone = false}) =>
        MarkReady(MarkDetails(url: task, title: title, status: status, brief: brief, editedAt: 1, readAt: 1, gone: gone));
    List<LinkPill> pills(WidgetTester tester) => tester.widgetList<LinkPill>(find.byType(LinkPill)).toList();
    List<String> words(WidgetTester tester) => pills(tester).map((pill) => pill.text).toList();
    LinkRow row(WidgetTester tester) => tester.widget<LinkRow>(find.byType(LinkRow));

    setUp(() {
      notion.known.clear();
      opened.clear();
      closed = 0;
      said.clear();
    });

    testWidgets('says what the task is doing: its service, then its stage and status, then each fact, an overdue one marked', (tester) async {
      notion.known[task] = details(status: const MarkStatus('Doing', Stage.doing), brief: const <String>['P1', 'Overdue by 2 days']);
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(words(tester), <String>['Notion', 'Doing', 'P1', 'Overdue by 2 days']);
      expect(pills(tester).firstWhere((pill) => pill.kind == LinkPillKind.status).stage, Stage.doing);
      expect(pills(tester).map((pill) => pill.late), <bool>[false, false, false, true]);
      expect(row(tester).title, 'Buy milk');
    });

    testWidgets('names a stage in words where the board has none of its own, and says a task in the trash is there', (tester) async {
      notion.known[task] = details(status: const MarkStatus('', Stage.todo));
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(words(tester), <String>['Notion', 'To do']);
      notion.known[task] = details(gone: true, brief: const <String>['P1']);
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(words(tester), <String>['Notion', 'In trash']);
      expect(pills(tester)[1].gone, isTrue);
    });

    testWidgets('says so while the task is read, and when it cannot be', (tester) async {
      notion.known[task] = const MarkLoading();
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(words(tester), <String>['Notion', 'Reading…']);
      notion.known[task] = const MarkFailed('Notion said no');
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(words(tester), <String>['Notion', 'Can’t read it']);
      expect(pills(tester)[1].tip, 'Notion said no');
    });

    testWidgets('is drawn again when the task is renamed, so its tooltip and what a screen reader says follow', (tester) async {
      notion.known[task] = details(status: const MarkStatus('Doing', Stage.doing));
      final on = await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(row(tester).title, 'Buy milk');
      notion.known[task] = details(title: 'Buy oat milk', status: const MarkStatus('Doing', Stage.doing));
      on.dispatch(TransactionSpec(effects: detailsArrived.of(null)));
      await tester.pump();
      expect(row(tester).title, 'Buy oat milk');
      expect(row(tester).label, 'notion: Buy oat milk. Open its menu.');
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('notion: Buy oat milk. Open its menu.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('always draws a mark’s row, and an ordinary link’s only once it has been read', (tester) async {
      await open(tester, 'Remember [the task]($task) tomorrow.\n');
      expect(find.byType(LinkRow), findsNothing);
      notion.known[task] = details(status: const MarkStatus('Done', Stage.done));
      await open(tester, 'Remember [the task]($task) tomorrow.\n');
      expect(words(tester), <String>['Notion', 'Done']);
    });

    testWidgets('opens the drawer for its line on a tap on a pill, and closes it on another', (tester) async {
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      expect(row(tester).row.menus, isTrue);
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      expect(opened, hasLength(1));
      expect((opened[0].name, opened[0].url, opened[0].words), ('notion', task, 'Buy milk'));
      expect(row(tester).row.open, isTrue);
      expect(pills(tester).first.open, isTrue);
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      expect(closed, 1);
      expect(row(tester).row.open, isFalse);
    });

    testWidgets('leaves a tap on the empty rest of the row to the note, and opens nothing where menus are off', (tester) async {
      await open(tester, '- [ ] Buy milk [notion]($task)\n');
      final box = tester.getRect(find.byKey(const ValueKey<String>('cm-linkRow')));
      final empty = Offset(box.right - 30, box.center.dy), onPill = tester.getCenter(find.byType(LinkPill).first);
      await tester.tapAt(empty);
      await tester.pump();
      expect(opened, isEmpty);
      // What the editor asks before it places the caret: a pill keeps its press, the rest of the row does not.
      final widget = row(tester).row;
      expect(widget.takesPointer(PointerDownEvent(position: empty)), isFalse);
      expect(widget.takesPointer(PointerDownEvent(position: onPill)), isTrue);
      await open(tester, '- [ ] Buy milk [notion]($task)\n', menus: false);
      expect(row(tester).row.menus, isFalse);
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      expect(opened, isEmpty);
    });

    testWidgets('unlinks from the drawer, keeping the words, and closes it', (tester) async {
      final on = await open(tester, '- [ ] Buy milk [notion]($task) ^milk\nnext\n');
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      opened[0].unlink();
      await tester.pump();
      expect(on.state.doc.toString(), '- [ ] Buy milk ^milk\nnext\n');
      expect(closed, 1);
      expect(find.byType(LinkRow), findsNothing);
    });

    testWidgets('closes the drawer when its line loses its link some other way', (tester) async {
      final on = await open(tester, '- [ ] Buy milk [notion]($task)\n');
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      final line = on.state.doc.line(1);
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: line.from, to: line.to, insert: '- [ ] Buy milk')));
      expect(closed, 1);
      // And the open menu is let go of, once that update is done, so the next link on the line starts closed.
      await tester.pump();
      expect(openLinkMenu(on.state), isNull);
      on.dispatch(TransactionSpec(changes: ChangeSpec(from: on.state.doc.line(1).to, insert: ' [notion]($task)')));
      await tester.pump();
      expect(opened, hasLength(1));
    });
  });

  group('the drawer the row itself draws (not on the page, where a root of its own did)', () {
    testWidgets('is up over the note while the row’s menu is open, says what it did, and is gone when it closes', (tester) async {
      notion.known.clear();
      final said = <String>[];
      final on = await pumpNote(tester, '- [ ] Buy milk [notion]($task) ^milk\n', more: <Extension>[linkedRows(LinkMenus(say: said.add))]);
      expect(find.byType(MarkMenu), findsNothing);
      await tester.tap(find.byType(LinkPill).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MarkMenu), findsOneWidget);
      expect(find.text('Buy milk'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('markMenu-option-unlink')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(on.state.doc.toString(), '- [ ] Buy milk ^milk\n');
      expect(said, <String>['Unlinked. The words stay.']);
      expect(find.byType(MarkMenu), findsNothing);
    });
  });
}
