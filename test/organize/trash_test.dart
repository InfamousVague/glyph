import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/note_actions.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/trash_sheet.dart';
import 'package:ghost_md/notes/tree.dart' show writeTrashOpen;
import 'package:ghost_md/sheet/kit.dart';

import '../sidebar/support.dart' show PageUnder, away;
import '../support/render.dart';
import 'support.dart';

/// The Trash as a section of its own (Matt, 2026-10-23: "add a "trash" section in the app where deleted notes go
/// before getting perma deleted"): the thirty days' rule and the purge (lib/core/trash.dart `expiredInTrash`,
/// lib/notes/note_actions.dart `purge`), the sheet (lib/notes/trash_sheet.dart), the ways into it from the sidebar's
/// folder and All notes, and its pictures, written to build/feature-shots/organize/trash-*.png.
void main() {
  setUpAll(loadAppFonts);

  const day = Duration.millisecondsPerDay;
  const now = organizeNow;
  Note note(String id, String title) => Note(id: id, body: '# $title\n\nWords.', createdAt: now - 60 * day, updatedAt: now - 40 * day);
  final plan = note('plan', 'Old plan'), receipt = note('receipt', 'Train receipt'), minutes = note('minutes', 'Team minutes'), draft = note('draft', 'Draft letter');
  final held = <String, int>{'plan': now - 31 * day, 'receipt': now - 2 * day - 3600000, 'minutes': now - 45 * day, 'draft': now - 3 * 3600000};
  List<Note> trashed() => inTrash([plan, receipt, minutes, draft], held);

  group('thirty days in the Trash', () {
    test('what is due: past thirty days, the longest there first, an organization’s left for the person', () {
      expect(expiredInTrash([plan, receipt, minutes, draft], held, now).map((n) => n.id), ['minutes', 'plan']);
      expect(expiredInTrash([plan, receipt, minutes, draft], held, now, kept: (id) => id == 'minutes').map((n) => n.id), ['plan']);
      expect(expiredInTrash([plan], {'plan': now - 30 * day}, now).map((n) => n.id), ['plan']);
      expect(expiredInTrash([plan], {'plan': now - 30 * day + 1}, now), isEmpty);
      expect(expiredInTrash([plan], const {}, now), isEmpty);
      expect(trashDaysLeft(now - 2 * day - 3600000, now), 28);
      expect(trashDaysLeft(now - 3 * 3600000, now), 30);
      expect(trashDaysLeft(now - 31 * day, now), 0);
    });

    test('the words: when it went in and what is left', () {
      expect(deletedWhen(now - 3 * 3600000, now), 'Deleted 3 hr ago');
      expect(deletedWhen(now - 20000, now), 'Deleted just now');
      expect(deletedWhen(now - day - 3600000, now), 'Deleted yesterday');
      expect(deletedWhen(now - 3 * day, now), startsWith('Deleted on '));
      expect(trashLeft(now - 29 * day, now, team: false), 'deleted for good tomorrow');
      expect(trashLeft(now - 2 * day, now, team: false), 'deleted for good in 28 days');
      expect(trashLeft(now - 2 * day, now, team: true), 'kept until you empty the Trash');
    });

    testWidgets('the purge deletes for good what is due, quietly, and keeps one restored meanwhile', (tester) async {
      final library = SampleLibrary([plan, receipt, minutes, draft]);
      final trash = MemoryTrash(held);
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage());
      final said = <NoteToast>[], forgot = <String>[];
      final actions = NoteActions(library: library, workspaces: spaces, trash: trash, say: said.add, onForget: forgot.add);
      final due = expiredInTrash(library.value, trash.value, now);
      // Brought back on another device, landed here before the purge got to it.
      trash.restoreNote('minutes');
      expect(await actions.purge(due), 1);
      expect(library.noteOf('plan'), isNull);
      expect(library.noteOf('minutes'), isNotNull);
      expect(library.noteOf('receipt'), isNotNull);
      expect(trash.value.keys, unorderedEquals(['receipt', 'draft']));
      expect(forgot, ['plan']);
      expect(said, isEmpty);
      actions.dispose();
    });
  });

  group('the sheet', () {
    Future<List<String>> show(WidgetTester tester, {bool simple = false, String? open, bool Function(String id)? teamNote, Size size = const Size(390, 844), String theme = 'light'}) async {
      final did = <String>[];
      var up = true;
      await pumpApp(
        tester,
        size: size,
        ratio: 2,
        prefs: AppPreferences(theme: theme),
        home: StatefulBuilder(
          builder: (context, setState) => PageUnder(
            children: [
              if (up)
                TrashSheet(
                  notes: trashed(),
                  held: held,
                  open: open,
                  onRestore: (n) => did.add('restore ${n.id}'),
                  onDestroy: (n) => did.add('destroy ${n.id}'),
                  onEmpty: () => did.add('empty'),
                  onClose: () {
                    did.add('closed');
                    setState(() => up = false);
                  },
                  teamNote: teamNote,
                  placeOf: (id) => id == 'receipt' ? 'Home › Travel' : null,
                  simple: simple,
                  now: () => now,
                ),
            ],
          ),
        ),
      );
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return did;
    }

    Finder row(String label) => find.widgetWithText(SheetRow, label);

    testWidgets('lists every note in it, the last thrown away first, with when it went in and the rule at its foot', (tester) async {
      await show(tester);
      expect(find.text('Trash'), findsOneWidget);
      final titles = [for (final each in tester.widgetList<SheetRow>(find.byType(SheetRow))) each.key];
      expect(titles, [const ValueKey('trash-note-draft'), const ValueKey('trash-note-receipt'), const ValueKey('trash-note-plan'), const ValueKey('trash-note-minutes'), const ValueKey('trash-empty')]);
      expect(find.text('Deleted 3 hr ago · deleted for good in 30 days'), findsOneWidget);
      expect(find.text('Notes are deleted for good 30 days after they go in the Trash.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('a note’s page: Restore puts it back where it was, and says where', (tester) async {
      final did = await show(tester);
      await tester.tap(row('Train receipt'));
      await tester.pump();
      expect(find.text('Back in Home › Travel.'), findsOneWidget);
      await tester.tap(row('Restore'));
      await tester.pump();
      expect(did, ['restore receipt']);
      // Back on the list.
      expect(row('Empty Trash'), findsOneWidget);
      await away(tester);
    });

    testWidgets('Delete for good asks once, then deletes', (tester) async {
      final did = await show(tester, open: 'plan');
      await tester.tap(row('Delete for good'));
      await tester.pump();
      expect(find.text('Delete “Old plan” for good?'), findsOneWidget);
      expect(did, isEmpty);
      await tester.tap(row('Cancel'));
      await tester.pump();
      await tester.tap(row('Delete for good'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-destroy-yes')));
      await tester.pump();
      expect(did, ['destroy plan']);
      await away(tester);
    });

    testWidgets('Empty Trash asks once, then empties and shuts', (tester) async {
      final did = await show(tester);
      await tester.tap(row('Empty Trash'));
      await tester.pump();
      expect(find.text('Delete 4 for good?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trash-empty-yes')));
      await tester.pump();
      expect(did, ['empty', 'closed']);
      await away(tester);
    });

    testWidgets('simple mode keeps Delete for good behind More, opened in place', (tester) async {
      final did = await show(tester, simple: true, open: 'plan');
      expect(row('Delete for good'), findsNothing);
      await tester.tap(row('More'));
      await tester.pump();
      await tester.tap(row('Delete for good'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-destroy-yes')));
      await tester.pump();
      expect(did, ['destroy plan']);
      await away(tester);
    });

    testWidgets('an organization’s note waits for the person’s own Empty, and says so', (tester) async {
      await show(tester, teamNote: (id) => id == 'minutes');
      expect(find.textContaining('kept until you empty the Trash'), findsOneWidget);
      expect(find.text('Notes are deleted for good 30 days after they go in the Trash. An organization’s notes wait until you empty it.'), findsOneWidget);
      await away(tester);
    });
  });

  group('the ways in', () {
    testWidgets('All notes has a Trash word beside Archived while the Trash holds any', (tester) async {
      var opened = 0;
      await pumpApp(
        tester,
        size: const Size(390, 844),
        home: BackScope(child: AllNotesScreen(notes: organizeNotes(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())), onOpen: (_) {}, onBack: () {}, stored: MemoryStored(), clock: () => organizeNow, wisp: false, trashCount: 4, onTrash: () => opened += 1)),
      );
      await tester.pump();
      expect(find.text('Trash · 4'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trash-word')));
      await tester.pump();
      expect(opened, 1);
      await away(tester);
    });

    testWidgets('the sidebar’s Trash folder opens the Trash, on a note’s page from its name', (tester) async {
      final opened = <String?>[];
      final kept = MemoryStored();
      await pumpApp(
        tester,
        size: const Size(390, 844),
        home: NoteTree(notes: organizeNotes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())), trashed: trashed(), onRestore: (_) {}, onDestroy: (_) {}, onEmptyTrash: () {}, onOpenTrash: opened.add, stored: kept),
      );
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Trash'), 200);
      await tester.tap(find.text('Trash'));
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('trash-open')).hitTestable(), 200);
      await tester.tap(find.byKey(const ValueKey('trash-open')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-open-plan')));
      await tester.pump();
      expect(opened, [null, 'plan']);
      await away(tester);
    });
  });

  group('the pictures', () {
    for (final (sized, size, mac) in [('phone', const Size(390, 844), false), ('mac', const Size(1280, 800), true)]) {
      for (final theme in ['light', 'dark']) {
        testWidgets('the Trash, $sized $theme', (tester) async {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          await show2(tester, size: size, theme: theme);
          await snap(tester, 'trash-sheet-$sized-$theme');
          debugDefaultTargetPlatformOverride = null;
        });

        testWidgets('a note in the Trash, $sized $theme', (tester) async {
          if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          await show2(tester, size: size, theme: theme, open: 'receipt');
          await snap(tester, 'trash-note-$sized-$theme');
          debugDefaultTargetPlatformOverride = null;
        });

        for (final (stage, opens) in [('before', false), ('after', true)]) {
          testWidgets('the sidebar’s Trash folder, $stage, $sized $theme', (tester) async {
            if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            final kept = MemoryStored();
            writeTrashOpen(true, kept);
            await pumpApp(
              tester,
              size: size,
              ratio: 2,
              prefs: AppPreferences(theme: theme),
              // At a docked sidebar's width on the Mac.
              home: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: mac ? 300 : size.width,
                  child: NoteTree(notes: organizeNotes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())), trashed: trashed(), onRestore: (_) {}, onDestroy: (_) {}, onEmptyTrash: () {}, onOpenTrash: opens ? (_) {} : null, stored: kept),
                ),
              ),
            );
            tester.view.padding = FakeViewPadding.zero;
            tester.view.viewPadding = FakeViewPadding.zero;
            await tester.pump();
            // Down to the Trash, at the list's foot.
            for (var i = 0; i < 12 && find.text('Train receipt').hitTestable().evaluate().isEmpty; i += 1) {
              final at = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
              at.jumpTo((at.pixels + 250).clamp(0, at.maxScrollExtent));
              await tester.pump();
            }
            expect(find.text('Train receipt').hitTestable(), findsOneWidget);
            await snap(tester, 'trash-sidebar-$stage-$sized-$theme');
            debugDefaultTargetPlatformOverride = null;
          });
        }

        for (final (stage, opens) in [('before', false), ('after', true)]) {
          testWidgets('All notes’ line of words, $stage, $sized $theme', (tester) async {
            if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            await pumpApp(
              tester,
              size: size,
              ratio: 2,
              prefs: AppPreferences(theme: theme),
              home: BackScope(child: AllNotesScreen(notes: organizeNotes(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())), onOpen: (_) {}, onBack: () {}, stored: MemoryStored(), clock: () => organizeNow, wisp: false, trashCount: opens ? 4 : 0, onTrash: opens ? () {} : null)),
            );
            tester.view.padding = FakeViewPadding.zero;
            tester.view.viewPadding = FakeViewPadding.zero;
            await tester.pump();
            await snap(tester, 'trash-allnotes-$stage-$sized-$theme');
            debugDefaultTargetPlatformOverride = null;
          });
        }
      }
    }
  });
}

/// The sheet for a picture, over a page.
Future<void> show2(WidgetTester tester, {required Size size, required String theme, String? open}) async {
  const day = Duration.millisecondsPerDay;
  const now = organizeNow;
  Note note(String id, String title) => Note(id: id, body: '# $title\n\nWords.', createdAt: now - 60 * day, updatedAt: now - 40 * day);
  final notes = [note('draft', 'Draft letter'), note('receipt', 'Train receipt'), note('plan', 'Old plan'), note('minutes', 'Team minutes')];
  final held = <String, int>{'plan': now - 27 * day, 'receipt': now - 2 * day - 3600000, 'minutes': now - 29 * day, 'draft': now - 3 * 3600000};
  await pumpApp(
    tester,
    size: size,
    ratio: 2,
    prefs: AppPreferences(theme: theme),
    home: PageUnder(
      children: [
        TrashSheet(
          notes: inTrash(notes, held),
          held: held,
          open: open,
          onRestore: (_) {},
          onDestroy: (_) {},
          onEmpty: () {},
          onClose: () {},
          teamNote: (id) => id == 'minutes',
          placeOf: (id) => id == 'receipt' ? 'Home › Travel' : null,
          now: () => now,
        ),
      ],
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
}
