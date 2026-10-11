// Comments in the app put together (lib/root/note_desk.dart, ghost_root.dart): a note's editor draws its threads,
// Comment is on the band, in the bar's tools and in More with the threads' count, the sheet comes up over the note,
// and "Add a comment" on a note's menu opens the note with a comment started on its first line. The pieces
// themselves are held in test/comments and test/editor/comments.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/ask.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

const String commented = '# Barn dance\n\nThe ==venue==[^c1] is booked.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n```\n';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<SampleLibrary> open(WidgetTester tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  NoteScreenState screenOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen));

  Future<Note> make(WidgetTester tester, SampleLibrary library, String body) async {
    final note = library.create(body);
    await settle(tester, 2);
    return note;
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a note draws its threads, and a round opens the thread’s card over the note', (tester) async {
    final library = await open(tester);
    final note = await make(tester, library, commented);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    expect(find.byType(DrawnComments), findsOneWidget);
    expect(find.bySemanticsLabel('Comment by sam'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Comment by sam'));
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);
    expect(tester.widget<CommentSheet>(find.byType(CommentSheet)).page, const ThreadPage('c1'));
    await close(tester);
  });

  testWidgets('Comment is on the band and in More, which counts the threads and opens their list', (tester) async {
    final library = await open(tester);
    final note = await make(tester, library, commented);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    expect(tester.widget<ContextBand>(find.byType(ContextBand)).onComment, isNotNull);
    final seams = tester.widget<NoteScreen>(find.byType(NoteScreen)).seams;
    expect(seams.onComment, isNotNull);
    expect(seams.commentsSummary!(), '1 comment, open');
    seams.onCommentsList!();
    await settle(tester);
    expect(tester.widget<CommentSheet>(find.byType(CommentSheet)).page, const ListPage());
    await close(tester);
  });

  testWidgets('a comment started from the band’s seam is written into the note and saved with it', (tester) async {
    final library = await open(tester);
    final note = await make(tester, library, '# Plan\n\nBook the barn for Saturday');
    shellOf(tester).openNote(note.id);
    await settle(tester);
    final from = note.body.indexOf('the barn');
    tester.widget<ContextBand>(find.byType(ContextBand)).onComment!((from: from, to: from + 8));
    await settle(tester);
    expect(tester.widget<CommentSheet>(find.byType(CommentSheet)).page, const NewPage('the barn'));
    await tester.enterText(find.descendant(of: find.byType(CommentSheet), matching: find.byType(EditableText)), 'Which one?');
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == 'Add comment'));
    await settle(tester);
    expect(find.byType(CommentSheet), findsNothing);
    final view = screenOf(tester).view!;
    expect(view.state.doc.line(3).text, matches(RegExp(r'^Book ==the barn==\[\^c[0-9a-z]{4}\] for Saturday$')));
    expect(find.byType(DrawnComments), findsOneWidget);
    await close(tester);
    final kept = library.value.firstWhere((each) => each.id == note.id).body;
    expect(kept, contains('```comments\n'));
    expect(noteTitle(kept), 'Plan');
  });

  testWidgets('a comment asked for from a note’s menu is started on the note’s first line as it opens', (tester) async {
    final library = await open(tester);
    final note = await make(tester, library, '# Plan\n\nwords');
    commentAsks.ask(note.id);
    addTearDown(() => commentAsks.value = null);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);
    expect(tester.widget<CommentSheet>(find.byType(CommentSheet)).page, const NewPage(null));
    expect(commentAsks.value, isNull);
    await close(tester);
  });
}
