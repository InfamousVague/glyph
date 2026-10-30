// A heading's fold triangle in the line's gutter beside the comment glyph (lib/editor/comments/comment_gutter.dart,
// lib/editor/view/section_folds.dart; Matt, 2026-10-30, "add all 12"): before the glyph and never over it, on a
// desktop with a mouse, on a phone under a finger, and on a phone with a mouse (a Fold with one plugged in), where
// the gutter is one square wide and the two share it; a heading with a thread; a press folds and unfolds.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/ui/note_comments.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/comments/comment_gutter.dart';
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/section_folds.dart';
import 'package:ghost_md/note/note_editor.dart' show noteLookEnv;
import 'package:ghost_md/plugins/marks.dart';
import 'package:glacier/glacier.dart';

import '../../sidebar/support.dart';
import '../../support/editor_text.dart';
import '../../support/render.dart';

const String plan = '# Barn dance\n\nThe venue is booked.\n\n## Band\n\nNot yet.\n\n## Food\n\nA potluck.\n';

const String commented = '# Barn dance\n\n## Venue[^c1]\n\nThe hall.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n```\n';

final Finder adding = find.byKey(const ValueKey<String>('comment-gutter-add'));
Finder foldGlyph(int line) => find.byKey(ValueKey<String>('fold-gutter-$line'));
Finder threadGlyph(int line) => find.byKey(ValueKey<String>('comment-gutter-thread-$line'));
CommentGutterState gutterOf(WidgetTester tester) => tester.state<CommentGutterState>(find.byType(CommentGutter));

bool shown(WidgetTester tester, Finder glyph) {
  if (glyph.evaluate().isEmpty) return false;
  return tester.widget<AnimatedOpacity>(find.descendant(of: glyph, matching: find.byType(AnimatedOpacity))).opacity == 1;
}

/// The triangle as it is drawn, inside its place.
Rect triangleOf(WidgetTester tester, int line) => tester.getRect(find.descendant(of: foldGlyph(line), matching: find.byType(FoldTriangle)));

Future<EditorView> pumpNote(WidgetTester tester, String doc, {Size size = const Size(1280, 800), double width = 390, String? look}) async {
  late final EditorView view;
  final comments = ScreenComments(noteId: 'n1', view: () => view, say: (_) {}, colours: () => commentColours(orgId: null));
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(formats: marks, more: <Extension>[history(), formatLooks(marks), noteComments(() => comments.hooks), sectionFolds()]),
    ),
  );
  addTearDown(view.destroy);
  addTearDown(comments.dispose);
  view.focusRequest = () => view.setFocused(true);
  await pumpPage(
    tester,
    size: size,
    BackScope(
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('app-paper'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CommentGutter(view: view, onStart: comments.start, onOpen: comments.hooks.open, colour: comments.hooks.colour, child: SingleChildScrollView(child: EditorColumn(view: view, env: look == null ? null : noteLookEnv(context, look: look, pageWidth: width)))),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return view;
}

Offset wordsOf(EditorView view, int number, [int into = 3]) => view.coordsAtPos(view.state.doc.line(number).from + into)!.center;

Future<TestGesture> mouseAt(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(at);
  await tester.pump();
  return mouse;
}

Future<void> beat(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 200));
}

final TargetPlatformVariant mac = TargetPlatformVariant.only(TargetPlatform.macOS);

/// The two in one gutter: the triangle before the glyph, neither over the other, both before the words.
void sideBySide(WidgetTester tester, EditorView view, int line, Finder comment) {
  final triangle = tester.getRect(foldGlyph(line));
  final glyph = tester.getRect(comment);
  final words = view.coordsAtPos(view.state.doc.line(line).from)!;
  expect(triangle.right, lessThanOrEqualTo(glyph.left + 0.01), reason: 'the triangle before the comment glyph, not over it');
  expect(triangle.overlaps(glyph), isFalse);
  expect(glyph.right, lessThanOrEqualTo(words.left + 0.5), reason: 'the glyph in the gutter, before the words');
  expect(triangle.left, greaterThanOrEqualTo(0), reason: 'inside the page');
  expect(triangle.center.dy, moreOrLessEquals(glyph.center.dy, epsilon: 0.5), reason: 'on the same row');
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  group('on a desktop, with a mouse', () {
    testWidgets('a pointer over a heading brings its triangle before the comment glyph, and a click folds it', (tester) async {
      final view = await pumpNote(tester, plan);
      expect(shown(tester, foldGlyph(5)), isFalse, reason: 'not before a pointer comes');
      final mouse = await mouseAt(tester, wordsOf(view, 5));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, 5);
      expect(shown(tester, foldGlyph(5)), isTrue);
      expect(shown(tester, adding), isTrue);
      expect(gutterOf(tester).foldLines, [5]);
      sideBySide(tester, view, 5, adding);
      // A line of words has no triangle, and its glyph keeps its whole square.
      await mouse.moveTo(wordsOf(view, 3));
      await beat(tester);
      expect(gutterOf(tester).foldLines, isEmpty);
      expect(tester.getSize(adding).width, moreOrLessEquals(tester.getSize(adding).height));
      // Back to the heading, and its triangle pressed.
      await mouse.moveTo(wordsOf(view, 5));
      await beat(tester);
      await mouse.moveTo(tester.getCenter(foldGlyph(5)));
      await tester.pump();
      await mouse.down(tester.getCenter(foldGlyph(5)));
      await mouse.up();
      await beat(tester);
      expect(foldedOf(view.state), {view.state.doc.line(5).from});
      expect(editorText('Not yet.'), findsNothing);
      expect(view.state.selection.main.head, 0, reason: 'the press was the triangle\'s, not a caret put in the gutter');
      // Folded, it wears its triangle with the pointer gone.
      await mouse.moveTo(const Offset(1200, 780));
      await beat(tester);
      expect(shown(tester, foldGlyph(5)), isTrue);
      expect(gutterOf(tester).foldLines, [5]);
      await mouse.down(tester.getCenter(foldGlyph(5)));
      await mouse.up();
      await beat(tester);
      expect(foldedOf(view.state), isEmpty);
      expect(editorText('Not yet.'), findsOneWidget);
      await away(tester);
    }, variant: mac);

    testWidgets('a heading with a thread: its filled glyph and the triangle side by side', (tester) async {
      final view = await pumpNote(tester, commented);
      await mouseAt(tester, wordsOf(view, 3));
      await beat(tester);
      expect(threadGlyph(3), findsOneWidget);
      expect(shown(tester, foldGlyph(3)), isTrue);
      sideBySide(tester, view, 3, threadGlyph(3));
      expect(find.descendant(of: threadGlyph(3), matching: find.text('1')), findsOneWidget, reason: 'its count still reads');
      await away(tester);
    }, variant: mac);

    testWidgets('a page to read on a wide window has room for both: the glyph keeps its whole square', (tester) async {
      final view = await pumpNote(tester, plan, width: 1100, look: 'reading');
      // The gutter widened to the reading column's edge.
      final gutter = view.look!.env.gutter;
      expect(gutter, greaterThan(200));
      await mouseAt(tester, wordsOf(view, 5));
      await beat(tester);
      sideBySide(tester, view, 5, adding);
      expect(tester.getSize(adding).width, moreOrLessEquals(tester.getSize(adding).height), reason: 'its whole square');
      expect(tester.getRect(foldGlyph(5)).right, moreOrLessEquals(tester.getRect(adding).left, epsilon: 0.01), reason: 'the triangle just before it');
      await away(tester);
    }, variant: mac);
  });

  group('on a phone', () {
    testWidgets('under a finger every heading that folds wears its triangle, its target the gutter\'s square, and a tap folds it', (tester) async {
      final view = await pumpNote(tester, plan, size: const Size(390, 844));
      await beat(tester);
      expect(adding, findsNothing, reason: 'no comment glyph under a finger');
      expect(gutterOf(tester).foldLines, [1, 5, 9]);
      for (final line in [1, 5, 9]) {
        expect(shown(tester, foldGlyph(line)), isTrue);
      }
      final place = tester.getRect(foldGlyph(5));
      final words = view.coordsAtPos(view.state.doc.line(5).from)!;
      expect(place.right, lessThanOrEqualTo(words.left + 0.5));
      expect(place.width, moreOrLessEquals(place.height), reason: 'the whole square to tap');
      expect(place.left, greaterThanOrEqualTo(0));
      await tester.tapAt(place.center);
      await beat(tester);
      expect(foldedOf(view.state), {view.state.doc.line(5).from});
      expect(editorText('Not yet.'), findsNothing);
      await away(tester);
    });

    testWidgets('with a mouse (a Fold with one plugged in) the gutter is one square: the triangle and the glyph share it', (tester) async {
      final view = await pumpNote(tester, commented, size: const Size(390, 844));
      await mouseAt(tester, wordsOf(view, 3));
      await beat(tester);
      expect(shown(tester, foldGlyph(3)), isTrue);
      expect(threadGlyph(3), findsOneWidget);
      sideBySide(tester, view, 3, threadGlyph(3));
      final gutter = view.look!.env.gutter;
      final words = view.coordsAtPos(view.state.doc.line(3).from)!;
      expect(tester.getRect(foldGlyph(3)).left, moreOrLessEquals(words.left - gutter, epsilon: 0.5), reason: 'at the gutter\'s outer edge');
      // The drawn triangle sits inside its own place.
      final drawn = triangleOf(tester, 3);
      expect(tester.getRect(foldGlyph(3)).contains(drawn.center), isTrue);
      await away(tester);
    });

    testWidgets('a heading on a phone with a mouse: the comment glyph to start one beside the triangle', (tester) async {
      final view = await pumpNote(tester, plan, size: const Size(390, 844));
      await mouseAt(tester, wordsOf(view, 9));
      await beat(tester);
      expect(shown(tester, adding), isTrue);
      expect(shown(tester, foldGlyph(9)), isTrue);
      sideBySide(tester, view, 9, adding);
      await away(tester);
    });
  });
}
