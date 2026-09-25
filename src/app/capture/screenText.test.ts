import { describe, expect, it } from 'vitest';
import { statusLine, stopHint, whereLine } from './screenText.ts';

/** The recorder's own lines (capture/screenText.ts): the top line, and how a recording ends. */

const listening = { phase: 'listening' as const, error: null, download: null, heardWords: false };

describe('the top line', () => {
  it('says what stands between the person and the recording', () => {
    expect(statusLine({ ...listening, phase: 'starting' })).toBe('Starting');
    expect(statusLine({ ...listening, phase: 'finishing' })).toBe('Saving');
    expect(statusLine({ ...listening, phase: 'failed' })).toBe('Could not start');
    expect(statusLine({ ...listening, phase: 'failed', error: 'Local only is on' })).toBe('Local only is on');
  });

  it('counts a download in megabytes, whatever the phase', () => {
    expect(statusLine({ ...listening, phase: 'starting', download: { received: 12_400_000, total: 60_100_000 } })).toBe('Downloading voice model 12 / 60 MB');
  });

  it('shows a problem only until the first words, and says nothing while it listens', () => {
    expect(statusLine({ ...listening, error: 'capture_push rejected' })).toBe('Problem: capture_push rejected');
    expect(statusLine({ ...listening, error: 'capture_push rejected', heardWords: true })).toBeNull();
    expect(statusLine(listening)).toBeNull();
  });

  it('says where the words are going, and names no note over the lock screen', () => {
    expect(whereLine(null, false)).toBe('New note');
    expect(whereLine({ body: '# Weekend trip\n\nBook the cabin.' }, false)).toBe('Adding to “Weekend trip”');
    expect(whereLine({ body: '# Weekend trip' }, true)).toBe('Adding to your last note');
  });
});

describe('how a recording ends', () => {
  it('names the side key the way this phone stops with it', () => {
    expect(stopHint(true, true, false)).toBe('Press the side key to stop.');
    expect(stopHint(true, false, false)).toBe('Hold the side key again to stop.');
    expect(stopHint(false, true, false)).toBe('Press the side key to stop.');
  });

  it('says going quiet finishes it when that is on', () => {
    expect(stopHint(false, false, true)).toBe('Stop talking to finish, or tap Done.');
    expect(stopHint(true, false, true)).toBe('Stop talking to finish, or hold the side key again.');
  });

  it('is Done otherwise', () => {
    expect(stopHint(false, false, false)).toBe('Tap Done to stop.');
  });
});
