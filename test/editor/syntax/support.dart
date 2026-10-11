import 'dart:convert';
import 'dart:io';

import 'package:ghost_md/editor/syntax/extension.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/markdown.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

/// One fixture written by `tool/editor_trees.mjs`: trees the web's parser made, for the port to make again.
class TreeFixture {
  TreeFixture(String file) : _json = jsonDecode(File('test/editor/syntax/fixtures/$file').readAsStringSync()) as Map<String, dynamic>;

  final Map<String, dynamic> _json;

  List<String> get names => (_json['names'] as List).cast<String>();
  List<Map<String, dynamic>> get cases => (_json['cases'] as List).cast<Map<String, dynamic>>();

  /// The marks the fixture's parser was made with, as the script restated them from plugins/marks/index.tsx.
  List<InlineFormat> get formats => [
    for (final format in (_json['formats'] as List? ?? const []).cast<Map<String, dynamic>>())
      InlineFormat(format['name'] as String, format['delimiter'] as String),
  ];
}

/// The configs Lezer's test files name, by the names the script wrote for them.
final Map<String, List<MarkdownConfig>> _extensions = {
  'GFM': gfm,
  'Table': [table],
  'TaskList': [taskList],
  'Strikethrough': [strikethrough],
  'Autolink': [autolink],
  'Subscript': [subscript],
  'Superscript': [superscript],
  'Emoji': [emoji],
};

/// The parser a Lezer case was run with: CommonMark's, reconfigured once for each of [steps].
MarkdownParser parserFor(List<dynamic> steps) {
  var made = parser;
  for (final step in steps) {
    made = made.configure([
      for (final part in (step as List).cast<String>())
        if (part.startsWith('remove:')) MarkdownConfig(remove: part.substring(7).split(',')) else ..._extensions[part]!,
    ]);
  }
  return made;
}

/// A tree as the fixtures write one: its nodes in document order, each a name, from, to and depth.
List<Object> flat(Tree tree) {
  final out = <Object>[];
  var depth = 0;
  tree.iterate(
    enter: (node) {
      out
        ..add(node.name)
        ..add(node.from)
        ..add(node.to)
        ..add(depth);
      depth += 1;
    },
    leave: (node) => depth -= 1,
  );
  return out;
}

/// A fixture's tree, with its names written out.
List<Object> expectedFlat(List<dynamic> tree, List<String> names) {
  return [for (var i = 0; i < tree.length; i++) i % 4 == 0 ? names[tree[i] as int] : tree[i] as int];
}

/// Where two flat trees first part, in words, or null when they are the same.
String? firstDifference(List<Object> actual, List<Object> expected) {
  String node(List<Object> list, int i) => i + 3 < list.length ? '${'  ' * (list[i + 3] as int)}${list[i]} ${list[i + 1]}-${list[i + 2]}' : '(nothing)';
  final length = actual.length > expected.length ? actual.length : expected.length;
  for (var i = 0; i < length; i += 4) {
    final same = i + 3 < actual.length && i + 3 < expected.length && actual[i] == expected[i] && actual[i + 1] == expected[i + 1] && actual[i + 2] == expected[i + 2] && actual[i + 3] == expected[i + 3];
    if (!same) return 'node ${i ~/ 4}: the port has "${node(actual, i)}", the web "${node(expected, i)}"';
  }
  return null;
}
