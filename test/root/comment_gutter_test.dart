// The comment glyph in a line's gutter in the app put together (lib/root/note_desk.dart puts
// lib/editor/comments/comment_gutter.dart round the note's page; Matt, 2026-10-30: "When hovering a line show the
// comment icon in the gutter"): on the Mac's window a pointer over a line brings it and a click starts a comment
// there, a thread's line wears its count and opens it, simple mode has it as advanced does, and a phone under a
// finger has none. The piece's own cases are test/editor/comments/comment_gutter_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/comments/comment_gutter.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

const String commented = '# Barn dance\n\nThe ==venue==[^c1] is booked.\n\nThe band is not.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n```\n';

final Finder adding = find.byKey(const ValueKey<String>('comment-gutter-add'));
final Finder sheet = find.byType(CommentSheet);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<SampleLibrary> open(WidgetTester tester, {Size size = const Size(390, 844), bool simple = false}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      prefs: simple ? const Preferences(theme: 'light').choosing('simple') : const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    if (size.width > 600) {
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewPadding = FakeViewPadding.zero;
    }
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  EditorView viewOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
  CommentGutterState gutterOf(WidgetTester tester) => tester.state<CommentGutterState>(find.byType(CommentGutter));

  Future<Note> openNote(WidgetTester tester, SampleLibrary library, String body) async {
    final note = library.create(body);
    await settle(tester, 2);
    shellOf(tester).openNote(note.id);
    await settle(tester);
    return note;
  }

  Offset wordsOf(EditorView view, int number) => view.coordsAtPos(view.state.doc.line(number).from + 2)!.center;

  Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(at);
    await settle(tester, 3);
    return mouse;
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final simple in [false, true]) {
    testWidgets('on the Mac a pointer over a line brings the glyph, and a click starts a comment there${simple ? ', in simple mode' : ''}', (tester) async {
      final library = await open(tester, size: const Size(1280, 800), simple: simple);
      await openNote(tester, library, '# Plan\n\nBook the barn for Saturday.\n\nThen the band.\n');
      final view = viewOf(tester);
      final before = [for (var n = 1; n <= view.state.doc.lines; n += 1) view.coordsAtPos(view.state.doc.line(n).from)];
      final mouse = await mouseAt(tester, wordsOf(view, 3));
      expect(gutterOf(tester).hoveredLine, 3);
      expect(adding, findsOneWidget);
      // Beside the words, not over them, and nothing moved for it.
      expect(tester.getRect(adding).right, lessThanOrEqualTo(view.coordsAtPos(view.state.doc.line(3).from)!.left + 0.5));
      expect([for (var n = 1; n <= view.state.doc.lines; n += 1) view.coordsAtPos(view.state.doc.line(n).from)], before);
      await mouse.down(tester.getCenter(adding));
      await mouse.up();
      await settle(tester);
      expect(tester.widget<CommentSheet>(sheet).page, const NewPage(null));
      await tester.enterText(find.descendant(of: sheet, matching: find.byType(EditableText)), 'Which Saturday?');
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == 'Add comment'));
      await settle(tester);
      expect(view.state.doc.line(3).text, matches(RegExp(r'^Book the barn for Saturday\.\[\^c[0-9a-z]{4}\]$')));
      expect(find.byKey(const ValueKey<String>('comment-gutter-thread-3')), findsOneWidget);
      await close(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }

  testWidgets('on the Mac a line with a thread wears its count, and a click opens the thread', (tester) async {
    final library = await open(tester, size: const Size(1280, 800));
    await openNote(tester, library, commented);
    final glyph = find.byKey(const ValueKey<String>('comment-gutter-thread-3'));
    expect(glyph, findsOneWidget);
    expect(find.descendant(of: glyph, matching: find.text('1')), findsOneWidget);
    await tester.tap(glyph);
    await settle(tester);
    expect(tester.widget<CommentSheet>(sheet).page, const ThreadPage('c1'));
    await close(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('on a phone under a finger there is no glyph, and a press on a line is the words’', (tester) async {
    final library = await open(tester);
    await openNote(tester, library, commented);
    final view = viewOf(tester);
    expect(find.byKey(const ValueKey<String>('comment-gutter-thread-3')), findsNothing);
    await tester.tapAt(wordsOf(view, 5));
    await settle(tester);
    expect(adding, findsNothing);
    expect(sheet, findsNothing);
    await close(tester);
  });
}
