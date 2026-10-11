// What a screen reader is told of the note (lib/editor/semantics/line_semantics.dart; docs/PARITY.md, Missing 12):
// each line a node with its words, a heading a header at its level, a to-do with its tick, a link a link, and the
// caret's line the text field, with the reader's own controls answered by the editor. The page's editor was read by
// the WebView; the port's drew its text and handed the phone nothing. Read from the tree the app hands the phone,
// root down, as TalkBack is given it.
import 'dart:ui' show CheckedState;

import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart' show Extension;
import 'package:ghost_md/editor/semantics/line_semantics.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:ghost_md/editor/view/line.dart';

import '../../support/render.dart';
import '../input/support.dart';

/// Every node the phone is handed, from the root down, in the order it is handed them.
List<SemanticsNode> handed(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return nodes;
}

/// The node called [label], or whose value is [label].
SemanticsNode nodeOf(WidgetTester tester, String label) {
  final found = [
    for (final node in handed(tester))
      if (node.label == label || node.value == label) node,
  ];
  expect(found, hasLength(1), reason: 'one node called "$label" among ${[for (final node in handed(tester)) if (node.label.isNotEmpty || node.value.isNotEmpty) node.label.isEmpty ? node.value : node.label]}');
  return found.single;
}

List<String> said(WidgetTester tester) => [
      for (final node in handed(tester))
        if (node.label.isNotEmpty || node.value.isNotEmpty) node.label.isEmpty ? node.value : node.label,
    ];

void act(WidgetTester tester, SemanticsNode node, SemanticsAction action, [Object? arguments]) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(node.id, action, arguments);

const note = '# Lisbon\n'
    '\n'
    'Three days in the old town.\n'
    '## What to pack\n'
    '- [ ] Sunscreen\n'
    '- [x] Tickets\n'
    'See [the guide](https://a.test/g).\n'
    'The last line';

/// The note drawn formatted, as a note is read: the marks that only style the words beside them are not drawn, and
/// so not read out.
final List<Extension> formatted = <Extension>[noteView(NoteView.formatted)];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('nothing is described while no screen reader is listening', semanticsEnabled: false, (tester) async {
    final rig = await pumpEditor(tester, note, caret: note.length);
    expect(tester.binding.renderViews.first.owner!.semanticsOwner, isNull);
    final line = tester.renderObjectList<RenderEditorLine>(find.byElementPredicate((element) => element.renderObject is RenderEditorLine)).first;
    expect(line.debugSemantics, isNull);
    // Nor as the caret moves and words are typed: nobody is asked what to say.
    await rig.place(3);
    await rig.ime.type('x');
    expect(line.debugSemantics, isNull);
    expect(tester.binding.renderViews.first.owner!.semanticsOwner, isNull);
    await finish(tester);
  });

  testWidgets('each line is a node called by its words as drawn, and an empty line says nothing', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, note, caret: note.length, more: formatted);
    final heard = said(tester);
    expect(heard, containsAllInOrder(['Lisbon', 'Three days in the old town.', 'What to pack']));
    expect(heard.where((words) => words.contains('Sunscreen')), hasLength(1));
    expect(heard, contains('The last line'));
    expect(heard.where((words) => words.trim().isEmpty), isEmpty);
    // The marks a drawn line hides are not read out.
    expect(heard.any((words) => words.startsWith('#')), isFalse);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a heading is a header at its level', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, note, caret: note.length, more: formatted);
    expect(nodeOf(tester, 'Lisbon'), matchesSemantics(label: 'Lisbon', isHeader: true, hasTapAction: true, textDirection: TextDirection.ltr));
    expect(nodeOf(tester, 'Lisbon').getSemanticsData().headingLevel, 1);
    expect(nodeOf(tester, 'What to pack'), matchesSemantics(label: 'What to pack', isHeader: true, hasTapAction: true, textDirection: TextDirection.ltr));
    expect(nodeOf(tester, 'What to pack').getSemanticsData().headingLevel, 2);
    expect(nodeOf(tester, 'Three days in the old town.').getSemanticsData().flagsCollection.isHeader, isFalse);
    expect(headingLevelOf('lineH4', '###### Deep'), 6);
    expect(headingLevelOf('lineH4', '#### Four'), 4);
    expect(headingLevelOf('lineItem', '- # not one'), 0);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a note drawn with its marks is read with them, as the page’s was: what is drawn is what is said', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, note, caret: note.length);
    expect(said(tester), containsAllInOrder(['# Lisbon', 'Three days in the old town.', '## What to pack']));
    // Still a header, at its level.
    final title = nodeOf(tester, '# Lisbon').getSemanticsData();
    expect((title.flagsCollection.isHeader, title.headingLevel), (true, 1));
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a to-do says whether it is ticked, and activating it ticks or clears its box', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpEditor(tester, note, caret: note.length);
    SemanticsNode todo(String words) => handed(tester).singleWhere((node) => node.label.contains(words));
    expect(todo('Sunscreen').getSemanticsData().flagsCollection.isChecked, CheckedState.isFalse);
    expect(todo('Tickets').getSemanticsData().flagsCollection.isChecked, CheckedState.isTrue);
    expect(todo('Sunscreen').getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    act(tester, todo('Sunscreen'), SemanticsAction.tap);
    await tester.pump();
    await tester.pump();
    expect(rig.doc, contains('- [x] Sunscreen'));
    expect(todo('Sunscreen').getSemanticsData().flagsCollection.isChecked, CheckedState.isTrue);
    act(tester, todo('Tickets'), SemanticsAction.tap);
    await tester.pump();
    expect(rig.doc, contains('- [ ] Tickets'));
    // And a long press goes into its words, to type.
    act(tester, todo('Tickets'), SemanticsAction.longPress);
    await tester.pump();
    expect(rig.head, rig.at('Tickets') + 'Tickets'.length);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a link is a node of its own in its line, called by its words, and activating it opens its address', (tester) async {
    final handle = tester.ensureSemantics();
    final opened = <String>[];
    final rig = await pumpEditor(tester, note, caret: note.length, more: [semanticsOpenLink.of(opened.add)]);
    final line = handed(tester).singleWhere((node) => node.label.startsWith('See'));
    final inside = <SemanticsNode>[];
    line.visitChildren((child) {
      inside.add(child);
      return true;
    });
    final link = inside.singleWhere((node) => node.getSemanticsData().flagsCollection.isLink);
    expect(link.label, 'the guide');
    expect(link.getSemanticsData().linkUrl, Uri.parse('https://a.test/g'));
    // Where the link is on the page: round its words and its marks as drawn, wherever the line wraps, and inside
    // its line.
    final render = tester.renderObjectList<RenderEditorLine>(find.byElementPredicate((element) => element.renderObject is RenderEditorLine)).firstWhere((each) => each.spec.projection.source.startsWith('See'));
    final box = link.rect.shift(render.localToGlobal(Offset.zero)).inflate(1);
    final start = rig.view.coordsAtPos(rig.at('[the guide]'))!, end = rig.view.coordsAtPos(rig.at('g).', 2), -1)!;
    expect(box.contains(start.center), isTrue, reason: '$box holds the link\'s first letter at $start');
    expect(box.contains(end.center.translate(-2, 0)), isTrue, reason: '$box holds its last at $end');
    expect(link.rect.width, lessThanOrEqualTo(render.size.width));
    expect(link.rect.height, lessThanOrEqualTo(render.size.height));
    expect(link.rect.height, lessThan(render.size.height + 1));
    act(tester, link, SemanticsAction.tap);
    expect(opened, ['https://a.test/g']);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('the line the caret is on is the text field: focused, its words its value, the selection in them', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpEditor(tester, note, caret: note.length - 4);
    await tester.pump();
    final field = nodeOf(tester, 'The last line');
    expect(
      field,
      matchesSemantics(
        value: 'The last line',
        isTextField: true,
        isMultiline: true,
        isFocused: true,
        isFocusable: true,
        textDirection: TextDirection.ltr,
        hasSetSelectionAction: true,
        hasMoveCursorForwardByCharacterAction: true,
        hasMoveCursorBackwardByCharacterAction: true,
        hasMoveCursorForwardByWordAction: true,
        hasMoveCursorBackwardByWordAction: true,
      ),
    );
    expect(field.getSemanticsData().textSelection, const TextSelection.collapsed(offset: 9));
    // Only that line: the rest are words to read, not edit boxes.
    expect(handed(tester).where((node) => node.getSemanticsData().flagsCollection.isTextField), hasLength(1));

    // A selection made by the keyboard or a finger is reported in the line's own words.
    await rig.place(rig.at('The last'), rig.at('The last') + 3);
    expect(nodeOf(tester, 'The last line').getSemanticsData().textSelection, const TextSelection(baseOffset: 0, extentOffset: 3));
    // And the caret gone to another line takes the field with it.
    await rig.place(rig.at('Three days') + 5);
    expect(nodeOf(tester, 'Three days in the old town.').getSemanticsData().flagsCollection.isTextField, isTrue);
    expect(nodeOf(tester, 'The last line').getSemanticsData().flagsCollection.isTextField, isFalse);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('the reader’s own controls move the editor’s caret: set the selection, by a character, by a word, extending', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpEditor(tester, note, caret: note.length);
    await tester.pump();
    final start = rig.at('The last line');
    SemanticsNode field() => nodeOf(tester, 'The last line');

    act(tester, field(), SemanticsAction.setSelection, <String, int>{'base': 4, 'extent': 8});
    await tester.pump();
    expect((rig.anchor, rig.head), (start + 4, start + 8));
    expect(field().getSemanticsData().textSelection, const TextSelection(baseOffset: 4, extentOffset: 8));

    act(tester, field(), SemanticsAction.setSelection, <String, int>{'base': 13, 'extent': 13});
    await tester.pump();
    act(tester, field(), SemanticsAction.moveCursorBackwardByCharacter, false);
    await tester.pump();
    expect((rig.anchor, rig.head), (start + 12, start + 12));
    act(tester, field(), SemanticsAction.moveCursorBackwardByWord, false);
    await tester.pump();
    expect(rig.head, start + 9, reason: 'to the start of "line"');
    act(tester, field(), SemanticsAction.moveCursorBackwardByWord, true);
    await tester.pump();
    expect((rig.anchor, rig.head), (start + 9, start + 4), reason: 'extended back over "last "');
    act(tester, field(), SemanticsAction.moveCursorForwardByCharacter, false);
    await tester.pump();
    expect(rig.view.state.selection.main.empty, isTrue);
    act(tester, field(), SemanticsAction.moveCursorForwardByWord, true);
    await tester.pump();
    expect(rig.view.state.selection.main.empty, isFalse);
    expect(rig.head, greaterThan(rig.anchor));
    handle.dispose();
    await finish(tester);
  });

  testWidgets('another line activated takes the caret to its end, and the keyboard', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpEditor(tester, note, caret: note.length, focus: false);
    expect(handed(tester).where((node) => node.getSemanticsData().flagsCollection.isTextField), isEmpty, reason: 'no caret anywhere until the note has the keyboard');
    act(tester, nodeOf(tester, 'Three days in the old town.'), SemanticsAction.tap);
    await tester.pump();
    await tester.pump();
    expect(rig.head, rig.at('old town.') + 'old town.'.length);
    expect(rig.view.hasFocus, isTrue);
    expect(nodeOf(tester, 'Three days in the old town.').getSemanticsData().flagsCollection.isTextField, isTrue);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a note that cannot be typed in is read and offers nothing to do', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, note, readOnly: true, focus: false, more: formatted);
    final line = nodeOf(tester, 'Three days in the old town.');
    expect(line.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(nodeOf(tester, 'Lisbon').getSemanticsData().flagsCollection.isHeader, isTrue);
    expect(handed(tester).where((node) => node.getSemanticsData().flagsCollection.isTextField), isEmpty);
    handle.dispose();
    await finish(tester);
  });
}
