import { describe, expect, it } from 'vitest';
import { protectEmbeds, restoreEmbeds } from './embeds.ts';

/**
 * A place or a video line through the model (format/embeds.ts): swapped for a picture-shaped token the model copies,
 * and put back exactly, so a model can neither move a place's coordinates nor describe it.
 */

const CAIS = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
const VIDEO = '[![video 0:12](image/poster.jpg)](video/0f8fad5b-d9cb-469f-a165-70867728950e.mp4)';

describe('a place or a video line through the model', () => {
  it('goes in as a token line and comes back as written, lead and all', () => {
    const body = `# Lisbon\n\nLunch\n- ${CAIS}\n\n${VIDEO}\n`;
    const { text, embeds } = protectEmbeds(body);
    expect(text).toBe('# Lisbon\n\nLunch\n![place-1](place)\n\n![video-1](video)\n');
    expect(text).not.toContain('geo:');
    expect(restoreEmbeds(text, embeds)).toBe(body);
  });

  it('comes back however the model wrote the token, and on a line of its own when it was buried in words', () => {
    const { embeds } = protectEmbeds(`${CAIS}\n${CAIS}\n`);
    expect(restoreEmbeds('[place-1]\nplace 2\n', embeds)).toBe(`${CAIS}\n${CAIS}\n`);
    expect(restoreEmbeds('We ate at ![place-1](place) by the river.', embeds.slice(0, 1))).toBe(`We ate at \n\n${CAIS}\n\n by the river.`);
  });

  it('is never read as another’s token once it is back, whatever the place is called', () => {
    const market = '[Market place 2](geo:38.7100,-9.1400)';
    const { text, embeds } = protectEmbeds(`${market}\n${CAIS}\n`);
    expect(restoreEmbeds(text, embeds)).toBe(`${market}\n${CAIS}\n`);
  });

  it('is added at the end when the model lost it, except in a summary, which may leave it out', () => {
    const { embeds } = protectEmbeds(`Lunch\n${CAIS}`);
    expect(restoreEmbeds('Lunch was lovely.', embeds)).toBe(`Lunch was lovely.\n\n${CAIS}\n`);
    expect(restoreEmbeds('Lunch was lovely.', embeds, true, false)).toBe('Lunch was lovely.');
    // Still streaming: only what has come is put back.
    expect(restoreEmbeds('Lunch was', embeds, false)).toBe('Lunch was');
  });

  it('leaves a place inside words, and one in code, to the words and the code', () => {
    const body = `Met at ${CAIS}\n\n\`\`\`\n${CAIS}\n\`\`\``;
    expect(protectEmbeds(body)).toEqual({ text: body, embeds: [] });
  });
});
