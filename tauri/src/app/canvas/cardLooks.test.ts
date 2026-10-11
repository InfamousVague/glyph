import { describe, expect, it } from 'vitest';
import { TABLE_CARD } from './edits.ts';
import { fileTitle, isOnlyTable, ownPicture, paintOf, paintProps } from './cardLooks.ts';
import type { CanvasNode } from './jsonCanvas.ts';

/** What the screen makes of a card: its colour, the note it names, its picture, and a card that is only a table. */

describe('colour and names', () => {
  it('paints the six presets as the page’s hues and keeps a chosen hex as it is', () => {
    expect(['1', '2', '3', '4', '5', '6'].map((c) => paintOf(c))).toEqual([{ hue: 'rose' }, { hue: 'ember' }, { hue: 'amber' }, { hue: 'moss' }, { hue: 'sea' }, { hue: 'violet' }]);
    expect(paintOf('#ff8800')).toEqual({ hex: '#ff8800' });
    expect(paintOf(undefined)).toBeNull();
  });

  it('names a file node by its file, without the folder or the .md', () => {
    expect(fileTitle('Plans/Cabin trip.md')).toBe('Cabin trip');
    expect(fileTitle('Cabin trip')).toBe('Cabin trip');
    expect(fileTitle('photos/tent.JPG')).toBe('tent.JPG');
  });

  it('wears a preset as the page’s hue and a hex as the card’s own colour, and nothing for no colour', () => {
    expect(paintProps('4')).toEqual({ hue: 'moss' });
    expect(paintProps('#ff8800')).toEqual({ style: { '--app-space': '#ff8800' } });
    expect(paintProps(undefined)).toEqual({});
    expect(paintProps('9')).toEqual({});
  });

  it('knows one of Ghost.md’s own pictures by a picture name with no folder, and nothing else as one', () => {
    const file = (name: string): CanvasNode => ({ id: 'f', type: 'file', file: name, x: 0, y: 0, width: 10, height: 10 });
    expect(ownPicture(file('abc.jpg'))).toBe('abc.jpg');
    expect(ownPicture(file('Pictures/abc.jpg'))).toBeNull();
    expect(ownPicture(file('Cabin trip.md'))).toBeNull();
    expect(ownPicture({ id: 't', type: 'text', text: 'abc.jpg', x: 0, y: 0, width: 10, height: 10 })).toBeNull();
  });
});

describe('a card that is only a table', () => {
  it('knows a table from words with a table in them', () => {
    expect(isOnlyTable(TABLE_CARD)).toBe(true);
    expect(isOnlyTable('| a | b |\n| - | - |\n| 1 | 2 |')).toBe(true);
    expect(isOnlyTable('# Prices\n\n| a | b |\n| - | - |')).toBe(false);
    expect(isOnlyTable('| just one line |')).toBe(false);
    expect(isOnlyTable('')).toBe(false);
  });
});
