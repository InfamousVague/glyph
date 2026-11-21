// The MV3 manifest, built for a target. Permissions are kept to what the extension actually needs: `cookies` and
// host access to the service domains (to read their httpOnly sign-in cookies) and `storage` (to hold the session).
// The hub it syncs through is a WebSocket the worker opens; MV3 does not gate that by host permission.
import { SERVICES } from './ghost/services.ts';

export const RELEASE_HUB = 'wss://gogho.st/hub';

/** `https://*.<domain>/*` for every service domain, which `cookies` needs to read that site's cookies. */
function cookieHosts(): string[] {
  const bases = new Set(SERVICES.flatMap((s) => s.domains.map((d) => d.replace(/^\./, ''))));
  return [...bases].map((b) => `https://*.${b}/*`);
}

export function manifest(target: 'chrome' | 'firefox', opts: { version: string }): Record<string, unknown> {
  const base: Record<string, unknown> = {
    manifest_version: 3,
    name: 'Ghost Messaging — keys',
    version: opts.version,
    description:
      'Captures your Messenger, Instagram and LinkedIn sign-in cookies and syncs them, sealed, across every device signed into your Ghost account — so you sign in once, not on every device.',
    permissions: ['cookies', 'storage'],
    host_permissions: cookieHosts(),
    action: { default_title: 'Ghost Messaging keys', default_popup: 'popup.html' },
    icons: { 16: 'icons/16.png', 48: 'icons/48.png', 128: 'icons/128.png' },
  };
  if (target === 'firefox') {
    return {
      ...base,
      background: { scripts: ['background.js'], type: 'module' },
      browser_specific_settings: { gecko: { id: 'keys@ghost-messaging' } },
    };
  }
  return {
    ...base,
    background: { service_worker: 'background.js' },
    minimum_chrome_version: '120',
  };
}
