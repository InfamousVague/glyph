import { describe, expect, it } from 'vitest';
import { show } from '../../../test/render.tsx';
import { ASK, COMMAND } from '../phrases.ts';
import { Tips } from './Tips.tsx';

/** The habits page, on every platform: the cues, and "Hey Ghost" first for a command or an ask. */
describe('the guide’s habits page', () => {
  it('teaches “Hey Ghost” with the command and the ask the recorder’s readers are tested on (guide/guide.test.ts)', () => {
    const el = show(<Tips />);
    expect(el.textContent).toContain('Start with “Hey Ghost” to give a command.');
    expect(el.textContent).toContain(`“${COMMAND.say}” puts it in your ${COMMAND.note} note`);
    expect(el.textContent).toContain(`“${ASK.say}” asks the AI`);
  });

  it('promises nothing the cues do not do: they lay the words out and never change them', () => {
    const el = show(<Tips />);
    expect(el.textContent).toContain('never the words');
    expect(el.textContent).not.toMatch(/memo mode|robot|✨/i);
  });
});
