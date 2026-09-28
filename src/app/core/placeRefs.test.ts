import { describe, expect, it } from 'vitest';
import { GEO_AUTOLINK, GEO_DEFINITION, GEO_LINK, cleanPlaceName, hasPlaces, placeLines, placeMarkdown, placeOfLine, withoutPlaces } from './placeRefs.ts';

/**
 * A place written into a note's words (core/placeRefs.ts): the line the + beside the line writes, read back in every
 * lead a line can have, and every way a `geo:` address can be written, taken out of what a share carries.
 */

const CAIS = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';

describe('a place line', () => {
  it('is a line whose words are one link to a geo: address', () => {
    expect(placeOfLine(CAIS)).toEqual({ tag: { lat: 38.7057, lon: -9.1446, place: 'Cais do Sodré, Lisbon', rough: false }, words: 'Cais do Sodré, Lisbon' });
  });

  it('is read whatever the line’s lead: a bullet, a number, a box, a quote', () => {
    for (const lead of ['- ', '3. ', '- [ ] ', '> ', '> - ']) expect(placeOfLine(`${lead}${CAIS}`)?.tag.lat, lead).toBe(38.7057);
  });

  it('is rough when its coordinates have two decimals or fewer', () => {
    expect(placeOfLine('[Roughly 38.71, -9.14](geo:38.71,-9.14)')?.tag).toEqual({ lat: 38.71, lon: -9.14, place: null, rough: true });
  });

  it('names no place when its words are only the coordinates', () => {
    expect(placeOfLine('[38.7057, -9.1446](geo:38.7057,-9.1446)')?.tag.place).toBeNull();
  });

  it('is not a link inside other words, two links, or coordinates out of range', () => {
    expect(placeOfLine(`Met at ${CAIS}`)).toBeNull();
    expect(placeOfLine(`${CAIS} ${CAIS}`)).toBeNull();
    expect(placeOfLine('[Nowhere](geo:91.0,10.0)')).toBeNull();
    expect(placeOfLine('[Nowhere](geo:10.0,-181.0)')).toBeNull();
    expect(placeOfLine('[A site](https://example.com)')).toBeNull();
    expect(placeOfLine('![](image/x.jpg)')).toBeNull();
  });
});

describe('writing a place', () => {
  it('writes the name, or the coordinates, as the link’s words', () => {
    expect(placeMarkdown({ lat: 38.7057, lon: -9.1446, place: null, rough: false }, 'Cais do Sodré, Lisbon')).toBe(CAIS);
    expect(placeMarkdown({ lat: 38.7057, lon: -9.1446, place: null, rough: false })).toBe('[38.7057, -9.1446](geo:38.7057,-9.1446)');
    expect(placeMarkdown({ lat: 38.71, lon: -9.14, place: null, rough: true })).toBe('[Roughly 38.71, -9.14](geo:38.71,-9.14)');
  });

  it('keeps a name from breaking the link: brackets and line breaks out, and no longer than a title', () => {
    expect(cleanPlaceName('The [Old] Pier\nNorth')).toBe('The Old Pier North');
    expect(cleanPlaceName('x'.repeat(120))).toHaveLength(80);
    const written = placeMarkdown({ lat: 1, lon: 2, place: null, rough: false }, 'A ] name [ with \\ marks');
    expect(placeOfLine(written)?.words).toBe('A name with marks');
  });

  it('reads back what it writes', () => {
    const tag = { lat: -33.8568, lon: 151.2153, place: null, rough: false };
    expect(placeOfLine(placeMarkdown(tag, 'Sydney Opera House'))?.tag).toEqual({ ...tag, place: 'Sydney Opera House' });
  });
});

describe('the places in a note', () => {
  it('are its place lines, outside code', () => {
    const body = `# Lisbon\n\n${CAIS}\n\n\`\`\`\n[Code](geo:1.0,2.0)\n\`\`\`\n\n- [Belém](geo:38.6916,-9.2160)`;
    expect(placeLines(body).map((place) => [place.line, place.words])).toEqual([
      [3, 'Cais do Sodré, Lisbon'],
      [9, 'Belém'],
    ]);
  });
});

describe('a note without its places', () => {
  const clean = (body: string) => {
    const out = withoutPlaces(body);
    expect(out, body).not.toMatch(/geo:/i);
    return out;
  };

  it('loses a place line whole, whatever its lead', () => {
    for (const lead of ['', '- ', '1. ', '- [ ] ', '> ']) expect(clean(`${lead}${CAIS}`)).toBe('');
  });

  it('keeps one blank line where a place line stood between two', () => {
    expect(clean(`Lunch\n\n${CAIS}\n\nAfter`)).toBe('Lunch\n\nAfter');
    expect(clean(`Lunch\n${CAIS}\nAfter`)).toBe('Lunch\nAfter');
  });

  it('keeps the words of a place inside other words, and loses the address', () => {
    expect(clean(`Met at ${CAIS}`)).toBe('Met at Cais do Sodré, Lisbon');
    expect(clean(`${CAIS} lunch was lovely`)).toBe('Cais do Sodré, Lisbon lunch was lovely');
    expect(clean(`| ${CAIS} | b |`)).toBe('| Cais do Sodré, Lisbon | b |');
  });

  it('takes an autolink, a definition and a titled or bracketed address', () => {
    expect(clean('Met at <geo:38.7057,-9.1446>')).toBe('Met at ');
    expect(clean('Met at [Cais][c]\n\n[c]: geo:38.7057,-9.1446')).toBe('Met at Cais\n');
    expect(clean('[Cais](<geo:38.7057,-9.1446> "Lisbon")')).toBe('');
  });

  it('takes an address in code too: the switch promises none leaves', () => {
    expect(clean('```\n[Cais](geo:38.7,-9.1)\n```')).toBe('```\n```');
    expect(clean('see `[Cais](geo:38.7,-9.1)` here')).toBe('see `Cais` here');
  });

  it('takes the forms only a hand types: a link over two lines, a break inside its brackets, a picture, raw HTML', () => {
    expect(clean('Met at [Cais do\nSodré](geo:38.7057,-9.1446) for lunch')).toBe('Met at Cais do\nSodré for lunch');
    expect(clean('[Cais](geo:38.7057,-9.1446\n)')).toBe('Cais');
    expect(clean('[Cais](\ngeo:38.7057,-9.1446 "Lisbon")')).toBe('Cais');
    expect(clean('![map](geo:38.7057,-9.1446)')).toBe('');
    expect(clean('The ![map](geo:38.7057,-9.1446) of it')).toBe('The map of it');
    expect(clean('A <a href="geo:38.7057,-9.1446">harbour</a>.')).toBe('A <a href="">harbour</a>.');
    expect(clean('Meet at geo:38.7057,-9.1446;u=35 at noon')).toBe('Meet at  at noon');
    expect(clean('[Maps](https://maps.example/?to=geo:38.7057,-9.1446)')).toBe('[Maps](https://maps.example/?to=)');
    // A blank line is two paragraphs, never one link: the address still goes.
    expect(clean('[Cais\n\nSodré](geo:38.7057,-9.1446)')).toBe('[Cais\n\nSodré]()');
  });

  it('leaves pictures, web links, the words geo: and the tag in the front matter alone', () => {
    for (const body of ['![](image/x.jpg)', '[site](https://example.com)', 'the geo: scheme', 'geo:', 'a geology:1 class', '---\nlocation: 51.5074,-0.1278\n---\n\nWords']) {
      expect(withoutPlaces(body)).toBe(body);
      expect(hasPlaces(body)).toBe(false);
    }
  });

  it('says whether a body holds a place at all', () => {
    expect(hasPlaces(`Met at ${CAIS}`)).toBe(true);
    expect(hasPlaces('<geo:1,2>')).toBe(true);
  });
});

describe('the forms', () => {
  it('match each way a geo: address is written', () => {
    expect(`x ${CAIS} y`.match(GEO_LINK)).toHaveLength(1);
    expect('<geo:1,2>'.match(GEO_AUTOLINK)).toHaveLength(1);
    expect('[c]: geo:1,2'.match(GEO_DEFINITION)).toHaveLength(1);
  });
});
