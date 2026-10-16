import { describe, expect, it } from 'vitest';
import { escapeText, pictureSource, toMarkdown } from '../src/core/markdown.ts';
import { ClipRefused, extract, peek } from '../src/core/page.ts';
import { loadPage, select } from './support.ts';

/**
 * The page's words as the Markdown a note holds, from fixture pages: an article among a site's furniture, a reference
 * page of tables and code, and a selection. The expectations are whole lines, so a change in what Ghost.md would show
 * is a change here.
 */

describe('an article', () => {
  it('is the readable part alone: no menu, no sidebar, no footer, no script', () => {
    const got = extract(loadPage('article'), 'article');
    expect(got.mode).toBe('article');
    expect(got.title).toBe('The Quiet Garden');
    expect(got.markdown).not.toMatch(/Subscribe|Ten tomatoes|Privacy|tracking/);
    expect(got.description).toBe('How a small city garden keeps its soil alive through the winter.');
  });

  it('keeps headings, emphasis, nested and numbered lists, a quote and its links, made absolute', () => {
    const { markdown } = extract(loadPage('article'), 'article');
    const lines = markdown.split('\n');
    expect(lines).toContain('## What we covered the beds with');
    expect(lines).toContain('### The order we did it in');
    expect(markdown).toContain('Most of the work in a *winter* garden');
    expect(markdown).toContain('gets **twice the harvest** in spring');
    expect(lines).toContain('- Leaves from the street trees, shredded first:');
    expect(lines).toContain('  - oak takes longest to break down,');
    expect(lines).toContain('1. Clear the last of the summer crop.');
    expect(lines).toContain('3. Lay the cover, thickest on the north side.');
    expect(lines).toContain('> Feed the soil, not the plant. The plant will take care of itself.');
    expect(markdown).toContain('[here](https://field.example/data/soil.csv)');
    expect(markdown).toContain('[the rye notes](https://example.org/rye)');
  });

  it('does not say its title twice: the note has it as its own heading', () => {
    const { markdown } = extract(loadPage('article'), 'article');
    expect(markdown).not.toMatch(/^# The Quiet Garden/m);
  });

  it('lists its pictures, a lazy one by its real source, and leaves a tracking pixel out', () => {
    const got = extract(loadPage('article'), 'article');
    expect(got.pictures).toEqual([
      { url: 'https://field.example/pictures/beds.png', alt: 'Three raised beds under straw' },
      { url: 'https://field.example/pictures/shed.png', alt: 'The tool shed in snow' },
    ]);
    expect(got.markdown).toContain('![Three raised beds under straw](ghost-clip:picture/0)');
    expect(got.markdown).toContain('![The tool shed in snow](ghost-clip:picture/1)');
    expect(got.markdown).not.toContain('pixel.gif');
  });

  it('escapes what Ghost.md would read as a mark, and nothing more', () => {
    const { markdown } = extract(loadPage('article'), 'article');
    // A blank the AI would fill (core/blanks.ts), written about rather than asked.
    expect(markdown).toContain('marked like \\{?this one}');
    // snake_case and two prices are words, as the app reads them.
    expect(markdown).toContain('`soil_temp`');
    expect(markdown).toContain('The probe cost $5 and the notebook $10');
  });

  it('falls back to the whole page, and says so, where there is no article', () => {
    const got = extract(loadPage('selection', 'https://pages.example/select'), 'article');
    expect(got.mode).toBe('page');
    expect(got.notice).toBe('no-article');
    expect(got.markdown).toContain('This paragraph is before the selection');
  });
});

describe('a page with tables and code', () => {
  const page = () => extract(loadPage('table-code', 'https://docs.example/sorting/'), 'page');

  it('draws a table with a heading row as a GFM table, its alignment and an escaped bar kept', () => {
    const lines = page().markdown.split('\n');
    const at = lines.indexOf('| Method | Average | Stable |');
    expect(at).toBeGreaterThan(-1);
    expect(lines.slice(at, at + 5)).toEqual([
      '| Method | Average | Stable |',
      '| --- | ---: | --- |',
      '| Insertion | O(n²) | yes |',
      '| Heap | O(n log n) | no |',
      '| Quick \\| median of three | O(n log n) | no |',
    ]);
  });

  it('takes the first row as the heading of a table without one, and pads a colspan', () => {
    const lines = page().markdown.split('\n');
    const at = lines.indexOf('| Monday | Water the beds | |');
    expect(lines.slice(at, at + 3)).toEqual(['| Monday | Water the beds | |', '| --- | --- | --- |', '| Tuesday | Rest | |']);
  });

  it('keeps a table with code and a list in it a table, the list on one line', () => {
    expect(page().markdown).toContain('| `arr.sort()` | sorts in place; returns the array |');
  });

  it('fences code with its language, from a class, a data-lang or a highlighter, and a longer fence round a fence', () => {
    const { markdown } = page();
    expect(markdown).toContain('```js\nfunction insertionSort(a) {\n  for (let i = 1; i < a.length; i++) {');
    expect(markdown).toContain('```python\ndef heap_sort(a):\n    heapq.heapify(a)');
    expect(markdown).toContain('````rust\nfn main() { println!("```"); }\n````');
  });

  it('writes a task list as to-dos, ticked as the page has them, and strikethrough', () => {
    const { markdown } = page();
    expect(markdown).toContain('- [x] Read the paper\n- [ ] Try it on real data');
    expect(markdown).toContain('~~bubble sort~~');
  });

  it('keeps the to-dos in Article mode too, where Readability takes the boxes out', () => {
    const { markdown } = extract(loadPage('table-code', 'https://docs.example/sorting/'), 'article');
    expect(markdown).toContain('- [x] Read the paper\n- [ ] Try it on real data');
  });

  it('does not make a note link of words in double brackets', () => {
    expect(page().markdown).toContain('\\[\\[not a link]] in passing');
  });
});

describe('a selection', () => {
  it('is what was selected and nothing else, its links absolute and its picture listed', () => {
    const win = loadPage('selection', 'https://pages.example/select');
    select(win, 'first', 'last');
    expect(peek(win).selected).toBe(true);
    const got = extract(win, 'selection');
    expect(got.markdown).toBe(
      [
        'The first chosen paragraph, with a [relative link](https://pages.example/linked) and **bold words**.',
        '',
        '- One item of the chosen list',
        '- Another item, with `inline code`',
        '',
        'The last chosen paragraph, and a picture: ![Beds](ghost-clip:picture/0)',
        '',
      ].join('\n'),
    );
    expect(got.pictures).toEqual([{ url: 'https://pages.example/pictures/beds.png', alt: 'Beds' }]);
  });

  it('chosen inside a code block keeps the block and its language', () => {
    const win = loadPage('selection', 'https://pages.example/select');
    const code = win.document.querySelector('#code code')!.firstChild!;
    const range = win.document.createRange();
    range.setStart(code, 0);
    range.setEnd(code, 'git log --oneline -3'.length);
    win.getSelection()!.addRange(range);
    expect(extract(win, 'selection').markdown).toBe('```sh\ngit log --oneline -3\n```\n');
  });

  it('is refused, in words, when nothing is selected', () => {
    const win = loadPage('selection', 'https://pages.example/select');
    expect(peek(win).selected).toBe(false);
    expect(() => extract(win, 'selection')).toThrow(ClipRefused);
    expect(() => extract(win, 'selection')).toThrow('Select something on the page first.');
  });
});

describe('a bookmark', () => {
  it('is the page as it describes itself: its title, address, description and preview picture', () => {
    const got = extract(loadPage('article'), 'bookmark');
    expect(got).toMatchObject({
      mode: 'bookmark',
      title: 'The Quiet Garden',
      url: 'https://field.example/2026/10/the-quiet-garden',
      description: 'How a small city garden keeps its soil alive through the winter.',
      image: 'https://field.example/pictures/garden-wide.png',
      siteName: 'Field Notes',
      pictures: [{ url: 'https://field.example/pictures/garden-wide.png', alt: 'The Quiet Garden' }],
    });
  });
});

describe('the pieces', () => {
  it('finds a picture behind a lazy page: data-src, then the largest of a srcset', () => {
    const img = (html: string) => {
      document.body.innerHTML = html;
      return document.body.querySelector('img')!;
    };
    expect(pictureSource(img('<img src="data:image/gif;base64,R0lGOD" data-src="/a.jpg">'), 'https://x.example/p/')).toBe('https://x.example/a.jpg');
    expect(pictureSource(img('<img srcset="s.jpg 320w, l.jpg 1280w, m.jpg 640w">'), 'https://x.example/p/')).toBe('https://x.example/p/l.jpg');
    expect(pictureSource(img('<picture><source srcset="b.webp 2x, a.webp 1x"><img src="/blank.gif"></picture>'), 'https://x.example/')).toBe('https://x.example/b.webp');
    expect(pictureSource(img('<img src="javascript:alert(1)">'), 'https://x.example/')).toBeNull();
  });

  it('escapes a line that would open a list, a heading or a quote, and an underscore at a word edge only', () => {
    expect(escapeText('- not a list')).toBe('\\- not a list');
    expect(escapeText('# not a heading')).toBe('\\# not a heading');
    expect(escapeText('> not a quote')).toBe('\\> not a quote');
    expect(escapeText('1. not a list')).toBe('1\\. not a list');
    expect(escapeText('snake_case stays, _this_ does not')).toBe('snake_case stays, \\_this\\_ does not');
    expect(escapeText('a *star* and `tick`')).toBe('a \\*star\\* and \\`tick\\`');
    expect(escapeText('x^2 is $x^2$ here')).toBe('x^2 is \\$x^2\\$ here');
    expect(escapeText('<b> as words')).toBe('\\<b> as words');
  });

  it('takes HTML as text too, and drops what is never words', () => {
    const { markdown } = toMarkdown('<h2>Hi</h2><script>x()</script><style>p{}</style><button>Buy</button><p>Text <a href="#top">top</a></p>', { base: 'https://x.example/' });
    expect(markdown).toBe('## Hi\n\nText top\n');
  });
});
