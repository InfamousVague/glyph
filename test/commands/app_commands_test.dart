import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/app_commands.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../notes/bar_support.dart' show appSheet;
import '../support/render.dart';
import 'support.dart';

/// The palette over the real shell, library, workspaces and preferences, as lib/root would mount it: what
/// [paletteWorldFor] reads of the app and what [paletteDoingFor] does to it.
void main() {
  setUpAll(loadAppFonts);

  late SampleLibrary library;
  late WorkspaceStore workspaces;
  late Calls calls;
  final shellKey = GlobalKey<AppShellState>();
  final barKey = GlobalKey<CommandBarState>();
  AppShellState shell() => shellKey.currentState!;
  CommandBarState bar() => barKey.currentState!;

  PaletteWorld world() => paletteWorldFor(shell: shell(), workspaces: workspaces.value, prefs: preferences.value);
  PaletteDoing doing({bool pages = true}) => paletteDoingFor(
        shell: shell(),
        library: library,
        workspaces: workspaces,
        // Opened once the shell has been handed the library with the new note in it: it opens notes it has.
        newNote: () {
          final made = library.create('');
          WidgetsBinding.instance.addPostFrameCallback((_) => shell().openNote(made.id));
        },
        removeNote: (id) {
          shell().dropTab(id);
          library.delete(id);
        },
        settings: () => calls('settings'),
        settingsPage: pages ? (section) => calls('settings $section') : null,
      );

  Future<void> app(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    library = SampleLibrary.seeded();
    workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()));
    calls = Calls();
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'dark'),
      home: ListenableBuilder(
        listenable: Listenable.merge([library, workspaces, preferences]),
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            AppShell(key: shellKey, sheet: sheet, notes: library.value, workspaces: workspaces.value, backStack: BackStack(), mobile: true, finePointer: false),
            CommandBar.over(key: barKey, world: world, doing: doing),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String query, String row) async {
    bar().show();
    await settle(tester);
    await type(tester, query);
    await tester.tap(find.text(row, findRichText: true).last);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  List<String> offered() => [for (final command in paletteCommands(world(), doing())) command.descriptor.label];

  testWidgets('on the home page it offers the web app’s list, less what is not ported', (tester) async {
    await app(tester);
    final page = [for (final row in (web['phone-dark-empty']['rows'] as List)) if (row['kind'] == 'row') (row['text'] as String).split(' | ').first];
    // Waiting on a feature: notebooks, journals, the recorder, the Academy and the walkthrough.
    const waiting = ['New notebook', 'New journal', 'Speak a new note', 'Ghost.md Academy', 'The welcome walkthrough'];
    // Focus mode is the port's own (Matt, 2026-10-27: "build ... focus mode"), after the themes.
    final ported = [for (final row in page) if (!waiting.contains(row)) row];
    ported.insert(ported.lastIndexWhere((row) => row.startsWith('Theme: ')) + 1, 'Focus mode');
    expect(offered(), ported);
    // With nowhere to open Settings at a page, neither of the commands that would.
    final bare = [for (final command in paletteCommands(world(), doing(pages: false))) command.descriptor.id];
    expect(bare, isNot(contains('organizations')));
    expect(bare, isNot(contains('cheatsheet')));
    await away(tester);
  });

  testWidgets('opens a note by name, and over it offers the note’s own commands, which do what they say', (tester) async {
    await app(tester);
    await choose(tester, 'groc', 'Open Groceries');
    expect(shell().screen, isA<ScreenNote>());
    expect(shell().shown, 'groceries');

    final over = world();
    expect(over.note, const PaletteNote(id: 'groceries', title: 'Groceries'));
    expect(over.filedIn, 'home');
    expect(over.pinned, isFalse);
    expect(over.canBack, isTrue);
    expect(over.tabs.map((tab) => tab.id), ['groceries']);
    expect(offered().take(9), [
      'Pin it to the top', 'Archive this note', 'Delete this note', 'Close the Groceries tab', 'File it in Work', 'Take it out of its workspace', //
      'Put this tab in a new group', 'New note', 'Home',
    ]);
    // Its own tab is not somewhere to go, and it is not offered by name again.
    expect(offered(), isNot(contains('Open Groceries')));
    expect(offered(), contains('Back'));

    await choose(tester, 'pin', 'Pin it to the top');
    expect(library.noteOf('groceries')!.starred, isTrue);
    expect(world().pinned, isTrue);
    expect(offered().first, 'Unpin it from the top');

    await choose(tester, 'file', 'File it in Work');
    expect(workspaces.workspaceOf('groceries')?.id, 'work');
    await choose(tester, 'take it out', 'Take it out of its workspace');
    expect(workspaces.workspaceOf('groceries'), isNull);

    await choose(tester, 'new group', 'Put this tab in a new group');
    expect(shell().tabs.groups.of.keys, ['groceries']);
    expect(offered(), contains('Take this tab out of its group'));
    await choose(tester, 'out of its group', 'Take this tab out of its group');
    expect(shell().tabs.groups.of, isEmpty);

    await choose(tester, 'archive', 'Archive this note');
    expect(library.noteOf('groceries')!.archivedAt, isNotNull);
    await away(tester);
  });

  // docs/PARITY.md, Differs 30: App.tsx's `pin` and `archive` are its note actions', which the root hands in.
  testWidgets('Pin and Archive are the root’s own where it hands them in, and the library’s otherwise', (tester) async {
    await app(tester);
    await choose(tester, 'groc', 'Open Groceries');
    final said = <String>[];
    final theirs = paletteDoingFor(
      shell: shell(),
      library: library,
      workspaces: workspaces,
      newNote: () {},
      removeNote: (_) {},
      settings: () {},
      pin: (id, pinned) => said.add('pin $id $pinned'),
      archive: (id) => said.add('archive $id'),
    );
    for (final command in paletteCommands(world(), theirs)) {
      if (command.descriptor.id == 'note:pin' || command.descriptor.id == 'note:archive') command.run();
    }
    expect(said, ['pin groceries true', 'archive groceries']);
    expect(library.noteOf('groceries')!.starred, isFalse);
    expect(library.noteOf('groceries')!.archivedAt, isNull);
    await away(tester);
  });

  testWidgets('goes home, to All notes, back, and to another tab; closes a tab; deletes the note', (tester) async {
    await app(tester);
    await choose(tester, 'groc', 'Open Groceries');
    await choose(tester, 'flat', 'Open Flat');
    expect(shell().shown, 'flat');
    expect(offered(), containsAll(['Go to Groceries', 'Close Groceries']));
    await choose(tester, 'go to', 'Go to Groceries');
    expect(shell().shown, 'groceries');
    await choose(tester, 'close flat', 'Close Flat');
    expect(shell().tabs.open, ['groceries']);

    await choose(tester, 'all notes', 'All notes');
    expect(shell().screen, isA<ScreenNotes>());
    await choose(tester, 'back', 'Back');
    expect(shell().shown, 'groceries');
    await choose(tester, 'forward', 'Forward');
    expect(shell().screen, isA<ScreenNotes>());
    await choose(tester, 'home', 'Home');
    expect(shell().screen, isA<ScreenList>());

    await choose(tester, 'groc', 'Go to Groceries');
    await choose(tester, 'delete', 'Delete this note');
    expect(library.noteOf('groceries'), isNull);
    expect(shell().screen, isA<ScreenList>());
    expect(offered(), isNot(contains('Open Groceries')));

    final before = library.value.length;
    await choose(tester, 'new note', 'New note');
    expect(library.value.length, before + 1);
    expect(shell().screen, isA<ScreenNote>());
    await away(tester);
  });

  testWidgets('chooses a workspace and a theme, and opens Settings, its pages and the notifications', (tester) async {
    await app(tester);
    await choose(tester, 'Work', 'Show Work');
    expect(workspaces.value.current?.id, 'work');
    expect(offered(), containsAll(['Show all notes', 'Show Home']));
    expect(offered(), isNot(contains('Show Work')));
    await choose(tester, 'show all', 'Show all notes');
    expect(workspaces.value.current, isNull);

    await choose(tester, 'theme', 'Theme: Boreal');
    expect(preferences.value.theme, 'boreal');
    expect(preferences.value.accent, 'green');
    expect(offered(), contains('Theme: Dark'));
    expect(offered(), isNot(contains('Theme: Boreal')));
    await choose(tester, 'theme', 'Theme: Dark');
    expect(preferences.value.theme, 'dark');
    expect(preferences.value.accent, 'ink');

    // Focus mode on and off again, the command saying which way it goes.
    await choose(tester, 'focus', 'Focus mode');
    expect(preferences.value.focusMode, isTrue);
    expect(offered(), contains('Leave focus mode'));
    expect(offered(), isNot(contains('Focus mode')));
    await choose(tester, 'leave focus', 'Leave focus mode');
    expect(preferences.value.focusMode, isFalse);

    await choose(tester, 'settings', 'Settings');
    await choose(tester, 'organizations', 'Organizations');
    await choose(tester, 'cheat', 'Cheat sheet');
    expect(calls.said, ['settings', 'settings organizations', 'settings cheatsheet']);

    expect(shell().notificationsOpen, isFalse);
    await choose(tester, 'notifications', 'Notifications');
    expect(shell().notificationsOpen, isTrue);
    await away(tester);
  });

  test('the notes are named newest-changed first, a journal’s entries marked, whatever order the library is in', () {
    final notes = seedLibrary();
    final named = paletteNotes(notes);
    final page = [for (final row in (web['phone-dark-empty']['rows'] as List)) if ((row['text'] as String).startsWith('Open ')) (row['text'] as String).substring(5)];
    expect([for (final note in named) note.title], page);
    expect(identical(paletteNotes(notes), named), isTrue);
    final starter = starterNotes(seedNow);
    expect([for (final note in paletteNotes(starter)) if (note.entry) note.id], ['starter-entry']);
    expect([for (final note in paletteJournals(starter)) (note.id, note.journal)], [('starter-journal', true)]);
  });
}
