import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/smart_notebooks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/collection_screen.dart';
import 'package:ghost_md/notes/daily_notes.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/smart_notebook_sheet.dart';
import 'package:ghost_md/notes/workspace_sheet.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;
import 'package:ghost_md/settings/panes/daily_notes_pane.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:ghost_md/shell/screen.dart' show CollectionKind;
import 'package:ghost_md/app/style_sheets.dart';
import 'package:glacier/glacier.dart';

import '../settings/panes/support.dart' show openPane;
import '../support/render.dart';
import 'support.dart';

/// Pictures of the organizing features, dark, at a phone's size (430 x 932 at 3) and the Fold opened (900 x 1000),
/// written to build/feature-shots/organize/ to be looked at (test/organize/support.dart `snap`), not held as goldens.
void main() {
  setUpAll(loadAppFonts);
  setUp(NoteMarks.debugForget);

  const phone = Size(430, 932);
  const fold = Size(900, 1000);

  Future<void> page(WidgetTester tester, Widget child, {Size size = phone, bool split = false}) async {
    final sheet = split ? await tester.runAsync(() => loadTokenSheet(more: appStyleSheets)) : null;
    final home = BackScope(child: child);
    await pumpApp(tester, size: size, ratio: size == phone ? 3 : 2, prefs: const AppPreferences(theme: 'dark'), home: sheet == null ? home : RootStamps(sheet: sheet, stamps: const {'split': 'on'}, child: home));
  }

  SmartNotebookStore smartStore() {
    final prefs = PreferencesStore()..startWithoutStorage();
    final store = SmartNotebookStore(prefs: prefs);
    store.add('Open at work', 'in:work is:todo');
    store.add('This week', 'updated:<7d');
    store.add('With a picture', 'has:image');
    return store;
  }

  Widget home(WorkspaceStore spaces, {ValueChanged<String>? onSave}) => HomeScreen(
        notes: organizeNotes(),
        workspaces: spaces,
        onOpen: (_) {},
        onNew: () {},
        onAllNotes: () {},
        onSearch: () {},
        clock: () => organizeNow,
        onSaveSearch: onSave ?? (_) {},
      );

  Future<void> typeIn(WidgetTester tester, String words) async {
    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.pump();
    if (words.isNotEmpty) await tester.enterText(field, words);
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final (name, size) in [('phone', phone), ('fold', fold)]) {
    testWidgets('the home page’s search, empty and taking the keyboard: the operators, $name', (tester) async {
      await page(tester, home(WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()))), size: size, split: size == fold);
      await typeIn(tester, '');
      expect(find.byKey(const ValueKey('search-hints')), findsOneWidget);
      await snap(tester, 'search-hints-$name');
    });

    testWidgets('the home page’s search with operators: what it understood, and Save, $name', (tester) async {
      await page(tester, home(WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()))), size: size, split: size == fold);
      await typeIn(tester, 'tag:work is:todo -in:kiln send');
      expect(find.text('Tagged #work'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-save')), findsOneWidget);
      await snap(tester, 'search-understood-$name');
    });
  }

  testWidgets('All notes’ search with operators', (tester) async {
    await page(
      tester,
      AllNotesScreen(notes: organizeNotes(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())), onOpen: (_) {}, onBack: () {}, stored: MemoryStored(), clock: () => organizeNow, onSaveSearch: (_) {}, wisp: false),
    );
    await typeIn(tester, 'has:todo updated:<7d');
    expect(find.text('Changed in the last 7 days'), findsOneWidget);
    await snap(tester, 'allnotes-understood-phone');
  });

  CollectionScreen collection(CollectionKind kind, {String name = '', List<Note>? notes, SmartNotebookStore? smart}) => CollectionScreen(
        kind: kind,
        name: name,
        notes: notes ?? organizeNotes(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())).value,
        smart: smart ?? smartStore(),
        onOpen: (_) {},
        onBack: () {},
        onTag: (_) {},
        onRenameTag: (_, _) async => 0,
        onEditSmart: (_) {},
        stored: MemoryStored(),
        clock: () => organizeNow,
      );

  for (final (name, size) in [('phone', phone), ('fold', fold)]) {
    testWidgets('the Tags page, tags inside tags, $name', (tester) async {
      await page(tester, collection(CollectionKind.tags), size: size);
      await snap(tester, 'tags-nested-$name');
    });
  }

  testWidgets('the Tags page of a library whose tags are all at the top, by name', (tester) async {
    final flat = [
      for (final (id, tags) in [('a', '#reading #books'), ('b', '#reading'), ('c', '#errands'), ('d', '#ideas #reading'), ('e', '#ideas'), ('f', '#recipes')])
        Note(id: id, body: '# Note $id\n\n$tags', createdAt: organizeNow, updatedAt: organizeNow),
    ];
    final kept = MemoryStored()..writeText(tagsSortKey, 'name');
    await page(
      tester,
      CollectionScreen(kind: CollectionKind.tags, notes: flat, workspaces: const Workspaces(), smart: smartStore(), onOpen: (_) {}, onBack: () {}, onTag: (_) {}, stored: kept, clock: () => organizeNow),
    );
    await snap(tester, 'tags-flat-phone');
  });

  testWidgets('a tag’s page, and its rename', (tester) async {
    await page(tester, collection(CollectionKind.tag, name: 'work'));
    await snap(tester, 'tag-work-phone');
    await page(tester, collection(CollectionKind.tag, name: 'work'));
    await tester.tap(find.byKey(const ValueKey('tag-rename')));
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('tag-new-name')), matching: find.byType(EditableText)), 'job');
    await tester.pump(const Duration(milliseconds: 500));
    await snap(tester, 'tag-rename-phone');
  });

  testWidgets('a smart notebook’s page, and its sheet', (tester) async {
    final smart = smartStore();
    await page(tester, collection(CollectionKind.smart, name: smart.value.first.id, smart: smart));
    await snap(tester, 'smart-page-phone');
    await page(tester, SmartNotebookSheet(store: smart, query: 'tag:home/garden is:todo', onClose: () {}));
    await snap(tester, 'smart-save-sheet-phone');
  });

  for (final (name, size) in [('phone', phone), ('fold', fold)]) {
    testWidgets('the sidebar: Tags, the smart notebooks with their counts, and folders inside folders, $name', (tester) async {
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
      await page(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: NoteTree(
              notes: organizeNotes(),
              activeId: 'kickoff',
              onOpen: (_) {},
              onNew: () {},
              workspaces: spaces,
              stored: MemoryStored()..writeText('glyph-tree-compact', '1'),
              smart: smartStore(),
              onSmart: (_) {},
              onManageSmart: (_) {},
              onTags: () {},
              onSettings: () {},
            ),
          ),
        ),
        size: size,
      );
      await snap(tester, 'sidebar-organize-$name');
    });
  }

  testWidgets('a folder’s sheet: a new folder inside it, and Move', (tester) async {
    final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
    await page(tester, WorkspaceManageSheet(store: spaces, editing: spaces.value.list.firstWhere((w) => w.id == 'clients'), folders: true, onClose: () {}));
    await snap(tester, 'folder-sheet-phone');
    await page(tester, WorkspaceManageSheet(store: spaces, editing: spaces.value.list.firstWhere((w) => w.id == 'clients'), folders: true, onClose: () {}));
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('workspace-move')));
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await snap(tester, 'folder-move-phone');
  });

  testWidgets('the + with Today', (tester) async {
    await page(tester, NewSheet(open: true, onClose: () {}, onNote: () {}, onCanvas: () {}, onBook: () {}, onToday: () {}, clock: () => DateTime(2026, 10, 16, 9)));
    expect(find.text('Today'), findsOneWidget);
    await snap(tester, 'new-sheet-today-phone');
  });

  testWidgets('Settings › Workspaces › Daily notes: where they go, what they start from, a notebook', (tester) async {
    final library = ValueNotifier<List<Note>>([
      ...organizeNotes(),
      Note(id: 'garden-book', body: '---\nbook: true\n---\n# Garden notebook\n\n- [[Raised beds]]', createdAt: organizeNow, updatedAt: organizeNow),
    ]);
    dailyNotesLibrary = library;
    addTearDown(() => dailyNotesLibrary = null);
    final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
    await openPane(tester, 'daily', prefs: const Preferences(theme: 'dark'), workspaces: spaces);
    expect(find.text('WHERE THEY GO'), findsOneWidget);
    await snap(tester, 'settings-daily-phone');
    // A choice is kept in the preferences.
    await openPane(tester, 'daily', prefs: const Preferences(theme: 'dark'), workspaces: spaces);
    final none = find.descendant(of: find.byKey(const ValueKey('daily-folder-none')), matching: find.byType(Pick));
    await tester.ensureVisible(none);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(none);
    await tester.pump();
    expect(dailyNotesIn(preferences.value).folder, '');
    await snap(tester, 'settings-daily-chosen-phone');
  });

  testWidgets('a tag’s page and a smart notebook’s on the Fold opened, beside nothing', (tester) async {
    await page(tester, collection(CollectionKind.tag, name: 'home'), size: fold);
    await snap(tester, 'tag-home-fold');
  });

  test('the library’s moment is the pictures’ day', () {
    expect(DateTime.fromMillisecondsSinceEpoch(organizeNow).day, 16);
    expect(SampleLibrary(organizeNotes()).value, hasLength(10));
  });
}
