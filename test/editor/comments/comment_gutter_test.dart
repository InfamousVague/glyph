// The comment glyph in a line's gutter (lib/editor/comments/comment_gutter.dart; Matt, 2026-10-30: "When hovering a
// line show the comment icon in the gutter"): a real editor with its comments drawn, the [ScreenComments] a desk
// makes and its sheet, and the gutter round the page as the desk puts it. A desktop's window with a mouse, a phone
// with a finger, and a phone with a mouse (a Fold with one plugged in). Where the desk puts it is held in
// test/root/comment_gutter_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/ui/note_comments.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/comments/comment_gutter.dart';
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/format_looks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:glacier/glacier.dart';

import '../../sidebar/support.dart';
import '../../support/render.dart';

final RegExp anchor = RegExp(r'\[\^(c[0-9a-z]{4})\]');

const String plain = '# Plan\n\nBook the barn for Saturday.\n\nThen the band.\n';

const String commented = '# Barn dance\n\nThe ==venue==[^c1] is booked.\n\nThe band is not.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nThe hall or the barn?\n  matt 2026-10-04T19:05:40Z\n  The hall.\n```\n';

class Desk {
  Desk(this.view, this.comments, this.said);
  final EditorView view;
  final ScreenComments comments;
  final List<String> said;

  String get doc => view.state.doc.toString();
}

final Finder adding = find.byKey(const ValueKey<String>('comment-gutter-add'));
final Finder sheet = find.byType(CommentSheet);

Finder threadGlyph(int line) => find.byKey(ValueKey<String>('comment-gutter-thread-$line'));

CommentGutterState gutterOf(WidgetTester tester) => tester.state<CommentGutterState>(find.byType(CommentGutter));

/// The glyph that starts a comment, drawn and seen: in the tree, and at full opacity.
bool addShown(WidgetTester tester) {
  if (adding.evaluate().isEmpty) return false;
  final fade = tester.widget<AnimatedOpacity>(find.descendant(of: adding, matching: find.byType(AnimatedOpacity)));
  return fade.opacity == 1;
}

Future<Desk> pumpNote(WidgetTester tester, String doc, {bool readOnly = false, Size size = const Size(1280, 800), bool still = false}) async {
  final said = <String>[];
  late final EditorView view;
  final comments = ScreenComments(noteId: 'n1', view: () => view, say: said.add, colours: () => commentColours(orgId: null));
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(formats: marks, readOnly: readOnly, more: <Extension>[history(), formatLooks(marks), noteComments(() => comments.hooks)]),
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
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: ColoredBox(
            color: context.tokens.color('app-paper'),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 390,
                    child: CommentGutter(view: view, onStart: comments.start, onOpen: comments.hooks.open, colour: comments.hooks.colour, child: SingleChildScrollView(child: EditorColumn(view: view))),
                  ),
                ),
                ListenableBuilder(listenable: comments, builder: (context, _) => comments.sheet(context) ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return Desk(view, comments, said);
}

/// The middle of line [number]'s first letters on the screen.
Offset wordsOf(EditorView view, int number, [int into = 2]) => view.coordsAtPos(view.state.doc.line(number).from + into)!.center;

/// Where every line's start stands, to see that nothing moved.
List<Rect> starts(EditorView view) => [for (var n = 1; n <= view.state.doc.lines; n += 1) view.coordsAtPos(view.state.doc.line(n).from)!];

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

void main() {
  setUpAll(loadAppFonts);

  group('on a desktop, with a mouse', () {
    testWidgets('a pointer over a line brings the glyph beside its first row, and it goes as the pointer leaves', (tester) async {
      final desk = await pumpNote(tester, plain);
      expect(addShown(tester), isFalse);
      final mouse = await mouseAt(tester, wordsOf(desk.view, 3));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, 3);
      expect(addShown(tester), isTrue);
      // In the gutter, before the words, level with the middle of the line's first row.
      final glyph = tester.getRect(adding);
      final first = desk.view.coordsAtPos(desk.view.state.doc.line(3).from)!;
      expect(glyph.right, lessThanOrEqualTo(first.left + 0.5));
      expect(glyph.center.dy, moreOrLessEquals(first.center.dy, epsilon: 2));
      // To the next line of words: it goes with the pointer.
      await mouse.moveTo(wordsOf(desk.view, 5));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, 5);
      // Off the page: it fades.
      await mouse.moveTo(const Offset(900, 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final fading = tester.widget<AnimatedOpacity>(find.descendant(of: adding, matching: find.byType(AnimatedOpacity)));
      expect(fading.opacity, 0);
      expect(fading.duration, commentGlyphFade);
      await beat(tester);
      expect(addShown(tester), isFalse);
      expect(gutterOf(tester).hoveredLine, isNull);
      await away(tester);
    }, variant: mac);

    testWidgets('no glyph beside a blank line, where the + is and there are no words', (tester) async {
      final desk = await pumpNote(tester, plain);
      // A blank line between: none (the + is there).
      final blank = desk.view.coordsAtPos(desk.view.state.doc.line(4).from)!;
      await mouseAt(tester, Offset(200, blank.center.dy));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, isNull);
      await away(tester);
    }, variant: mac);

    testWidgets('it shows with reduced motion with no fade', (tester) async {
      final desk = await pumpNote(tester, plain, still: true);
      await mouseAt(tester, wordsOf(desk.view, 3));
      final fade = tester.widget<AnimatedOpacity>(find.descendant(of: adding, matching: find.byType(AnimatedOpacity)));
      expect(fade.duration, Duration.zero);
      expect(fade.opacity, 1);
      await away(tester);
    }, variant: mac);

    testWidgets('it says Comment on this line after a rest, and darkens under the pointer', (tester) async {
      final desk = await pumpNote(tester, plain);
      final mouse = await mouseAt(tester, wordsOf(desk.view, 3));
      await beat(tester);
      expect(find.byKey(const ValueKey('comment-gutter-tip')), findsNothing);
      expect(find.bySemanticsLabel(commentGlyphTip), findsOneWidget);
      Color ink() => tester.widget<AppIcon>(find.descendant(of: adding, matching: find.byType(AppIcon))).color!;
      final tokens = tester.element(adding).tokens;
      expect(ink(), tokens.color('app-ink-3'));
      await mouse.moveTo(tester.getCenter(adding));
      await tester.pump(commentGlyphTipWait + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 200));
      expect(ink(), tokens.color('app-ink-2'));
      expect(find.byKey(const ValueKey('comment-gutter-tip')), findsOneWidget);
      expect(find.text(commentGlyphTip), findsOneWidget);
      await away(tester);
    }, variant: mac);

    testWidgets('a click starts a comment on that line: the sheet opens, and the comment is written after its words', (tester) async {
      final desk = await pumpNote(tester, plain);
      final before = starts(desk.view);
      final mouse = await mouseAt(tester, wordsOf(desk.view, 3));
      await beat(tester);
      // The words did not move for it.
      expect(starts(desk.view), before);
      await mouse.moveTo(tester.getCenter(adding));
      await tester.pump();
      await mouse.down(tester.getCenter(adding));
      await mouse.up();
      await settle(tester);
      expect(sheet, findsOneWidget);
      expect(tester.widget<CommentSheet>(sheet).page, const NewPage(null));
      // The caret did not land in the line's gutter under the press.
      expect(desk.view.state.selection.main.head, 0);
      await tester.enterText(find.descendant(of: sheet, matching: find.byType(EditableText)), 'Which Saturday?');
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == 'Add comment'));
      await settle(tester);
      expect(desk.view.state.doc.line(3).text, matches(RegExp(r'^Book the barn for Saturday\.\[\^c[0-9a-z]{4}\]$')));
      expect(desk.doc, contains('Which Saturday?'));
      // Now the line has a thread: its glyph is the filled one, with its count.
      await beat(tester);
      expect(threadGlyph(3), findsOneWidget);
      expect(find.descendant(of: threadGlyph(3), matching: find.text('1')), findsOneWidget);
      await away(tester);
    }, variant: mac);

    testWidgets('words selected on the line are what the glyph comments on', (tester) async {
      final desk = await pumpNote(tester, plain);
      final from = desk.doc.indexOf('the barn');
      desk.view.dispatch(TransactionSpec(selection: EditorSelection.single(from, from + 8)));
      await tester.pump();
      final mouse = await mouseAt(tester, wordsOf(desk.view, 3));
      await beat(tester);
      await mouse.down(tester.getCenter(adding));
      await mouse.up();
      await settle(tester);
      expect(tester.widget<CommentSheet>(sheet).page, const NewPage('the barn'));
      await away(tester);
    }, variant: mac);

    testWidgets('a line with a thread wears it filled with its count all the time, and a click opens it', (tester) async {
      final desk = await pumpNote(tester, commented);
      await beat(tester);
      expect(gutterOf(tester).threadLines, [3]);
      expect(threadGlyph(3), findsOneWidget);
      // The thread and its reply.
      expect(find.descendant(of: threadGlyph(3), matching: find.text('2')), findsOneWidget);
      expect(find.bySemanticsLabel('2 comments on this line'), findsOneWidget);
      final glyph = tester.getRect(threadGlyph(3));
      final first = desk.view.coordsAtPos(desk.view.state.doc.line(3).from)!;
      expect(glyph.right, lessThanOrEqualTo(first.left + 0.5));
      expect(glyph.center.dy, moreOrLessEquals(first.center.dy, epsilon: 2));
      // Under the pointer it stays itself: no second glyph to start one.
      final mouse = await mouseAt(tester, wordsOf(desk.view, 3));
      await beat(tester);
      expect(addShown(tester), isFalse);
      await mouse.down(tester.getCenter(threadGlyph(3)));
      await mouse.up();
      await settle(tester);
      expect(tester.widget<CommentSheet>(sheet).page, const ThreadPage('c1'));
      await away(tester);
    }, variant: mac);

    testWidgets('no glyph in fenced code, a table, the front matter, or the comments’ own list', (tester) async {
      const doc = '---\ntags: plan\n---\n# Plan\n\n```js\nconst barn = 1;\n```\n\n| Day | Who |\n| --- | --- |\n| Sat | Sam |\n\nWords here.\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nAn orphan.\n```\n';
      final desk = await pumpNote(tester, doc);
      await beat(tester);
      final mouse = await mouseAt(tester, wordsOf(desk.view, 14));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, 14, reason: 'the line of words is commentable');
      for (final (line, what) in [(2, 'front matter'), (7, 'fenced code'), (12, 'a table'), (17, 'the comments')]) {
        expect(commentableLine(desk.view.state, line), isFalse, reason: what);
        final at = desk.view.coordsAtPos(desk.view.state.doc.line(line).from);
        if (at == null) continue;
        await mouse.moveTo(Offset(200, at.center.dy));
        await beat(tester);
        expect(gutterOf(tester).hoveredLine, isNull, reason: what);
      }
      await away(tester);
    }, variant: mac);

    testWidgets('a note that cannot be written in has no glyph to start one, and its threads still open', (tester) async {
      final desk = await pumpNote(tester, commented, readOnly: true);
      await beat(tester);
      await mouseAt(tester, wordsOf(desk.view, 5));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, isNull);
      expect(adding, findsNothing);
      expect(threadGlyph(3), findsOneWidget);
      await tester.tap(threadGlyph(3));
      await settle(tester);
      expect(tester.widget<CommentSheet>(sheet).page, const ThreadPage('c1'));
      await away(tester);
    }, variant: mac);
  });

  group('on a phone', () {
    testWidgets('under a finger there is no glyph: a press is the words’, and a thread has its round', (tester) async {
      final desk = await pumpNote(tester, commented, size: const Size(390, 844));
      await beat(tester);
      final before = starts(desk.view);
      expect(adding, findsNothing);
      expect(threadGlyph(3), findsNothing);
      await tester.tapAt(wordsOf(desk.view, 5));
      await beat(tester);
      expect(adding, findsNothing);
      expect(threadGlyph(3), findsNothing);
      expect(sheet, findsNothing);
      expect(starts(desk.view), before);
      // The thread's round in the words is the way in.
      expect(find.bySemanticsLabel(RegExp('^Comment by sam')), findsOneWidget);
      await away(tester);
    });

    testWidgets('with a mouse (a Fold with one plugged in) the glyphs come with its first move, and go with a finger', (tester) async {
      final desk = await pumpNote(tester, commented, size: const Size(390, 844));
      await beat(tester);
      expect(threadGlyph(3), findsNothing);
      await mouseAt(tester, wordsOf(desk.view, 5));
      await beat(tester);
      expect(gutterOf(tester).hoveredLine, 5);
      expect(addShown(tester), isTrue);
      expect(threadGlyph(3), findsOneWidget);
      // Inside the page's own padding: the words start after it, and the glyph is in it.
      final glyph = tester.getRect(adding);
      expect(glyph.left, greaterThanOrEqualTo(0));
      expect(glyph.right, lessThanOrEqualTo(desk.view.coordsAtPos(desk.view.state.doc.line(5).from)!.left + 0.5));
      await tester.tapAt(wordsOf(desk.view, 1));
      await beat(tester);
      expect(threadGlyph(3), findsNothing);
      expect(adding, findsNothing);
      await away(tester);
    });
  });
}
