/**
 * The extension's manifest, one source for both browsers (Manifest V3). What it asks for, and why, is the narrowest
 * set that does the job, said here once:
 *
 * - `activeTab`: the tab the person opened the clipper on, the menu item or the shortcut was used in, and only for
 *   that moment. No page is read until the person asks.
 * - `scripting`: to run the clipper's reader (content.js) in that tab, which `activeTab` lets it do there and nowhere
 *   else. There is no content script declared for every page.
 * - `storage`: the session (core/keep.ts), in the browser's memory unless the person ticks "Stay signed in".
 * - `contextMenus`: "Save selection to Ghost.md".
 * - One host: the Ghost.md service the build talks to (`api`), so a sealed note can be sent there. Nothing else.
 * - Optional hosts, asked for one site at a time and only when the person presses "Keep them" for pictures the page's
 *   own site would not hand over: a picture on a CDN is read with that site's permission, never `<all_urls>` at
 *   install. A screenshot needs none: `activeTab` covers `captureVisibleTab`.
 *
 * Firefox runs the same background as an event page (`background.scripts`) and needs an id of its own.
 */

export type Target = 'chrome' | 'firefox';

export const RELEASE_API = 'https://ghostmarkdown.com/api';

/** The match pattern for the service's own address: its origin, any path. A pattern cannot name a port, so a local one is its host. */
export function apiHost(api: string): string {
  const url = new URL(api);
  return `${url.protocol}//${url.hostname}/*`;
}

export function manifest(target: Target, { api, version }: { api: string; version: string }): Record<string, unknown> {
  const icons = { 16: 'icons/16.png', 32: 'icons/32.png', 48: 'icons/48.png', 128: 'icons/128.png' };
  return {
    manifest_version: 3,
    name: 'Ghost.md Clipper',
    short_name: 'Ghost.md',
    version,
    description: 'Save what is on a web page into your Ghost.md notes, encrypted in the browser before it leaves.',
    icons,
    action: { default_popup: 'popup.html', default_title: 'Ghost.md clipper', default_icon: { 16: icons[16], 32: icons[32] } },
    permissions: ['activeTab', 'scripting', 'storage', 'contextMenus'],
    host_permissions: [apiHost(api)],
    optional_host_permissions: ['https://*/*', 'http://*/*'],
    background: target === 'chrome' ? { service_worker: 'background.js' } : { scripts: ['background.js'] },
    commands: {
      _execute_action: { suggested_key: { default: 'Alt+Shift+G' }, description: 'Open the clipper' },
      'save-clip': { suggested_key: { default: 'Alt+Shift+S' }, description: 'Save the selection, or else the article, straight away' },
    },
    ...(target === 'firefox'
      ? {
          browser_specific_settings: {
            gecko: {
              id: 'clipper@ghostmarkdown.com',
              strict_min_version: '128.0',
              // What leaves the browser, in Mozilla's words: the page's words (sealed, to the person's own account) and
              // the login half of the password. Nothing is collected by anyone else.
              data_collection_permissions: { required: ['websiteContent', 'authenticationInfo'] },
            },
          },
        }
      : { minimum_chrome_version: '120' }),
  };
}
