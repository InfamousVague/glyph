import { MarksTable } from '../MarksTable.tsx';
import styles from '../Guide.module.css';

/** Every mark a note can carry, what to type and how it reads, drawn by the note's own editor (guide/MarksTable.tsx). */
export function Marks() {
  return (
    <>
      <h1 className={styles.title}>Every mark, side by side.</h1>
      <p className={styles.lead}>
        What you type is on the left, how the note reads it on the right. The marks stay on the page as you write, so you can always see what a line is doing.
      </p>
      <MarksTable />
    </>
  );
}
