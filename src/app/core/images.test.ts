import { describe, expect, it } from 'vitest';
import { imageMarkdown, imageNames } from './images.ts';
import { noteTitle } from './store.ts';

describe('pictures in notes', () => {
  it('writes and reads back the relative reference', () => {
    const md = imageMarkdown('a1b2.jpg', 'the cabin');
    expect(md).toBe('![the cabin](image/a1b2.jpg)');
    expect(imageNames(`# Trip\n\n${md}\n\n![](image/c3d4.png)\n\n![](http://elsewhere/x.png)`)).toEqual(['a1b2.jpg', 'c3d4.png']);
  });

  it('does not make a picture the note title', () => {
    expect(noteTitle('![](image/a1b2.jpg)\n\nThe cabin')).toBe('The cabin');
    expect(noteTitle('![the cabin](image/a1b2.jpg)')).toBe('');
    expect(noteTitle('# Trip\n\n![](image/a1b2.jpg)')).toBe('Trip');
  });
});
