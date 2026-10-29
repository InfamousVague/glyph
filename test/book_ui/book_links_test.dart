// A tap on a link in a notebook opens it: in the notebook's own words over its index, and in its pages read straight
// through, short ones drawn whole and long ones drawn as the note's page draws them (lib/book/book_view.dart,
// lib/editor/media/links.dart `ReadLinks`, `readLinkAt`). Matt, 2026-10-29: "Allow opening web links in the book
// view". The words there are drawn to be read and take no caret, so the editor's own press on a link (which opens
// it in a note) never heard them.
//
// On the real renderer and its gestures, at a phone's size and a Mac window's: a finger's tap and a mouse's click,
// a drag that scrolls, the pointer's shape. The opener is a fake given as the note's desk gives its own
// (`MediaSeams.openLink`, lib/root/note_desk.dart `_bookDrawing`).
import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/items/items.dart' show itemExtensions;
import 'package:ghost_md/editor/items/wiki_links.dart' show WikiOptions;
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/media/media.dart' show MediaSeams, mediaExtensions;
import 'package:ghost_md/editor/state/state.dart' show Extension;
import 'package:ghost_md/editor/tables/table_box.dart' show GlyphTable, RenderGlyphTable;
import 'package:ghost_md/editor/tables/tables.dart' show drawnTables;

import '../support/editor_text.dart';
import 'support.dart';

const String hello = 'https://hello.trade/waitlist?ref=EXU6LYUP5K';
const String lan = 'http://192.168.18.21:3120';

/// The notebook: its own words with a link of each kind, then its index.
const String notebook = '---\ntitle: "Field guide"\nbook: true\n---\n'
    'Join [the preface waitlist]($hello) first, or the QA page $lan for inboxes, and read [[Trees]] after.\n\n'
    'Words before the pages with nothing in them to open.\n\n'
    '1. [[Introduction]]\n2. [[Trees]]\n';

/// A page short enough to be drawn whole, read straight through.
final String intro = [
  '# Introduction',
  '',
  'Tap [the page waitlist]($hello) on a phone and the app opens.',
  '',
  'Plain words of the page, with nothing to open.',
  '',
  'See [[Trees]] for the rest.',
  '',
  '| Code | Link |',
  '| --- | --- |',
  '| EXU6LYUP5K | [hello.trade/waitlist?ref=EXU6LYUP5K]($hello) |',
].join('\n');

/// A long page, drawn as the note's page draws its lines, with a link near its top.
final String trees = [
  '# Trees',
  '',
  'The long page links [the tree waitlist]($hello) here.',
  '',
  for (var i = 0; i < 40; i += 1) 'Paragraph $i of the long page, which runs on about the wind and the bent trees by the wall.\n',
].join('\n');

const Size phone = Size(390, 844);
const Size mac = Size(1280, 900);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));
  tearDown(() => BookViewState.longPage = 400);

  /// What was opened: web addresses by the desk's opener, notes by title (a `[[link]]`'s, a page title's).
  late List<String> opened, notes;

  BookDrawing drawing() => BookDrawing(
        extensions: <Extension>[
          drawnTables(),
          itemExtensions(wiki: WikiOptions(known: (_) => true, open: (title, [anchor]) => notes.add(title))),
          mediaExtensions(seams: MediaSeams(openLink: (url) async => opened.add(url))),
        ],
      );

  Future<void> show(WidgetTester tester, {required Size size, BookDrawing? given, bool drawn = true, ScrollController? scroll}) async {
    opened = <String>[];
    notes = <String>[];
    await pumpView(
      tester,
      BookView(
        body: notebook,
        title: 'Field guide',
        known: (_) => true,
        open: notes.add,
        titles: () => const <String>[],
        onChange: (_) {},
        bodyOf: (title) => switch (title) {
          'Introduction' => intro,
          'Trees' => trees,
          _ => null,
        },
        drawing: drawn ? given ?? drawing() : null,
      ),
      size: size,
      scroll: scroll,
    );
  }

  Future<void> readThrough(WidgetTester tester) async {
    await press(tester, 'Read straight through');
    for (var i = 0; i < 4; i += 1) {
      await tester.pump();
    }
  }

  /// The middle of the drawn table's link in its first row, on screen.
  Offset cellLink(WidgetTester tester) {
    final table = tester.renderObject<RenderGlyphTable>(find.byType(GlyphTable));
    return table.localToGlobal(table.table.cells[1][1].linkBoxes.first.first.center);
  }

  /// The long page's title in the middle of the window, clear of the bar that stays at its top.
  Future<void> toLongPage(WidgetTester tester) async {
    unawaited(Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('book-read-title-1'))), alignment: 0.4));
    await tester.pump();
    await tester.pump();
  }

  /// A mouse's click at [at].
  Future<void> click(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
  }

  for (final (name, size) in <(String, Size)>[('on a phone', phone), ('on a Mac', mac)]) {
    final kind = size == mac ? PointerDeviceKind.mouse : PointerDeviceKind.touch;
    Future<void> tap(WidgetTester tester, Offset at) async {
      await tester.tapAt(at, kind: kind);
      await tester.pump();
    }

    group('the notebook\'s own words, $name', () {
      testWidgets('a tap on a link opens its address through the opener, a bare address too, and a [[link]] its note', (tester) async {
        await show(tester, size: size);
        await tap(tester, editorTextRect(tester, 'preface waitlist').center);
        expect(opened, <String>[hello]);
        expect(notes, isEmpty);
        await tap(tester, tester.getCenter(find.byKey(const ValueKey<String>('cm-shortLink')).last));
        expect(opened, <String>[hello, lan]);
        await tap(tester, editorTextRect(tester, 'Trees]]').centerLeft + const Offset(12, 0));
        expect(notes, <String>['Trees'], reason: 'the [[link]] opens its note, once');
        expect(opened, <String>[hello, lan]);
        await away(tester);
      });

      testWidgets('a tap on the words round a link opens nothing, and the index\'s rows still open their pages', (tester) async {
        await show(tester, size: size);
        await tap(tester, editorTextRect(tester, 'Words before the pages').center);
        await tap(tester, editorTextRect(tester, 'Join').center);
        expect(opened, isEmpty);
        expect(notes, isEmpty);
        await press(tester, 'Introduction');
        expect(notes, <String>['Introduction']);
        await away(tester);
      });

      testWidgets('drawn with the base alone (a notebook with no drawing), a [[link]] still opens and an address has nothing to open it', (tester) async {
        await show(tester, size: size, drawn: false);
        await tap(tester, editorTextRect(tester, 'preface waitlist').center);
        expect(opened, isEmpty);
        await tap(tester, editorTextRect(tester, 'Trees]]').centerLeft + const Offset(12, 0));
        expect(notes, <String>['Trees']);
        await away(tester);
      });
    });

    group('pages read straight through, $name', () {
      testWidgets('a short page: a link, a [[link]] and a table\'s link open; its plain words and a drag do not', (tester) async {
        await show(tester, size: size);
        await readThrough(tester);
        expect(tester.widget<MarkdownView>(find.byKey(const ValueKey('book-read-body-0'))).links, isTrue);
        await tap(tester, editorTextRect(tester, 'page waitlist').center);
        expect(opened, <String>[hello]);
        await tap(tester, editorTextRect(tester, 'Plain words of the page').center);
        expect(opened, <String>[hello]);
        expect(notes, isEmpty, reason: 'the words beside a link are only read');
        await tap(tester, editorTextRect(tester, 'Trees]]').centerLeft + const Offset(12, 0));
        expect(notes, <String>['Trees']);
        await tap(tester, cellLink(tester));
        expect(opened, <String>[hello, hello], reason: 'a table\'s link opens, though the page keeps its taps');
        // The page's title still opens the page.
        await tester.tap(button('Open Introduction'));
        await tester.pump();
        expect(notes, <String>['Trees', 'Introduction']);
        await away(tester);
      });

      testWidgets('a long page drawn as the note\'s lines are: a link opens, its plain words do not', (tester) async {
        BookViewState.longPage = 400;
        await show(tester, size: size);
        await readThrough(tester);
        expect(tester.widget(find.byKey(const ValueKey('book-read-body-1'))), isNot(isA<MarkdownView>()), reason: 'the long page is a sliver of the note\'s page');
        await toLongPage(tester);
        await tap(tester, editorTextRect(tester, 'tree waitlist').center);
        expect(opened, <String>[hello]);
        await tap(tester, editorTextRect(tester, 'Paragraph 1 of').center);
        expect(opened, <String>[hello]);
        expect(notes, isEmpty);
        await away(tester);
      });

      testWidgets(size == mac ? 'the wheel over a link scrolls the page and opens nothing' : 'a drag that starts on a link scrolls the page and opens nothing', (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await show(tester, size: size, scroll: scroll);
        await readThrough(tester);
        // A finger drags the page; a Mac's mouse turns its wheel over it.
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        Future<void> move(Offset from) async {
          if (kind == PointerDeviceKind.mouse) {
            await tester.sendEventToBinding(mouse.hover(from));
            await tester.sendEventToBinding(mouse.scroll(const Offset(0, 200)));
          } else {
            await tester.dragFrom(from, const Offset(0, -200), kind: kind);
          }
          await tester.pump();
        }

        await move(editorTextRect(tester, 'page waitlist').center);
        expect(scroll.offset, greaterThan(0), reason: 'the page scrolled');
        expect(opened, isEmpty);
        // And from a link on the long page.
        await toLongPage(tester);
        final was = scroll.offset;
        await move(editorTextRect(tester, 'tree waitlist').center);
        expect(scroll.offset, greaterThan(was));
        expect(opened, isEmpty);
        await away(tester);
      });
    });
  }

  group('the mouse', () {
    testWidgets('is a hand over a link in the notebook\'s words and its pages, short and long, and not over plain words', (tester) async {
      await show(tester, size: mac);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      MouseCursor at() => RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
      Future<void> over(Offset point) async {
        await mouse.moveTo(point);
        await tester.pump();
      }

      await over(editorTextRect(tester, 'preface waitlist').center);
      expect(at(), SystemMouseCursors.click);
      await over(editorTextRect(tester, 'Words before the pages').center);
      expect(at(), isNot(SystemMouseCursors.click));
      await readThrough(tester);
      await over(editorTextRect(tester, 'page waitlist').center);
      expect(at(), SystemMouseCursors.click);
      await over(cellLink(tester));
      expect(at(), SystemMouseCursors.click);
      await over(editorTextRect(tester, 'Plain words of the page').center);
      expect(at(), isNot(SystemMouseCursors.click));
      await toLongPage(tester);
      await over(editorTextRect(tester, 'tree waitlist').center);
      await tester.pump();
      expect(at(), SystemMouseCursors.click);
      await over(editorTextRect(tester, 'Paragraph 1 of').center);
      await tester.pump();
      expect(at(), isNot(SystemMouseCursors.click));
      await away(tester);
    });

    testWidgets('opens nothing with the other button', (tester) async {
      await show(tester, size: mac);
      await tester.tapAt(editorTextRect(tester, 'preface waitlist').center, kind: PointerDeviceKind.mouse, buttons: 2);
      await tester.pump();
      await readThrough(tester);
      await tester.tapAt(editorTextRect(tester, 'page waitlist').center, kind: PointerDeviceKind.mouse, buttons: 2);
      await tester.pump();
      expect(opened, isEmpty);
      await click(tester, editorTextRect(tester, 'page waitlist').center);
      expect(opened, <String>[hello]);
      await away(tester);
    });
  });
}
