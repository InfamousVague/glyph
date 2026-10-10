// The open note's editor is told of the library only what the note reads of it (lib/root/note_desk.dart
// `_libraryChanged`): every change of the library, the note's own save among them, used to be sent into the editor
// as three effects, and each is a transaction, with every field and every plugin asked and every query run again.
//
// A transaction makes a new state, so whether the editor was told is whether its state is another object: a note
// of plain words is told nothing, whatever changes; a note with a query in it is told when another note changes
// (and its own times, which the query reads), and draws what the library now holds.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<(SampleLibrary, EditorView)> open(WidgetTester tester, String id) async {
    final library = SampleLibrary(<Note>[
      ...seedLibrary(seedNow),
      Note(id: 'plain', body: '# Plain words\n\nNothing here reads another note.\n\n- [ ] a to-do of its own\n', createdAt: seedNow, updatedAt: seedNow),
      Note(id: 'asker', body: '# Asking\n\nWhat is open:\n\n```query\nfrom: todos\nwhere: not done\n```\n\nWords after.\n', createdAt: seedNow, updatedAt: seedNow),
      Note(id: 'other', body: '# Another note\n\n- [ ] an open thing\n', createdAt: seedNow, updatedAt: seedNow),
    ], clock: () => seedNow + 60000);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.state<AppShellState>(find.byType(AppShell)).openNote(id);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (library, tester.widget<Editor>(find.byType(Editor)).view);
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a note of plain words is told nothing of the library: not another note\'s change, not its own save', (tester) async {
    final (library, view) = await open(tester, 'plain');
    var state = view.state;

    await library.save('other', '# Another note\n\n- [x] an open thing\n- [ ] and one more\n');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(identical(view.state, state), isTrue, reason: 'another note changed, and nothing in this one reads it');

    // A letter typed, and the save it brings: the letter is one transaction, and the save none.
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: 'x'), userEvent: 'input.type'));
    await tester.pump();
    state = view.state;
    final before = library.noteOf('plain')!.body;
    for (var i = 0; i < 12 && library.noteOf('plain')!.body == before; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(library.noteOf('plain')!.body, isNot(before), reason: 'the letter was saved');
    await tester.pump(const Duration(milliseconds: 200));
    expect(identical(view.state, state), isTrue, reason: 'the note\'s own save tells its editor nothing');
    await close(tester);
  });

  testWidgets('a note with a query is told when another note changes, and draws what the library holds now', (tester) async {
    final (library, view) = await open(tester, 'asker');
    final state = view.state;
    expect(find.textContaining('an open thing'), findsWidgets, reason: 'the query lists the other note\'s to-do');
    expect(find.textContaining('and one more'), findsNothing);

    await library.save('other', '# Another note\n\n- [ ] an open thing\n- [ ] and one more\n');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(view.state, state), isFalse, reason: 'the editor was told the library changed');
    expect(find.textContaining('and one more'), findsWidgets, reason: 'and the query was run again');
    await close(tester);
  });
}
