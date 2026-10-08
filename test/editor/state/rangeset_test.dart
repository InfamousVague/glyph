// RangeSet and the decorations made of it. fixtures/rangeset.json holds what CodeMirror's RangeSet did with 130
// random sets (built, mapped, updated, walked, spanned, compared), what sides and map modes @codemirror/view gives
// each kind of decoration, and what mapping does to 120 sets of real decorations. Then the behaviours by hand, after
// @codemirror/state's test-rangeset.ts.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

class Val extends RangeValue {
  Val(this.id, {this.startSide = 0, this.endSide = 0, this.point = false, this.mapMode = MapMode.trackDel});

  final int id;
  @override
  final int startSide;
  @override
  final int endSide;
  @override
  final bool point;
  @override
  final MapMode mapMode;

  @override
  bool eq(RangeValue other) => other is Val && other.id == id;

  @override
  Range<Val> range(int from, [int? to]) => Range<Val>.create(from, to ?? from, this);

  @override
  String toString() => 'Val($id)';
}

List<List<int>> dump(RangeSet<Val> set, [int from = 0]) {
  final out = <List<int>>[];
  for (final c = set.iter(from); c.value != null; c.next()) {
    out.add(<int>[c.from, c.to, c.value!.id]);
  }
  return out;
}

List<int> ids(List<Val> values) => <int>[for (final v in values) v.id];

class Spans extends SpanIterator<Val> {
  final List<List<Object?>> out = <List<Object?>>[];

  @override
  void span(int from, int to, List<Val> active, int openStart) => out.add(<Object?>['s', from, to, ids(active), openStart]);

  @override
  void point(int from, int to, Val value, List<Val> active, int openStart, int index) =>
      out.add(<Object?>['p', from, to, value.id, ids(active), openStart, index]);
}

Map<String, Object?> spansOf(List<RangeSet<Val>> sets, int from, int to, int minPoint) {
  final iter = Spans();
  final open = RangeSet.spans<Val>(sets, from, to, iter, minPoint);
  return <String, Object?>{'out': iter.out, 'open': open};
}

class Compare extends RangeComparator<Val> {
  Compare(this.bounds);

  final bool bounds;
  final List<List<Object?>> out = <List<Object?>>[];

  @override
  void compareRange(int from, int to, List<Val> activeA, List<Val> activeB) => out.add(<Object?>['r', from, to, ids(activeA), ids(activeB)]);

  @override
  void comparePoint(int from, int to, Val? pointA, Val? pointB) => out.add(<Object?>['p', from, to, pointA?.id, pointB?.id]);

  @override
  bool get tracksBounds => bounds;

  @override
  void boundChange(int pos) => out.add(<Object?>['b', pos]);
}

List<List<Object?>> compareOf(List<RangeSet<Val>> a, List<RangeSet<Val>> b, ChangeDesc diff, bool bounds, int minPoint) {
  final comparator = Compare(bounds);
  RangeSet.compare<Val>(a, b, diff, comparator, minPoint);
  return comparator.out;
}

int sum(Object? value) => checksum(jsonEncode(value));

class W extends EditorWidget {
  const W(this.h);
  final int h;

  @override
  bool eq(W other) => other.h == h;

  @override
  double get estimatedHeight => h.toDouble();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  final data = fixture('rangeset');

  group('against CodeMirror', () {
    final cases = data['cases'] as List;
    test('${cases.length} sets: built, mapped, updated, walked, spanned, compared', () {
      for (var n = 0; n < cases.length; n++) {
        final c = cases[n] as Map<String, dynamic>, r = c['r'] as Map<String, dynamic>;
        final length = c['length'] as int;
        final objs = <Val>[
          for (final (i, v) in (c['vals'] as List).indexed)
            Val(i, startSide: v['startSide'] as int, endSide: v['endSide'] as int, point: v['point'] as bool, mapMode: MapMode.values[v['mapMode'] as int]),
        ];
        List<Range<Val>> toRanges(Object? list) => <Range<Val>>[
          for (final x in list as List) objs[x[2] as int].range(x[0] as int, x[1] as int),
        ];
        final reason = 'set $n';
        final set = RangeSet.of<Val>(toRanges(c['ranges']), true), set2 = RangeSet.of<Val>(toRanges(c['ranges2']), true);
        final changes = changesOf(c['change'] as List, length);
        final mapped = set.map(changes);
        final k = c['k'] as int, filterFrom = c['filterFrom'] as int, filterTo = c['filterTo'] as int;
        bool filter(int from, int to, Val v) => v.id % 3 != k;
        final updated = set.update(add: toRanges(c['add']), sort: true, filter: filter, filterFrom: filterFrom, filterTo: filterTo);
        final a = c['a'] as int, b = c['b'] as int;

        if (r['dump'] != null) expect(dump(set), r['dump'], reason: reason);
        expect(sum(dump(set)), r['sum'], reason: reason);
        expect(set.size, r['size'], reason: reason);
        expect(set.length, r['length'], reason: reason);
        if (r['mapped'] != null) expect(dump(mapped), r['mapped'], reason: '$reason mapped through ${jsonEncode(c['change'])}');
        expect(sum(dump(mapped)), r['mappedSum'], reason: reason);
        if (r['updated'] != null) expect(dump(updated), r['updated'], reason: '$reason updated');
        expect(sum(dump(updated)), r['updatedSum'], reason: reason);
        expect(sum(dump(set.update(add: toRanges(c['add']), sort: true))), r['updatedNoFilter'], reason: reason);

        final between = <List<int>>[], firstTwo = <List<int>>[];
        set.between(a, b, (from, to, v) {
          between.add(<int>[from, to, v.id]);
          return null;
        });
        set.between(a, b, (from, to, v) {
          firstTwo.add(<int>[from, to, v.id]);
          return firstTwo.length < 2 ? null : false;
        });
        expect(between, r['between'], reason: '$reason between($a, $b)');
        expect(firstTwo, r['firstTwo'], reason: reason);
        expect(dump(set, a).take(30).toList(), r['from'], reason: '$reason iter($a)');
        final both = <List<int>>[];
        for (final cur = RangeSet.iterSets<Val>(<RangeSet<Val>>[set, set2], a); cur.value != null && both.length < 30; cur.next()) {
          both.add(<int>[cur.from, cur.to, cur.value!.id]);
        }
        expect(both, r['both'], reason: reason);
        expect(sum(dump(RangeSet.join<Val>(<RangeSet<Val>>[set, set2]))), r['joined'], reason: reason);

        expect(spansOf(<RangeSet<Val>>[set, set2], a, b, -1), r['spans'], reason: '$reason spans($a, $b)');
        expect(spansOf(<RangeSet<Val>>[set], a, b, 0), r['spansPoints'], reason: '$reason point spans($a, $b)');

        final changed = mapped.update(add: toRanges(c['add2']), sort: true, filter: filter);
        final none = ChangeSet.emptyOf(length).desc;
        expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[mapped], changes.desc, false, -1), r['compare'], reason: reason);
        expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[mapped], changes.desc, true, -1), r['compareBounds'], reason: reason);
        expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[changed], changes.desc, true, -1), r['compareChanged'], reason: '$reason compare');
        expect(compareOf(<RangeSet<Val>>[set, set2], <RangeSet<Val>>[changed], changes.desc, false, 0), r['compareChangedPoints'], reason: reason);
        expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[set], none, true, -1), r['compareSelf'], reason: reason);
        expect(compareOf(<RangeSet<Val>>[set, set2], <RangeSet<Val>>[set2], none, false, -1), r['compareOther'], reason: reason);

        expect(RangeSet.eq<Val>(<RangeSet<Val>>[set], <RangeSet<Val>>[RangeSet.of<Val>(toRanges(c['ranges']), true)]), r['eqSelf'], reason: reason);
        expect(RangeSet.eq<Val>(<RangeSet<Val>>[set], <RangeSet<Val>>[set2]), r['eqOther'], reason: reason);
        expect(RangeSet.eq<Val>(<RangeSet<Val>>[set], <RangeSet<Val>>[mapped], min(a, changes.newLength), min(b, changes.newLength)), r['eqMapped'], reason: reason);
      }
    });

    final kinds = data['kinds'] as List;
    test('${kinds.length} decorations: the sides, map modes and block types the web view gives each kind', () {
      for (final kind in kinds) {
        final spec = kind['spec'] as Map<String, dynamic>, r = kind['r'] as Map<String, dynamic>;
        final inclusive = spec['inclusive'] as bool?, start = spec['inclusiveStart'] as bool?, end = spec['inclusiveEnd'] as bool?;
        final Decoration d = switch (kind['k'] as String) {
          'mark' => Decoration.mark(className: 'x', inclusive: inclusive, inclusiveStart: start, inclusiveEnd: end),
          'replace' => Decoration.replace(
            inclusive: inclusive,
            inclusiveStart: start,
            inclusiveEnd: end,
            block: spec['block'] as bool? ?? false,
            widget: spec['h'] == null ? null : W(spec['h'] as int),
          ),
          'widget' => Decoration.widget(widget: W(spec['h'] as int), side: spec['side'] as int, block: spec['block'] as bool),
          _ => Decoration.line(className: 'l'),
        };
        final reason = jsonEncode(kind);
        expect(d.startSide, r['startSide'], reason: reason);
        expect(d.endSide, r['endSide'], reason: reason);
        expect(d.point, r['point'], reason: reason);
        expect(d.mapMode.index, r['mapMode'], reason: reason);
        expect(d.heightRelevant, r['heightRelevant'], reason: reason);
        if (d is PointDecoration) {
          expect(d.block, r['block'], reason: reason);
          if (d.block) expect(d.type.index, r['type'], reason: reason);
        }
      }
    });

    final decoCases = data['decoCases'] as List;
    test('${decoCases.length} sets of decorations: their order, and what an edit leaves of them', () {
      for (final c in decoCases) {
        final text = c['doc'] as String;
        final list = <Range<Decoration>>[
          for (final m in c['made'] as List)
            () {
              final i = m['i'] as int, from = m['from'] as int, to = m['to'] as int;
              return switch (m['kind'] as String) {
                'mark' => Decoration.mark(className: 'm$i', data: i).range(from, to),
                'markInc' => Decoration.mark(className: 'm$i', inclusive: true, data: i).range(from, to),
                'replace' => Decoration.replace(data: i).range(from, to),
                'replaceInc' => Decoration.replace(inclusive: true, data: i).range(from, to),
                'widget' => Decoration.widget(widget: W(i), side: -1, data: i).range(from),
                'widgetAfter' => Decoration.widget(widget: W(i), side: 1, data: i).range(from),
                'line' => Decoration.line(className: 'l$i', data: i).range(from),
                'block' => Decoration.widget(widget: W(i), block: true, side: m['side'] as int, data: i).range(from),
                _ => Decoration.replace(block: true, widget: W(i), data: i).range(from, to),
              };
            }(),
        ];
        final set = Decoration.set(list, true);
        final changes = changesOf(c['change'] as List, text.length);
        List<List<Object?>> tags(DecorationSet s) {
          final out = <List<Object?>>[];
          for (final cur = s.iter(); cur.value != null; cur.next()) {
            out.add(<Object?>[cur.from, cur.to, cur.value!.spec.data]);
          }
          return out;
        }

        final reason = jsonEncode(<String, Object?>{'doc': text, 'made': c['made'], 'change': c['change']});
        expect(tags(set), c['r']['dump'], reason: reason);
        expect(tags(set.map(changes)), c['r']['mapped'], reason: reason);
      }
    });
  });

  group('RangeSetBuilder', () {
    test('wants ranges in order, and layers the ones that overlap', () {
      final a = Val(0), b = Val(1), c = Val(2);
      final builder = RangeSetBuilder<Val>()
        ..add(0, 10, a)
        ..add(2, 4, b)
        ..add(2, 20, c);
      final set = builder.finish();
      expect(dump(set), <List<int>>[<int>[0, 10, 0], <int>[2, 4, 1], <int>[2, 20, 2]]);
      expect(set.size, 3);
      expect(set.length, 20);
      expect(set.nextLayer.isEmpty, isFalse);
      expect(() => (RangeSetBuilder<Val>()..add(5, 6, a)).add(4, 6, b), throwsStateError);
      expect(() => builder.add(30, 31, a), throwsStateError);
      expect(RangeSetBuilder<Val>().finish().isEmpty, isTrue);
    });

    test('orders ranges at one position by their start side', () {
      final before = Val(0, startSide: -1, endSide: -1, point: true), after = Val(1, startSide: 1, endSide: 1, point: true);
      expect(() => (RangeSetBuilder<Val>()..add(3, 3, after)).add(3, 3, before), throwsStateError);
      final set = RangeSet.of<Val>(<Range<Val>>[after.range(3), before.range(3)], true);
      expect(dump(set), <List<int>>[<int>[3, 3, 0], <int>[3, 3, 1]]);
    });

    test('starts a new chunk every 250 ranges, and a big set still finds its ranges', () {
      final v = Val(0);
      final builder = RangeSetBuilder<Val>();
      for (var i = 0; i < 2000; i++) {
        builder.add(i * 3, i * 3 + 2, v);
      }
      final set = builder.finish();
      expect(set.chunk.length, 8);
      expect(set.size, 2000);
      final found = <int>[];
      set.between(3000, 3010, (from, to, _) {
        found.add(from);
        return null;
      });
      expect(found, <int>[3000, 3003, 3006, 3009]);
    });
  });

  group('RangeSet', () {
    final a = Val(0), b = Val(1);

    test('the empty set is empty whatever it is asked', () {
      final empty = RangeSet<Val>.empty();
      expect(empty.isEmpty, isTrue);
      expect(empty.size, 0);
      expect(empty.length, 0);
      expect(empty.nextLayer, same(empty));
      expect(empty.map(ChangeSet.of(const ChangeSpec(from: 0, insert: 'x'), 0)), same(empty));
      expect(empty.update(), same(empty));
      expect(empty.iter().value, isNull);
      expect(dump(empty.update(add: <Range<Val>>[a.range(1, 2)])), <List<int>>[<int>[1, 2, 0]]);
      expect(RangeSet.join<Val>(<RangeSet<Val>>[]).isEmpty, isTrue);
      expect(Decoration.none.isEmpty, isTrue);
    });

    test('maps ranges through changes; what was deleted round a plain range leaves it empty, not gone', () {
      final set = RangeSet.of<Val>(<Range<Val>>[a.range(2, 5), b.range(8, 12)]);
      final insert = ChangeSet.of(const ChangeSpec(from: 0, insert: 'xx'), 20);
      expect(dump(set.map(insert)), <List<int>>[<int>[4, 7, 0], <int>[10, 14, 1]]);
      final delete = ChangeSet.of(const ChangeSpec(from: 1, to: 6), 20);
      // Asked of CodeMirror itself: a range with sides of 0 survives its text as an empty range. (A mark, whose start
      // side is after its end side, does not: the decoration fixtures hold that.)
      expect(dump(set.map(delete)), <List<int>>[<int>[1, 1, 0], <int>[3, 7, 1]]);
      final inside = ChangeSet.of(const ChangeSpec(from: 9, to: 10, insert: 'long'), 20);
      expect(dump(set.map(inside)), <List<int>>[<int>[2, 5, 0], <int>[8, 15, 1]]);
      expect(set.map(ChangeSet.emptyOf(20)), same(set));
    });

    test('text typed at a range\'s edges is kept out or taken in by its sides', () {
      final exclusive = Val(0, startSide: 1, endSide: -1), inclusive = Val(1, startSide: -1, endSide: 1);
      final atStart = ChangeSet.of(const ChangeSpec(from: 2, insert: 'x'), 10), atEnd = ChangeSet.of(const ChangeSpec(from: 5, insert: 'x'), 10);
      expect(dump(RangeSet.of<Val>(<Range<Val>>[exclusive.range(2, 5)]).map(atStart)), <List<int>>[<int>[3, 6, 0]]);
      expect(dump(RangeSet.of<Val>(<Range<Val>>[exclusive.range(2, 5)]).map(atEnd)), <List<int>>[<int>[2, 5, 0]]);
      expect(dump(RangeSet.of<Val>(<Range<Val>>[inclusive.range(2, 5)]).map(atStart)), <List<int>>[<int>[2, 6, 1]]);
      expect(dump(RangeSet.of<Val>(<Range<Val>>[inclusive.range(2, 5)]).map(atEnd)), <List<int>>[<int>[2, 6, 1]]);
    });

    test('a point is dropped or kept by its map mode', () {
      Val point(MapMode mode) => Val(0, point: true, mapMode: mode);
      final across = ChangeSet.of(const ChangeSpec(from: 3, to: 7), 10), before = ChangeSet.of(const ChangeSpec(from: 3, to: 5), 10);
      final after = ChangeSet.of(const ChangeSpec(from: 5, to: 7), 10);
      List<List<int>> at5(MapMode mode, ChangeSet changes) => dump(RangeSet.of<Val>(<Range<Val>>[point(mode).range(5)]).map(changes));
      // A deletion that covers a whole chunk drops it unasked, whatever the mode (CodeMirror's "cover").
      expect(at5(MapMode.simple, across), isEmpty);
      expect(at5(MapMode.trackDel, across), isEmpty);
      expect(at5(MapMode.simple, before), <List<int>>[<int>[3, 3, 0]]);
      expect(at5(MapMode.trackDel, before), hasLength(1));
      expect(at5(MapMode.trackBefore, before), isEmpty);
      expect(at5(MapMode.trackBefore, after), hasLength(1));
      expect(at5(MapMode.trackAfter, after), isEmpty);
      expect(at5(MapMode.trackAfter, before), hasLength(1));
    });

    test('keeps untouched chunks as they are when mapping', () {
      final v = Val(0);
      final builder = RangeSetBuilder<Val>();
      for (var i = 0; i < 1000; i++) {
        builder.add(i * 4, i * 4 + 2, v);
      }
      final set = builder.finish();
      final mapped = set.map(ChangeSet.of(const ChangeSpec(from: 2001, insert: 'xyz'), 4000));
      expect(mapped.chunk.length, set.chunk.length);
      var shared = 0;
      for (var i = 0; i < set.chunk.length; i++) {
        if (identical(set.chunk[i], mapped.chunk[i])) shared++;
      }
      expect(shared, set.chunk.length - 1);
      expect(mapped.chunkPos.last, set.chunkPos.last + 3);
    });

    test('update adds, filters, and filters only where it is told', () {
      final set = RangeSet.of<Val>(<Range<Val>>[a.range(0, 2), b.range(4, 6), a.range(8, 10)]);
      expect(dump(set.update(add: <Range<Val>>[b.range(20, 22), b.range(1, 3)], sort: true)), <List<int>>[
        <int>[0, 2, 0],
        <int>[1, 3, 1],
        <int>[4, 6, 1],
        <int>[8, 10, 0],
        <int>[20, 22, 1],
      ]);
      expect(dump(set.update(filter: (_, _, v) => v.id != 0)), <List<int>>[<int>[4, 6, 1]]);
      expect(dump(set.update(filter: (_, _, v) => v.id != 0, filterFrom: 5, filterTo: 20)), <List<int>>[<int>[0, 2, 0], <int>[4, 6, 1]]);
      expect(set.update(), same(set));
    });

    test('compare sees nothing between a set and itself moved by an edit elsewhere', () {
      final v = Val(0);
      final builder = RangeSetBuilder<Val>();
      for (var i = 0; i < 1000; i++) {
        builder.add(i * 4, i * 4 + 2, v);
      }
      final set = builder.finish();
      final changes = ChangeSet.of(const ChangeSpec(from: 1, insert: 'x'), 4000);
      expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[set.map(changes)], changes.desc, true, -1), isEmpty);
      final dropped = set.update(filter: (from, _, _) => from != 2000);
      expect(compareOf(<RangeSet<Val>>[set], <RangeSet<Val>>[dropped], ChangeSet.emptyOf(4000).desc, false, -1), <List<Object?>>[
        <Object?>['r', 2000, 2002, <int>[0], <int>[]],
      ]);
    });

    test('spans reports which ranges were already open at the start', () {
      final set = RangeSet.of<Val>(<Range<Val>>[a.range(0, 10), b.range(4, 6)]);
      expect(spansOf(<RangeSet<Val>>[set], 5, 8, -1)['out'], <List<Object?>>[
        <Object?>['s', 5, 6, <int>[1, 0], 2],
        <Object?>['s', 6, 8, <int>[0], 1],
      ]);
    });
  });

  group('Decoration', () {
    test('a mark needs text, a line and a widget need none, a replacement may be either', () {
      expect(() => Decoration.mark(className: 'a').range(3), throwsRangeError);
      expect(() => Decoration.mark(className: 'a').range(3, 3), throwsRangeError);
      expect(() => Decoration.line(className: 'a').range(3, 4), throwsRangeError);
      expect(() => Decoration.widget(widget: const W(1)).range(3, 4), throwsRangeError);
      expect(() => Decoration.replace().range(4, 3), throwsRangeError);
      expect(() => Decoration.replace().range(3, 3), throwsRangeError);
      expect(Decoration.replace(inclusive: true).range(3, 3).from, 3);
      expect(Decoration.mark(className: 'a').range(3, 4).value, isA<MarkDecoration>());
    });

    test('marks are equal by class and attributes; widgets by their own eq', () {
      expect(Decoration.mark(className: 'a').eq(Decoration.mark(className: 'a')), isTrue);
      expect(Decoration.mark(className: 'a').eq(Decoration.mark(className: 'b')), isFalse);
      expect(Decoration.mark(className: 'a', attributes: const <String, String>{'data-x': '1'}).eq(Decoration.mark(className: 'a')), isFalse);
      expect(
        Decoration.mark(className: 'a', attributes: const <String, String>{'data-x': '1'}).eq(Decoration.mark(attributes: const <String, String>{'class': 'a', 'data-x': '1'})),
        isTrue,
      );
      expect(Decoration.mark(className: 'a', tagName: 'strong').eq(Decoration.mark(className: 'a')), isFalse);
      expect((Decoration.mark(className: 'a', attributes: const <String, String>{'class': 'b'}) as MarkDecoration).attrs, <String, String>{'class': 'a b'});
      expect(Decoration.line(className: 'a').eq(Decoration.line(className: 'a')), isTrue);
      expect(Decoration.line(className: 'a').eq(Decoration.mark(className: 'a')), isFalse);
      expect(Decoration.widget(widget: const W(1)).eq(Decoration.widget(widget: const W(1))), isTrue);
      expect(Decoration.widget(widget: const W(1)).eq(Decoration.widget(widget: const W(2))), isFalse);
      expect(Decoration.widget(widget: const W(1)).eq(Decoration.widget(widget: const W(1), side: 1)), isFalse);
      expect(Decoration.replace(widget: const W(1)).eq(Decoration.replace(widget: const W(1))), isTrue);
      expect(Decoration.replace().eq(Decoration.replace()), isTrue);
      expect(Decoration.replace().eq(Decoration.replace(block: true)), isFalse);
    });

    test('keeps what it was made with, and knows whether it has a height', () {
      final d = Decoration.widget(widget: const W(20), side: 1, data: 'tag');
      expect(d.spec.side, 1);
      expect(d.spec.data, 'tag');
      expect(d.widget, isA<W>());
      expect(d.hasHeight(), isTrue);
      expect(Decoration.mark(className: 'a').hasHeight(), isFalse);
      expect(Decoration.mark(className: 'a b').spec.className, 'a b');
    });

    test('a redraw sees equal decorations as no change', () {
      DecorationSet draw(int counterAt) => Decoration.set(<Range<Decoration>>[
        Decoration.line(className: 'heading').range(0),
        Decoration.mark(className: 'tag').range(2, 6),
        Decoration.replace(widget: W(counterAt)).range(8, 13),
      ]);
      final none = ChangeSet.emptyOf(20).desc;
      final same = _Changes();
      RangeSet.compare<Decoration>(<DecorationSet>[draw(3)], <DecorationSet>[draw(3)], none, same);
      expect(same.out, isEmpty);
      final different = _Changes();
      RangeSet.compare<Decoration>(<DecorationSet>[draw(3)], <DecorationSet>[draw(4)], none, different);
      expect(different.out, <String>['point 8-13']);
      expect(RangeSet.eq<Decoration>(<DecorationSet>[draw(3)], <DecorationSet>[draw(3)]), isTrue);
      expect(RangeSet.eq<Decoration>(<DecorationSet>[draw(3)], <DecorationSet>[draw(4)]), isFalse);
    });
  });
}

class _Changes extends RangeComparator<Decoration> {
  final List<String> out = <String>[];

  @override
  void compareRange(int from, int to, List<Decoration> activeA, List<Decoration> activeB) => out.add('range $from-$to');

  @override
  void comparePoint(int from, int to, Decoration? pointA, Decoration? pointB) => out.add('point $from-$to');
}
