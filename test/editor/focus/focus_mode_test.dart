// Focus mode (Matt, 2026-10-27: "build ... focus mode"): every block but the caret's dimmed while the note is being
// written in, a fade between them, nothing dimmed unfocused or switched off, and the typewriter scroll that keeps the
// caret's line in the middle of the page. The pictures, before and after, are shots/focus-mode-off.png and
// shots/focus-mode-on.png.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/focus/focus_mode.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/sliver.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

class _Page extends StatelessWidget {
  const _Page(this.view, this.controller);
  final EditorView view;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.color('glacier-bg'),
    child: CustomScrollView(controller: controller, slivers: [EditorSliver(view: view)]),
  );
}

/// The switches as a store would hold them.
class _Switches extends ChangeNotifier {
  bool dim = true;
  bool typewriter = true;
  void set({bool? dim, bool? typewriter}) {
    this.dim = dim ?? this.dim;
    this.typewriter = typewriter ?? this.typewriter;
    notifyListeners();
  }
}

Future<(EditorView, ScrollController, _Switches)> _pump(WidgetTester tester, String doc, {bool still = true, bool dim = true}) async {
  final switches = _Switches()..dim = dim;
  final view = EditorView(
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(more: [focusMode(FocusModeHooks(dim: () => switches.dim, typewriter: () => switches.typewriter, changes: switches, still: still))]),
    ),
  );
  final controller = ScrollController();
  addTearDown(view.destroy);
  addTearDown(controller.dispose);
  await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), ratio: 2, home: _Page(view, controller));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  return (view, controller, switches);
}

FocusDim _dim(EditorView view) => view.state.facet(viewPlugin).map(view.plugin).whereType<FocusDim>().single;

const String _note = '# A title\n'
    '\n'
    'The first paragraph, its first line\n'
    'and its second.\n'
    '\n'
    '- an item\n'
    '- another item\n'
    '\n'
    'The last paragraph.';

void main() {
  // The pictures in the app's own faces, not the test's blocks.
  setUpAll(loadAppFonts);

  test('a block is the leaf block round the caret, or its blank line', () {
    final state = EditorState.create(doc: _note, extensions: noteExtensions());
    int at(String text) => _note.indexOf(text);
    ({int first, int last}) lines(int pos) => focusLinesOf(state, EditorSelection.cursor(pos));
    expect(lines(at('A title')), (first: 1, last: 1));
    expect(lines(at('second')), (first: 3, last: 4));
    expect(lines(at('The first')), (first: 3, last: 4));
    // The end of a paragraph is in it.
    expect(lines(at('and its second.') + 'and its second.'.length), (first: 3, last: 4));
    expect(lines(at('another')), (first: 7, last: 7));
    expect(lines(at('an item')), (first: 6, last: 6));
    // A blank line is a block of its own.
    expect(lines(at('\n\n- an') + 1), (first: 5, last: 5));
    // A selection lights every block it touches.
    expect(focusLinesOf(state, EditorSelection.range(at('second'), at('an item'))), (first: 3, last: 6));
  });

  testWidgets("the caret's block keeps its ink and the rest dim, only while the editor has focus", (tester) async {
    final (view, _, switches) = await _pump(tester, _note);
    final dim = _dim(view);
    // Unfocused: nothing dimmed.
    view.dispatch(TransactionSpec(selection: EditorSelection.single(_note.indexOf('second'))));
    await tester.pump();
    expect(dim.litLines, isNull);
    expect(dim.dims, isFalse);
    expect(tester.layers.whereType<OpacityLayer>(), isEmpty);

    view.setFocused(true);
    await tester.pump();
    expect(dim.litLines, (first: 3, last: 4));
    for (final line in [1, 2, 5, 6, 7, 9]) {
      expect(dim.opacityOf(line, line), focusDimOpacity, reason: 'line $line');
    }
    expect(dim.opacityOf(3, 3), 1);
    expect(dim.opacityOf(4, 4), 1);
    // Painted so: every entry but the paragraph's two lines through a layer at the dimmed opacity.
    final alphas = tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha).toList();
    expect(alphas, hasLength(7));
    expect(alphas.toSet(), {(focusDimOpacity * 255).round()});

    // The caret moves to the list's second item: that item alone.
    view.dispatch(TransactionSpec(selection: EditorSelection.single(_note.indexOf('another'))));
    await tester.pump();
    expect(dim.litLines, (first: 7, last: 7));
    expect(dim.opacityOf(6, 6), focusDimOpacity);
    expect(dim.opacityOf(3, 4), focusDimOpacity);

    // Focus gone: drawn whole again.
    view.setFocused(false);
    await tester.pump();
    expect(dim.litLines, isNull);
    expect(dim.opacityOf(1, 1), 1);
    expect(tester.layers.whereType<OpacityLayer>(), isEmpty);

    // Switched off while focused: nothing; switched on: dimmed at once, with no editor made again.
    view.setFocused(true);
    switches.set(dim: false);
    await tester.pump();
    expect(dim.litLines, isNull);
    expect(tester.layers.whereType<OpacityLayer>(), isEmpty);
    switches.set(dim: true);
    await tester.pump();
    expect(dim.litLines, (first: 7, last: 7));
    expect(tester.layers.whereType<OpacityLayer>(), isNotEmpty);
    expect(identical(_dim(view), dim), isTrue);
    debugDisableShadows = true;
  });

  testWidgets('a block fades as the caret leaves it, at the pace; reduce motion changes it at once', (tester) async {
    final (view, _, _) = await _pump(tester, _note, still: false);
    final dim = _dim(view);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(_note.indexOf('second'))));
    view.setFocused(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(dim.fading, isFalse);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(_note.indexOf('The last'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(dim.fading, isTrue);
    // The paragraph left on its way down, the last on its way up.
    expect(dim.opacityOf(3, 3), inExclusiveRange(focusDimOpacity, 1));
    expect(dim.opacityOf(9, 9), inExclusiveRange(focusDimOpacity, 1));
    // A block neither was stays dimmed.
    expect(dim.opacityOf(1, 1), focusDimOpacity);
    await tester.pump(const Duration(milliseconds: 200));
    expect(dim.fading, isFalse);
    expect(dim.opacityOf(3, 3), focusDimOpacity);
    expect(dim.opacityOf(9, 9), 1);
    debugDisableShadows = true;
  });

  testWidgets("the typewriter keeps the caret's line in the middle of the page as it is typed", (tester) async {
    final doc = List<String>.generate(120, (i) => 'Paragraph ${i + 1}, a line of its own.').join('\n\n');
    final (view, controller, switches) = await _pump(tester, doc);
    view.setFocused(true);
    Future<double> caretMiddle(int pos, {String userEvent = 'input.type'}) async {
      view.dispatch(TransactionSpec(selection: EditorSelection.single(pos), scrollIntoView: true, userEvent: userEvent));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final caret = view.coordsAtPos(view.state.selection.main.head)!;
      return caret.center.dy;
    }

    // The page is 844 tall: the line stands in its middle, a pixel or two either way.
    final middle = tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
    expect(await caretMiddle(doc.indexOf('Paragraph 60,')), closeTo(middle, 2));
    expect(controller.offset, greaterThan(1000));
    // Typed on a line further down: still the middle.
    final pos = doc.indexOf('Paragraph 61,');
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: pos, insert: 'Now '), selection: EditorSelection.single(pos + 4), scrollIntoView: true, userEvent: 'input.type'));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(view.coordsAtPos(pos + 4)!.center.dy, closeTo(middle, 2));

    // A tap puts the caret where it lands: the page does not move.
    final before = controller.offset;
    final tapped = view.posAtCoords(const Offset(60, 120), precise: false)!;
    await caretMiddle(tapped, userEvent: 'select.pointer');
    expect(controller.offset, before);

    // Typewriter off: the least move again, which leaves a line in sight where it is.
    switches.set(typewriter: false);
    final near = view.posAtCoords(const Offset(60, 200), precise: false)!;
    final at = await caretMiddle(near);
    expect(at, closeTo(200, 30));
    debugDisableShadows = true;
  });

  testWidgets('before and after', (tester) async {
    final (view, _, switches) = await _pump(tester, _note);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(_note.indexOf('second'))));
    view.setFocused(true);
    switches.set(dim: false);
    await tester.pump();
    await expectLater(find.byType(_Page), matchesGoldenFile('shots/focus-mode-off.png'));
    switches.set(dim: true);
    await tester.pump();
    await expectLater(find.byType(_Page), matchesGoldenFile('shots/focus-mode-on.png'));
    debugDisableShadows = true;
  });
}
