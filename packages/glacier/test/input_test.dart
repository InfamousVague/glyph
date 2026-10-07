import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/src/components/field_core.dart';
import 'package:glacier/src/components/input.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/harness.dart';

/// The box the `<input>` is painted as, as it stands on screen now.
KitBoxPainter boxOf(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(GlacierFieldCore), matching: find.byType(CustomPaint)));
  return paints.map((p) => p.painter).whereType<KitBoxPainter>().firstWhere((p) => p.borderWidth > 0);
}

/// Pumps [child] into a tree of its own. The harness's overlay keeps the first child it was given, so a test that
/// shows a second thing clears the first away.
Future<void> pumpFresh(WidgetTester tester, Widget child, {String theme = 'light'}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpKit(tester, child, theme: theme);
}

Future<TestGesture> hover(WidgetTester tester, Offset at) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(at);
  await tester.pumpAndSettle();
  return mouse;
}

void main() {
  group('GlacierInput', () {
    for (final size in GlacierFieldSize.values) {
      testWidgets('is the control height of ${size.name}, and as wide as it is given', (tester) async {
        await pumpKit(tester, GlacierInput(size: size, placeholder: 'Name'));
        final t = testTokens();
        final box = tester.getSize(find.byType(GlacierInput));
        expect(box.height, t.len('glacier-control-height-${size.name}'));
        expect(box.width, 390);
        // font-size: xs, sm, md; padding-inline: space 3, 4, 5, inside the hairline.
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.style.fontSize, t.fontSize(const {GlacierFieldSize.sm: 'xs', GlacierFieldSize.md: 'sm', GlacierFieldSize.lg: 'md'}[size]!));
        final pad = t.len('glacier-hairline') + t.space(const {GlacierFieldSize.sm: 3, GlacierFieldSize.md: 4, GlacierFieldSize.lg: 5}[size]!);
        expect(tester.getTopLeft(find.byType(EditableText)).dx, moreOrLessEquals(pad));
        expect(tester.getTopRight(find.byType(EditableText)).dx, moreOrLessEquals(390 - pad));
        // The line of text sits in the middle of the box.
        expect(tester.getCenter(find.byType(EditableText)).dy, moreOrLessEquals(box.height / 2));
      });
    }

    testWidgets('paints the stylesheet: surface, hairline border, large radius; the placeholder in the subtle ink', (tester) async {
      for (final theme in ['light', 'dark']) {
        await pumpFresh(tester, const GlacierInput(placeholder: 'Name'), theme: theme);
        await tester.pumpAndSettle();
        final t = testTokens(theme: theme);
        final box = boxOf(tester);
        expect(box.fill, t.color('glacier-surface'));
        expect(box.border, t.color('glacier-border'));
        expect(box.borderWidth, t.len('glacier-hairline'));
        expect(box.radius, t.radius('lg'));
        expect(box.ringSpread, 0);
        final placeholder = tester.widget<Text>(find.text('Name'));
        expect(placeholder.style!.color, t.color('glacier-text-subtle'));
        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.style.color, t.color('glacier-text'));
        expect(editable.cursorColor, t.color('glacier-text'));
        expect(editable.style.fontFamily, t.families('glacier-font-sans').first);
      }
    });

    testWidgets('typing tells onChange, hides the placeholder, and an uncontrolled field keeps what was typed', (tester) async {
      final heard = <String>[];
      await pumpKit(tester, GlacierInput(placeholder: 'Name', defaultValue: 'Ada', onChange: heard.add));
      expect(find.text('Name'), findsNothing);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Ada');

      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      expect(find.text('Name'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Grace');
      await tester.pump();
      expect(heard, ['', 'Grace']);
      expect(find.text('Name'), findsNothing);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Grace');
    });

    testWidgets('a controlled field shows its parent’s value: taken, it holds; refused, it goes back', (tester) async {
      var value = 'a';
      var accept = true;
      late StateSetter rebuild;
      await pumpKit(
        tester,
        StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return GlacierInput(
            value: value,
            onChange: (next) {
              if (accept) setState(() => value = next);
            },
          );
        }),
      );
      final controller = tester.widget<EditableText>(find.byType(EditableText)).controller;

      await tester.enterText(find.byType(EditableText), 'ab');
      await tester.pump();
      expect(value, 'ab');
      expect(controller.text, 'ab');

      accept = false;
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.pump();
      expect(value, 'ab');
      expect(controller.text, 'ab');

      // And the parent may set it from outside.
      rebuild(() => value = 'reset');
      await tester.pump();
      expect(controller.text, 'reset');
    });

    testWidgets('a controller of the caller’s holds the text', (tester) async {
      final controller = TextEditingController(text: 'one');
      addTearDown(controller.dispose);
      final heard = <String>[];
      await pumpKit(tester, GlacierInput(controller: controller, onChange: heard.add, placeholder: 'Name'));
      await tester.enterText(find.byType(EditableText), 'two');
      await tester.pump();
      expect(controller.text, 'two');
      expect(heard, ['two']);
      controller.clear();
      await tester.pump();
      expect(find.text('Name'), findsOneWidget);
      expect(heard, ['two'], reason: 'only what the user does is an onChange');
    });

    testWidgets('submitting from the soft keyboard calls onSubmitted', (tester) async {
      final sent = <String>[];
      await pumpKit(tester, GlacierInput(onSubmitted: sent.add));
      await tester.enterText(find.byType(EditableText), 'hello');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sent, ['hello']);
    });

    testWidgets('focus draws the ring and the focus border, over 150ms', (tester) async {
      final focused = <String>[];
      await pumpKit(tester, GlacierInput(onFocus: () => focused.add('focus'), onBlur: () => focused.add('blur')));
      final t = testTokens();
      await tester.tap(find.byType(GlacierInput));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue, reason: 'a tap asks for the keyboard');
      expect(focused, ['focus']);

      // Halfway: on its way, not there.
      await tester.pump(const Duration(milliseconds: 30));
      final mid = boxOf(tester);
      expect(mid.ringSpread, inExclusiveRange(0, 3));
      expect(mid.border, isNot(t.color('glacier-border')));
      expect(mid.border, isNot(t.color('glacier-focus-ring')));

      await tester.pump(t.duration('glacier-duration-fast'));
      final box = boxOf(tester);
      expect(box.border, t.color('glacier-focus-ring'));
      expect(box.ring, t.color('glacier-accent-soft'));
      expect(box.ringSpread, 3);
      expect(tester.widget<EditableText>(find.byType(EditableText)).selectionColor, t.color('glacier-selection'));

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      expect(focused, ['focus', 'blur']);
      expect(boxOf(tester).border, t.color('glacier-border'));
      expect(boxOf(tester).ringSpread, 0);
      expect(tester.widget<EditableText>(find.byType(EditableText)).selectionColor, isNull);
    });

    testWidgets('hover strengthens the border, but not on a focused field', (tester) async {
      await pumpKit(tester, const GlacierInput());
      final t = testTokens();
      final mouse = await hover(tester, tester.getCenter(find.byType(GlacierInput)));
      expect(boxOf(tester).border, t.color('glacier-border-strong'));
      await mouse.moveTo(const Offset(200, 600));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-border'));

      await tester.tap(find.byType(GlacierInput));
      await mouse.moveTo(tester.getCenter(find.byType(GlacierInput)));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-focus-ring'));
    });

    testWidgets('an invalid field is bordered in danger, by its own word or its Field’s', (tester) async {
      final t = testTokens();
      await pumpKit(tester, const GlacierInput(ariaInvalid: true));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-danger-border'));

      await tester.tap(find.byType(GlacierInput));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-danger-solid'));
      expect(boxOf(tester).ring, t.color('glacier-danger-soft'));

      await pumpFresh(
        tester,
        const GlacierFieldContext(
          value: FieldContextValue(id: 'handle', invalid: true, label: 'Handle', description: 'Taken already'),
          child: GlacierInput(),
        ),
      );
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-danger-border'));
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.label, 'Handle');
      expect(node.hint, 'Taken already');
      expect(node.identifier, 'handle');
      expect(node.getSemanticsData().validationResult, SemanticsValidationResult.invalid);
    });

    testWidgets('a disabled field is half there, sunken, and takes neither focus nor text', (tester) async {
      await pumpKit(tester, const GlacierInput(disabled: true, defaultValue: 'fixed'));
      await tester.pumpAndSettle();
      final t = testTokens();
      expect(boxOf(tester).fill, t.color('glacier-surface-sunken'));
      final opacity = tester.widget<Opacity>(find.descendant(of: find.byType(GlacierInput), matching: find.byType(Opacity)));
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(GlacierInput), warnIfMissed: false);
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // Hovered, it does not light, and the pointer says no.
      await hover(tester, tester.getCenter(find.byType(GlacierInput)));
      expect(boxOf(tester).border, t.color('glacier-border'));
      final region = tester.widget<MouseRegion>(find.descendant(of: find.byType(GlacierInput), matching: find.byType(MouseRegion)).first);
      expect(region.cursor, SystemMouseCursors.forbidden);
      expect(tester.getSemantics(find.byType(EditableText)), isSemantics(isTextField: true, isEnabled: false, hasEnabledState: true, isReadOnly: true));
    });

    testWidgets('the icon slots pin an icon to each edge and pad the text clear of it', (tester) async {
      for (final size in GlacierFieldSize.values) {
        await pumpFresh(tester, GlacierInput(size: size, leadingIcon: const Icon(LucideIcons.search), trailingIcon: const Icon(LucideIcons.x)));
        final t = testTokens();
        final hairline = t.len('glacier-hairline');
        final pad = hairline + t.space(size == GlacierFieldSize.lg ? 10 : 8);
        expect(tester.getTopLeft(find.byType(EditableText)).dx, moreOrLessEquals(pad));
        expect(tester.getTopRight(find.byType(EditableText)).dx, moreOrLessEquals(390 - pad));

        final field = tester.getRect(find.byType(GlacierInput));
        final leading = tester.getRect(find.byIcon(LucideIcons.search));
        final trailing = tester.getRect(find.byIcon(LucideIcons.x));
        expect(leading.size, const Size.square(18));
        expect(leading.left, moreOrLessEquals(t.space(3)));
        expect(trailing.right, moreOrLessEquals(390 - t.space(3)));
        expect(leading.center.dy, moreOrLessEquals(field.center.dy));
        expect(trailing.center.dy, moreOrLessEquals(field.center.dy));
        final icon = tester.widget<RichText>(find.descendant(of: find.byIcon(LucideIcons.search), matching: find.byType(RichText)));
        expect(icon.text.style!.color, t.color('glacier-text-subtle'));

        // The leading icon lets a tap through to the field; the trailing one keeps its own.
        await tester.tapAt(leading.center);
        await tester.pump();
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pump();
        await tester.tapAt(trailing.center);
        await tester.pump();
        expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isFalse);
      }
    });

    testWidgets('glass is the frosted material: a blur behind, the glass ground and border, a highlight until focus', (tester) async {
      await pumpKit(tester, const GlacierInput(glass: true), theme: 'dark');
      await tester.pumpAndSettle();
      final t = testTokens(theme: 'dark');
      expect(find.descendant(of: find.byType(GlacierInput), matching: find.byType(BackdropFilter)), findsOneWidget);
      expect(boxOf(tester).fill, t.color('glacier-glass-regular'));
      expect(boxOf(tester).border, t.color('glacier-glass-border'));
      expect(boxOf(tester).highlight, t.color('glacier-glass-highlight'));

      await tester.tap(find.byType(GlacierInput));
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, t.color('glacier-focus-ring'));
      expect(boxOf(tester).ring, t.color('glacier-accent-soft'));
      expect(boxOf(tester).highlight!.a, 0);
    });

    testWidgets('the type picks the keyboard, and a password hides itself', (tester) async {
      Future<EditableText> made(GlacierInput input) async {
        await pumpFresh(tester, input);
        return tester.widget<EditableText>(find.byType(EditableText));
      }

      var e = await made(const GlacierInput());
      expect(e.keyboardType, TextInputType.text);
      expect(e.obscureText, isFalse);
      expect(e.textCapitalization, TextCapitalization.sentences);
      expect(e.autocorrect, isTrue);
      expect(e.maxLines, 1);

      e = await made(const GlacierInput(type: GlacierInputType.password, autoComplete: 'current-password'));
      expect(e.keyboardType, TextInputType.visiblePassword);
      expect(e.obscureText, isTrue);
      expect(e.autocorrect, isFalse);
      expect(e.enableSuggestions, isFalse);
      expect(e.textCapitalization, TextCapitalization.none);
      expect(e.autofillHints, [AutofillHints.password]);

      e = await made(const GlacierInput(type: GlacierInputType.email));
      expect(e.keyboardType, TextInputType.emailAddress);
      expect(e.textCapitalization, TextCapitalization.none);

      e = await made(const GlacierInput(type: GlacierInputType.search));
      expect(e.textInputAction, TextInputAction.search);

      // As Ghost.md asks for its handle field and its organization's name.
      e = await made(const GlacierInput(autoComplete: 'username', autoCapitalize: TextCapitalization.none, spellCheck: false, autoCorrect: false));
      expect(e.autofillHints, [AutofillHints.username]);
      expect(e.textCapitalization, TextCapitalization.none);
      expect(e.autocorrect, isFalse);
      expect(e.spellCheckConfiguration, const SpellCheckConfiguration.disabled());

      await pumpFresh(tester, const GlacierInput(autoCapitalize: TextCapitalization.words, maxLength: 5));
      await tester.enterText(find.byType(EditableText), 'abcdefgh');
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'abcde');

      // What the platform is told when the keyboard comes up.
      await pumpFresh(tester, const GlacierInput(type: GlacierInputType.email, enterKeyHint: TextInputAction.next));
      await tester.showKeyboard(find.byType(EditableText));
      final args = tester.testTextInput.setClientArgs!;
      expect((args['inputType'] as Map)['name'], 'TextInputType.emailAddress');
      expect(args['inputAction'], 'TextInputAction.next');
    });

    testWidgets('autoFocus takes the focus and raises the keyboard', (tester) async {
      await pumpKit(tester, const GlacierInput(autoFocus: true));
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('focus arriving on its own brings no selection handle; a finger does', (tester) async {
      await pumpKit(tester, const GlacierInput(autoFocus: true, defaultValue: 'hello'));
      await tester.pump();
      EditableText editable() => tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().focusNode.hasFocus, isTrue);
      expect(editable().showSelectionHandles, isFalse);
      editable().controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      expect(editable().showSelectionHandles, isFalse, reason: 'nor does a selection the program made');

      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(editable().showSelectionHandles, isTrue);
      // A mouse is not a finger: where it next moves the caret, the handle goes.
      final mouse = await tester.startGesture(tester.getTopLeft(find.byType(EditableText)) + const Offset(20, 8), kind: PointerDeviceKind.mouse);
      await mouse.up();
      await tester.pump();
      expect(editable().showSelectionHandles, isFalse);
    });

    testWidgets('a focus node of the caller’s is the ref: focusing it focuses the field', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpKit(tester, GlacierInput(focusNode: node));
      node.requestFocus();
      await tester.pumpAndSettle();
      expect(boxOf(tester).border, testTokens().color('glacier-focus-ring'));
    });

    testWidgets('onKeyDown hears a key going down and may keep it', (tester) async {
      final keys = <LogicalKeyboardKey>[];
      await pumpKit(
        tester,
        GlacierInput(
          defaultValue: 'abc',
          onKeyDown: (event) {
            keys.add(event.logicalKey);
            return event.logicalKey == LogicalKeyboardKey.backspace ? KeyEventResult.handled : KeyEventResult.ignored;
          },
        ),
      );
      await tester.tap(find.byType(GlacierInput));
      await tester.pump();
      final controller = tester.widget<EditableText>(find.byType(EditableText)).controller;
      controller.selection = const TextSelection.collapsed(offset: 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(keys, [LogicalKeyboardKey.backspace], reason: 'down, not up');
      expect(controller.text, 'abc', reason: 'a handled key does not reach the text');

      // A key it lets by is the field's own: the hardware keyboard edits without an app around it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.selection.baseOffset, 2);
    });

    testWidgets('says what it is to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpKit(tester, const GlacierInput(ariaLabel: 'Handle', placeholder: 'yours', defaultValue: 'ada', id: 'handle'));
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node, isSemantics(isTextField: true, isEnabled: true, hasEnabledState: true, hasTapAction: true, label: 'Handle', hint: 'yours', value: 'ada', identifier: 'handle'));
      expect(node.getSemanticsData().validationResult, SemanticsValidationResult.none);

      await pumpFresh(tester, const GlacierInput(ariaLabel: 'Password', type: GlacierInputType.password, defaultValue: 'secret'));
      expect(tester.getSemantics(find.byType(EditableText)), isSemantics(isTextField: true, isObscured: true, label: 'Password'));
      handle.dispose();
    });

    testWidgets('a long press on touch selects a word and offers the kit’s own handles and menu', (tester) async {
      await pumpKit(tester, const GlacierInput(defaultValue: 'hello world'));
      await tester.longPressAt(tester.getTopLeft(find.byType(EditableText)) + const Offset(12, 8));
      await tester.pumpAndSettle();
      final controller = tester.widget<EditableText>(find.byType(EditableText)).controller;
      expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      expect(find.byType(GlacierTextSelectionToolbar), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.widget<EditableText>(find.byType(EditableText)).showSelectionHandles, isTrue);

      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(controller.text, ' world');
    });
  });
}
