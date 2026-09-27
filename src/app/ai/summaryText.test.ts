import { describe, expect, it } from 'vitest';
import { carryTicked, dateTitled, ONE_PASS_CHARS, shapeSummary, summaryLine, summaryPlace, summarySection, transcriptPieces, withoutSummary, withSummary } from './summaryText.ts';

/**
 * The summary section (docs/DESIGN.md §127 section 2): its shape, how it is found again by that shape and closed by
 * what follows it, where a fresh one goes, how a remake treats the one there, and the pieces a long transcript is
 * cut into. Every rule is a case here, since two writers depend on them: the queue and the editor.
 */

const SECTION = ['## Summary', 'What the call settled about the March launch.', '', '- Launch moves to the second week of March.', '- Decided: no paid ads until the beta closes.', '', '- [ ] Send Sam the press list by Friday.', '- [ ] Book the venue before the 10th.'].join('\n');

describe('the shape', () => {
  it('takes the heading for the title, keeps one prose line and only item lines, and drops the rest', () => {
    const model = ['# Planning call with Sam', 'What the call settled about the March launch.', 'Sam sounded tired.', '', '- Launch moves to the second week of March.', '* Decided: no paid ads until the beta closes.', '', '', '- [ ] Send Sam the press list by Friday.', '- [ ] Book the venue before the 10th.', '', 'Let me know if you need more.'].join('\n');
    expect(shapeSummary(model)).toEqual({ title: 'Planning call with Sam', section: SECTION });
  });

  it('never writes the model’s echoed heading, a rule or a code fence into the section', () => {
    expect(shapeSummary('```markdown\n## Summary\nTwo errands.\n---\n- [ ] Milk.\n```')).toEqual({ title: null, section: '## Summary\nTwo errands.\n\n- [ ] Milk.' });
    expect(shapeSummary('')).toEqual({ title: null, section: '' });
    expect(shapeSummary('# Only a name')).toEqual({ title: 'Only a name', section: '' });
  });

  it('only ever grows as the model streams, so a run’s landed lines never move', () => {
    const whole = '# Planning call\nWhat the call settled.\n- Launch moves.\n- [ ] Send the list.\n';
    let last = '';
    for (let n = 0; n <= whole.length; n += 1) {
      const { section } = shapeSummary(whole.slice(0, n));
      const lines = section.split('\n').slice(0, -1);
      expect(section.startsWith(lines.join('\n'))).toBe(true);
      // Every finished line of the answer so far is a finished line of the next one.
      const finished = last.split('\n').slice(0, -1).join('\n');
      expect(section.startsWith(finished)).toBe(true);
      last = section;
    }
  });
});

describe('finding the section', () => {
  it('is found by its shape, and closed by a paragraph, a heading, a rule, or the transcript', () => {
    const paragraphs = `# Planning call\n\n${SECTION}\n\nWe started with the launch date.\n\nThen the press.`;
    expect(summarySection(paragraphs)?.text).toBe(SECTION);
    expect(paragraphs.slice(summarySection(paragraphs)!.start, summarySection(paragraphs)!.end)).toBe(SECTION);
    expect(summarySection(`# T\n${SECTION}\n## Transcript\nWords.`)?.text).toBe(SECTION);
    expect(summarySection(`# T\n${SECTION}\n\n---\nWords.`)?.text).toBe(SECTION);
    expect(summarySection('# T\nNo section here.')).toBeNull();
    // A `## Summary` inside the front matter's lines is not the section; one after it is.
    expect(summarySection('---\ntitle: x\n---\n# T\n## Summary\nA line.')?.text).toBe('## Summary\nA line.');
  });

  it('takes a prose line only straight after the heading, so a dictated paragraph after items is not the section’s', () => {
    expect(summarySection('# T\n## Summary\n- One.\n- Two.\n\nA paragraph said later.')?.text).toBe('## Summary\n- One.\n- Two.');
    expect(summarySection('# T\n## Summary\nThe line.\nA second line ends it.')?.text).toBe('## Summary\nThe line.');
  });

  it('answers the prose line for the shelf, the toast and the notification', () => {
    expect(summaryLine(`# T\n\n${SECTION}`)).toBe('What the call settled about the March launch.');
    expect(summaryLine('# T\n## Summary\n- Only items.')).toBeNull();
    expect(summaryLine('# T\nNothing.')).toBeNull();
  });
});

describe('its place', () => {
  const at = (body: string) => body.slice(0, summaryPlace(body));

  it('is after the first line of words, whatever its marks, and after the front matter', () => {
    expect(at('# Title\n\nWords.')).toBe('# Title\n');
    expect(at('A plain first line\nthat runs on.\n\nMore.')).toBe('A plain first line\nthat runs on.\n');
    expect(at('- [ ] Call Sam\n- [ ] Book the venue\n\nNotes.')).toBe('- [ ] Call Sam\n- [ ] Book the venue\n');
    expect(at('![](image/a.jpg)\n# Title\nWords.')).toBe('![](image/a.jpg)\n# Title\n');
    expect(at('---\ntitle: x\n---\n# Title\nWords.')).toBe('---\ntitle: x\n---\n# Title\n');
    expect(at('---\ntitle: x\n---\nPlain line.\n\nWords.')).toBe('---\ntitle: x\n---\nPlain line.\n');
    expect(at('---\ntitle: x\n---\n- [ ] Task\nWords.')).toBe('---\ntitle: x\n---\n- [ ] Task\nWords.');
    expect(at('---\ntitle: x\n---\n![](p.png)\n# T\n')).toBe('---\ntitle: x\n---\n![](p.png)\n# T\n');
    expect(summaryPlace('# Title')).toBe('# Title'.length);
    expect(summaryPlace('')).toBe(0);
  });
});

describe('writing it', () => {
  it('writes a fresh section under the title with a blank line either side', () => {
    expect(withSummary('# Planning call\n\nWe started with the launch.', SECTION)).toBe(`# Planning call\n\n${SECTION}\n\nWe started with the launch.`);
    expect(withSummary('# Planning call\nWe started.', SECTION)).toBe(`# Planning call\n\n${SECTION}\n\nWe started.`);
    expect(withSummary('# Planning call', SECTION)).toBe(`# Planning call\n\n${SECTION}`);
    expect(withSummary('', '## Summary\nA line.')).toBe('## Summary\nA line.');
  });

  it('replaces the section it has, whole, and leaves every paragraph after it', () => {
    const body = `# Planning call\n\n${SECTION}\n\nWe started with the launch.\n\nThen the press.`;
    const next = '## Summary\nA newer line.\n\n- [ ] One thing.';
    expect(withSummary(body, next)).toBe(`# Planning call\n\n${next}\n\nWe started with the launch.\n\nThen the press.`);
  });

  it('takes the model’s heading as the title only while the note still wears its date title', () => {
    const meeting = '# Meeting, 26 Sep 14:05\n\n## Transcript\nWords.';
    expect(withSummary(meeting, '## Summary\nA line.', { title: 'Planning call' })).toBe('# Planning call\n\n## Summary\nA line.\n\n## Transcript\nWords.');
    expect(withSummary('# Sam’s call\n\nWords.', '## Summary\nA line.', { title: 'Planning call' })).toBe('# Sam’s call\n\n## Summary\nA line.\n\nWords.');
    expect(dateTitled('# Meeting, Sep 26 09:15')).toBe(true);
    expect(dateTitled('Meeting, 26 Sep 14:05\n')).toBe(true);
    expect(dateTitled('# Meeting with Sam')).toBe(false);
  });

  it('takes the section off for a compare, and the blank that went with it', () => {
    const body = `# Planning call\n\n${SECTION}\n\nWe started with the launch.`;
    expect(withoutSummary(body)).toBe('# Planning call\n\nWe started with the launch.');
    expect(withoutSummary(`# Planning call\n\n${SECTION}`)).toBe('# Planning call');
    expect(withoutSummary('# Planning call\n\nWords.')).toBe('# Planning call\n\nWords.');
  });

  it('carries every ticked to-do of the old section into the new one, verbatim, after the new to-dos', () => {
    const old = '## Summary\nOld line.\n\n- [x] Send Sam the press list.\n- [ ] Book the venue.\n- [x] Call Jo.';
    const next = '## Summary\nNew line.\n\n- Launch moves.\n\n- [ ] Send the press list to Sam by Friday.\n- [ ] Book the venue before the 10th.';
    expect(carryTicked(old, next)).toBe(`${next}\n- [x] Send Sam the press list.\n- [x] Call Jo.`);
    // No to-dos in the new one: the ticked ones make a group of their own at the end.
    expect(carryTicked(old, '## Summary\nNew line.\n\n- Launch moves.')).toBe('## Summary\nNew line.\n\n- Launch moves.\n\n- [x] Send Sam the press list.\n- [x] Call Jo.');
    // A ticked line the model kept word for word is not doubled, and un-ticked old to-dos are not carried.
    expect(carryTicked(old, '## Summary\nNew line.\n\n- [x] Call Jo.')).toBe('## Summary\nNew line.\n\n- [x] Call Jo.\n- [x] Send Sam the press list.');
    expect(carryTicked('## Summary\nOld.\n\n- [ ] Open.', next)).toBe(next);
  });

  it('keeps every paragraph of a dictated note when it is summarised again on purpose', () => {
    const note = `# Groceries\n\n${SECTION}\n\nWe need oat milk and eggs.\n\nAnd the good coffee.`;
    const remade = withSummary(note, '## Summary\nShopping for the week.\n\n- [ ] Oat milk and eggs.');
    expect(remade).toBe('# Groceries\n\n## Summary\nShopping for the week.\n\n- [ ] Oat milk and eggs.\n\nWe need oat milk and eggs.\n\nAnd the good coffee.');
    expect(withoutSummary(remade)).toBe('# Groceries\n\nWe need oat milk and eggs.\n\nAnd the good coffee.');
  });
});

describe('a long recording', () => {
  const paragraph = (n: number) => `Paragraph ${n}. ${'Words that were said. '.repeat(40)}`.trim();

  it('goes in one piece up to twenty thousand characters, and in pieces cut at paragraph breaks past that', () => {
    const short = Array.from({ length: 10 }, (_, i) => paragraph(i)).join('\n\n');
    expect(transcriptPieces(short)).toEqual([short]);
    const long = Array.from({ length: 40 }, (_, i) => paragraph(i)).join('\n\n');
    expect(long.length).toBeGreaterThan(ONE_PASS_CHARS);
    const pieces = transcriptPieces(long);
    expect(pieces.length).toBeGreaterThan(1);
    for (const piece of pieces) expect(piece.length).toBeLessThanOrEqual(12_000);
    // Nothing dropped, nothing cut mid-paragraph.
    expect(pieces.join('\n\n')).toBe(long);
    expect(transcriptPieces('')).toEqual([]);
  });

  it('cuts a paragraph longer than a piece at sentence ends', () => {
    const run = 'A sentence that was said. '.repeat(1200).trim();
    const pieces = transcriptPieces(run);
    expect(pieces.length).toBeGreaterThan(1);
    for (const piece of pieces) {
      expect(piece.length).toBeLessThanOrEqual(12_000);
      expect(piece.endsWith('.')).toBe(true);
    }
    expect(pieces.join(' ')).toBe(run);
  });
});
