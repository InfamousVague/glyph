import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/src/components/field_core.dart';
import 'package:glacier/src/components/kbd.dart';
import 'package:glacier/src/components/pressable.dart';
import 'package:glacier/src/components/search_field.dart';

import 'support/harness.dart';

/// The box the `<input>` is painted as, as it stands on screen now.
KitBoxPainter boxOf(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(GlacierFieldCore), matching: find.byType(CustomPaint)));
  return paints.map((p) => p.painter).whereType<KitBoxPainter>().firstWhere((p) => p.borderWidth > 0);
}

/// The magnifier and the cross: the two drawings that are not a box.
Finder glyphs() => find.descendant(
      of: find.byType(GlacierSearchField),
      matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter is! KitBoxPainter && w.size != Size.zero),
    );

Finder clearButton() => find.descendant(of: find.byType(GlacierSearchField), matching: find.byType(GlacierPressable));

/// Pumps [child] into a tree of its own. The harness's overlay keeps the first child it was given, so a test that
/// shows a second thing clears the first away.
Future<void> pumpFresh(WidgetTester tester, Widget child, {String theme = 'light'}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpKit(tester, child, theme: theme);
}

void main() {
  group('GlacierSearchField', () {
    for (final size in GlacierFieldSize.values) {
      testWidgets('is the control height of ${size.name}, with the magnifier inside its leading edge', (tester) async {
        await pumpKit(tester, GlacierSearchField(size: size));
        final t = testTokens();
        final lg = size == GlacierFieldSize.lg;
        final box = tester.getRect(find.byType(GlacierSearchField));
        expect(box.height, t.len('glacier-control-height-${size.name}'));
        expect(box.width, 390);

        // padding-inline: space 8 (10 on lg), so the text clears the icon and the trailing slot.
        final pad = t.len('glacier-hairline') + t.space(lg ? 10 : 8);
        expect(tester.getTopLeft(find.byType(EditableText)).dx, moreOrLessEquals(pad));
        expect(tester.getTopRight(find.byType(EditableText)).dx, moreOrLessEquals(390 - pad));
        expect(tester.widget<EditableText>(find.byType(EditableText)).style.fontSize, t.fontSize(const {GlacierFieldSize.sm: 'xs', GlacierFieldSize.md: 'sm', GlacierFieldSize.lg: 'md'}[size]!));

        // .icon: 1em of the text around the field (the root's 16 here), at space 3 (4 on lg), centred on the height.
        final icon = tester.getRect(glyphs());
        expect(icon.size, const Size.square(16));
        expect(icon.left, moreOrLessEquals(t.space(lg ? 4 : 3)));
        expect(icon.center.dy, moreOrLessEquals(box.center.dy));
      });
    }

    testWidgets('the default placeholder is Search, in the subtle ink, and the field is the stylesheet’s box', (tester) async {
      for (final theme in ['light', 'dark']) {
        await pumpFresh(tester, const GlacierSearchField(), theme: theme);
        await tester.pumpAndSettle();
        final t = testTokens(theme: theme);
        expect(tester.widget<Text>(find.text('Search')).style!.color, t.color('glacier-text-subtle'));
        final box = boxOf(tester);
        expect(box.fill, t.color('glacier-surface'));
        expect(box.border, t.color('glacier-border'));
        expect(box.radius, t.radius('lg'));
      }
    });

    testWidgets('typing tells onValueChange and swaps the shortcut hint for the clear button', (tester) async {
      final heard = <String>[];
      await pumpKit(tester, GlacierSearchField(onValueChange: heard.add, shortcut: const GlacierKbd(child: Text('⌘K'))));
      final t = testTokens();
      // Empty: the hint, at space 3 from the end, and no clear button.
      expect(find.text('⌘K'), findsOneWidget);
      expect(clearButton(), findsNothing);
      expect(tester.getRect(find.byType(GlacierKbd)).right, moreOrLessEquals(390 - t.space(3)));

      await tester.enterText(find.byType(EditableText), 'notes');
      await tester.pump();
      expect(heard, ['notes']);
      expect(find.text('⌘K'), findsNothing);
      expect(find.text('Search'), findsNothing);

      // .clear: 1.5em of a button's own 13.3333px, round, at space 2 from the end; its cross 1em of the same.
      final clear = tester.getRect(clearButton());
      expect(clear.width, moreOrLessEquals(20, epsilon: 0.001));
      expect(clear.height, moreOrLessEquals(20, epsilon: 0.001));
      expect(clear.right, moreOrLessEquals(390 - t.space(2)));
      expect(clear.center.dy, moreOrLessEquals(tester.getCenter(find.byType(GlacierSearchField)).dy));
      expect(tester.getSize(glyphs().last).width, moreOrLessEquals(13.3333, epsilon: 0.001));
    });

    testWidgets('the clear button empties an uncontrolled field, says so, and leaves the focus where it was', (tester) async {
      final heard = <String>[];
      await pumpKit(tester, GlacierSearchField(defaultValue: 'old', onValueChange: heard.add));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(editable.focusNode.hasFocus, isTrue);

      await tester.tap(clearButton());
      await tester.pump();
      expect(heard, ['']);
      expect(editable.controller.text, '');
      expect(clearButton(), findsNothing);
      expect(find.text('Search'), findsOneWidget);
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('a controlled field is cleared by its parent, or not at all', (tester) async {
      var value = 'query';
      var accept = false;
      await pumpKit(
        tester,
        StatefulBuilder(
          builder: (context, setState) => GlacierSearchField(
            value: value,
            onValueChange: (next) {
              if (accept) setState(() => value = next);
            },
          ),
        ),
      );
      final controller = tester.widget<EditableText>(find.byType(EditableText)).controller;
      await tester.tap(clearButton());
      await tester.pump();
      expect(controller.text, 'query', reason: 'the parent kept its value');

      accept = true;
      await tester.tap(clearButton());
      await tester.pump();
      expect(value, '');
      expect(controller.text, '');

      await tester.enterText(find.byType(EditableText), 'new');
      await tester.pump();
      expect(value, 'new');
      expect(controller.text, 'new');
    });

    testWidgets('the soft keyboard’s key is Search, and pressing it submits', (tester) async {
      final sent = <String>[];
      await pumpKit(tester, GlacierSearchField(onSubmitted: sent.add));
      await tester.showKeyboard(find.byType(EditableText));
      final args = tester.testTextInput.setClientArgs!;
      expect(args['inputAction'], 'TextInputAction.search');
      expect((args['inputType'] as Map)['name'], 'TextInputType.text');
      await tester.enterText(find.byType(EditableText), 'ghost');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(sent, ['ghost']);
    });

    testWidgets('focus, hover and invalid paint as the input’s rules have them', (tester) async {
      await pumpKit(tester, const GlacierSearchField());
      final t = testTokens();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(EditableText)));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-border-strong'));

      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-focus-ring'));
      expect(boxOf(tester).ring, t.color('glacier-accent-soft'));
      expect(boxOf(tester).ringSpread, 3);

      // The pointer is still over the field. `:hover:not(:disabled):not(:focus)` is the most specific rule the input
      // has, so a hovered invalid field shows the strong border, not the danger one, until the pointer leaves.
      await pumpFresh(tester, const GlacierSearchField(ariaInvalid: true));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-border-strong'));
      await mouse.moveTo(const Offset(200, 600));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-danger-border'));
    });

    testWidgets('the clear button lights on hover and rings on keyboard focus', (tester) async {
      // Hover and focus-visible show in the keyboard-and-mouse highlight mode, which a test on a phone target is not in.
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await pumpKit(tester, const GlacierSearchField(defaultValue: 'x'));
      final t = testTokens();
      Color ground() => (tester.widget<DecoratedBox>(find.descendant(of: clearButton(), matching: find.byType(DecoratedBox))).decoration as BoxDecoration).color!;
      expect(ground().a, 0);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(clearButton()));
      await tester.pumpAndSettle();
      expect(ground(), t.color('glacier-surface-sunken'));
      // Over the button, the pointer is not over the input: its border stays as it was.
      expect(boxOf(tester).border, t.color('glacier-border'));
      await mouse.moveTo(const Offset(200, 600));
      await tester.pumpAndSettle();

      // The next stop after the field is the button (Tab, in an app; the harness has no app to bind the key), which
      // shows the ring; Enter presses it.
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      FocusManager.instance.primaryFocus!.nextFocus();
      await tester.pumpAndSettle();
      final ring = tester
          .widgetList<CustomPaint>(find.descendant(of: clearButton(), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<KitBoxPainter>()
          .single;
      expect(ring.ring, t.color('glacier-accent-soft'));
      expect(ring.ringSpread, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
    });

    testWidgets('glass puts the material on the wrapper and leaves the input clear over it', (tester) async {
      await pumpKit(tester, const GlacierSearchField(glass: true), theme: 'dark');
      await tester.pumpAndSettle();
      final t = testTokens(theme: 'dark');
      expect(find.descendant(of: find.byType(GlacierSearchField), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(boxOf(tester).fill!.a, 0);
      expect(boxOf(tester).border, t.color('glacier-glass-border'));
      final wrapper = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(GlacierFieldCore), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<KitBoxPainter>()
          .firstWhere((p) => p.borderWidth == 0 && p.fill != null);
      expect(wrapper.fill, t.color('glacier-glass-regular'));
      expect(wrapper.radius, t.radius('lg'));

      // `.glass .input` comes after `.input:focus` and is as specific: the border holds, the ring still shows.
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-glass-border'));
      expect(boxOf(tester).ring, t.color('glacier-accent-soft'));
    });

    testWidgets('a disabled field dims the input alone', (tester) async {
      await pumpKit(tester, const GlacierSearchField(disabled: true));
      await tester.pumpAndSettle();
      final t = testTokens();
      expect(boxOf(tester).fill, t.color('glacier-surface-sunken'));
      expect(tester.widget<Opacity>(find.descendant(of: find.byType(GlacierSearchField), matching: find.byType(Opacity))).opacity, 0.5);
      // The magnifier is the wrapper's, outside what is dimmed.
      expect(find.ancestor(of: glyphs(), matching: find.byType(Opacity)), findsNothing);
      await tester.tap(find.byType(GlacierSearchField), warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);
    });

    testWidgets('onKeyDown may keep a key from the text, as the palette does with its arrows', (tester) async {
      final keys = <LogicalKeyboardKey>[];
      await pumpKit(
        tester,
        GlacierSearchField(
          autoFocus: true,
          onKeyDown: (event) {
            keys.add(event.logicalKey);
            return KeyEventResult.handled;
          },
        ),
      );
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue, reason: 'autoFocus');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(keys, [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.enter]);
    });

    testWidgets('says what it is to a screen reader, in the reader’s language', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKit(tester, const GlacierSearchField(defaultValue: 'ghost', ariaLabel: 'Search tests', placeholder: 'Words', ariaExpanded: true, ariaControls: 'results'));
      final field = tester.getSemantics(find.byType(EditableText));
      expect(field, isSemantics(isTextField: true, isEnabled: true, hasEnabledState: true, hasTapAction: true, hasExpandedState: true, isExpanded: true, label: 'Search tests', hint: 'Words', value: 'ghost'));
      expect(field.getSemanticsData().controlsNodes, {'results'});
      expect(tester.getSemantics(clearButton()), isSemantics(isButton: true, isEnabled: true, hasEnabledState: true, hasTapAction: true, label: 'Clear search'));

      await pumpFresh(
        tester,
        Localizations(
          locale: const Locale('de'),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: const GlacierSearchField(defaultValue: 'geist'),
        ),
      );
      await tester.pump();
      expect(tester.getSemantics(clearButton()).label, 'Suche löschen');

      await pumpFresh(tester, const GlacierSearchField(defaultValue: 'x', clearLabel: 'Empty it'));
      expect(tester.getSemantics(clearButton()).label, 'Empty it');
      handle.dispose();
    });
  });
}
