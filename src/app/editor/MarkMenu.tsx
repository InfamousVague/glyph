import { CircleCheck, ExternalLink, PencilLine, RefreshCw, RotateCcw, Unlink } from '@glacier/icons';
import { useEffect, useState } from 'react';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { agoText, markActions, onMarkDetails, openMarked, peekMarkDetails, wantMarkDetails, type MarkAction } from '../core/markDetails.ts';
import { capitalise } from '../core/text.ts';
import { useRedraw } from '../core/useRedraw.ts';
import type { MenuIcon } from './MenuBand.tsx';
import { Sheet } from './Sheet.tsx';
import styles from './MarkMenu.module.css';

/**
 * The drawer a linked line's row opens (editor/linkedRows.ts).
 *
 * Matt: "tap on the notion pills to show a few options like opening the ticket
 * in notion or un linking or updating etc. … make the options typography and
 * iconography heavy so they fit the theme on all context menus." It first
 * split the note open at the line; then "the notion opener should open in a
 * drawer instead of rendering in place". So it rises from the bottom over the
 * dimmed note, in the note settings' sheet: the task in the note's own type
 * (its title set large, its stage and status above, its properties in two
 * quiet columns) and then the things to do, each a full-width row with a drawn
 * icon and a word in display weight:
 *
 * - Open in Notion
 * - Mark done in Notion, or Reopen (the board's own first done or to-do status)
 * - Use these words as its title, when the item's words and the task's title differ
 * - Refresh
 * - Unlink: the link comes off the line and the words stay
 *
 * Opening it reads the task fresh. It closes on a tap on the dimmed note or the
 * back gesture; an action that changes the note closes it.
 */

export interface MarkMenuProps {
  name: string;
  url: string;
  words: string;
  say(message: string): void;
  close(): void;
  unlink(): void;
}

const ICONS: Record<MarkAction['icon'], MenuIcon> = {
  done: CircleCheck,
  reopen: RotateCcw,
  rename: PencilLine,
};

export function MarkMenu({ name, url, words, say, close, unlink }: MarkMenuProps) {
  const redraw = useRedraw();
  const [busy, setBusy] = useState<string | null>(null);
  const title = capitalise(name);

  useEffect(() => onMarkDetails(redraw), [redraw]);
  useEffect(() => wantMarkDetails(name, url, true), [name, url]);

  const entry = peekMarkDetails(name, url);
  const details = entry?.state === 'ready' ? entry.details : null;
  const reading = entry?.state === 'loading' || (entry?.state === 'ready' && entry.loading);
  const fields = details ? details.fields.filter((field) => !(details.status && /status/i.test(field.label))) : [];
  const actions = markActions(name, url, words);

  const act = async (id: string, run: () => Promise<string | void> | void, busyWords?: string) => {
    fireNativeHaptic('selection');
    if (busyWords) setBusy(id);
    try {
      const said = await run();
      if (said) {
        fireNativeHaptic('success');
        say(said);
      }
    } catch (failure) {
      fireNativeHaptic('error');
      say(failureText(failure));
    } finally {
      setBusy(null);
    }
  };

  // The drawer takes a pull on its handle: down far enough and it closes (editor/sheetDrag.ts).
  return (
    <Sheet label={`${title} ${details?.title ?? 'link'}`} onClose={close} className={styles.drawer}>
      <div className={styles.head}>
        <p className={styles.eyebrow}>
          <span>{title}</span>
          {details?.gone ? <span className={styles.status}>In trash</span> : null}
          {details?.status && !details.gone ? (
            <span className={styles.status} data-stage={details.status.stage}>
              <span className={styles.stage} aria-hidden="true" />
              {details.status.label}
            </span>
          ) : null}
          {details?.brief.map((fact) => (
            <span key={fact} className={styles.fact}>
              {fact}
            </span>
          ))}
        </p>
        <p className={styles.title}>{details?.title || words || 'Linked'}</p>
        {fields.length ? (
          <dl className={styles.fields}>
            {fields.map((field) => (
              <div key={field.label} className={styles.field}>
                <dt>{field.label}</dt>
                <dd>{field.value}</dd>
              </div>
            ))}
          </dl>
        ) : null}
        <p className={styles.quiet}>
          {entry?.state === 'failed'
            ? entry.message
            : details
              ? `${details.editedAt ? `Changed ${agoText(details.editedAt)} · ` : ''}${reading ? 'Reading…' : `Read ${agoText(details.readAt)}`}`
              : reading
                ? `Reading from ${title}…`
                : `Ghost.md can’t read ${title} right now.`}
        </p>
      </div>

      <div className={styles.options}>
        <Row
          id="open"
          busy={busy}
          icon={ExternalLink}
          label={`Open in ${title}`}
          onPress={() =>
            void act('open', async () => {
              close();
              await openMarked(name, details?.url || url);
            })
          }
        />
        {actions.map((action) => (
          <Row
            key={action.id}
            id={action.id}
            busy={busy}
            icon={ICONS[action.icon]}
            label={action.label}
            busyLabel={action.busyLabel}
            onPress={() => void act(action.id, action.run, action.busyLabel)}
          />
        ))}
        <Row
          id="refresh"
          busy={busy}
          icon={RefreshCw}
          label={reading ? 'Reading…' : 'Refresh'}
          onPress={() =>
            void act('refresh', () => {
              wantMarkDetails(name, url, true);
              redraw();
            })
          }
        />
        <Row
          id="unlink"
          busy={busy}
          icon={Unlink}
          label="Unlink"
          quiet
          onPress={() =>
            void act('unlink', async () => {
              unlink();
              return 'Unlinked. The words stay.';
            })
          }
        />
      </div>
    </Sheet>
  );
}

/**
 * One of the drawer's rows: a drawn icon and a word in display weight, the busy words while its action runs, and every
 * row still while any runs. At the top level rather than inside the drawer, so a redraw keeps the row a person is
 * pressing rather than drawing a new one under the finger.
 */
function Row({
  id,
  busy,
  icon: Icon,
  label,
  busyLabel,
  onPress,
  quiet = false,
}: {
  id: string;
  /** The row whose action is running, or null. */
  busy: string | null;
  icon: MenuIcon;
  label: string;
  busyLabel?: string;
  onPress: () => void;
  quiet?: boolean;
}) {
  return (
    <button type="button" className={styles.option} data-quiet={quiet || undefined} disabled={busy !== null} onClick={onPress}>
      <span className={styles.icon} aria-hidden="true">
        <Icon size={18} strokeWidth={2.2} />
      </span>
      <span className={styles.label}>{busy === id && busyLabel ? busyLabel : label}</span>
    </button>
  );
}
