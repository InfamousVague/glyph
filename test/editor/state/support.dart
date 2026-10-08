// What the state tests share: the fixtures CodeMirror itself wrote (fixtures/generate.mjs), a seeded random source
// for the property tests, and the JSON shapes both sides print.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ghost_md/editor/editor.dart';

/// One of the fixture files, decoded.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/editor/state/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// The generator's checksum of a string.
int checksum(String s) {
  var h = 0;
  for (var i = 0; i < s.length; i++) {
    h = ((h * 31) + s.codeUnitAt(i)) & 0x7fffffff;
  }
  return h;
}

/// `{from, to, insert}` objects from a fixture, as specs.
List<ChangeSpec> specsOf(List<dynamic> list) => <ChangeSpec>[
  for (final s in list) ChangeSpec(from: s['from'] as int, to: s['to'] as int?, insert: s['insert'] as String?),
];

/// A change set the way the generator makes one.
ChangeSet changesOf(List<dynamic> list, int length) => ChangeSet.of(specsOf(list), length);

Map<String, Object?> rangeJson(SelectionRange x) => <String, Object?>{
  'from': x.from,
  'to': x.to,
  'anchor': x.anchor,
  'head': x.head,
  'empty': x.empty,
  'assoc': x.assoc,
  'bidi': x.bidiLevel,
  'goal': x.goalColumn,
};

Map<String, Object?> selJson(EditorSelection s) => <String, Object?>{
  'ranges': <Object?>[for (final r in s.ranges) rangeJson(r)],
  'main': s.mainIndex,
};

/// Everything a text iterator yields.
List<String> drain(TextIterator iter) {
  final out = <String>[];
  for (iter.next(); !iter.done; iter.next()) {
    out.add(iter.value);
  }
  return out;
}

const List<String> alphabet = <String>['a', 'b', 'c', 'd', 'e', ' ', ' ', 'x', 'é', '#', '[', ']', '*', '😀', '\t'];

String randomWord(Random r, int max) => <String>[for (var i = r.nextInt(max + 1); i > 0; i--) alphabet[r.nextInt(alphabet.length)]].join();

List<String> randomLines(Random r, int count, int max) => <String>[for (var i = 0; i < count; i++) randomWord(r, max)];

/// Random specs against a document of `length`, positions anywhere and in any order.
List<ChangeSpec> randomSpecs(Random r, int length, [int max = 4]) => <ChangeSpec>[
  for (var i = r.nextInt(max + 1); i > 0; i--)
    () {
      final from = r.nextInt(length + 1), to = min(length, from + const <int>[0, 0, 1, 2, 5][r.nextInt(5)]);
      return ChangeSpec(from: from, to: to, insert: const <String>['', '', 'x', 'yz', 'one\ntwo', '😀', '\n'][r.nextInt(7)]);
    }(),
];
