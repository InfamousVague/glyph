import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';

import 'package:ghost_md/sheet/css.dart' show CssLines;

import '../../settings/support.dart';
import '../../support/icons.dart';
import '../notion/support.dart' show Held, Measured;

/// Settings › Plugins › Claude and its instructions drawer, held to the web app's own, measured in Chromium at
/// 390 x 844 on 2026-10-08 (fixtures/*.json: each named thing's `getBoundingClientRect`, to a hundredth). The page
/// draws in a browser as it is, with nothing stood in for; every request not to the dev server was refused.
///
/// Pictures: `flutter test --update-goldens test/plugins/claude/reference_test.dart`, then `shots/`.
void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

  /// Settings open on Claude's page, as the app's sheet lists a plugin's: a sub-page of Plugins in its own colour.
  Future<void> pane(WidgetTester tester, {String theme = 'light'}) async {
    final settings = claudePlugin.settings!;
    await pumpSettings(
      tester,
      SettingsScreen(
        open: true,
        onClose: () {},
        goTo: const SettingsTarget('plugin:claude', nonce: 1),
        sections: [
          SettingsSection(id: 'plugins', label: 'Plugins', icon: const AppIcon(Lucide.puzzle, size: 16), group: 2, content: (context) => const SizedBox.shrink()),
          SettingsSection(id: 'plugin:claude', label: claudePlugin.manifest.name, icon: const AppIcon(Lucide.bot, size: 16), group: 2, hue: settings.hue, listed: false, parent: 'plugins', content: settings.pane),
        ],
      ),
      prefs: Preferences(theme: theme),
    );
    await settleSettings(tester);
  }

  Future<void> open(WidgetTester tester, String row, {String? way}) async {
    await tester.tap(find.text(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (way != null) {
      await tester.tap(find.descendant(of: find.byKey(ClaudeGuide.cardKey), matching: find.text(way)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Finder rowCalled(String label) => find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false);
  Finder inRow(String label, Finder what) => find.descendant(of: rowCalled(label), matching: what, skipOffstage: false);
  Finder cardCalled(String title) => find.byWidgetPredicate((w) => w is PaneSection && w.title == title, skipOffstage: false);
  Finder surfaceOf(Finder card) => find.descendant(of: card, matching: find.byType(ClipRRect, skipOffstage: false), skipOffstage: false).first;
  Finder inCard(Finder what) => find.descendant(of: find.byKey(ClaudeGuide.cardKey), matching: what, skipOffstage: false);

  /// The box the page's lines take: the text's own lines are whole pixels, the page's a fraction more (`CssLines`).
  Finder lines(Finder text) => find.ancestor(of: text, matching: find.byType(CssLines, skipOffstage: false)).first;

  group('Settings › Plugins › Claude, against the page', () {
    testWidgets('the hero, the Connect card with its three rows, and the head of what Claude can do', (tester) async {
      final page = Measured('claude', 'pane');
      await pane(tester);
      final t = tokensAt(tester, find.byType(PaneBody));
      final held = Held();
      held.block('the page’s name', rectOf(tester, find.byKey(const ValueKey('settings-display'))), page.rect('display'));
      held.rect('the hero’s card', rectOf(tester, surfaceOf(find.byType(PaneSection).first)), page.rect('cards', 0));
      held.rect('the hero’s glyph chip', rectOf(tester, find.ancestor(of: byLucide(Lucide.bot), matching: find.byType(Container)).first), page.rect('heroGlyph'));
      held.block('the hero’s title', rectOf(tester, find.text('Claude, on your notes')), page.rect('heroTitle'));
      held.block('the hero’s words', rectOf(tester, find.textContaining('Read, add to and change your notes from Claude, on any device')), page.rect('heroMeta'));
      held.block('the title Connect', rectOf(tester, find.text('CONNECT')), page.rect('titles', 0), indent: t.space(2));
      held.block('the introduction of Connect', rectOf(tester, find.textContaining('Two ways in: hosted')), page.rect('descs', 0), indent: t.space(2));
      held.span('the card Connect', rectOf(tester, surfaceOf(cardCalled('Connect'))), page.rect('cards', 1), by: 0.75);
      // The first row to the half pixel; the rows under a hairline to three quarters (see below).
      const rows = ['How to connect', 'Server address', 'On your own computer'];
      final hints = ['The steps, for claude.ai, Claude Desktop and Claude Code.', mcpUrl, 'One file, run with Node. Your key never leaves the machine.'];
      for (final (i, label) in rows.indexed) {
        final by = i == 0 ? 0.5 : 0.75;
        if (i == 0) {
          held.rect('the row $label', rectOf(tester, rowCalled(label)), page.rect('rows', i));
        } else {
          // The page's row is measured with the hairline over it, which here is drawn round the row and not in it.
          final own = rectOf(tester, rowCalled(label));
          held.span('the row $label', Rect.fromLTRB(own.left, own.top - t.len('glacier-hairline'), own.right, own.bottom), page.rect('rows', i), by: 0.75);
        }
        held.block('the label $label', rectOf(tester, inRow(label, find.text(label))), page.rect('labels', i), by: by);
        held.block('the hint of $label', rectOf(tester, inRow(label, find.text(hints[i]))), page.rect('hints', i), by: by);
        held.rect('the glyph of $label', rectOf(tester, inRow(label, find.byType(AppIcon)).first), page.rect('iconGlyphs', i), by: by);
        held.rect('the chip of $label', rectOf(tester, find.ancestor(of: inRow(label, find.byType(AppIcon)).first, matching: find.byType(Container)).first), page.rect('icons', i), by: by);
      }
      held.rect('the word Copy', rectOf(tester, find.byType(RowAction)), page.rect('actions'), by: 0.75);
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      // The plugin's colour on its page: coral, rgb(200, 100, 63), and 16% of it under a glyph.
      final chip = tester.widget<Container>(find.ancestor(of: inRow('How to connect', find.byType(AppIcon)).first, matching: find.byType(Container)).first);
      expect((chip.decoration! as BoxDecoration).color, sameColor(const Color.fromARGB(255, 200, 100, 63).withValues(alpha: 0.16)));
      await endSettings(tester);
    });

    // The settings kit (lib/settings/kit, another piece's) rules a row a half pixel where the page's rule is one,
    // and sets a caption's lines on whole pixels where the page's are 20.09, so a long page drifts from the page's
    // a little at every rule and every caption: 0.8 px at the first row of this card, 1.6 within it, 1.8 at the key's banner
    // (whose nine lines are 0.8 px shorter here) and 2.4 at the footnote, 1,750 px down. What is held below is that
    // every part is there in the page's order and each within that drift; the parts' own sizes are held where the
    // kit sets them (test/settings).
    testWidgets('the rest of the page: nine rows of what Claude can do, the key’s banner and the footnote, in the page’s places to the kit’s drift', (tester) async {
      final page = Measured('claude', 'pane');
      await pane(tester);
      final t = tokensAt(tester, find.byType(PaneBody));
      final held = Held();
      held.block('the title What Claude can do', rectOf(tester, find.text('WHAT CLAUDE CAN DO', skipOffstage: false)), page.rect('titles', 1), indent: t.space(2), by: 1);
      held.block('its introduction', rectOf(tester, find.textContaining('Ask in words. Behind them', skipOffstage: false)), page.rect('descs', 1), indent: t.space(2), by: 1);
      expect(page.count('rows'), 3 + canDo.length);
      for (final (i, tool) in canDo.indexed) {
        expect(page.text('labels', 3 + i), tool.name);
        held.block('the label ${tool.name}', rectOf(tester, inRow(tool.name, find.text(tool.name, skipOffstage: false))), page.rect('labels', 3 + i), by: 2);
        expect(rectOf(tester, rowCalled(tool.name)).height, closeTo(page.rect('rows', 3 + i).height, 1.5), reason: 'the row ${tool.name}');
      }
      held.block('the title Your key', rectOf(tester, find.text('YOUR KEY', skipOffstage: false)), page.rect('titles', 2), indent: t.space(2), by: 2);
      final banner = rectOf(tester, find.byType(SettingsCallout, skipOffstage: false));
      expect([banner.left, banner.width], [closeTo(page.rect('callouts').left, 0.5), closeTo(page.rect('callouts').width, 0.5)]);
      expect(banner.height, closeTo(page.rect('callouts').height, 1.5));
      final key = rectOf(tester, find.byWidgetPredicate((w) => w is AppIcon && w.icon == Lucide.keyRound, skipOffstage: false));
      expect([key.left, key.width, key.height], [closeTo(page.rect('calloutIcons').left, 0.5), 18, 18]);
      final foot = rectOf(tester, find.textContaining('Claude sees the words of the notes it reads', skipOffstage: false));
      expect(foot.left, closeTo(page.rect('footnotes').left + t.space(2), 0.5));
      expect(foot.height, closeTo(page.rect('footnotes').height, 1.5));
      expect(banner.top, closeTo(page.rect('callouts').top, 2));
      expect(foot.top, closeTo(page.rect('footnotes').top, 2.5));
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      await endSettings(tester);
    });
  });

  group('the instructions drawer, against the page', () {
    /// Everything the drawer draws for [guide], against [page].
    void holdGuide(WidgetTester tester, Measured page, Guide guide, Held held) {
      final t = tokensAt(tester, find.byKey(ClaudeGuide.cardKey));
      held.rect('the card', rectOf(tester, find.byKey(ClaudeGuide.cardKey)), page.rect('card'));
      held.rect('the scrim', rectOf(tester, find.byKey(ClaudeGuide.scrimKey)), page.rect('scrim'));
      held.block('the title', rectOf(tester, inCard(find.text('Connecting Claude'))), page.rect('title'));
      held.rect('the close', rectOf(tester, inCard(byLucide(Lucide.x))), page.rect('close'));
      for (final (i, g) in guides(null).indexed) {
        held.rect('the way ${g.label}', rectOf(tester, find.ancestor(of: inCard(find.text(g.label)), matching: find.byType(Container)).first), page.rect('way', i));
      }
      held.rect('the ways’ track', rectOf(tester, find.ancestor(of: inCard(find.text('Hosted')), matching: find.byType(Container)).at(1)), page.rect('ways'));
      held.block('the lead', rectOf(tester, lines(inCard(find.text(guide.lead, skipOffstage: false)))), page.rect('lead'));
      expect(page.count('step'), guide.steps.length);
      var snippet = 0;
      for (final (i, step) in guide.steps.indexed) {
        held.rect('step ${i + 1}', rectOf(tester, find.byKey(ValueKey('claude-step-${step.title}'), skipOffstage: false)), page.rect('step', i).inflateTop(i == 0 ? 0 : t.space(5)));
        held.rect('the number ${i + 1}', rectOf(tester, find.byKey(ValueKey('claude-step-number-${i + 1}'), skipOffstage: false)), page.rect('number', i).inflateTop(t.lenOf('0.05rem')));
        held.block('the title ${step.title}', rectOf(tester, inCard(find.text(step.title, skipOffstage: false))), page.rect('stepTitle', i));
        held.block('the words of ${step.title}', rectOf(tester, lines(inCard(find.text(step.body, skipOffstage: false)))), page.rect('words', i));
        for (final text in step.snippets) {
          final code = find.descendant(of: find.byKey(ValueKey(text), skipOffstage: false), matching: find.byType(Text, skipOffstage: false), skipOffstage: false);
          held.rect('the code ${text.split('\n').first}', rectOf(tester, lines(code)), page.rect('code', snippet).deflateBlock(t.lenOf('0.3rem')));
          held.rect('the block of ${text.split('\n').first}', rectOf(tester, find.ancestor(of: code, matching: find.byType(Container, skipOffstage: false)).first), page.rect('snippet', snippet));
          final copy = find.descendant(of: find.byKey(ValueKey(text), skipOffstage: false), matching: byLucide(Lucide.copy), skipOffstage: false);
          held.rect('the Copy’s icon of ${text.split('\n').first}', rectOf(tester, copy), page.rect('copyIcon', snippet));
          held.rect('the Copy of ${text.split('\n').first}', rectOf(tester, find.ancestor(of: copy, matching: find.byType(Container, skipOffstage: false)).first), page.rect('copy', snippet));
          snippet += 1;
        }
      }
      expect(page.count('snippet'), snippet);
    }

    testWidgets('the hosted way: the card on the bottom edge, its head and segments, four steps and two things to copy', (tester) async {
      final page = Measured('claude', 'guide-hosted');
      await pane(tester);
      await open(tester, 'How to connect');
      final held = Held();
      holdGuide(tester, page, guides(null)[0], held);
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      await endSettings(tester);
    });

    testWidgets('the local way: four steps and five things to copy, the config file on its own lines', (tester) async {
      final page = Measured('claude', 'guide-local');
      await pane(tester);
      await open(tester, 'How to connect', way: 'On your computer');
      final held = Held();
      holdGuide(tester, page, guides(null)[1], held);
      expect(held.off, isEmpty, reason: held.off.join('\n'));
      await endSettings(tester);
    });
  });

  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the page, $theme', (tester) async {
        await pane(tester, theme: theme);
        await shot(tester, 'claude-pane-$theme');
      });

      testWidgets('the foot of the page, $theme', (tester) async {
        await pane(tester, theme: theme);
        await tester.ensureVisible(find.textContaining('Claude sees the words of the notes it reads', skipOffstage: false));
        await tester.pump();
        await shot(tester, 'claude-pane-foot-$theme');
      });

      testWidgets('the drawer on the hosted way, $theme', (tester) async {
        await pane(tester, theme: theme);
        await open(tester, 'How to connect');
        await shot(tester, 'claude-guide-hosted-$theme');
      });

      testWidgets('the drawer on the local way, $theme', (tester) async {
        await pane(tester, theme: theme);
        await open(tester, 'How to connect', way: 'On your computer');
        await shot(tester, 'claude-guide-local-$theme');
      });
    }

    testWidgets('the drawer on a wide window', (tester) async {
      final settings = claudePlugin.settings!;
      await pumpSettings(tester, SingleChildScrollView(child: Builder(builder: settings.pane)), size: wideWindow);
      await open(tester, 'How to connect');
      await shot(tester, 'claude-guide-wide-light');
    });
  });
}

extension on Rect {
  /// The page's box with the margin over it that the port keeps inside its own (a step's gap, a number's nudge).
  Rect inflateTop(double by) => Rect.fromLTRB(left, top - by, right, bottom);

  /// The page's box without its block padding: the words alone.
  Rect deflateBlock(double by) => Rect.fromLTRB(left, top + by, right, bottom - by);
}
