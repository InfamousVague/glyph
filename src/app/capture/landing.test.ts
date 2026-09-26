import { describe, expect, it } from 'vitest';
import { takeOut } from './landing.ts';

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
