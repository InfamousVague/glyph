import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/importer/notion/notion_markdown.dart';

import 'fake_notion.dart';

/// What converting asked for: the titles it is told, the files it kept, and what it left out or could not link.
class Writing implements NotionWriting {
  Writing([this.titles = const {}]);
  final Map<String, String> titles;
  final List<String> kept = [];
  final List<String> left = [];
  final List<String> unresolvedWords = [];

  @override
  String? titleOf(String id) => titles[id];

  @override
  Future<String?> keep(String url, {required String name, String caption = '', bool picture = false}) async {
    kept.add(url);
    if (url.contains('gone')) return null;
    return picture ? '![$caption](image/p${kept.length}.png)' : '[$name](file/$name)';
  }

  @override
  void leftOut(String type) => left.add(type);

  @override
  void unresolved(String words) => unresolvedWords.add(words);
}

Future<String> md(List<Map<String, Object?>> blocks, [Writing? writing]) => blocksMarkdown(blocks, writing ?? Writing());

void main() {
  group('rich text', () {
    test('bold, italic, strike, code and their mix, a run written once and its spaces outside its marks', () {
      final rich = [
        text('Plain, '),
        text('bold ', bold: true),
        text('and bold', bold: true),
        text(' '),
        text('both', bold: true, italic: true),
        text(', '),
        text('gone', strike: true),
        text(', '),
        text('x = 1', code: true),
        text(' and '),
        text('a ` tick', code: true),
      ];
      expect(richMarkdown(rich, Writing()), 'Plain, **bold and bold** ***both***, ~~gone~~, `x = 1` and `` a ` tick ``');
    });

    test('a link, a highlight by colour, an underline and a coloured text as words', () {
      expect(richMarkdown([text('the site', link: 'https://example.com/a b')], Writing()), '[the site](https://example.com/a%20b)');
      expect(richMarkdown([text('key', color: 'yellow_background'), text(' '), text('go', color: 'green_background'), text(' red', color: 'red')], Writing()), '==key== ==go==(green) red');
      expect(richMarkdown([text('under', underline: true)], Writing()), 'under');
    });

    test('what would be Markdown is escaped; a soft break is a hard one', () {
      expect(richMarkdown([text('2 * 3 and `x` and [[not]] and ==no==')], Writing()), r'2 \* 3 and \`x\` and \[\[not\]\] and \=\=no\=\=');
      expect(richMarkdown([text('one\ntwo')], Writing()), 'one  \ntwo');
    });

    test('mentions: a person by name, a page by its title, a date, and a page Ghost.md was not shown as words', () {
      final writing = Writing({idA: 'Plans'});
      final rich = [
        mentionUser('@Sam Ortiz'),
        text(' wrote '),
        mentionPage(idA, 'Plans'),
        text(' on '),
        mentionDate('2026-11-04', end: '2026-11-06'),
        text(', see '),
        mentionPage(idB, 'Secret'),
      ];
      expect(richMarkdown(rich, writing), 'Sam Ortiz wrote [[Plans]] on 2026-11-04 → 2026-11-06, see Secret');
      expect(writing.unresolvedWords, ['Secret']);
    });

    test('a link into Notion is a wiki link to the page, with its words where they differ', () {
      final writing = Writing({idA: 'Plans'});
      expect(richMarkdown([text('Plans', link: '/${idA.substring(0, 8)}${idA.substring(8)}')], writing), '[[Plans]]');
      expect(richMarkdown([text('the plan', link: 'https://www.notion.so/team/Plans-$idA?pvs=4')], writing), '[[Plans|the plan]]');
      expect(richMarkdown([text('gone', link: 'https://www.notion.so/Gone-$idB')], writing), '[gone](https://www.notion.so/Gone-$idB)');
      expect(writing.unresolvedWords, ['gone']);
    });

    test('an equation inline', () {
      expect(richMarkdown([text('So '), {'type': 'equation', 'equation': {'expression': 'e^{i\\pi}'}, 'plain_text': 'e^{i\\pi}', 'annotations': plainNotes}], Writing()), r'So $e^{i\pi}$');
    });
  });

  group('blocks', () {
    test('headings, paragraphs, a toggle heading with its blocks under it, an empty paragraph dropped', () async {
      expect(
          await md([
            block('heading_1', rich: 'Title'),
            block('paragraph', rich: ''),
            block('paragraph', rich: 'Words.'),
            block('heading_2', rich: 'Folded', extra: {'is_toggleable': true}, children: [block('paragraph', rich: 'Inside.')]),
            block('heading_3', rich: 'Small'),
            block('paragraph', rich: '# not a heading'),
          ]),
          '# Title\n\nWords.\n\n## Folded\n\nInside.\n\n### Small\n\n\\# not a heading');
    });

    test('lists nest as deep as Notion has them; numbers count each run; to-dos tick', () async {
      expect(
          await md([
            block('bulleted_list_item', rich: 'One', children: [
              block('bulleted_list_item', rich: 'One a', children: [block('to_do', rich: 'Deep', extra: {'checked': true})]),
            ]),
            block('bulleted_list_item', rich: 'Two'),
            block('paragraph', rich: 'Between.'),
            block('numbered_list_item', rich: 'First'),
            block('numbered_list_item', rich: 'Second', children: [block('numbered_list_item', rich: 'Inner')]),
            block('to_do', rich: 'Open'),
          ]),
          '- One\n  - One a\n    - [x] Deep\n- Two\n\nBetween.\n\n1. First\n2. Second\n   1. Inner\n- [ ] Open');
    });

    test('a quote, a callout by its icon, a toggle as <details>, a divider', () async {
      expect(
          await md([
            block('quote', rich: 'Said.', children: [block('paragraph', rich: 'And more.')]),
            block('callout', rich: 'Watch out', extra: {'icon': {'type': 'emoji', 'emoji': '⚠️'}}),
            block('callout', rich: 'An idea', extra: {'icon': {'type': 'emoji', 'emoji': '💡'}}),
            block('callout', rich: 'Plain', extra: {'icon': {'type': 'emoji', 'emoji': '🍕'}}),
            block('toggle', rich: 'Packing', children: [block('bulleted_list_item', rich: 'Boots')]),
            block('divider'),
          ]),
          '> Said.\n>\n> And more.\n\n> [!WARNING]\n> ⚠️ Watch out\n\n> [!TIP]\n> 💡 An idea\n\n> [!NOTE]\n> 🍕 Plain\n\n<details>\n<summary>Packing</summary>\n\n- Boots\n\n</details>\n\n---');
    });

    test('code with its language and caption, an equation, a table with and without its header', () async {
      expect(
          await md([
            block('code', rich: 'print("hi")', extra: {'language': 'python', 'caption': [text('The start')]}),
            block('code', rich: 'a\n```\nb', extra: {'language': 'c++'}),
            block('code', rich: 'graph TD; A-->B', extra: {'language': 'mermaid'}),
            block('code', rich: 'plain', extra: {'language': 'plain text'}),
            block('equation', extra: {'expression': 'x^2'}),
          ]),
          '```python\nprint("hi")\n```\n\n*The start*\n\n````cpp\na\n```\nb\n````\n\n```mermaid\ngraph TD; A-->B\n```\n\n```\nplain\n```\n\n\$\$\nx^2\n\$\$');
      expect(
          await md([
            table([['Name', 'Score'], ['Sam | Jo', '3']], header: true),
            table([['a', 'b']], header: false),
          ]),
          '| Name | Score |\n| --- | --- |\n| Sam \\| Jo | 3 |\n\n|  |  |\n| --- | --- |\n| a | b |');
    });

    test('pictures and files kept from Notion, an external picture left as its link, a bookmark and an embed alone on their lines', () async {
      final writing = Writing();
      expect(
          await md([
            fileBlock('image', 'https://prod-files-secure.s3.us-west-2.amazonaws.com/x/cat.png', caption: 'A cat'),
            fileBlock('image', 'https://example.com/dog.png', external: true),
            fileBlock('pdf', 'https://prod-files-secure.s3.us-west-2.amazonaws.com/x/Plan%20A.pdf'),
            fileBlock('video', 'https://www.youtube.com/watch?v=abc', external: true),
            fileBlock('file', 'https://prod-files-secure.s3.us-west-2.amazonaws.com/x/gone.zip'),
            block('bookmark', extra: {'url': 'https://ghostmarkdown.com', 'caption': []}),
            block('embed', extra: {'url': 'https://open.spotify.com/track/1'}),
          ], writing),
          '![A cat](image/p1.png)\n\n![](https://example.com/dog.png)\n\n[Plan A.pdf](file/Plan A.pdf)\n\nhttps://www.youtube.com/watch?v=abc\n\nhttps://ghostmarkdown.com\n\nhttps://open.spotify.com/track/1');
      expect(writing.kept.length, 3);
    });

    test('a file whose name has a % in it (Matt, 2026-11-04: "The import failed with illegal percent parsing uri")', () async {
      final writing = Writing();
      expect(await md([fileBlock('pdf', 'https://prod-files-secure.s3.us-west-2.amazonaws.com/x/50%25%20off.pdf')], writing), '[50% off.pdf](file/50% off.pdf)');
    });

    test('sub-pages, databases and links to pages as wiki links; columns and synced blocks as their blocks in order', () async {
      final writing = Writing({idA: 'Plans', idB: 'Tasks'});
      expect(
          await md([
            {'object': 'block', 'id': dashed(idA), 'type': 'child_page', 'has_children': false, 'child_page': {'title': 'Plans'}},
            {'object': 'block', 'id': dashed(idB), 'type': 'child_database', 'has_children': false, 'child_database': {'title': 'Tasks'}},
            block('link_to_page', extra: {'type': 'page_id', 'page_id': dashed(idA)}),
            block('column_list', children: [
              block('column', children: [block('paragraph', rich: 'Left')]),
              block('column', children: [block('paragraph', rich: 'Right')]),
            ]),
            block('synced_block', extra: {'synced_from': null}, children: [block('paragraph', rich: 'Synced words')]),
          ], writing),
          '[[Plans]]\n\n[[Tasks]]\n\n[[Plans]]\n\nLeft\n\nRight\n\nSynced words');
    });

    test('what has no Markdown is left out and named', () async {
      final writing = Writing();
      expect(await md([block('table_of_contents'), block('breadcrumb'), block('unsupported'), block('paragraph', rich: 'Kept.')], writing), 'Kept.');
      expect(writing.left, ['table of contents', 'breadcrumb', 'block Notion doesn’t share with apps']);
    });
  });
}
