import { useCallback, useEffect, useRef, useState } from 'react';
import type { EditorView } from '@codemirror/view';
import { ArrowLeft, Cog } from '../art/Icons.tsx';
import { adoptImagePath, pickImage } from '../core/images.ts';
import { ContextMenu } from './ContextMenu.tsx';
import { Editor } from './Editor.tsx';
import { insertImageAt, releaseImageSpot, reserveImageSpot } from './images.ts';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { useUnfold } from '../core/unfold.ts';
import { noteTitle, saveNote, type Note } from '../core/store.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { convertFileSrc } from '@tauri-apps/api/core';
import { FormattedView } from '../format/FormattedView.tsx';
import { useFormatter } from '../format/formatter.ts';
import type { Mode } from '../format/modes.ts';
import { RobotMenu } from '../format/RobotMenu.tsx';
import { NoteTape, TranscriptWords } from '../tapes/NoteTape.tsx';
import { NoteSettings } from './NoteSettings.tsx';
import { plugins } from '../plugins/registry.ts';
import type { NoteEditing } from '../plugins/types.ts';
import { useTape } from '../tapes/useTape.ts';
import styles from './NoteScreen.module.css';

/**
 * One note, open.
 *
 * This component owns SAVING, and saving is the part with teeth. A phone kills
 * a backgrounded webview without warning and without a beforeunload, so a
 * debounce alone would lose whatever was typed in the last fraction of a
 * second before the user switched apps - which is precisely the moment a person
 * has just written the thing they opened the app to write.
 *
 * So there are two paths. The debounce (400ms after the last keystroke) keeps
 * the common case cheap, and a flush on blur, on unmount, and on
 * `visibilitychange` covers every way the app can go away. The flush is
 * synchronous in its decision - it checks a ref, not state - because by the
 * time a re-render could happen the process may be gone.
 *
 * The note, and over it what the robot makes of it: the robot button in the
 * header (format/RobotMenu.tsx) drops Format, Summarize and Enhance, and
 * choosing one opens that mode's view (format/FormattedView.tsx) over the
 * note, which starts writing the first time it is opened; Close, "Back to
 * note" in the menu, or the back gesture returns to the note. Matt: "make
 * all of these buttons instead of the segmented toggle, make a robot drop
 * down button for these options". A spoken note has one more view, the
 * transcript - the recording's phrases following the sound - which shows
 * whenever the tape is playing and steps aside when it stops (Matt: "the
 * default mode whenever we're playing, not a different tab"). The editor
 * stays mounted behind the others, hidden, so nothing typed is lost and its
 * caret keeps its place.
 */

interface NoteScreenProps {
  note: Note;
  onBack: () => void;
  onDelete: (id: string) => void;
  /** Talk into this note: the recorder, aimed here, and back here after. */
  onSpeak: (id: string) => void;
  onPin: (note: Note) => void;
  onArchive: (note: Note) => void;
}

const SAVE_DEBOUNCE_MS = 400;

export function NoteScreen({ note, onBack, onDelete, onSpeak, onPin, onArchive }: NoteScreenProps) {
  const prefs = usePreferences();
  const [title, setTitle] = useState(() => noteTitle(note.body));
  const [view, setView] = useState<EditorView | null>(null);
  const [photoProblem, setPhotoProblem] = useState<string | null>(null);
  // A spoken note keeps its recording: the tape at the top plays it.
  const tape = useTape(note);
  /** What the robot is showing over the note, or null for the note itself. */
  const [mode, setMode] = useState<Mode | null>(null);
  /** The cog's sheet: pin, archive, what the note is linked to, delete. */
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [pinned, setPinned] = useState(Boolean(note.starred));
  // A picture that didn't come in is said once, then gets out of the way.
  useEffect(() => {
    if (!photoProblem) return;
    const id = window.setTimeout(() => setPhotoProblem(null), 6000);
    return () => window.clearTimeout(id);
  }, [photoProblem]);

  // The formatted text made the note (the Formatted view's Apply): said once,
  // with the way back, for a few seconds.
  const [applied, setApplied] = useState<{ undo: () => void } | null>(null);
  useEffect(() => {
    if (!applied) return;
    const id = window.setTimeout(() => setApplied(null), 8000);
    return () => window.clearTimeout(id);
  }, [applied]);

  // The live document, held in a ref rather than state: it changes on every
  // keystroke and nothing in this component's render depends on it, so putting
  // it in state would re-render the screen once per character for nothing.
  const body = useRef(note.body);
  const saved = useRef(note.body);
  const timer = useRef<number | null>(null);

  // The robot's text for the note in the mode showing (the hook looks up
  // what is kept itself); Format while nothing shows, so a run the queue
  // started is found the moment the view opens.
  const formatter = useFormatter(note.id, mode ?? 'format');
  const currentBody = useCallback(() => body.current, []);

  const flush = useCallback(() => {
    if (timer.current !== null) {
      window.clearTimeout(timer.current);
      timer.current = null;
    }
    if (body.current === saved.current) return;
    const pending = body.current;
    saved.current = pending;
    void saveNote(note.id, pending, note.source);
  }, [note.id, note.source]);

  const onChange = useCallback(
    (next: string) => {
      body.current = next;
      // The header title is the first line, so it does need to re-render - but
      // only when the first line actually changed, which is rare.
      setTitle((prev) => {
        const now = noteTitle(next);
        return prev === now ? prev : now;
      });
      if (timer.current !== null) window.clearTimeout(timer.current);
      timer.current = window.setTimeout(flush, SAVE_DEBOUNCE_MS);
    },
    [flush],
  );

  useEffect(() => {
    const onHide = () => {
      if (document.visibilityState === 'hidden') flush();
    };
    document.addEventListener('visibilitychange', onHide);
    window.addEventListener('pagehide', flush);
    return () => {
      document.removeEventListener('visibilitychange', onHide);
      window.removeEventListener('pagehide', flush);
      flush();
    };
  }, [flush]);

  const back = () => {
    flush();
    onBack();
  };

  // The phone's back gesture: the list.
  useBack(true, back);

  // On a folding phone, the note flattens with the hinge as the phone opens.
  const screen = useRef<HTMLDivElement>(null);
  useUnfold(screen);

  // A picture, put into the note at the caret on its own line: from the
  // phone's picker (the menu's Add image), or one the activity copied out of
  // the clipboard (the menu's Paste). Pasting with the keyboard is the
  // editor's own (editor/images.ts).
  const placeImage = async (fetch: () => Promise<string | null>) => {
    setPhotoProblem(null);
    // The place is taken now: the picker leaves the app, and the caret is not
    // guaranteed to be where it was when it comes back.
    const spot = view ? reserveImageSpot(view) : null;
    try {
      const name = await fetch();
      if (name && view && spot !== null) {
        insertImageAt(view, spot, name);
        fireNativeHaptic('light');
      }
    } catch (failure) {
      setPhotoProblem(failure instanceof Error ? failure.message : String(failure));
    } finally {
      if (view && spot !== null) releaseImageSpot(view, spot);
    }
  };
  const addPhoto = () => placeImage(pickImage);
  const pasteImage = (path: string) => placeImage(() => adoptImagePath(path));

  const remove = () => {
    // Deliberately no confirmation dialog yet: v1 notes are cheap and the
    // alternative - an AlertDialog on every delete - is the kind of friction
    // that makes a quick-capture app feel heavy. Undo is the right answer and
    // is milestone 5's job.
    fireNativeHaptic('warning');
    onDelete(note.id);
  };

  const showMode = (next: Mode | null) => {
    if (next) flush();
    setMode(next);
    // The editor was hidden, not unmounted, so nothing typed is lost; it
    // measures itself again now that it has a size.
    if (!next) window.requestAnimationFrame(() => view?.requestMeasure());
  };

  /**
   * The note, as plugins change it (plugins/types.ts `NoteEditing`): through the
   * editor, so each change is one undo and saves like typing, and anything to
   * say shows on the note like a picture's problem does.
   */
  const editing: NoteEditing = {
    noteId: note.id,
    body: () => view?.state.doc.toString() ?? body.current,
    replaceLine(find, next) {
      const doc = view?.state.doc;
      if (!view || !doc) return false;
      for (let n = 1; n <= doc.lines; n += 1) {
        const line = doc.line(n);
        if (find(line.text, n)) {
          view.dispatch({ changes: { from: line.from, to: line.to, insert: next(line.text) } });
          return true;
        }
      }
      return false;
    },
    say: setPhotoProblem,
  };

  // Apply, from the Formatted view: the rewrite becomes the note. Through the
  // editor, so its history has it, and said with an Undo that puts the old
  // words back and the formatted version back to what it was kept as.
  const applyFormatted = (text: string) => {
    if (!view) return;
    const previous = view.state.doc.toString();
    view.dispatch({ changes: { from: 0, to: previous.length, insert: text }, selection: { anchor: 0 }, scrollIntoView: true });
    const unkeep = formatter.apply(text);
    showMode(null);
    fireNativeHaptic('success');
    setApplied({
      undo: () => {
        const now = view.state.doc.toString();
        view.dispatch({ changes: { from: 0, to: now.length, insert: previous }, selection: { anchor: 0 }, scrollIntoView: true });
        unkeep();
        setApplied(null);
      },
    });
  };

  // Playing takes the screen for the transcript; the chosen view waits under it.
  const shown: 'transcript' | 'robot' | 'raw' = tape.length && tape.playing ? 'transcript' : mode ? 'robot' : 'raw';

  return (
    <div ref={screen} className={styles.screen}>
      {/* The crease's shadow while the note unfolds; nothing the rest of the time. */}
      <div className={styles.crease} aria-hidden="true" />
      {/*
        Two words and the note. The note's first line is already the biggest
        type on the screen, so the header no longer repeats it; it keeps the
        title only as the back button's accessible description.
      */}
      <header className={styles.header}>
        <button type="button" className={`app-word ${styles.back}`} onClick={back} aria-label={`Back to notes from ${title || 'new note'}`}>
          <ArrowLeft /> Notes
        </button>
        <div className={styles.tools}>
          <RobotMenu mode={mode} onChoose={showMode} />
          <button
            type="button"
            className={styles.cog}
            onClick={() => setSettingsOpen(true)}
            aria-label="This note's settings"
          >
            <Cog />
          </button>
        </div>
      </header>
      {photoProblem ? (
        <p className={styles.problem} role="alert">
          {photoProblem}
        </p>
      ) : null}
      {applied ? (
        <p className={styles.problem} role="status">
          Applied to the note.
          <button type="button" className={`app-word ${styles.undo}`} onClick={applied.undo}>
            Undo
          </button>
        </p>
      ) : null}

      <div className={styles.tapeRow}>
        {tape.length && !tape.web ? (
            <audio
              ref={tape.audio.ref}
              src={convertFileSrc(`${note.id}.wav`, 'rec')}
              preload="metadata"
              onPlay={tape.audio.onPlay}
              onPause={tape.audio.onPause}
              onEnded={tape.audio.onEnded}
              onTimeUpdate={tape.audio.onTimeUpdate}
              onError={tape.audio.onError}
            />
        ) : null}
        <NoteTape
          note={note}
          title={title}
          tape={tape}
          onSpeak={() => {
            flush();
            onSpeak(note.id);
          }}
        />
      </div>

      {shown === 'transcript' ? (
        <div className={styles.body}>
          <TranscriptWords tape={tape} />
        </div>
      ) : null}
      {shown === 'robot' ? (
        <div className={styles.body}>
          {/* Keyed by mode: a change of mode is a fresh view, with its own editor and its own once-per-mount start. */}
          <FormattedView key={mode} formatter={formatter} currentBody={currentBody} dark={isDarkNow(prefs.theme)} onApply={applyFormatted} onClose={() => showMode(null)} />
        </div>
      ) : null}
      <div className={styles.body} hidden={shown !== 'raw'}>
        <Editor
          value={note.body}
          onChange={onChange}
          onView={setView}
          onImageError={setPhotoProblem}
          dark={isDarkNow(prefs.theme)}
          assist={prefs.assist}
          placeholder="Write something."
          swipeAction={() => {
            const action = plugins.itemAction(note.id);
            return action ? { label: action.label, busyLabel: action.busyLabel, run: (text) => action.run(text, editing) } : null;
          }}
        />
      </div>
      {/* Press and hold in the note: Cut, Copy, Paste, Select all, Add image. */}
      <ContextMenu view={view} onAddImage={() => void addPhoto()} onPasteImage={pasteImage} />
      <NoteSettings
        open={settingsOpen}
        noteId={note.id}
        title={title}
        pinned={pinned}
        editing={editing}
        onClose={() => setSettingsOpen(false)}
        onPin={() => {
          flush();
          onPin({ ...note, starred: pinned });
          setPinned((was) => !was);
          fireNativeHaptic('selection');
          setSettingsOpen(false);
        }}
        onArchive={() => {
          flush();
          setSettingsOpen(false);
          onArchive(note);
        }}
        onDelete={() => {
          setSettingsOpen(false);
          remove();
        }}
      />
    </div>
  );
}
