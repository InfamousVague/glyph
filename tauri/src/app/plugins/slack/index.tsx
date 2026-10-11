import { Hash } from '@glacier/icons';
import { keptText } from '../../ai/summaryKeep.ts';
import { summarySection } from '../../ai/summaryText.ts';
import { failureText } from '../../core/failure.ts';
import { fireNativeHaptic } from '../../core/haptics.ts';
import type { GlyphPlugin, NoteAction, NoteEditing } from '../types.ts';
import { channelById, channels, postToChannel, slackAvailable, slackReadyNow } from './channels.ts';
import { manifest } from './manifest.ts';
import { SlackMark } from './marks.tsx';
import { hasWords, noteMessage, summaryMessage } from './mrkdwn.ts';
import { forwardNews } from './news.ts';
import { SlackPane } from './SlackPane.tsx';

/**
 * The Slack plugin, built in and off until switched on: a note, or a meeting's summary, posted to a Slack channel when
 * the person chooses, and an organization's news to the channel chosen for it.
 *
 * Matt: "include #6 as a plugin as well as #5", where #5 was "Slack: post a meeting's summary, or a note, to a channel
 * when you choose to. It pairs well with organizations: a team's news could go to its channel too. Sending is always
 * your choice, so the encryption holds." Posting is the one moment words leave the encryption, so it is always a press:
 * nothing of a note goes unless "Post to Slack" is pressed on it, and an organization's news only once a channel is set
 * for it. The channels are incoming webhooks, pasted in the plugin's page, kept on this device (channels.ts).
 *
 * - On a note's More sheet, once a channel is added: "Post to Slack", the whole note as a message (mrkdwn.ts), and
 *   "Post the summary to Slack" on a note with a meeting's summary, that section alone. With more than one channel the
 *   row opens them to choose from.
 * - After each pass of the feed: an organization's new news to its channel (news.ts).
 * - In Settings: the channels, a test message for each, and where each organization's news goes (SlackPane.tsx).
 */

/** The channels as the More sheet's rows to choose from. */
const channelChoices = () => channels().map((c) => ({ id: c.id, label: c.name }));

/** "#launch", or how many to choose from. */
function where(): string {
  const list = channels();
  return list.length === 1 ? `to ${list[0]!.name}` : `to one of ${list.length} channels`;
}

/**
 * Posts what `message` makes of the note on screen to the channel chosen, then says so on the note, or says why not
 * in Slack's words (Rust turns its answer into a sentence, src-tauri/src/slack.rs).
 */
async function post(editing: NoteEditing, choice: string | undefined, message: (body: string) => string | null): Promise<void> {
  const list = channels();
  const channel = channelById(choice) ?? (list.length === 1 ? list[0]! : null);
  if (!channel) {
    editing.say('That Slack channel isn’t on this device any more.');
    return;
  }
  const text = message(editing.body());
  if (!text) {
    editing.say('There is no summary in this note to post.');
    return;
  }
  try {
    await postToChannel(channel, text);
    fireNativeHaptic('success');
    editing.say(`Posted to ${channel.name}.`);
  } catch (failure) {
    editing.say(`Not posted to ${channel.name}. ${failureText(failure)}`);
  }
}

/** The meeting's summary in the note as it stands, or null (ai/summaryText.ts, closed by what the app kept). */
const summaryOf = (noteId: string, body: string) => summarySection(body, keptText(noteId));

export const postNote: NoteAction = {
  id: 'slack-post-note',
  label: 'Post to Slack',
  icon: SlackMark,
  visible: () => slackReadyNow() && channels().length > 0,
  hint: (_noteId, body) => (hasWords(body) ? `The whole note goes ${where()}, as it reads now.` : 'Nothing to post yet.'),
  enabled: (_noteId, body) => hasWords(body),
  choices: channelChoices,
  run: (editing, choice) => post(editing, choice, noteMessage),
};

export const postSummary: NoteAction = {
  id: 'slack-post-summary',
  label: 'Post the summary to Slack',
  icon: SlackMark,
  visible: (noteId, body) => slackReadyNow() && channels().length > 0 && summaryOf(noteId, body) !== null,
  hint: () => `The meeting’s summary goes ${where()}, and nothing else of the note.`,
  enabled: () => true,
  choices: channelChoices,
  run: (editing, choice) =>
    post(editing, choice, (body) => {
      const section = summaryOf(editing.noteId, body);
      return section ? summaryMessage(body, section.text) : null;
    }),
};

export const slackPlugin: GlyphPlugin = {
  manifest,
  icon: Hash,
  settings: {
    Pane: SlackPane,
    hue: 'graphite',
    summary: () => {
      const count = channels().length;
      return count ? `${count} ${count === 1 ? 'channel' : 'channels'}` : 'Channels to post to';
    },
    // What Settings' search finds on the page (docs/DESIGN.md §138): its cards, by their titles. Drawn in the app only.
    settings: [
      { name: 'Channels', words: 'webhook test message organizations news' },
      { name: 'Add a channel', words: 'incoming webhook hooks.slack.com' },
    ],
  },
  noteActions: [postNote, postSummary],
  async newRows(before, rows) {
    if (before <= 0 || !channels().length) return;
    if (await slackAvailable()) await forwardNews(before, rows);
  },
};
