import { describe, expect, it } from 'vitest';
import { coordsText, geoTagOf, sameTag, shortPlace, tagLabel, tagOf, withGeoTag } from './geotag.ts';

/**
 * The tag in the note's front matter (geotag.ts): read tolerantly and never rewritten by a reader, written at the
 * precision the fix earned, `location:` before `place:`, and taken out with the block when nothing else is in it.
 */

const LONDON = { lat: 51.5074, lon: -0.1278, place: null, rough: false };

describe('a tag written into the note', () => {
  it('adds a block where there was none, location before place, and reads back the same', () => {
    const body = withGeoTag('# A walk\n\nWords.', LONDON);
    expect(body).toBe('---\nlocation: 51.5074,-0.1278\n---\n# A walk\n\nWords.');
    expect(geoTagOf(body)).toEqual(LONDON);
    const named = withGeoTag(body, { ...LONDON, place: 'Trafalgar Square, London' });
    expect(named).toBe('---\nlocation: 51.5074,-0.1278\nplace: "Trafalgar Square, London"\n---\n# A walk\n\nWords.');
    expect(geoTagOf(named)).toEqual({ ...LONDON, place: 'Trafalgar Square, London' });
  });

  it('keeps the other keys as they are, and quotes a place with a colon or a quote in it', () => {
    const body = '---\ntitle: "Plans"\nauthors: matt, Claude\n---\n# Plans\n';
    const tagged = withGeoTag(body, { ...LONDON, place: 'The "Old" Vic: Waterloo' });
    expect(tagged).toBe('---\ntitle: "Plans"\nauthors: matt, Claude\nlocation: 51.5074,-0.1278\nplace: "The \'Old\' Vic: Waterloo"\n---\n# Plans\n');
    expect(geoTagOf(tagged)?.place).toBe("The 'Old' Vic: Waterloo");
    // A place already written is replaced in its own line, not written twice.
    expect(withGeoTag(tagged, { ...LONDON, place: 'Waterloo' })).toBe('---\ntitle: "Plans"\nauthors: matt, Claude\nlocation: 51.5074,-0.1278\nplace: "Waterloo"\n---\n# Plans\n');
  });

  it('takes both keys out, and an emptied block with them', () => {
    const tagged = withGeoTag('# A walk\n', { ...LONDON, place: 'London' });
    expect(withGeoTag(tagged, null)).toBe('# A walk\n');
    const withTitle = withGeoTag('---\ntitle: "Map"\n---\n{}', LONDON);
    expect(withGeoTag(withTitle, null)).toBe('---\ntitle: "Map"\n---\n{}');
    expect(withGeoTag('# Plain', null)).toBe('# Plain');
  });

  it('writes four decimals from a fine fix and two from a rough one, read back as rough', () => {
    expect(tagOf({ lat: 51.50741234, lon: -0.12776, accuracy: 12, at: 0 })).toEqual({ lat: 51.5074, lon: -0.1278, place: null, rough: false });
    const rough = tagOf({ lat: 51.50741234, lon: -0.12776, accuracy: 2000, at: 0 });
    expect(rough).toEqual({ lat: 51.51, lon: -0.13, place: null, rough: true });
    const body = withGeoTag('# Out\n', rough);
    expect(body).toBe('---\nlocation: 51.51,-0.13\n---\n# Out\n');
    expect(geoTagOf(body)).toEqual(rough);
    // A rough fix's precision is the signal: the same numbers with four decimals read fine.
    expect(geoTagOf('---\nlocation: 51.5100,-0.1300\n---\n')?.rough).toBe(false);
  });
});

describe('a tag read from the note', () => {
  it('reads spaces after the comma, quotes and brackets alike', () => {
    for (const line of ['51.5074, -0.1278', '"51.5074,-0.1278"', "'51.5074, -0.1278'", '[51.5074, -0.1278]', '  51.5074 ,-0.1278  ']) {
      expect(geoTagOf(`---\nlocation: ${line}\n---\n# A`)).toEqual(LONDON);
    }
  });

  it('reads anything that is not two numbers in range as no tag, and leaves the line as it was', () => {
    for (const line of ['London', '51.5074', '91,0', '0,181', '51.5,abc', '', 'NaN,0']) {
      const body = `---\nlocation: ${line}\nplace: "Somewhere"\n---\n# A`;
      expect(geoTagOf(body)).toBeNull();
      // A writer never touches a line a reader could not read, either: the tag is written beside it.
      expect(withGeoTag(body, null)).toBe('# A');
    }
    expect(geoTagOf('# No front matter\nlocation: 51,0')).toBeNull();
    expect(geoTagOf('---\ntitle: "A"\n---\n# A')).toBeNull();
  });

  it('says the coordinates as a person reads them, and the place where one is known', () => {
    expect(coordsText(LONDON)).toBe('51.5074, -0.1278');
    expect(coordsText({ ...LONDON, lat: 51.51, lon: -0.13, rough: true })).toBe('Roughly 51.51, -0.13');
    expect(tagLabel(LONDON)).toBe('51.5074, -0.1278');
    expect(tagLabel({ ...LONDON, place: 'London' })).toBe('London');
    expect(sameTag(LONDON, { ...LONDON })).toBe(true);
    expect(sameTag(LONDON, { ...LONDON, place: 'London' })).toBe(false);
    expect(sameTag(null, null)).toBe(true);
    expect(sameTag(LONDON, null)).toBe(false);
  });
});

describe('the short name of a place', () => {
  const answer = (over: Record<string, unknown>) => ({ display_name: '10 Downing Street, Westminster, London, England, United Kingdom', ...over });

  it('takes a named place and its settlement', () => {
    expect(shortPlace(answer({ name: 'Trafalgar Square', addresstype: 'square', address: { road: 'Trafalgar Square', city: 'London', state: 'England', country: 'United Kingdom' } }), false)).toBe('Trafalgar Square, London');
  });

  it('takes the road where nothing is named, and the region where there is no settlement', () => {
    expect(shortPlace(answer({ addresstype: 'road', address: { road: 'Rue de Rivoli', city: 'Paris', country: 'France' } }), false)).toBe('Rue de Rivoli, Paris');
    expect(shortPlace(answer({ name: 'Hardangervidda', addresstype: 'plateau', address: { state: 'Vestland', country: 'Norway' } }), false)).toBe('Hardangervidda, Vestland');
    expect(shortPlace(answer({ addresstype: 'road', address: { road: 'High Street', village: 'Chipping Campden', county: 'Gloucestershire' } }), false)).toBe('High Street, Chipping Campden');
  });

  it('never names a house, and a rough tag takes the settlement and its region only', () => {
    const house = answer({ name: 'Number Ten', addresstype: 'house', address: { house_number: '10', road: 'Downing Street', city: 'London', state: 'England' } });
    expect(shortPlace(house, false)).toBe('Downing Street, London');
    expect(shortPlace(house, true)).toBe('London, England');
    expect(shortPlace(answer({ addresstype: 'building', address: { house_number: '221B', road: 'Baker Street', city: 'London' } }), false)).toBe('Baker Street, London');
  });

  it('falls back to the first two parts of the display name with any house number dropped, and nothing to null', () => {
    expect(shortPlace(answer({ address: {} }), false)).toBe('Downing Street, Westminster');
    expect(shortPlace({ address: {} }, false)).toBeNull();
    expect(shortPlace({ display_name: '   ' }, true)).toBeNull();
  });
});
