import { beforeEach, describe, expect, it } from 'vitest';
import { markAudioRemoved } from '../core/recordings.ts';
import { AUDIO_REMOVED, COULD_NOT_PLAY, NOT_ON_THIS_DEVICE, whyNotPlayed } from './useTape.ts';

/**
 * Why a tape did not play (tapes/useTape.ts `whyNotPlayed`): its audio removed from this device by the Tapes row, or
 * left on the device that made it, or a reason nothing here knows.
 */

beforeEach(() => {
  localStorage.clear();
});

describe('a tape that did not play', () => {
  it('says its audio was removed when the Tapes row removed it here', async () => {
    markAudioRemoved(['t1']);
    expect(await whyNotPlayed({ id: 't1', recordingMs: 60_000 }, async () => 200)).toBe(AUDIO_REMOVED);
  });

  it('says the recording is not on this device when its file answers 404: a meeting’s audio, or one over the sync limit', async () => {
    const asked: string[] = [];
    expect(
      await whyNotPlayed({ id: 't2', recordingMs: 3_600_000 }, async (id) => {
        asked.push(id);
        return 404;
      }),
    ).toBe(NOT_ON_THIS_DEVICE);
    expect(asked).toEqual(['t2']);
  });

  it('otherwise only that it could not be played', async () => {
    expect(await whyNotPlayed({ id: 't3', recordingMs: 60_000 }, async () => 500)).toBe(COULD_NOT_PLAY);
    expect(await whyNotPlayed({ id: 't3', recordingMs: 60_000 }, async () => null)).toBe(COULD_NOT_PLAY);
    expect(
      await whyNotPlayed({ id: 't3', recordingMs: 60_000 }, async () => {
        throw new Error('offline');
      }),
    ).toBe(COULD_NOT_PLAY);
    // A note with no recording has no file to ask about.
    expect(await whyNotPlayed({ id: 't4', recordingMs: 0 }, async () => 404)).toBe(COULD_NOT_PLAY);
  });
});
