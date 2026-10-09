// What a line shows, from what it holds: the segments, and the maps between the document, the shown text and the
// text the paragraph is given.
import 'package:flutter/widgets.dart' show BuildContext, SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/state/rangeset.dart';
import 'package:ghost_md/editor/view/decoration.dart';
import 'package:ghost_md/editor/view/line_breaks.dart';
import 'package:ghost_md/editor/view/projection.dart';
import 'package:ghost_md/editor/view/widget.dart';

class _W extends EditorWidget {
  const _W(this.name);
  final String name;

  @override
  bool eq(_W other) => other.name == name;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

DecorationSet set(List<Range<Decoration>> ranges) => Decoration.set(ranges, true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a line with nothing over it is its own text', () {
    final line = LineProjection.plain('some words');
    expect(line.display, 'some words');
    expect(line.segments.single.kind, SegmentKind.text);
    expect([line.toDisplay(0), line.toDisplay(4), line.toDisplay(10)], [0, 4, 10]);
    expect([line.toDoc(0), line.toDoc(4), line.toDoc(10)], [0, 4, 10]);
    expect(LineProjection.plain('').isEmpty, isTrue);
  });

  test('marks nest outermost first, and a line’s decorations give it its classes and attributes', () {
    // The line starts 100 into the document.
    final bold = Decoration.mark(className: 'strong'), mark = Decoration.mark(className: 'strong mark'), name = Decoration.mark(className: 'cm-name');
    final line = LineProjection.build('a **b** c', 100, [
      set([
        Decoration.line(className: 'lineItem', attributes: const {'style': '--hang: 12.00px'}).range(100),
        Decoration.line(className: 'lineQuote', attributes: const {'style': '--x: 1px', 'data-callout': 'note'}).range(100),
        mark.range(102, 104),
        bold.range(104, 105),
        mark.range(105, 107),
      ]),
      set([name.range(102, 107)]),
    ]);
    expect(line.className, 'lineItem lineQuote');
    expect(line.attributes['data-callout'], 'note');
    expect(line.attributes['style'], contains('--hang: 12.00px'));
    expect(line.attributes['style'], contains('--x: 1px'));
    // "Nesting order is determined by precedence of the facet, with the higher-precedence decorations creating the
    // inner DOM nodes": the first set's marks are inside the second's.
    expect([for (final seg in line.segments) '${seg.from}-${seg.to} ${seg.marks.map((m) => m.attrs['class']).join('>')}'], ['0-2 ', '2-4 cm-name>strong mark', '4-5 cm-name>strong', '5-7 cm-name>strong mark', '7-9 ']);
    // A line decoration elsewhere in the range is another line's.
    expect(LineProjection.build('ab', 0, [set([Decoration.line(className: 'x').range(1)])]).className, '');
  });

  test('what is hidden is left out, and its positions are one place', () {
    final hide = Decoration.replace();
    // "# One" with "# " hidden, "**b**" with its stars hidden.
    final line = LineProjection.build('# One **b** x', 0, [
      set([hide.range(0, 2), hide.range(6, 8), hide.range(9, 11)]),
    ]);
    expect(line.display, 'One b x');
    expect([for (final seg in line.segments) seg.kind.name], ['hidden', 'text', 'hidden', 'text', 'hidden', 'text']);
    // Into the shown text: every position of a hidden range is where the range was.
    expect([for (var pos = 0; pos <= 13; pos++) line.toDisplay(pos)], [0, 0, 0, 1, 2, 3, 4, 4, 4, 5, 5, 5, 6, 7]);
    // And back: the first or the last of the positions that are one place.
    expect([line.toDoc(0, -1), line.toDoc(0, 1)], [0, 2]);
    expect([line.toDoc(4, -1), line.toDoc(4, 1)], [6, 8]);
    expect([line.toDoc(5, -1), line.toDoc(5, 1)], [9, 11]);
    expect([line.toDoc(2, -1), line.toDoc(2, 1)], [4, 4]);
    // The segment a caret is drawn by: the one it is in, or the one on the side it leans.
    expect(line.segmentAt(1)!.kind, SegmentKind.hidden);
    expect(line.segmentAt(2, -1)!.kind, SegmentKind.hidden);
    expect(line.segmentAt(2, 1)!.kind, SegmentKind.text);
    expect(line.segmentAt(13, 1)!.kind, SegmentKind.text);
  });

  test('a widget takes one place: at a position, on the side its decoration says, or instead of a range', () {
    final line = LineProjection.build('ab :tada: cd', 0, [
      set([
        Decoration.widget(widget: const _W('before'), side: -1).range(1),
        Decoration.widget(widget: const _W('after'), side: 1).range(1),
        Decoration.replace(widget: const _W('emoji')).range(3, 9),
      ]),
    ]);
    expect(line.display, 'a$widgetPlaceholder${widgetPlaceholder}b $widgetPlaceholder cd');
    final widgets = [for (final seg in line.segments) if (seg.kind == SegmentKind.widget) seg];
    expect([for (final w in widgets) (w.widget! as _W).name], ['before', 'after', 'emoji']);
    expect([for (final w in widgets) w.side], [-1, 1, 0]);
    // The caret at 1 is after the widget that is before it and before the one that is after it.
    expect([line.toDisplay(1, -1), line.toDisplay(1, 1)], [2, 2]);
    expect(line.toDisplay(2), 4);
    // A replaced range: its start before the widget, its end after, inside by the side asked.
    expect([line.toDisplay(3), line.toDisplay(9), line.toDisplay(5, -1), line.toDisplay(5, 1)], [5, 6, 5, 6]);
    expect([line.toDoc(5), line.toDoc(6, 1)], [3, 9]);
    // An equal description is the same line; another widget is not.
    LineProjection again(String name) => LineProjection.build('ab', 0, [set([Decoration.widget(widget: _W(name), side: 1).range(1)])]);
    expect(again('x').same(again('x')), isTrue);
    expect(again('x').same(again('y')), isFalse);
  });

  test('a line that only moved projects to an equal value', () {
    final mark = Decoration.mark(className: 'strong');
    final a = LineProjection.build('some **bold**', 40, [set([mark.range(45, 53)])]);
    final b = LineProjection.build('some **bold**', 400, [set([mark.range(405, 413)])]);
    expect(a.same(b), isTrue);
    expect(a.same(LineProjection.build('some **bolt**', 40, [set([mark.range(45, 53)])])), isFalse);
    expect(a.same(LineProjection.build('some **bold**', 40, [set([mark.range(46, 53)])])), isFalse);
  });

  test('atomic ranges cut the text and mark what the caret steps over', () {
    final hide = Decoration.replace();
    final line = LineProjection.build('ab cd ef', 10, [set([hide.range(13, 15)])], atomic: [(11, 12), (13, 15)]);
    expect([for (final seg in line.segments) '${seg.kind.name} ${seg.from}-${seg.to} ${seg.atomic}'], ['text 0-1 false', 'text 1-2 true', 'text 2-3 false', 'hidden 3-5 true', 'text 5-8 false']);
    expect(line.display, 'ab  ef');
  });

  group('the text the paragraph is given', () {
    test('a space is one that takes its room and may be broken after; a tab is the spaces to its stop', () {
      final words = PaintText('a b  c');
      expect(words.text, 'a ​b ​ ​c');
      expect([for (var i = 0; i <= 6; i++) words.toPaint(i)], [0, 1, 3, 4, 6, 8, 9]);
      expect([for (var i = 0; i <= 9; i++) words.toDisplay(i)], [0, 1, 2, 2, 3, 4, 4, 5, 5, 6]);
      final tabbed = PaintText('a\tb', tabSize: 4);
      expect(tabbed.text, 'a   ​b');
      expect([tabbed.toPaint(1), tabbed.toPaint(2), tabbed.toDisplay(2), tabbed.toDisplay(5)], [1, 5, 2, 2]);
      expect(PaintText('plain').text, 'plain');
    });

    test('a pair of ASCII characters breaks where the page’s lines may, not where the paragraph’s would', () {
      // Blink never breaks an address after a slash; ICU does.
      expect(blinkBreaks(-1, 0x2f, 0x61), isFalse);
      expect(breakFix(-1, 0x2f, 0x61), BreakFix.forbid);
      expect(PaintText('a/b').text, 'a/${wordJoiner}b');
      // Where something hidden stands the page has an image either side of an empty element, and a line may break
      // there whatever the pair: "`code`." ends a line after code on the page, though `e.` never breaks.
      expect(PaintText('code.').text, 'code${wordJoiner}.');
      final marked = PaintText('for code. Say', breaks: {4, 8});
      expect(marked.text, 'for\u00A0\u200Bcode\u200B.\u00A0\u200BSay');
      expect(marked.toDisplay(marked.toPaint(8)), 8);
      // And it wins over a pair the page would otherwise hold together.
      expect(PaintText('a/b', breaks: {2}).text, 'a/\u200Bb');
      // Nothing at either end of the line: there is no line to break.
      expect(PaintText('code', breaks: {0, 4}).text, 'code');
      // Blink breaks before a bracket after a closing one, and after a question mark.
      expect(blinkBreaks(-1, 0x5d, 0x28), isTrue);
      expect(blinkBreaks(-1, 0x3f, 0x61), isTrue);
      // A hyphen before a figure is a minus unless letters or figures come before it.
      expect(blinkBreaks(0x20, 0x2d, 0x31), isFalse);
      expect(blinkBreaks(0x61, 0x2d, 0x31), isTrue);
      // Two letters are a word to both: nothing is written in.
      expect(breakFix(-1, 0x61, 0x62), BreakFix.none);
      // The maps hold with what was written in.
      final address = PaintText('x a/b');
      expect(address.toDisplay(address.toPaint(4)), 4);
      expect(address.toDisplay(address.text.length), 5);
    });
  });
}
