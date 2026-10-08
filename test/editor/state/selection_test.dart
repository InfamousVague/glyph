// EditorSelection and SelectionRange against fixtures/selection.json (CodeMirror's answers), and by hand.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

void main() {
  final data = fixture('selection');

  group('against CodeMirror', () {
    final cases = data['cases'] as List;
    test('${cases.length} selections: sorted, merged, mapped, grown', () {
      for (final c in cases) {
        final pairs = c['pairs'] as List, r = c['r'] as Map<String, dynamic>;
        final reason = jsonEncode(<String, Object?>{'pairs': pairs, 'main': c['main'], 'change': c['change'], 'extra': c['extra']});
        final sel = EditorSelection.create(<SelectionRange>[
          for (final p in pairs) EditorSelection.range(p[0] as int, p[1] as int),
        ], c['main'] as int);
        final set = changesOf(c['change'] as List, 30);
        final extra = EditorSelection.range(c['extra'][0] as int, c['extra'][1] as int);
        expect(selJson(sel), r['sel'], reason: reason);
        expect(selJson(sel.asSingle()), r['single'], reason: reason);
        expect(sel.toJson(), r['json'], reason: reason);
        expect(selJson(EditorSelection.fromJson(jsonDecode(jsonEncode(sel.toJson())))), r['sel'], reason: reason);
        expect(selJson(sel.map(set)), r['mapped'], reason: reason);
        expect(selJson(sel.map(set, 1)), r['mappedAfter'], reason: reason);
        expect(selJson(sel.addRange(extra)), r['added'], reason: reason);
        expect(selJson(sel.addRange(extra, false)), r['addedNotMain'], reason: reason);
        expect(selJson(sel.replaceRange(extra)), r['replaced'], reason: reason);
        final ext = c['ext'] as List;
        expect(rangeJson(sel.main.extend(ext[0] as int, (ext[0] as int) + (ext[1] as int))), r['extended'], reason: reason);
        expect(sel.eq(sel.asSingle()), r['eqSingle'], reason: reason);
      }
    });

    final flags = data['flags'] as List;
    test('${flags.length} ranges and carets: sides, bidi levels, goal columns', () {
      for (final f in flags) {
        final anchor = f['anchor'] as int, head = f['head'] as int;
        final goal = f['goal'] as int?, bidi = f['bidi'] as int?, assoc = f['assoc'] as int?;
        final range = f['k'] == 'range' ? EditorSelection.range(anchor, head, goal, bidi, assoc) : EditorSelection.cursor(anchor, assoc ?? 0, bidi, goal);
        expect(rangeJson(range), f['r'], reason: jsonEncode(f));
      }
    });
  });

  group('SelectionRange', () {
    test('knows its anchor and head either way round', () {
      final forward = EditorSelection.range(2, 6), backward = EditorSelection.range(6, 2);
      expect(<int>[forward.from, forward.to, forward.anchor, forward.head], <int>[2, 6, 2, 6]);
      expect(<int>[backward.from, backward.to, backward.anchor, backward.head], <int>[2, 6, 6, 2]);
      expect(forward.eq(backward), isFalse);
      expect(forward.eq(EditorSelection.range(2, 6)), isTrue);
      expect(EditorSelection.cursor(4).empty, isTrue);
      expect(EditorSelection.cursor(4, -1).eq(EditorSelection.cursor(4, 1)), isTrue);
      expect(EditorSelection.cursor(4, -1).eq(EditorSelection.cursor(4, 1), true), isFalse);
      expect(EditorSelection.undirectionalRange(1, 3).undirectional, isTrue);
      expect(forward.undirectional, isFalse);
    });

    test('a caret holds its side of an insertion; a range does not swallow one at its edges', () {
      final insert = ChangeSet.of(const ChangeSpec(from: 4, insert: 'xx'), 10);
      expect(EditorSelection.cursor(4).map(insert).from, 4);
      expect(EditorSelection.cursor(4).map(insert, 1).from, 6);
      final range = EditorSelection.range(4, 8).map(insert);
      expect(<int>[range.from, range.to], <int>[6, 10]);
      final end = EditorSelection.range(1, 4).map(insert);
      expect(<int>[end.from, end.to], <int>[1, 4]);
      final same = EditorSelection.range(0, 2);
      expect(identical(same.map(insert), same), isTrue);
    });

    test('reads its JSON back, and refuses what is not one', () {
      expect(SelectionRange.fromJson(EditorSelection.range(5, 1).toJson()).head, 1);
      expect(() => SelectionRange.fromJson(<String, Object?>{'anchor': 1}), throwsRangeError);
      expect(() => EditorSelection.fromJson(<String, Object?>{'ranges': <Object?>[], 'main': 0}), throwsRangeError);
    });
  });

  group('EditorSelection', () {
    test('needs a range, and merges the ones that touch', () {
      expect(() => EditorSelection.create(<SelectionRange>[]), throwsRangeError);
      final sel = EditorSelection.create(<SelectionRange>[
        EditorSelection.range(8, 10),
        EditorSelection.range(0, 4),
        EditorSelection.range(3, 6),
        EditorSelection.cursor(10),
      ], 1);
      expect(<List<int>>[for (final r in sel.ranges) <int>[r.from, r.to]], <List<int>>[<int>[0, 6], <int>[8, 10]]);
      expect(sel.mainIndex, 0);
      // Two carets at one place are one caret, and a caret at a range's end joins it; one at its start does not
      // (asked of CodeMirror itself: 1, 1, 2).
      expect(EditorSelection.create(<SelectionRange>[EditorSelection.cursor(2), EditorSelection.cursor(2)]).ranges, hasLength(1));
      expect(EditorSelection.create(<SelectionRange>[EditorSelection.range(2, 5), EditorSelection.cursor(5)]).ranges, hasLength(1));
      expect(EditorSelection.create(<SelectionRange>[EditorSelection.cursor(2), EditorSelection.range(2, 5)]).ranges, hasLength(2));
      // Ranges that only touch end to start stay two.
      expect(EditorSelection.create(<SelectionRange>[EditorSelection.range(0, 2), EditorSelection.range(2, 5)]).ranges, hasLength(2));
    });

    test('single is a caret or a range, and a selection may not reach past the document', () {
      expect(EditorSelection.single(3).main.empty, isTrue);
      expect(EditorSelection.single(3, 1).main.head, 1);
      expect(() => checkSelection(EditorSelection.single(11), 10), throwsRangeError);
      checkSelection(EditorSelection.single(10), 10);
    });

    test('is the same object after an empty change', () {
      final sel = EditorSelection.single(3, 5);
      expect(identical(sel.map(ChangeSet.emptyOf(10)), sel), isTrue);
    });
  });
}
