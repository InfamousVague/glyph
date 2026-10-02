import { BookOpen } from '@glacier/icons';
import { Tips as LidArt } from '../../art/Shapes.tsx';
import styles from '../Guide.module.css';

/**
 * The last page. The walkthrough has said what Ghost.md is, how it looks and which model it runs, and hands over:
 * everything else - the marks, the words you can say, boards, canvases, journals - is the Academy's (academy/), short
 * lessons inside the app, so this page offers it and otherwise gets out of the way. Start, in the dock, closes the
 * guide (Matt: "instead show the option to learn about markdown and other stuff, take the ghost.md academy or
 * 'start'"). The habits page that was here, and the marks page before it, taught the same things as a list to read;
 * the Academy teaches them by doing, and the home page offers it again to anyone who started writing first.
 */
export function Start({ onAcademy }: { onAcademy: () => void }) {
  return (
    <>
      <LidArt className={styles.art} />
      <h1 className={styles.title}>Learn it, or just start.</h1>
      <p className={styles.lead}>
        The marks, the words you can say, boards, canvases and the rest are in the Ghost.md Academy: short lessons inside the app, a few minutes
        each. Take it now, or start writing and find it on the home page any time.
      </p>
      <button type="button" className={`app-pill ${styles.learn}`} onClick={onAcademy}>
        <BookOpen size={18} strokeWidth={2.2} aria-hidden="true" />
        Take the Ghost.md Academy
      </button>
    </>
  );
}
