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
