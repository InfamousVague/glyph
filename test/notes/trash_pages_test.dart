import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_tray.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_actions.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/trash_sheet.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../organize/support.dart' show snap;
import '../sidebar/support.dart' show PageUnder, away;
import '../support/render.dart';

/// A full Trash (Matt, 2026-11-02, with some 1,300 notes in his after the Hello HQ cleanup: "paginate the trash and add
/// a 'delete forever' button at the top of the trash modal so we don't have to scroll all the way down"): the sheet's
/// pages and their two bars (lib/notes/trash_sheet.dart), Delete forever pinned at its top on a phone and a Mac, its
/// question with the count and the team notes, Find, Restore all, the emptying in batches on the Activity tray
/// (lib/notes/note_actions.dart `emptyTrash`), and the sidebar's Trash folder keeping to its newest page.
void main() {
  setUpAll(loadAppFonts);

  const minute = 60000;
  final now = DateTime(2026, 11, 2, 10).millisecondsSinceEpoch;
  // Note 0 the last thrown away, a minute apart; every hundredth one an organization's, and every tenth a Hello HQ one.
  Note note(int at) => Note(id: 'n$at', body: '# ${at % 10 == 0 ? 'Hello HQ' : 'Old note'} $at\n\nWords.', createdAt: now - 90 * 86400000, updatedAt: now - 60 * 86400000);
  List<Note> many(int count) => [for (var at = 0; at < count; at += 1) note(at)];
  TrashHeld heldOf(List<Note> notes) => {for (final (at, each) in notes.indexed) each.id: now - (at + 1) * minute};
  bool team(String id) => int.parse(id.substring(1)) % 100 == 0;

  Future<List<String>> show(WidgetTester tester, {int count = 1312, bool simple = false, Size size = const Size(390, 844), bool Function(String id)? teamNote}) async {
    final did = <String>[];
    var up = true;
    final notes = many(count);
    final held = heldOf(notes);
    await pumpApp(
      tester,
      size: size,
      home: StatefulBuilder(
        builder: (context, setState) => PageUnder(
          children: [
            if (up)
              TrashSheet(
                notes: inTrash(notes, held),
                held: held,
                onRestore: (n) => did.add('restore ${n.id}'),
                onDestroy: (n) => did.add('destroy ${n.id}'),
                onEmpty: (gone) => did.add('empty ${gone.length}'),
                onRestoreAll: (back) => did.add('restore all ${back.length}'),
                onClose: () {
                  did.add('closed');
                  setState(() => up = false);
                },
                teamNote: teamNote,
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

  List<String> rows(WidgetTester tester) => [
        for (final row in tester.widgetList<SheetRow>(find.byType(SheetRow)))
          if (row.key case ValueKey<String>(:final value) when value.startsWith('trash-note-')) value.substring('trash-note-'.length),
      ];

  Finder bar(String at, String button) => find.byKey(ValueKey('trash-pages-$at-$button'));

  Future<void> press(WidgetTester tester, Finder button) async {
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
  }

  group('the words', () {
    test('counts, pages and the question', () {
      expect(groupedCount(0), '0');
      expect(groupedCount(999), '999');
      expect(groupedCount(1312), '1,312');
      expect(groupedCount(1234567), '1,234,567');
      expect(trashPageWords(1, 50, 1312), '1–50 of 1,312');
      expect(trashPageWords(1301, 1312, 1312), '1,301–1,312 of 1,312');
      expect(trashEmptyQuestion(1312), 'Delete 1,312 notes forever?');
      expect(trashEmptyQuestion(1), 'Delete 1 note forever?');
      expect(trashEmptyNote(0), 'This can’t be undone.');
      expect(trashEmptyNote(14), 'Including 14 team notes, for every member. This can’t be undone.');
      expect(trashEmptyNote(1), 'Including 1 team note, for every member. This can’t be undone.');
    });
  });

  group('pages', () {
    testWidgets('fifty a page, the last thrown away first, with the count over the rows and under them', (tester) async {
      await show(tester);
      expect(rows(tester), [for (var at = 0; at < 50; at += 1) 'n$at']);
      expect(find.text('1–50 of 1,312'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('trash-pages-top')), findsOneWidget);
      expect(find.byKey(const ValueKey('trash-pages-foot')), findsOneWidget);
      // The top bar is in sight as the sheet opens; the foot's is under the rows.
      expect(find.byKey(const ValueKey('trash-pages-top')).hitTestable(), findsOneWidget);
      await away(tester);
    });

    testWidgets('Next and Previous turn the page from either bar, and stop at each end', (tester) async {
      await show(tester);
      // Nothing before the first page.
      await press(tester, bar('top', 'previous'));
      expect(find.text('1–50 of 1,312'), findsNWidgets(2));
      await press(tester, bar('top', 'next'));
      expect(find.text('51–100 of 1,312'), findsNWidgets(2));
      expect(rows(tester).first, 'n50');
      expect(rows(tester), hasLength(50));
      await press(tester, bar('foot', 'next'));
      expect(find.text('101–150 of 1,312'), findsNWidgets(2));
      // The page turned from the foot opens at its top.
      expect(find.byKey(const ValueKey('trash-pages-top')).hitTestable(), findsOneWidget);
      await press(tester, bar('foot', 'previous'));
      expect(find.text('51–100 of 1,312'), findsNWidgets(2));
      for (var page = 2; page <= 26; page += 1) {
        await press(tester, bar('top', 'next'));
      }
      expect(find.text('1,301–1,312 of 1,312'), findsNWidgets(2));
      expect(rows(tester), [for (var at = 1300; at < 1312; at += 1) 'n$at']);
      await press(tester, bar('top', 'next'));
      expect(find.text('1,301–1,312 of 1,312'), findsNWidgets(2));
      await away(tester);
    });

    testWidgets('a Trash of one page has no bars and no Find', (tester) async {
      await show(tester, count: 12);
      expect(rows(tester), hasLength(12));
      expect(find.byKey(const ValueKey('trash-pages-top')), findsNothing);
      expect(find.byKey(const ValueKey('trash-pages-foot')), findsNothing);
      expect(find.byKey(const ValueKey('trash-find')), findsNothing);
      await away(tester);
    });

    testWidgets('Find narrows it by title, and Delete forever then deletes what it found', (tester) async {
      final did = await show(tester);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('trash-find')), matching: find.byType(EditableText)), 'hello hq');
      await tester.pump();
      expect(find.text('1–50 of 132'), findsNWidgets(2));
      expect(rows(tester).take(3), ['n0', 'n10', 'n20']);
      expect(find.text('The 132 found, of 1,312.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trash-empty')));
      await tester.pump();
      expect(find.text('Delete 132 notes forever?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trash-empty-yes')));
      await tester.pump();
      expect(did, ['empty 132', 'closed']);
      await away(tester);
    });
  });

  group('Delete forever at the top', () {
    for (final (sized, size, mac) in [('a phone', const Size(390, 844), false), ('a Mac', const Size(1280, 800), true)]) {
      testWidgets('in sight without scrolling, and still there with the list scrolled, on $sized', (tester) async {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await show(tester, size: size);
        final button = find.byKey(const ValueKey('trash-empty'));
        expect(button.hitTestable(), findsOneWidget);
        final at = tester.getRect(button);
        expect(at.top, greaterThanOrEqualTo(0));
        expect(at.bottom, lessThanOrEqualTo(size.height));
        expect(find.text('Deletes all 1,312 notes in the Trash.'), findsOneWidget);
        // Down to the foot's bar: the button has not moved.
        await tester.ensureVisible(bar('foot', 'next'));
        await tester.pump();
        expect(find.byKey(const ValueKey('trash-note-n0')).hitTestable(), findsNothing);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button), at);
        debugDefaultTargetPlatformOverride = null;
        await away(tester);
      });
    }

    testWidgets('asks once, on the row, with the count; Cancel puts it back', (tester) async {
      final did = await show(tester);
      await tester.tap(find.byKey(const ValueKey('trash-empty')));
      await tester.pump();
      expect(find.text('Delete 1,312 notes forever?'), findsOneWidget);
      expect(find.text('This can’t be undone.'), findsOneWidget);
      // The list is still there under the question.
      expect(rows(tester), hasLength(50));
      await tester.tap(find.byKey(const ValueKey('trash-empty-no')));
      await tester.pump();
      expect(find.text('Delete 1,312 notes forever?'), findsNothing);
      expect(did, isEmpty);
      await tester.tap(find.byKey(const ValueKey('trash-empty')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-empty-yes')));
      await tester.pump();
      expect(did, ['empty 1312', 'closed']);
      await away(tester);
    });

    testWidgets('says how many are an organization’s, deleted for every member', (tester) async {
      await show(tester, teamNote: team);
      await tester.tap(find.byKey(const ValueKey('trash-empty')));
      await tester.pump();
      expect(find.text('Delete 1,312 notes forever?'), findsOneWidget);
      expect(find.text('Including 14 team notes, for every member. This can’t be undone.'), findsOneWidget);
      await away(tester);
    });
  });

  group('Restore all', () {
    testWidgets('asks once, then puts every note back and shuts', (tester) async {
      final did = await show(tester);
      await tester.tap(find.byKey(const ValueKey('trash-restore-all')));
      await tester.pump();
      expect(find.text('Restore 1,312 notes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trash-restore-all-yes')));
      await tester.pump();
      expect(did, ['restore all 1312', 'closed']);
      await away(tester);
    });

    testWidgets('simple mode has the same Delete forever, and Restore all behind More', (tester) async {
      final did = await show(tester, simple: true);
      expect(find.byKey(const ValueKey('trash-empty')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('trash-restore-all')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('trash-all-more')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-restore-all')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trash-restore-all-yes')));
      await tester.pump();
      expect(did, ['restore all 1312', 'closed']);
      await away(tester);
    });

    testWidgets('one note restored from its page, on a later page', (tester) async {
      final did = await show(tester);
      await press(tester, bar('top', 'next'));
      await press(tester, find.byKey(const ValueKey('trash-note-n60')));
      await tester.tap(find.byKey(const ValueKey('trash-restore')));
      await tester.pump();
      expect(did, ['restore n60']);
      expect(find.byKey(const ValueKey('trash-empty')), findsOneWidget);
      await away(tester);
    });
  });

  group('the actions', () {
    late Activity record;
    setUp(() {
      record = Activity(store: () => MemoryStored());
      useActivity(record);
    });
    tearDown(() => useActivity(Activity()));

    ({NoteActions actions, SampleLibrary library, MemoryTrash trash, WorkspaceStore spaces, List<NoteToast> said}) rig(int count) {
      final notes = many(count);
      final library = SampleLibrary(notes);
      final trash = MemoryTrash(heldOf(notes));
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage());
      final kitchen = spaces.addWorkspace('Kitchen')!.id;
      for (final each in notes.take(200)) {
        spaces.fileNote(each.id, kitchen);
      }
      final said = <NoteToast>[];
      return (actions: NoteActions(library: library, workspaces: spaces, trash: trash, say: said.add), library: library, trash: trash, spaces: spaces, said: said);
    }

    test('emptying 1,312 goes in batches of fifty, on the record as it goes, and says how many went', () async {
      final it = rig(1312);
      final notes = inTrash(it.library.value, it.trash.value);
      final seen = <String>[];
      record.addListener(() {
        final job = record[NoteActions.emptyJobId];
        if (job != null && job.state.live && (seen.isEmpty || seen.last != job.steps)) seen.add(job.steps ?? '');
      });
      final run = it.actions.emptyTrash(notes);
      expect(record[NoteActions.emptyJobId]?.title, 'Emptying the Trash');
      await run;
      expect(seen.first, '0 of 1,312 notes');
      expect(seen, contains('50 of 1,312 notes'));
      expect(seen, contains('650 of 1,312 notes'));
      expect(seen.length, greaterThanOrEqualTo(27));
      expect(record[NoteActions.emptyJobId], isNull, reason: 'it ended well');
      expect(record.log.today.counts['note deleted for good|notes deleted for good'], 1312);
      expect(it.library.value, isEmpty);
      expect(it.trash.value, isEmpty);
      expect(it.spaces.value.of, isEmpty);
      expect(it.said.single.message, 'Deleted 1,312 notes for good.');
      it.actions.dispose();
    });

    test('a note restored while the emptying runs stays', () async {
      final it = rig(300);
      final notes = inTrash(it.library.value, it.trash.value);
      final run = it.actions.emptyTrash(notes);
      // The first batch is on its way; one of the last is brought back.
      it.actions.restore(notes.last);
      await run;
      expect(it.library.value.map((n) => n.id), [notes.last.id]);
      expect(it.trash.value, isEmpty);
      expect(it.said.last.message, 'Deleted 299 notes for good.');
      it.actions.dispose();
    });

    test('Stop on the tray leaves the rest in the Trash', () async {
      final it = rig(300);
      final notes = inTrash(it.library.value, it.trash.value);
      final run = it.actions.emptyTrash(notes);
      record[NoteActions.emptyJobId]!.onStop!();
      await run;
      expect(it.library.value, hasLength(250));
      expect(it.trash.value, hasLength(250));
      expect(it.said.last.message, 'Deleted 50 of 300 notes for good. The rest are still in the Trash.');
      it.actions.dispose();
    });

    test('Restore all puts every note back at once', () {
      final it = rig(1312);
      it.actions.restoreAll(inTrash(it.library.value, it.trash.value));
      expect(it.trash.value, isEmpty);
      expect(it.library.value, hasLength(1312));
      expect(it.spaces.value.of, hasLength(200), reason: 'each keeps its filing');
      expect(it.said.last.message, '1,312 notes are back in your notes.');
      it.actions.dispose();
    });

    testWidgets('the tray shows the emptying while it runs, and lets it go when it ends', (tester) async {
      final it = rig(1312);
      await pumpApp(tester, size: const Size(390, 844), home: ActivityTray(record: record));
      await tester.pump();
      final run = it.actions.emptyTrash(inTrash(it.library.value, it.trash.value));
      await tester.pump();
      expect(find.text('Emptying the Trash'), findsOneWidget);
      var done = false;
      run.then((_) => done = true);
      for (var i = 0; i < 200 && !done; i += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(done, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Emptying the Trash'), findsNothing);
      expect(it.library.value, isEmpty);
      it.actions.dispose();
      await away(tester);
    });
  });

  group('the pictures', () {
    for (final (sized, size, mac) in [('phone', const Size(390, 844), false), ('mac', const Size(1280, 800), true)]) {
      testWidgets('a full Trash, $sized', (tester) async {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await show(tester, size: size, teamNote: team);
        await snap(tester, 'trash-pages-$sized');
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('the question asked with the list scrolled to its foot, $sized', (tester) async {
        if (mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await show(tester, size: size, teamNote: team);
        await tester.ensureVisible(bar('foot', 'next'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('trash-empty')));
        await tester.pump();
        await snap(tester, 'trash-pages-asking-$sized');
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('the sidebar’s Trash folder', () {
    testWidgets('keeps to the newest page, with Open the Trash saying how many more there are', (tester) async {
      final notes = many(1312);
      final held = heldOf(notes);
      final kept = MemoryStored();
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: const AppPreferences(theme: 'light'),
        home: NoteTree(notes: const [], activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()), trashed: inTrash(notes, held), onRestore: (_) {}, onDestroy: (_) {}, onEmptyTrash: () {}, onOpenTrash: (_) {}, stored: kept),
      );
      await tester.pump();
      await tester.tap(find.text('Trash'));
      await tester.pump();
      expect(find.byKey(const ValueKey('trash-row-n49'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('trash-row-n50'), skipOffstage: false), findsNothing);
      expect(find.text('Open the Trash · 1,262 more', skipOffstage: false), findsOneWidget);
      await away(tester);
    });
  });
}
