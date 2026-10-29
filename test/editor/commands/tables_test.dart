// A table's source read and grown: the pure cases of `src/app/editor/tables.test.ts`. Its other four ("a table
// drawn in a note") are of the drawn widget and its focus, which are the view's piece.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/tables.dart';

void main() {
  group('reading a GFM table to draw it', () {
    test('reads the header, the alignment and the rows, escaped pipes kept as text', () {
      final parsed = parseTable('| Bug | Owner | Status |\n| --- | :---: | ---: |\n| Seek bar \\| drift | Matt | Open |\n| Login |')!;
      expect(parsed.header, <String>['Bug', 'Owner', 'Status']);
      expect(parsed.align, <TableAlign?>[null, TableAlign.center, TableAlign.right]);
      expect(parsed.rows, <List<String>>[
        <String>['Seek bar | drift', 'Matt', 'Open'],
        <String>['Login', '', ''],
      ]);
    });

    test('is not a table without its divider line', () {
      expect(parseTable('| a | b |\n| c | d |'), isNull);
    });
  });

  group('growing a table from its drawing', () {
    const table = '| Bug | Owner |\n| --- | --- |\n| Seek bar | Matt |';

    test('adds a column: a heading, dashes and an empty cell on every row', () {
      expect(addTableColumn(table), '| Bug | Owner | Column |\n| --- | --- | --- |\n| Seek bar | Matt |  |');
    });

    test('adds an empty row as wide as the header, after the last row', () {
      expect(addTableRow(table), '| Bug | Owner |\n| --- | --- |\n| Seek bar | Matt |\n|  |  |');
    });

    test('grows a table written without outer pipes too', () {
      expect(addTableColumn('Bug | Owner\n--- | ---\nSeek | Matt'), 'Bug | Owner | Column\n--- | --- | ---\nSeek | Matt | ');
    });
  });

  // Not in the web's file, where these two are private to the widget: what the drawn table reads a cell through.
  group('a cell as the drawing reads it', () {
    test('its words without the markup that would show as symbols', () {
      expect(plainCell('Seek **bar** and _drift_ in `code` at [here](https://x.y)'), 'Seek bar and drift in code at here');
    });

    test('its links: a `[words](address)`’s words and an address said bare, where they stand in the words drawn', () {
      const hello = 'https://hello.trade/waitlist?ref=EXU6LYUP5K';
      var read = readCell('[hello.trade/waitlist?ref=EXU6LYUP5K]($hello)');
      expect(read.text, 'hello.trade/waitlist?ref=EXU6LYUP5K');
      expect(read.links, <CellLink>[const CellLink(from: 0, to: 35, url: hello)]);
      read = readCell('**Open** [the waitlist]($hello) or http://192.168.18.21:3120, then _wait_.');
      expect(read.text, 'Open the waitlist or http://192.168.18.21:3120, then wait.');
      expect(read.links, <CellLink>[const CellLink(from: 5, to: 17, url: hello), const CellLink(from: 21, to: 46, url: 'http://192.168.18.21:3120', bare: true)]);
      expect(read.text.substring(5, 17), 'the waitlist');
      // An address the brackets of a sentence close round.
      read = readCell('(see https://x.y/a)');
      expect(read.links.single.url, 'https://x.y/a');
      expect(read.text.substring(read.links.single.from, read.links.single.to), 'https://x.y/a');
      // A link's words in a mark of their own, and a mark round the link: the words are where they are drawn.
      read = readCell('**[bold words](https://x.y)** and `code`');
      expect(read.text, 'bold words and code');
      expect(read.links.single, const CellLink(from: 0, to: 10, url: 'https://x.y'));
    });

    test('its words are plainCell’s, letter for letter, whatever it holds', () {
      for (final raw in <String>[
        'Seek **bar** and _drift_ in `code` at [here](https://x.y)',
        'a_b [c_d](https://x.y/e_f) g_h https://x.y/i_j_k',
        '[[A note]] and [x](<https://x.y>) and <https://a.b>',
        'https:// and http://',
        'nothing at all',
        '',
      ]) {
        expect(readCell(raw).text, plainCell(raw), reason: raw);
      }
      expect(readCell('https:// and http://').links, isEmpty);
      expect(readCell('[x](<https://x.y>)').links.single.url, 'https://x.y');
    });

    test('where each cell starts in the table’s text, blank lines skipped, a left-aligned divider read', () {
      const text = '| a | bb |\n\n| :-- | --- |\n|  c |';
      final spans = cellSpans(text);
      expect(spans.length, 3);
      expect(spans[0], <({String raw, int at})>[(raw: 'a', at: 2), (raw: 'bb', at: 6)]);
      expect(text.substring(spans[2][0].at, spans[2][0].at + 1), 'c');
      expect(parseTable(text)!.align, <TableAlign?>[TableAlign.left, null]);
      expect(addTableRow('| a |\n| - |\n\n'), '| a |\n| - |\n|  |\n\n');
    });
  });
}
