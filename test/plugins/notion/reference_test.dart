import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../../settings/support.dart';
import 'support.dart';

/// Notion's page in Settings and its picker on a note's cog, held to the web app's own, measured in Chromium at
/// 390 x 844 on 2026-10-08 (fixtures/*.json: each named thing's `getBoundingClientRect`, to a hundredth).
///
/// How the page was drawn: the web app on its dev server, Settings › Plugins › Notion and a note's More › Notion
/// board. Notion's page only draws inside the app (`isTauri()`), so the page's own `plugins/notion/client.ts` was
/// answered with three lines changed in transit - "this is the app", an account the script set, the boards the
/// script set - and `index.tsx` with its browser refusal off. Nothing left the machine: every request not to the
/// dev server was refused. The same account and boards are recorded here for the real client.
///
/// Pictures: `flutter test --update-goldens test/plugins/notion/reference_test.dart`, then `shots/`.
final Map<String, Object?> _boards = {
  'results': [
    database('b1', 'Roadmap', properties: const {'Task': {'type': 'title'}}),
    database('b2', 'Home'),
  ],
};

void main() {
  setUpAll(loadAppFonts);
  late Phone phone;

  setUp(() {
    phone = Phone()..use();
    phone.answer = (request) async => json(200, _boards);
  });
  tearDown(() {
    resetNotionDetails();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  /// Settings open on Notion's page, as the app's sheet lists a plugin's: a sub-page of Plugins in its own colour.
  Future<void> pane(WidgetTester tester, {String theme = 'light'}) async {
    final settings = notionPlugin.settings!;
    await pumpSettings(
      tester,
      SettingsScreen(
        open: true,
        onClose: () {},
        goTo: const SettingsTarget('plugin:notion', nonce: 1),
        sections: [
          SettingsSection(id: 'plugins', label: 'Plugins', icon: const AppIcon(Lucide.puzzle, size: 16), group: 2, content: (context) => const SizedBox.shrink()),
          SettingsSection(id: 'plugin:notion', label: notionPlugin.manifest.name, icon: const AppIcon(Lucide.squareKanban, size: 16), group: 2, hue: settings.hue, listed: false, parent: 'plugins', content: settings.pane),
        ],
      ),
      prefs: Preferences(theme: theme),
    );
    await settleSettings(tester);
  }

  /// The picker where the page's sheet had it: its title's corner, and the sheet's width inside its gutters.
  Future<void> picker(WidgetTester tester, Measured page, {String theme = 'light'}) async {
    final sheet = page.rect('sheet');
    final title = page.rect('title');
    await pumpSettings(
      tester,
      Builder(
        builder: (context) {
          final t = context.tokens;
          return Stack(
            children: [
              // The sheet's own ground under it, for the picture: `--sheet-ground: var(--app-paper-2)`.
              Positioned.fromRect(rect: sheet, child: DecoratedBox(decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('xl'))))),
              Positioned(left: title.left, top: title.top, width: title.width, child: BoardPicker(noteId: 'n1', onDone: () {})),
            ],
          );
        },
      ),
      prefs: Preferences(theme: theme),
    );
    await settleSettings(tester);
  }

  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Finder rowCalled(String label) => find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false);
  Finder inRow(String label, Finder what) => find.descendant(of: rowCalled(label), matching: what, skipOffstage: false);
  Finder cardCalled(String title) => find.byWidgetPredicate((w) => w is PaneSection && w.title == title, skipOffstage: false);
  Finder surfaceOf(Finder card) => find.descendant(of: card, matching: find.byType(ClipRRect, skipOffstage: false), skipOffstage: false).first;

  /// The parts every state of the page has, against [page].
  ///
  /// [after] names the rows that come after a hairline, which with everything below them are held to three quarters
  /// of a pixel, not a half: the settings kit (lib/settings/kit, another piece's) rules a row a half pixel where the
  /// page's rule is one, and sets a three-line caption on whole pixels where the page's lines are 20.09.
  void holdPane(WidgetTester tester, Measured page, Held held, {required List<String> rows, required List<String> hints, required List<String> actions, Set<String> after = const {}}) {
    final low = after.isEmpty ? 0.5 : 0.75;
    final t = tokensAt(tester, find.byType(PaneBody));
    held.block('the page’s name', rectOf(tester, find.byKey(const ValueKey('settings-display'))), page.rect('display'));
    final titles = ['Account', 'Boards'].sublist(0, page.count('titles'));
    for (final (i, title) in titles.indexed) {
      // `.setk__title { padding-inline: var(--glacier-space-2) }`: the words start that far into the box measured.
      held.block('the title $title', rectOf(tester, find.text(title.toUpperCase())), page.rect('titles', i), indent: t.space(2));
      held.block('the introduction of $title', rectOf(tester, find.textContaining(page.text('descs', i).substring(0, 20))), page.rect('descs', i), indent: t.space(2));
      held.rect('the card $title', rectOf(tester, surfaceOf(cardCalled(title))), page.rect('cards', i));
    }
    for (final (i, label) in rows.indexed) {
      final by = after.contains(label) ? 0.75 : 0.5;
      if (after.contains(label)) {
        // The page's row is measured with the hairline over it, which here is drawn round the row and not in it.
        final own = rectOf(tester, rowCalled(label));
        held.span('the row $label', Rect.fromLTRB(own.left, own.top - t.len('glacier-hairline'), own.right, own.bottom), page.rect('rows', i), by: 0.75);
      } else {
        held.rect('the row $label', rectOf(tester, rowCalled(label)), page.rect('rows', i));
      }
      held.block('the label $label', rectOf(tester, inRow(label, find.text(label))), page.rect('labels', i), by: by);
      held.block('the hint of $label', rectOf(tester, inRow(label, find.text(hints[i]))), page.rect('hints', i), by: by);
    }
    for (final (i, word) in actions.indexed) {
      held.rect('the word $word', rectOf(tester, find.ancestor(of: find.text(word), matching: find.byType(RowAction))), page.rect('actions', i));
    }
    held.block('the footnote', rectOf(tester, find.textContaining('Signing in goes through')), page.rect('footnotes'), indent: t.space(2), by: low);
  }

  group('Settings › Plugins › Notion, against the page', () {
    testWidgets('signed out: the Account card, its row and its word, and the footnote', (tester) async {
      final page = Measured('notion', 'pane-signed-out');
      await pane(tester);
      final held = Held();
      expect(page.text('labels'), 'Not signed in');
      holdPane(
        tester,
        page,
        held,
        rows: ['Not signed in'],
        hints: ['Notion opens in your browser and asks which pages and boards Ghost.md may use.'],
        actions: ['Sign in'],
      );
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      expect(find.text('BOARDS'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('signed in: both cards, the boards’ rows with their chips, and the words', (tester) async {
      final page = Measured('notion', 'pane-signed-in');
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
      await pane(tester);
      final held = Held();
      holdPane(
        tester,
        page,
        held,
        rows: ['Signed in to Studio', 'Roadmap', 'Home'],
        hints: ['To give Ghost.md more boards, sign in again and pick them.', 'Tasks are named by “Task”.', 'Tasks are named by “Name”.'],
        actions: ['Sign out'],
        after: {'Home'},
      );
      for (final (i, label) in ['Roadmap', 'Home'].indexed) {
        final by = label == 'Home' ? 0.75 : 0.5;
        held.rect('the glyph of $label', rectOf(tester, inRow(label, find.byType(AppIcon))), page.rect('iconGlyphs', i), by: by);
        held.rect('the chip of $label', rectOf(tester, find.ancestor(of: inRow(label, find.byType(AppIcon)), matching: find.byType(Container)).first), page.rect('icons', i), by: by);
      }
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      // The plugin's colour on its page: orange since 2026-10-24 (the page's graphite), rgb(217, 96, 13), and 16% of it
      // under a glyph.
      final chip = tester.widget<Container>(find.ancestor(of: inRow('Roadmap', find.byType(AppIcon)), matching: find.byType(Container)).first);
      expect((chip.decoration! as BoxDecoration).color, sameColor(const Color.fromARGB(255, 217, 96, 13).withValues(alpha: 0.16)));
      await endSettings(tester);
    });
  });

  group('the board picker, against the page', () {
    Finder sheetRow(String label) => find.ancestor(of: find.text(label), matching: find.byType(SheetRow));

    testWidgets('signed out: the title, the sentence, and the one row with Notion’s mark', (tester) async {
      final page = Measured('notion', 'picker-signed-out');
      await picker(tester, page);
      final held = Held();
      held.rect('the title', rectOf(tester, find.byType(SheetTitle)), page.rect('title'));
      held.block('the sentence', rectOf(tester, find.textContaining('Notion opens in your browser')), page.rect('notes'));
      held.rect('the group', rectOf(tester, find.byType(SheetGroup)), page.rect('groups'));
      held.rect('the row', rectOf(tester, sheetRow('Sign in with Notion')), page.rect('rows'));
      held.rect('the ring', rectOf(tester, find.byType(SheetIcon)), page.rect('icons'));
      held.rect('the mark', rectOf(tester, find.byType(NotionMark)), page.rect('iconGlyphs'));
      held.block('the label', rectOf(tester, find.text('Sign in with Notion')), page.rect('labels'));
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      await endSettings(tester);
    });

    testWidgets('signed in with a board linked: the boards, the tick, and the way off Notion', (tester) async {
      final page = Measured('notion', 'picker-signed-in');
      phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
      linkBoard('n1', const Board(id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task'));
      await picker(tester, page);
      final held = Held();
      held.rect('the title', rectOf(tester, find.byType(SheetTitle)), page.rect('title'));
      held.block('the sentence', rectOf(tester, find.text('Boards in Studio that Ghost.md can see.')), page.rect('notes'));
      for (final (i, group) in tester.widgetList<SheetGroup>(find.byType(SheetGroup)).indexed) {
        held.rect('group $i', rectOf(tester, find.byWidget(group)), page.rect('groups', i));
      }
      for (final (i, label) in ['Roadmap', 'Home', 'Don’t send this note to Notion'].indexed) {
        held.rect('the row $label', rectOf(tester, sheetRow(label)), page.rect('rows', i));
        held.block('the label $label', rectOf(tester, find.text(label)), page.rect('labels', i));
      }
      for (final (i, label) in ['Roadmap', 'Home'].indexed) {
        held.rect('the ring of $label', rectOf(tester, find.descendant(of: sheetRow(label), matching: find.byType(SheetIcon))), page.rect('icons', i));
        held.rect('the mark of $label', rectOf(tester, find.descendant(of: sheetRow(label), matching: find.byType(NotionMark))), page.rect('iconGlyphs', i));
      }
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      expect(page.count('ticks'), 1);
      expect(tester.widget<SheetRow>(sheetRow('Roadmap')).chosen, isTrue);
      await endSettings(tester);
    });
  });

  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the page signed out, $theme', (tester) async {
        await pane(tester, theme: theme);
        await shot(tester, 'notion-pane-signed-out-$theme');
      });

      testWidgets('the page signed in, $theme', (tester) async {
        phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
        await pane(tester, theme: theme);
        await shot(tester, 'notion-pane-signed-in-$theme');
      });

      testWidgets('the picker signed out, $theme', (tester) async {
        await picker(tester, Measured('notion', 'picker-signed-out'), theme: theme);
        await shot(tester, 'notion-picker-signed-out-$theme');
      });

      testWidgets('the picker signed in, $theme', (tester) async {
        phone.secrets.held[accountSecret] = accountJson(workspace: 'Studio');
        linkBoard('n1', const Board(id: 'b1', url: 'https://notion.so/b1', title: 'Roadmap', titleProperty: 'Task'));
        await picker(tester, Measured('notion', 'picker-signed-in'), theme: theme);
        await shot(tester, 'notion-picker-signed-in-$theme');
      });
    }
  });
}
