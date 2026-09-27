import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { MODES } from './modes.ts';
import { budgetFor, ENHANCE_PROMPT, outputBudget, promptFor, RECORDING_NOTES_PROMPT, RECORDING_SUMMARY_PROMPT, recordingNotesBudget, recordingSummaryBudget, SUMMARIZE_PROMPT, SYSTEM_PROMPT } from './prompt.ts';

describe('the recording prompts', () => {
  it('ask for a box only on the person recording’s own to-dos, and can be read by name from the Mac’s test', () => {
    for (const prompt of [RECORDING_SUMMARY_PROMPT, RECORDING_NOTES_PROMPT]) {
      expect(prompt.startsWith('You are the editor inside Ghost.md')).toBe(true);
      expect(prompt).toContain('"- [ ] "');
      expect(prompt).toContain('Never a task item');
      expect(prompt).toContain('[the words](link-1)');
    }
    expect(RECORDING_SUMMARY_PROMPT).toContain('Decided: ');
    expect(RECORDING_SUMMARY_PROMPT).toContain('no numbered lists');
    expect(RECORDING_SUMMARY_PROMPT.endsWith('no code fence around it.')).toBe(true);
    // The rule for other people's actions sits with the points, where the example puts "- Sam: the press list."
    const points = RECORDING_SUMMARY_PROMPT.split('\n').find((line) => line.includes('three to eight points'));
    expect(points).toContain("Other people's actions are points, with the name first");
    // src-tauri/src/llm/tests.rs `page_prompt_in` copies a literal's source up to its closing backtick: each is a plain
    // String.raw literal with nothing built in, so what it reads is what the phone sends.
    const source = readFileSync(join(process.cwd(), 'src/app/format/prompt.ts'), 'utf8');
    for (const [name, prompt] of [
      ['RECORDING_SUMMARY_PROMPT', RECORDING_SUMMARY_PROMPT],
      ['RECORDING_NOTES_PROMPT', RECORDING_NOTES_PROMPT],
    ] as const) {
      const opener = `${name} = String.raw\``;
      const start = source.indexOf(opener) + opener.length;
      const end = source.indexOf('`', start);
      expect(source.slice(start, end).trim()).toBe(prompt);
    }
  });

  it('give a summary a sixth of the transcript and a piece’s notes a quarter of the piece, within their floors and ceilings', () => {
    expect(recordingSummaryBudget(100)).toBe(200);
    expect(recordingSummaryBudget(20_000)).toBe(Math.ceil(5000 / 6) + 96);
    expect(recordingSummaryBudget(400_000)).toBe(1024);
    expect(recordingNotesBudget(100)).toBe(128);
    expect(recordingNotesBudget(4000)).toBe(1000 / 4 + 64);
    expect(recordingNotesBudget(100_000)).toBe(512);
  });
});

describe('the prompts', () => {
  it('has one per mode, each keeping links as tokens and asking for markdown alone', () => {
    for (const { id } of MODES) {
      const prompt = promptFor(id);
      expect(prompt.startsWith('You are the editor inside Ghost.md')).toBe(true);
      expect(prompt).toContain('[the words](link-1)');
      expect(prompt.endsWith('no code fence around it.')).toBe(true);
    }
    expect(promptFor('format')).toBe(SYSTEM_PROMPT);
    expect(promptFor('summarize')).toBe(SUMMARIZE_PROMPT);
    expect(promptFor('enhance')).toBe(ENHANCE_PROMPT);
    expect(new Set([SYSTEM_PROMPT, SUMMARIZE_PROMPT, ENHANCE_PROMPT]).size).toBe(3);
  });

  it('gives a summary less room than the note and an enhancement more', () => {
    const chars = 2000; // about 500 tokens
    expect(budgetFor('format', chars)).toBe(outputBudget(chars));
    expect(budgetFor('summarize', chars)).toBeLessThan(budgetFor('format', chars));
    expect(budgetFor('enhance', chars)).toBeGreaterThan(budgetFor('format', chars));
    // Floors for a tiny note, ceilings for a huge one.
    expect(budgetFor('summarize', 10)).toBe(160);
    expect(budgetFor('enhance', 10)).toBe(512);
    expect(budgetFor('summarize', 100_000)).toBe(768);
    expect(budgetFor('enhance', 100_000)).toBe(4096);
  });
});
