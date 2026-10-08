import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

/// `src/app/editor/language.test.ts`, case for case.
///
/// One expectation is not here: a fence with a language the pack knows (```js) being parsed by that language, so
/// that the innermost node at a variable is JavaScript's `VariableDefinition`. Nested languages are not ported
/// (language.dart); the other two expectations of that case, which say what a fence is without one, are.
void main() {
  const spoiler = InlineFormat('Spoiler', '||');
  const heat = InlineFormat('Heat', '🔥🔥');
  const frost = InlineFormat('Frost', '❄️❄️');

  /// The node names in the document's syntax tree.
  List<String> nodes(String doc, [List<InlineFormat> formats = const []]) {
    final names = <String>[];
    glyphMarkdown(formats).parse(doc).iterate(enter: (node) => names.add(node.name));
    return names;
  }

  group("the editor's markdown", () {
    test('does not turn a line into a heading because a dash follows it', () {
      expect(nodes('Places to go\n-'), isNot(contains('SetextHeading2')));
      expect(nodes('Places to go\n---'), isNot(contains('SetextHeading2')));
      expect(nodes('Places to go\n==='), isNot(contains('SetextHeading1')));
    });

    test('still makes headings from #, lists from -, and rules from ---', () {
      expect(nodes('# Places to go'), contains('ATXHeading1'));
      expect(nodes('- snacks'), contains('ListItem'));
      expect(nodes('Places to go\n\n---'), contains('HorizontalRule'));
      expect(nodes('- [ ] Book the cabin'), contains('TaskMarker'));
    });

    test('parses a fence with no language, or one nobody knows, as plain code', () {
      List<String> inside(String doc) {
        final chain = <String>[];
        for (SyntaxNode? node = glyphMarkdown().parse(doc).resolveInner(doc.indexOf('answer'), 1); node != null; node = node.parent) {
          chain.add(node.name);
        }
        return chain;
      }

      expect(inside('```\nconst answer = 42;\n```'), ['CodeText', 'FencedCode', 'Document']);
      expect(inside('```cobol\nMOVE answer TO X.\n```'), ['CodeText', 'FencedCode', 'Document']);
    });

    test("parses a plugin's formatting between its delimiters, marks and all", () {
      final names = nodes('The key is ||under the stone|| by the door.', [spoiler]);
      expect(names, contains('Spoiler'));
      expect(names.where((name) => name == 'SpoilerMark'), hasLength(2));
      expect(nodes('||two secrets|| and ||another||', [spoiler]).where((name) => name == 'Spoiler'), hasLength(2));
    });

    test('leaves a lone pipe, an unclosed run, and a longer run alone', () {
      expect(nodes('a | b | c', [spoiler]), isNot(contains('Spoiler')));
      expect(nodes('||never closed', [spoiler]), isNot(contains('Spoiler')));
      expect(nodes('|||three|||', [spoiler]), isNot(contains('Spoiler')));
      expect(nodes('|| spaced out ||', [spoiler]), isNot(contains('Spoiler')));
    });

    test("knows nothing of a formatting whose plugin is off, and a table's pipes are still a table's", () {
      expect(nodes('||secret||'), isNot(contains('Spoiler')));
      final table = nodes('| a | b |\n| - | - |\n| c || d |', [spoiler]);
      expect(table, contains('Table'));
      expect(table, isNot(contains('Spoiler')));
    });

    test('knows a delimiter by the piece it repeats, a character or an emoji of several code units', () {
      expect(delimiterUnit('||'), '|');
      expect(delimiterUnit('==='), '=');
      expect(delimiterUnit('🔥🔥'), '🔥');
      // A character and its variation selector are one piece.
      expect(delimiterUnit('❄️❄️'), '❄️');
      expect(delimiterUnit('ab'), 'ab');
    });

    test('parses an effect between two emoji either side, marks and all, as it does a character run', () {
      final names = nodes('It was 🔥🔥too hot to touch🔥🔥 all day.', [heat]);
      expect(names, contains('Heat'));
      expect(names.where((name) => name == 'HeatMark'), hasLength(2));
      expect(nodes('🔥🔥one🔥🔥 and 🔥🔥two🔥🔥', [heat]).where((name) => name == 'Heat'), hasLength(2));
      expect(nodes('❄️❄️cold❄️❄️', [frost]), contains('Frost'));
    });

    test('leaves a single flame, three flames, an unclosed pair and spaced flames alone', () {
      expect(nodes('a 🔥 fire 🔥 here', [heat]), isNot(contains('Heat')));
      expect(nodes('🔥🔥🔥lit🔥🔥🔥', [heat]), isNot(contains('Heat')));
      expect(nodes('🔥🔥 never closed', [heat]), isNot(contains('Heat')));
      expect(nodes('🔥🔥 spaced out 🔥🔥', [heat]), isNot(contains('Heat')));
      // An effect inside other marks, and marks inside an effect.
      expect(nodes('**🔥🔥bold heat🔥🔥**', [heat]), containsAll(['StrongEmphasis', 'Heat']));
      expect(nodes('🔥🔥so **very** hot🔥🔥', [heat]), containsAll(['StrongEmphasis', 'Heat']));
    });
  });

  test('a mark is where the web puts it, counted in UTF-16 code units', () {
    // 'It was ' is seven units and a flame is two, so the first run is 7..11 and the words start at 11.
    final tree = glyphMarkdown([heat]).parse('It was 🔥🔥too hot🔥🔥.');
    final found = <String>[];
    tree.iterate(enter: (node) => found.add('${node.name} ${node.from}-${node.to}'));
    expect(found, ['Document 0-23', 'Paragraph 0-23', 'Heat 7-22', 'HeatMark 7-11', 'HeatMark 18-22']);
  });
}
