import { describe, expect, it } from 'vitest';
import { landingLine, takeOut } from './landing.ts';

/** `doc` with the changes `takeOut` found made. */
const undone = (doc: string, blocks: string[]) => {
  const { changes, missing } = takeOut(doc, blocks);
  let out = doc;
  for (const change of [...changes].reverse()) out = out.slice(0, change.from) + out.slice(change.to);
  return { out, missing };
};

describe('taking a recording’s words out of the note again', () => {
  it('takes out an item it put in a list, and the break before it', () => {
    expect(undone('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', ['- [ ] Call Sam'])).toEqual({ out: '# House TODOs\n\n- [ ] Fix the gutter\n', missing: 0 });
  });

  it('takes out a paragraph it put at the end, with the blank line before it', () => {
    expect(undone('# Daily Life\n\nWent for a walk.\n\nWent for a run.', ['Went for a run.'])).toEqual({ out: '# Daily Life\n\nWent for a walk.', missing: 0 });
  });

  it('takes out several pieces, in several lists', () => {
    const doc = '## Electrical\n- [ ] Rewire\n- [ ] Call Sam\n\n## Garden\n- [ ] Mow\n- [ ] Trim the hedge\n';
    expect(undone(doc, ['- [ ] Call Sam', '- [ ] Trim the hedge']).out).toBe('## Electrical\n- [ ] Rewire\n\n## Garden\n- [ ] Mow\n');
  });

  it('leaves a piece edited since, or there twice, as it is', () => {
    expect(undone('- [ ] Call Sam tomorrow\n', ['- [ ] Call Sam'])).toEqual({ out: '- [ ] Call Sam tomorrow\n', missing: 1 });
    expect(undone('- [ ] Call Sam\n- [ ] Call Sam\n', ['- [ ] Call Sam'])).toEqual({ out: '- [ ] Call Sam\n- [ ] Call Sam\n', missing: 1 });
  });
});

describe('what the note’s toast says', () => {
  const landing = { noteId: 'n', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: [] };

  it('names the note the words went into, and the others', () => {
    expect(landingLine(landing)).toBe('Added to House TODOs');
    expect(landingLine({ ...landing, others: ['m1'], into: ['Home jobs'] })).toBe('Added to House TODOs and Home jobs');
    expect(landingLine({ ...landing, others: ['m1', 'm2'], into: ['Home jobs', 'Todo'] })).toBe('Added to House TODOs and 2 other notes');
  });

  it('names only the others for a note of the take’s own, which had nothing added to it', () => {
    expect(landingLine({ ...landing, title: 'Buy milk', blocks: [], others: ['m1', 'm2'], into: ['House TODOs', 'Home jobs'] })).toBe('Added to House TODOs and Home jobs');
  });
});
