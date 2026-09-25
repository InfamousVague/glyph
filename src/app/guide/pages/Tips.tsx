import { Tips as TipsArt } from '../../art/Shapes.tsx';
import { ASK, COMMAND } from '../phrases.ts';
import { Step } from './parts.tsx';
import styles from '../Guide.module.css';

/**
 * The last page: how to talk so the cues are heard. Every habit here is one the speech rules keep
 * (capture/markdown.ts) - a cue at the start of a sentence, a cue said on its own, a pause for a paragraph - and
 * guide/guide.test.ts holds the rules to them through the spoken examples in guide/phrases.ts. The cues' own words
 * are on the marks page, beside each mark (guide/marks.ts `say`).
 *
 * One habit is not a cue: "Hey Ghost" first, for a command or an ask. Its two examples are guide/phrases.ts
 * `COMMAND` and `ASK`, which guide/guide.test.ts runs through the recorder's own readers (capture/command.ts,
 * ai/instruction.ts), so the page never teaches a command the recorder would write down as words.
 */
export function Tips() {
  return (
    <>
      <TipsArt className={styles.art} />
      <h1 className={styles.title}>A few habits.</h1>
      <ol className={styles.steps}>
        <Step title="Pause before a cue word." note="A short pause before “heading” or “bullet point” starts a new sentence. That’s where Ghost.md listens for cues." />
        <Step title="Or say the cue on its own." note="“Bullet point.” Pause. “Oat milk.” The cue waits for the next thing you say." />
        <Step title="Stop for two seconds to start a paragraph." note="You don’t have to say it. The pause does it." />
        <Step title="Talk normally." note="Ghost.md picks lists and to-dos out of normal speech. The cues change how your words are laid out, never the words." />
        <Step
          title="Start with “Hey Ghost” to give a command."
          note={`“${COMMAND.say}” puts it in your ${COMMAND.note} note, and a card shows what will change before anything does. Said into a note’s own mic, “${ASK.say}” asks the AI.`}
        />
        <Step title="Fix it after." note="A voice note lands at the top of your notes. Open it to fix anything. The markdown is all there." />
      </ol>
    </>
  );
}
