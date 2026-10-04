import { useEffect, useState } from 'react';
import { Hash } from '@glacier/icons';
import { failureText } from '../../core/failure.ts';
import { useOrgs } from '../../core/orgs/orgs.ts';
import { isTauri } from '../../core/tauri.ts';
import { Pick, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsEmpty, SettingsFootnote } from '../../settings/kit/settingsKit.tsx';
import { addChannel, forgetChannel, keptWebhooks, nameProblem, postToChannel, renameChannel, slackAvailable, useChannels, webhookProblem, type Channel } from './channels.ts';
import { newsChannelFor, setNewsChannel } from './news.ts';
import styles from './SlackPane.module.css';

/**
 * The Slack plugin's page in Settings: the channels on this device, each with a test message, a new name and a way to
 * forget it; a channel added by name and pasted webhook; and, for each organization the person is a member of, the
 * channel its news goes to, if any.
 *
 * Everything here is this device's: the webhooks are kept inside the app (src-tauri/src/slack.rs) and nothing syncs,
 * which the page says, so a person with two phones is not surprised that the second has no channels, or that both post
 * an organization's news where both have it set. What a note posts is chosen on the note, from its More sheet.
 */

/** What a test post says in the channel. */
const TEST_TEXT = 'A test from Ghost.md. What you post from this device will land here.';

/** The fields are plain inputs, not the kit's: this page is reached through the plugin registry, which every test loads. */
function Field(props: { label: string; value: string; onChange: (value: string) => void; placeholder: string; secret?: boolean }) {
  return (
    <input
      className={styles.field}
      type={props.secret ? 'password' : 'text'}
      autoCapitalize="off"
      autoCorrect="off"
      spellCheck={false}
      autoComplete="off"
      aria-label={props.label}
      placeholder={props.placeholder}
      value={props.value}
      onChange={(event) => props.onChange(event.target.value)}
    />
  );
}

export function SlackPane() {
  const list = useChannels();
  const orgs = useOrgs().list.filter((org) => org.state === 'member');
  const [available, setAvailable] = useState<boolean | null>(null);
  /** The ids Rust holds a webhook for, once asked; a listed channel without one cannot post. */
  const [kept, setKept] = useState<string[] | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [renaming, setRenaming] = useState<{ id: string; name: string } | null>(null);
  /** The organization whose channel is being chosen. */
  const [choosing, setChoosing] = useState<string | null>(null);
  // News choices live in the plugin's storage; this re-reads them after a change.
  const [, setNewsTurn] = useState(0);

  useEffect(() => {
    void slackAvailable().then(setAvailable);
  }, []);

  useEffect(() => {
    if (!available) return;
    let live = true;
    void keptWebhooks().then((ids) => live && setKept(ids));
    return () => {
      live = false;
    };
  }, [available, list]);

  if (!isTauri()) {
    return <SettingsEmpty icon={<Hash size={22} />} title="Slack works in the app." body="Add channels from Ghost.md on your phone or Mac, where each webhook is kept inside the app and posts go straight from the device." />;
  }
  if (available === false) {
    return <SettingsEmpty icon={<Hash size={22} />} title="Slack needs the newest Ghost.md." body="Install the latest version from Settings › Updates, then come back here to add a channel." />;
  }

  /** Runs one thing at a time, and says how it went at the top of the page. */
  const act = async (what: string, run: () => Promise<string>) => {
    setBusy(what);
    setSaid(null);
    try {
      setSaid(await run());
    } catch (failure) {
      setSaid(failureText(failure));
    } finally {
      setBusy(null);
    }
  };

  const typedProblem = name.trim() || url.trim() ? (nameProblem(name) ?? webhookProblem(url)) : null;

  const add = () =>
    act('add', async () => {
      const channel = await addChannel(name, url);
      setName('');
      setUrl('');
      return `Added ${channel.name}. Send it a test to be sure it posts.`;
    });

  const test = (channel: Channel) =>
    act(channel.id, async () => {
      await postToChannel(channel, TEST_TEXT);
      return `Sent a test to ${channel.name}.`;
    });

  const forget = (channel: Channel) =>
    act(channel.id, async () => {
      await forgetChannel(channel.id);
      return `Forgot ${channel.name}. Its webhook is gone from this device; it still works in Slack until it is removed there.`;
    });

  const rename = () => {
    if (!renaming) return;
    try {
      renameChannel(renaming.id, renaming.name);
      setRenaming(null);
      setSaid(null);
    } catch (failure) {
      setSaid(failureText(failure));
    }
  };

  const channelRow = (channel: Channel) => {
    if (renaming?.id === channel.id) {
      return (
        <SettingRow
          key={channel.id}
          icon={<Hash size={16} />}
          label={`Rename ${channel.name}`}
          layout="stacked"
          control={
            <div className={styles.form}>
              <Field label="Channel name" value={renaming.name} onChange={(next) => setRenaming({ id: channel.id, name: next })} placeholder="#launch" />
              <span className={styles.actions}>
                <RowAction onPress={() => setRenaming(null)}>Cancel</RowAction>
                <RowAction onPress={rename} disabled={nameProblem(renaming.name, channel.id) !== null}>
                  Keep it
                </RowAction>
              </span>
            </div>
          }
        />
      );
    }
    const missing = kept !== null && !kept.includes(channel.id);
    return (
      <SettingRow
        key={channel.id}
        icon={<Hash size={16} />}
        label={channel.name}
        hint={missing ? 'Its webhook isn’t on this device any more. Forget it and add it again.' : 'Posts from this device go here.'}
        control={
          <span className={styles.actions}>
            <RowAction onPress={() => void test(channel)} disabled={busy !== null || missing}>
              {busy === channel.id ? 'Sending…' : 'Test'}
            </RowAction>
            <RowAction onPress={() => setRenaming({ id: channel.id, name: channel.name })} disabled={busy !== null}>
              Rename
            </RowAction>
            <RowAction onPress={() => void forget(channel)} disabled={busy !== null}>
              Forget
            </RowAction>
          </span>
        }
      />
    );
  };

  const choose = (orgId: string, channelId: string | null) => {
    setNewsChannel(orgId, channelId);
    setChoosing(null);
    setNewsTurn((n) => n + 1);
  };

  return (
    <>
      {said ? <SettingsCallout>{said}</SettingsCallout> : null}

      <PaneSection
        title="Channels"
        description="Each is a Slack channel’s incoming webhook, under a name you give it. Kept on this device: not synced, and once kept no page can read the webhook back."
      >
        {list.length ? list.map(channelRow) : <SettingRow label="No channels yet" hint="Add one below: a name, and the webhook Slack gives you." />}
      </PaneSection>

      <PaneSection title="Add a channel" description="In Slack, add an incoming webhook to the channel (Apps › Incoming WebHooks, or a workflow’s webhook), copy its URL, and paste it here.">
        <SettingRow
          label="A name and its webhook"
          hint={typedProblem ?? 'The name is yours, for the rows you choose from. Slack decides the channel by the webhook.'}
          layout="stacked"
          control={
            <div className={styles.form}>
              <Field label="Channel name" value={name} onChange={setName} placeholder="#launch" />
              <Field label="Webhook" value={url} onChange={setUrl} placeholder="https://hooks.slack.com/services/…" secret />
              <RowAction onPress={() => void add()} disabled={busy !== null || !name.trim() || !url.trim() || typedProblem !== null}>
                {busy === 'add' ? 'Adding…' : 'Add it'}
              </RowAction>
            </div>
          }
        />
      </PaneSection>

      {orgs.length && list.length ? (
        <PaneSection
          title="Organizations’ news"
          description="An organization’s news (who joined, left or changed role, and its new name) can go to a channel as it arrives. Set here, on this device only: each device with a channel set posts the news, so set it on one."
        >
          {orgs.flatMap((org) => {
            const to = newsChannelFor(org.id);
            const open = choosing === org.id;
            const row = (
              <SettingRow
                key={org.id}
                label={org.name}
                hint={to ? `Its news goes to ${to.name}.` : 'Its news isn’t posted.'}
                control={<RowAction onPress={() => setChoosing(open ? null : org.id)}>{open ? 'Done' : 'Change'}</RowAction>}
              />
            );
            if (!open) return [row];
            return [
              row,
              <SettingRow key={`${org.id}-none`} label="Nowhere" control={<Pick checked={to === null} label={`Don’t post ${org.name}’s news`} onPress={() => choose(org.id, null)} />} />,
              ...list.map((channel) => (
                <SettingRow
                  key={`${org.id}-${channel.id}`}
                  icon={<Hash size={16} />}
                  label={channel.name}
                  control={<Pick checked={to?.id === channel.id} label={`Post ${org.name}’s news to ${channel.name}`} onPress={() => choose(org.id, channel.id)} />}
                />
              )),
            ];
          })}
        </PaneSection>
      ) : null}

      <SettingsFootnote>
        Nothing goes to Slack unless you post it from a note, or set an organization’s news to go. What is posted leaves Ghost.md’s encryption: Slack, and everyone in the channel, can read it.
      </SettingsFootnote>
    </>
  );
}
