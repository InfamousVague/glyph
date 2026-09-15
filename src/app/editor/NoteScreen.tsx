import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Mic } from '@glacier/icons';
import { useToast } from '@glacier/react';
import type { EditorView } from '@codemirror/view';
import { ArrowLeft, Cog } from '../art/Icons.tsx';
import { adoptImagePath, pickImage } from '../core/images.ts';
import { ScrollFades } from '../art/ScrollFades.tsx';
import { useWispEdge } from '../art/wispEdge.ts';
import { ContextMenu } from './ContextMenu.tsx';
import { FindBar } from './FindBar.tsx';
import { Editor } from './Editor.tsx';
import { insertImageAt, releaseImageSpot, reserveImageSpot } from './images.ts';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { useUnfold } from '../core/unfold.ts';
import { getNote, noteTitle, saveNote, setNoteRecording, type Note } from '../core/store.ts';
import type { Segment } from '../capture/markdown.ts';
import { isDarkNow, setPreferences, usePreferences } from '../core/preferences.ts';
import { useWideScreen } from '../core/useWideScreen.ts';
import type { NoteView } from './viewMode.ts';
import { convertFileSrc } from '@tauri-apps/api/core';
import { FormattedView, type ApplyHow } from '../format/FormattedView.tsx';
import { useFormatter } from '../format/formatter.ts';
import type { Mode } from '../format/modes.ts';
import { RobotMenu } from '../format/RobotMenu.tsx';
import { NoteTape, TranscriptWords } from '../tapes/NoteTape.tsx';
import { NoteSettings } from './NoteSettings.tsx';
import { LinkMarks } from '../plugins/LinkMarks.tsx';
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
  // The view switch has room in the header only on a wide screen (a folding phone opened out); otherwise it lives in
  // the cog's sheet (Matt: "too big, it clogs up the header; hide it under a more menu that only expands when there
  // is enough space on the screen").
  const wide = useWideScreen();
  const chooseView = (value: NoteView) => {
    if (prefs.noteView === value) return;
    setPreferences({ noteView: value });
    fireNativeHaptic('selection');
  };
  const [title, setTitle] = useState(() => noteTitle(note.body));
  const [view, setView] = useState<EditorView | null>(null);
  const [photoProblem, setPhotoProblem] = useState<string | null>(null);
  // A spoken note keeps its recording: the tape at the top plays it. Removing it
  // (the tape's Remove) is held here, so the tape goes at once and Undo brings
  // it back without a trip to the store.
  const [kept, setKept] = useState<{
    ms: number | null;
    segments: Segment[] | null;
  } | null>(null);
  const spoken = useMemo(() => (kept ? { ...note, recordingMs: kept.ms, segments: kept.segments } : note), [note, kept]);
  const tape = useTape(spoken);
  const { toast } = useToast();
  /** The recording just removed, while its Undo still means something: cleared when the note is spoken into or left. */
  const removed = useRef<{ ms: number; segments: Segment[] } | null>(null);
  useEffect(
    () => () => {
      removed.current = null;
    },
    [],
  );
  /** What the robot is showing over the note, or null for the note itself. */
  const [mode, setMode] = useState<Mode | null>(null);
  /** The cog's sheet: pin, archive, what the note is linked to, delete. */
  const [settingsOpen, setSettingsOpen] = useState(false);
  /** Find and replace, open with its first words, or null when it's closed (FindBar.tsx). */
  const [finding, setFinding] = useState<string | null>(null);
  const [pinned, setPinned] = useState(Boolean(note.starred));
  /** The tape and the note's scrolling page. */
  const page = useRef<HTMLDivElement>(null);
  const header = useRef<HTMLElement>(null);
  // The tape and note go to smoke as they slip behind the header (art/wispEdge.ts).
  useWispEdge(page, undefined, header);
  // A picture that didn't come in is said once, then gets out of the way.
  useEffect(() => {
    if (!photoProblem) return;
    const id = window.setTimeout(() => setPhotoProblem(null), 6000);
    return () => window.clearTimeout(id);
  }, [photoProblem]);

  // The formatted text made the note (the Formatted view's Apply): said once,
  // with the way back, for a few seconds.
  const [applied, setApplied] = useState<{
    said: string;
    undo: () => void;
  } | null>(null);
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
          view.dispatch({
            changes: { from: line.from, to: line.to, insert: next(line.text) },
          });
          return true;
        }
      }
      return false;
    },
    say: setPhotoProblem,
  };

  // Apply, from the robot's view: the text goes into the note - in place of
  // it, above it or below it. Through the editor, so its history has it, and
  // said with an Undo that puts the old words back and the kept version back
  // to what it was.
  const applyFormatted = (text: string, how: ApplyHow) => {
    if (!view) return;
    const previous = view.state.doc.toString();
    const piece = text.trim();
    const next = how === 'replace' ? text : how === 'prepend' ? `${piece}\n\n${previous.replace(/^\s+/, '')}` : `${previous.replace(/\s+$/, '')}\n\n${piece}\n`;
    view.dispatch({
      changes: { from: 0, to: previous.length, insert: next },
      selection: { anchor: how === 'append' ? next.length : 0 },
      scrollIntoView: true,
    });
    const unkeep = formatter.apply(text, next);
    showMode(null);
    fireNativeHaptic('success');
    setApplied({
      said: how === 'replace' ? 'Applied to the note.' : how === 'prepend' ? 'Added above the note.' : 'Added below the note.',
      undo: () => {
        const now = view.state.doc.toString();
        view.dispatch({
          changes: { from: 0, to: now.length, insert: previous },
          selection: { anchor: 0 },
          scrollIntoView: true,
        });
        unkeep();
        setApplied(null);
      },
    });
  };

  // Playing takes the screen for the transcript; the chosen view waits under it.
  const shown: 'transcript' | 'robot' | 'raw' = tape.length && tape.playing ? 'transcript' : mode ? 'robot' : 'raw';

  // The tape's Remove: the recording comes off the note (its length and phrases forgotten; the audio file stays
  // until the note is spoken into again or deleted, which is what lets Undo put it back).
  const removeRecording = () => {
    void (async () => {
      tape.audio.ref.current?.pause();
      const full = await getNote(note.id).catch(() => null);
      const ms = tape.length;
      const segments = full?.segments ?? tape.segments ?? [];
      removed.current = { ms, segments };
      setKept({ ms: null, segments: null });
      fireNativeHaptic('warning');
      try {
        await setNoteRecording(note.id, null, []);
      } catch (failure) {
        removed.current = null;
        setKept({ ms, segments });
        toast({
          message: `The recording couldn’t be removed: ${failure instanceof Error ? failure.message : String(failure)}`,
        });
        return;
      }
      toast({
        message: 'Recording removed.',
        duration: 5000,
        action: {
          label: 'Undo',
          onPress: () => {
            const back = removed.current;
            if (!back) return;
            removed.current = null;
            setKept({ ms: back.ms, segments: back.segments });
            void setNoteRecording(note.id, back.ms, back.segments);
          },
        },
      });
    })();
  };
  const speakHere = () => {
    // A new take replaces a removed recording's file, so its Undo would no longer be true.
    removed.current = null;
    flush();
    onSpeak(note.id);
  };

  return (
    <div ref={screen} className={styles.screen}>
      {/* The crease's shadow while the note unfolds; nothing the rest of the time. */}
      <div className={styles.crease} aria-hidden="true" />
      {/*
        Two words and the note. The note's first line is already the biggest
        type on the screen, so the header no longer repeats it; it keeps the
        title only as the back button's accessible description.
      */}
      <header ref={header} className={`app-headerPane ${styles.header}`}>
        <button type="button" className={`app-word ${styles.back}`} onClick={back} aria-label={`Back to notes from ${title || 'new note'}`}>
          <ArrowLeft /> Notes
        </button>
        <div className={styles.tools}>
          {/* Markdown, the marks with the formatting (the default), or just the formatted text (editor/viewMode.ts). */}
          {wide ? (
            <div className={styles.viewSwitch} role="radiogroup" aria-label="How the note is shown">
              {(
                [
                  ['mixed', 'Markdown'],
                  ['formatted', 'Formatted'],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={prefs.noteView === value}
                  data-on={prefs.noteView === value || undefined}
                  disabled={shown !== 'raw'}
                  onClick={() => chooseView(value)}
                >
                  {label}
                </button>
              ))}
            </div>
          ) : null}
          {/* A note with no recording has no tape; talking into it is this mic. Once it has audio, the tape's Add is. */}
          {tape.length > 0 ? null : (
            <button type="button" className={styles.cog} onClick={speakHere} aria-label="Talk into this note">
              <Mic size={18} strokeWidth={2.2} aria-hidden="true" />
            </button>
          )}
          <RobotMenu mode={mode} onChoose={showMode} />
          <button type="button" className={styles.cog} onClick={() => setSettingsOpen(true)} aria-label="This note's settings">
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
          {applied.said}
          <button type="button" className={`app-word ${styles.undo}`} onClick={applied.undo}>
            Undo
          </button>
        </p>
      ) : null}

      {/*
        The tape and the note are one page under the header, and scroll
        together (Matt: "the tape and stuff at the top of a note should scroll
        up with the rest of the note instead of sticking to the top"). The
        Formatted view and the transcript keep their own scrolling, under a
        tape that stays, since each has a bar of words at its top.
      */}
      <div ref={page} className={styles.page} data-scrolls={shown === 'raw' || undefined}>
        {tape.length > 0 ? (
          <div className={styles.tapeRow}>
            {!tape.web ? (
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
            <NoteTape note={note} title={title} tape={tape} onSpeak={speakHere} onRemove={removeRecording} />
          </div>
        ) : null}
        {/* What the note is linked to (a Notion board, a repo): a tap opens the cog sheet to change it. */}
        <LinkMarks noteId={note.id} onPress={() => setSettingsOpen(true)} />

        {shown === 'transcript' ? (
          <div className={styles.body}>
            <TranscriptWords tape={tape} />
          </div>
        ) : null}
        {shown === 'robot' ? (
          <div className={styles.body}>
            {/* Keyed by mode: a change of mode is a fresh view, with its own editor and its own once-per-mount start. */}
            <FormattedView
              key={mode}
              formatter={formatter}
              currentBody={currentBody}
              dark={isDarkNow(prefs.theme)}
              onApply={applyFormatted}
              onClose={() => showMode(null)}
            />
          </div>
        ) : null}
        <div className={styles.body} hidden={shown !== 'raw'}>
          <Editor
            value={note.body}
            onChange={onChange}
            onView={setView}
            wispTyping
            display={prefs.noteView}
            onImageError={setPhotoProblem}
            dark={isDarkNow(prefs.theme)}
            assist={prefs.assist}
            placeholder="Write something."
            swipeAction={() => {
              const action = plugins.itemAction(note.id);
              return action
                ? {
                    label: action.label,
                    busyLabel: action.busyLabel,
                    run: (text) => action.run(text, editing),
                  }
                : null;
            }}
            suggest={(text) =>
              plugins.suggestions(note.id, text).map((s) => ({
                line: s.line,
                label: s.label,
                busyLabel: s.busyLabel,
                run: () => s.run(editing),
              }))
            }
            linkMenus={{ say: (message) => editing.say(message) }}
            grow
          />
        </div>
      </div>
      {/* Press and hold in the note: Cut, Copy, Paste, Select all, Add image. */}
      <ContextMenu view={view} onAddImage={() => void addPhoto()} onPasteImage={pasteImage} onFind={setFinding} />
      {finding !== null && view && shown === 'raw' ? <FindBar view={view} initial={finding} onClose={() => setFinding(null)} /> : null}
      {/* The page's top and bottom soften while there is more to scroll to. */}
      {shown === 'raw' ? <ScrollFades target={page} top={false} /> : null}
      <NoteSettings
        open={settingsOpen}
        noteId={note.id}
        title={title}
        pinned={pinned}
        editing={editing}
        onClose={() => setSettingsOpen(false)}
        view={!wide && shown === 'raw' ? prefs.noteView : undefined}
        onView={chooseView}
        onFind={
          shown === 'raw'
            ? () => {
                setSettingsOpen(false);
                setFinding('');
              }
            : undefined
        }
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
