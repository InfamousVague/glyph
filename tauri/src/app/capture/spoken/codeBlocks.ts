import { capitalise } from '../../core/text.ts';
import type { Block } from './blocks.ts';

/**
 * Code said aloud: "code block in bash. npm run build. End code block." is a fenced block, a line for each sentence
 * said, lower case and without the commas Whisper puts at its pauses, as a command is typed.
 *
 * A code block runs until its "end code block" however long the pauses inside it were, so the paragraphs a pause
 * would have made are put back together first (`withCodeBlocksWhole`), and then each paragraph is cut around the
 * blocks said in it (`codeBlocksIn`). Pure.
 */

const CODE_LANGUAGES = String.raw`java\s?script|type\s?script|python|rust|bash|shell|json|html|css|sql|swift|kotlin|yaml|ruby|go`;

/** "Code block in bash. npm run build. End code block.": a block of code, a line for each sentence said. */
const CODE_BLOCK_SAID = new RegExp(
  String.raw`\bcode\s?block\b[.,:]?\s*(?:(?:in\s+|and\s+)?(${CODE_LANGUAGES})\b[.,:]?\s*)?([\s\S]*?)[.,;]?\s*\b(?:end|and)\s+code\s?block\b[.,!]?`,
  'gi',
);
const CODE_BLOCK_OPEN = /\bcode\s?block\b/gi;
const CODE_BLOCK_CLOSE = /\b(?:end|and)\s+code\s?block\b/gi;

/** Paragraphs with a spoken code block kept in one, however long the pauses inside it were. */
export function withCodeBlocksWhole(paragraphs: readonly string[]): string[] {
  const out: string[] = [];
  let open = false;
  for (const paragraph of paragraphs) {
    if (open) out[out.length - 1] = `${out[out.length - 1]} ${paragraph}`;
    else out.push(paragraph);
    const opened = (out[out.length - 1]!.match(CODE_BLOCK_OPEN) ?? []).length;
    const closed = (out[out.length - 1]!.match(CODE_BLOCK_CLOSE) ?? []).length;
    open = opened > closed;
  }
  return out;
}

/** A stretch of a paragraph: words, or a code block said in it. */
export type Piece = { kind: 'text'; text: string } | Extract<Block, { kind: 'fence' }>;

/** A paragraph cut around the code blocks said in it. */
export function codeBlocksIn(paragraph: string): Piece[] {
  const pieces: Piece[] = [];
  let from = 0;
  for (const found of paragraph.matchAll(CODE_BLOCK_SAID)) {
    const code = (found[2] ?? '')
      .split(/(?<=[.;!?])\s+/)
      .map((line) => line.trim().replace(/[.;,]+$/, '').replace(/,/g, '').toLowerCase())
      .filter(Boolean);
    if (!code.length) continue;
    const before = paragraph.slice(from, found.index).trim();
    if (before) pieces.push({ kind: 'text', text: before });
    pieces.push({ kind: 'fence', lang: (found[1] ?? '').toLowerCase().replace(/\s+/g, ''), text: code.join('\n') });
    from = (found.index ?? 0) + found[0].length;
  }
  const rest = paragraph.slice(from).trim();
  if (rest || !pieces.length) pieces.push({ kind: 'text', text: capitalise(rest) });
  return pieces;
}
