import { describe, expect, it } from 'vitest';
import { sealShare, type Shared } from '../app/share/share.ts';
import { isSitePath, readSite, readSiteAddress, SITE_CONTEXT, sitePath, siteSlugs, slugOf } from './site.ts';

/**
 * A published site's addresses (site.ts, docs/SITES.md): the id from the path and the key from the part after the #;
 * each page named from its title the same way every time; and the site read with its key, sealed in a site's own
 * context, from nothing but its id.
 */

const ID = 'SiteSiteSiteSiteSite01';
const KEY = 'k'.repeat(43);

describe('a site’s address', () => {
  it('is /s/<id>, with or without a page, and its key after the #', () => {
    expect(readSiteAddress(`/s/${ID}`, `#${KEY}`)).toEqual({ id: ID, slug: null, key: KEY });
    expect(readSiteAddress(`/s/${ID}/`, `#${KEY}`)).toEqual({ id: ID, slug: null, key: KEY });
    expect(readSiteAddress(`/s/${ID}/cafe-plans`, `#${KEY}`)).toEqual({ id: ID, slug: 'cafe-plans', key: KEY });
    expect(readSiteAddress(`/s/${ID}/%E5%A4%A7%E9%98%AA`, `#${KEY}`)?.slug).toBe('大阪');
    expect(readSiteAddress(`/s/${ID}/a`, '')?.key).toBeNull();
    expect(readSiteAddress(`/s/${ID}/a`, '#short')?.key).toBeNull();
    for (const not of ['/read.html', '/s/short', `/s/${ID}/a/b`, `/x/${ID}`, `/s/${'a'.repeat(65)}`]) expect(readSiteAddress(not, `#${KEY}`)).toBeNull();
    expect([isSitePath(`/s/${ID}`), isSitePath(`/s/${ID}/trees`), isSitePath('/read.html'), isSitePath('/s/')]).toEqual([true, true, false, false]);
  });

  it('names a page from its title: lower case, accents off, any script’s letters kept, one dash between', () => {
    expect(slugOf('Café plans, 2026')).toBe('cafe-plans-2026');
    expect(slugOf('  The *long* road!  ')).toBe('the-long-road');
    expect(slugOf('大阪の朝')).toBe('大阪の朝');
    expect(slugOf('!!!')).toBe('');
    expect(slugOf('a'.repeat(80))).toHaveLength(60);
  });

  it('gives the first page none, every other a name of its own, and keeps the key on every page’s address', () => {
    const shared: Shared = { v: 1, kind: 'book', title: 'Field guide', at: 1, pages: ['Field guide', 'Trees', 'Trees', '???', 'trees 2'].map((title) => ({ title, body: `# ${title}` })) };
    expect(siteSlugs(shared)).toEqual(['', 'trees', 'trees-2', 'page-4', 'trees-2-2']);
    expect(sitePath(ID, '', `#${KEY}`)).toBe(`/s/${ID}#${KEY}`);
    expect(sitePath(ID, 'trees', `#${KEY}`)).toBe(`/s/${ID}/trees#${KEY}`);
  });
});

describe('reading a site', () => {
  it('asks the service for the id alone, and opens what it holds with the key, in a site’s context', async () => {
    const key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
    const shared: Shared = { v: 1, kind: 'note', title: 'Walk', at: 1, pages: [{ title: 'Walk', body: '# Walk\n\nBy the river.' }] };
    const blob = await sealShare(shared, key, SITE_CONTEXT);
    const asked: string[] = [];
    const fetcher = (async (url: string | URL | Request) => {
      asked.push(String(url));
      return new Response(JSON.stringify({ blob, updated: 1 }), { status: 200 });
    }) as typeof fetch;
    const read = await readSite(ID, key, fetcher);
    expect(read.pages[0]!.body).toContain('By the river.');
    expect(asked).toHaveLength(1);
    expect(asked[0]).toMatch(new RegExp(`/v1/sites/${ID}$`));
    expect(asked[0]).not.toContain(key);
    // A shared link's blob is not a site's: the contexts differ.
    const shareBlob = await sealShare(shared, key);
    const share = (async () => new Response(JSON.stringify({ blob: shareBlob, updated: 1 }), { status: 200 })) as typeof fetch;
    await expect(readSite(ID, key, share)).rejects.toThrow();
  });
});
