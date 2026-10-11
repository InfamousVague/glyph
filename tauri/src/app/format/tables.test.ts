import { describe, expect, it } from 'vitest';
import { protectLinks, restoreLinks } from './links.ts';
import { protectTables, restoreTables } from './tables.ts';

const TABLE = '| Bug | Owner | Status |\n|:----|:-----:|-------:|\n| Login loops | Sam | open |\n| Dark theme | Matt | fixed |';
const NOTE = `# Bug bash\n\nWhat we found on Friday.\n\n${TABLE}\n\nNext round on Monday.\n`;

describe('tables through the model', () => {
  it('swaps a table block for one token line and puts the block back verbatim', () => {
    const { text, tables } = protectTables(NOTE);
    expect(text).toBe('# Bug bash\n\nWhat we found on Friday.\n\n![table-1](table)\n\nNext round on Monday.\n');
    expect(tables).toEqual([{ token: 'table-1', block: TABLE }]);
    const rewrite = '# Bug bash\n\nWhat we found on Friday:\n\n![table-1](table)\n\n- [ ] Next round on Monday.\n';
    expect(restoreTables(rewrite, tables)).toBe(`# Bug bash\n\nWhat we found on Friday:\n\n${TABLE}\n\n- [ ] Next round on Monday.\n`);
  });

  it('takes the token however the model wrote it, and unburies one from a sentence', () => {
    const { tables } = protectTables(NOTE);
    expect(restoreTables('[table-1]\n', tables)).toBe(`${TABLE}\n`);
    expect(restoreTables('<table-1>\n', tables)).toBe(`${TABLE}\n`);
    expect(restoreTables('  table 1  \n', tables)).toBe(`${TABLE}\n`);
    expect(restoreTables('The bugs are in [table-1] below.\n', tables)).toBe(`The bugs are in \n\n${TABLE}\n\n below.\n`);
  });

  it('appends a table whose token vanished, unless told a summary may drop it', () => {
    const { tables } = protectTables(NOTE);
    expect(restoreTables('# Bug bash\n\nFound on Friday.\n', tables)).toBe(`# Bug bash\n\nFound on Friday.\n\n${TABLE}\n`);
    expect(restoreTables('# Bug bash\n\nFound on Friday.\n', tables, true, false)).toBe('# Bug bash\n\nFound on Friday.\n');
    expect(restoreTables('# Bug bash\n\nFound on', tables, false)).toBe('# Bug bash\n\nFound on');
  });

  it('numbers several tables and tells table-1 from table-10', () => {
    const many = Array.from({ length: 10 }, (_, i) => `| a${i} |\n|---|\n| ${i} |`).join('\n\ntext\n\n');
    const { text, tables } = protectTables(many);
    expect(tables).toHaveLength(10);
    expect(text).toContain('![table-10](table)');
    expect(restoreTables(text, tables)).toBe(many);
  });

  it('does not mistake a rule or a line with a pipe for a table', () => {
    const note = 'either | or\n\n---\n\n| lonely |\n';
    expect(protectTables(note)).toEqual({ text: note, tables: [] });
  });

  it('keeps a link inside a cell whole: tables first, then links, and back in reverse', () => {
    const note = `See the board.\n\n| Task | Where |\n|---|---|\n| Buy milk | [board](https://www.notion.so/x) |\n\nand https://example.com/a after.\n`;
    const guarded = protectTables(note);
    const { text, links } = protectLinks(guarded.text);
    expect(text).toBe('See the board.\n\n![table-1](table)\n\nand <link-1> after.\n');
    expect(links).toHaveLength(1);
    const back = restoreTables(restoreLinks(text, links), guarded.tables);
    expect(back).toBe(note);
  });
});
