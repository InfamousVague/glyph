// editor/links.test.ts and editor/linkCards.test.ts, case for case. Not ported: "reading the tasks on a board" (two
// cases), which is editor/markReads.ts and the boards, stages 9 and 5.
import 'package:flutter/gestures.dart' show PointerDeviceKind, PointerDownEvent;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_preview.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/media/link_cards.dart';
import 'package:ghost_md/editor/media/links.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'link_cards_reference_test.dart' show Known;
import 'support.dart';

const String url = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d5e6f';
const Key pill = ValueKey<String>('cm-itemMark'), short = ValueKey<String>('cm-shortLink'), pillName = ValueKey<String>('cm-itemMark-name');

List<String> said(WidgetTester tester, Key key) => tester.widgetList<InlineWords>(find.byKey(key)).map((w) => w.text).toList();

void main() {
  setUpAll(loadAppFonts);

  group('item marks in the editor', () {
    testWidgets('draws the mark at the end of an item as one pill with the name on it', (tester) async {
      await pumpNote(tester, '- [ ] Buy milk [notion]($url)\nplain\n', more: <Extension>[shortLinks()]);
      expect(said(tester, pillName), <String>['Notion']);
      // The mark's own address is inside the pill, not shortened beside it.
      expect(find.byKey(short), findsNothing);
    });

    testWidgets('leaves an ordinary link alone: its address is shortened, the words stay', (tester) async {
      await pumpNote(tester, '- [ ] read [the board]($url)\n', more: <Extension>[shortLinks()]);
      expect(find.byKey(pill), findsNothing);
      expect(find.byKey(short), findsOneWidget);
    });

    testWidgets('is still the mark with a board’s anchor after it', (tester) async {
      await pumpNote(tester, '- [ ] Buy milk [notion]($url) ^buy-milk\n', more: <Extension>[shortLinks()]);
      expect(said(tester, pillName), <String>['Notion']);
    });

    testWidgets('is still the mark with a counter after it', (tester) async {
      await pumpNote(tester, '- [ ] Pack socks [notion]($url) [3/8] ^pack-socks\n', more: <Extension>[shortLinks()]);
      expect(said(tester, pillName), <String>['Notion']);
    });

    testWidgets('is not a mark when something follows it on the line, or the line is not an item', (tester) async {
      await pumpNote(tester, '- [ ] Buy milk [notion]($url) today\nSee [notion]($url)\n', more: <Extension>[shortLinks()]);
      expect(find.byKey(pill), findsNothing);
    });

    testWidgets('draws nothing for a mark whose plugin reads it: the row under the line carries it', (tester) async {
      await pumpNote(tester, '- [ ] Buy milk [notion]($url)\n', more: <Extension>[shortLinks(), markRead.of((name) => name == 'notion')]);
      expect(find.byKey(pill), findsNothing);
      expect(find.byKey(const ValueKey<String>('cm-itemMarkHidden')), findsOneWidget);
    });

    testWidgets('writes the mark and the address out in full on the caret’s line', (tester) async {
      final view = await pumpNote(tester, '- [ ] Buy milk [notion]($url)\nsee https://example.com/a/long/path/here\n', more: <Extension>[shortLinks()], caret: 3);
      expect(find.byKey(pill), findsNothing);
      expect(find.byKey(short), findsOneWidget);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length - 2)));
      await tester.pump();
      expect(find.byKey(pill), findsOneWidget);
      expect(find.byKey(short), findsNothing);
    });
  });

  group('an address under a look that hides its words', () {
    testWidgets('stays as it is, under the bar, where one outside it is shortened beside its words', (tester) async {
      // The short address is a widget, which sits beside a mark's span rather than in it, so under a redaction's
      // bar it showed in plain ink between two pieces of bar. The looks that hide their words are named through
      // `coveringLooks`, and an address under one is left whole.
      const bar = InlineFormat('Bar', '@@');
      const doc = '@@see [the plan](https://example.com/the/plan)@@ and [the rest](https://example.org/the/rest)';
      Future<void> draw(List<Extension> more) async {
        final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(formats: const <InlineFormatSyntax>[bar], more: more)));
        addTearDown(view.destroy);
        await pumpApp(tester, home: SingleChildScrollView(child: EditorColumn(view: view)));
        debugDisableShadows = true;
        await tester.pump();
      }

      await draw(<Extension>[shortLinks(), coveringLooks.of('Bar')]);
      expect(said(tester, short), <String>['example.org/the/rest']);
      expect(shownOf(tester, 0), contains('(https://example.com/the/plan)'));
      // With no look that hides its words, every address is shortened, as before.
      await tester.pumpWidget(const SizedBox.shrink());
      await draw(<Extension>[shortLinks()]);
      expect(find.byKey(short), findsNWidgets(2));
    });
  });

  group('a tap on an address (added here: the page opens no link from the words)', () {
    testWidgets('is handed to the caller, in a view that cannot be edited and in one that can, but not with the caret in it', (tester) async {
      final opened = <String>[];
      const doc = 'see https://example.com/a/long/path/here now';
      bool press(EditorView view, int pos) => view.eventHandlers.any((h) => h.mouseDown?.call(PointerDownEvent(position: view.coordsAtPos(pos)!.center, kind: PointerDeviceKind.touch), view) ?? false);
      var view = await pumpNote(tester, doc, more: <Extension>[shortLinks(onOpen: opened.add)], readOnly: true);
      expect(press(view, 1), isFalse);
      expect(press(view, 10), isTrue);
      expect(opened, <String>['https://example.com/a/long/path/here']);
      view = await pumpNote(tester, doc, more: <Extension>[shortLinks(onOpen: opened.add)]);
      expect(press(view, 10), isTrue);
      expect(opened, hasLength(2));
      // The caret elsewhere on its line, in a note that has the keyboard: the address is written out, and opens.
      view = await pumpNote(tester, doc, more: <Extension>[shortLinks(onOpen: opened.add)], caret: 1);
      expect(press(view, 10), isTrue);
      expect(opened, hasLength(3));
      // The caret in the address: it is being edited, and a press is the caret's.
      view = await pumpNote(tester, doc, more: <Extension>[shortLinks(onOpen: opened.add)], caret: 20);
      expect(press(view, 10), isFalse);
      expect(opened, hasLength(3));
    });
  });

  // ---- editor/linkCards.test.ts ----

  // As the Notion and GitHub plugins do when they are on: they read their own links, which have their own rows.
  bool reads(String text, String url) => url.contains('notion.so') || url.contains('github.com');

  group('link preview cards', () {
    test('are for a line that is only a link, bare, bracketed or named, in a list or not', () {
      expect(linkLine('https://www.airbnb.com/rooms/1234'), const LinkLine('https://www.airbnb.com/rooms/1234', null));
      expect(linkLine('  <https://example.com/a>  ')?.url, 'https://example.com/a');
      expect(linkLine('- [The cabin](https://airbnb.com/rooms/1)'), const LinkLine('https://airbnb.com/rooms/1', 'The cabin'));
      expect(linkLine('- [ ] https://example.com/read-this.')?.url, 'https://example.com/read-this');
      expect(linkLine('1. https://example.com')?.url, 'https://example.com');
    });

    test('are not for a link among words, a picture, another scheme, or a link a plugin reads', () {
      expect(linkLine('see https://example.com for more', reads: reads), isNull);
      expect(linkLine('![a cassette](https://example.com/tape.jpg)', reads: reads), isNull);
      expect(linkLine('ftp://example.com/file', reads: reads), isNull);
      expect(linkLine('- [ ] Buy milk [notion](https://www.notion.so/abc123)', reads: reads), isNull);
      expect(linkLine('https://www.notion.so/Some-page-0123456789abcdef0123456789abcdef', reads: reads), isNull);
      expect(linkLine('- [Fix it](https://github.com/o/r/issues/4)', reads: reads), isNull);
    });
  });

  group('link cards drawn in a note', () {
    const cabin = 'https://www.airbnb.com/rooms/1234';
    final doc = <String>['The trip', cabin, '```', 'https://example.com/in-code', '```', 'see $cabin for more'].join('\n');
    const card = ValueKey<String>('cm-linkCard'), title = ValueKey<String>('cm-linkCard-title'), about = ValueKey<String>('cm-linkCard-about'), where = ValueKey<String>('cm-linkCard-where');

    testWidgets('draws a card under a line that is only a link, and none for a link in code or among words', (tester) async {
      final known = Known()..known.clear();
      await pumpNote(tester, doc, more: <Extension>[linkCards(previewer: known)]);
      expect(find.byKey(card), findsOneWidget);
      // Until the page's title is known, the card says the site and where on it.
      expect(said(tester, title), <String>['airbnb.com']);
      expect(said(tester, where), <String>['airbnb.com/rooms/1234']);
      expect(shownOf(tester, 1), contains(cabin));
      // Asked for, since it is drawn.
      expect(known.wanted, <String>[cabin]);
    });

    testWidgets('says the page’s title and what it is about once they arrive', (tester) async {
      final known = Known()..known.clear();
      await pumpNote(tester, doc, more: <Extension>[linkCards(previewer: known)]);
      known.arrive(const LinkPreview(url: cabin, title: 'The cabin by the lake', site: 'Airbnb', description: 'Sleeps four.'));
      await tester.pump();
      await tester.pump();
      expect(said(tester, title), <String>['The cabin by the lake']);
      expect(said(tester, about), <String>['Sleeps four.']);
      expect(find.bySemanticsLabel('Open The cabin by the lake'), findsOneWidget);
    });

    testWidgets('opens the page on a tap', (tester) async {
      final opened = <String>[];
      await pumpNote(tester, doc, more: <Extension>[linkCards(open: (url) async => opened.add(url))]);
      await tester.tap(find.byKey(card));
      await tester.pump();
      expect(opened, <String>[cabin]);
    });

    testWidgets('draws none with link previews off, and draws them again when they are turned back on', (tester) async {
      final on = ValueNotifier<bool>(false);
      await pumpNote(tester, doc, more: <Extension>[linkCards(enabled: () => on.value, switches: on)]);
      expect(find.byKey(card), findsNothing);
      on.value = true;
      await tester.pump();
      await tester.pump();
      expect(find.byKey(card), findsOneWidget);
    });
  });
}
