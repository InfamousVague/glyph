import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_tree.dart';

import '../support/render.dart';
import 'support.dart';

/// Simple mode's sidebar (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): the tools over the notes
/// are New note, Search and commands, Open or Fold every folder where there are folders, and Close; no New
/// workspace and no names-only switch. What the root leaves out of it (Browse files, Tags, the smart notebooks, the
/// graph) is the root's test (test/root/simple_test.dart); here is what the tree itself trims, and that the folders
/// a person already has still show.
void main() {
  setUpAll(loadAppFonts);

  Note note(String id, {String? body}) => Note(id: id, body: body ?? '# $id', createdAt: 0, updatedAt: 0);

  Future<void> show(WidgetTester tester, NoteTree tree) => pumpPage(tester, BackScope(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: tree))));

  NoteTree tree({required bool simple, required WorkspaceStore spaces, List<Note> notes = const [], VoidCallback? onClose}) => NoteTree(
        notes: notes,
        activeId: null,
        onOpen: (_) {},
        onNew: () {},
        onCommands: () {},
        onSettings: () {},
        onClose: onClose,
        workspaces: spaces,
        stored: MemoryStored(),
        simple: simple,
      );

  Finder button(String label) => find.bySemanticsLabel(label);

  testWidgets('offers New note, Search and Close, and no New workspace or names only', (tester) async {
    await show(tester, tree(simple: true, spaces: WorkspaceStore(), notes: [note('a'), note('b')], onClose: () {}));
    expect(button('New note'), findsOneWidget);
    expect(button('Search and commands'), findsOneWidget);
    expect(button('Close'), findsOneWidget);
    expect(button('New workspace'), findsNothing);
    expect(button('Show names only'), findsNothing);
    expect(button('Show each note drawn small'), findsNothing);
    // No folders, so nothing to open or fold.
    expect(button('Open every folder'), findsNothing);
    expect(button('Fold every folder'), findsNothing);
    await away(tester);
  });

  testWidgets('still shows the folders a person has, with the tool to open and fold them', (tester) async {
    final spaces = WorkspaceStore(
      storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'w1', name: 'Work', hue: 'sea')], notes: {'a': 'w1'})),
    );
    await show(tester, tree(simple: true, spaces: spaces, notes: [note('a'), note('b')]));
    expect(find.text('Work'), findsOneWidget, reason: 'a workspace holding notes is never hidden');
    expect(button('Fold every folder'), findsOneWidget);
    expect(button('New workspace'), findsNothing);
    await away(tester);
  });

  testWidgets('has the whole tool row in advanced', (tester) async {
    await show(tester, tree(simple: false, spaces: WorkspaceStore(), notes: [note('a')], onClose: () {}));
    for (final tool in ['New note', 'New workspace', 'Search and commands', 'Show names only', 'Close']) {
      expect(button(tool), findsOneWidget, reason: '$tool is drawn');
    }
    await away(tester);
  });
}
