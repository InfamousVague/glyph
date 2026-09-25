import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import suiteJson from '../../../voice-tests/suite.json';
import { MARKS } from '../plugins/marks/index.tsx';
import { sendCommand, taskNoteCommand } from '../plugins/notion/voice.ts';
import { toParagraphs } from './markdown.ts';
import { setSpokenFormats } from './spoken/inline.ts';
import { problems, runTest, scriptHeard, type Heard, type Suite } from './voiceSuite.ts';

/**
 * Every recording in the voice suite, from its script: the recorder's rules against what each test says should happen.
 * With GLYPH_VOICE set (`npm run voice:suite`), the same tests again from what Whisper heard in the audio files.
 */

const suite = suiteJson as unknown as Suite;
const voice = [sendCommand, taskNoteCommand];

beforeAll(() => {
  // The Marks plugin is on by default, so its cues can be said.
  setSpokenFormats(MARKS.flatMap((format) => (format.cue ? [{ word: format.cue, delimiter: format.delimiter }] : [])));
});

describe('the voice suite, from the scripts', () => {
  for (const test of suite.tests) {
    it(`${test.file}: ${test.tests}`, () => {
      const outcome = runTest(test, suite.fixtures, scriptHeard(test.lines), voice);
      expect(problems(test, outcome)).toEqual([]);
    });
  }
});

const heardDir = process.env.GLYPH_VOICE ? join(process.env.GLYPH_VOICE_DIR ?? join(homedir(), 'Desktop', 'glyph-voice-tests'), '.heard') : null;

describe.runIf(heardDir)('the voice suite, from the audio', () => {
  for (const test of suite.tests) {
    const file = heardDir ? join(heardDir, `${test.file}.json`) : '';
    it.runIf(heardDir && existsSync(file))(`${test.file}: ${test.tests}`, () => {
      const heard = JSON.parse(readFileSync(file, 'utf8')) as Heard;
      const outcome = runTest(test, suite.fixtures, heard, voice);
      const wrong = problems(test, outcome, { heard: true });
      expect(wrong, `heard: ${heard.segments.map((s) => `[${s.startMs}-${s.endMs}] ${s.text}`).join(' | ')}`).toEqual([]);
    });
  }
});

/*
 * The scripts are timed as src-tauri/src/whisper/stream.rs commits speech - 300 ms of the quiet after a phrase kept,
 * two seconds of quiet dropped for all but 300 ms - and capture/markdown.ts's paragraph gap is set against the same
 * arithmetic. Change either side and every script is re-timed; these say what the timing is, so it cannot move unseen.
 */
describe('a script, timed as the phone commits it', () => {
  const gapAfter = (pause: number) => {
    const [first, second] = scriptHeard([
      ['Grocery run.', pause],
      ['Oat milk and eggs.', 0],
    ]).segments;
    return second!.startMs - first!.endMs;
  };

  it('shows a pause as no gap, or 1.7 s for each two seconds of quiet past the 300 ms kept', () => {
    expect(gapAfter(0)).toBe(0);
    expect(gapAfter(1)).toBe(0);
    expect(gapAfter(2.3)).toBe(1700);
    expect(gapAfter(4)).toBe(1700);
    expect(gapAfter(4.5)).toBe(3400);
  });

  it('keeps each phrase until 300 ms into the quiet after it, and times it by its words', () => {
    const { segments, audioMs } = scriptHeard([['Grocery run.', 2]]);
    // Two words at a third of a second each, never under half a second, after the 300 ms of quiet the take opens with.
    expect(segments).toEqual([{ text: 'Grocery run.', startMs: 0, endMs: 300 + 660 + 300 }]);
    expect(audioMs).toBe(300 + 660 + 2000);
  });

  it('breaks a paragraph at a pause of two and a half seconds, and not at one of a second', () => {
    const paragraphs = (pause: number) => toParagraphs(scriptHeard([['Grocery run.', pause], ['Oat milk and eggs.', 0]]).segments);
    expect(paragraphs(2.5)).toEqual(['Grocery run.', 'Oat milk and eggs.']);
    expect(paragraphs(1)).toEqual(['Grocery run. Oat milk and eggs.']);
  });
});

describe('comparing what was heard', () => {
  it('takes a number said in words and one written in digits as the same', async () => {
    const { heardForm } = await import('./voiceSuite.ts');
    expect(heardForm('We agreed on four thousand for the kitchen.')).toBe('We agreed on 4000 for the kitchen.');
    expect(heardForm('We agreed on 4,000 for the kitchen.')).toBe('We agreed on 4000 for the kitchen.');
    expect(heardForm('The gate code is four four one seven.')).toBe('The gate code is 4417.');
    expect(heardForm('Calculate: four hundred fifty plus one hundred twenty')).toBe('Calculate: 450 plus 120');
    expect(heardForm('Someone said it')).toBe('Someone said it');
  });

  it('forgives a misheard word, and nothing about the marks', async () => {
    const { sameShape } = await import('./voiceSuite.ts');
    expect(sameShape('# Groceries\n\n- Book the ferry #travel', '# Groceries\n\n- Book the fairy #travel')).toBe(true);
    expect(sameShape('- [ ] Buy ice', '- [ ] By ice')).toBe(true);
    expect(sameShape('- [ ] Buy ice', '- Buy ice')).toBe(false);
    expect(sameShape('The deadline is **Friday**.', 'The deadline is Friday.')).toBe(false);
    expect(sameShape('# Weekend trip\n\nWe leave.', '# We can trip\n\nWe leave.')).toBe(true);
    expect(sameShape('# Weekend trip\n\nWe leave.', '# Something else entirely\n\nWe leave.')).toBe(false);
    expect(sameShape('One line.', 'One line.\n\nAnother.')).toBe(false);
  });
});
