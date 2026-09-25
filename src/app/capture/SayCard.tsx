import { Bot, ListTree, Send } from '@glacier/icons';
import type { Tip } from '../plugins/types.ts';
import type { Starters } from './tips.ts';
import styles from './SayCard.module.css';

/**
 * Things to say: the card the recorder shows while the microphone waits for the first word (Matt: "when I open the
 * AI page, I should see a list of suggested prompts / commands / etc but don't see that card anymore").
 *
 * Three short groups, one line each way of saying it (capture/tips.ts `starters`): how to shape the note as it is
 * said, where to send it, and what to ask the AI to do with it. The one-line tips that come in a pause teach the same
 * things one at a time once talking has begun; this is the whole of it at once, for the moment before, when a person
 * is deciding what to say. It goes the moment words arrive, and it takes no taps: the recorder is listening, and
 * saying a line is the way to use it.
 */
export function SayCard({ starters }: { starters: Starters }) {
  const groups: { id: keyof Starters; heading: string; Icon: typeof Bot; tips: Tip[] }[] = [
    { id: 'shape', heading: 'To shape it', Icon: ListTree, tips: starters.shape },
    { id: 'send', heading: 'To send it somewhere', Icon: Send, tips: starters.send },
    { id: 'ask', heading: 'To ask the AI', Icon: Bot, tips: starters.ask },
  ];
  return (
    <section className={styles.card} aria-label="Things to say">
      <p className={styles.title}>Things to say</p>
      {groups
        .filter((group) => group.tips.length)
        .map((group) => (
          <div key={group.id} className={styles.group}>
            <p className={styles.heading}>
              <group.Icon size={13} strokeWidth={2.2} aria-hidden="true" />
              {group.heading}
            </p>
            <ul className={styles.lines}>
              {group.tips.map((tip) => (
                <li key={tip.say} className={styles.line}>
                  <strong className={styles.say}>“{tip.say}”</strong> <span className={styles.does}>{tip.does}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
    </section>
  );
}
