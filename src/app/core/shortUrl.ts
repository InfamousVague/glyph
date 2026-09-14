/**
 * A link's address, shortened for showing: `notion.so/att…b3c`. Matt: "don't
 * show the full link path just show the first 3 chars after the tld then a
 * ... and the last 3 chars". Pure, used wherever an address is shown: the
 * editor (editor/links.ts), the recorder's words and the list's titles.
 */

/**
 * The short form of `url`: the host without `www.`, then the first three and
 * the last three characters of what follows the host. A short path is kept
 * whole, since shortening it would save nothing.
 */
export function shortUrl(url: string): string {
  const bare = url.trim().replace(/^[a-z][a-z0-9+.-]*:\/\//i, '').replace(/^www\./i, '');
  const cut = bare.search(/[/?#]/);
  const host = cut < 0 ? bare : bare.slice(0, cut);
  const rest = (cut < 0 ? '' : bare.slice(cut)).replace(/^\/+/, '').replace(/\/+$/, '');
  if (!rest) return host;
  if (rest.length <= 9) return `${host}/${rest}`;
  return `${host}/${rest.slice(0, 3)}…${rest.slice(-3)}`;
}

/** Every http(s) address in running `text`, shortened. */
export function shortenUrls(text: string): string {
  return text.replace(/\bhttps?:\/\/[^\s)\]>]+/gi, (url) => shortUrl(url));
}
