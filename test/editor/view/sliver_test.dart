// The editor in a scroll view: only what is on screen is built and laid out, a change lays out the line it
// touched, lines follow the document's changes, and a position is scrolled into view. With the numbers for a note
// of 380 kB.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/decoration.dart' as cm;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/sliver.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

/// A note of about [bytes]: headings, paragraphs that wrap, lists, to-dos, quotes and code, over and over.
String bigNote(int bytes) {
  final out = StringBuffer();
  var n = 0;
  while (out.length < bytes) {
    n += 1;
    out
      ..writeln('## Section $n')
      ..writeln()
      ..writeln('The quick brown fox jumps over the lazy dog, then turns round and does it again for the **sign-in** page, _${n}_ times.')
      ..writeln()
      ..writeln('- one thing for section $n')
      ..writeln('- [ ] a to-do with a [link](https://example.com/a/$n) in it')
      ..writeln('- [x] and one that is done')
      ..writeln()
      ..writeln('> quoted words, number $n')
      ..writeln()
      ..writeln('```')
      ..writeln('const section = $n;')
      ..writeln('```')
      ..writeln();
  }
  return out.toString();
}

class _Page extends StatelessWidget {
  const _Page(this.view, this.controller);
  final EditorView view;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.color('glacier-bg'),
    child: CustomScrollView(
      controller: controller,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 60, child: Text('the note\'s bar'))),
        EditorSliver(view: view),
      ],
    ),
  );
}

Future<(EditorView, ScrollController)> pumpNote(WidgetTester tester, String doc, {List<Extension> more = const [], bool readOnly = false}) async {
  final view = EditorView(state: EditorState.create(doc: doc, extensions: noteExtensions(more: more, readOnly: readOnly)));
  final controller = ScrollController();
  addTearDown(view.destroy);
  addTearDown(controller.dispose);
  await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), ratio: 2, home: _Page(view, controller));
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump();
  return (view, controller);
}

List<RenderEditorLine> drawn(WidgetTester tester) => tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);

class _Banner extends EditorWidget {
  const _Banner(this.label, this.height);
  final String label;
  final double height;

  @override
  bool eq(_Banner other) => other.label == label && other.height == height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: Text(label, key: ValueKey('banner-$label')));
}

class _Dot extends EditorWidget {
  const _Dot(this.size);
  final double size;

  @override
  bool eq(_Dot other) => other.size == size;

  @override
  Widget build(BuildContext context) => SizedBox(key: const ValueKey('dot'), width: size, height: size);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('builds and lays out the lines on screen and a little round them, wherever the note is scrolled to', (tester) async {
    final doc = bigNote(60000);
    final (view, controller) = await pumpNote(tester, doc);
    final lines = view.state.doc.lines;
    expect(lines, greaterThan(1000));
    var built = drawn(tester);
    // A screen 844 tall and the scroll view's cache either side: tens of lines, not the note's thousand.
    expect(built.length, inInclusiveRange(20, 90));
    expect(built.first.from, 0);
    expect(view.viewport.from, 0);
    expect(view.viewport.to, lessThan(doc.length ~/ 4));
    // The note's whole length is known from the start, by estimate.
    expect(controller.position.maxScrollExtent, greaterThan(lines * 20));

    // To the middle: nothing between here and there is laid out on the way.
    final before = RenderEditorLine.layouts;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pump();
    await tester.pump();
    built = drawn(tester);
    expect(built.length, inInclusiveRange(20, 90));
    expect(RenderEditorLine.layouts - before, lessThan(200));
    final middle = view.state.doc.lineAt(built[built.length ~/ 2].from).number;
    expect(middle, inInclusiveRange(lines ~/ 2 - lines ~/ 5, lines ~/ 2 + lines ~/ 5));
    expect(view.viewport.from, lessThanOrEqualTo(built.first.from));
    expect(view.viewport.to, greaterThanOrEqualTo(built.last.to));
    // What is on screen answers where it is; what is not, does not.
    expect(view.coordsAtPos(built[built.length ~/ 2].from), isNotNull);
    expect(view.coordsAtPos(0), isNull);
    debugDisableShadows = true;
  });

  testWidgets('a keystroke lays out the line it is on and no other; a new line moves the ones under it without laying them out', (tester) async {
    final (view, _) = await pumpNote(tester, bigNote(20000));
    final target = drawn(tester)[6];
    var before = RenderEditorLine.layouts;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: target.from + 1, insert: 'x'), userEvent: 'input.type'));
    await tester.pump();
    await tester.pump();
    expect(RenderEditorLine.layouts - before, 1);
    expect(drawn(tester)[6].spec.projection.source, contains('x'));

    // Enter at the end of that line: one new line is laid out, and the lines below keep their render objects.
    final below = drawn(tester)[9];
    final belowTop = below.localToGlobal(Offset.zero).dy;
    before = RenderEditorLine.layouts;
    final end = drawn(tester)[6].to;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: end, insert: '\n'), userEvent: 'input'));
    await tester.pump();
    await tester.pump();
    expect(RenderEditorLine.layouts - before, lessThanOrEqualTo(2));
    expect(below.attached, isTrue);
    expect(below.from, greaterThan(end));
    expect(below.localToGlobal(Offset.zero).dy, greaterThan(belowTop));
    debugDisableShadows = true;
  });

  testWidgets('scrolls a position into view, measured or not, and keeps the selection it is given', (tester) async {
    final doc = bigNote(40000);
    final (view, controller) = await pumpNote(tester, doc);
    final pos = doc.indexOf('## Section 120');
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(pos), scrollIntoView: true));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    final caret = view.coordsAtPos(pos);
    expect(caret, isNotNull);
    expect(caret!.top, inInclusiveRange(0, 844));
    expect(caret.bottom, inInclusiveRange(0, 844));
    expect(controller.offset, greaterThan(1000));
    // The caret's line draws the caret; the handles' links are for a selection.
    expect(drawn(tester).where((line) => line.selection.carets.isNotEmpty).length, 1);
    // To the start again, by effect.
    view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(0, y: ScrollStrategy.start)));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(view.coordsAtPos(0), isNotNull);
    debugDisableShadows = true;
  });

  testWidgets('block widgets stand before, after and in place of lines, an inline widget in a line, and a tap finds them', (tester) async {
    const doc = 'one\ntwo\nthree\nfour\nfive\nsix';
    final field = StateField.define<cm.DecorationSet>(
      create: (state) => cm.Decoration.set(<Range<cm.Decoration>>[
        cm.Decoration.widget(widget: const _Banner('before', 30), block: true, side: -1).range(0),
        cm.Decoration.widget(widget: const _Dot(12), side: 1).range(2),
        cm.Decoration.widget(widget: const _Banner('after', 20), block: true, side: 1).range(7),
        cm.Decoration.replace(widget: const _Banner('instead', 50), block: true).range(8, 18),
      ]),
      update: (value, tr) => value.map(tr.changes),
      provide: (field) => EditorViewLike.decorations.from(field),
    );
    final (view, _) = await pumpNote(tester, doc, more: [field]);
    final lines = drawn(tester);
    // "three" and "four" are under the block that replaces them.
    expect([for (final line in lines) line.spec.projection.source], ['one', 'two', 'five', 'six']);
    expect(view.visibleRanges, [const DocRange(0, 8), DocRange(18, doc.length)]);
    final top = lines[0].localToGlobal(Offset.zero).dy;
    final before = tester.getRect(find.byKey(const ValueKey('banner-before')));
    expect(before.bottom, closeTo(top, 0.01));
    expect(before.height, 30);
    final after = tester.getRect(find.byKey(const ValueKey('banner-after')));
    expect(after.top, closeTo(lines[1].localToGlobal(Offset.zero).dy + lines[1].size.height, 0.01));
    final instead = tester.getRect(find.byKey(const ValueKey('banner-instead')));
    expect(instead.top, closeTo(after.bottom, 0.01));
    expect(lines[2].localToGlobal(Offset.zero).dy, closeTo(instead.bottom, 0.01));
    // The dot is in the first line, after "on", and the words go round it.
    final dot = tester.getRect(find.byKey(const ValueKey('dot')));
    final o = view.coordsAtPos(2, -1)!, e = view.coordsAtPos(2, 1)!;
    // A widget on the far side of its position: the caret there is before it, whichever way it leans.
    expect(dot.left, closeTo(o.left, 0.01));
    expect(e.left, closeTo(dot.left, 0.01));
    expect(view.coordsAtPos(3)!.left, greaterThan(dot.right + 5), reason: 'the "e" is drawn past the dot');
    expect(dot.bottom, closeTo(o.bottom - lines[0].spec.look.base.descent, 0.01), reason: 'a box with no words in it sits on the baseline');
    // A point on the replacing block is its range's start or end; one under a block is the block's widget.
    final hit = view.hitAt(instead.center - const Offset(0, 10))!;
    expect([hit.pos, hit.block is _Banner], [8, true]);
    expect(view.hitAt(instead.center + const Offset(0, 10))!.pos, 18);
    expect(view.hitAt(dot.center)!.widget, isA<_Dot>());
    // A position under the block is at the block's edge.
    expect(view.coordsAtPos(12)!.top, closeTo(instead.top, 0.01));
    debugDisableShadows = true;
  });

  testWidgets('a note of 380 kB: what a first screen, a scroll and a keystroke cost', (tester) async {
    final doc = bigNote(380000);
    final clock = Stopwatch()..start();
    final state = EditorState.create(doc: doc, extensions: noteExtensions());
    final made = clock.elapsedMicroseconds;
    final view = EditorView(state: state);
    final controller = ScrollController();
    addTearDown(view.destroy);
    addTearDown(controller.dispose);
    await pumpApp(tester, prefs: const AppPreferences(theme: 'light'), ratio: 2, home: _Page(view, controller));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump();
    final lines = view.state.doc.lines;
    final first = drawn(tester).length;

    // A keystroke in a line on screen.
    final target = drawn(tester)[8];
    final times = <int>[];
    final laidOut = <int>[];
    for (var i = 0; i < 12; i++) {
      final before = RenderEditorLine.layouts;
      clock.reset();
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: target.from + 1 + i, insert: 'x'), userEvent: 'input.type'));
      final dispatched = clock.elapsedMicroseconds;
      await tester.pump();
      times.add(clock.elapsedMicroseconds);
      laidOut.add(RenderEditorLine.layouts - before);
      if (i == 0) {
        // ignore: avoid_print
        print('  first keystroke: dispatch ${dispatched / 1000} ms');
      }
      await tester.pump();
    }
    times.sort();

    // A scroll down the note, a screen at a time.
    final scrollTimes = <int>[];
    final scrollLayouts = <int>[];
    for (var i = 1; i <= 12; i++) {
      final before = RenderEditorLine.layouts;
      clock.reset();
      controller.jumpTo(i * 700.0);
      await tester.pump();
      scrollTimes.add(clock.elapsedMicroseconds);
      scrollLayouts.add(RenderEditorLine.layouts - before);
      await tester.pump();
    }
    scrollTimes.sort();
    // And a jump to the far end.
    var before = RenderEditorLine.layouts;
    clock.reset();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    final jump = clock.elapsedMicroseconds;
    final jumpLayouts = RenderEditorLine.layouts - before;
    before = RenderEditorLine.layouts;

    // ignore: avoid_print
    print(
      '380 kB note: ${doc.length} units, $lines lines\n'
      '  state made (parse and fields): ${made / 1000} ms\n'
      '  lines built for the first screen: $first of $lines\n'
      '  a keystroke, dispatch and frame: median ${times[times.length ~/ 2] / 1000} ms, worst ${times.last / 1000} ms; lines laid out ${laidOut.toSet()}\n'
      '  a screen scrolled, one frame: median ${scrollTimes[scrollTimes.length ~/ 2] / 1000} ms, worst ${scrollTimes.last / 1000} ms; lines laid out ${scrollLayouts.reduce((a, b) => a > b ? a : b)} at most\n'
      '  a jump to the end: ${jump / 1000} ms, $jumpLayouts lines laid out',
    );
    expect(first, lessThan(100));
    expect(laidOut.every((n) => n == 1), isTrue, reason: 'a keystroke lays out its own line: $laidOut');
    expect(scrollLayouts.every((n) => n < 120), isTrue, reason: 'a screen scrolled lays out a screen: $scrollLayouts');
    expect(jumpLayouts, lessThan(200));
    debugDisableShadows = true;
  });
}
