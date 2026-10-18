import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/band/band.dart';
import 'package:ghost_md/editor/commands/format.dart' show insertLink;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/note/format_bar.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// Simple mode's Format bar (lib/note/format_bar.dart, GHST-103): six of the Style page's rows pressed from outside
/// the band, over a real editor. Where the note's screen stands it is test/note/note_format_bar_test.dart.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  const six = <String>['Bold', 'Italic', 'Heading', 'List', 'To-do', 'Link'];

  Future<EditorView> pumpBar(WidgetTester tester, {required String doc, int anchor = 0, int? head, FormatBarLook look = FormatBarLook.strip, List<HapticKind>? felt}) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, selection: EditorSelection.single(anchor, head), extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Column(
            children: [
              Expanded(child: SingleChildScrollView(child: EditorColumn(view: view))),
              FormatBar(view: view, look: look, felt: felt?.add),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return view;
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label));
    await tester.pump();
  }

  /// Whether the button that says [label] is lit: told to a screen reader as toggled.
  bool lit(WidgetTester tester, String label) {
    final tool = formatBarTools().singleWhere((one) => one.label == label);
    return tester.widget<GlacierPressable>(find.descendant(of: find.byKey(FormatBar.keyOf(tool)), matching: find.byType(GlacierPressable))).toggled ?? false;
  }

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('carries six: Bold, Italic, Heading, List, To-do, Link, each said with its hint', (tester) async {
    await pumpBar(tester, doc: 'buy milk');
    for (final word in six) {
      expect(find.bySemanticsLabel(word), findsOneWidget, reason: word);
    }
    expect(tester.getSemantics(find.bySemanticsLabel('Heading')).hint, 'A title for a section');
    expect(tester.getSemantics(find.bySemanticsLabel('To-do')).hint, 'A box to tick');
    expect(find.byKey(FormatBar.stripKey), findsOneWidget);
    // In the order the tools list them, which is the bar's.
    expect([for (final tool in formatBarTools()) tool.label], six);
    await away(tester);
  });

  testWidgets('Bold wraps the selected word in two stars, and is lit while the caret is in it', (tester) async {
    final felt = <HapticKind>[];
    final view = await pumpBar(tester, doc: 'buy milk', anchor: 4, head: 8, felt: felt);
    expect(lit(tester, 'Bold'), isFalse);
    await press(tester, 'Bold');
    expect(view.state.doc.toString(), 'buy **milk**');
    expect(lit(tester, 'Bold'), isTrue);
    expect(felt, <HapticKind>[HapticKind.selection]);
    // Pressed again, the stars come off.
    await press(tester, 'Bold');
    expect(view.state.doc.toString(), 'buy milk');
    expect(lit(tester, 'Bold'), isFalse);
    await away(tester);
  });

  testWidgets('To-do makes a plain line a box to tick, Heading a title, List a bullet; each lit on its line, and off again', (tester) async {
    final view = await pumpBar(tester, doc: 'buy milk', anchor: 2);
    await press(tester, 'To-do');
    expect(view.state.doc.toString(), '- [ ] buy milk');
    expect(lit(tester, 'To-do'), isTrue);
    expect(lit(tester, 'List'), isFalse);
    await press(tester, 'To-do');
    expect(view.state.doc.toString(), 'buy milk');
    expect(lit(tester, 'To-do'), isFalse);
    await press(tester, 'Heading');
    expect(view.state.doc.toString(), '# buy milk');
    expect(lit(tester, 'Heading'), isTrue);
    await press(tester, 'Heading');
    expect(view.state.doc.toString(), 'buy milk');
    await press(tester, 'List');
    expect(view.state.doc.toString(), '- buy milk');
    expect(lit(tester, 'List'), isTrue);
    await press(tester, 'List');
    expect(view.state.doc.toString(), 'buy milk');
    await away(tester);
  });

  testWidgets('Link wraps the selection as a link, the same as the Style page’s Link', (tester) async {
    final view = await pumpBar(tester, doc: 'buy milk', anchor: 4, head: 8);
    final page = EditorState.create(doc: 'buy milk', selection: EditorSelection.single(4, 8), extensions: noteExtensions());
    final want = insertLink(page).state.doc.toString();
    await press(tester, 'Link');
    expect(view.state.doc.toString(), want);
    expect(view.state.doc.toString(), contains('[milk]('));
    await away(tester);
  });

  testWidgets('follows the caret: moving it into a heading lights Heading without a press', (tester) async {
    final view = await pumpBar(tester, doc: '# Title\n\nwords', anchor: 10);
    expect(lit(tester, 'Heading'), isFalse);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(2)));
    await tester.pump();
    expect(lit(tester, 'Heading'), isTrue);
    await away(tester);
  });

  testWidgets('a press asks for no focus of its own', (tester) async {
    await pumpBar(tester, doc: 'buy milk', anchor: 4, head: 8);
    for (final tool in formatBarTools()) {
      expect(tester.widget<GlacierPressable>(find.descendant(of: find.byKey(FormatBar.keyOf(tool)), matching: find.byType(GlacierPressable))).canRequestFocus, isFalse, reason: tool.label);
    }
    await away(tester);
  });

  testWidgets('the pill is the dock’s own hand: rings of the dock’s size in a pill of glass; the row has no paper of its own', (tester) async {
    await pumpBar(tester, doc: 'buy milk', look: FormatBarLook.pill);
    expect(find.byKey(FormatBar.pillKey), findsOneWidget);
    final t = GlacierTheme.of(tester.element(find.byKey(FormatBar.pillKey)));
    final bold = tester.getSize(find.byKey(FormatBar.keyOf(formatBarTools().first)));
    expect(bold.width, closeTo(t.len('app-ring'), 0.01));
    expect(bold.height, closeTo(t.len('app-ring'), 0.01));
    expect(find.byType(BackdropFilter), findsOneWidget);
    await away(tester);

    await pumpBar(tester, doc: 'buy milk', look: FormatBarLook.row);
    expect(find.byKey(FormatBar.rowKey), findsOneWidget);
    expect(find.byKey(FormatBar.stripKey), findsNothing);
    expect(tester.getSize(find.byKey(FormatBar.keyOf(formatBarTools().first))), const Size(formatBarHeight, formatBarHeight));
    await away(tester);
  });

  testWidgets('on a desktop a hint comes up over the button while the pointer rests there', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpBar(tester, doc: 'buy milk', look: FormatBarLook.pill);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(FormatBar.keyOf(formatBarTools()[2]))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('band-tip')), findsOneWidget);
    expect(find.text('A title for a section'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.byKey(const ValueKey('band-tip')), findsNothing);
    await away(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
