// The editor a note keeps behind its canvas or its notebook's index reads nothing of the note until it is shown
// (lib/note/note_editor.dart `NoteEditorSpec.shown`, lib/editor/view/syntax_tree.dart `syntaxAsleep`): what it
// holds there is the canvas's JSON, and reading that as Markdown was the dearest thing a canvas's opening did.
//
// Held in the app put together: a canvas opened leaves its editor's words unread while its own cards read theirs;
// shown as its JSON, the editor holds the tree a parse of those words gives; back on the canvas it lets it go. A
// notebook the same, and a note of words is read from the start.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/syntax_tree.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<void> open(WidgetTester tester, String noteId) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    SyntaxWork.reset();
    tester.state<AppShellState>(find.byType(AppShell)).openNote(noteId);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  EditorState stateOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen)).view!.state;

  /// The tree a state never asleep holds for these words.
  String parsed(String words) => syntaxTree(EditorState.create(doc: words, extensions: noteExtensions())).toString();

  Future<void> flip(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tool-switch')).first);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a canvas\'s editor reads its JSON when it is shown, and not before', (tester) async {
    await open(tester, 'cabin-canvas');
    var state = stateOf(tester);
    final words = state.doc.toString();
    expect(words, contains('"nodes"'));
    expect(syntaxTree(state).length, 0, reason: 'behind the canvas, nothing is read');
    // What was read as the canvas opened: its cards' own words, each a few lines, and nothing as long as the note.
    final opening = SyntaxWork.whole;
    // ignore: avoid_print
    print('a canvas opening read ${SyntaxWork.whole} notes whole (its cards\' words), the note itself not among them');

    await flip(tester);
    state = stateOf(tester);
    expect(state.doc.toString(), words);
    expect(syntaxTree(state).length, words.length, reason: 'shown, the words are read');
    final expected = parsed(words);
    expect(syntaxTree(state).toString(), expected);

    await flip(tester);
    expect(syntaxTree(stateOf(tester)).length, 0, reason: 'behind the canvas again, the tree is let go');
    expect(opening, greaterThan(0));
    await close(tester);
  });

  testWidgets('a notebook\'s editor reads its Markdown when the index gives way to it', (tester) async {
    final id = seedLibrary(seedNow).firstWhere((note) => note.body.contains('book: true') && !note.body.contains('journal: true')).id;
    await open(tester, id);
    var state = stateOf(tester);
    final words = state.doc.toString();
    expect(syntaxTree(state).length, 0, reason: 'behind the index, nothing is read');
    await flip(tester);
    state = stateOf(tester);
    expect(syntaxTree(state).length, state.doc.length);
    expect(state.doc.toString(), words);
    final expected = parsed(words);
    expect(syntaxTree(state).toString(), expected);
    await close(tester);
  });

  testWidgets('a note of words is read from the start', (tester) async {
    final id = seedLibrary(seedNow).firstWhere((note) => !note.body.contains('"nodes"') && !note.body.contains('book: true') && !note.body.contains('type: ticket')).id;
    await open(tester, id);
    final state = stateOf(tester);
    expect(state.doc.length, greaterThan(0));
    expect(syntaxTree(state).length, state.doc.length);
    await close(tester);
  });
}
