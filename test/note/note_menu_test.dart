// The note's ••• as a menu of its More sheet's rows (Matt, 2026-11-02: "Show more items in the more dropdown we should
// be able to scroll on it instead of needing to open a new modal"; lib/note/note_settings.dart `noteSheetGroups`,
// lib/shell/header/header_kit.dart `noteMenuEntries`): the rows are there without the sheet, a press does what the
// sheet's row does, the menu scrolls inside the room under its button, a page of the sheet opens the sheet there,
// simple mode's fancy rows are behind a More… that opens in place, and All settings… is the sheet itself.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_screen.dart' show NoteSeams;
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/note/workspace_picker.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:glacier/glacier.dart';

import '../support/header_bar.dart';
import '../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'menu${made += 1}', body)))!;

  Future<void> beat(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder row(String id) => find.byKey(HeaderAct.keyOf('note:$id'));

  /// The note's own ⋯ (a phone's, where no bar takes the tools), opened.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await beat(tester);
  }

  /// Whether [finder]'s middle is inside the window and the menu's panel shows it there.
  bool shown(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final scroller = tester.getRect(find.descendant(of: find.byType(GlacierMenu), matching: find.byType(Scrollable)).first);
    return rect.center.dy > 0 && rect.center.dy < window.height && scroller.contains(rect.center);
  }

  testWidgets('a phone’s ⋯ lists the sheet’s rows, grouped, without opening the sheet; a press does what the row does', (tester) async {
    final world = NoteWorld();
    final note = await seeded(tester, world, '# Day\n\nWords.');
    await pumpNote(tester, world, note, bar: false, speak: true, seams: const NoteSeams(focusMode: true));
    await openMenu(tester);
    expect(find.byType(NoteSettings), findsNothing, reason: 'no sheet, the menu');
    for (final id in ['speak', 'focus', 'pin', 'archive', 'workspace', 'trash']) {
      expect(row(id), findsOneWidget, reason: id);
    }
    expect(find.byKey(HeaderAct.keyOf('more')), findsOneWidget, reason: 'All settings… is the sheet itself');
    // The sheet's headings, and its order: Where it sits after Reading it, Move to Trash at the foot, after All settings….
    expect(find.text('READING IT'), findsOneWidget);
    expect(find.text('WHERE IT SITS'), findsOneWidget);
    expect(tester.getRect(row('focus')).top, lessThan(tester.getRect(row('pin')).top));
    expect(tester.getRect(find.byKey(HeaderAct.keyOf('more'))).top, lessThan(tester.getRect(row('trash')).top));
    // The trash in the app's red, as the sheet's row is.
    final trash = tester.widget<GlacierMenuItem>(row('trash'));
    expect(trash.danger, isTrue);

    await tapRow(tester, row('archive'));
    await beat(tester);
    expect(world.asked, contains('archive ${note.id}'));
    expect(find.byType(NoteSettings), findsNothing);
    expect(row('pin'), findsNothing, reason: 'the menu closes on a press');
    await closeNote(tester);
  });

  testWidgets('Pin and Move to Trash run from the menu', (tester) async {
    final world = NoteWorld();
    final note = await seeded(tester, world, 'Words.');
    await pumpNote(tester, world, note, bar: false);
    await openMenu(tester);
    expect(find.text('Pin to the top'), findsOneWidget);
    await tapRow(tester, row('pin'));
    await beat(tester);
    expect(world.asked, contains('pin ${note.id} false'));
    await openMenu(tester);
    expect(find.text('Unpin'), findsOneWidget, reason: 'its words follow the note');
    await tapRow(tester, row('trash'));
    await beat(tester);
    expect(world.asked, contains('delete ${note.id}'));
    await closeNote(tester);
  });

  testWidgets('a row that is a page of the sheet opens the sheet at that page; All settings… opens the sheet', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, 'Words.'), bar: false);
    await openMenu(tester);
    await tapRow(tester, row('workspace'));
    await beat(tester);
    expect(find.byType(NoteSettings), findsOneWidget);
    expect(find.byType(WorkspacePicker), findsOneWidget, reason: 'at the Workspace page');
    await tester.binding.handlePopRoute();
    await beat(tester);
    await closeNote(tester);

    await pumpNote(tester, world, await seeded(tester, world, 'Words.'), bar: false);
    await pressInBar(tester, 'more', label: 'More for this note');
    expect(find.byType(NoteSettings), findsOneWidget);
    expect(find.byType(WorkspacePicker), findsNothing, reason: 'the sheet from its top');
    await closeNote(tester);
  });

  testWidgets('a long menu scrolls inside a small window, under a finger, and stays open', (tester) async {
    final world = NoteWorld();
    final note = await seeded(tester, world, '# Day\n\nWords.');
    await pumpNote(tester, world, note, size: const Size(344, 520), bar: false, speak: true, seams: NoteSeams(focusMode: true, onAi: (view, kind, [instruction]) => world.asked.add('ai $kind')));
    await openMenu(tester);
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final panel = tester.getRect(find.descendant(of: find.byType(GlacierMenu), matching: find.byType(Scrollable)).first);
    expect(panel.bottom, lessThanOrEqualTo(window.height - 8 + 0.01), reason: 'the menu ends inside the window');
    expect(shown(tester, row('trash')), isFalse, reason: 'Move to Trash is below the fold at first');
    // A finger's drag up the menu scrolls it, and the menu stays.
    await tester.drag(find.descendant(of: find.byType(GlacierMenu), matching: find.byType(Scrollable)).first, const Offset(0, -2000));
    await beat(tester);
    expect(row('trash'), findsOneWidget, reason: 'still open');
    expect(shown(tester, row('trash')), isTrue, reason: 'scrolled to the foot');
    await tester.tap(row('trash'));
    await beat(tester);
    expect(world.asked, contains('delete ${note.id}'));
    await closeNote(tester);
  });

  testWidgets('the keys walk the menu and it scrolls to the row they reach; Escape closes it', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), size: const Size(344, 520), bar: false, speak: true, seams: NoteSeams(focusMode: true, onAi: (view, kind, [instruction]) {}));
    await openMenu(tester);
    expect(shown(tester, row('trash')), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await beat(tester);
    expect(shown(tester, row('trash')), isTrue, reason: 'End reaches the last row, scrolled into view');
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await beat(tester);
    expect(shown(tester, row('speak')), isTrue, reason: 'Home back to the first');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await beat(tester);
    expect(row('speak'), findsNothing);
    expect(find.byType(NoteSettings), findsNothing);
    await closeNote(tester);
  });

  testWidgets('in simple mode the fancy rows are behind a More… that opens in place in the menu', (tester) async {
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords.'), bar: false, seams: NoteSeams(onAi: (view, kind, [instruction]) {}));
    await openMenu(tester);
    expect(row('pin'), findsOneWidget);
    expect(row('archive'), findsOneWidget);
    expect(row('view-switch'), findsOneWidget, reason: 'simple’s view switch, the first row of Reading it');
    expect(row('workspace'), findsNothing, reason: 'filing is simple’s fancy');
    expect(row('ai:format'), findsNothing, reason: 'and the AI');
    final more = find.byKey(HeaderAct.keyOf('note-more'));
    expect(more, findsOneWidget);
    await tapRow(tester, more);
    await beat(tester);
    expect(find.byType(NoteSettings), findsNothing, reason: 'in place, no sheet');
    expect(row('workspace'), findsOneWidget);
    expect(row('ai:format'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    await tapRow(tester, more);
    await beat(tester);
    expect(row('workspace'), findsNothing, reason: 'Less hides them again');
    expect(row('pin'), findsOneWidget, reason: 'the menu is still up');
    await closeNote(tester);
  });

  testWidgets('the bar’s ••• on a note lists the sheet’s rows too', (tester) async {
    final world = NoteWorld();
    final note = await seeded(tester, world, 'Words.');
    await pumpNote(tester, world, note);
    await openBarMenu(tester, 'overflow');
    // Pin is the bar's own action in the sheet's place for it, under its own key; the sheet's other rows are the sheet's.
    final pin = find.byKey(HeaderAct.keyOf('pin'));
    expect(pin, findsOneWidget);
    expect(row('pin'), findsNothing);
    expect(row('workspace'), findsOneWidget);
    expect(row('trash'), findsOneWidget);
    expect(find.byKey(HeaderAct.keyOf('more')), findsOneWidget);
    expect(find.byType(NoteSettings), findsNothing);
    expect(tester.getRect(pin).top, greaterThan(tester.getRect(find.text('WHERE IT SITS')).top), reason: 'under Where it sits');
    await tapRow(tester, pin);
    await beat(tester);
    expect(world.asked, contains('pin ${note.id} false'));
    await closeNote(tester);
  });
}
