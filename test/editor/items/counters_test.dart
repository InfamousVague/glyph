// Counters (lib/editor/items/counters.dart): `src/app/editor/counters.test.ts`, case for case.
//
// What is asked differently: the page's one `<span class="cm-counter">` is three marks here (the brackets apart),
// so a chip is read as the marks that share a `data-counter`; a press is the plugin's own pointer handlers called
// with a point of a view laid out on a grid (every character 10 px wide, every line 20 px tall), where the page's
// test pressed the chip's element; `mousedown` kept from the editor is `pointerDown` answering true, and the
// phone's long-press menu kept shut is `longPress` and `secondaryTap` answering true. Nothing is left out.
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/counters.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// A view that is not drawn lays nothing out, as jsdom lays nothing out: every character 10 px wide and every line
/// 20 px tall.
class _Grid extends EditorView {
  _Grid(EditorState state) : super(state: state, wholeDocument: true);

  Rect _box(int pos) {
    final line = state.doc.lineAt(pos);
    final left = (pos - line.from) * 10.0, top = (line.number - 1) * 20.0;
    return Rect.fromLTRB(left, top, left + 10, top + 20);
  }

  // Leaning back (`side` -1), a position is the character before it.
  @override
  Rect? coordsAtPos(int pos, [int side = 1]) => side < 0 && pos > 0 ? _box(pos - 1) : _box(pos);

  @override
  int? posAtCoords(Offset global, {bool precise = true}) {
    final line = state.doc.line(math.min(state.doc.lines, (global.dy / 20).floor() + 1));
    return math.min(line.to, line.from + (global.dx / 10).floor());
  }
}

/// One chip: the marks of one counter, joined.
typedef _Chip = ({int from, int to, String text, String className, String style});

List<_Chip> _chips(EditorView view) {
  final byCounter = <String, List<({int from, int to, DecorationSpec spec})>>{};
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      final spec = value.spec;
      if ((spec.className ?? '').split(' ').contains('cm-counter')) (byCounter[spec.attributes!['data-counter']!] ??= <({int from, int to, DecorationSpec spec})>[]).add((from: from, to: to, spec: spec));
      return null;
    });
  }
  final chips = <_Chip>[];
  for (final pieces in byCounter.values) {
    pieces.sort((a, b) => a.from - b.from);
    // The pieces touch, and every one says the same class and fill.
    for (var i = 1; i < pieces.length; i++) {
      expect(pieces[i].from, pieces[i - 1].to);
      expect(pieces[i].spec.className, pieces.first.spec.className);
      expect(pieces[i].spec.attributes!['style'], pieces.first.spec.attributes!['style']);
    }
    chips.add((
      from: pieces.first.from,
      to: pieces.last.to,
      text: view.state.sliceDoc(pieces.first.from, pieces.last.to),
      className: pieces.first.spec.className!,
      style: pieces.first.spec.attributes!['style']!,
    ));
  }
  return chips..sort((a, b) => a.from - b.from);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('counters', () {
    test('finds a count and a goal in brackets, and nothing that only looks like one', () {
      expect(countersIn('- Water [3/8] and push-ups [0/50]').map((c) => <int>[c.count, c.goal]), <List<int>>[
        <int>[3, 8],
        <int>[0, 50],
      ]);
      expect(countersIn('[1/2](https://x.dev) ![3/4](image/a.jpg) a[1/2] [0/0] [ 1/2 ]'), isEmpty);
      expect(countersIn('x [2/5]', 10)[0], const Counter(from: 12, to: 17, count: 2, goal: 5));
    });

    test('steps up to the goal and down to nothing, and no further', () {
      Counter at(int count) => Counter(from: 0, to: 0, count: count, goal: 3);
      expect(stepped(at(1), 1), '[2/3]');
      expect(stepped(at(3), 1), '[3/3]');
      expect(stepped(at(1), -1), '[0/3]');
      expect(stepped(at(0), -1), '[0/3]');
    });
  });

  group('a counter in a note', () {
    EditorView open(String doc, [bool readOnly = false]) {
      final view = _Grid(EditorState.create(doc: doc, extensions: noteExtensions(readOnly: readOnly, more: <Extension>[counters(), history()])));
      addTearDown(view.destroy);
      return view;
    }

    // The middle of a chip, on the grid.
    Offset middle(EditorView on, _Chip chip) {
      final line = on.state.doc.lineAt(chip.from);
      return Offset((chip.from + chip.to) / 2 * 10 - line.from * 10, (line.number - 1) * 20 + 10);
    }

    bool down(EditorView on, Offset at) => on.eventHandlers.any((h) => h.pointerDown?.call(PointerDownEvent(position: at), on) ?? false);
    bool up(EditorView on, Offset at) => on.eventHandlers.any((h) => h.pointerUp?.call(PointerUpEvent(position: at), on) ?? false);

    test('is drawn as a chip that fills as the count rises, full at its goal', () {
      final on = open('- Water [3/8]\n- Stretch [2/2]');
      final chips = _chips(on);
      expect(chips.map((one) => one.text), <String>['[3/8]', '[2/2]']);
      expect(chips[0].style, '--fill:38%');
      expect(chips.map((one) => one.className.split(' ').contains('cm-counterFull')), <bool>[false, true]);
    });

    test('counts one up on a tap, as an edit of its own that one undo takes back', () {
      final on = open('- Water [3/8]');
      final at = middle(on, _chips(on).single);
      down(on, at);
      up(on, at);
      expect(on.state.doc.toString(), '- Water [4/8]');
      undo(on);
      expect(on.state.doc.toString(), '- Water [3/8]');
    });

    testWidgets('takes one away on a hold, and the lift after it adds nothing', (tester) async {
      final on = open('- Water [3/8]');
      final at = middle(on, _chips(on).single);
      down(on, at);
      await tester.pump(const Duration(milliseconds: 449));
      expect(on.state.doc.toString(), '- Water [3/8]');
      await tester.pump(const Duration(milliseconds: 1));
      expect(on.state.doc.toString(), '- Water [2/8]');
      up(on, at);
      expect(on.state.doc.toString(), '- Water [2/8]');
    });

    testWidgets('stays full when tapped at its goal, and empty when held at nothing', (tester) async {
      final on = open('- Stretch [2/2] and rest [0/3]');
      final full = middle(on, _chips(on)[0]);
      down(on, full);
      up(on, full);
      final empty = middle(on, _chips(on)[1]);
      down(on, empty);
      await tester.pump(const Duration(milliseconds: 500));
      up(on, empty);
      expect(on.state.doc.toString(), '- Stretch [2/2] and rest [0/3]');
    });

    test('is a control: the caret stays put, the phone’s long-press menu does not open, and a locked note is left alone', () {
      final on = open('- Water [3/8]');
      final at = middle(on, _chips(on).single);
      // The press is the chip's: it does not reach the editor, which would move the caret.
      expect(down(on, at), isTrue);
      on.eventHandlers.any((h) => h.pointerCancel?.call(PointerCancelEvent(position: at), on) ?? false);
      final held = EditorTap(global: at, local: at, kind: PointerDeviceKind.touch);
      expect(on.eventHandlers.any((h) => h.longPress?.call(held, on) ?? false), isTrue);
      expect(on.eventHandlers.any((h) => h.secondaryTap?.call(EditorTap(global: at, local: at, kind: PointerDeviceKind.mouse), on) ?? false), isTrue);
      expect(on.state.selection.main.head, 0);
      expect(on.state.doc.toString(), '- Water [3/8]');

      final locked = open('- Water [3/8]', true);
      down(locked, at);
      up(locked, at);
      expect(locked.state.doc.toString(), '- Water [3/8]');
    });

    test('is not a counter in code', () {
      final on = open('Run `[3/8]` as written');
      expect(_chips(on), isEmpty);
    });
  });
}
