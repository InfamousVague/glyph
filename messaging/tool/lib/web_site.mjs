/**
 * app.gogho.st: the app in a browser at an address of its own, apart from gogho.st's pages and the relay's own
 * answers there (/link, /files, /market), so nothing slipped into one of those can read what the app keeps in the
 * browser (docs/OPEN_NETWORK.md, part 6). tool/build-web.mjs --app builds it, naming gogho.st's hub; tool/deploy-site.mjs
 * --app ships it, with the block that serves it.
 */
import { readFileSync } from 'node:fs';

export const APP_HOST = 'app.gogho.st';

/** The hub the app.gogho.st build speaks to (lib/web/app.dart: hubFor, GHOST_WEB_HUB). */
export const APP_HUB = 'wss://gogho.st/hub';

/** Where the box keeps its files, swapped in whole as the site's are. */
export const APP_DIR = '/opt/ghost-sms-app';

/** A hub a build may name: wss to any host, or ws to this machine (for trying a build against a relay here). */
export const goodHub = (hub) => /^wss:\/\/[a-z0-9.-]+(:\d{1,5})?\/[A-Za-z0-9._~/-]*$/.test(hub) || /^ws:\/\/(127\.0\.0\.1|localhost)(:\d{1,5})?\/[A-Za-z0-9._~/-]*$/.test(hub);

const META = /<meta http-equiv="Content-Security-Policy" content="([^"]+)">/;

/** The policy a page's `<meta>` gives, from [html]; null where it gives none. */
export const policyOf = (html) => META.exec(html)?.[1] ?? null;

/** [policy] with connect-src the page's own address and [hub]: what a build that names its hub is held to. */
export function withHub(policy, hub) {
  const parts = policy.split(';').map((p) => p.trim());
  const at = parts.findIndex((p) => p.split(' ')[0] === 'connect-src');
  if (at < 0 || parts[at] !== "connect-src 'self'") throw new Error(`the page's policy has no plain connect-src 'self' to name the hub in (${policy}).`);
  parts[at] = `connect-src 'self' ${hub}`;
  return parts.join('; ');
}

/** [html] with its policy's connect-src naming [hub] ([withHub]). */
export function pageWithHub(html, hub) {
  const policy = policyOf(html);
  if (policy == null) throw new Error('the page has no Content-Security-Policy.');
  return html.replace(META, `<meta http-equiv="Content-Security-Policy" content="${withHub(policy, hub)}">`);
}

/** The policy of the app.gogho.st build, as the page in web/ (under [root]) says it with gogho.st's hub. */
export function appPolicy(root) {
  const policy = policyOf(readFileSync(`${root}/web/index.html`, 'utf8'));
  if (policy == null) throw new Error('web/index.html has no Content-Security-Policy.');
  return withHub(policy, APP_HUB);
}
