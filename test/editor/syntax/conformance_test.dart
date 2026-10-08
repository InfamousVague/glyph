import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/markdown.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

import 'support.dart';

/// The port held to the web's parser, node for node: every tree `tool/editor_trees.mjs` wrote is parsed again here
/// and must come out the same, name, start, end and depth, and `resolveInner` must answer what Lezer's answered at
/// every position the script asked.
///
/// A fixture is one test, so its count is said once: the cases that fail are named (the first twenty), each with
/// the first node it parts at.
void main() {
  /// Runs every case of [fixture] through the parser [parserOf] gives it; answers the failures.
  List<String> run(TreeFixture fixture, MarkdownParser Function(Map<String, dynamic> one) parserOf, String label) {
    final failures = <String>[];
    var nodes = 0, asked = 0;
    for (final one in fixture.cases) {
      final doc = one['doc'] as String;
      final Tree tree;
      try {
        tree = parserOf(one).parse(doc);
      } catch (error) {
        failures.add('${one['name']}: threw $error');
        continue;
      }
      final expected = expectedFlat(one['tree'] as List, fixture.names);
      nodes += expected.length ~/ 4;
      final difference = firstDifference(flat(tree), expected);
      if (difference != null) {
        failures.add('${one['name']}: $difference');
        continue;
      }
      final resolve = (one['resolve'] as List).cast<int>();
      for (var i = 0; i < resolve.length; i += 5) {
        final node = tree.resolveInner(resolve[i], resolve[i + 1]);
        asked += 1;
        if (node.name != fixture.names[resolve[i + 2]] || node.from != resolve[i + 3] || node.to != resolve[i + 4]) {
          failures.add(
            '${one['name']}: resolveInner(${resolve[i]}, ${resolve[i + 1]}) is ${node.name} ${node.from}-${node.to}, '
            'the web\'s ${fixture.names[resolve[i + 2]]} ${resolve[i + 3]}-${resolve[i + 4]}',
          );
          break;
        }
      }
    }
    final passed = fixture.cases.length - failures.length;
    // ignore: avoid_print
    print('$label: $passed of ${fixture.cases.length} cases, $nodes nodes, $asked positions resolved');
    return failures;
  }

  String told(List<String> failures) => failures.take(20).join('\n');

  test("every case of Lezer's CommonMark tests parses as Lezer parses it", () {
    final fixture = TreeFixture('lezer_markdown.json');
    expect(fixture.cases.length, 655);
    final failures = run(fixture, (one) => parserFor(one['steps'] as List), 'test-markdown.ts');
    expect(failures, isEmpty, reason: told(failures));
  });

  test("every case of Lezer's extension tests parses as Lezer parses it", () {
    final fixture = TreeFixture('lezer_extension.json');
    expect(fixture.cases.length, 53);
    final failures = run(fixture, (one) => parserFor(one['steps'] as List), 'test-extension.ts');
    expect(failures, isEmpty, reason: told(failures));
  });

  test("the app's own Markdown parses as the web editor parses it, every node", () {
    final fixture = TreeFixture('glyph_corpus.json');
    expect(fixture.formats.length, 12);
    final glyph = glyphMarkdown(fixture.formats);
    final failures = run(fixture, (one) => glyph, 'the corpus');
    expect(failures, isEmpty, reason: told(failures));
  });

  test("lines of it dealt at random parse as the web editor parses them, every node", () {
    final fixture = TreeFixture('glyph_fuzz.json');
    final glyph = glyphMarkdown(fixture.formats);
    final failures = run(fixture, (one) => glyph, 'dealt lines');
    expect(failures, isEmpty, reason: told(failures));
  });
}
