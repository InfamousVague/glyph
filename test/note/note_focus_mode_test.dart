// Focus mode from a note's More sheet (Matt, 2026-10-27: "build ... focus mode"; lib/note/note_settings.dart
// `NoteFocus`): a row under Reading it in both modes, which turns it on for every note and closes the sheet, and says
// "Leave focus mode" while it is on.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/note/note_screen.dart' show NoteSeams;
import 'package:ghost_md/note/note_settings.dart';

import '../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'focus${made += 1}', body)))!;

  Future<void> more(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  const row = ValueKey<String>('note-focus-mode');

  for (final mode in ['advanced', 'simple']) {
    testWidgets('in $mode, the More sheet turns focus mode on and off', (tester) async {
      final world = NoteWorld();
      world.prefs.value = world.prefs.value.choosing(mode);
      await pumpNote(tester, world, await seeded(tester, world, '# Day\n\nWords, and more words.'), bar: false, seams: const NoteSeams(focusMode: true));
      await more(tester);
      expect(find.byKey(row), findsOneWidget);
      expect(find.text('Focus mode'), findsOneWidget);
      // Under Reading it, with the note's other ways of reading it.
      expect(tester.getRect(find.text('READING IT')).bottom, lessThanOrEqualTo(tester.getRect(find.byKey(row)).top + 0.01));
      await tester.tap(find.byKey(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(world.prefs.value.focusMode, isTrue);
      expect(find.byType(NoteSettings), findsNothing, reason: 'the sheet closes, back to the words');

      await more(tester);
      expect(find.text('Leave focus mode'), findsOneWidget);
      await tester.tap(find.byKey(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(world.prefs.value.focusMode, isFalse);
      await closeNote(tester);
    });
  }

  testWidgets('an editor without focus mode, or a note that cannot be written in, has no row', (tester) async {
    final plain = NoteWorld();
    await pumpNote(tester, plain, await seeded(tester, plain, 'Words.'), bar: false);
    await more(tester);
    expect(find.byType(NoteSettings), findsOneWidget);
    expect(find.byKey(row), findsNothing);
    await closeNote(tester);

    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, 'Words.'), bar: false, readOnly: true, seams: const NoteSeams(focusMode: true));
    await more(tester);
    expect(find.byType(NoteSettings), findsOneWidget);
    expect(find.byKey(row), findsNothing);
    await closeNote(tester);
  });
}
