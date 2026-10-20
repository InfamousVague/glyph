// The app's own Claude making a new note, the app put together (lib/root): asked from the chat (or by voice), the
// note is made, opened on screen and Claude's words typed into its editor as they stream (Matt, 2026-10-18, of the
// 2.2.1 iPhone build: a new note was made and never opened, so nobody saw Claude write it).
import 'dart:convert';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/claude_runner.dart' show debugClaudeApi;
import 'package:ghost_md/claude/claude_settings.dart' show claudeSettings;
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/claude_script.dart';
import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
    await claudeSettings.load();
  });

  late SampleLibrary library;
  late WorkspaceStore workspaces;

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> until(WidgetTester tester, bool Function() holds, String reason) async {
    for (var waited = 0; waited < 12000 && !holds(); waited += 50) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(holds(), isTrue, reason: reason);
    await tester.pump(const Duration(milliseconds: 50));
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  Future<void> open(WidgetTester tester, {Size size = const Size(390, 844)}) async {
    library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: library,
        workspaces: workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        untouched: UntouchedNotes(kept: MemoryStored()),
      ),
    );
    await settle(tester, 3);
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  const body = '# Packing list\n\n- [ ] Passport\n- [ ] Charger\n- [ ] Rain jacket\n';

  /// Asks Claude from the chat, its answer scripted to make a note of [body]; answers what the new note's editor
  /// held while Claude was still writing it, and the note.
  Future<(List<String>, Note)> askForNote(WidgetTester tester) async {
    debugClaudeApi = (_) => ScriptedClaudeApi([
          scriptedTurn(words: 'Making it.', tool: ClaudeTool.create, pieces: scriptedPieces(jsonEncode({'body': body}), 6)),
          scriptedTurn(words: 'Wrote [[Packing list]].'),
        ]);
    addTearDown(() => debugClaudeApi = null);
    final before = {for (final note in library.value) note.id};
    await tester.tap(find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-claude'))));
    await settle(tester, 3);
    expect(find.byKey(const ValueKey('claude-chat')), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('claude-ask')), matching: find.byType(EditableText)), 'Make me a packing list');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('claude-send')));
    // While Claude writes: the new note's own screen, and what its editor holds.
    final seen = <String>[];
    Note? made() => library.value.where((note) => !before.contains(note.id)).firstOrNull;
    bool done() {
      final note = made();
      if (note != null) {
        final screens = tester.widgetList<NoteScreen>(find.byType(NoteScreen)).where((screen) => screen.note.id == note.id);
        if (screens.isNotEmpty) {
          final words = tester.state<NoteScreenState>(find.byWidget(screens.first)).view?.state.doc.toString();
          if (words != null && (seen.isEmpty || seen.last != words)) seen.add(words);
        }
      }
      return seen.contains(body) || note?.body == body;
    }

    await until(tester, done, 'Claude did not finish the note');
    await until(tester, () => made()?.body == body, 'the note was not kept with Claude\'s words');
    return (seen, made()!);
  }

  testWidgets('a note Claude makes is opened on screen, the chat makes way, and its words are typed into its editor', (tester) async {
    await tester.runAsync(() => claudeSettings.setKey('sk-test'));
    addTearDown(() => claudeSettings.setKey(null));
    await open(tester);
    final (seen, note) = await askForNote(tester);
    // Opened: the shell is on it, the chat put away.
    expect(shellOf(tester).shown, note.id);
    expect(find.byKey(const ValueKey('claude-chat')), findsNothing);
    // Typed in as it came: the editor held a part of the words before it held all of them.
    expect(seen, contains(body));
    expect(seen.where((words) => words.isNotEmpty && words.length < body.length && body.startsWith(words)), isNotEmpty, reason: 'seen: $seen');
    await close(tester);
    await tester.runAsync(() => claudeSettings.setKey(null));
  });

  testWidgets('on a wide window, where the chat is a panel beside the note, the new note is opened and typed into', (tester) async {
    await tester.runAsync(() => claudeSettings.setKey('sk-test'));
    addTearDown(() => claudeSettings.setKey(null));
    await open(tester, size: const Size(1280, 800));
    final (seen, note) = await askForNote(tester);
    expect(shellOf(tester).shown, note.id);
    expect(seen, contains(body));
    expect(seen.where((words) => words.isNotEmpty && words.length < body.length && body.startsWith(words)), isNotEmpty, reason: 'seen: $seen');
    await close(tester);
    await tester.runAsync(() => claudeSettings.setKey(null));
  });

  // GHST-108 (Matt, 2026-10-19: "Make it so the AI can manage folders and sorting of files into folders"): the root
  // hands its Claude the workspaces, so a folder Claude makes and a note it files there are the app's own, and
  // list_notes says each note's folder by its path.
  testWidgets('Claude makes a folder, files a note in it, and list_notes says where the note is', (tester) async {
    await tester.runAsync(() => claudeSettings.setKey('sk-test'));
    addTearDown(() => claudeSettings.setKey(null));
    await open(tester);
    final api = ScriptedClaudeApi([
      scriptedTurn(tool: 'create_folder', pieces: [jsonEncode({'name': 'Errands', 'parent': 'Home'})]),
      scriptedTurn(tool: 'file_notes', pieces: [jsonEncode({'ids': ['groceries'], 'folder': 'Home › Errands'})]),
      scriptedTurn(tool: ClaudeTool.list, pieces: [jsonEncode({'query': 'Groceries'})]),
      scriptedTurn(words: 'Filed [[Groceries]] in Home › Errands.'),
    ]);
    debugClaudeApi = (_) => api;
    addTearDown(() => debugClaudeApi = null);
    await tester.tap(find.descendant(of: find.byType(HomeScreen), matching: find.byKey(const ValueKey('dock-claude'))));
    await settle(tester, 3);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('claude-ask')), matching: find.byType(EditableText)), 'Sort my errands');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('claude-send')));
    await until(tester, () => api.asked == 4, 'Claude did not get to its last turn');
    final errands = workspaces.value.list.singleWhere((w) => w.name == 'Errands');
    expect(errands.parent, 'home');
    expect(workspaces.workspaceOf('groceries')?.id, errands.id);
    final listed = ((api.bodies.last['messages']! as List).last as Map)['content'] as List;
    final notes = (jsonDecode((listed.single as Map)['content'] as String) as Map)['notes'] as List;
    final groceries = notes.cast<Map>().firstWhere((n) => n['id'] == 'groceries');
    expect((groceries['folder'], groceries['folder_id']), ('Home › Errands', errands.id));
    await settle(tester, 3);
    await close(tester);
    await tester.runAsync(() => claudeSettings.setKey(null));
  });
}
