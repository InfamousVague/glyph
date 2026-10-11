import { createHost } from '../host.ts';
import type { PluginManifest } from '../types.ts';

export const manifest: PluginManifest = {
  id: 'slack',
  name: 'Slack',
  description: 'Posts a note, or a meeting’s summary, to a Slack channel when you say so, and an organization’s news to its channel.',
  version: '1.0.0',
  author: 'Ghost.md',
  // Off until switched on: it sends words off the phone, and only ever when the person has set a channel up for it.
  standard: false,
  permissions: [
    { kind: 'notes', why: 'Reads the note you post, or its summary, to make the message. Nothing in the note changes.' },
    { kind: 'network', why: 'Posts to the channels you add, straight from this device. Only what you choose to post goes, and an organization’s news where you set a channel for it.' },
    { kind: 'native', why: 'Keeps each channel’s webhook inside the app, where no page can read it back, and posts with it.' },
  ],
  hosts: ['hooks.slack.com'],
  native: { generation: 25, commands: ['slack_channels', 'slack_save_channel', 'slack_forget_channel', 'slack_post'] },
  storage: ['glyph-slack-channels', 'glyph-slack-news', 'glyph-slack-posted'],
};

export const host = createHost(manifest);
