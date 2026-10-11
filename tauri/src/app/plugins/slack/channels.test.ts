import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * Slack's channels on this device: a pasted webhook judged by its shape before Rust ever sees it, the webhook handed
 * to Rust before the name is kept here, and the page holding names and ids only. Rust's own check of the same shape is
 * src-tauri/src/slack.rs `allowed_webhook`.
 */

const calls: { command: string; args?: Record<string, unknown> }[] = [];
let refuse: string | null = null;
vi.mock('../../core/tauri.ts', () => ({
  isTauri: () => true,
  invoke: vi.fn(async (command: string, args?: Record<string, unknown>) => {
    if (command === 'ota_status') return { nativeGeneration: 25 };
    calls.push({ command, args });
    if (refuse) throw refuse;
    return command === 'slack_channels' ? ['kept'] : undefined;
  }),
}));

const { addChannel, channels, forgetChannel, renameChannel, webhookProblem, postToChannel, slackAvailable } = await import('./channels.ts');
const { host } = await import('./manifest.ts');

const HOOK = 'https://hooks.slack.com/services/T0001/B0001/abcDEF123';

beforeEach(() => {
  calls.length = 0;
  refuse = null;
  localStorage.clear();
});

describe('a pasted webhook', () => {
  it('is one Slack hands out: https, hooks.slack.com, services or workflows', () => {
    expect(webhookProblem(HOOK)).toBeNull();
    expect(webhookProblem(`  ${HOOK}  `)).toBeNull();
    expect(webhookProblem('https://hooks.slack.com/workflows/T0001/A0001/123/xyz')).toBeNull();
  });

  it('is refused, in a sentence, for anything else', () => {
    expect(webhookProblem('')).toBe('Paste the webhook Slack gave you.');
    expect(webhookProblem('http://hooks.slack.com/services/T0/B0/x')).toContain('never http://');
    expect(webhookProblem('https://hooks.slack.com.evil.example/services/T0/B0/x')).toContain('isn’t a Slack webhook');
    expect(webhookProblem('https://example.com/services/T0/B0/x')).toContain('isn’t a Slack webhook');
    expect(webhookProblem('https://hooks.slack.com/api/chat.postMessage')).toContain('isn’t a Slack incoming webhook');
    expect(webhookProblem('https://hooks.slack.com/services/')).toContain('isn’t a Slack incoming webhook');
    expect(webhookProblem('https://hooks.slack.com/services/T0/B0/x?then=elsewhere')).toContain('isn’t a Slack incoming webhook');
    expect(webhookProblem('https://hooks.slack.com/services/../api/x')).toContain('isn’t a Slack incoming webhook');
  });
});

describe('a channel', () => {
  it('needs the newest binary and the app', async () => {
    await expect(slackAvailable()).resolves.toBe(true);
  });

  it('hands its webhook to Rust and keeps only its name and id here', async () => {
    const channel = await addChannel('  #launch ', HOOK);
    expect(channel.name).toBe('#launch');
    expect(channel.id).toMatch(/^[0-9a-f]{32}$/);
    expect(calls).toEqual([{ command: 'slack_save_channel', args: { id: channel.id, url: HOOK } }]);
    expect(channels()).toEqual([channel]);
    expect(localStorage.getItem('glyph-slack-channels')).not.toContain('hooks.slack.com');
  });

  it('is not listed when Rust refuses its webhook', async () => {
    refuse = 'cannot keep the Slack webhook: disk full';
    await expect(addChannel('#launch', HOOK)).rejects.toBe('cannot keep the Slack webhook: disk full');
    expect(channels()).toEqual([]);
  });

  it('refuses a name that is empty or taken, and a webhook that is not one, before Rust is asked', async () => {
    await addChannel('#launch', HOOK);
    calls.length = 0;
    await expect(addChannel('  ', HOOK)).rejects.toThrow('Give the channel a name');
    await expect(addChannel('#LAUNCH', HOOK)).rejects.toThrow('There is a channel called #LAUNCH already.');
    await expect(addChannel('#ops', 'https://example.com/hook')).rejects.toThrow('isn’t a Slack webhook');
    expect(calls).toEqual([]);
  });

  it('is renamed here alone, and forgotten in Rust and here', async () => {
    const launch = await addChannel('#launch', HOOK);
    const ops = await addChannel('#ops', HOOK);
    renameChannel(launch.id, '#ship-it');
    expect(() => renameChannel(launch.id, '#ops')).toThrow('already');
    expect(channels().map((c) => c.name)).toEqual(['#ship-it', '#ops']);
    calls.length = 0;
    await forgetChannel(launch.id);
    expect(calls).toEqual([{ command: 'slack_forget_channel', args: { id: launch.id } }]);
    expect(channels()).toEqual([ops]);
    await forgetChannel(ops.id);
    expect(localStorage.getItem('glyph-slack-channels')).toBeNull();
  });

  it('is posted to by its id, never by its webhook', async () => {
    const launch = await addChannel('#launch', HOOK);
    calls.length = 0;
    await postToChannel(launch, '*Hello*');
    expect(calls).toEqual([{ command: 'slack_post', args: { id: launch.id, payload: { text: '*Hello*' } } }]);
  });

  it('reaches only what its manifest lists', async () => {
    await expect(host.invoke('notion_request')).rejects.toThrow('didn\'t declare the native command “notion_request”');
    expect(() => host.storage.get('glyph-notes', null)).toThrow();
  });
});
