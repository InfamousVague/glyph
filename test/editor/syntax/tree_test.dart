import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/markdown.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

import 'support.dart';

/// The tree as the editor's extensions walk it: what `@lezer/common` answers for the calls the web app makes on
/// `syntaxTree(state)` (`iterate` over a range, `resolveInner` and the walk out through `parent`, `node.node`), and
/// the rest of `SyntaxNode` a port of an extension may reach for.
///
/// `resolveInner` itself is held to Lezer's answers in conformance_test.dart; here the walks are held to each
/// other, over every document of the corpus.
void main() {
  final fixture = TreeFixture('glyph_corpus.json');
  final glyph = glyphMarkdown(fixture.formats);

  const note = '# Trip\n\nPack **warm** things, and `code`.\n\n- [ ] Book the *cabin*\n- [x] Call Sam\n\n> A quote\n> of two lines\n\n```js\nlet a = 1;\n```\n';

  test('the two things Lezer checks outside its tree notation', () {
    // "Doesn't get confused by tabs indenting a list item"
    const tabs = ' - a\n\t\tb';
    expect(parser.parse(tabs).length, lessThanOrEqualTo(tabs.length));
    // "Parses horizontal rules when setext headers are disabled"
    expect(parser.configure([const MarkdownConfig(remove: ['SetextHeading'])]).parse('abc\n---').toString(), 'Document(Paragraph,HorizontalRule)');
  });

  test('iterate enters a parent before its children and leaves it after them', () {
    final walk = <String>[];
    glyph.parse('Pack **warm** things').iterate(enter: (node) => walk.add('>${node.name}'), leave: (node) => walk.add('<${node.name}'));
    expect(walk, ['>Document', '>Paragraph', '>StrongEmphasis', '>EmphasisMark', '<EmphasisMark', '>EmphasisMark', '<EmphasisMark', '<StrongEmphasis', '<Paragraph', '<Document']);
  });

  test('a node whose enter answers false has its children passed over, and is not left', () {
    final walk = <String>[];
    glyph.parse(note).iterate(
      enter: (node) {
        walk.add('>${node.name}');
        return node.name != 'BulletList' && node.name != 'Paragraph';
      },
      leave: (node) => walk.add('<${node.name}'),
    );
    expect(walk, containsAllInOrder(['>Paragraph', '>BulletList', '>Blockquote']));
    expect(walk, isNot(contains('>ListItem')));
    expect(walk, isNot(contains('>StrongEmphasis')));
    expect(walk, isNot(contains('<BulletList')));
    expect(walk, contains('<Blockquote'));
  });

  test('iterate over a range enters the nodes that touch it and no others, as Lezer does', () {
    var ranges = 0;
    for (final one in fixture.cases) {
      final doc = one['doc'] as String;
      final tree = glyph.parse(doc);
      final all = flat(tree);
      // A handful of ranges through each document: a point, a short stretch, a long one.
      for (var k = 0; k < 6; k++) {
        final from = (doc.length * k) ~/ 6;
        final to = k.isEven ? from : (from + doc.length ~/ 9).clamp(0, doc.length);
        // Lezer's rule, worked from the whole walk: a node is entered when it touches the range and so does every
        // node around it.
        final expected = <Object>[];
        var shut = 1 << 30;
        for (var i = 0; i < all.length; i += 4) {
          final depth = all[i + 3] as int;
          if (depth > shut) continue;
          shut = 1 << 30;
          if ((all[i + 1] as int) <= to && (all[i + 2] as int) >= from) {
            expected.addAll(all.sublist(i, i + 4));
          } else {
            shut = depth;
          }
        }
        final entered = <Object>[];
        var depth = 0, left = 0;
        tree.iterate(
          from: from,
          to: to,
          enter: (node) {
            entered
              ..add(node.name)
              ..add(node.from)
              ..add(node.to)
              ..add(depth);
            depth += 1;
          },
          leave: (node) {
            depth -= 1;
            left += 1;
          },
        );
        expect(firstDifference(entered, expected), isNull, reason: '${one['name']} $from..$to');
        expect(left, entered.length ~/ 4);
        ranges += 1;
      }
    }
    expect(ranges, greaterThan(5000));
  });

  test('a cursor walks the nodes in the order iterate does, and back again', () {
    for (final one in fixture.cases.take(120)) {
      final tree = glyph.parse(one['doc'] as String);
      final forward = <String>[];
      final cursor = tree.cursor();
      do {
        forward.add('${cursor.name} ${cursor.from}-${cursor.to}');
      } while (cursor.next());
      final iterated = <String>[];
      tree.iterate(enter: (node) => iterated.add('${node.name} ${node.from}-${node.to}'));
      expect(forward, iterated);
      // `prev` is Lezer's other walk: a node, then its last child, else the sibling before it or before a parent.
      // From the top it meets every node once, each parent before its children and the later child first.
      final back = <String>[];
      final mirror = tree.cursor();
      do {
        back.add('${mirror.name} ${mirror.from}-${mirror.to}');
      } while (mirror.prev());
      expect(back.length, forward.length);
      expect(back.first, forward.first);
      expect(back.toSet(), forward.toSet());
      // The last node of the forward walk is where `next` stops, and it stays there.
      expect(cursor.next(), isFalse);
      expect('${cursor.name} ${cursor.from}-${cursor.to}', forward.last);
    }
  });

  test('every node knows its parent, its siblings and its place', () {
    for (final one in fixture.cases.take(200)) {
      final tree = glyph.parse(one['doc'] as String);
      tree.iterate(
        enter: (node) {
          expect(node.node, same(node));
          final first = node.firstChild, last = node.lastChild;
          expect(first == null, node.tree.children.isEmpty);
          var count = 0;
          SyntaxNode? before;
          for (var child = first; child != null; child = child.nextSibling) {
            expect(child.parent, same(node));
            expect(child.index, count);
            expect(child.prevSibling?.from, before?.from);
            expect(child.prevSibling?.name, before?.name);
            before = child;
            count += 1;
          }
          expect(count, node.tree.children.length);
          expect(last?.from, before?.from);
          expect(last?.to, before?.to);
        },
      );
    }
  });

  test('getChild and getChildren find children by name or by group', () {
    final top = glyph.parse(note).topNode;
    expect(top.getChild('BulletList')!.getChildren('ListItem'), hasLength(2));
    expect(top.getChildren('Block').map((node) => node.name), ['ATXHeading1', 'Paragraph', 'BulletList', 'Blockquote', 'FencedCode']);
    expect(top.getChildren('LeafBlock').map((node) => node.name), ['ATXHeading1', 'Paragraph', 'FencedCode']);
    expect(top.getChild('Table'), isNull);
    final fence = top.getChild('FencedCode')!;
    expect(fence.getChildren('CodeMark'), hasLength(2));
    // Only the children after the first CodeInfo, and only those before the first CodeText.
    expect(fence.getChildren('CodeMark', 'CodeInfo'), hasLength(1));
    expect(fence.getChildren('CodeMark', null, 'CodeText'), hasLength(1));
    expect(fence.getChild('CodeInfo')!.from, note.indexOf('js'));
    // No child of the `after` type at all: nothing.
    expect(fence.getChildren('CodeMark', null, 'Table'), isEmpty);
  });

  test('childAfter, childBefore and enter find the child at a position', () {
    final tree = glyph.parse(note);
    final top = tree.topNode;
    final list = note.indexOf('- [ ]');
    expect(top.childAfter(list)!.name, 'BulletList');
    expect(top.childBefore(list)!.name, 'Paragraph');
    expect(top.childAfter(note.length), isNull);
    expect(top.childBefore(0), isNull);
    expect(top.enter(list, 1)!.name, 'BulletList');
    // Between two blocks nothing holds the position.
    expect(top.enter(list - 1, 0), isNull);
    // At a node's end, only a side that leans back steps into it.
    final heading = top.firstChild!;
    expect(top.enter(heading.to, -1)!.name, 'ATXHeading1');
    expect(top.enter(heading.to, 1), isNull);
  });

  test('a node resolves from where it is, and matches the nodes around it', () {
    final tree = glyph.parse(note);
    final at = note.indexOf('cabin');
    final inner = tree.resolveInner(at, 1);
    expect(inner.name, 'Emphasis');
    expect(inner.matchContext(['ListItem', 'Task']), isTrue);
    expect(inner.matchContext(['BulletList', '', 'Task']), isTrue);
    expect(inner.matchContext(['Blockquote', 'Task']), isFalse);
    // From a node elsewhere in the tree the answer is the same one.
    final elsewhere = tree.resolveInner(note.indexOf('quote'), 1);
    expect(elsewhere.resolveInner(at, 1).from, inner.from);
    expect(elsewhere.resolve(at, 1).name, 'Emphasis');
    expect(tree.cursor().moveTo(at, 1).name, 'Emphasis');
    expect(inner.toTree(), same(inner.tree));
  });

  test('an empty note is a Document with nothing in it', () {
    final tree = glyph.parse('');
    expect(tree.toString(), 'Document');
    expect(tree.length, 0);
    expect(tree.resolveInner(0, 1).name, 'Document');
    expect(tree.topNode.firstChild, isNull);
    expect(tree.cursor().next(), isFalse);
  });

  test('a parser can be extended the way Lezer\'s is: a node, a block parser, an inline parser', () {
    // A composite block for lines that start with `!`, and `@name` as an inline node: the shape of Lezer's own
    // extension examples.
    final extended = parser.configure([
      MarkdownConfig(
        defineNodes: [
          NodeSpec(
            'Shout',
            composite: (cx, line, value) {
              if (line.next != 33) return false;
              line.addMarker(cx.elt('ShoutMark', cx.lineStart + line.pos, cx.lineStart + line.pos + 1));
              line.moveBase(line.pos + 1);
              return true;
            },
          ),
          const NodeSpec('ShoutMark'),
          const NodeSpec('Mention'),
        ],
        parseBlock: [
          BlockParser(
            name: 'Shout',
            parse: (cx, line) {
              if (line.next != 33) return false;
              cx.startComposite('Shout', line.pos);
              cx.addElement(cx.elt('ShoutMark', cx.lineStart + line.pos, cx.lineStart + line.pos + 1));
              line.moveBase(line.pos + 1);
              return null;
            },
            before: 'Blockquote',
          ),
        ],
        parseInline: [
          InlineParser(
            name: 'Mention',
            parse: (cx, next, pos) {
              if (next != 64) return -1;
              var end = pos + 1;
              while (cx.char(end) >= 97 && cx.char(end) <= 122) {
                end++;
              }
              return end == pos + 1 ? -1 : cx.addElement(cx.elt('Mention', pos, end));
            },
            before: 'Emphasis',
          ),
        ],
      ),
    ]);
    expect(extended.parse('! hey @sam\n! *again*\n\nquiet').toString(), 'Document(Shout(ShoutMark,Paragraph(Mention,ShoutMark,Emphasis(EmphasisMark,EmphasisMark))),Paragraph)');
    expect(extended.nodeTypes[extended.getNodeType('Shout')].isA('BlockContext'), isTrue);
    expect(() => parser.configure([const MarkdownConfig(parseInline: [InlineParser(name: 'X', parse: _never, after: 'Nobody')])]), throwsRangeError);
    // The parser it was made from is as it was.
    expect(parser.parse('! hey @sam').toString(), 'Document(Paragraph)');
  });
}

int _never(InlineContext cx, int next, int pos) => -1;
