import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/swipe.dart';
import 'package:ghost_md/simple/simple_bar.dart';
import 'package:ghost_md/simple/simple_home.dart';

import '../support/render.dart';

/// Simple mode's home page (GHST-105; Matt, 2026-10-18: "it still is a bit complex with the tabs and such ... build
/// out a clean simple UI"): the title and the gear, the search narrowing the rows, the groups by when, the swipes
/// (right pins, left deletes, no archive), the bar's two destinations, the + and the microphone, and the page as a
/// column beside a note.
void main() {
  setUpAll(loadAppFonts);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> swipe(WidgetTester tester, Finder what, double dx) async {
    final gesture = await tester.startGesture(tester.getCenter(what));
    await gesture.moveBy(Offset(dx.sign * 30, 0));
    await tester.pump();
    await gesture.moveBy(Offset(dx - dx.sign * 30, 0));
    await tester.pump();
    await gesture.up();
    await settle(tester);
  }

  Finder row(String id) => find.byKey(ValueKey('simple-row-$id'));

  testWidgets('is the title, the gear, the search and the rows under Pinned and the spans, a name and a line and when each', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    final asked = <String>[];
    await pumpApp(tester, home: _Page(library: it, asked: asked, speak: true));
    await settle(tester);
    expect(find.text('Notes'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('simple-settings')));
    expect(asked, ['settings']);
    // The groups, in order, each said with its count.
    expect(find.bySemanticsLabel('Pinned, 1'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Today, \d+')), findsOneWidget);
    expect([for (final group in simpleGroups(it.value, now: seedNow)) group.key], ['pinned', 'today', 'yesterday', 'week'], reason: 'pinned first, then newest first; the seed reaches nine days back');
    // A pinned row wears a small pin and nothing else marks a kind.
    expect(row('weekend'), findsOneWidget);
    expect(find.descendant(of: row('weekend'), matching: find.bySemanticsLabel(RegExp(r'^Weekend trip, pinned, '))), findsOneWidget);
    // Only the rows near the screen are built; the rest, a notebook by its name among them, come as the list is
    // scrolled.
    expect(find.text('Portugal'), findsNothing);
    await tester.drag(find.byKey(const ValueKey('simple-scroll')), const Offset(0, -700));
    await settle(tester);
    expect(find.bySemanticsLabel(RegExp(r'^Yesterday, \d+')), findsOneWidget);
    expect(find.text('Portugal'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('simple-scroll')), const Offset(0, 900));
    await settle(tester);
    // A tap opens.
    await tester.tap(row('standup'));
    expect(asked.last, 'open standup');
    // The microphone and the +.
    expect(find.bySemanticsLabel('Speak a note'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simple-speak')));
    expect(asked.last, 'speak');
    await tester.tap(find.byKey(const ValueKey('simple-new')));
    expect(asked.last, 'new');
    await tester.longPress(find.byKey(const ValueKey('simple-new')));
    await settle(tester);
    expect(asked.last, 'new long');
    await away(tester);
  });

  testWidgets('narrows the rows as the search is typed, and says when nothing has the words', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    await pumpApp(tester, home: _Page(library: it, asked: []));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Search'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText), 'milk');
    await settle(tester);
    expect(row('groceries'), findsOneWidget);
    expect(row('weekend'), findsNothing);
    expect(find.text('Pinned'), findsNothing, reason: 'a search is one run of rows');
    await tester.enterText(find.byType(EditableText), 'zxqv');
    await settle(tester);
    expect(find.text('Nothing has “zxqv”.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Clear the search'));
    await settle(tester);
    expect(row('weekend'), findsOneWidget);
    await away(tester);
  });

  testWidgets('swipes right to pin or unpin and left to delete, with no archive between', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    final asked = <String>[];
    await pumpApp(tester, home: _Page(library: it, asked: asked));
    await settle(tester);
    await swipe(tester, row('standup'), 120);
    expect(asked.last, 'swipe pin standup');
    expect(find.bySemanticsLabel('Pinned, 2'), findsOneWidget);
    await swipe(tester, row('flat'), -160);
    expect(asked.last, 'swipe delete flat');
    expect(row('flat'), findsNothing);
    expect(asked.where((said) => said.contains('archive')), isEmpty);
    await away(tester);
  });

  testWidgets('has Notes and To-dos along the foot, and the other tab shows what the root hands it or says where it will be', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    await pumpApp(tester, home: _Page(library: it, asked: []));
    await settle(tester);
    expect(find.byType(SimpleBar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('simple-tab-todos')));
    await settle(tester);
    expect(find.text('To-dos'), findsWidgets);
    expect(find.text('Your open to-dos will show here.'), findsOneWidget);
    expect(find.bySemanticsLabel('Search'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('simple-tab-notes')));
    await settle(tester);
    expect(find.text('Your open to-dos will show here.'), findsNothing);
    expect(row('weekend'), findsOneWidget);
    await away(tester);
  });

  testWidgets('has no microphone without onSpeak, and says so on the empty page', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    await pumpApp(tester, home: _Page(library: it, asked: []));
    await settle(tester);
    expect(find.bySemanticsLabel('Speak a note'), findsNothing);
    expect(find.byKey(const ValueKey('simple-new')), findsOneWidget);
    await away(tester);
    final none = SampleLibrary(const <Note>[], clock: () => seedNow);
    await pumpApp(tester, home: _Page(library: none, asked: []));
    await settle(tester);
    expect(find.text('A blank page.'), findsOneWidget);
    expect(find.text('Tap + to write it.'), findsOneWidget);
    await away(tester);
    await pumpApp(tester, home: _Page(library: none, asked: [], speak: true));
    await settle(tester);
    expect(find.text('Write it, or tap the mic and say it.'), findsOneWidget);
    await away(tester);
  });

  testWidgets('as a column beside a note has the switch under the title and the pair at its foot, and no bar', (tester) async {
    final it = SampleLibrary.seeded(clock: () => seedNow);
    final asked = <String>[];
    await pumpApp(tester, size: const Size(360, 800), home: _Page(library: it, asked: asked, speak: true, pane: true));
    await settle(tester);
    expect(find.byType(SimpleBar), findsNothing);
    expect(find.byKey(const ValueKey('simple-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('simple-speak')), findsOneWidget);
    // The pair stands at the foot, under the rows.
    expect(tester.getBottomLeft(find.byKey(const ValueKey('simple-new'))).dy, greaterThan(tester.getBottomLeft(row('weekend')).dy));
    await tester.tap(find.text('To-dos'));
    await settle(tester);
    expect(find.text('Your open to-dos will show here.'), findsOneWidget);
    await away(tester);
  });
}

/// The page over a library, alive: swipes pin and delete in the library, and everything that leaves the page is
/// written down in [asked]. The tab is held here, as the root holds it.
class _Page extends StatefulWidget {
  const _Page({required this.library, required this.asked, this.speak = false, this.pane = false});
  final SampleLibrary library;
  final List<String> asked;
  final bool speak;
  final bool pane;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  SimpleTab _tab = SimpleTab.notes;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Note>>(
        valueListenable: widget.library,
        builder: (context, notes, _) => SimpleHome(
          notes: notes,
          clock: () => seedNow,
          onOpen: (id) => widget.asked.add('open $id'),
          onNew: () => widget.asked.add('new'),
          onNewLong: () => widget.asked.add('new long'),
          onSpeak: widget.speak ? () => widget.asked.add('speak') : null,
          onSettings: () => widget.asked.add('settings'),
          onNoteMenu: (id, at) => widget.asked.add('menu $id'),
          onSwipe: (note, action) {
            widget.asked.add('swipe ${action.name} ${note.id}');
            switch (action) {
              case NoteSwipe.pin:
                widget.library.pin(note.id, pinned: !note.starred);
              case NoteSwipe.archive:
                widget.library.archive(note.id, archived: true);
              case NoteSwipe.delete:
                widget.library.delete(note.id);
            }
          },
          tab: _tab,
          onTab: (tab) => setState(() => _tab = tab),
          pane: widget.pane,
        ),
      );
}
