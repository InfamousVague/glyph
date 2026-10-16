import { describe, expect, it } from 'vitest';
import { apiHost, manifest, RELEASE_API } from '../src/manifest.ts';

/** What the clipper asks of the browser: as little as does the job (src/manifest.ts says why each). */

describe('the manifest', () => {
  const chrome = manifest('chrome', { api: RELEASE_API, version: '0.1.0' });
  const firefox = manifest('firefox', { api: RELEASE_API, version: '0.1.0' });

  it('asks for four permissions and one host, the service, and nothing at install beyond them', () => {
    for (const m of [chrome, firefox]) {
      expect(m.manifest_version).toBe(3);
      expect(m.permissions).toEqual(['activeTab', 'scripting', 'storage', 'contextMenus']);
      expect(m.host_permissions).toEqual(['https://ghostmarkdown.com/*']);
      expect(JSON.stringify(m)).not.toContain('<all_urls>');
      expect(m).not.toHaveProperty('content_scripts');
      expect(m).not.toHaveProperty('web_accessible_resources');
      expect(m).not.toHaveProperty('externally_connectable');
    }
  });

  it('runs in Chrome as a service worker and in Firefox as an event page with an id of its own', () => {
    expect(chrome.background).toEqual({ service_worker: 'background.js' });
    expect(firefox.background).toEqual({ scripts: ['background.js'] });
    expect((firefox.browser_specific_settings as { gecko: { id: string } }).gecko.id).toBe('clipper@ghostmarkdown.com');
  });

  it('has the popup on its button and a shortcut for it and for saving straight away', () => {
    expect(chrome.action).toMatchObject({ default_popup: 'popup.html' });
    expect(Object.keys(chrome.commands as object)).toEqual(['_execute_action', 'save-clip']);
  });

  it('names a local service by its host, which a match pattern cannot give a port', () => {
    expect(apiHost('http://127.0.0.1:5555/api')).toBe('http://127.0.0.1/*');
    expect(manifest('chrome', { api: 'http://127.0.0.1:5555/api', version: '0.1.0' }).host_permissions).toEqual(['http://127.0.0.1/*']);
  });
});
