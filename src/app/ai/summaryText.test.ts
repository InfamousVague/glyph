import { describe, expect, it } from 'vitest';
import { carryTicked, dateTitled, hasWords, ONE_PASS_CHARS, shapeSummary, summaryLine, summaryPlace, summarySection, transcriptPieces, withoutSummary, withSummary } from './summaryText.ts';

/**
 * The summary section (docs/DESIGN.md §127 section 2): its shape and what a model's looser answer is read as, how
 * it is found again by that shape or closed by the kept text, where a fresh one goes, how a remake treats the one
 * there, and the pieces a long transcript is cut into. Every rule is a case here, since two writers depend on them:
 * the queue and the editor.
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

  it('reads a label or an introduction on the prose line as not the prose, so the sentence after it is taken', () => {
    const rest = '\n\n- Launch moves to March.\n\n- [ ] Book the venue.';
    const section = `## Summary\nWhat the call settled.${rest}`;
    expect(shapeSummary(`# Planning call\n**Summary**\nWhat the call settled.${rest}`)).toEqual({ title: 'Planning call', section });
    expect(shapeSummary(`# Planning call\nSummary:\nWhat the call settled.${rest}`).section).toBe(section);
    expect(shapeSummary(`# Planning call\nHere is the summary:\nWhat the call settled.${rest}`).section).toBe(section);
    expect(shapeSummary(`# Planning call\n**Summary:** What the call settled.${rest}`).section).toBe(section);
    expect(shapeSummary(`# Planning call\n**Summary**: What the call settled.${rest}`).section).toBe(section);
    // A label alone with nothing after it leaves no empty prose line behind, and never two blanks in a row.
    const bare = shapeSummary('# Planning call\n**Summary**\n\n- Launch moves to March.').section;
    expect(bare).toBe('## Summary\n\n- Launch moves to March.');
    expect(bare).not.toContain('\n\n\n');
    expect(summaryLine(`# T\n${bare}`)).toBeNull();
  });

  it('reads a numbered list, a typographic bullet, a tight box and a bare decision as items', () => {
    const model = '# Planning call\nWhat the call settled.\n\n1. Launch moves to March.\n2) Sam: the press list.\n• Site copy still open.\nDecided: no paid ads until the beta closes.\n\n-[ ] Book the venue.\n-[x] Send the list.';
    expect(shapeSummary(model).section).toBe('## Summary\nWhat the call settled.\n\n- Launch moves to March.\n- Sam: the press list.\n- Site copy still open.\n- Decided: no paid ads until the beta closes.\n\n- [ ] Book the venue.\n- [x] Send the list.');
  });

  it('joins a sentence wrapped over two lines, and still drops a second sentence', () => {
    expect(shapeSummary('# T\nWhat the call settled about\nthe March launch.\n\n- One.').section).toBe('## Summary\nWhat the call settled about the March launch.\n\n- One.');
    expect(shapeSummary('# T\nWhat the call settled.\nSam sounded tired.\n\n- One.').section).toBe('## Summary\nWhat the call settled.\n\n- One.');
    // A blank closes the sentence, however it ended.
    expect(shapeSummary('# T\nWhat the call settled about\n\nthe March launch.\n\n- One.').section).toBe('## Summary\nWhat the call settled about\n\n- One.');
  });

  it('only ever grows as the model streams, so a run’s landed lines never move', () => {
    const wholes = [
      '# Planning call\nWhat the call settled.\n- Launch moves.\n- [ ] Send the list.\n',
      '# Planning call\n**Summary**\nWhat the call settled about\nthe launch.\n\n1. Launch moves.\n• Sam: the list.\n\n-[ ] Send the list.\n',
    ];
    for (const whole of wholes) {
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

  it('is closed by the kept text where the body still reads so, so the person’s own list under it is not read as its', () => {
    const list = '- [ ] Task under the title\n- [ ] Another';
    const body = `# Title\n\n${SECTION}\n\n${list}`;
    // By the shape alone the list is the section's; the keep closes it.
    expect(summarySection(body)?.text).toBe(`${SECTION}\n\n${list}`);
    expect(summarySection(body, SECTION)?.text).toBe(SECTION);
    expect(body.slice(summarySection(body, SECTION)!.start, summarySection(body, SECTION)!.end)).toBe(SECTION);
    // A box the person ticked does not stop the keep closing it; the text it answers carries the tick.
    const ticked = body.replace('- [ ] Book the venue before the 10th.', '- [x] Book the venue before the 10th.');
    expect(summarySection(ticked, SECTION)?.text).toBe(SECTION.replace('- [ ] Book the venue before the 10th.', '- [x] Book the venue before the 10th.'));
    // Edited past a tick, or run straight into the list, and the shape is the fallback.
    expect(summarySection(body.replace('What the call settled', 'My own words'), SECTION)?.text).toBe(`${SECTION.replace('What the call settled', 'My own words')}\n\n${list}`);
    expect(summarySection(`# Title\n\n${SECTION}\n${list}`, SECTION)?.text).toBe(`${SECTION}\n${list}`);
    expect(summarySection('# T\nNo section here.', SECTION)).toBeNull();
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

  it('puts the model’s heading above the section in a note with no words, which the section would otherwise title', () => {
    expect(withSummary('', SECTION, { title: 'Planning call' })).toBe(`# Planning call\n\n${SECTION}`);
    expect(withSummary('![](image/a.jpg)', SECTION, { title: 'Planning call' })).toBe(`![](image/a.jpg)\n\n# Planning call\n\n${SECTION}`);
    expect(withSummary('---\nauthor: sam\n---\n', SECTION, { title: 'Planning call' })).toBe(`---\nauthor: sam\n---\n\n# Planning call\n\n${SECTION}`);
    // A title named in the front matter is a title, and is never written over.
    expect(withSummary('---\ntitle: x\n---\n', SECTION, { title: 'Planning call' })).toBe(`---\ntitle: x\n---\n\n${SECTION}`);
    expect(withSummary('---\ntitle: Meeting, 26 Sep 14:05\n---\nWords.', '## Summary\nA line.', { title: 'Planning call' })).toBe('---\ntitle: Meeting, 26 Sep 14:05\n---\nWords.\n\n## Summary\nA line.');
    expect(hasWords('')).toBe(false);
    expect(hasWords('![](image/a.jpg)')).toBe(false);
    expect(hasWords('# T')).toBe(true);
    expect(hasWords('---\ntitle: x\n---\n')).toBe(true);
  });

  it('keeps the person’s list under a remade section, since the keep closes the section', () => {
    const list = '- [ ] Task under the title\n- [ ] Another';
    const once = withSummary(`# Title\n\n${list}`, SECTION);
    expect(once).toBe(`# Title\n\n${SECTION}\n\n${list}`);
    const next = '## Summary\nA newer line.\n\n- [ ] One thing.';
    expect(withSummary(once, next, { kept: SECTION })).toBe(`# Title\n\n${next}\n\n${list}`);
    expect(withoutSummary(once, SECTION)).toBe(`# Title\n\n${list}`);
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
    // Nor one it kept with a capital X, or without the full stop.
    expect(carryTicked('## Summary\nOld.\n\n- [x] Call Jo.', '## Summary\nNew.\n\n- [X] Call Jo.')).toBe('## Summary\nNew.\n\n- [X] Call Jo.');
    expect(carryTicked('## Summary\nOld.\n\n- [x] Call Jo', '## Summary\nNew.\n\n- [x] Call Jo.')).toBe('## Summary\nNew.\n\n- [x] Call Jo.');
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
