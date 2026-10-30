import { useEffect, useRef, useState, type FormEvent } from 'react';
import { failureText } from '../app/core/failure.ts';
import { INSTALL_URL } from './places.ts';
import { Rendered } from './Rendered.tsx';
import { introOf, payloadOf, problemsOf, sendAnswer, standingOf, type Files, type FormDef, type FormField, type Standing, type Values } from './form.ts';
import readerStyles from './Reader.module.css';
import styles from './FormRead.module.css';

/**
 * A form from a share link, filled in (form.ts says what it is and how what is sent is sealed). The page asks the
 * service whether the form takes answers and whom to seal them to, draws its introduction and its fields, and on Send
 * seals the answers here and sends only the seal; then thanks the visitor in the owner's words. A form paused or
 * closed says so in place of its fields, and one taken down reads as nothing at all. No account, no sign-in.
 *
 * A field a person never sees (`website`, off the page and out of the tab order) is a bot's to fill: it is sent as it
 * is, and the service keeps nothing from one that filled it.
 */

type Phase = { kind: 'asking' } | { kind: 'failed'; message: string } | { kind: 'ready'; standing: Standing } | { kind: 'sent' };

export function FormRead({ id, title, body, def, fetcher }: { id: string; title: string; body: string; def: FormDef; fetcher?: typeof fetch }) {
  const [phase, setPhase] = useState<Phase>({ kind: 'asking' });
  const [values, setValues] = useState<Values>({});
  const [files, setFiles] = useState<Files>({});
  const [shown, setShown] = useState<Record<string, string>>({});
  const [sending, setSending] = useState(false);
  const [refusal, setRefusal] = useState<string | null>(null);
  const opened = useRef(Date.now());
  const trap = useRef<HTMLInputElement>(null);
  // What the note says around its fence, its heading taken off: the title is drawn above it.
  const intro = introOf(body).replace(/^#\s.*\n?/, '').trim();

  useEffect(() => {
    standingOf(id, fetcher).then(
      (standing) => {
        opened.current = Date.now();
        setPhase({ kind: 'ready', standing });
      },
      (failure: unknown) => setPhase({ kind: 'failed', message: failureText(failure) }),
    );
  }, [id, fetcher]);

  const set = (label: string, value: string) => {
    setValues((now) => ({ ...now, [label]: value }));
    if (shown[label]) setShown((now) => ({ ...now, [label]: '' }));
  };

  const send = async (event: FormEvent) => {
    event.preventDefault();
    if (phase.kind !== 'ready' || phase.standing.state !== 'open' || sending) return;
    const found = problemsOf(def, values, files);
    setShown(found);
    if (Object.keys(found).length > 0) {
      document.getElementById(`field-${Object.keys(found)[0]!.replace(/\W+/g, '-')}`)?.focus();
      return;
    }
    setSending(true);
    setRefusal(null);
    try {
      await sendAnswer(id, phase.standing, await payloadOf(def, values, files), { hp: trap.current?.value ?? '', openedAt: opened.current, fetcher });
      setPhase({ kind: 'sent' });
      window.scrollTo({ top: 0 });
    } catch (failure) {
      setRefusal(failureText(failure));
    } finally {
      setSending(false);
    }
  };

  return (
    <>
      <header className={readerStyles.banner}>
        <div className={readerStyles.bannerInner}>
          <span className={readerStyles.brand}>Ghost.md</span>
          <span className={readerStyles.pitch}>
            <span className={readerStyles.pitchMore}>A form, sealed so only its owner can read your answers. </span>
            <a className={readerStyles.getApp} href={INSTALL_URL}>
              Get the app
            </a>
          </span>
        </div>
      </header>
      <main className={`${readerStyles.page} ${styles.page}`} data-form="">
        {phase.kind === 'sent' ? (
          <section className={styles.thanks} aria-live="polite">
            <h1 className={readerStyles.title}>Sent</h1>
            <p>{def.thanks ?? 'Thank you. Your answers are on their way to the form’s owner.'}</p>
            <p className={readerStyles.quiet}>Sealed in this browser before it left: only the owner’s Ghost.md can open it.</p>
          </section>
        ) : (
          <>
            <h1 className={readerStyles.title}>{title}</h1>
            {intro ? (
              <div className={styles.intro}>
                <Rendered body={intro} />
              </div>
            ) : null}
            {phase.kind === 'asking' ? <p className={readerStyles.quiet}>Opening the form…</p> : null}
            {phase.kind === 'failed' ? <p className={styles.problem}>{phase.message}</p> : null}
            {phase.kind === 'ready' && phase.standing.state === 'gone' ? <p className={styles.closed}>This form was taken down. It takes no answers.</p> : null}
            {phase.kind === 'ready' && phase.standing.state === 'closed' ? <p className={styles.closed}>This form is closed. It takes no more answers.</p> : null}
            {phase.kind === 'ready' && phase.standing.state === 'paused' ? <p className={styles.closed}>This form is paused: it isn’t taking answers just now. Try again later.</p> : null}
            {phase.kind === 'ready' && phase.standing.state === 'open' ? (
              <form className={styles.form} onSubmit={(event) => void send(event)} noValidate>
                {def.fields.map((field) => (
                  <Field key={field.label} field={field} value={values[field.label] ?? ''} file={files[field.label] ?? null} problem={shown[field.label] || null} onValue={(v) => set(field.label, v)} onFile={(f) => setFiles((now) => ({ ...now, [field.label]: f }))} />
                ))}
                {/* For bots only: off the page, out of the tab order, and named as a site field is. */}
                <div className={styles.trap} aria-hidden="true">
                  <label>
                    Website
                    <input ref={trap} type="text" name="website" tabIndex={-1} autoComplete="off" defaultValue="" />
                  </label>
                </div>
                {refusal ? <p className={styles.problem} role="alert">{refusal}</p> : null}
                <div className={styles.sendRow}>
                  <button type="submit" className={styles.send} disabled={sending}>
                    {sending ? 'Sending…' : def.button ?? 'Send'}
                  </button>
                  <span className={readerStyles.quiet}>Sealed in your browser. No account needed.</span>
                </div>
              </form>
            ) : null}
          </>
        )}
      </main>
    </>
  );
}

function Field({ field, value, file, problem, onValue, onFile }: { field: FormField; value: string; file: File | null; problem: string | null; onValue: (v: string) => void; onFile: (f: File | null) => void }) {
  const id = `field-${field.label.replace(/\W+/g, '-')}`;
  const said = problem ? `${id}-problem` : undefined;
  const common = { id, 'aria-invalid': problem ? true : undefined, 'aria-describedby': said, 'aria-required': field.required || undefined };
  return (
    <div className={styles.field} data-problem={problem ? '' : undefined}>
      {field.kind === 'choice' ? (
        <fieldset className={styles.choices} aria-describedby={said}>
          <legend className={styles.label}>
            {field.label}
            {field.required ? null : <span className={styles.optional}> optional</span>}
          </legend>
          {field.options.map((option, i) => (
            <label key={option} className={styles.choice}>
              <input id={i === 0 ? id : undefined} type="radio" name={id} value={option} checked={value === option} onChange={() => onValue(option)} />
              {option}
            </label>
          ))}
        </fieldset>
      ) : (
        <>
          <label className={styles.label} htmlFor={id}>
            {field.label}
            {field.required ? null : <span className={styles.optional}> optional</span>}
          </label>
          {field.kind === 'long' ? (
            <textarea {...common} className={styles.input} rows={5} value={value} onChange={(event) => onValue(event.target.value)} />
          ) : field.kind === 'file' ? (
            <span className={styles.fileRow}>
              <input {...common} className={styles.file} type="file" onChange={(event) => onFile(event.target.files?.[0] ?? null)} />
              <span className={readerStyles.quiet}>{file ? `${file.name}` : 'Up to 2 MB'}</span>
            </span>
          ) : (
            <input {...common} className={styles.input} type={field.kind === 'email' ? 'email' : 'text'} inputMode={field.kind === 'email' ? 'email' : undefined} autoComplete={field.kind === 'email' ? 'email' : 'off'} value={value} onChange={(event) => onValue(event.target.value)} />
          )}
        </>
      )}
      {problem ? (
        <span id={said} className={styles.problem}>
          {problem}
        </span>
      ) : null}
    </div>
  );
}
