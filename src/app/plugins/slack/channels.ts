import { useSyncExternalStore } from 'react';
import { isTauri } from '../../core/tauri.ts';
import { onPluginStorage } from '../host.ts';
import { host } from './manifest.ts';

/**
 * The Slack plugin's channels on this device: what each is called, and the way to post to it.
 *
 * Matt: "include #6 as a plugin as well as #5", where #5 was "Slack: post a meeting's summary, or a note, to a channel
 * when you choose to. It pairs well with organizations: a team's news could go to its channel too. Sending is always
 * your choice, so the encryption holds." He chose incoming webhooks: nothing to sign in to and nothing on the server,
 * the post goes straight from the device.
 *
 * A channel is two halves kept in two places:
 *
 * - **Its name and id** in the plugin's storage, `glyph-slack-channels`, which the page lists and a reset clears. The
 *   name is the person's own ("#launch"); Slack never tells a webhook's poster which channel it is.
 * - **Its webhook** in Rust, `slack.json` in the app's data directory (src-tauri/src/slack.rs), keyed by the id, as
 *   Notion's sign-in is kept. A webhook URL is a secret, since whoever holds it can post to the channel, so once it is
 *   handed over no page can read it back: the page posts by naming the id.
 *
 * Both are this device's only. Nothing here syncs, so a second phone has no channels until they are added there, and
 * an organization's news is posted from each device that has a channel set for it (news.ts).
 *
 * Every native call goes through the plugin's host (plugins/host.ts), so the four commands and three keys in the
 * manifest are all it can reach. Native generation 25.
 */

const CHANNELS_KEY = 'glyph-slack-channels';

export interface Channel {
  /** Made here when the channel is added: the key its webhook is kept under natively. */
  id: string;
  /** The person's name for it: "#launch". */
  name: string;
}

// ---- availability ------------------------------------------------------------------------------

/** Whether this binary can post to Slack at all: the app, with the native generation the manifest asks for. */
export async function slackAvailable(): Promise<boolean> {
  return isTauri() && (await host.nativeReady());
}

let ready = false;
void slackAvailable().then((yes) => (ready = yes));

/** The last answer of `slackAvailable`, for code that cannot wait (whether a row on the More sheet shows). */
export function slackReadyNow(): boolean {
  return ready;
}

/** For the tests: as though the binary had answered. */
export function setSlackReady(yes: boolean): void {
  ready = yes;
}

// ---- the webhook's shape -----------------------------------------------------------------------

/** The two kinds Slack hands out: an app's incoming webhook, and a Workflow Builder trigger. Rust holds to the same. */
const WEBHOOK = /^https:\/\/hooks\.slack\.com\/(?:services|workflows)\/[A-Za-z0-9_/-]+$/;

/**
 * What is wrong with a pasted webhook, in a sentence, or null when it is one Slack would hand out. Checked here so the
 * pane can say so as it is typed; Rust checks again before it keeps one and before it posts (slack.rs `allowed_webhook`).
 */
export function webhookProblem(pasted: string): string | null {
  const url = pasted.trim();
  if (!url) return 'Paste the webhook Slack gave you.';
  if (/^http:\/\//i.test(url)) return 'A Slack webhook starts with https://, never http://.';
  if (!url.startsWith('https://hooks.slack.com/')) return 'That isn’t a Slack webhook. It starts with https://hooks.slack.com/services/.';
  if (url.includes('..') || !WEBHOOK.test(url)) return 'That isn’t a Slack incoming webhook. It starts with https://hooks.slack.com/services/ and has no spaces or ? in it.';
  return null;
}

/** A channel's name as kept: trimmed, one space between words, at most 80 characters. */
export function channelName(typed: string): string {
  return typed.trim().replace(/\s+/g, ' ').slice(0, 80);
}

/** What is wrong with a name for a new or renamed channel, or null. `except` is the channel being renamed. */
export function nameProblem(typed: string, except: string | null = null): string | null {
  const name = channelName(typed);
  if (!name) return 'Give the channel a name, like #launch.';
  const taken = channels().some((c) => c.id !== except && c.name.toLowerCase() === name.toLowerCase());
  return taken ? `There is a channel called ${name} already.` : null;
}

// ---- the list ----------------------------------------------------------------------------------

function isChannel(value: unknown): value is Channel {
  if (!value || typeof value !== 'object') return false;
  const { id, name } = value as Partial<Channel>;
  return typeof id === 'string' && Boolean(id) && typeof name === 'string' && Boolean(name);
}

/** The channels on this device, in the order they were added. */
export function channels(): Channel[] {
  const kept = host.storage.get<unknown>(CHANNELS_KEY, []);
  return Array.isArray(kept) ? kept.filter(isChannel) : [];
}

export function channelById(id: string | null | undefined): Channel | null {
  return id ? (channels().find((c) => c.id === id) ?? null) : null;
}

function keep(list: readonly Channel[]): void {
  if (list.length) host.storage.set(CHANNELS_KEY, list);
  else host.storage.remove(CHANNELS_KEY);
}

/** Sixteen random bytes as hex: the id a channel's webhook is kept under (slack.rs takes letters, digits and dashes). */
function newId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * A channel added: its webhook handed to Rust first, so a channel is never listed without the way to post to it, then
 * its name kept here. Refused, in a sentence, for a name or a webhook that won't do.
 */
export async function addChannel(typedName: string, pastedUrl: string): Promise<Channel> {
  const problem = nameProblem(typedName) ?? webhookProblem(pastedUrl);
  if (problem) throw new Error(problem);
  const channel: Channel = { id: newId(), name: channelName(typedName) };
  await host.invoke('slack_save_channel', { id: channel.id, url: pastedUrl.trim() });
  keep([...channels(), channel]);
  return channel;
}

/** A new name for a channel; its webhook stays as it was. */
export function renameChannel(id: string, typedName: string): void {
  const problem = nameProblem(typedName, id);
  if (problem) throw new Error(problem);
  keep(channels().map((c) => (c.id === id ? { ...c, name: channelName(typedName) } : c)));
}

/**
 * A channel forgotten: its webhook gone from Rust, then its name from here. An organization whose news went there is
 * set to nowhere by the reader (news.ts `newsChannelFor`), which finds no channel by that id.
 */
export async function forgetChannel(id: string): Promise<void> {
  await host.invoke('slack_forget_channel', { id });
  keep(channels().filter((c) => c.id !== id));
}

/** The ids Rust has a webhook for: a channel listed here without one (a hand-cleared file) can't post, and the pane says so. */
export async function keptWebhooks(): Promise<string[]> {
  return host.invoke<string[]>('slack_channels').catch(() => []);
}

/** Posts `text`, as Slack's mrkdwn, to a channel. Rejects with Rust's sentence for why not. */
export async function postToChannel(channel: Channel, text: string): Promise<void> {
  await host.invoke('slack_post', { id: channel.id, payload: { text } });
}

/** The channels, kept current: read again whenever the plugin writes its storage. */
export function useChannels(): Channel[] {
  return useSyncExternalStore(onPluginStorage, channelsShared, channelsShared);
}

/** One array for as long as the stored text is the same, so useSyncExternalStore sees no change when there is none. */
let shared: { from: unknown; list: Channel[] } | null = null;
const NONE: readonly Channel[] = [];
function channelsShared(): Channel[] {
  // The same fallback every time, so nothing kept reads as no change.
  const kept = host.storage.get<unknown>(CHANNELS_KEY, NONE);
  if (shared === null || shared.from !== kept) shared = { from: kept, list: channels() };
  return shared.list;
}
