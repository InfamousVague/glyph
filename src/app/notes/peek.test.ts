import { describe, expect, it } from 'vitest';
import { peekMarkdown } from './peek.ts';

describe('the note as the card’s own editor is given it', () => {
  it('starts after the title and front matter, and stops after a few lines', () => {
    expect(peekMarkdown('---\nid: x\n---\n# Title\n\n- [ ] Eggs\n- [x] Milk\n\nWords.')).toBe('- [ ] Eggs\n- [x] Milk\n\nWords.');
    const long = `# T\n${Array.from({ length: 40 }, (_, i) => `line ${i + 1}`).join('\n')}`;
    expect(peekMarkdown(long, 5)).toBe('line 1\nline 2\nline 3\nline 4\nline 5');
  });

  it('keeps a block of code whole, so it is drawn as one', () => {
    expect(peekMarkdown('# T\n```js\nconst a = 1;\nconst b = 2;\n```\nAfter.', 2)).toBe('```js\nconst a = 1;\nconst b = 2;\n```');
  });

  it('leaves a board out, and draws its items as the list they are, without their anchors', () => {
    expect(peekMarkdown('# T\n\n```board\nTo do: a, b\nDone: c\n```\n\n- [ ] A ^a\n- [ ] B ^b\n- [x] C ^c')).toBe('- [ ] A\n- [ ] B\n- [x] C');
  });

  it('closes the blank lines around a cut to one', () => {
    expect(peekMarkdown('# T\n\nWords.\n\n\n```board\nTo do: a\n```\n\n\n- [ ] A ^a\n\n\n\nMore.')).toBe('Words.\n\n- [ ] A\n\nMore.');
    // A superscript is not an anchor: the caret closes.
    expect(peekMarkdown('# T\nE = mc^2^')).toBe('E = mc^2^');
  });

  it('is titled by the words under a picture, and starts after them', () => {
    expect(peekMarkdown('![cover](cover.jpg)\n# Bread\n\n500g strong white.')).toBe('500g strong white.');
  });

  it('has nothing for a note that is only its title', () => {
    expect(peekMarkdown('# Title')).toBe('');
    expect(peekMarkdown('# Title\n\n\n')).toBe('');
  });

  it('takes an anchor off with a mark after it too, the order a sent item used to be written in (core/itemSyntax.ts)', () => {
    expect(peekMarkdown('# T\n- [ ] Ship it ^ship [notion](https://n.so/a)')).toBe('- [ ] Ship it [notion](https://n.so/a)');
  });
});
