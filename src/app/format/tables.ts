/**
 * Tables through the model, kept by construction, like links (links.ts).
 *
 * A note can carry a GFM table (editor/tables.ts draws them; the recorder
 * builds them by voice), and a table is exactly what a small model rewriting
 * a note will mangle: cells reordered, a column dropped, the pipes lost. So
 * before the note goes in, each table block - a header row with pipes, a
 * delimiter row of dashes, then every following row with pipes - is swapped
 * for one line the model can copy, and after the rewrite the line is swapped
 * back for the block, verbatim. Tables go first, before links, so a link in
 * a cell is inside the block and never touched.
 *
 * The line is shaped like a picture, `![table-1](table)`: measured with the
 * 4B, a bare `[table-1]` was dropped as noise even when the prompt asked for
 * it, while a picture line - which the prompt has always asked to be copied
 * exactly, on its own line - is kept every time.
 *
 * A token that does not come back is appended at the end of the note, for
 * the modes that keep everything; a summary is allowed to leave a table out.
 */

export interface ProtectedTable {
  /** `table-2`: what stands in for the block while the model works. */
  token: string;
  /** The block's lines, joined with newlines, exactly as written. */
  block: string;
}

export interface ProtectedTables {
  text: string;
  tables: ProtectedTable[];
}

/** A GFM delimiter row: cells of dashes, an optional colon at either end, pipes between. */
const DELIMITER = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

/** The note with every table block replaced by a token line, and the blocks to put back. */
export function protectTables(body: string): ProtectedTables {
  const lines = body.split('\n');
  const out: string[] = [];
  const tables: ProtectedTable[] = [];
  let i = 0;
  while (i < lines.length) {
    const header = lines[i]!;
    const delimiter = lines[i + 1];
    if (header.includes('|') && delimiter !== undefined && delimiter.includes('|') && DELIMITER.test(delimiter)) {
      let end = i + 2;
      while (end < lines.length && lines[end]!.includes('|') && lines[end]!.trim() !== '') end += 1;
      const token = `table-${tables.length + 1}`;
      tables.push({ token, block: lines.slice(i, end).join('\n') });
      out.push(`![${token}](table)`);
      i = end;
    } else {
      out.push(header);
      i += 1;
    }
  }
  return { text: out.join('\n'), tables };
}

/**
 * The rewrite with its tables back: a line that is the token, however the
 * model wrote it (`![table-1](table)`, `[table-1]`, `table 1`), becomes the block; a
 * token buried in a sentence gets the block on its own lines. With `final`
 * and `appendMissing`, a block whose token never came back is added at the
 * end; a partial rewrite still streaming is only substituted.
 */
export function restoreTables(text: string, tables: readonly ProtectedTable[], final = true, appendMissing = true): string {
  let out = text;
  const missing: ProtectedTable[] = [];
  for (const table of tables) {
    const number = table.token.slice('table-'.length);
    // Spaces and tabs only, never `\s`: that would swallow the line's newline.
    const token = `!?[[<(]?[ \\t]*table[ \\t-]?${number}(?!\\d)[ \\t]*[\\]>)]?(?:\\([ \\t]*table[ \\t]*\\))?`;
    let found = false;
    out = out.replace(new RegExp(`^[ \\t]*${token}[ \\t]*$`, 'gim'), () => {
      found = true;
      return table.block;
    });
    out = out.replace(new RegExp(token, 'gi'), () => {
      found = true;
      return `\n\n${table.block}\n\n`;
    });
    if (!found) missing.push(table);
  }
  if (!final || !appendMissing || !missing.length) return out;
  return `${out.replace(/\s+$/, '')}\n\n${missing.map((t) => t.block).join('\n\n')}\n`;
}
