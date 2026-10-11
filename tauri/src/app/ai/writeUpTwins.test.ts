import { describe, expect, it } from 'vitest';
import { withoutTranscript, withTranscript } from '../capture/markdown.ts';
import { recordingNotesBudget, recordingSummaryBudget } from '../format/prompt.ts';
import { transcriptPieces } from './summaryText.ts';
import fixture from './writeUpTwins.fixture.json';

/*
 * The phone's write-up (src-tauri/src/write_up.rs, transcript.rs) cuts a long transcript into pieces, gives each pass
 * its budget and puts the transcript into the note by the page's own rules, written again in Rust because it runs
 * with no page. The fixture beside this file is read by both sides, so a rule changed on one and not the other fails
 * on the side that was not changed.
 */

describe('the write-up’s twins', () => {
  it('cut a long transcript into the same pieces', () => {
    expect(fixture.pieces.length).toBeGreaterThan(0);
    for (const piece of fixture.pieces) {
      const plain = Array<string>(piece.times).fill(piece.unit).join(piece.joiner);
      expect(transcriptPieces(plain, piece.size).map((p) => p.length), piece.name).toEqual(piece.pieces);
    }
  });

  it('give each pass the same budget', () => {
    for (const budget of fixture.budgets) {
      expect([recordingSummaryBudget(budget.chars), recordingNotesBudget(budget.chars)], String(budget.chars)).toEqual([budget.summary, budget.notes]);
    }
  });

  it('put the transcript in the same place and take it out the same way', () => {
    for (const section of fixture.sections) {
      expect(withTranscript(section.body, `## Transcript\n\n${section.words}`).trimEnd()).toBe(section.withTranscript.trimEnd());
      expect(withoutTranscript(section.body)).toBe(section.withoutTranscript);
    }
  });
});
