import { BOARD_TITLE } from '../core/boardNote.ts';
import { canvasNoteBody, type Canvas } from './jsonCanvas.ts';

/**
 * The example canvas, added from Settings the way the example board is (core/boardNote.ts): a note that is a
 * working canvas, with one of each thing a canvas holds - a group, cards of words, a card that is another note, a
 * card that is a link, and lines between them with words on. It is written in JSON Canvas exactly as Obsidian would
 * write it (docs/CANVAS.md), so it is also the file to hand to Obsidian to see the same thing there.
 *
 * The note card points at the example board by its title: add both and tapping the card opens the board.
 */

export const CANVAS_TITLE = 'Cabin weekend, laid out';

export function sampleCanvas(): Canvas {
  return {
    nodes: [
      { id: 'before', type: 'group', x: -40, y: -60, width: 640, height: 360, label: 'Before we go' },
      { id: 'book', type: 'text', x: 0, y: 0, width: 260, height: 100, color: '4', text: '# Book the cabin\n\nBy Friday. The deposit is **200**.' },
      { id: 'pack', type: 'text', x: 320, y: 0, width: 260, height: 100, text: '- [ ] Snacks\n- [ ] A charger for the drive\n- [x] The good coffee' },
      { id: 'sam', type: 'text', x: 0, y: 160, width: 260, height: 100, color: '2', text: 'Ask Sam about the dog' },
      { id: 'car', type: 'text', x: 320, y: 160, width: 260, height: 100, color: '#5b8def', text: 'Oil change before we go. The garage on Hill Street is open until six.' },
      { id: 'board', type: 'file', x: 0, y: 380, width: 260, height: 160, file: `${BOARD_TITLE}.md` },
      { id: 'site', type: 'link', x: 320, y: 380, width: 260, height: 100, color: '5', url: 'https://attack.fm/glyph' },
      { id: 'there', type: 'text', x: 720, y: 60, width: 280, height: 140, color: '6', text: '# The weekend\n\nSaturday the lake, Sunday the long walk if it is dry. Nothing planned for the evenings.' },
    ],
    edges: [
      { id: 'e1', fromNode: 'book', toNode: 'pack', fromSide: 'right', toSide: 'left', label: 'then' },
      { id: 'e2', fromNode: 'book', toNode: 'sam', fromSide: 'bottom', toSide: 'top' },
      { id: 'e3', fromNode: 'pack', toNode: 'car', fromSide: 'bottom', toSide: 'top', color: '2', label: 'same day' },
      { id: 'e4', fromNode: 'before', toNode: 'there', fromSide: 'right', toSide: 'left', label: 'and then' },
      { id: 'e5', fromNode: 'sam', toNode: 'board', fromSide: 'bottom', toSide: 'top', toEnd: 'none' },
    ],
  };
}

export function sampleCanvasBody(): string {
  return canvasNoteBody(CANVAS_TITLE, sampleCanvas());
}
