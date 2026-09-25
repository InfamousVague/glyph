import { Ghost } from '../art/Ghost.tsx';
import { createPortal } from 'react-dom';
import { useTopBarTools } from '../core/topBarTools.ts';
import { useEffect, useMemo, useRef, useState } from 'react';
import { useToast } from '@glacier/react';
import type { EditorView } from '@codemirror/view';
import { useWispEdge } from '../art/wispEdge.ts';
import { useNotePlace } from './notePlace.ts';
import { boardFrom } from '../core/boards.ts';
import { hasClips, tapeId } from '../core/clips.ts';
import { useNoteZoom } from './pinchZoom.ts';
import { ContextMenu } from './ContextMenu.tsx';
import { FindBar } from './FindBar.tsx';
import { Editor } from './Editor.tsx';
import { CanvasView } from '../canvas/CanvasView.tsx';
import { canvasOf, withCanvas } from '../canvas/jsonCanvas.ts';
import { BookBar, BookFoot, BookView } from '../book/BookView.tsx';
import { isBookBody, type BookPlace } from '../book/book.ts';
import { writeBookSpot } from '../book/bookSpot.ts';
import { withFrontMatterTitle } from '../core/frontMatter.ts';
import { authorsOf } from '../core/authors.ts';
import { Byline } from '../authors/Byline.tsx';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { useUnfold } from '../core/unfold.ts';
import type { Note } from '../core/store.ts';
import { isDarkNow, setPreferences, usePreferences } from '../core/preferences.ts';
import { useWideScreen } from '../core/useWideScreen.ts';
import type { NoteView } from './viewMode.ts';
import type { ReviewHandoff } from '../ai/review.ts';
import { keepAllChanges } from './aiChanges.ts';
import { NoteTape, TranscriptWords } from '../tapes/NoteTape.tsx';
import { NoteSettings } from './NoteSettings.tsx';
import { LinkMarks } from '../plugins/LinkMarks.tsx';
import { AiStrip } from '../ai/AiStrip.tsx';
import { boardMadeWords } from './boardActions.ts';
import { itemSend, lineOffers, noteEditing } from './notePlugins.ts';
import { NoteTools } from './NoteTools.tsx';
import { useBookmark } from './useBookmark.ts';
import { useLandAt } from './useLandAt.ts';
import { useLiveNote } from './useLiveNote.ts';
import { useNoteAi, type NoteAsk } from './useNoteAi.ts';
import { useNotePictures } from './useNotePictures.ts';
import { useNoteSaving, type NoteRename } from './useNoteSaving.ts';
import { useNoteTape } from './useNoteTape.ts';
import { useStripRoom } from './useStripRoom.ts';
import styles from './NoteScreen.module.css';

/**
 * One note, open: the words in their editor (editor/Editor.tsx), and everything that floats over or beside them.
 *
 * This component owns SAVING, and saving is the part with teeth: the words are kept in a ref, saved on a debounce,
 * and flushed on every way the app can go away and every way off the note this screen offers
 * (editor/useNoteSaving.ts says why). Everything outside the screen that must change the open note asks it rather
 * than writing the store - a rename from the tab comes in as `rename`.
 *
 * One screen shows five things in one place. While a spoken note's tape plays, the transcript - the recording's
 * phrases following the sound - takes the page (Matt: "the default mode whenever we're playing, not a different
 * tab"), and steps aside when it stops. Otherwise the note's own view: its words, or, for a note that is a canvas or a
 * book, the canvas drawn or the book's index, with the JSON or Markdown behind the view switch. The editor stays
 * mounted behind whichever of the others is up, hidden, so nothing typed is lost and its caret keeps its place.
 *
 * The rest is composed here from pieces with one job each: the tools (editor/NoteTools.tsx) and the bookmark behind
 * one of them (editor/useBookmark.ts), the tape and its removal (editor/useNoteTape.ts), the AI in the note
 * (editor/useNoteAi.ts, with the room its strip takes in editor/useStripRoom.ts), pictures and the note's one line of problems
 * (editor/useNotePictures.ts), landing on an item a link pointed at (editor/useLandAt.ts), live sync
 * (editor/useLiveNote.ts), and the ways plugins reach the note (editor/notePlugins.ts).
 */

interface NoteScreenProps {
  note: Note;
  onBack: () => void;
  onDelete: (id: string) => void;
  /** Talk into this note: the recorder, aimed here, and back here after. */
  onSpeak: (id: string) => void;
  onPin: (note: Note) => void;
  onArchive: (note: Note) => void;
  /** Opens the note by that title, making it where there is none: what a [[link]] in the words does. */
  onOpenTitle?: (title: string, at?: string) => void;
  /** The item to land on when the note was opened by a link pointing inside it: `^anchor` (core/boards.ts). */
  at?: string;
  /** Whether a note by that title exists, for drawing a [[link]] as written or as waiting. */
  hasTitle?: (title: string) => boolean;
  /** The book this note is a chapter of, for the bar under its header (book/book.ts `bookOf`); null for none. */
  book?: BookPlace | null;
  /** Opens a note by its title in this note's tab, for moving within a book; without it, `onOpenTitle`. */
  onOpenWithin?: (title: string) => void;
  /** Makes a canvas by that title and opens it in this tab: a book's "Add a canvas" (book/BookView.tsx). */
  onNewCanvas?: (title: string) => void;
  /** A note's body by its title, for a canvas card that is a note to be drawn small (canvas/CanvasView.tsx). */
  bodyOfTitle?: (title: string) => string | null;
  /** Every note's title, for a canvas's + to choose a note from. */
  allTitles?: () => string[];
  /**
   * A canvas renamed from its tab (notes/NoteTabs.tsx), while this is the note being read.
   *
   * It cannot be written from outside: the live body is a ref here that only this screen's own `onChange` sets, so a
   * `saveNote` from App would be flushed away by the next keystroke. So the row asks, and the screen writes it the
   * way the canvas itself writes - through `onChange`, on the same debounce as typing. `asked` rises with each
   * asking, so renaming twice to the same name still lands.
   */
  rename?: NoteRename | null;
  /** A spoken instruction about this note, to run on it as it opens (App.tsx, ai/instruction.ts); `key` tells one from the next. */
  ask?: NoteAsk;
  /** The review after the recording that just made or grew this note (ai/useNoteReview.ts): run here, in the strip and the note. */
  review?: ReviewHandoff & { key: number };
}

export function NoteScreen({ note, onBack, onDelete, onSpeak, onPin, onArchive, onOpenTitle, hasTitle, book, onOpenWithin, onNewCanvas, bodyOfTitle, allTitles, at, rename, ask, review }: NoteScreenProps) {
  const prefs = usePreferences();
  // The view switch has room in the header only on a wide screen (a folding phone opened out); otherwise it lives in
  // the More sheet (Matt: "too big, it clogs up the header; hide it under a more menu that only expands when there
  // is enough space on the screen").
  const wide = useWideScreen();
  const chooseView = (value: NoteView) => {
    if (prefs.noteView === value) return;
    setPreferences({ noteView: value });
    fireNativeHaptic('selection');
  };
  const [view, setView] = useState<EditorView | null>(null);
  const { toast } = useToast();
  // The live words, and their saving: everything below that reads or writes the note goes through these.
  const { body, onChange, flush, title, blank } = useNoteSaving(note, rename);
  /*
   * A note that is a canvas (docs/CANVAS.md) is drawn as one where its words would be. Its JSON is there behind the
   * header's view switch (Matt: "the raw JSON in the editor"), but as the note's own switch rather than the
   * preference every note shares - that one defaults to the marks, and a canvas should open as a canvas. Switching
   * to the JSON hands the editor what the canvas has written since (it follows `value`); switching back reads the
   * canvas from what was typed. While the canvas is drawn there is no editor, so what needs one (find, zoom, the
   * caret's place) stands idle.
   */
  const [source, setSource] = useState(false);
  const [canvasBody, setCanvasBody] = useState(note.body);
  const canvas = useMemo(() => canvasOf(canvasBody), [canvasBody]);
  const drawing = !!canvas && !source;
  /*
   * A note that is a book (docs/BOOKS.md) is drawn as its index the same way, its Markdown behind the same switch.
   * The view's own changes (a chapter added, moved, taken out) are written through `onChange` like typing and kept
   * here too, so the index redraws from what it just wrote.
   */
  const [bookBody, setBookBody] = useState(note.body);
  const isBook = useMemo(() => isBookBody(bookBody), [bookBody]);
  // A rename from the tab lands in the live body (editor/useNoteSaving.ts), and the index is drawn from its own copy:
  // it takes the new name too, or its next change would write the old one back.
  useEffect(() => {
    if (rename?.id === note.id) setBookBody(body.current);
    // Each asking is its own, as it is for the saving.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rename?.asked]);
  /** The name typed in the More sheet, into the front matter; the index takes it too, as it takes one from the tab. */
  const renameHere = (next: string) => {
    const named = withFrontMatterTitle(body.current, next);
    onChange(named);
    if (isBook) setBookBody(named);
  };
  const paging = isBook && !source;
  const typed = !!canvas || isBook;
  const showSource = (next: boolean) => {
    if (next === source) return;
    if (!next) {
      setCanvasBody(body.current);
      setBookBody(body.current);
    }
    setSource(next);
    fireNativeHaptic('selection');
  };
  useLiveNote(view, note.id);
  const pictures = useNotePictures(view);
  const { tape, recording, removeRecording, forgetRemoved } = useNoteTape(note, body, toast);
  /** The More sheet: how it is read, the AI, pin, archive, what the note is linked to, delete (NoteSettings.tsx). */
  const [settingsOpen, setSettingsOpen] = useState(false);
  /** Find and replace, open with its first words, or null when it's closed (FindBar.tsx). */
  const [finding, setFinding] = useState<string | null>(null);
  // Local, because App keeps the same `note` after a pin (notes/useNoteActions.ts toggles `!note.starred`): passing
  // `note` unchanged would pin, then unpin, then pin.
  const [pinned, setPinned] = useState(Boolean(note.starred));
  /** The tape and the note's scrolling page. */
  const page = useRef<HTMLDivElement>(null);
  const header = useRef<HTMLElement>(null);

  const back = () => {
    flush();
    onBack();
  };

  // The phone's back gesture: the list.
  useBack(true, back);

  // On a folding phone, the note flattens with the hinge as the phone opens.
  const screen = useRef<HTMLDivElement>(null);
  useUnfold(screen);
  const onStripHeight = useStripRoom(screen, header);

  const ai = useNoteAi({ note, view, flush, body, wisp: prefs.wisp, ask, review, toast });

  const remove = () => {
    // No confirmation: it goes to the trash, with an Undo, and is only deleted
    // for good from there (core/trash.ts, notes/useNoteActions.ts).
    fireNativeHaptic('warning');
    onDelete(note.id);
  };

  const editing = noteEditing(note.id, view, () => body.current, pictures.say);

  // Playing takes the screen for the transcript; the note waits under it.
  const shown: 'transcript' | 'raw' = tape.length && tape.playing ? 'transcript' : 'raw';
  // The tape and note go to smoke as they slip behind the header; read again on a view change, since another view may not scroll (art/wispEdge.ts).
  // The page smokes at both ends: under the header, and off the bottom where the dock is (art/wispEdge.ts).
  // Not on a canvas: it is not a page that scrolls off its foot, and the band was smoking the canvas's own tools at
  // the bottom of the screen (Matt: "The bottom wisp effect is effecting canvas view buttons at the bottom").
  useWispEdge(page, shown, header, { foot: !canvas });
  // The note opens where it was left, and remembers where it is left (editor/notePlace.ts).
  // Opened at an item, the note goes to that line rather than back to where it was left last time.
  useNotePlace(note.id, page, view, shown === 'raw' && !at);
  // A chapter open is where its book was left, so the book opens here again from outside it (book/bookSpot.ts).
  const inBook = book?.book.id ?? null;
  useEffect(() => {
    if (inBook) writeBookSpot(inBook, { kind: 'chapter', title });
  }, [inBook, title]);
  const { marked, bookmark } = useBookmark(note, view, page, (message) => toast({ message }));
  useLandAt(at, view, page, header);

  /**
   * The note's list laid out as a board (core/boards.ts): each item gets a name at the end, and a fence of columns
   * goes in under the title, ticked items in Done. One change, so one Undo puts the note back as it was.
   */
  const makeBoard = () => {
    if (!view) return;
    const made = boardFrom(view.state.doc.toString());
    setSettingsOpen(false);
    if (!made) return;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: made.doc }, userEvent: 'input.board' });
    fireNativeHaptic('success');
    toast({ message: boardMadeWords(made, 'cards') });
  };

  // Two fingers pinch the note's text larger or smaller (editor/pinchZoom.ts).
  useNoteZoom(page, view, shown === 'raw');

  const speakHere = () => {
    // A new take replaces a removed recording's file, so its Undo would no longer be true.
    forgetRemoved();
    flush();
    onSpeak(note.id);
  };

  // Where the app's bar wants this screen's controls, if it is there to hold them (core/topBarTools.ts).
  const toolsSlot = useTopBarTools();

  /*
   * The links for the editor, one object for as long as App's lookups are the same ones: the editor looks again at the
   * canvases framed in the note whenever it is handed a new one (editor/Editor.tsx), which rescans the whole note, and
   * this screen draws several times a second while a tape plays. App makes new lookups when the notes change, which is
   * when a framed canvas may have been drawn on.
   */
  const wiki = useMemo(() => (onOpenTitle && hasTitle ? { known: hasTitle, open: onOpenTitle, body: bodyOfTitle } : undefined), [onOpenTitle, hasTitle, bodyOfTitle]);

  const tools = (
    <NoteTools
      kind={canvas ? 'canvas' : isBook ? 'book' : 'words'}
      page={typed ? !source : prefs.noteView === 'formatted'}
      switchable={shown === 'raw'}
      onSwitch={() => (typed ? showSource(!source) : chooseView(prefs.noteView === 'formatted' ? 'mixed' : 'formatted'))}
      marked={marked}
      onBookmark={bookmark}
      onSpeak={tape.length > 0 ? null : speakHere}
      onMore={() => setSettingsOpen(true)}
    />
  );

  return (
    <div ref={screen} className={styles.screen}>
      {/* The crease's shadow while the note unfolds; nothing the rest of the time. */}
      <div className={styles.crease} aria-hidden="true" />
      {/*
        The note's controls live in the app's top bar now (Matt: "Move the controls for the note into the topbar"),
        put there by a portal because they hold the editor's state - the view being shown, the bookmark's line, the
        tape - and lifting them into App.tsx would lift the editor with them. Where there is no bar to take them,
        they stay in this header, which is where they have always been. With them in the bar the header holds
        nothing at all, which its stylesheet's `.header:empty` depends on.
      */}
      <header ref={header} className={`app-headerPane ${styles.header}`}>
        {toolsSlot ? null : (
          <div className={styles.headerRow}>
            <span />
            {tools}
          </div>
        )}
      </header>
      {toolsSlot ? createPortal(tools, toolsSlot) : null}
      {/* The model at work on this note, and what it did: under the header, over the page (ai/AiStrip.tsx). */}
      <div className={styles.stripHolder}>
        <AiStrip noteId={note.id} onUndo={ai.undoRun} onHeight={onStripHeight} marks={ai.marks && view ? { count: ai.marks, keepAll: () => keepAllChanges(view) } : undefined} stage={ai.reviewStage} />
      </div>
      {pictures.problem ? (
        <p className={styles.problem} role="alert">
          {pictures.problem}
        </p>
      ) : null}

      {/*
        The tape and the note are one page under the header, and scroll
        together (Matt: "the tape and stuff at the top of a note should scroll
        up with the rest of the note instead of sticking to the top"). The
        Formatted view and the transcript keep their own scrolling, under a
        tape that stays, since each has a bar of words at its top.
      */}
      <div ref={page} className={styles.page} data-scrolls={(shown === 'raw' && !drawing) || undefined}>
        {tape.length > 0 ? (
          <div className={styles.tapeRow}>
            {recording ? (
              <audio
                ref={tape.audio.ref}
                src={recording}
                preload="metadata"
                onPlay={tape.audio.onPlay}
                onPause={tape.audio.onPause}
                onEnded={tape.audio.onEnded}
                onTimeUpdate={tape.audio.onTimeUpdate}
                onError={tape.audio.onError}
              />
            ) : null}
            <NoteTape note={note} title={title} tape={tape} onSpeak={speakHere} onRemove={removeRecording} hasMemos={hasClips(body.current)} />
          </div>
        ) : null}
        {/* What the note is linked to (a Notion board, a repo): a tap opens the More sheet to change it. */}
        <LinkMarks noteId={note.id} onPress={() => setSettingsOpen(true)} />
        {/* A chapter's book, its place in it and the chapters either side (docs/BOOKS.md). */}
        {book && onOpenTitle ? <BookBar place={book} open={(t) => (onOpenWithin ?? onOpenTitle)(t)} /> : null}
        {/* Who wrote it, when it names anyone (core/authors.ts): a book says so for all its pages, in its index. */}
        {!paging ? <Byline authors={authorsOf(note.body)} className={styles.byline} /> : null}

        {shown === 'transcript' ? (
          <div className={styles.body}>
            <TranscriptWords tape={tape} />
          </div>
        ) : null}
        {drawing ? (
          <div className={`${styles.body} ${styles.canvasBody}`} hidden={shown !== 'raw'}>
            <CanvasView
              canvas={canvas}
              dark={isDarkNow(prefs.theme)}
              wiki={onOpenTitle && hasTitle ? { known: hasTitle, open: onOpenTitle, body: bodyOfTitle, titles: allTitles } : undefined}
              // A change to the canvas is a change to the note: written into the body as the spec's JSON, front
              // matter kept, and saved the way typing is (editor/useNoteSaving.ts).
              onChange={(next) => onChange(withCanvas(body.current, next))}
            />
          </div>
        ) : null}
        {paging ? (
          <div className={styles.body} hidden={shown !== 'raw'}>
            <BookView
              body={bookBody}
              title={title}
              known={hasTitle ?? (() => false)}
              open={(t) => (onOpenWithin ?? onOpenTitle)?.(t)}
              openCanvas={onNewCanvas}
              titles={allTitles ?? (() => [])}
              bodyOf={bodyOfTitle}
              spot={{ id: note.id, page }}
              onChange={(next) => {
                setBookBody(next);
                onChange(next);
              }}
            />
          </div>
        ) : null}
        <div className={styles.body} hidden={shown !== 'raw' || drawing || paging}>
          <Editor
            // A canvas's JSON or a book's Markdown, once asked for, is what the view has written by now, not what the note opened with.
            value={typed && source ? body.current : note.body}
            onChange={onChange}
            onView={setView}
            wispTyping={prefs.wisp}
            display={typed ? 'mixed' : prefs.noteView}
            tape={recording}
            tapeId={tape.length > 0 ? tapeId(note.id) : null}
            onImageError={pictures.say}
            dark={isDarkNow(prefs.theme)}
            assist={prefs.assist}
            placeholder="Write something."
            swipeAction={() => itemSend(note.id, editing)}
            suggest={(text) => lineOffers(note.id, editing, text)}
            linkMenus={{ say: (message) => editing.say(message) }}
            wiki={wiki}
            onAiMarks={ai.onAiMarks}
            grow
          />
          {blank && !typed ? <Ghost scene="new-note" align="center" className={styles.blankGhost} /> : null}
        </div>
        {/* And under its last line, the chapters either side again, to go on from the end of the page (docs/BOOKS.md). */}
        {book && onOpenTitle && shown === 'raw' ? <BookFoot place={book} open={(t) => (onOpenWithin ?? onOpenTitle)(t)} /> : null}
      </div>
      {/* Press and hold in the note: Cut, Copy, Paste, Select all, Add image. */}
      <ContextMenu
        view={view}
        onAddImage={() => void pictures.addPhoto()}
        onPasteImage={pictures.pasteImage}
        say={(message) => toast({ message })}
        onFind={setFinding}
        // The same send a swipe on the item does, where a plugin takes this note's items (a Notion board, a GitHub issue).
        send={itemSend(note.id, editing)}
      />
      {finding !== null && view && shown === 'raw' ? <FindBar view={view} initial={finding} onClose={() => setFinding(null)} /> : null}
      <NoteSettings
        open={settingsOpen}
        noteId={note.id}
        title={title}
        pinned={pinned}
        editing={editing}
        onClose={() => setSettingsOpen(false)}
        name={typed ? { value: title, onChange: renameHere } : undefined}
        view={!wide && shown === 'raw' ? (typed ? (source ? 'mixed' : 'formatted') : prefs.noteView) : undefined}
        onView={typed ? (next) => showSource(next === 'mixed') : chooseView}
        running={ai.runningKind}
        onAi={ai.runAi}
        onFind={
          shown === 'raw'
            ? () => {
                setSettingsOpen(false);
                setFinding('');
              }
            : undefined
        }
        onMakeBoard={shown === 'raw' && settingsOpen && boardFrom(view?.state.doc.toString() ?? body.current) ? makeBoard : undefined}
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
