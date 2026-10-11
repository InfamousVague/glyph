import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/ghost.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/back.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// The palette on screen. First `commands/CommandBar.test.tsx`, case for case; then the palette held to the web
/// app's own, measured on its page (test/commands/fixtures/web_palette.json): the same headings and rows for the
/// same words typed, in the same places to half a pixel, on a phone and on a wide window.
void main() {
  setUpAll(loadAppFonts);

  PaletteWorld apples([List<PaletteNote> notes = const [PaletteNote(id: 'a', title: 'Apples')]]) => PaletteWorld(notes: notes);
  final Finder palette = find.byType(EditableText);

  group('the command palette (CommandBar.test.tsx)', () {
    testWidgets('hands its opener out once, whatever its caller passes each render', (tester) async {
      final readies = [0, 0, 0];
      for (var i = 0; i < 3; i += 1) {
        await pumpBar(tester, world: apples(), doing: everyDoing(Calls()), onReady: (_) => readies[i] += 1);
        await tester.pump();
      }
      expect(readies, [1, 0, 0]);
      await away(tester);
    });

    testWidgets('opens from the opener it handed out, and closes on the back gesture', (tester) async {
      final stack = BackStack();
      VoidCallback open = () {};
      await pumpBar(tester, world: apples(), doing: everyDoing(Calls()), stack: stack, onReady: (opener) => open = opener);
      expect(palette, findsNothing);
      open();
      await settle(tester);
      expect(palette, findsOneWidget);
      expect(lines(tester).map((line) => line.text), contains('Open Apples'));
      // The phone's gesture, as the system asks it of the app (core/back.dart): the palette takes it.
      final took = stack.goBack();
      await settle(tester);
      expect(took, isTrue);
      expect(palette, findsNothing);
      expect(stack.depth, 0);
      await away(tester);
    });

    testWidgets('finds a note by name past the forty newest once something is typed, and opens empty again', (tester) async {
      // Forty-five newer notes on top, as adding Ghost.md: The Guide leaves a library.
      final notes = [for (var i = 0; i < 45; i += 1) PaletteNote(id: 'g$i', title: 'Chapter $i'), const PaletteNote(id: 'mine', title: 'Groceries')];
      final stack = BackStack();
      final bar = await pumpBar(tester, world: apples(notes), doing: everyDoing(Calls()), stack: stack);
      bar.show();
      await settle(tester);
      expect(lines(tester).map((line) => line.text), isNot(contains('Open Groceries')));
      await type(tester, 'groc');
      expect(lines(tester).map((line) => line.text), contains('Open Groceries'));
      stack.goBack();
      await settle(tester);
      bar.show();
      await settle(tester);
      expect(tester.widget<EditableText>(palette).controller.text, '');
      expect(lines(tester).map((line) => line.text), isNot(contains('Open Groceries')));
      await away(tester);
    });
  });

  group('the keys and the presses', () {
    testWidgets('Ctrl+K opens it, Enter runs the first row and closes it, and it opens empty the next time', (tester) async {
      final calls = Calls();
      final bar = await pumpBar(tester, world: seededWorld('dark'), doing: everyDoing(calls));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
      expect(bar.isOpen, isTrue);
      await type(tester, 'groc');
      expect(lines(tester).where((line) => line.kind == 'row').map((line) => line.text), ['Open Groceries']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(calls.said, ['openNote groceries']);
      expect(bar.isOpen, isFalse);
      // The chord again: nothing of the last search is left.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);
      expect(bar.isOpen, isTrue);
      expect(bar.query, '');
      expect(tester.widget<EditableText>(palette).controller.text, '');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(bar.isOpen, isFalse);
      expect(calls.said, ['openNote groceries']);
      await away(tester);
    });

    testWidgets('a row pressed runs its command, and a press on the scrim closes it and runs nothing', (tester) async {
      final calls = Calls();
      final bar = await pumpBar(tester, world: seededWorld('dark'), doing: everyDoing(calls));
      bar.show();
      await settle(tester);
      await tester.tap(find.text('Show Work'));
      await settle(tester);
      expect(calls.said, ['chooseWorkspace work']);
      expect(bar.isOpen, isFalse);
      bar.show();
      await settle(tester);
      await tester.tapAt(const Offset(195, 800));
      await settle(tester);
      expect(bar.isOpen, isFalse);
      expect(calls.said, ['chooseWorkspace work']);
      await away(tester);
    });

    testWidgets('every row of the seeded home page runs the doing its words name', (tester) async {
      final calls = Calls();
      final world = seededWorld('dark');
      final commands = paletteCommands(world, everyDoing(calls));
      for (final command in commands) {
        command.run();
      }
      expect(calls.said.take(8), ['newNote', 'newNotebook', 'newJournal', 'speak', 'showList', 'browseNotes', 'chooseWorkspace work', 'chooseWorkspace home']);
      expect(calls.said.skip(calls.said.length - 11), [
        'setTheme system', 'setTheme light', 'setTheme dawn', 'setTheme boreal', 'setTheme ember', //
        'settings', 'notifications', 'organizations', 'cheatSheet', 'academy', 'guide',
      ]);
    });
  });

  group('the words', () {
    testWidgets('are the web app’s: the field, the hints, and nothing found', (tester) async {
      final bar = await pumpBar(tester, world: seededWorld('dark'), doing: everyDoing(Calls()));
      bar.show();
      await settle(tester);
      expect(tester.widget<GlacierSearchField>(find.byType(GlacierSearchField)).placeholder, web['phone-dark-empty']['placeholder']);
      expect(find.text('↑↓ to navigate · ↵ to run · esc to close'), findsOneWidget);
      await type(tester, 'zzzqq');
      expect(hasList, isFalse);
      expect(find.text('Nothing by that name.'), findsOneWidget);
      expect(find.byType(Ghost), findsOneWidget);
      expect(tester.widget<Ghost>(find.byType(Ghost)).scene, GhostScene.searchNothing);
      await away(tester);
    });

    testWidgets('a key hint is set as the app’s stylesheet sets a kbd: the mono face’s ligatures, no tracking', (tester) async {
      final bar = await pumpBar(tester, world: seededWorld('dark'), doing: everyDoing(Calls()));
      bar.show();
      await settle(tester);
      final cap = tester.widget<RichText>(find.descendant(of: find.byType(GlacierKbd), matching: find.byType(RichText)));
      expect(cap.text.toPlainText(), '⌘N');
      expect(cap.text.style!.fontFeatures, const [FontFeature('calt'), FontFeature('liga')]);
      expect(cap.text.style!.letterSpacing, 0);
      expect(cap.text.style!.fontFamily, 'Maple Mono');
      // 0.8em of the row's text, as the page computed it (10.7159px).
      expect(cap.text.style!.fontSize, closeTo(10.7159, 0.01));
      await away(tester);
    });
  });

  // The web app's own lists and rectangles. A light page offers Dark where a dark one offers Light; nothing else
  // of the list turns on the theme.
  for (final (name, size) in [('phone', const Size(390, 844)), ('wide', const Size(1280, 800))]) {
    group('held to the web app’s palette at ${size.width.round()} x ${size.height.round()}', () {
      for (final (query, key) in [('', 'empty'), ('Weekend trip', 'Weekend trip'), ('set', 'set'), ('theme', 'theme'), ('Work', 'Work'), ('groc', 'groc'), ('new', 'new')]) {
        for (final theme in ['dark', if (query.isEmpty || query == 'theme') 'light']) {
          testWidgets('"$query" in $theme: the same headings and rows, where the page drew them', (tester) async {
            final page = web['$name-$theme-$key'] as Map<String, dynamic>;
            final bar = await pumpBar(tester, size: size, theme: theme, world: seededWorld(theme), doing: everyDoing(Calls()));
            bar.show();
            await settle(tester);
            if (query.isNotEmpty) await type(tester, query);

            final drawn = await allLines(tester);
            final rows = (page['rows'] as List).cast<Map<String, dynamic>>();
            expect([for (final line in drawn) '${line.kind} ${line.text}'], [for (final row in rows) '${row['kind']} ${row['text']}']);
            expect([for (final line in drawn) if (line.selected) line.text], [for (final row in rows) if (row['selected'] == true) row['text']]);

            expectRect(panelRect(tester), page['panel'] as List, 'the panel');
            expectRect(fieldRect(tester), page['field'] as List, 'the field');
            expectRect(listRect(tester), page['list'] as List, 'the list');
            expectRect(footerRect(tester), page['footer'] as List, 'the footer');
            for (var i = 0; i < rows.length; i += 1) {
              // Three quarters of a pixel down the list: the page snaps each row to a 64th of a pixel and this does
              // not, which by the fortieth row of the wide window's list has come to half a pixel exactly.
              expectRect(drawn[i].rect, rows[i]['rect'] as List, '${rows[i]['kind']} "${rows[i]['text']}"', by: 0.75);
            }
            if (page['kbd'] != null) expectRect(tester.getRect(find.byType(GlacierKbd)), page['kbd'] as List, 'the key hint');
            await away(tester);
          });
        }
      }

      testWidgets('nothing found: the panel and the field where the page drew them, and the ghost held inside the panel', (tester) async {
        final page = web['$name-dark-zzzqq'] as Map<String, dynamic>;
        final bar = await pumpBar(tester, size: size, world: seededWorld('dark'), doing: everyDoing(Calls()));
        bar.show();
        await settle(tester);
        await type(tester, 'zzzqq');
        expect(tester.takeException(), isNull);
        // The panel is as tall as it may be, as the page's is, less a pixel or two: the ghost's room is worked out
        // from whole lines of text.
        final panel = panelRect(tester);
        final pagePanel = rectOf(page['panel'] as List);
        expect(panel.top, closeTo(pagePanel.top, 0.5));
        expect(panel.left, closeTo(pagePanel.left, 0.5));
        expect(panel.width, closeTo(pagePanel.width, 0.5));
        expect(panel.height, inInclusiveRange(pagePanel.height - 3, pagePanel.height + 0.01));
        expectRect(fieldRect(tester), page['field'] as List, 'the field');
        // The page's ghost is 40% of the window tall and its words and hints fall below the panel's edge (its
        // footer's bottom is past the panel's). Here everything is inside.
        final pageGhost = rectOf(page['ghost'] as List);
        final pageFooter = rectOf(page['footer'] as List);
        expect(pageGhost.height, closeTo(size.height * 0.4, 0.5));
        expect(pageFooter.bottom, greaterThan(rectOf(page['panel'] as List).bottom));
        final ghost = tester.getRect(find.byType(Image));
        final words = tester.getRect(find.text('Nothing by that name.'));
        final footer = footerRect(tester);
        expect(ghost.height, lessThan(pageGhost.height));
        expect(ghost.width / ghost.height, closeTo(594 / 1024, 0.01));
        expect(ghost.center.dx, closeTo(pageGhost.center.dx, 0.5));
        expect(ghost.top, closeTo(pageGhost.top, 0.5));
        expect(words.top, greaterThan(ghost.bottom));
        expect(footer.top, greaterThan(words.bottom));
        expect(footer.bottom, lessThanOrEqualTo(panel.bottom));
        await away(tester);
      });
    });
  }

  group('pictures', () {
    for (final theme in ['dark', 'light']) {
      testWidgets('the palette on a phone, $theme: opened, a workspace typed, nothing found', (tester) async {
        final bar = await pumpBar(tester, theme: theme, world: seededWorld(theme), doing: everyDoing(Calls()), under: const _Page());
        bar.show();
        await settle(tester);
        await _picture(tester, 'palette-phone-$theme-empty');
        await type(tester, 'Work');
        await _picture(tester, 'palette-phone-$theme-work');
        await type(tester, 'zzzqq');
        await _picture(tester, 'palette-phone-$theme-nothing');
        await away(tester);
      });

      testWidgets('the palette on a wide window, $theme', (tester) async {
        final bar = await pumpBar(tester, size: const Size(1280, 800), theme: theme, world: seededWorld(theme), doing: everyDoing(Calls()), under: const _Page());
        bar.show();
        await settle(tester);
        await _picture(tester, 'palette-wide-$theme-empty');
        await type(tester, 'Work');
        await _picture(tester, 'palette-wide-$theme-work');
        await type(tester, 'zzzqq');
        await _picture(tester, 'palette-wide-$theme-nothing');
        await away(tester);
      });
    }
  });
}

Future<void> _picture(WidgetTester tester, String name) => expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));

/// Something under the scrim to see it by: the page's paper with a few lines of ink.
class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('app-paper'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(6), 96, t.space(6), 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (words, size) in [('Weekend trip', 28.0), ('Fix the sign-in loop', 20.0), ('Monday standup', 20.0), ('Flat', 20.0), ('Reading list', 20.0), ('Groceries', 20.0)])
              Padding(
                padding: EdgeInsets.only(bottom: t.space(8)),
                child: Text(words, style: t.textAt(size, weight: 'semibold', color: t.color('app-ink'))),
              ),
          ],
        ),
      ),
    );
  }
}
