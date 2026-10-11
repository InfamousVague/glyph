import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * A meeting's gate and its title (capture/meeting.ts): where one can be recorded, by platform and by the binary's
 * generation, and the date title in three locales, which ai/summaryText.ts must still know as a date title.
 */

const platform = vi.hoisted(() => ({ tauri: false, android: false, ios: false, mobile: false, generation: 0 }));
vi.mock('../core/tauri.ts', () => ({
  isTauri: () => platform.tauri,
  invoke: async (command: string) => {
    if (command === 'ota_status') return { nativeGeneration: platform.generation };
    throw new Error(`no ${command} here`);
  },
}));
vi.mock('../core/platform.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/platform.ts')>()),
  get isAndroid() {
    return platform.android;
  },
  get isIOS() {
    return platform.ios;
  },
  get isMobile() {
    return platform.mobile;
  },
}));

const { canRecordMeeting, MEETING_GENERATION, meetingBody, meetingTitle } = await import('./meeting.ts');
const { dateTitled } = await import('../ai/summaryText.ts');

beforeEach(() => {
  platform.tauri = false;
  platform.android = false;
  platform.ios = false;
  platform.mobile = false;
  platform.generation = 0;
  // The generation is asked once per page load and kept: each test loads the module afresh.
  vi.resetModules();
});

describe('where a meeting can be recorded', () => {
  it('never in a browser, and never on iOS, which has no whisper and no model', async () => {
    expect(await canRecordMeeting()).toBe(false);
    platform.tauri = true;
    platform.ios = true;
    platform.mobile = true;
    expect(await canRecordMeeting()).toBe(false);
  });

  it('on the Mac, in the page recorder', async () => {
    platform.tauri = true;
    expect(await canRecordMeeting()).toBe(true);
  });

  it('on Android only from the generation with the service', async () => {
    platform.tauri = true;
    platform.android = true;
    platform.mobile = true;
    platform.generation = MEETING_GENERATION - 1;
    const { canRecordMeeting: older } = await import('./meeting.ts');
    expect(await older()).toBe(false);
    vi.resetModules();
    platform.generation = MEETING_GENERATION;
    const { canRecordMeeting: newer } = await import('./meeting.ts');
    expect(await newer()).toBe(true);
    expect(MEETING_GENERATION).toBe(20);
  });
});

describe('the title', () => {
  // Local times: the title is the time on the phone's own clock.
  const afternoon = new Date(2026, 8, 26, 14, 5).getTime();
  const smallHours = new Date(2026, 8, 26, 0, 5).getTime();

  it('is the day and the month in the locale’s own order, and the time on a 24-hour clock', () => {
    expect(meetingTitle(afternoon, 'en-GB')).toBe('Meeting, 26 Sept 14:05');
    expect(meetingTitle(afternoon, 'en-US')).toBe('Meeting, Sep 26 14:05');
    // The locale's literal after the day (".") is dropped, and its month abbreviation kept as it is.
    expect(meetingTitle(afternoon, 'de-DE')).toBe('Meeting, 26 Sept. 14:05');
    expect(meetingTitle(smallHours, 'en-GB')).toBe('Meeting, 26 Sept 00:05');
    expect(meetingTitle(smallHours, 'en-US')).toBe('Meeting, Sep 26 00:05');
    expect(meetingTitle(smallHours, 'de-DE')).toBe('Meeting, 26 Sept. 00:05');
  });

  it('is still a date title to the summary, in every locale and at every hour, so the model’s heading can take its place', () => {
    for (const locale of ['en-US', 'en-GB', 'de-DE', undefined]) {
      for (const ms of [afternoon, smallHours]) {
        expect(dateTitled(`# ${meetingTitle(ms, locale)}\n\nWords.`), `${locale} at ${ms}`).toBe(true);
      }
    }
    expect(dateTitled('# Planning call')).toBe(false);
  });

  it('heads the body a meeting note is made with, over its transcript', () => {
    const body = meetingBody('Meeting, 26 Sep 14:05', [
      { text: 'we settled the date.', startMs: 0, endMs: 1000 },
      { text: 'A different one.', startMs: 4000, endMs: 5000 },
    ]);
    expect(body).toBe('# Meeting, 26 Sep 14:05\n\n## Transcript\n\nWe settled the date.\n\nA different one.');
    expect(dateTitled(body)).toBe(true);
  });
});
