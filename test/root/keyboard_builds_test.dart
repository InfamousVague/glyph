// The keyboard coming up and going down builds the open note's screen when what the screen draws by it changes
// (whether the keyboard is up at all), not at every frame of its rise: the screen asked the window for the
// keyboard's height with its own context, a new number each frame, and was built again whole each time, a canvas
// and its cards with it (lib/note/note_screen.dart `_KeyboardWatch`, `_AboveKeyboard`).
//
// Counted by the framework's own word for an element built again (`debugOnRebuildDirtyWidget`), over twelve frames
// of a keyboard rising and twelve of it going: the canvas's view under a canvas, and the editor's host under a
// note of words. The page itself still ends where the keyboard begins at every frame (its bottom padding is asked
// where it is used).
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_editor.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<Map<Type, int>> rebuiltThroughKeyboard(WidgetTester tester, String noteId, {required Set<Type> watch, void Function()? halfway}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.state<AppShellState>(find.byType(AppShell)).openNote(noteId);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final counted = <Type, int>{for (final type in watch) type: 0};
    final ratio = tester.view.devicePixelRatio;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final type = element.widget.runtimeType;
      if (counted.containsKey(type)) counted[type] = counted[type]! + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    // Up, twelve frames; then down, twelve frames.
    for (var i = 1; i <= 12; i++) {
      tester.view.viewInsets = FakeViewPadding(bottom: i * 25 * ratio);
      await tester.pump(const Duration(milliseconds: 16));
    }
    halfway?.call();
    for (var i = 11; i >= 0; i--) {
      tester.view.viewInsets = FakeViewPadding(bottom: i * 25 * ratio);
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    tester.view.resetViewInsets();
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    return counted;
  }

  testWidgets('a canvas is not built again at every frame of the keyboard', (tester) async {
    final counted = await rebuiltThroughKeyboard(tester, 'cabin-canvas', watch: <Type>{CanvasView, NoteScreen});
    // ignore: avoid_print
    print('a canvas through a keyboard up and down, 24 frames: $counted');
    // Once as the keyboard comes up (the room kept for the phone's bar goes) and once as it is gone.
    expect(counted[CanvasView], lessThanOrEqualTo(4), reason: 'the canvas is built when the keyboard is up or gone, not at each frame between: $counted');
  });

  testWidgets('nor is a note of words, whose page still ends where the keyboard begins', (tester) async {
    double? pageFoot;
    final counted = await rebuiltThroughKeyboard(
      tester,
      seedLibrary(seedNow).firstWhere((note) => !note.body.contains('"nodes"') && !note.body.contains('book: true')).id,
      watch: <Type>{NoteEditorHost, NoteScreen},
      halfway: () {
        // With the keyboard 300 up, the page's scroll view ends 300 above the window's foot.
        final scroll = tester.renderObject<RenderBox>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(CustomScrollView)).first);
        pageFoot = scroll.localToGlobal(Offset(0, scroll.size.height)).dy;
      },
    );
    // ignore: avoid_print
    print('a note of words through a keyboard up and down, 24 frames: $counted; the page\'s foot with the keyboard 300 up: $pageFoot');
    expect(counted[NoteEditorHost], lessThanOrEqualTo(4), reason: 'the editor\'s host is handed a new spec when the keyboard is up or gone, not at each frame: $counted');
    expect(pageFoot, closeTo(844 - 300, 0.5), reason: 'the page ends where the keyboard begins');
  });
}
