import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import type { ApkInfo, Updates } from '../core/ota.ts';
import { button, show } from '../../test/render.tsx';
import { AcademyCard, UpdateNotice, VoiceModelStatus } from './Notices.tsx';

/**
 * What is waiting on the person, in the words it is said in: each stage of an update, the voice model coming down or
 * failing to, and the Academy's invitation. Each says nothing at all when there is nothing to say, which the sidebar
 * relies on to hide its notices' room (NoteTree.module.css `.notices:not(:has(> *))`).
 */

const info: ApkInfo = { version: '1.9.0', versionCode: 190, native: 20, sha256: '', bytes: 48_000_000, url: '' };
const updates = (over: Partial<Updates> = {}): Updates =>
  ({ ready: null, apk: { kind: 'none' }, checking: false, lastError: null, lastChecked: null, status: null, build: 'b', version: 'v', check: vi.fn(), reload: vi.fn(), installApk: vi.fn(), ...over }) as Updates;

describe('the update card', () => {
  it('says nothing with nothing newer', () => {
    const host = show(<UpdateNotice updates={updates()} />);
    expect(host.innerHTML).toBe('');
  });

  it('offers a new version to install, and installs it', () => {
    const waiting = updates({ apk: { kind: 'available', info } });
    const host = show(<UpdateNotice updates={waiting} />);
    expect(host.textContent).toContain('Ghost.md 1.9.0 is out.');
    act(() => button('Install', host).click());
    expect(waiting.installApk).toHaveBeenCalledTimes(1);
  });

  it('counts a download in whole megabytes, with its bar, and offers nothing to press meanwhile', () => {
    const host = show(<UpdateNotice updates={updates({ apk: { kind: 'downloading', info, received: 12_400_000, total: 48_000_000 } })} />);
    expect(host.textContent).toContain('Downloading Ghost.md 1.9.0, 12 of 48 MB.');
    expect(host.querySelector('button')).toBeNull();
    expect(host.querySelector<HTMLElement>('[aria-hidden="true"] > span')?.style.inlineSize).toBe('26%');
  });

  it('says why an install did not happen, and offers it again', () => {
    const host = show(<UpdateNotice updates={updates({ apk: { kind: 'failed', info, message: 'The file was damaged.' } })} />);
    expect(host.textContent).toContain('Ghost.md 1.9.0 didn’t install. The file was damaged.');
    expect(button('Try again', host)).toBeTruthy();
  });

  it('asks to be let install, and waits on Android once it has asked', () => {
    const asking = show(<UpdateNotice updates={updates({ apk: { kind: 'needs-permission', info } })} />);
    expect(asking.textContent).toContain('Let Ghost.md install apps, then come back.');
    const waiting = show(<UpdateNotice updates={updates({ apk: { kind: 'installing', info } })} />);
    expect(waiting.textContent).toContain('Ghost.md 1.9.0 is waiting on Android.');
    expect(button('Open', waiting)).toBeTruthy();
  });

  it('offers a reload for a new version of the page already downloaded', () => {
    const ready = updates({ ready: { build: 'c', version: '1.9.0' } });
    const host = show(<UpdateNotice updates={ready} />);
    expect(host.textContent).toContain('A new version of Ghost.md is ready.');
    act(() => button('Reload', host).click());
    expect(ready.reload).toHaveBeenCalledTimes(1);
  });
});

describe('the voice model’s line', () => {
  it('is there only while voice notes cannot work yet', () => {
    for (const kind of ['ready', 'unsupported', 'checking'] as const) {
      const host = show(<VoiceModelStatus state={{ kind }} onRetry={() => undefined} />);
      expect(host.innerHTML).toBe('');
    }
  });

  it('counts its download, and offers another go when it failed', () => {
    const coming = show(<VoiceModelStatus state={{ kind: 'downloading', received: 30_600_000, total: 148_000_000 }} onRetry={() => undefined} />);
    expect(coming.textContent).toBe('Downloading the voice model, 31 of 148 MB. Keep Ghost.md open.');
    const onRetry = vi.fn();
    const failed = show(<VoiceModelStatus state={{ kind: 'failed', message: 'offline' }} onRetry={onRetry} />);
    expect(failed.querySelector('[role="alert"]')?.textContent).toContain('The voice model didn’t download.');
    act(() => button('Try again', failed).click());
    expect(onRetry).toHaveBeenCalledTimes(1);
  });
});

describe('the Academy’s invitation', () => {
  it('starts the Academy, and can be put away when there is a way to', () => {
    const onOpen = vi.fn();
    const onHide = vi.fn();
    const host = show(<AcademyCard onOpen={onOpen} onHide={onHide} />);
    act(() => button('Start', host).click());
    act(() => button('Not now', host).click());
    expect(onOpen).toHaveBeenCalledTimes(1);
    expect(onHide).toHaveBeenCalledTimes(1);
    const bare = show(<AcademyCard onOpen={onOpen} />);
    expect(bare.querySelector('button[aria-label="Not now"]')).toBeNull();
  });
});
