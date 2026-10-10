// A canvas renamed from its tab while it is the note being read (App.tsx `renameNote`): the name goes through its
// open screen, which writes it itself, so the screen's own words have it at once and its next save keeps it. A tab
// that is not being read has no screen holding it, and is a plain write.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a canvas renamed from its tab is named through its open screen, and keeps the name through its next change', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    final canvas = library.create(canvasNoteBody('Map', parseCanvas('{"nodes":[{"id":"a","type":"text","text":"A card","x":0,"y":0,"width":120,"height":60}],"edges":[]}')!));
    final other = library.create(canvasNoteBody('Other', parseCanvas('{"nodes":[],"edges":[]}')!));
    await tester.pump();
    shell.openNote(canvas.id);
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    expect(noteTitle(screen.body), 'Map');

    // Renamed from its tab: the screen's own words have the name before anything is saved.
    tester.widget<AppShell>(find.byType(AppShell)).onRenameNote!(canvas.id, 'The cabin, laid out');
    await tester.pump();
    expect(noteTitle(screen.body), 'The cabin, laid out');
    expect(canvasOf(screen.body)!.nodes.single.text, 'A card');

    // And a card moved after it is saved with the name, not over it.
    final view = tester.state<CanvasViewState>(find.byType(CanvasView));
    final moved = withNode(view.live, view.live.nodes.single.put({'x': 40}));
    tester.widget<CanvasView>(find.byType(CanvasView)).onChange!(withCanvas(screen.body, moved));
    await settle(tester);

    // A tab that is not the note being read is written where it is kept.
    tester.widget<AppShell>(find.byType(AppShell)).onRenameNote!(other.id, 'Another');
    await settle(tester, 2);
    expect(noteTitle(library.noteOf(other.id)!.body), 'Another');

    shell.backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final kept = library.noteOf(canvas.id)!.body;
    expect(noteTitle(kept), 'The cabin, laid out');
    expect(canvasOf(kept)!.nodes.single.x, 40);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  // Unwired 1 (docs/PARITY.md): a page's heading retyped in the app keeps its line in its notebook's index
  // (editor/useNoteSaving.ts calling book/followRename.ts), where the port dropped the page out of its notebook.
  testWidgets('a page renamed in its editor keeps its place in the notebook that lists it', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    final book = library.create('---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n1. [[Hedgerows in spring]]\n2. [[Trees]]\n');
    final page = library.create('# Hedgerows in spring\n\nWhy this guide.\n');
    await tester.pump();
    shell.openNote(page.id);
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: 2, to: '# Hedgerows in spring'.length, insert: 'Before you start'), userEvent: 'input.type'));
    // The save's debounce, the save, and the notebook written after it.
    await settle(tester, 12);
    expect(noteTitle(library.noteOf(page.id)!.body), 'Before you start');
    expect(library.noteOf(book.id)!.body, contains('1. [[Before you start]]'));
    expect(library.noteOf(book.id)!.body, contains('2. [[Trees]]'));

    shell.backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
