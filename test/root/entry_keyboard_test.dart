// A journal's new entry, opened with the caret at the end of its words, as the keyboard comes up (README, stages 5
// and 6: the entry was scrolled until the caret's line stood at the top of the page, its heading and the journal's
// bar above it out of sight). On the page a caret in plain sight is left where it is (CodeMirror's
// `scrollRectIntoView`, "nearest"), so a short entry stays as it opened: its heading under the bar, the caret two
// lines down, and the keyboard over the empty paper below.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/editor_text.dart';
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

  testWidgets('a journal’s new entry keeps its heading and the journal’s bar in sight as the keyboard comes up', (tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    final journal = library.create('---\ntitle: "Days"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\n---\n# Days\n\n');
    await tester.pump();
    shell.openNote(journal.id);
    await settle(tester);
    await tester.runAsync(() async {
      tester.widget<JournalView>(find.byType(JournalView)).onNewEntry!('# {{date}}\n\n**{{time}}** ');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    final entry = library.noteOf(shell.shown!)!;
    expect(entry.id, isNot(journal.id));
    // Opened ready to type: the caret after the last of its words, two lines under its heading.
    expect(view.state.selection.main.head, view.state.doc.length);
    // The entry's heading, as its template wrote it: the day.
    final title = view.state.doc.line(5).text;
    expect(title, startsWith('# '));
    final heading = editorTextRect(tester, title);
    final bar = tester.getRect(find.byType(BookBar));
    Scrollable page() => tester.widget<Scrollable>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first);
    final before = page().controller!.position.pixels;

    // The keyboard comes up, and stays.
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await settle(tester, 8);
    expect(view.hasFocus, isTrue);
    expect(page().controller!.position.pixels, before, reason: 'the caret was in plain sight: the page is left where it was');
    expect(editorTextRect(tester, title), heading);
    expect(tester.getRect(find.byType(BookBar)), bar);
    // And the caret's own line is clear of the keyboard.
    final caret = view.coordsAtPos(view.state.selection.main.head)!;
    expect(caret.bottom, lessThan(844 - 300));

    // A line typed there moves nothing either.
    view.dispatch(view.state.replaceSelection('walked the dog'));
    await settle(tester, 3);
    expect(page().controller!.position.pixels, before);
    expect(editorTextRect(tester, title), heading);

    tester.view.resetViewInsets();
    shell.backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
