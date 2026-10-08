// ChangeSet and ChangeDesc: every answer CodeMirror gave in fixtures/changes.json, then the laws that composition,
// inversion and mapping obey, over random documents and changes.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

List<List<int>> changedRanges(ChangeDesc set, bool individual) {
  final out = <List<int>>[];
  set.iterChangedRanges((a, b, c, d) => out.add(<int>[a, b, c, d]), individual);
  return out;
}

void main() {
  group('against CodeMirror', () {
    final cases = fixture('changes')['cases'] as List;
    test('${cases.length} documents, each with three change sets', () {
      for (final c in cases) {
        final text = c['doc'] as String;
        final doc = Doc.ofString(text);
        final r = c['r'] as Map<String, dynamic>;
        final a = changesOf(c['a'] as List, doc.length), b = changesOf(c['b'] as List, doc.length);
        final after = a.apply(doc);
        final cs = changesOf(c['c'] as List, after.length);
        final reason = 'doc ${jsonEncode(text)} a ${jsonEncode(c['a'])} b ${jsonEncode(c['b'])} c ${jsonEncode(c['c'])}';

        expect(a.toJson(), r['json'], reason: reason);
        expect(a.desc.toString(), r['desc'], reason: reason);
        expect(a.length, r['length']);
        expect(a.newLength, r['newLength']);
        expect(a.empty, r['empty']);
        expect(after.toString(), r['applied'], reason: reason);
        expect(a.invert(doc).toJson(), r['inverted'], reason: reason);
        expect(a.invertedDesc.toString(), r['invertedDesc'], reason: reason);

        final mapPos = r['mapPos'] as List;
        var i = 0;
        for (var pos = 0; pos <= doc.length; pos++) {
          for (final assoc in <int>[-1, 1]) {
            expect(
              <int?>[for (final mode in MapMode.values) a.mapPosTracked(pos, assoc, mode)],
              mapPos[i++],
              reason: '$reason mapPos($pos, $assoc)',
            );
            expect(a.desc.mapPos(pos, assoc), a.mapPos(pos, assoc));
          }
        }
        for (final t in r['touches'] as List) {
          expect(a.touchesRange(t[0] as int, t[1] as int).index, t[2], reason: '$reason touchesRange(${t[0]}, ${t[1]})');
        }

        final iter = <List<Object>>[], iterInd = <List<Object>>[];
        a.iterChanges((fa, ta, fb, tb, ins) => iter.add(<Object>[fa, ta, fb, tb, ins.toString()]));
        a.iterChanges((fa, ta, fb, tb, ins) => iterInd.add(<Object>[fa, ta, fb, tb, ins.toString()]), true);
        expect(iter, r['iter'], reason: reason);
        expect(iterInd, r['iterInd'], reason: reason);
        final gaps = <List<int>>[];
        a.iterGaps((pa, pb, len) => gaps.add(<int>[pa, pb, len]));
        expect(gaps, r['gaps'], reason: reason);
        expect(changedRanges(a, false), r['ranges'], reason: reason);
        expect(changedRanges(a.desc, true), r['rangesInd'], reason: reason);

        expect(a.map(b).toJson(), r['aMapB'], reason: reason);
        expect(a.map(b, true).toJson(), r['aMapBBefore'], reason: reason);
        expect(b.map(a).toJson(), r['bMapA'], reason: reason);
        expect(b.map(a, true).toJson(), r['bMapABefore'], reason: reason);
        expect(a.desc.mapDesc(b.desc).toString(), r['aMapDescB'], reason: reason);
        expect(a.desc.mapDesc(b.desc, true).toString(), r['aMapDescBBefore'], reason: reason);
        expect(a.compose(cs).toJson(), r['compose'], reason: reason);
        expect(a.desc.composeDesc(cs.desc).toString(), r['composeDesc'], reason: reason);
        expect(a.compose(cs).apply(doc).toString(), r['composed'], reason: reason);

        final filtered = a.filter((r['filterRanges'] as List).cast<int>());
        expect(filtered.changes.toJson(), r['filterChanges'], reason: reason);
        expect(filtered.filtered.toString(), r['filterFiltered'], reason: reason);
      }
    });
  });

  group('ChangeSet.of', () {
    test('reads one spec, a list, a nested list and a set among them', () {
      final one = ChangeSet.of(const ChangeSpec(from: 2, to: 4, insert: 'xy'), 10);
      expect(one.toString(), '2 2:2 6');
      final nested = ChangeSet.of(<Object>[
        const ChangeSpec(from: 0, insert: 'a'),
        <Object>[const ChangeSpec(from: 5, to: 6), one],
      ], 10);
      expect(nested.apply(Doc.ofString('0123456789')).toString(), 'a01xy46789');
      expect(ChangeSet.of(null, 4).empty, isTrue);
      expect(ChangeSet.of(const <Object>[], 0).sections, isEmpty);
      expect(ChangeSet.emptyOf(3).toString(), '3');
    });

    test('takes positions in the starting document, whatever order the specs come in', () {
      final set = ChangeSet.of(<ChangeSpec>[const ChangeSpec(from: 8, insert: 'B'), const ChangeSpec(from: 2, insert: 'A')], 10);
      expect(set.apply(Doc.ofString('0123456789')).toString(), '01A234567B89');
    });

    test('splits inserted text on any line break, or on the one it is told', () {
      final set = ChangeSet.of(const ChangeSpec(from: 0, insert: 'a\r\nb\rc\nd'), 0);
      expect(set.inserted.single.lines, 4);
      final sep = ChangeSet.of(const ChangeSpec(from: 0, insert: 'a\r\nb\nc'), 0, '\r\n');
      expect(sep.inserted.single.toJson(), <String>['a', 'b\nc']);
      expect(ChangeSet.of(ChangeSpec(from: 0, insert: Doc.ofString('x\ny')), 0).newLength, 3);
    });

    test('refuses a range outside the document, a set of another length, and what is not a change', () {
      expect(() => ChangeSet.of(const ChangeSpec(from: 3, to: 2), 10), throwsRangeError);
      expect(() => ChangeSet.of(const ChangeSpec(from: 0, to: 11), 10), throwsRangeError);
      expect(() => ChangeSet.of(const ChangeSpec(from: -1), 10), throwsRangeError);
      expect(() => ChangeSet.of(ChangeSet.emptyOf(4), 10), throwsRangeError);
      expect(() => ChangeSet.of('nope', 10), throwsArgumentError);
      expect(() => ChangeSet.of(const ChangeSpec(from: 0, insert: 3), 10), throwsArgumentError);
      expect(() => ChangeSet.emptyOf(4).apply(Doc.ofString('abc')), throwsRangeError);
      expect(() => ChangeSet.emptyOf(4).mapPos(5), throwsRangeError);
      expect(() => ChangeSet.of(const ChangeSpec(from: 0, insert: 'x'), 4).compose(ChangeSet.of(const ChangeSpec(from: 0, insert: 'x'), 9)), throwsStateError);
      expect(() => ChangeSet.of(const ChangeSpec(from: 0, insert: 'x'), 4).map(ChangeSet.of(const ChangeSpec(from: 0, insert: 'y'), 5)), throwsStateError);
    });
  });

  group('mapPos', () {
    final set = ChangeSet.of(<ChangeSpec>[const ChangeSpec(from: 2, insert: 'ab'), const ChangeSpec(from: 5, to: 8)], 10);

    test('holds to the side it is told at an insertion', () {
      expect(set.mapPos(2), 2);
      expect(set.mapPos(2, 1), 4);
      expect(set.mapPos(1), 1);
      expect(set.mapPos(3, 1), 5);
    });

    test('collapses into a deletion, and says so when asked to track', () {
      expect(set.mapPos(6), 7);
      expect(set.mapPos(6, 1), 7);
      expect(set.mapPosTracked(6, -1, MapMode.trackDel), isNull);
      expect(set.mapPosTracked(5, -1, MapMode.trackDel), 7);
      expect(set.mapPosTracked(8, -1, MapMode.trackDel), 7);
      expect(set.mapPosTracked(5, -1, MapMode.trackAfter), isNull);
      expect(set.mapPosTracked(5, -1, MapMode.trackBefore), 7);
      expect(set.mapPosTracked(8, -1, MapMode.trackBefore), isNull);
      expect(set.mapPosTracked(8, -1, MapMode.trackAfter), 7);
    });

    test('touchesRange tells touching from covering', () {
      expect(set.touchesRange(0, 1), Touch.none);
      expect(set.touchesRange(0, 1).touched, isFalse);
      expect(set.touchesRange(0, 2), Touch.touches);
      expect(set.touchesRange(6, 7), Touch.cover);
      expect(set.touchesRange(6).touched, isTrue);
      expect(set.touchesRange(9), Touch.none);
    });
  });

  group('JSON', () {
    test('round trips a set and a description', () {
      final r = Random(5);
      for (var i = 0; i < 200; i++) {
        final doc = Doc.ofString(randomLines(r, 1 + r.nextInt(4), 9).join('\n'));
        final set = ChangeSet.of(randomSpecs(r, doc.length), doc.length);
        final back = ChangeSet.fromJson(jsonDecode(jsonEncode(set.toJson())));
        expect(back.toJson(), set.toJson());
        expect(back.apply(doc).toString(), set.apply(doc).toString());
        expect(ChangeDesc.fromJson(jsonDecode(jsonEncode(set.desc.toJson()))).toString(), set.desc.toString());
      }
    });

    test('refuses what is not one', () {
      expect(() => ChangeSet.fromJson('x'), throwsRangeError);
      expect(() => ChangeSet.fromJson(<Object>[<Object>['a']]), throwsRangeError);
      expect(() => ChangeSet.fromJson(<Object>[<Object>[1, 2]]), throwsRangeError);
      expect(() => ChangeDesc.fromJson(<Object>[1]), throwsRangeError);
      expect(() => ChangeDesc.fromJson(<Object>[1, 'a']), throwsRangeError);
    });
  });

  // CodeMirror's own test/test-change.ts checks these laws over random change sets; so does this.
  group('laws, over random changes', () {
    for (final seed in <int>[11, 12, 13, 14, 15]) {
      test('seed $seed', () {
        final r = Random(seed);
        for (var n = 0; n < 500; n++) {
          final text = randomLines(r, 1 + r.nextInt(5), 12).join('\n');
          final doc = Doc.ofString(text);
          final a = ChangeSet.of(randomSpecs(r, doc.length), doc.length);
          final b = ChangeSet.of(randomSpecs(r, doc.length), doc.length);
          final docA = a.apply(doc), docB = b.apply(doc);
          final c = ChangeSet.of(randomSpecs(r, docA.length), docA.length);
          final docAC = c.apply(docA);
          final reason = 'seed $seed, round $n, doc ${jsonEncode(text)}, a ${a.toJson()}, b ${b.toJson()}, c ${c.toJson()}';

          // Lengths agree with what applying does.
          expect(a.length, doc.length);
          expect(a.newLength, docA.length, reason: reason);

          // Composing is applying one after the other, and composing is associative.
          final ac = a.compose(c);
          expect(ac.apply(doc).toString(), docAC.toString(), reason: reason);
          expect(ac.desc.toString(), a.desc.composeDesc(c.desc).toString(), reason: reason);
          final d = ChangeSet.of(randomSpecs(r, docAC.length), docAC.length);
          expect(a.compose(c).compose(d).apply(doc).toString(), a.compose(c.compose(d)).apply(doc).toString(), reason: reason);

          // Inverting undoes, and the inverse of the inverse is the change.
          final inv = a.invert(doc);
          expect(inv.apply(docA).toString(), text, reason: reason);
          expect(inv.invert(docA).apply(doc).toString(), docA.toString(), reason: reason);
          expect(inv.desc.toString(), a.invertedDesc.toString(), reason: reason);
          expect(a.compose(inv).apply(doc).toString(), text, reason: reason);

          // Two changes made beside each other converge whichever goes first.
          final viaA = a.compose(b.map(a)), viaB = b.compose(a.map(b, true));
          expect(viaA.apply(doc).toString(), viaB.apply(doc).toString(), reason: reason);
          expect(b.map(a).length, docA.length);
          expect(a.map(b, true).length, docB.length);
          expect(a.mapDesc(b, true).toString(), a.map(b, true).desc.toString(), reason: reason);
          expect(a.desc.mapDesc(b.desc).toString(), a.map(b).desc.toString(), reason: reason);

          // Positions: never backwards, inside the new document, and a position outside every change keeps its
          // distance from the changes round it.
          var last = 0;
          for (var pos = 0; pos <= doc.length; pos++) {
            final before = a.mapPos(pos, -1), afterPos = a.mapPos(pos, 1);
            expect(before, lessThanOrEqualTo(afterPos), reason: reason);
            expect(before, greaterThanOrEqualTo(last), reason: reason);
            expect(afterPos, lessThanOrEqualTo(docA.length), reason: reason);
            last = before;
            if (!a.touchesRange(pos).touched) {
              expect(before, afterPos, reason: reason);
              expect(a.mapPosTracked(pos, -1, MapMode.trackDel), before, reason: reason);
              expect(docA.sliceString(before, min(docA.length, before + 1)), doc.sliceString(pos, min(doc.length, pos + 1)), reason: reason);
            }
          }
          // Unchanged stretches hold the same text on both sides, and the changed ranges are the rest.
          a.iterGaps((posA, posB, len) => expect(docA.sliceString(posB, posB + len), doc.sliceString(posA, posA + len), reason: reason));
          var covered = 0;
          a.iterGaps((_, _, len) => covered += len);
          a.iterChangedRanges((fromA, toA, _, _) => covered += toA - fromA);
          expect(covered, doc.length, reason: reason);
          a.iterChanges((fromA, toA, fromB, toB, inserted) {
            expect(docA.sliceString(fromB, toB), inserted.toString(), reason: reason);
            expect(inserted.length, toB - fromB);
          });
        }
      });
    }
  });
}
