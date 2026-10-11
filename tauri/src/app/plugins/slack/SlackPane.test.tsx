import { beforeEach, describe, expect, it, vi } from 'vitest';
import { button, press, show, typeInto, waitUntil } from '../../../test/render.tsx';
import type { OrgRow } from '../../core/orgs/types.ts';

/**
 * The Slack plugin's page in Settings: a channel added by name and pasted webhook, which is never shown again; a test
 * message, a new name and forgetting; where an organization's news goes, for the organizations the person is in; and
 * in a browser, only that Slack works in the app.
 */

let native = true;
const calls: { command: string; args?: Record<string, unknown> }[] = [];
const kept = new Set<string>();
vi.mock('../../core/tauri.ts', () => ({
  isTauri: () => native,
  invoke: vi.fn(async (command: string, args?: { id?: string }) => {
    if (command === 'ota_status') return { nativeGeneration: 25 };
    calls.push({ command, args });
    if (command === 'slack_save_channel') kept.add(args!.id!);
    if (command === 'slack_forget_channel') kept.delete(args!.id!);
    return command === 'slack_channels' ? [...kept] : undefined;
  }),
}));

const member = (id: string, name: string, state: OrgRow['state'] = 'member'): OrgRow => ({ id, name, hue: null, role: 'member', state, members: 3, invitedBy: null, createdAt: 0 });
let orgs: OrgRow[] = [];
vi.mock('../../core/orgs/orgs.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../core/orgs/orgs.ts')>()),
  useOrgs: () => ({ list: orgs, at: 1 }),
}));

const { SlackPane } = await import('./SlackPane.tsx');
const { channels } = await import('./channels.ts');
const { newsChannelFor } = await import('./news.ts');

const HOOK = 'https://hooks.slack.com/services/T0/B0/secretpart';
const field = (pane: HTMLElement, label: string) => pane.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!;

async function addLaunch(pane: HTMLElement): Promise<void> {
  typeInto(field(pane, 'Channel name'), '#launch');
  typeInto(field(pane, 'Webhook'), HOOK);
  press(button('Add it', pane));
  await waitUntil(() => expect(pane.textContent).toContain('Added #launch.'));
}

beforeEach(() => {
  native = true;
  calls.length = 0;
  kept.clear();
  orgs = [];
  localStorage.clear();
});

describe('Slack’s page', () => {
  it('says Slack works in the app, in a browser', () => {
    native = false;
    const pane = show(<SlackPane />);
    expect(pane.textContent).toContain('Slack works in the app.');
    expect(pane.querySelector('input')).toBeNull();
  });

  it('adds a channel, then lists it by its name alone, kept on this device', async () => {
    const pane = show(<SlackPane />);
    await waitUntil(() => expect(pane.textContent).toContain('No channels yet'));
    expect(pane.textContent).toContain('Kept on this device');
    typeInto(field(pane, 'Channel name'), '#launch');
    typeInto(field(pane, 'Webhook'), 'https://example.com/hook');
    expect(pane.textContent).toContain('isn’t a Slack webhook');
    expect(button('Add it', pane).disabled).toBe(true);
    await addLaunch(pane);
    expect(channels().map((c) => c.name)).toEqual(['#launch']);
    expect(pane.textContent).not.toContain('secretpart');
    expect(field(pane, 'Webhook').value).toBe('');
  });

  it('sends a test, renames and forgets a channel', async () => {
    const pane = show(<SlackPane />);
    await addLaunch(pane);
    const id = channels()[0]!.id;
    press(button('Test', pane));
    await waitUntil(() => expect(pane.textContent).toContain('Sent a test to #launch.'));
    expect(calls.find((c) => c.command === 'slack_post')?.args).toEqual({ id, payload: { text: 'A test from Ghost.md. What you post from this device will land here.' } });
    press(button('Rename', pane));
    typeInto(field(pane, 'Channel name'), '#ship');
    press(button('Keep it', pane));
    expect(channels().map((c) => c.name)).toEqual(['#ship']);
    press(button('Forget', pane));
    await waitUntil(() => expect(pane.textContent).toContain('Forgot #ship.'));
    expect(channels()).toEqual([]);
    expect(kept.size).toBe(0);
  });

  it('chooses a channel for the news of each organization the person is in, and nowhere again', async () => {
    orgs = [member('acme', 'Acme'), member('globex', 'Globex', 'invited')];
    const pane = show(<SlackPane />);
    expect(pane.textContent).not.toContain('Organizations’ news');
    await addLaunch(pane);
    expect(pane.textContent).toContain('Organizations’ news');
    expect(pane.textContent).toContain('each device with a channel set posts the news');
    expect(pane.textContent).not.toContain('Globex');
    press(button('Change', pane));
    press(button('Post Acme’s news to #launch', pane));
    expect(newsChannelFor('acme')?.name).toBe('#launch');
    expect(pane.textContent).toContain('Its news goes to #launch.');
    press(button('Change', pane));
    press(button('Don’t post Acme’s news', pane));
    expect(newsChannelFor('acme')).toBeNull();
  });
});
