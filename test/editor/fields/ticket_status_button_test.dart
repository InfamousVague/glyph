// A ticket's status as a button (lib/notes/ticket_mark.dart `TicketStatusButton`; the web's `notes/TicketMark.tsx`
// and `TicketMark.module.css` `.statusButton`): what it says and wears for each status, the phone's rule that leaves
// it its mark alone, and the press. The page has no test file of its own for the button.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/fields/field_picker.dart';
import 'package:ghost_md/editor/fields/field_picks.dart';
import 'package:ghost_md/notes/ticket_mark.dart';
import 'package:glacier/glacier.dart';

import '../../sidebar/support.dart';
import '../../support/icons.dart';
import '../../support/render.dart';

String ticket([String? status]) => '---\ntype: ticket\nid: GHO-1\n${status == null ? '' : 'status: $status\n'}---\n# Fix the login loop';

void main() {
  setUpAll(loadAppFonts);

  Future<void> show(WidgetTester tester, List<Widget> children, {Size size = const Size(800, 600)}) =>
      pumpPage(tester, Align(alignment: Alignment.topLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children)), size: size);

  Tokens tokens(WidgetTester tester) => tester.element(find.byType(TicketStatusButton).first).tokens;
  Finder inButton(int at, Type type) => find.descendant(of: find.byType(TicketStatusButton).at(at), matching: find.byType(type));
  Color wordsOf(WidgetTester tester, int at) => tester.widget<RichText>(inButton(at, RichText)).text.style!.color!;
  BoxDecoration pillOf(WidgetTester tester, int at) => tester.widgetList<DecoratedBox>(inButton(at, DecoratedBox)).map((box) => box.decoration).whereType<BoxDecoration>().firstWhere((box) => box.borderRadius != null);

  testWidgets('is a pill in its category’s colour with its mark: the ink not started, blue under way, purple in review, green done', (tester) async {
    await show(tester, [for (final status in const ['Backlog', 'To do', 'In progress', 'In review', 'Done']) TicketStatusButton(body: ticket(status), onPress: () {})]);
    final t = tokens(tester);
    expect([for (final text in tester.widgetList<Text>(find.byType(Text))) text.data], ['Backlog', 'To do', 'In progress', 'In review', 'Done']);
    expect([for (final mark in tester.widgetList<StatusIcon>(find.byType(StatusIcon))) mark.look], const [StatusLook.backlog, StatusLook.todo, StatusLook.doing, StatusLook.review, StatusLook.done]);
    expect([for (var at = 0; at < 5; at++) wordsOf(tester, at)], [t.color('app-ink-2'), t.color('app-ink-2'), t.color('glacier-blue-11'), t.color('glacier-purple-11'), t.color('glacier-green-11')]);
    expect([for (var at = 0; at < 5; at++) pillOf(tester, at).color], [
      t.colorOf('color-mix(in srgb, var(--app-ink-4) 18%, transparent)'),
      t.colorOf('color-mix(in srgb, var(--app-ink-4) 18%, transparent)'),
      t.colorOf('color-mix(in srgb, var(--glacier-blue-9) 14%, transparent)'),
      t.colorOf('color-mix(in srgb, var(--glacier-purple-9) 14%, transparent)'),
      t.colorOf('color-mix(in srgb, var(--glacier-green-9) 14%, transparent)'),
    ]);
    expect(pillOf(tester, 0).border, isNull);
    // The mark keeps its own colour, the faint ink where the words are the second ink, at the words' size.
    final em = t.fontSize('xs');
    final marks = tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();
    expect([for (final mark in marks) mark.color], [t.color('app-ink-3'), t.color('app-ink-3'), t.color('glacier-blue-11'), t.color('glacier-purple-11'), t.color('glacier-green-11')]);
    expect(tester.getSize(find.byType(StatusIcon).first), Size(em, em));
    // `min-block-size: 1.9em; padding: 0.15em 0.6em 0.15em 0.45em; gap: 0.35em`
    final pill = tester.getRect(find.byType(TicketStatusButton).first);
    expect(pill.height, closeTo(1.9 * em, 0.01));
    expect(tester.getRect(find.byType(StatusIcon).first).left - pill.left, closeTo(0.45 * em, 0.01));
    expect(tester.getRect(find.text('Backlog')).left - tester.getRect(find.byType(StatusIcon).first).right, closeTo(0.35 * em, 0.01));
    expect(pill.right - tester.getRect(find.text('Backlog')).right, closeTo(0.6 * em, 0.01));
    await away(tester);
  });

  testWidgets('places a status in its notebook’s workflow, says Status on a ticket with none, and is nothing for a note', (tester) async {
    const notebook = '---\ntype: notebook\nstatuses: [Open, Building, Shipped]\n---\n# Roadmap';
    await show(tester, [
      TicketStatusButton(body: ticket('Building'), notebook: notebook, onPress: () {}),
      TicketStatusButton(body: ticket('Shipped'), notebook: notebook, onPress: () {}),
      TicketStatusButton(body: ticket(), onPress: () {}),
      TicketStatusButton(key: const ValueKey('note'), body: '# A note', onPress: () {}),
    ]);
    final t = tokens(tester);
    expect([for (final mark in tester.widgetList<StatusIcon>(find.byType(StatusIcon))) mark.look], const [StatusLook.doing, StatusLook.done, StatusLook.todo]);
    expect([wordsOf(tester, 0), wordsOf(tester, 1)], [t.color('glacier-blue-11'), t.color('glacier-green-11')]);
    // `[data-empty]`: muted words on nothing, in a hairline ring.
    expect(find.text('Status'), findsOneWidget);
    expect(wordsOf(tester, 2), t.color('glacier-text-muted'));
    expect(pillOf(tester, 2).color, const Color(0x00000000));
    expect((pillOf(tester, 2).border! as Border).top, BorderSide(color: t.color('glacier-border-subtle')));
    expect(tester.getSize(find.byKey(const ValueKey('note'))), Size.zero);
    expect([TicketStatusButton.has(ticket()), TicketStatusButton.has('# A note')], [isTrue, isFalse]);
    await away(tester);
  });

  testWidgets('cuts long words short at 11em', (tester) async {
    await show(tester, [TicketStatusButton(body: ticket('Waiting on the people upstairs to decide'), onPress: () {})]);
    final em = tokens(tester).fontSize('xs');
    expect(tester.getSize(find.byType(TicketStatusButton)).width, closeTo(11 * em, 0.01));
    final words = tester.widget<RichText>(inButton(0, RichText));
    expect([words.maxLines, words.overflow, words.softWrap], [1, TextOverflow.ellipsis, false]);
    await away(tester);
  });

  testWidgets('on a phone is its mark alone, in its colour, and still says its status', (tester) async {
    final handle = tester.ensureSemantics();
    for (final (width, words) in const [(520.0, false), (521.0, true), (390.0, false)]) {
      await show(tester, [TicketStatusButton(body: ticket('In review'), onPress: () {}), TicketStatusButton(body: ticket(), onPress: () {})], size: Size(width, 844));
      final t = tokens(tester);
      final em = t.fontSize('xs');
      expect(find.text('In review'), words ? findsOneWidget : findsNothing, reason: '$width');
      expect(find.text('Status'), words ? findsOneWidget : findsNothing, reason: '$width');
      expect(tester.widget<AppIcon>(inButton(0, AppIcon)).color, t.color('glacier-purple-11'));
      expect(find.bySemanticsLabel('Status: In review. Change it'), findsOneWidget);
      expect(find.bySemanticsLabel('Set a status'), findsOneWidget);
      // `padding-inline: 0.45em` round the mark, and nothing else.
      if (!words) {
        final pill = tester.getSize(find.byType(TicketStatusButton).first);
        expect([pill.width, pill.height], [closeTo(1.9 * em, 0.01), closeTo(1.9 * em, 0.01)]);
      }
      await away(tester);
    }
    handle.dispose();
  });

  testWidgets('is a button that says it was pressed, and keeps the press from what it lies on', (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0, under = 0;
    await show(tester, [GestureDetector(onTap: () => under += 1, child: Padding(padding: const EdgeInsets.all(20), child: TicketStatusButton(body: ticket('To do'), onPress: () => pressed += 1)))]);
    expect(tester.getSemantics(find.bySemanticsLabel('Status: To do. Change it')).flagsCollection.isButton, isTrue);
    await tester.tap(find.byType(TicketStatusButton));
    await tester.pump();
    expect([pressed, under], [1, 0]);
    handle.dispose();
    await away(tester);
  });
}
