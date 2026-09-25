import { describe, expect, it } from 'vitest';
import { describeBuild, type ApkInfo, type ApkPhase, type OtaStatus, type Updates } from '../core/ota.ts';
import { buildLine, installable, updatesStatus, updatesSummary, type BuildPlace } from './updateLines.ts';

/**
 * What About says about where this build stands: the page's ladder, the list's shorter one, and the line under the
 * version. Each rung is one fact about the updates set on a build that has nothing else going on, so a rung that
 * moves above or below another fails here rather than on somebody's phone.
 */

const info: ApkInfo = { version: '1.9.0', versionCode: 190, native: 20, sha256: '', bytes: 1, url: '' };

function updates(over: Partial<Updates> = {}): Updates {
  return {
    ready: null,
    apk: { kind: 'none' },
    checking: false,
    lastError: null,
    lastChecked: null,
    status: null,
    build: '20260924221500',
    version: '1.8.0',
    check: () => undefined,
    reload: () => undefined,
    installApk: () => undefined,
    ...over,
  };
}

const status = (over: Partial<OtaStatus> = {}): OtaStatus => ({
  nativeVersion: '1.8.0',
  nativeGeneration: 20,
  embeddedBuild: null,
  embeddedVersion: null,
  activeBuild: null,
  activeVersion: null,
  runningBuild: null,
  quarantined: [],
  ...over,
});

describe('the Updates card', () => {
  it('says the first thing that is true, from checking down to never checked', () => {
    const ready = { build: '20260925000000', version: '1.8.1' };
    expect(updatesStatus(updates({ checking: true, ready, lastChecked: 1 }))).toBe('Checking for updates.');
    expect(updatesStatus(updates({ apk: { kind: 'downloading', info, received: 1, total: 2 }, ready }))).toBe('Downloading Ghost.md 1.9.0.');
    expect(updatesStatus(updates({ apk: { kind: 'available', info }, ready }))).toBe('Ghost.md 1.9.0 is ready to install.');
    expect(updatesStatus(updates({ ready, lastError: 'offline' }))).toBe('A new version is downloaded.');
    expect(updatesStatus(updates({ lastError: 'offline', lastChecked: 1 }))).toBe("Couldn't check for updates: offline");
    expect(updatesStatus(updates({ lastChecked: 1 }))).toBe('Up to date.');
    expect(updatesStatus(updates())).toBe('Not checked yet.');
  });

  it('offers to install an app that was found, or whose install stopped short, and nothing else', () => {
    const phases: [ApkPhase, boolean][] = [
      [{ kind: 'none' }, false],
      [{ kind: 'available', info }, true],
      [{ kind: 'downloading', info, received: 0, total: 1 }, false],
      [{ kind: 'installing', info }, false],
      [{ kind: 'needs-permission', info }, true],
      [{ kind: 'failed', info, message: 'no' }, true],
    ];
    for (const [phase, offered] of phases) expect(installable(phase), phase.kind).toBe(offered);
  });
});

describe('About in the list of sections', () => {
  it('says it is the web version in a browser, whatever the updates say', () => {
    expect(updatesSummary(updates({ checking: true }), false)).toBe('Web version');
  });

  it('climbs a shorter ladder in the app, with no rung for an app downloading', () => {
    expect(updatesSummary(updates({ checking: true }), true)).toBe('Checking');
    expect(updatesSummary(updates({ apk: { kind: 'available', info } }), true)).toBe('1.9.0 ready to install');
    expect(updatesSummary(updates({ ready: { build: '1', version: '1.8.1' } }), true)).toBe('New version downloaded');
    expect(updatesSummary(updates({ lastError: 'offline' }), true)).toBe("Couldn't check");
    expect(updatesSummary(updates({ lastChecked: 1 }), true)).toBe('Up to date');
    expect(updatesSummary(updates(), true)).toBe('Not checked yet');
    // Downloading reads as whatever the rest of the ladder says: here, checked and current.
    expect(updatesSummary(updates({ apk: { kind: 'downloading', info, received: 1, total: 2 }, lastChecked: 1 }), true)).toBe('Up to date');
  });
});

describe('the line under the version', () => {
  const app: BuildPlace = { native: true, overTheAir: false, staging: false };
  const when = describeBuild('20260924221500');

  it('is only when the page was built, in a browser', () => {
    expect(buildLine(updates({ status: status({ sources: ['https://attack.fm/glyph'] }) }), { ...app, native: false })).toBe(when);
  });

  it('says how the page arrived, when, the app it runs in and where its updates come from', () => {
    const line = buildLine(updates({ status: status({ sources: ['https://attack.fm/glyph'] }) }), { ...app, overTheAir: true });
    expect(line).toBe(`Updated over the air · ${when} · app 1.8.0 · updates from attack.fm`);
    expect(buildLine(updates({ status: status() }), app)).toBe(`Built into the app · ${when} · app 1.8.0`);
  });

  it('leaves out the app before the binary has answered, and says a staging build has its updates off', () => {
    expect(buildLine(updates(), app)).toBe(`Built into the app · ${when}`);
    expect(buildLine(updates({ status: status({ sources: ['https://attack.fm/glyph'] }) }), { ...app, staging: true })).toBe(`Built into the app · ${when} · app 1.8.0 · staging build, updates off`);
  });
});
