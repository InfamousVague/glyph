import { describe, expect, it } from 'vitest';
import { quietHost } from '../../test/takeHost.ts';
import { Take, takeMarkdown } from './take.ts';

/**
 * A take as markdown (capture/take.ts `takeMarkdown`): the one way the page it is spoken onto and the note saved at
 * Done are made from it, so the two cannot disagree.
 */

const said = (text: string, startMs: number) => ({ text, startMs, endMs: startMs + 900 });

describe('a take’s markdown', () => {
  it('lays the words out by their cues, with the phrase still being guessed after them and marked as pending', () => {
    const shown = takeMarkdown({ segments: [said('Grocery run.', 0), said('Bullet point, eggs.', 1000)] }, { titled: true, partial: 'and milk' });
    expect(shown.markdown).toBe('# Grocery run\n\n- Eggs\n\nand milk');
    expect(shown.pendingFrom).toBe(shown.markdown.indexOf('and milk'));
  });

  it('keeps an opening sentence as a sentence when the words go on the end of a note that has a title', () => {
    expect(takeMarkdown({ segments: [said('Grocery run.', 0)] }, { titled: false }).markdown).toBe('Grocery run.');
  });

  it('applies links, after which there is no telling where the guess starts', () => {
    const linked = takeMarkdown({ segments: [said('Book the cabin.', 0)] }, { titled: false, partial: 'soon', link: (text) => text.replace('cabin', '[cabin](https://example.com)') });
    expect(linked.markdown).toBe('Book the [cabin](https://example.com). soon');
    expect(linked.pendingFrom).toBeNull();
  });
});

describe('what a take has to save', () => {
  it('is words that come to something', () => {
    const take = new Take(quietHost());
    expect(take.hasContent).toBe(false);
    take.listen(said('Hello.', 0));
    expect(take.hasContent).toBe(true);
  });

  it('is not a cue said on its own, which is held for a sentence that never comes', () => {
    const take = new Take(quietHost());
    take.listen(said('Bullet point.', 0));
    expect(take.segments).toHaveLength(1);
    expect(take.hasContent).toBe(false);
  });
});
