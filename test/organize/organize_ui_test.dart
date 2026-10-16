import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/smart_notebooks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/search_hints.dart';
import 'package:ghost_md/notes/collection_screen.dart';
import 'package:ghost_md/notes/daily_notes.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/root/organize.dart';
import 'package:ghost_md/shell/desktop/desktop_commands.dart';
import 'package:ghost_md/shell/screen.dart' show Caret, CollectionKind;

import '../support/render.dart';
import 'support.dart';

/// The organizing features on screen: the hint row under a search, the Tags page and a tag's, a smart notebook's
/// page, the sidebar's shelf and its folders inside folders, and what the root's [Organize] does.
void main() {
  setUpAll(loadAppFonts);
  setUp(NoteMarks.debugForget);

  Future<void> page(WidgetTester tester, Widget child, {Size size = const Size(430, 932)}) async {
    await pumpApp(tester, size: size, prefs: const AppPreferences(theme: 'dark'), home: BackScope(child: child));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  Future<void> down(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the hint row under a search', () {
    testWidgets('offers the operators while the field is empty and has the keyboard, and puts one in', (tester) async {
      final said = <String>[];
      await page(tester, Align(alignment: Alignment.topLeft, child: SearchHints(query: '', focused: true, onQuery: said.add)));
      expect(find.byKey(const ValueKey('search-hints')), findsOneWidget);
      expect(find.text('tag:'), findsOneWidget);
      expect(find.text('is:pinned'), findsOneWidget);
      await tester.tap(find.text('tag:'));
      expect(said, ['tag:']);
      expect(SearchHints.withHint('ferns', 'is:todo'), 'ferns is:todo');
      expect(SearchHints.withHint('ferns ', 'is:todo'), 'ferns is:todo');
      await down(tester);
    });

    testWidgets('draws nothing for an empty field without the keyboard', (tester) async {
      await page(tester, Align(alignment: Alignment.topLeft, child: SearchHints(query: '', focused: false, onQuery: (_) {})));
      expect(find.byKey(const ValueKey('search-hints')), findsNothing);
      await down(tester);
    });

    testWidgets('says what it understood, a chip each, its cross taking that operator out, and offers Save', (tester) async {
      final said = <String>[];
      var saved = 0;
      await page(tester, Align(alignment: Alignment.topLeft, child: SearchHints(query: 'ferns tag:garden -is:pinned', focused: true, onQuery: said.add, onSave: () => saved += 1)));
      expect(find.text('Tagged #garden'), findsOneWidget);
      expect(find.text('Not pinned'), findsOneWidget);
      // The plain words are the search's own, and get no chip.
      expect(find.text('ferns'), findsNothing);
      await tester.tap(find.text('Tagged #garden'));
      expect(said, ['ferns -is:pinned']);
      await tester.tap(find.byKey(const ValueKey('search-save')));
      expect(saved, 1);
      await down(tester);
    });
  });

  group('the Tags page', () {
    late MemoryStored kept;
    late SmartNotebookStore smart;
    setUp(() {
      kept = MemoryStored();
      final prefs = PreferencesStore()..startWithoutStorage();
      smart = SmartNotebookStore(prefs: prefs);
    });

    CollectionScreen screen(CollectionKind kind, {String name = '', List<String>? asked, Future<int> Function(String, String)? rename}) => CollectionScreen(
          kind: kind,
          name: name,
          notes: organizeNotes(),
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces())).value,
          smart: smart,
          onOpen: (id) => asked?.add('open $id'),
          onBack: () => asked?.add('back'),
          onTag: (tag) => asked?.add('tag $tag'),
          onRenameTag: rename,
          onEditSmart: (notebook) => asked?.add('edit ${notebook.id}'),
          stored: kept,
          clock: () => organizeNow,
        );

    testWidgets('lists every tag with its count, a tag inside another folded under it, by count or by name', (tester) async {
      final asked = <String>[];
      await page(tester, screen(CollectionKind.tags, asked: asked));
      expect(find.text('6 tags'), findsNothing);
      // work, work/clients, work/clients/kiln, admin, home, home/garden, shopping, reading, travel.
      expect(find.text('9 tags'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-row-work')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-row-work/clients/kiln')), findsOneWidget);
      // Work: the roadmap, the invoice and the kickoff; the archived plan left out.
      expect(find.descendant(of: find.byKey(const ValueKey('tag-row-work')), matching: find.text('3')), findsOneWidget);
      // Folded, its tags inside go; and it stays folded on this device.
      await tester.tap(find.bySemanticsLabel('Fold #work'));
      await tester.pump();
      expect(find.byKey(const ValueKey('tag-row-work/clients')), findsNothing);
      expect(kept.read<List<String>>(tagsClosedKey, const [], (raw) => raw is List ? raw.cast<String>() : null), ['work']);
      await tester.tap(find.byKey(const ValueKey('tags-by-name')));
      await tester.pump();
      expect(kept.readText(tagsSortKey), 'name');
      await tester.tap(find.byKey(const ValueKey('tag-row-home')));
      expect(asked, ['tag home']);
      await down(tester);
    });

    testWidgets('a tag’s page lists its notes and those of the tags inside it, newest first, and the tags inside to go on to', (tester) async {
      final asked = <String>[];
      await page(tester, screen(CollectionKind.tag, name: 'work', asked: asked));
      expect(find.text('#work'), findsOneWidget);
      expect(find.text('3 notes'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-kickoff')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-old')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('inside-work/clients')));
      await tester.tap(find.byKey(const ValueKey('row-invoice')));
      expect(asked, ['tag work/clients', 'open invoice']);
      await down(tester);
    });

    testWidgets('Rename says how many notes it changes, the archive’s too, and hands the new name over', (tester) async {
      final renames = <String>[];
      final asked = <String>[];
      await page(
        tester,
        screen(CollectionKind.tag, name: 'work', asked: asked, rename: (from, to) async {
          renames.add('$from to $to');
          return 4;
        }),
      );
      await tester.tap(find.byKey(const ValueKey('tag-rename')));
      for (var i = 0; i < 10; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Rename in 4 notes'), findsOneWidget);
      expect(find.text('A new name for it in 4 notes, and for the tags inside it.'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('tag-new-name')), matching: find.byType(EditableText)), 'two words');
      await tester.pump();
      expect(find.textContaining('has no spaces'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('tag-new-name')), matching: find.byType(EditableText)), '#home');
      await tester.pump();
      expect(find.textContaining('#home is a tag already'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('tag-new-name')), matching: find.byType(EditableText)), 'job');
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('becomes #job/…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-rename-go')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(renames, ['work to job']);
      expect(asked, ['tag job']);
      await down(tester);
    });

    testWidgets('a smart notebook’s page is what its search finds now, and its More is its sheet', (tester) async {
      final asked = <String>[];
      final made = smart.add('Open at work', 'in:work is:todo')!;
      await page(tester, screen(CollectionKind.smart, name: made.id, asked: asked));
      expect(find.text('Open at work'), findsOneWidget);
      expect(find.byKey(const ValueKey('row-kickoff')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-invoice')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-roadmap')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('smart-edit')));
      expect(asked, ['edit ${made.id}']);
      // Gone on another device: the page says so.
      smart.remove(made.id);
      await tester.pump();
      expect(find.text('This smart notebook is gone.'), findsOneWidget);
      await down(tester);
    });
  });

  group('the sidebar', () {
    testWidgets('a Tags row and the smart notebooks over the folders, folders inside folders, each folding', (tester) async {
      final prefs = PreferencesStore()..startWithoutStorage();
      final smart = SmartNotebookStore(prefs: prefs);
      final open = smart.add('Open at work', 'in:work is:todo')!;
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
      final asked = <String>[];
      await page(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: NoteTree(
              notes: organizeNotes(),
              activeId: null,
              onOpen: (id) => asked.add('open $id'),
              onNew: () {},
              workspaces: spaces,
              stored: MemoryStored(),
              smart: smart,
              onSmart: (id) => asked.add('smart $id'),
              onManageSmart: (notebook) => asked.add('more ${notebook.id}'),
              onTags: () => asked.add('tags'),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Tags, 9'), findsOneWidget);
      expect(find.byKey(ValueKey('smart-row-${open.id}')), findsOneWidget);
      expect(find.bySemanticsLabel('Open at work, 2 notes'), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-row-clients')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-row-kiln')), findsOneWidget);
      // Work counts its own note and those of the folders inside it.
      expect(find.descendant(of: find.byKey(const ValueKey('folder-row-work')), matching: find.text('3')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('folder-row-work')), matching: find.text('Work')));
      await tester.pump();
      expect(find.byKey(const ValueKey('folder-row-clients')), findsNothing);
      await tester.tap(find.bySemanticsLabel('Tags, 9'));
      await tester.tap(find.bySemanticsLabel('Open at work, 2 notes'));
      expect(asked, ['tags', 'smart ${open.id}']);
      smart.dispose();
      await down(tester);
    });

    testWidgets('on a wide window, a note dragged onto a folder is filed there, and a folder into another', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
      await page(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            // Names only, so every row is on the screen.
            child: NoteTree(notes: organizeNotes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: spaces, stored: MemoryStored()..writeText('glyph-tree-compact', '1')),
          ),
        ),
        size: const Size(900, 1000),
      );
      // Packing list is filed in none; dropped on Reading, it is filed there.
      final from = tester.getCenter(find.byKey(const ValueKey('note-row-packing')));
      final to = tester.getCenter(find.byKey(const ValueKey('folder-row-reading')));
      final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await drag.moveBy(const Offset(0, -20));
      await tester.pump();
      await drag.moveTo(to);
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(spaces.value.of['packing'], 'reading');
      // Garden dragged onto Reading moves inside it, and never into a folder inside itself.
      final garden = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('folder-row-garden'))), kind: PointerDeviceKind.mouse);
      await garden.moveBy(const Offset(0, 20));
      await tester.pump();
      await garden.moveTo(tester.getCenter(find.byKey(const ValueKey('folder-row-reading'))));
      await tester.pump();
      await garden.up();
      await tester.pump();
      expect(spaces.value.list.firstWhere((w) => w.id == 'garden').parent, 'reading');
      debugDefaultTargetPlatformOverride = null;
      await down(tester);
    });
  });

  group('what the root does', () {
    ({Organize organize, SampleLibrary library, WorkspaceStore spaces, List<String> made, PreferencesStore prefs}) organizeOver(List<Note> notes) {
      final library = SampleLibrary(notes, clock: () => organizeNow);
      final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage(organizeSpaces()));
      final prefs = PreferencesStore()..startWithoutStorage();
      final made = <String>[];
      final organize = Organize(
        library: library,
        workspaces: spaces,
        shell: () => null,
        notes: () => library.value,
        make: (body, {Caret? caret, String? into}) {
          final note = library.create(body);
          if (into != null) spaces.fileNote(note.id, into);
          made.add('${caret?.offset}|$into|$body');
          return note;
        },
        screenOf: (_) => null,
        templates: () => null,
        say: (_) {},
        prefs: prefs,
      );
      addTearDown(organize.dispose);
      return (organize: organize, library: library, spaces: spaces, made: made, prefs: prefs);
    }

    test('a tag renamed in every note that has it, through the library’s write', () async {
      final it = organizeOver(organizeNotes());
      final changed = await it.organize.renameTag('work', 'job');
      expect(changed, 4);
      final bodies = {for (final note in it.library.value) note.id: note.body};
      expect(bodies['kickoff'], contains('#job/clients/kiln'));
      expect(bodies['invoice'], contains('#job/clients #admin'));
      expect(bodies['old'], contains('#job Kept'));
      expect(bodies['beds'], isNot(contains('#job')));
    });

    test('today’s note made once from the day template, in the Daily notes folder, and opened the next time', () {
      final it = organizeOver(organizeNotes());
      final day = DateTime(2026, 10, 16, 9);
      it.organize.today(now: day);
      expect(it.made, hasLength(1));
      final folder = it.spaces.value.list.firstWhere((w) => w.name == dailyFolderName);
      expect(it.made.single, startsWith('${dailyNoteBody(builtIns.first, day).caret}|${folder.id}|# 2026-10-16'));
      it.organize.today(now: day);
      expect(it.made, hasLength(1));
      // Settings said no folder: none.
      it.prefs.update((now) => withDailyNotes(now, const DailyNotesSetup(folder: '')));
      it.organize.today(now: DateTime(2026, 10, 17, 9));
      expect(it.made.last, startsWith('${dailyNoteBody(builtIns.first, DateTime(2026, 10, 17, 9)).caret}|null|# 2026-10-17'));
    });

    test('a search kept from the Save under a search field, and its sheet put away', () {
      final it = organizeOver(const []);
      var told = 0;
      it.organize.addListener(() => told += 1);
      it.organize.saveSearch('  tag:work is:todo ');
      expect(it.organize.sheet?.query, 'tag:work is:todo');
      it.organize.closeSheet();
      expect(it.organize.sheet, isNull);
      it.organize.saveSearch('   ');
      expect(it.organize.sheet, isNull);
      expect(told, 2);
    });
  });

  test('the palette offers today’s note, the Tags page and each smart notebook', () {
    final asked = <String>[];
    final doing = PaletteDoing(
      openNote: (_) {},
      newNote: () {},
      closeTab: (_) {},
      showList: () {},
      browseNotes: () {},
      back: () {},
      forward: () {},
      settings: () {},
      chooseWorkspace: (_) {},
      fileNote: (_, _) {},
      setTheme: (_) {},
      pin: (_, _) {},
      archive: (_) {},
      remove: (_) {},
      today: () => asked.add('today'),
      tags: () => asked.add('tags'),
      openSmart: (id) => asked.add('smart $id'),
    );
    final commands = paletteCommands(const PaletteWorld(smartNotebooks: [(id: 's-1', name: 'Open at work')]), doing);
    final byId = {for (final command in commands) command.descriptor.id: command};
    expect(byId['today']?.descriptor.label, 'Today’s note');
    expect(byId['tags']?.descriptor.label, 'Tags');
    expect(byId['smart:s-1']?.descriptor.label, 'Show Open at work');
    byId['today']!.run();
    byId['tags']!.run();
    byId['smart:s-1']!.run();
    expect(asked, ['today', 'tags', 'smart s-1']);
  });

  testWidgets('Command-Shift-D asks for today’s note on a Mac, and Command-Shift alone with another letter for nothing', (tester) async {
    final commands = DesktopCommands();
    final ran = <DesktopCommand>[];
    for (final command in DesktopCommand.values) {
      commands.on(command, () {
        ran.add(command);
        return true;
      });
    }
    final mac = DesktopKeys.attach(platform: TargetPlatform.macOS, commands: commands)!;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(ran, [DesktopCommand.today]);
    expect(desktopCommandNamed('today'), DesktopCommand.today);
    mac.dispose();
  });
}
