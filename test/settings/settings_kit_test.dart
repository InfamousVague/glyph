import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The settings vocabulary the panes speak in: the web app's src/app/settings/kit/settingsKit.test.tsx on the
/// Flutter port, and each part's sizes held to the tokens and to what the web page measured for the same part
/// (Settings › Appearance at 390 x 844 on the light page, 2026-10-07): a row that is disabled is out of reach of the
/// keyboard too, a row that is pressed is one button, and the hero that opens the developer tools is pressable
/// without looking like a button.

/// [children] as a section's page, in Appearance's colour, on a phone: inside `.settingsScreen__pane`.
Future<void> _pane(WidgetTester tester, List<Widget> children, {String id = 'theme', bool settle = true}) => pumpSettings(
      tester,
      SettingsScreen(
        open: true,
        onClose: () {},
        sections: [SettingsSection(id: id, label: 'Kit', icon: const SizedBox.shrink(), group: 0, content: (context) => PaneBody(children: children))],
        goTo: SettingsTarget(id, nonce: 1),
      ),
      settle: settle,
    );

/// [child] on the page, outside any pane.
Future<void> _bare(WidgetTester tester, Widget child) => pumpSettings(tester, Align(alignment: Alignment.topLeft, child: SizedBox(width: 345.38, child: child)));

Tokens _t(WidgetTester tester) => tokensAt(tester, find.byType(PaneBody).evaluate().isEmpty ? find.byType(Align) : find.byType(PaneBody));
TextStyle _style(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

void main() {
  setUpAll(loadAppFonts);

  group('SettingRow', () {
    testWidgets('seats its control at the end, or across the row under its words', (tester) async {
      const end = ValueKey('end'), wide = ValueKey('wide');
      await _pane(tester, [
        const PaneSection(children: [
          SettingRow(label: 'Haptics', hint: Text('A small tap.'), control: SizedBox(key: end, width: 44, height: 26)),
          SettingRow(label: 'Text size', layout: SettingRowLayout.stacked, control: SizedBox(key: wide, height: 38)),
        ]),
      ]);
      final t = _t(tester);
      final row = tester.getRect(find.widgetWithText(SettingRow, 'Haptics'));
      // The card's whole width in the page's gutter, and the control at the row's end inside its padding, centred.
      expect(row.left, closeTo(22.31, 0.1));
      expect(row.width, closeTo(345.38, 0.1));
      final control = tester.getRect(find.byKey(end));
      expect(control.right, closeTo(row.right - t.space(3), 0.01));
      expect(control.center.dy, closeTo(row.center.dy, 0.01));
      // Under its words, a `--glacier-space-3` below them, and as wide as the row's inside.
      final stacked = tester.getRect(find.byKey(wide));
      expect(stacked.width, closeTo(318.59, 0.1));
      expect(stacked.top, closeTo(tester.getRect(find.text('Text size')).bottom + t.space(3), 0.01));
      await endSettings(tester);
    });

    testWidgets('is the page’s row to the pixel: a label over its caption, and a switch at its end', (tester) async {
      await _pane(tester, [
        PaneSection(children: [
          const SettingRow(label: 'Animation speed'),
          SettingRow(
            label: 'Ghostly typing',
            hint: const Text('Words you say arrive as smoke, and words you delete leave as smoke. What you type appears at once.'),
            control: GlacierSwitch(ariaLabel: 'Ghostly typing', checked: true, onCheckedChange: (_) {}),
          ),
        ]),
      ]);
      final row = tester.getRect(find.widgetWithText(SettingRow, 'Ghostly typing'));
      final label = tester.getRect(find.text('Ghostly typing'));
      // The caption's box is its lines at the page's own height (the kit's ExactLines), not the engine's whole pixels.
      final hint = tester.getRect(find.ancestor(of: find.textContaining('Words you say'), matching: find.byType(ExactLines)).first);
      // Measured on the page: row 345.38 x 110.41 with its hairline; label 261.2 x 20; caption 2.4 under it, three
      // lines of 20.09; the switch 44 x 26 at the end, in the middle of the words' height.
      expect(row.height, closeTo(110.41 - 1, 0.1));
      expect(label.left - row.left, closeTo(13.39, 0.05));
      expect(label.top - row.top, closeTo(13.39, 0.05));
      expect(label.height, 20);
      expect(hint.top - label.top, closeTo(22.39, 0.05));
      expect(hint.width, closeTo(261.2, 0.1));
      expect(hint.height, closeTo(3 * 20.0922, 0.01));
      final control = tester.getRect(find.byType(GlacierSwitch));
      expect(control.size, const Size(44, 26));
      expect(control.left - row.left, closeTo(310.3 - 22.31, 0.1));
      expect(control.center.dy, closeTo((label.top + hint.bottom) / 2, 0.01));
      // The words as the page sets them.
      expect(_style(tester, 'Ghostly typing').fontSize, closeTo(16.1152, 0.01));
      expect(_style(tester, 'Ghostly typing').fontWeight, FontWeight.w500);
      final caption = DefaultTextStyle.of(tester.element(find.textContaining('Words you say'))).style;
      expect(caption.fontSize, closeTo(13.3948, 0.01));
      expect(caption.fontSize! * caption.height!, closeTo(20.0922, 0.01));
      expect(caption.color, sameColor(cssColor(tester, 'oklch(0.36 0 0)')));
      // A row that follows a row has a hairline over it, in the rule's colour, and is that much lower.
      final first = tester.getRect(find.widgetWithText(SettingRow, 'Animation speed'));
      expect(row.top - first.bottom, closeTo(1, 0.01));
      await endSettings(tester);
    });

    testWidgets('says why it is disabled, and cannot be reached by tapping or tabbing', (tester) async {
      var pressed = 0;
      await _pane(tester, [
        PaneSection(children: [
          SettingRow(label: 'Haptics', control: GlacierSwitch(ariaLabel: 'on', onCheckedChange: (_) => pressed++), disabledReason: 'This device has no motor.'),
        ]),
      ]);
      expect(find.text('This device has no motor.'), findsOneWidget);
      expect(_style(tester, 'This device has no motor.').fontStyle, FontStyle.italic);
      expect(tester.widget<Opacity>(find.descendant(of: find.byType(SettingRow), matching: find.byType(Opacity)).first).opacity, 0.5);
      await tester.tap(find.byType(GlacierSwitch), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
      // `inert`, not only the look: a Tab does not reach the control, and a screen reader is not told of it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.descendant(of: find.byType(SettingRow), matching: find.byWidgetPredicate((w) => w is Focus && (w.focusNode?.hasFocus ?? false))), findsNothing);
      expect(find.bySemanticsLabel('on'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('is one button when pressed, with a chevron, and a disabled one refuses the press', (tester) async {
      var pressed = 0;
      await _pane(tester, [
        PaneSection(children: [
          SettingRow(label: 'Welcome guide', hint: const Text('From the first page.'), onPress: () => pressed++),
          SettingRow(label: 'Sync now', onPress: () => pressed++, disabled: true),
        ]),
      ]);
      final row = find.widgetWithText(SettingRow, 'Welcome guide');
      expect(tester.getSemantics(find.descendant(of: row, matching: find.byType(GlacierPressable))), isSemantics(isButton: true, hasTapAction: true, hasEnabledState: true, isEnabled: true, isFocusable: true, hasFocusAction: true, label: 'Welcome guide\nFrom the first page.'));
      final chevron = tester.widget<SettingsIcon>(find.descendant(of: row, matching: find.byType(SettingsIcon)));
      expect((chevron.glyph, chevron.size), (SettingsGlyph.chevronRight, 18));
      expect(chevron.color, sameColor(_t(tester).color('app-ink-4')));
      await tester.tap(row);
      expect(pressed, 1);
      await tester.tap(find.widgetWithText(SettingRow, 'Sync now'), warnIfMissed: false);
      expect(pressed, 1);
      await endSettings(tester);
    });

    testWidgets('draws no stacked control on a pressable row, which has only the trailing seat', (tester) async {
      // A known edge of the kit, pinned so it is changed on purpose: a row that is a button has no room below its words.
      await _pane(tester, [
        PaneSection(children: [SettingRow(label: 'Row', onPress: () {}, layout: SettingRowLayout.stacked, control: const SizedBox(key: ValueKey('lost')))]),
      ]);
      expect(find.byKey(const ValueKey('lost')), findsNothing);
      await endSettings(tester);
    });

    testWidgets('wears its icon in the section’s chip on a page, and plain outside one', (tester) async {
      await _pane(tester, [
        const PaneSection(children: [SettingRow(icon: SettingsIcon(SettingsGlyph.bell), label: 'Alerts')]),
      ]);
      final t = _t(tester);
      final chip = find.descendant(of: find.byType(SettingRow), matching: find.byType(Container));
      // `.settingsScreen__pane .setk-row__icon`: 1.85rem with a 0.55rem corner, purple at 16%, the glyph at 1.05rem.
      expect(tester.getSize(chip), const Size.square(29.6));
      final ground = tester.widget<Container>(chip).decoration! as BoxDecoration;
      expect(ground.color, sameColor(cssColor(tester, '#9a45c9').withValues(alpha: 0.16)));
      expect(ground.borderRadius, BorderRadius.circular(8.8));
      expect(tester.getSize(find.descendant(of: chip, matching: find.byType(FittedBox))), const Size.square(16.8));
      expect(IconTheme.of(tester.element(find.descendant(of: find.byType(SettingRow), matching: find.byType(SettingsIcon)))).color, sameColor(cssColor(tester, '#9a45c9')));
      expect(t.len('glacier-space-3'), closeTo(tester.getRect(find.text('Alerts')).left - tester.getRect(chip).right, 0.01));
      await endSettings(tester);

      await _bare(tester, const SettingRow(icon: SettingsIcon(SettingsGlyph.bell), label: 'Alerts'));
      expect(find.descendant(of: find.byType(SettingRow), matching: find.byType(Container)), findsNothing);
      await endSettings(tester);
    });

    testWidgets('keeps a value to its end of the row, small and muted, and an action in its place at the row’s own size', (tester) async {
      var removed = 0;
      await _pane(tester, [
        PaneSection(children: [
          const SettingRow(label: 'Version', value: Text('1.15.0')),
          SettingRow(label: 'Qwen', value: RowAction(onPress: () => removed++, child: const Text('Remove')), control: const SizedBox(key: ValueKey('pick'), width: 20, height: 20)),
        ]),
      ]);
      final t = _t(tester);
      final value = DefaultTextStyle.of(tester.element(find.text('1.15.0'))).style;
      expect(value.fontSize, closeTo(t.fontSize('sm'), 0.001));
      expect(value.color, sameColor(t.color('app-ink-3')));
      expect(value.fontFeatures, contains(const FontFeature.tabularFigures()));
      final row = tester.getRect(find.widgetWithText(SettingRow, 'Version'));
      expect(tester.getRect(find.text('1.15.0')).right, closeTo(row.right - t.space(3), 0.01));
      // The action: the page's own size and ink, at least `--glacier-space-10` high, and held off the control.
      final action = DefaultTextStyle.of(tester.element(find.text('Remove'))).style;
      expect(action.fontSize, 16);
      expect(action.fontWeight, FontWeight.w600);
      expect(action.color, sameColor(t.color('app-ink')));
      expect(tester.getSize(find.descendant(of: find.byType(RowAction), matching: find.byType(GlacierPressable))).height, closeTo(t.space(10), 0.01));
      expect(tester.getRect(find.byKey(const ValueKey('pick'))).left - tester.getRect(find.text('Remove')).right, closeTo(t.space(1) + t.space(2) + t.space(3), 0.01));
      await tester.tap(find.text('Remove'));
      expect(removed, 1);
      await endSettings(tester);
    });
  });

  group('the rest of the kit', () {
    testWidgets('titles a card, describes it, and puts a footer under it', (tester) async {
      await _pane(tester, [
        const PaneSection(title: 'Updates', description: Text('Where this build stands.'), footer: Text('From the Play Store.'), children: [SettingRow(label: 'Up to date.')]),
      ]);
      final t = _t(tester);
      // Drawn in capitals, named as written.
      expect(find.text('UPDATES'), findsOneWidget);
      expect(find.bySemanticsLabel('Updates'), findsOneWidget);
      final title = tester.getRect(find.text('UPDATES'));
      Rect lines(String words) => tester.getRect(find.ancestor(of: find.text(words), matching: find.byType(ExactLines)).first);
      final desc = lines('Where this build stands.');
      final card = tester.getRect(find.widgetWithText(SettingRow, 'Up to date.'));
      final footer = lines('From the Play Store.');
      // Measured on the page (Appearance's first card): the title at the pane's first row, 122.73 down, 14 high in
      // 11.52px capitals spaced 0.9216px; then 8.93 to the caption, and 8.93 to the card.
      expect(title.top, closeTo(122.73, 0.1));
      expect(title.height, 14);
      expect(title.left, closeTo(22.31 + 8.93, 0.05));
      expect(_style(tester, 'UPDATES').fontSize, closeTo(11.52, 0.001));
      expect(_style(tester, 'UPDATES').letterSpacing, closeTo(0.9216, 0.001));
      expect(_style(tester, 'UPDATES').fontWeight, FontWeight.w600);
      expect(_style(tester, 'UPDATES').color, sameColor(cssColor(tester, 'oklch(0.56 0 0)')));
      expect(desc.top - title.bottom, closeTo(t.space(2), 0.01));
      expect(card.top - desc.bottom, closeTo(t.space(2), 0.01));
      expect(footer.top - card.bottom, closeTo(t.space(2), 0.01));
      expect(card.left, closeTo(22.31, 0.05));
      // The card: paper-2 with the kit's large corner, and a deeper track for a segmented control on it.
      final clip = tester.widget<ClipRRect>(find.ancestor(of: find.byType(SettingRow), matching: find.byType(ClipRRect)).first);
      expect(clip.borderRadius, BorderRadius.circular(16));
      expect(tester.widget<ColoredBox>(find.ancestor(of: find.byType(SettingRow), matching: find.byType(ColoredBox)).first).color, sameColor(cssColor(tester, 'oklch(0.955 0 0)')));
      expect(tokensAt(tester, find.byType(SettingRow)).color('glacier-segment-track'), sameColor(t.color('app-paper-3')));
      expect(t.color('glacier-segment-track'), sameColor(t.color('app-paper-2')));
      await endSettings(tester);
    });

    testWidgets('lets a page’s cards arrive one after another, each rising as it fades in', (tester) async {
      await _pane(
        tester,
        [for (final name in ['One', 'Two', 'Three']) PaneSection(title: name, children: [SettingRow(label: 'Row $name')])],
        settle: false,
      );
      double opacity(String name) {
        final found = find.ancestor(of: find.text(name.toUpperCase()), matching: find.byType(Opacity));
        return found.evaluate().isEmpty ? 1 : tester.widget<Opacity>(found.first).opacity;
      }

      // `.setk:nth-child(2..4)`: 40, 80 and 120ms after the page, each over 360ms.
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity('One'), greaterThan(opacity('Two')));
      expect(opacity('Two'), greaterThan(opacity('Three')));
      expect(opacity('Three'), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect((opacity('One'), opacity('Two'), opacity('Three')), (1, 1, 1));
      await endSettings(tester);
    });

    testWidgets('makes the hero pressable without making it look like a button, and says a state with its dot', (tester) async {
      var pressed = 0;
      await _pane(tester, [
        PaneSection(children: [
          PaneHero(glyph: const SettingsIcon(SettingsGlyph.info, size: 20), title: '1.8.0', meta: const Text('Built into the app'), status: const PaneHeroStatus('Syncing', pulse: true), onPress: () => pressed++),
        ]),
      ]);
      final t = _t(tester);
      final title = _style(tester, '1.8.0');
      expect(title.fontSize, closeTo(t.fontSize('2xl'), 0.001));
      expect(title.height, 1.1);
      expect(title.fontWeight, FontWeight.w600);
      expect(title.letterSpacing, closeTo(-0.025 * t.fontSize('2xl'), 0.001));
      // The glyph's tile: 2.75rem with the large corner, in the section's colour on a page.
      final tile = find.descendant(of: find.byType(PaneHero), matching: find.byType(Container)).first;
      expect(tester.getSize(tile), const Size.square(44));
      expect((tester.widget<Container>(tile).decoration! as BoxDecoration).color, sameColor(cssColor(tester, '#9a45c9').withValues(alpha: 0.16)));
      expect(find.text('Syncing'), findsOneWidget);
      // The dot breathes while it pulses: dimmer a moment later.
      final dot = find.ancestor(of: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 8), matching: find.byType(Opacity)).first;
      // `setkPulse 1.6s`: down to 0.3 at the half, which is where the page's arrival (0.8s here) has left it, and back.
      expect(tester.widget<Opacity>(dot).opacity, closeTo(0.3, 0.01));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.widget<Opacity>(dot).opacity, closeTo(1, 0.01));
      await tester.tap(find.text('1.8.0'));
      expect(pressed, 1);
      await endSettings(tester);

      await _bare(tester, const PaneHero(title: 'sam'));
      expect(find.descendant(of: find.byType(PaneHero), matching: find.byType(GlacierPressable)), findsNothing);
      await endSettings(tester);
    });

    testWidgets('draws a pick as a radio that says whether it is chosen', (tester) async {
      var pressed = 0;
      await _bare(tester, Align(alignment: Alignment.topLeft, child: Pick(checked: true, label: 'Use Qwen3.5 4B', onPress: () => pressed++)));
      final t = _t(tester);
      expect(tester.getSemantics(find.bySemanticsLabel('Use Qwen3.5 4B')), isSemantics(label: 'Use Qwen3.5 4B', hasCheckedState: true, isChecked: true, isInMutuallyExclusiveGroup: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, isFocusable: true, hasFocusAction: true));
      // A thumb's target that takes only the ring's room: `margin: calc(var(--glacier-space-2) * -1)`.
      expect(tester.getSize(find.byType(Pick)), Size.square(t.space(10) - 2 * t.space(2)));
      expect(tester.getSize(find.byType(GlacierPressable)), Size.square(t.space(10)));
      expect(tester.getSize(find.descendant(of: find.byType(Pick), matching: find.byType(CustomPaint)).last), const Size.square(20));
      await tester.tap(find.byType(Pick));
      expect(pressed, 1);
      await endSettings(tester);
    });

    testWidgets('offers an empty state’s one action as a word', (tester) async {
      var pressed = 0;
      await _pane(tester, [
        SettingsEmpty(icon: const SettingsIcon(SettingsGlyph.puzzle, size: 20), title: 'No repos yet.', body: const Text('Link one from a note.'), action: SettingsEmptyAction('Open a note', () => pressed++)),
      ]);
      final t = _t(tester);
      final box = tester.getRect(find.byType(SettingsEmpty));
      expect(box.width, closeTo(345.38, 0.1));
      // `padding: var(--glacier-space-6) var(--glacier-space-4)`, everything centred, `--glacier-space-2` apart.
      final tile = tester.getRect(find.descendant(of: find.byType(SettingsEmpty), matching: find.byType(Container)).at(1));
      expect(tile.size, const Size.square(44));
      expect(tile.top - box.top, closeTo(t.space(6), 0.01));
      expect(tile.center.dx, closeTo(box.center.dx, 0.01));
      expect(tester.getRect(find.text('No repos yet.')).top - tile.bottom, closeTo(t.space(2), 0.01));
      expect(_style(tester, 'No repos yet.').fontWeight, FontWeight.w500);
      final word = DefaultTextStyle.of(tester.element(find.text('Open a note'))).style;
      expect(word.fontWeight, FontWeight.w600);
      expect(word.color, sameColor(t.color('app-ink')));
      await tester.tap(find.text('Open a note'));
      expect(pressed, 1);
      await endSettings(tester);
    });

    testWidgets('draws a callout as a ruled card, and a footnote as a small muted paragraph', (tester) async {
      await _pane(tester, [
        const SettingsCallout(icon: SettingsIcon(SettingsGlyph.info), action: Text('Fix'), child: Text('Local only is on.')),
        const SettingsFootnote(child: Text('Nothing is fetched while the app is closed.')),
      ]);
      final t = _t(tester);
      final box = tester.widget<Container>(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(Container)).first);
      final look = box.decoration! as BoxDecoration;
      expect(look.color, sameColor(t.color('app-paper-2')));
      expect(look.border, Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')));
      expect(look.borderRadius, BorderRadius.circular(t.radius('lg')));
      expect(IconTheme.of(tester.element(find.descendant(of: find.byType(SettingsCallout), matching: find.byType(SettingsIcon)))).color, sameColor(cssColor(tester, '#9a45c9')));
      final words = DefaultTextStyle.of(tester.element(find.text('Local only is on.'))).style;
      expect(words.fontSize, closeTo(t.fontSize('sm'), 0.001));
      final note = DefaultTextStyle.of(tester.element(find.textContaining('Nothing is fetched'))).style;
      expect(note.color, sameColor(t.color('app-ink-3')));
      expect(tester.getRect(find.textContaining('Nothing is fetched')).left, closeTo(22.31 + t.space(2), 0.05));
      // The pane's children stand `--glacier-space-4` apart.
      expect(tester.getRect(find.byType(SettingsFootnote)).top - tester.getRect(find.byType(SettingsCallout)).bottom, closeTo(t.space(4), 0.01));
      await endSettings(tester);
    });

    testWidgets('sets a word that goes somewhere in its sentence, underlined, and leaves it a word where it goes nowhere', (tester) async {
      var went = 0;
      await _bare(
        tester,
        DefaultTextStyle(
          style: const TextStyle(fontSize: 13, color: Color(0xFF777777)),
          child: Text.rich(TextSpan(children: [
            const TextSpan(text: 'Held off by '),
            WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: () => went++)),
            const TextSpan(text: ' and '),
            const WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('nothing')),
          ])),
        ),
      );
      final t = _t(tester);
      final word = _style(tester, 'Local only');
      expect(word.decoration, TextDecoration.underline);
      expect(word.color, sameColor(t.color('app-ink')));
      expect(word.fontSize, 13);
      expect(_style(tester, 'nothing').decoration, isNot(TextDecoration.underline));
      await tester.tap(find.text('Local only'));
      expect(went, 1);
      await endSettings(tester);
    });

    testWidgets('says Copied for a moment after a copy, however often it is pressed', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      final copied = Copied('ghostmarkdown.com/api/mcp');
      addTearDown(copied.dispose);
      expect(copied.value, isFalse);
      copied.copy();
      expect(copied.value, isTrue);
      expect(calls.single.method, 'Clipboard.setData');
      expect((calls.single.arguments as Map)['text'], 'ghostmarkdown.com/api/mcp');
      await tester.pump(const Duration(milliseconds: 1000));
      copied.copy();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(copied.value, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      expect(copied.value, isFalse);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });
}
