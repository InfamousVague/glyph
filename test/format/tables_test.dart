// A port of src/app/format/tables.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/links.dart';
import 'package:ghost_md/format/tables.dart';

const table = '| Bug | Owner | Status |\n|:----|:-----:|-------:|\n| Login loops | Sam | open |\n| Dark theme | Matt | fixed |';
const note = '# Bug bash\n\nWhat we found on Friday.\n\n$table\n\nNext round on Monday.\n';

void main() {
  group('tables through the model', () {
    test('swaps a table block for one token line and puts the block back verbatim', () {
      final guarded = protectTables(note);
      expect(guarded.text, '# Bug bash\n\nWhat we found on Friday.\n\n![table-1](table)\n\nNext round on Monday.\n');
      expect(guarded.tables, [const ProtectedTable(token: 'table-1', block: table)]);
      const rewrite = '# Bug bash\n\nWhat we found on Friday:\n\n![table-1](table)\n\n- [ ] Next round on Monday.\n';
      expect(restoreTables(rewrite, guarded.tables), '# Bug bash\n\nWhat we found on Friday:\n\n$table\n\n- [ ] Next round on Monday.\n');
    });

    test('takes the token however the model wrote it, and unburies one from a sentence', () {
      final tables = protectTables(note).tables;
      expect(restoreTables('[table-1]\n', tables), '$table\n');
      expect(restoreTables('<table-1>\n', tables), '$table\n');
      expect(restoreTables('  table 1  \n', tables), '$table\n');
      expect(restoreTables('The bugs are in [table-1] below.\n', tables), 'The bugs are in \n\n$table\n\n below.\n');
    });

    test('appends a table whose token vanished, unless told a summary may drop it', () {
      final tables = protectTables(note).tables;
      expect(restoreTables('# Bug bash\n\nFound on Friday.\n', tables), '# Bug bash\n\nFound on Friday.\n\n$table\n');
      expect(restoreTables('# Bug bash\n\nFound on Friday.\n', tables, isFinal: true, appendMissing: false), '# Bug bash\n\nFound on Friday.\n');
      expect(restoreTables('# Bug bash\n\nFound on', tables, isFinal: false), '# Bug bash\n\nFound on');
    });

    test('numbers several tables and tells table-1 from table-10', () {
      final many = List.generate(10, (i) => '| a$i |\n|---|\n| $i |').join('\n\ntext\n\n');
      final guarded = protectTables(many);
      expect(guarded.tables, hasLength(10));
      expect(guarded.text, contains('![table-10](table)'));
      expect(restoreTables(guarded.text, guarded.tables), many);
    });

    test('does not mistake a rule or a line with a pipe for a table', () {
      const plain = 'either | or\n\n---\n\n| lonely |\n';
      expect(protectTables(plain), const ProtectedTables(text: plain, tables: []));
    });

    test('keeps a link inside a cell whole: tables first, then links, and back in reverse', () {
      const linked = 'See the board.\n\n| Task | Where |\n|---|---|\n| Buy milk | [board](https://www.notion.so/x) |\n\nand https://example.com/a after.\n';
      final guarded = protectTables(linked);
      final masked = protectLinks(guarded.text);
      expect(masked.text, 'See the board.\n\n![table-1](table)\n\nand <link-1> after.\n');
      expect(masked.links, hasLength(1));
      final back = restoreTables(restoreLinks(masked.text, masked.links), guarded.tables);
      expect(back, linked);
    });
  });
}
