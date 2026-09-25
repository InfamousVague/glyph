import { describe, expect, it } from 'vitest';
import { askMessage, budgetForKind, CONTINUE_PROMPT, FIX_PROMPT, promptForKind, SHAPE_PROMPT } from './prompts.ts';
import { SYSTEM_PROMPT } from '../format/prompt.ts';

describe('the newer prompts', () => {
  it('each ask for the answer alone, and keep the links as tokens', () => {
    for (const prompt of [FIX_PROMPT, SHAPE_PROMPT, CONTINUE_PROMPT, promptForKind('ask')]) {
      expect(prompt).toContain('link-1');
      expect(prompt).toContain('nothing else');
    }
    expect(promptForKind('format')).toBe(SYSTEM_PROMPT);
  });

  it('give a fix the note again, a continuation a few lines, and an ask as much as an enhancement', () => {
    expect(budgetForKind('fix', 4000)).toBe(1314);
    expect(budgetForKind('fix', 10)).toBe(128);
    expect(budgetForKind('continue', 4000)).toBe(398);
    expect(budgetForKind('continue', 40000)).toBe(512);
    expect(budgetForKind('ask', 4000)).toBe(2256);
    expect(budgetForKind('format', 4000)).toBe(2192);
  });

  it('puts the instruction before the note', () => {
    expect(askMessage('  shorten it ', '# A\n')).toBe('Instruction: shorten it\n\nThe note:\n# A\n');
  });
});
