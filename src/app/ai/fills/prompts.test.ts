import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import * as prompts from './prompts.ts';

/** The prompts' source, as the Rust tests read it (src-tauri/src/llm/tests.rs `page_prompt_in`). */
const source = readFileSync(resolve(process.cwd(), 'src/app/ai/fills/prompts.ts'), 'utf8');

/** A literal as Rust reads it: from its opening backtick to the next one. */
function literal(name: string): string {
  const opener = `${name} = String.raw\``;
  const start = source.indexOf(opener) + opener.length;
  return source.slice(start, source.indexOf('`', start)).trim();
}

const NAMES = ['FILL_PROMPT', 'FILL_WEB_PROMPT', 'FILL_CORE', 'FILL_ANSWER', 'FILL_NUMBER', 'FILL_TITLE', 'FILL_SUMMARY', 'FILL_ITEMS', 'FILL_CELL', 'FILL_TRANSLATE'] as const;

describe('the fill prompts', () => {
  it('are literals the Rust tests read whole: no ${…} and no backtick inside', () => {
    for (const name of NAMES) {
      expect(literal(name), name).toBe(prompts[name].trim());
      expect(prompts[name], name).not.toContain('${');
    }
  });

  it('name UNKNOWN, never “Never invent”, and answer their examples in [1] lines', () => {
    const prompt = prompts.FILL_PROMPT;
    expect(prompt).toContain('answer exactly: UNKNOWN');
    expect(prompt).not.toContain('Never invent');
    expect(prompt.match(/^\[\d\] /gm)?.length).toBe(8);
    expect(prompt.endsWith('[1] おはようございます (ohayō gozaimasu)')).toBe(true);
  });

  it('give every third-rung block its worked example', () => {
    for (const name of ['FILL_ANSWER', 'FILL_NUMBER', 'FILL_TITLE', 'FILL_SUMMARY', 'FILL_ITEMS', 'FILL_CELL', 'FILL_TRANSLATE'] as const) expect(prompts[name], name).toContain('Example.');
  });

  it('keep the web prompt to what the source returned', () => {
    expect(prompts.FILL_WEB_PROMPT).toContain('Answer only from what the source returned.');
    expect(prompts.FILL_WEB_PROMPT).toContain('answer exactly: UNKNOWN');
  });
});
