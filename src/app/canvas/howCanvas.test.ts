import { describe, expect, it } from 'vitest';
import { renderNote } from '../capture/markdown.ts';
import { BOARD_TITLE } from '../core/boardNote.ts';
import { noteTitle } from '../core/store.ts';
import { SAMPLE_TITLE } from '../core/sampleNote.ts';
import { HOW_TITLE, howCanvas, howCanvasBody, renewedHowCanvas } from './howCanvas.ts';
import { pastHowCanvasBody } from '../../test/pastExamples.ts';
import { canvasOf, parseCanvas, serializeCanvas } from './jsonCanvas.ts';

describe('the canvas that says how Ghost.md works', () => {
  it('is eight plain cards in a group, opening the example board and the sample note, with the order on the lines', () => {
    const canvas = howCanvas();
    const cards = canvas.nodes.filter((n) => n.type !== 'group');
    expect(canvas.nodes.filter((n) => n.type === 'group')).toHaveLength(1);
    expect(cards).toHaveLength(8);
    const files = cards.filter((n) => n.type === 'file').map((n) => (n as { file: string }).file);
    expect(files).toEqual([`${BOARD_TITLE}.md`, `${SAMPLE_TITLE}.md`]);
    // Every line joins two cards that are there, and the first three tell the order of saying.
    const ids = new Set(canvas.nodes.map((n) => n.id));
    for (const edge of canvas.edges) {
      expect(ids.has(edge.fromNode)).toBe(true);
      expect(ids.has(edge.toNode)).toBe(true);
    }
    expect(canvas.edges.slice(0, 2).map((e) => [e.fromNode, e.toNode])).toEqual([
      ['speak', 'marks'],
      ['marks', 'note'],
    ]);
    // Said simply: no card runs past a few lines, and none of them is a chart or a table.
    for (const card of cards) {
      if (card.type !== 'text') continue;
      expect(card.text.length).toBeLessThan(160);
      expect(card.text).not.toMatch(/```|\|/);
    }
  });

  it('is a canvas note under its own title, and comes back the same from the file', () => {
    const body = howCanvasBody();
    expect(noteTitle(body)).toBe(HOW_TITLE);
    expect(canvasOf(body)).toEqual(howCanvas());
    expect(parseCanvas(serializeCanvas(howCanvas()))).toEqual(howCanvas());
  });
});

describe('what the canvas says to do', () => {
  const text = (id: string) => (howCanvas().nodes.find((node) => node.id === id) as { text: string }).text;

  it('names marks the recorder reads as cues, each gone into its mark when said', () => {
    const named = [...text('marks').matchAll(/\*([^*]+)\*/g)].map((found) => found[1]!);
    expect(named.length).toBeGreaterThan(2);
    for (const cue of named) {
      const said = ['The trip.', `${cue[0]!.toUpperCase()}${cue.slice(1)}: the plan.`];
      const markdown = renderNote(said.map((words, index) => ({ text: words, startMs: index * 1300, endMs: index * 1300 + 1000 }))).markdown;
      expect(markdown.toLowerCase(), cue).not.toContain(cue);
      expect(markdown, cue).toMatch(/^(?:#+|-|- \[[ x]\]) The plan$/m);
    }
  });

  it('names the button the home page draws, the microphone', () => {
    expect(text('speak')).toContain('**microphone**');
    expect(JSON.stringify(howCanvas())).not.toMatch(/Speak\*\*/);
  });
});

describe('the canvas an earlier Ghost.md made', () => {
  it('is this canvas when nobody has changed it, and left as it is once someone has', () => {
    const past = pastHowCanvasBody();
    expect(renewedHowCanvas(past)).toBe(howCanvasBody());
    expect(renewedHowCanvas(past.replace('"x": 0,', '"x": 40,'))).toBeNull();
    expect(renewedHowCanvas(howCanvasBody())).toBeNull();
  });
});
