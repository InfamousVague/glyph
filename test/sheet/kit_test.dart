import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/sheet/css.dart';
import 'package:ghost_md/sheet/flow.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';
import '../support/render.dart';

/// The pieces a sheet is built from (sheet/kit.dart, the web's plugins/kit.tsx): what each draws, what it says, and
/// what a press on it does. The numbers are the web page's at 390 x 844 (Chromium, 2026-10-07), where a group is
/// 345.38 wide inside the sheet's gutters.
void main() {
  setUpAll(loadAppFonts);

  /// The pieces in a column as wide as a sheet's is on the phone.
  Future<void> show(WidgetTester tester, List<Widget> children, {String theme = 'light'}) => pumpPage(
        tester,
        Align(alignment: Alignment.topLeft, child: SizedBox(width: 345.38, child: CssFlow(children: children))),
        theme: theme,
      );

  Tokens tokens(WidgetTester tester) => tester.element(find.byType(CssFlow).first).tokens;
  Color colorOf(WidgetTester tester, String text) => tester.widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText))).text.style!.color!;

  group('the words', () {
    testWidgets('a title is one bold line, cut short rather than wrapped, with a sentence and a heading under it as far apart as the page has them', (tester) async {
      await show(tester, [SheetTitle.text('A workspace with a name much too long for one line of a phone'), const SheetNote('What it is for.'), const SheetHeading('Colour'), const SizedBox(key: ValueKey('after'), height: 10)]);
      final t = tokens(tester);
      final title = tester.getRect(find.byType(SheetTitle));
      // 19.39px bold: a 24px line, and `margin: 0 0 var(--glacier-space-4)` under it.
      expect([title.top, title.height, title.width], [0, 24, 345.38]);
      final words = tester.widget<RichText>(find.descendant(of: find.byType(SheetTitle), matching: find.byType(RichText)));
      expect([words.maxLines, words.overflow, words.softWrap], [1, TextOverflow.ellipsis, false]);
      expect(words.text.style!.fontSize, t.fontSize('lg'));
      final note = tester.getRect(find.text('What it is for.'));
      expect(note.top, closeTo(24 + 17.85, 0.01));
      expect(note.height, 16);
      expect(colorOf(tester, 'What it is for.'), t.color('glacier-text-subtle'));
      // A heading is said as written and drawn in spaced capitals; its 8.93 above lies inside the note's 13.39 below.
      final heading = tester.getRect(find.text('COLOUR'));
      expect(heading.top, closeTo(note.bottom + 13.39, 0.01));
      expect(heading.height, 14);
      expect(find.bySemanticsLabel('Colour'), findsOneWidget);
      expect(tester.widget<RichText>(find.descendant(of: find.text('COLOUR'), matching: find.byType(RichText))).text.style!.letterSpacing, closeTo(0.8907, 0.001));
      expect(tester.getRect(find.byKey(const ValueKey('after'))).top, closeTo(heading.bottom + 8.93, 0.01));
      await away(tester);
    });
  });

  group('a group of rows', () {
    testWidgets('is a card on the page’s ground, with a hairline between two rows and none round anything else', (tester) async {
      await show(tester, [
        SheetGroup(
          children: [
            const SheetField(label: 'Name'),
            SheetRow(key: const ValueKey('add'), label: 'Add', onPress: () {}),
            const SizedBox(key: ValueKey('swatch'), height: 30),
            SheetRow(key: const ValueKey('after'), label: 'After something else', onPress: () {}),
          ],
        ),
      ]);
      final t = tokens(tester);
      final card = tester.widget<ColoredBox>(find.descendant(of: find.byType(SheetGroup), matching: find.byType(ColoredBox)).first);
      expect(card.color, t.color('glacier-bg'));
      expect(tester.widget<ClipRRect>(find.descendant(of: find.byType(SheetGroup), matching: find.byType(ClipRRect))).borderRadius, BorderRadius.circular(16));
      Border? ruleOf(Key key) => (tester.widget<DecoratedBox>(find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration).border as Border?;
      // `.field + .row`
      expect(ruleOf(const ValueKey('add'))!.top, BorderSide(color: t.color('glacier-border-subtle')));
      expect(ruleOf(const ValueKey('after')), isNull);
      // A row is `var(--glacier-space-12)` tall with its hairline inside that; the field over it is not ruled.
      expect(tester.getSize(find.byKey(const ValueKey('add'))).height, closeTo(53.55, 0.02));
      // The card's `margin-block-end: var(--glacier-space-3)` is told to the flow it stands in.
      expect(tester.renderObject<RenderCssFlow>(find.descendant(of: find.byType(SheetGroup), matching: find.byType(CssFlow))).marginBottom, closeTo(13.39, 0.01));
      await away(tester);
    });
  });

  group('a row', () {
    testWidgets('with something to do is a button that does it; pressed, it wears the wash', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await show(tester, [SheetGroup(children: [SheetRow(label: 'Cancel', onPress: () => pressed += 1)])]);
      final t = tokens(tester);
      expect(tester.getSemantics(find.bySemanticsLabel('Cancel')).flagsCollection.isButton, isTrue);
      // The page's numbers: the row 53.55 tall, its words 20 tall at 16.12px medium, 17.85 in from the card's edge.
      near(tester.getRect(find.text('Cancel')), [17.85, (53.55 - 20) / 2, 53.08, 20], what: 'the label');
      expect(colorOf(tester, 'Cancel'), t.color('glacier-text'));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Cancel')));
      await tester.pump();
      expect((tester.widget<DecoratedBox>(find.descendant(of: find.byType(SheetRow), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration).color, t.color('app-wash'));
      await gesture.up();
      expect(pressed, 1);
      handle.dispose();
      await away(tester);
    });

    testWidgets('carries a hint under its words, and is as tall as the two', (tester) async {
      await show(tester, [SheetGroup(children: [SheetRow(label: 'Delete workspace', hint: 'Asks what happens to its notes first.', danger: true, onPress: () {})])]);
      final t = tokens(tester);
      // 13.39 + 20 + 2 + 16 + 13.39.
      expect(tester.getSize(find.byType(SheetRow)).height, closeTo(64.78, 0.02));
      near(tester.getRect(find.text('Asks what happens to its notes first.')), [17.85, 13.39 + 22, 229.17, 16], what: 'the hint');
      expect(colorOf(tester, 'Delete workspace'), t.color('glacier-red-9'));
      expect(colorOf(tester, 'Asks what happens to its notes first.'), t.color('glacier-text-subtle'));
      await away(tester);
    });

    testWidgets('without anything to do is a line of text, and one that cannot be done now is muted and does nothing', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await show(tester, [
        SheetGroup(children: [const SheetRow(label: 'Only words'), SheetRow(label: 'Rename', onPress: () => pressed += 1, disabled: true)]),
      ]);
      final t = tokens(tester);
      expect(colorOf(tester, 'Only words'), t.color('glacier-text-muted'));
      expect(colorOf(tester, 'Rename'), t.color('glacier-text-muted'));
      expect(tester.getSemantics(find.bySemanticsLabel('Only words')).flagsCollection.isButton, isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Rename')).flagsCollection.isEnabled, Tristate.isFalse);
      await tester.tap(find.text('Only words'));
      await tester.tap(find.text('Rename'));
      expect(pressed, 0);
      handle.dispose();
      await away(tester);
    });

    testWidgets('that is a choice says whether it is the one chosen, and wears a tick at its end when it is', (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester, [
        SheetGroup(children: [SheetRow(label: 'Plain', chosen: true, onPress: () {}), SheetRow(label: 'Reading', chosen: false, onPress: () {}), SheetRow(label: 'Neither', onPress: () {})]),
      ]);
      expect(tester.getSemantics(find.bySemanticsLabel('Plain')).flagsCollection.isToggled, Tristate.isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Reading')).flagsCollection.isToggled, Tristate.isFalse);
      expect(tester.getSemantics(find.bySemanticsLabel('Neither')).flagsCollection.isToggled, Tristate.none);
      final ticks = find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border is Border && ((w.decoration! as BoxDecoration).border! as Border).right.width == 2);
      expect(ticks, findsOneWidget);
      expect(tester.getCenter(ticks).dx, greaterThan(300));
      expect(find.descendant(of: find.widgetWithText(SheetRow, 'Plain'), matching: ticks), findsOneWidget);
      handle.dispose();
      await away(tester);
    });

    testWidgets('draws a mark in a 30 px ring of its own colour, and takes widgets where words will not do', (tester) async {
      await show(tester, [
        SheetGroup(
          children: [
            SheetRow.rich(icon: Icon(LucideIcons.trash2), label: const Text('Throw away'), hint: const Text('For good.'), danger: true, onPress: () {}),
            SheetRow(icon: StrokeMark(path: Path()..addOval(const Rect.fromLTWH(4, 4, 16, 16))), label: 'A round', onPress: () {}),
          ],
        ),
      ]);
      final t = tokens(tester);
      final ring = find.descendant(of: find.byType(SheetIcon).first, matching: find.byType(Container));
      expect(tester.getSize(ring), const Size(30, 30));
      final border = (tester.widget<Container>(ring).decoration! as BoxDecoration).border! as Border;
      expect([border.top.color, border.top.width], [t.color('glacier-red-9'), 1.5]);
      expect(tester.getSize(find.byIcon(LucideIcons.trash2)), const Size(18, 18));
      expect(IconTheme.of(tester.element(find.byIcon(LucideIcons.trash2))).color, t.color('glacier-red-9'));
      expect(tester.getSize(find.byType(StrokeMark)), const Size(18, 18));
      // The words start a ring and `var(--glacier-space-3)` in.
      expect(tester.getRect(find.text('Throw away')).left, closeTo(17.85 + 30 + 13.39, 0.02));
      expect(find.text('For good.'), findsOneWidget);
      await away(tester);
    });
  });

  group('a field', () {
    testWidgets('is a named line to type on, ruled underneath, the rule in ink while it is typed in', (tester) async {
      final handle = tester.ensureSemantics();
      final typed = <String>[];
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await show(tester, [SheetGroup(children: [SheetField(label: 'Name', focusNode: focus, placeholder: 'Kitchen', onChange: typed.add)])]);
      final t = tokens(tester);
      // The page's numbers: the label 14 tall at 11.13px bold in capitals, the line under it 4.46 on.
      near(tester.getRect(find.text('NAME')), [17.85, 13.39, 309.69, 14], what: 'the label');
      expect(tester.widget<RichText>(find.descendant(of: find.text('NAME'), matching: find.byType(RichText))).text.style!.letterSpacing, closeTo(0.668, 0.001));
      near(tester.getRect(find.byType(EditableText)), [17.85, 13.39 + 14 + 4.46 + 8.93, 309.69, 20], what: 'the line');
      // `border-block-end: var(--app-line) solid`: 1.5px here, where the browser the page was measured in drew it 1px
      // (it snaps a border to whole CSS pixels when it emulates a phone's screen), so the field is half a pixel taller.
      expect(tester.getSize(find.byType(SheetField)).height, closeTo(84.08 + 0.5, 0.02));
      Border rule() => (tester.widget<DecoratedBox>(find.ancestor(of: find.byType(EditableText), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration).border! as Border;
      expect([rule().bottom.color, rule().bottom.width], [t.color('glacier-border-strong'), 1.5]);
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.bySemanticsLabel('Name'), findsOneWidget);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(rule().bottom.color, t.color('glacier-text'));
      await tester.enterText(find.byType(EditableText), 'Garden');
      await tester.pump();
      expect(typed, ['Garden']);
      expect(find.text('Kitchen'), findsNothing);
      handle.dispose();
      await away(tester);
    });

    testWidgets('held by its parent, shows what the parent holds; and tells Enter and the keys to whoever asks', (tester) async {
      final submitted = <String>[];
      final keys = <LogicalKeyboardKey>[];
      var held = 'Kitchen';
      late StateSetter set;
      await show(tester, [
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return SheetGroup(
              children: [
                SheetField(
                  label: 'Name',
                  value: held,
                  autoFocus: true,
                  // A parent that will not have digits.
                  onChange: (text) => setState(() => held = text.replaceAll(RegExp(r'\d'), '')),
                  onSubmitted: submitted.add,
                  onKeyDown: (event) {
                    keys.add(event.logicalKey);
                    return KeyEventResult.ignored;
                  },
                ),
              ],
            );
          },
        ),
      ]);
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, 'Kitchen');
      await tester.enterText(find.byType(EditableText), 'Pantry 2');
      await tester.pump();
      await tester.pump();
      expect(field.controller.text, 'Pantry ');
      set(() => held = 'Larder');
      await tester.pump();
      expect(field.controller.text, 'Larder');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(keys, contains(LogicalKeyboardKey.arrowLeft));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, ['Larder']);
      await away(tester);
    });
  });

  group('the page’s text, as its engine sets it (sheet/css.dart)', () {
    testWidgets('a line is as tall as the browser makes it: the ascent and the descent, each to a whole pixel', (tester) async {
      await show(tester, const [SizedBox(height: 1)]);
      final t = tokens(tester);
      // Measured on the page: 10.02px is 12, 11.13 is 14, 12.06 is 15, 13.39 is 16, 16.12 is 20, 19.39 is 24.
      for (final (px, line) in [(10.0208, 12), (11.1342, 14), (12.0553, 15), (13.3948, 16), (16.1152, 20), (19.3897, 24)]) {
        expect(normalLine(t, px) * px, closeTo(line.toDouble(), 1e-9), reason: '$px');
      }
      expect(pageText(t, 16.1152).height! * 16.1152, closeTo(20, 1e-9));
      expect(pageText(t, 16.1152, height: 1.5).height, 1.5);
      await away(tester);
    });

    testWidgets('lines with a height of their own keep it to the fraction, however many there are', (tester) async {
      await show(tester, [
        Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `font-size: 12.78px; line-height: 1.3`: 16.61 a line on the page, where the text engine makes it 17.
              cssLines('One line', pageText(context.tokens, 12.7787, height: 1.3), maxLines: 1),
              SizedBox(width: 120, child: cssLines('Two lines of words, at least, in a narrow column', pageText(context.tokens, 12.7787, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ]);
      final lines = find.byType(CssLines);
      expect(tester.getSize(lines.at(0)).height, closeTo(16.6123, 0.001));
      expect(tester.getSize(lines.at(1)).height, closeTo(2 * 16.6123, 0.001));
      expect(tester.getSize(find.text('One line')).height, 17);
      await away(tester);
    });

    testWidgets('a border is a whole number of the screen’s own pixels, and never none', (tester) async {
      await show(tester, const [SizedBox(height: 1)]);
      final context = tester.element(find.byType(CssFlow).first);
      // At 2 to a pixel: 1.5 is three, and stays; 1.2 is two and a bit, and is two.
      expect(snapBorder(context, 1.5), 1.5);
      expect(snapBorder(context, 1), 1);
      expect(snapBorder(context, 1.2), 1);
      expect(snapBorder(context, 0.2), 0.5);
      expect(snapBorder(context, 0), 0);
      expect(blurSigma(context.tokens, 'app-float-blur'), 20);
      expect(blurSigma(context.tokens, 'app-ink'), 0);
      await away(tester);
    });
  });
}
