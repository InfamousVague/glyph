// Simple mode's chrome on a note (lib/note/note_screen.dart, lib/note/note_tools.dart `NoteSimpleHeader`,
// GHST-105). Matt, 2026-10-18: "it still is a bit complex with the tabs and such… build out a clean simple UI", and
// for the note "‹ Notes, ⋯ and Done; the title in the page". Where the app draws no bar over the note, the note's own
// header is the way back as a word, ⋯ and, while the keyboard is up, Done; no tool rings. The view switch, Pin and
// Archive are the More sheet's rows; the note hands the dock nothing of its own.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/shell/page_dock.dart';

import '../shell/dock_support.dart';
import '../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'simple${made += 1}', body)))!;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void keyboard(WidgetTester tester, double height) => tester.view.viewInsets = FakeViewPadding(bottom: height * tester.view.devicePixelRatio);

  NoteWorld simpleWorld() {
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    return world;
  }

  testWidgets('the header is ‹ Notes and ⋯, no tool rings; Done comes with the keyboard and goes with it', (tester) async {
    final world = simpleWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false, speak: true);
    await settle(tester);
    final header = find.byType(NoteSimpleHeader);
    expect(header, findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to Notes'), findsOneWidget);
    expect(find.bySemanticsLabel('More for this note'), findsOneWidget);
    expect(find.byKey(NoteSimpleHeader.doneKey), findsNothing, reason: 'the keyboard is down and nothing is focused');
    // No tool rings at all: not the view switch, not Pin, not Archive, not the mic.
    expect(find.descendant(of: header, matching: find.byType(NoteToolButton)), findsNWidgets(1), reason: 'only ⋯ is a ring');
    expect(find.bySemanticsLabel('Pin to the top'), findsNothing);
    expect(find.bySemanticsLabel('Archive'), findsNothing);
    expect(find.bySemanticsLabel('Showing the formatted note. Show the marks.'), findsNothing);
    expect(find.bySemanticsLabel('Talk into this note'), findsNothing);
    // Back at the start, ⋯ at the end, on one row inside the header's glass.
    final back = tester.getRect(find.byKey(NoteSimpleHeader.backKey));
    final more = tester.getRect(find.bySemanticsLabel('More for this note'));
    expect(back.left, lessThan(more.left));
    expect(back.center.dy, closeTo(more.center.dy, 1));

    keyboard(tester, 300);
    await settle(tester);
    final doneWord = find.byKey(NoteSimpleHeader.doneKey);
    expect(doneWord, findsOneWidget);
    expect(tester.getRect(doneWord).left, greaterThan(tester.getRect(find.bySemanticsLabel('More for this note')).right), reason: 'Done is the last thing on the row');

    tester.view.resetViewInsets();
    await settle(tester);
    expect(find.byKey(NoteSimpleHeader.doneKey), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('Back leaves, saved first; Done puts the keyboard away and the note stays', (tester) async {
    final world = simpleWorld();
    final screen = await pumpNote(tester, world, await seeded(tester, world, 'buy milk'), bar: false);
    await settle(tester);
    // What Done asks of the phone.
    final asked = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (call) async {
      asked.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));

    keyboard(tester, 300);
    await settle(tester);
    await tester.tap(find.byKey(NoteSimpleHeader.doneKey));
    await settle(tester);
    expect(asked, contains('TextInput.hide'));
    expect(screen.view!.hasFocus, isFalse);
    expect(world.asked, isNot(contains('back')), reason: 'Done is not a way off the note');

    tester.view.resetViewInsets();
    await settle(tester);
    await tester.tap(find.byKey(NoteSimpleHeader.backKey));
    await tester.pump();
    expect(world.asked, contains('back'));
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('the way back wears the word it is given', (tester) async {
    final world = simpleWorld();
    await pumpNote(tester, world, await seeded(tester, world, '- [ ] milk'), bar: false, backLabel: 'To-dos');
    await settle(tester);
    expect(find.text('To-dos'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to To-dos'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('the More sheet offers the view switch first under Reading it, and a press switches; advanced’s sheet has no such row', (tester) async {
    final world = simpleWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false);
    await settle(tester);
    expect(world.prefs.value.noteView, 'formatted', reason: 'simple opens on the formatted note');
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NoteSettings), findsOneWidget);
    final row = find.byKey(const ValueKey<String>('note-view-switch'));
    expect(row, findsOneWidget);
    expect(find.text('Show the marks'), findsOneWidget);
    expect(find.text('Showing the formatted note.'), findsOneWidget);
    // The first row of Reading it: under its heading, above Find and replace.
    expect(tester.getRect(find.text('READING IT')).bottom, lessThanOrEqualTo(tester.getRect(row).top + 0.01));
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NoteSettings), findsNothing, reason: 'the sheet closes on the switch');
    expect(world.prefs.value.noteView, 'mixed');
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Show the formatted note'), findsOneWidget);
    expect(find.text('Pin to the top'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    await closeNote(tester);
    await done(tester);

    // Advanced: the ring in the header, and no row.
    world.prefs.value = world.prefs.value.choosing('advanced');
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false);
    await settle(tester);
    expect(find.byType(NoteSimpleHeader), findsNothing);
    expect(find.bySemanticsLabel('Showing the marks. Show the formatted note.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey<String>('note-view-switch')), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('the note hands the dock nothing of its own: a seam with nothing to draw is no dock, Claude’s stays Claude alone', (tester) async {
    final world = simpleWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false, speak: true, dock: const PageDockSeam());
    await settle(tester);
    expect(find.byType(PageDock), findsNothing);
    await closeNote(tester);
    await done(tester);

    final asked = <String>[];
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false, speak: true, dock: PageDockSeam(claude: fakeClaude(asked)));
    await settle(tester);
    expect(find.byType(PageDock), findsOneWidget);
    expect(dockOrder(tester), ['claude']);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('switching modes while the note is open swaps the header, and the page starts under it either way', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false);
    await settle(tester);
    expect(find.byType(NoteSimpleHeader), findsNothing);
    world.prefs.value = world.prefs.value.choosing('simple');
    await settle(tester);
    expect(find.byType(NoteSimpleHeader), findsOneWidget);
    world.prefs.value = world.prefs.value.choosing('advanced');
    await settle(tester);
    expect(find.byType(NoteSimpleHeader), findsNothing);
    await closeNote(tester);
    await done(tester);
  });
}
