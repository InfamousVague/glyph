import { describe, expect, it } from 'vitest';
import { show } from '../../../test/render.tsx';
import { ASK, COMMAND } from '../phrases.ts';
import { Tips } from './Tips.tsx';

/** The habits page, on every platform: the cues, and naming a note or asking the AI, with "Hey Ghost" first optional. */
describe('the guide’s habits page', () => {
  it('teaches the command and the ask the recorder’s readers are tested on (guide/guide.test.ts), said bare', () => {
    const el = show(<Tips />);
    expect(el.textContent).toContain('Name a note to send words to it.');
    expect(el.textContent).toContain(`“${COMMAND.say}” puts it in your ${COMMAND.note} note`);
    expect(el.textContent).toContain('“Add a note to Work, call Sam”');
    expect(el.textContent).toContain(`“${ASK.say}” asks the AI`);
    expect(el.textContent).toContain('“Hey Ghost” first is optional.');
    expect(COMMAND.say).not.toMatch(/Hey Ghost/);
    expect(ASK.say).not.toMatch(/Hey Ghost/);
  });

  it('promises nothing the cues do not do: they lay the words out and never change them', () => {
    const el = show(<Tips />);
    expect(el.textContent).toContain('never the words');
    expect(el.textContent).not.toMatch(/memo mode|robot|✨/i);
  });
});
