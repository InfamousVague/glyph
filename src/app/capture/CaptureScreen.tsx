import { Ghost } from '../art/Ghost.tsx';
import { Square } from '@glacier/icons';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { answerHost, endCapture, isLocked, setCapturing } from '../core/host.ts';
import { applyCommandMutation, createNote, getNote, listNotes, newNoteId, noteTitle, setNoteRecording, type Note } from '../core/store.ts';
import { preferences } from '../core/preferences.ts';
import { enqueueRefine, setRecorderLive } from './refine.ts';
import { reviewAvailable, type ReviewHandoff } from '../ai/review.ts';
import { discardRecording, reassignRecording, type Stopped } from './engine.ts';
import { renderNote, type Segment } from './markdown.ts';
import { setLinkTitles } from './spoken/extras.ts';
import { setSpokenFormats } from './spoken/inline.ts';
import { Opening } from './Opening.tsx';
import { QuietWatch } from './quiet.ts';
import type { Placement } from './command.ts';
import { appendToList, placeWords } from './listAppend.ts';
import { listTitle } from './instructionMutation.ts';
import { clipMarkdown, freshTapeId, setTapeId, tapeId } from '../core/clips.ts';
import { commandModel, understandInstructionCommand } from './understand.ts';
import { readInstruction } from '../ai/instruction.ts';
import { ConfirmCard } from '../ai/ConfirmCard.tsx';
import type { RunKind } from '../ai/kinds.ts';
import { appendBlock } from './appendBody.ts';
import { asBoardMarkdown, Take, takeMarkdown, type Offer } from './take.ts';
import { hostThrough, type RouteView, type TableDraft, type TakeHost } from './takeHost.ts';
import { TakeWriter, type NamedNote } from './takeWriter.ts';
import { bookNoteBody, isBookBody } from '../book/book.ts';
import { applyLinks, type SentLink } from '../core/itemLinks.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import { plugins } from '../plugins/registry.ts';
import type { CaptureContext } from '../plugins/types.ts';
import { starters, tipInPause, TIP_AFTER_MS, type Tip } from './tips.ts';
import { SayCard } from './SayCard.tsx';
import { SideKeyWaves } from './SideKeyWaves.tsx';
import { publishVoiceLevel } from './voiceLevel.ts';
import { useSideKeySpot } from './sideKey.ts';
import { LivePage } from './LivePage.tsx';
import { Tail } from './Tail.tsx';
import { counter } from './tape.ts';
import { ListLanding, TableCard, TablePreview } from './CaptureCards.tsx';
import { lingerMs } from './chip.ts';
import { RouteChip } from './RouteChip.tsx';
import { diagnosticsLine, EMPTY_DIAGNOSTICS, soundsSilent, type Diagnostics } from './diagnostics.ts';
import { withFinalWords } from './finalWords.ts';
import { appendsTo, onTape } from './timeline.ts';
import { statusLine, stopHint, whereLine } from './screenText.ts';
import { useCaptureSession } from './useCaptureSession.ts';
import styles from './CaptureScreen.module.css';

/**
 * A note being spoken.
 *
 * One screen for both ways in - the Speak button and the held side key - and
 * it shows one thing: the note taking shape as you say it, on its own page, the
 * spoken cues turning into its marks as they land. A small line at the top says
 * where the words are going; a counter says how long; Discard and Done are the
 * only buttons. Until the first words arrive, a card of things to say and the
 * ghost listening are the page, so the microphone being live is visible before
 * a word has been understood.
 *
 * The microphone opens before anything else is ready, and the model loads while
 * it listens (useCaptureSession.ts): the first words of a voice note are usually
 * its subject.
 *
 * The note is written at Done, from the final transcript read once (PR #1):
 * a committed phrase only shows on the page, so a partial phrase can never
 * route a command or write a note. The sound is kept as it is recorded under
 * an id chosen at mount, so the phone killing the app mid-sentence loses no
 * audio; a cancel deletes it; Done, or a confirmed command, writes the note.
 * Every write to a note goes through one chain (takeWriter.ts).
 *
 * A recording from the Speak button or the side key is a new note; a note's own Speak adds to that note.
 *
 * Done goes back to the list, whatever started the capture: the new note is at
 * the top, a tap away, and a locked phone has already stepped back behind its
 * lock screen without showing the note to whoever is holding it.
 *
 * The pieces are their own modules: the cards (CaptureCards.tsx), the chip (RouteChip.tsx), the lines of words that
 * are not the note (screenText.ts), the diagnostics line (diagnostics.ts), the last words of a stopped decode
 * (finalWords.ts) and where the take sits on its note's tape (timeline.ts). This screen ties them to the take
 * (take.ts), which decides.
 */

interface CaptureScreenProps {
  /** Opened by the side key, where the OS has already buzzed. */
  fromAssistant: boolean;
  /** Counts side-key presses during this capture: each one after the first means "stop and save". */
  stopRequests?: number;
  /** Talking into this note (its Speak): the words go on its end. */
  noteId?: string;
  /**
   * The take is over. `note` is the saved note, or null when the capture was cancelled or nothing was said. `review`
   * is set when the review after a recording should look at it (ai/review.ts); `ask` when the words were an
   * instruction about the note being continued, to run once it is open.
   */
  onFinish: (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk) => void;
}

/** A spoken instruction about the note being continued ("hey Ghost, fix the spelling"): run on it once it is open (ai/instruction.ts). */
export interface SpokenAsk {
  kind: RunKind;
  instruction?: string;
}

/** How long a quiet after words has to last before "Stop when I go quiet" saves the take. */
const QUIET_STOP_MS = 4000;

/**
 * The sound of a take that is not being kept: an instruction, a refused command, a command sent elsewhere or
 * cancelled. Its file goes, unless the take was put on the end of a continued note's own tape (`ownTape`): the stop has
 * already added it there, and that file is the whole of the note's tape, not the take's. There the sound stays, and the
 * note is told the tape's new length with its phrases as they were, so the next take's words still line up with their
 * sound - the same as a take that said nothing. (Deleting it lost the note's whole recording: a take said into a note
 * that had one, "Hey Ghost, fix the spelling", then Done, and the file was gone.)
 */
async function letGo(recordedAs: string, recordedMs: number | null, ownTape: Note | null): Promise<void> {
  if (!ownTape) {
    await discardRecording(recordedAs).catch(() => undefined);
    return;
  }
  if (recordedMs === null) return;
  await setNoteRecording(ownTape.id, recordedMs, ownTape.segments ?? []).catch((failure: unknown) => console.warn('[glyph] recording not kept:', failure));
}

export function CaptureScreen({ fromAssistant, stopRequests = 0, noteId: aimedAt, onFinish }: CaptureScreenProps) {
  /** The note this capture is being added to, if it continues one, as the page shows it (`writer.target` is the truth). */
  const [target, setTarget] = useState<Note | null>(null);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [partial, setPartial] = useState('');
  /** Milliseconds on the recording, copied from the session a few times a second. */
  const [recorded, setRecorded] = useState(0);
  const [diagnostics, setDiagnostics] = useState<Diagnostics>(EMPTY_DIAGNOSTICS);
  const [showDiagnostics, setShowDiagnostics] = useState(false);

  // Mirrors the render state reads at Done, which runs after the last events
  // have landed but before React has necessarily re-rendered with them.
  const segmentsRef = useRef<Segment[]>([]);
  const meterRef = useRef<HTMLDivElement>(null);
  const screenRef = useRef<HTMLDivElement>(null);
  /** The line at the top: a pane the note's page runs under (app.css .app-headerPane), so the wisp sits below it. */
  const topRef = useRef<HTMLDivElement>(null);
  // Its height, for the body to keep clear of it in the states that aren't the page (`--recorder-top`).
  useEffect(() => {
    const top = topRef.current;
    const screen = screenRef.current;
    if (!top || !screen) return undefined;
    const fit = () => screen.style.setProperty('--recorder-top', `${top.offsetHeight}px`);
    fit();
    const watched = new ResizeObserver(fit);
    watched.observe(top);
    return () => watched.disconnect();
  }, []);
  /** Set when "Stop when I go quiet" is on: watches for the end of talking. */
  const quiet = useRef(preferences().quietStop ? new QuietWatch(QUIET_STOP_MS) : null);
  /** Whether this phone stops a recording when the side key is pressed (generation 12). */
  const [pressStops, setPressStops] = useState(false);
  const spot = useSideKeySpot();

  /** The notes a spoken "add to …" can name, most recent first; loaded as the capture opens. */
  const candidates = useRef<NamedNote[]>([]);
  /**
   * The routing chip: a note being named while it is still being said, then
   * the note the words moved to (or a name that matched nothing).
   */
  const [route, setRoute] = useState<RouteView>(null);
  /** Bumped when words move to another note, to replay the lines writing out. */
  const [moves, setMoves] = useState(0);
  /** The words as they looked just before a move, sliding away. */
  const [ghost, setGhost] = useState<{ markdown: string; key: number } | null>(null);
  /** The phone's command model, once looked up; null without one, and the rules alone read commands. */
  const commandModelId = useRef<string | null>(null);
  useEffect(() => {
    let live = true;
    void commandModel().then((id) => {
      if (live) commandModelId.current = id;
    });
    return () => {
      live = false;
    };
  }, []);
  /** "Glyph, add a table to …": the table being asked for, column labels first, then row by row. */
  const [tableView, setTableView] = useState<TableDraft<Note> | null>(null);
  /** What a command will do once it is confirmed, by "yes" or a tap. */
  const [pending, setPendingView] = useState<Offer<Note> | null>(null);
  const [tables, setTables] = useState<string[]>([]);
  const [asBoard, setAsBoard] = useState(false);
  /** The tape this take writes to: the continued note's, or a new one (core/clips.ts). Read once, when it is first needed. */
  const takeTape = useRef<string | null>(null);
  /** Every phrase the fast model heard, commands and all, for the review to check against a second listen. */
  const heardRef = useRef<string[]>([]);
  /** What each command did, or didn't, in words: the review checks them. */
  const commandLog = useRef<string[]>([]);
  /** The last thing said, for plugin commands like "send that to Notion": a phrase of this take, or items added to another note. */
  const lastSaid = useRef<{ kind: 'take'; text: string } | { kind: 'items'; noteId: string; lines: string[] } | null>(null);
  /** When words were last heard, for the tips in a pause. */
  const lastHeard = useRef(performance.now());
  const [tip, setTip] = useState<Tip | null>(null);
  /** The notes have been read into `candidates`: the card of things to say can name one (SayCard.tsx). */
  const [notesRead, setNotesRead] = useState(false);
  const tipTurn = useRef(0);
  const finished = useRef(false);
  /** A stopped command is awaiting its explicit confirmation; its words never become a note. */
  const finalCommand = useRef<{
    note: Note | null;
    /** "Make a new list called … and add …": the note to create on confirmation, instead of one to add to. */
    create?: { title: string; items: readonly string[] };
    locked: boolean;
    temporaryId: string;
    recordedMs: number | null;
    /** The continued note whose own tape the take was added to the end of, or null: its sound is never moved or removed (`letGo`). */
    ownTape: Note | null;
  } | null>(null);

  const titled = target === null;
  /** While an item for another note is being said, its words show in the chip, not in this note. */
  const [itemWords, setItemWords] = useState('');
  /** Words of this take a plugin linked to something (a Notion task): links wherever the cues put them. */
  const [sentLinks, setSentLinks] = useState<SentLink[]>([]);
  const sentLinksRef = useRef<SentLink[]>([]);
  // The page as it is spoken: the take's markdown, from what React holds of it, with the phrase still being guessed.
  const note = useMemo(
    () =>
      takeMarkdown(
        { segments, tables, asBoard },
        { titled, partial: itemWords ? '' : partial, link: sentLinks.length ? (text) => applyLinks(text, sentLinks) : undefined, board: asBoardMarkdown },
      ),
    [segments, partial, titled, itemWords, sentLinks, tables, asBoard],
  );

  // The switched-on plugins' formattings can be said like bold ("spoiler … end spoiler"); read as the recorder opens,
  // before the first render lays the page out with them.
  useState(() => setSpokenFormats(plugins.formats().flatMap((format) => (format.cue ? [{ word: format.cue, delimiter: format.delimiter }] : []))));

  // No background pass over an earlier recording while this one is live: same cores.
  useEffect(() => {
    setRecorderLive(true);
    return () => setRecorderLive(false);
  }, []);

  // The screen stays on while this runs, and pressing the side key (which
  // turns it off) stops it: the only sign of the key Android gives an app.
  useEffect(() => {
    setPressStops(setCapturing(true));
    return () => void setCapturing(false);
  }, []);

  // What the take asks of the recorder, filled in below. Through a ref, so the take (made once) always reaches the
  // newest render's code (takeHost.ts `hostThrough`).
  const hostImpl = useRef<TakeHost<Note>>(null!);
  const [take] = useState(() => new Take<Note>(hostThrough(hostImpl)));
  /** The note this take is written into, and the one chain every write to a note joins. */
  const [writer] = useState(
    () =>
      new TakeWriter({
        markdown: (asTitled) => take.markdown({ titled: asTitled, link: (text) => applyLinks(text, sentLinksRef.current), board: asBoardMarkdown }),
        // Any phrase at all, where Done asks `take.hasContent`: a draft writes the take as it stands, and one that lays
        // out as nothing writes the note's own text back as it was (appendBody.ts), so the looser rule costs nothing.
        hasWords: () => take.segments.length > 0 || take.tables.length > 0 || take.clips.length > 0,
        candidates: () => candidates.current,
        targetChanged: setTarget,
      }),
  );

  // ---- which note --------------------------------------------------------------------
  // A note's own Speak aims the recording at that note; otherwise it is a new one.
  useEffect(() => {
    let current = true;
    const chosen = aimedAt ? getNote(aimedAt).catch(() => null) : Promise.resolve<Note | null>(null);
    void chosen.then((found) => {
      // Found after a draft was already written to a new note: stay with that one.
      if (!current || !found || writer.savedDraft || finished.current) return;
      writer.aim(found);
    });
    return () => {
      current = false;
    };
    // Decided once, as the capture opens: a new capture is a new mount.
  }, [aimedAt, writer]);

  // The notes "add to …" can name. Read once: a capture lasts minutes, and a
  // note made meanwhile is not one someone will name mid-sentence.
  useEffect(() => {
    let current = true;
    void listNotes()
      .then((all) => {
        if (!current) return;
        candidates.current = all
          .filter((n) => !n.archivedAt)
          .sort((a, b) => b.updatedAt - a.updatedAt)
          .map((note) => ({ id: note.id, title: noteTitle(note.body), note }))
          .filter((c) => c.title);
        // "Note link weekend trip end link" takes the note's own spelling.
        setLinkTitles(candidates.current.map((c) => c.title));
        setNotesRead(true);
      })
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, []);

  /**
   * The take carries on in `chosen`, or in a new note: what was said so far stays on the note it was said for,
   * written now, and the take starts afresh (take.fork). "New note", on a capture aimed at a note.
   */
  const carryOn = useCallback(
    async (chosen: Note | null) => {
      await writer.flushDraft();
      take.fork();
      writer.keepDraft();
      // The take's tape is the note it ends on: a note with a recording takes it on the end of its own.
      takeTape.current = null;
      if (chosen) {
        const full = (await getNote(chosen.id).catch(() => null)) ?? chosen;
        writer.aim(full);
        setRoute({ phase: 'moved', title: noteTitle(full.body) || 'that note' });
      } else {
        writer.aim(null);
      }
      setMoves((n) => n + 1);
    },
    [take, writer],
  );

  /** "New note": a fresh one from here; with a `title`, one already named. */
  const startNewNote = useCallback(
    async (title?: string) => {
      if (!title) {
        await carryOn(null);
        fireNativeHaptic('selection');
        return;
      }
      const named = listTitle(title);
      const result = await applyCommandMutation({
        mutationId: newNoteId(),
        noteId: newNoteId(),
        kind: 'create',
        beforeRevision: null,
        beforeBody: null,
        afterBody: named,
        source: 'capture',
      });
      if (result.status === 'conflict') {
        setRoute({ phase: 'said', text: 'That note could not be created safely.' });
        return;
      }
      const made = result.note;
      candidates.current = [{ id: made.id, title: named, note: made }, ...candidates.current];
      await carryOn(made);
    },
    [carryOn],
  );

  /**
   * "Add to <note>": this capture's words move to `note` and carry on there.
   * Everything said in this take goes, so "oat milk, add to shopping" and
   * "add to shopping, oat milk" land the same. The words slide away, the
   * note's last lines show, and the take is written out below them.
   */
  const routeTo = useCallback(
    async (chosen: Note) => {
      setRoute({ phase: 'moved', title: noteTitle(chosen.body) || 'that note' });
      fireNativeHaptic('success');
      if (chosen.id === writer.noteId) return;
      setGhost({ markdown: renderNote(segmentsRef.current, '', { titled: !writer.target }).markdown, key: Date.now() });
      await writer.undoDraft();
      // The full note, for its recording and phrases: this take's tape goes on the end of them.
      const full = (await getNote(chosen.id).catch(() => null)) ?? chosen;
      writer.aim(full);
      setMoves((n) => n + 1);
      // The next draft save writes the words so far to the note.
      setSegments([...segmentsRef.current]);
    },
    [writer],
  );

  // The moved chip and the sliding words have their moment, then go.
  useEffect(() => {
    const ms = lingerMs(route);
    if (ms === null) return undefined;
    const timer = window.setTimeout(() => setRoute(null), ms);
    return () => window.clearTimeout(timer);
  }, [route]);
  useEffect(() => {
    if (!ghost) return undefined;
    const timer = window.setTimeout(() => setGhost(null), 520);
    return () => window.clearTimeout(timer);
  }, [ghost]);

  /** Words arrived: a tip showing goes, and the next pause gets the next one. */
  const heard = () => {
    lastHeard.current = performance.now();
    setTip((showing) => {
      if (showing) tipTurn.current += 1;
      return null;
    });
  };

  // ---- the microphone and the transcriber (useCaptureSession.ts) ----------------------
  const { phase, setPhase, engine, download, error, setError, session, microphone, counts } = useCaptureSession({
    fromAssistant,
    isFinished: () => finished.current,
    events: {
      onPartial: (text) => {
        if (text) {
          quiet.current?.words(performance.now());
          heard();
        }
        // A partial is display only.  It cannot influence routing or a
        // model prompt before Whisper has committed the final transcript.
        setPartial(text);
      },
      onSegment: (raw) => {
        quiet.current?.words(performance.now());
        heard();
        heardRef.current.push(raw.text);
        take.listen(raw);
        setPartial('');
      },
      onLevel: (level, rms) => {
        // Straight to a custom property: five updates a second is too many
        // React renders for a meter nobody reads precisely. The screen
        // carries it too, for the side key's rings to swell with.
        meterRef.current?.style.setProperty('--level', String(level));
        screenRef.current?.style.setProperty('--level', String(level));
        publishVoiceLevel(level);
        quiet.current?.level(rms, performance.now());
      },
    },
  });

  // ---- commands: "Glyph", then what to do, then yes or no (capture/take.ts) ----------

  const commandWordOn = () => preferences().commandWord;

  /**
   * Items spoken for another note's list go straight into that note: its last
   * list grows by them, in its own style, while this take carries on where it
   * was. The chip and the landing preview show the lines arriving.
   */
  const addItems = async (note: Note, spoken: string, { how, task, many, target = null, near, items }: Placement) => {
    try {
      // The offer was made from this exact note snapshot. Confirmation is a
      // compare-and-swap, so a later edit or delete wins instead of being
      // overwritten by the voice command.
      const placed = placeWords(note.body, spoken, { how, task, many, near, items });
      if (!placed.added.length) return;
      const result = await applyCommandMutation({
        mutationId: newNoteId(),
        noteId: note.id,
        kind: 'append',
        beforeRevision: note.revision ?? 1,
        beforeBody: note.body,
        afterBody: placed.body,
        source: note.source,
      });
      if (result.status === 'conflict') {
        setRoute({ phase: 'said', text: `${noteTitle(note.body) || 'That note'} changed after the preview, so nothing was added.` });
        fireNativeHaptic('warning');
        return;
      }
      const saved = result.note;
      writer.remember(saved);
      writer.rebase(saved);
      if (writer.target?.id === saved.id) setRoute({ phase: 'done', text: `Added “${withoutLead(placed.added[0] ?? '')}”${placed.added.length > 1 ? ` and ${placed.added.length - 1} more` : ''}` });
      else setRoute({ phase: 'added', title: noteTitle(saved.body) || 'that note', body: saved.body, added: placed.added });
      fireNativeHaptic('success');
      lastSaid.current = { kind: 'items', noteId: saved.id, lines: placed.added };
      if (target) plugins.itemTargets().find((itemTarget) => itemTarget.word === target)?.afterAdd(saved.id, placed.added, captureContext);
    } catch (failure) {
      console.warn('[glyph] item not added:', failure);
      setRoute({ phase: 'missed', title: noteTitle(note.body) || 'that note' });
    }
  };

  // ---- plugins, by voice --------------------------------------------------------------

  /** What a plugin's voice command may do to this take (plugins/types.ts). Refs and setters only, so any render's copy works. */
  const captureContext: CaptureContext = {
    noteId: () => writer.noteId,
    lastSaid: () => lastSaid.current,
    said: (text) => {
      lastSaid.current = { kind: 'take', text };
    },
    status: ({ state, lead, title }) => setRoute({ phase: 'plugin', state, lead: lead ?? null, title }),
    link: (text, url) => {
      sentLinksRef.current = [...sentLinksRef.current, { text, url }];
      setSentLinks(sentLinksRef.current);
    },
    append: (markdown) => {
      const at = take.segments[take.segments.length - 1]?.endMs ?? 0;
      take.segments = [...take.segments, { text: markdown, startMs: at, endMs: at }];
      syncTake();
    },
    updateNote: async (id, change) => {
      await writer.updateNote(id, change);
    },
  };

  /** The words switched-on plugins let an item command end a note's name with ("…in Notion"). */
  const itemWordsOfPlugins = () => plugins.itemTargets().map((t) => t.word);

  /** A confirmed table for another note: its own block at the end of that note. */
  const addTable = async (note: Note, title: string, markdown: string) => {
    try {
      const body = await writer.updateNote(note.id, (current) => appendBlock(current, markdown));
      if (body === null) return;
      setRoute({ phase: 'done', text: `Table added to ${title}` });
      fireNativeHaptic('success');
    } catch (failure) {
      console.warn('[glyph] table not added:', failure);
      setRoute({ phase: 'said', text: `The table didn’t go into ${title}.` });
    }
  };

  /**
   * "Hey Ghost, make a book called Field guide": the book note is written beside this take, which carries on where it
   * was, and the book can be named by the next command (docs/BOOKS.md).
   */
  const makeBook = async (title: string, pages: readonly string[]) => {
    try {
      const made = await createNote(newNoteId(), bookNoteBody(title, pages), 'capture');
      candidates.current = [{ id: made.id, title, note: made }, ...candidates.current];
      take.touched.add(made.id);
      setRoute({ phase: 'done', text: `Made the book ${title}` });
      fireNativeHaptic('success');
    } catch (failure) {
      console.warn('[glyph] book not made:', failure);
      setRoute({ phase: 'said', text: `The book ${title} wasn’t made.` });
    }
  };

  /** Which tape this take is part of: the one a continued note holds, or a fresh one for a new file. */
  const tapeOfTake = useCallback((): string => {
    if (!takeTape.current) {
      const continued = writer.target;
      const appending = continued !== null && (continued.recordingMs ?? 0) > 0;
      takeTape.current = (appending ? tapeId(continued.id) : null) ?? freshTapeId();
    }
    return takeTape.current;
  }, [writer]);

  /** The take's segments and tables, copied to what the screen draws. */
  const syncTake = () => {
    segmentsRef.current = take.segments;
    setSegments(take.segments);
    setTables(take.tables);
    setAsBoard(take.asBoard);
  };

  hostImpl.current = {
    notes: () => candidates.current,
    target: () => writer.target,
    commandWord: commandWordOn,
    instructionCommands: () => true,
    voiceCommands: () => plugins.voiceCommands(),
    itemTargets: itemWordsOfPlugins,
    understand: commandModelId.current ? (words) => understandInstructionCommand(words, candidates.current) : undefined,
    route: setRoute,
    offer: setPendingView,
    table: setTableView,
    itemWords: setItemWords,
    haptic: (kind) => fireNativeHaptic(kind),
    changed: syncTake,
    addItems: (target, spoken, placement) => void addItems(target, spoken, placement),
    changeNote: (target, change, title) =>
      void writer.updateNote(target.id, change).then((body) => {
        if (body === null) setRoute({ phase: 'said', text: `${title} didn’t change.` });
        else {
          setRoute({ phase: 'done', text: `Done in ${title}` });
          fireNativeHaptic('success');
        }
      }),
    addTable: (target, title, markdown) => void addTable(target, title, markdown),
    moveTo: (target) => void routeTo(target),
    // A finished recording's "new list" is created by `confirmPending`, not by carrying the capture on into it.
    newNote: (title) => void (finished.current ? undefined : startNewNote(title)),
    newBook: (title, pages) => void makeBook(title, pages),
    runPlugin: (voice, parsed) => voice.run(parsed, captureContext),
    describePlugin: (voice, parsed) => voice.describe(parsed, captureContext),
    clip: (span) => {
      // The tape a continued note already has comes first, so the clip points at the right sound in the whole recording.
      const offset = writer.target?.recordingMs ?? 0;
      return clipMarkdown({ startMs: span.startMs + offset, endMs: span.endMs + offset, tape: tapeOfTake() });
    },
    log: (line) => commandLog.current.push(line),
    said: (text) => {
      lastSaid.current = { kind: 'take', text };
    },
  };

  const confirmPending = () => {
    take.confirm(performance.now());
    const final = finalCommand.current;
    if (!final) return;
    finalCommand.current = null;
    void writer.settled().then(async () => {
      let saved = final.create ? await createFinalList(final.create.title, final.create.items) : final.note ? await getNote(final.note.id).catch(() => final.note) : null;
      if (final.ownTape) {
        // The take is on the end of the continued note's own tape, and stays there: moving the file would move the
        // whole of that note's recording onto the command's note.
        await letGo(final.temporaryId, final.recordedMs, final.ownTape);
        if (saved?.id === final.ownTape.id) saved = (await getNote(saved.id).catch(() => saved)) ?? saved;
      } else if (saved && final.recordedMs !== null) {
        const recordingMs = await reassignRecording(final.temporaryId, saved.id, (saved.recordingMs ?? 0) > 0).catch(() => null);
        if (recordingMs !== null) saved = (await setNoteRecording(saved.id, recordingMs, saved.segments ?? []).catch(() => saved)) ?? saved;
      } else if (final.recordedMs !== null) {
        void discardRecording(final.temporaryId).catch(() => undefined);
      }
      endCapture(final.locked);
      onFinish(saved, final.locked);
    });
  };
  /** The confirmed new list of a finished recording: its title, then its items as a list. */
  const createFinalList = async (title: string, items: readonly string[]): Promise<Note | null> => {
    const named = listTitle(title);
    const result = await applyCommandMutation({
      mutationId: newNoteId(),
      noteId: newNoteId(),
      kind: 'create',
      beforeRevision: null,
      beforeBody: null,
      afterBody: items.length ? appendToList(named, items).body : named,
      source: 'capture',
    }).catch(() => null);
    if (result?.status !== 'applied') {
      setRoute({ phase: 'said', text: 'That list could not be created safely.' });
      return null;
    }
    return result.note;
  };
  /** Cancel tapped on the card: a no, as a spoken one is. */
  const cancelPending = (why: string | null) => {
    take.cancel(why, performance.now(), 'declined');
    const final = finalCommand.current;
    if (!final) return;
    finalCommand.current = null;
    void letGo(final.temporaryId, final.recordedMs, final.ownTape);
    endCapture(final.locked);
    onFinish(null, final.locked);
  };
  const finishTable = () => take.finishTable(performance.now());
  const cancelTable = (why: string | null) => take.cancelTable(why);

  // ---- the counter ---------------------------------------------------------------
  useEffect(() => {
    if (phase !== 'listening') return undefined;
    const timer = window.setInterval(() => {
      setRecorded(session.current?.positionMs() ?? 0);
      setDiagnostics({ ...counts.current });
      const now = performance.now();
      // A command being said, or waiting for its yes, holds the recording open. Once the recording is over, the card of
      // the command read from it waits for a tap: the take's clock gives up on a question it could hear answered, and
      // with the microphone stopped a dropped card left Done, Discard and back all refusing a take already finished.
      const commanding = take.commanding;
      if (!finished.current) take.tick(now);
      if (!commanding && quiet.current?.due(now)) void finishRef.current();
      // A pause, once there are words: one tip, until words come again. Before the first word the card of things to
      // say is up instead (SayCard.tsx), and a tip picked under it would be spent unseen.
      if (heardRef.current.length && now - lastHeard.current > TIP_AFTER_MS) {
        setTip(
          (showing) =>
            showing ??
            tipInPause({
              notes: candidates.current,
              own: writer.noteId,
              target: writer.target,
              keyword: commandWordOn(),
              pluginTips: (recent) => plugins.tips(recent),
              turn: tipTurn.current,
            }),
        );
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, [phase, take, writer, session, counts]);

  // No draft timer: phrase commits are display-only.  The complete transcript
  // is saved exactly once after final instruction classification.

  // ---- ending ----------------------------------------------------------------------
  const finish = useCallback(async () => {
    if (finished.current) return;
    finished.current = true;
    setCapturing(false);
    setPhase('finishing');
    microphone.current?.stop();
    // The tape is kept under the note's id, added to the end of the continued
    // note's tape when there is one, so its words and its sound stay one timeline (timeline.ts).
    const continued = writer.target;
    const append = appendsTo(continued);
    const ownTape = continued && append ? continued : null;
    let stopped: Stopped = { recordedMs: null, transcript: null };
    try {
      stopped = (await session.current?.stop({ recordAs: writer.noteId, append })) ?? stopped;
    } catch (failure) {
      setError(failureText(failure));
    }

    const committed = take.segments;
    // Native's stop-time result includes words whose phrase event was still in
    // flight when `stop()` detached event listeners. It is the one transcript
    // command classification may inspect; browser/simulated engines fall back
    // to their committed phrases because they explicitly return null.
    const transcript = stopped.transcript ?? committed.map((segment) => segment.text).join(' ').trim();
    const spoken = withFinalWords(committed, stopped.transcript, session.current?.positionMs() ?? committed.at(-1)?.endMs ?? 0);
    for (const segment of spoken.slice(committed.length)) {
      // `listen` remains display-only, so completing the ordinary-note stream
      // here cannot revive phrase-level routing or execution.
      take.listen(segment);
      heardRef.current.push(segment.text);
    }
    const locked = isLocked();

    // The one reader for a spoken instruction (ai/instruction.ts).
    const read = await readInstruction(transcript, candidates.current);
    if (read.kind === 'command') {
      // The stopped audio is already retained under this capture id.  The
      // mutation remains pending until this card is explicitly confirmed.
      take.offerFinal(read.plan, performance.now());
      const aimed = read.plan.kind === 'place' ? read.plan.note.note : null;
      const create = read.plan.kind === 'create-list' ? { title: read.plan.title, items: read.plan.items ?? [] } : undefined;
      finalCommand.current = { note: aimed, ...(create ? { create } : {}), locked, temporaryId: writer.noteId, recordedMs: stopped.recordedMs, ownTape };
      setPhase('listening');
      return;
    }
    if (read.kind === 'reject') {
      // Unsupported, destructive, ambiguous, and missing-target command
      // shapes fail closed: do not create a note containing command prose.
      setRoute({ phase: 'said', text: read.reason });
      await letGo(writer.noteId, stopped.recordedMs, ownTape);
      await writer.undoDraft();
      endCapture(locked);
      onFinish(null, locked);
      return;
    }
    if ((read.kind === 'run' || read.kind === 'ask') && continued && !locked) {
      // "Hey Ghost, fix the spelling", said into a note: the words are an instruction, not the note's, and the note
      // opens with the run on it (shell/useCaptureRoute.ts, editor/NoteScreen.tsx). The recording of the instruction goes,
      // unless it went on the end of the note's own tape (`letGo`).
      await letGo(writer.noteId, stopped.recordedMs, ownTape);
      await writer.undoDraft();
      endCapture(locked);
      onFinish(continued, locked, undefined, read.kind === 'run' ? { kind: read.run } : { kind: 'ask', instruction: read.instruction });
      return;
    }
    if (read.kind === 'words' && read.notice) setRoute({ phase: 'said', text: read.notice });

    // A command's change still landing, or the take carrying on elsewhere: written before the note is.
    await writer.settled();

    // Nothing that lays out as anything - no words, no table, no voice memo - leaves nothing behind. Asked of the
    // laid-out words (take.hasContent), not the transcript: a cue said alone ("Bullet point.", or Whisper echoing its
    // prompt on silence) is held for a sentence that never comes, and saved from the transcript it made an empty note.
    if (!take.hasContent) {
      // The stop has already kept the take's sound. On the end of a continued note's tape it stays, and the tape's new
      // length is kept with the note's phrases as they were, so the next take's words still line up with their sound;
      // a new note's goes with the note that is not made. A continued note's own file is never removed here: it is the
      // whole of that note's tape.
      if (stopped.recordedMs !== null) {
        if (continued && append) {
          await setNoteRecording(continued.id, stopped.recordedMs, continued.segments ?? []).catch((failure: unknown) => console.warn('[glyph] recording not kept:', failure));
        } else if (!continued) {
          await discardRecording(writer.noteId).catch(() => undefined);
        }
      }
      await writer.undoDraft();
      endCapture(locked);
      onFinish(null, locked);
      return;
    }

    const markdown = take.markdown({ titled: !writer.target, link: (text) => applyLinks(text, sentLinksRef.current), board: asBoardMarkdown });
    const saved = await writer.queue(async () => writer.persist(writer.noteId, await writer.compose(markdown), 'capture'));
    let refineJob: ReviewHandoff['job'] = null;
    if (stopped.recordedMs !== null && session.current?.keepsAudio) {
      // New phrases sit after the continued tape's, shifted by its length.
      const tape = onTape(continued, take, spoken);
      await setNoteRecording(saved.id, stopped.recordedMs, tape.segments).catch((failure: unknown) => console.warn('[glyph] recording not kept:', failure));
      // The tape this take wrote to, so its voice memos know it again when the note is opened (core/clips.ts).
      setTapeId(saved.id, tapeOfTake());
      // The better words: the larger model over this take's recording, later,
      // or now in the review after a recording when that runs.
      const base = continued ? ((await writer.baseBody) ?? continued.body) : '';
      refineJob = {
        id: saved.id,
        fromMs: tape.fromMs,
        recordingMs: stopped.recordedMs,
        baseBody: base,
        savedBody: saved.body,
        titled: !continued,
        priorSegments: tape.prior,
        promptTail: renderNote(tape.prior).plain.slice(-200),
        skip: tape.skip,
        // The voice memos this take left: the better words never heard them, and they go back where they were.
        clips: tape.clips,
        keywordAt: tape.keywordAt,
      };
    }
    fireNativeHaptic('success');
    endCapture(locked);
    // The review after a recording: it runs the better words and the formatting when it is done.
    // Not over a locked phone, whose note is not shown to whoever is holding it.
    if (!locked && (await reviewAvailable())) {
      onFinish(saved, locked, { noteId: saved.id, job: refineJob, heard: heardRef.current.join(' '), commands: [...commandLog.current], touched: [...take.touched] });
      return;
    }
    if (refineJob) enqueueRefine(refineJob);
    onFinish(saved, locked);
  }, [onFinish, take, writer, tapeOfTake, session, microphone, setPhase, setError]);

  // The side key held again: Done.
  useEffect(() => {
    if (stopRequests) void finish();
    // Only a new press should act, not a re-created callback.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stopRequests]);

  // The side key pressed: the screen went off, so the take is saved as Done
  // would save it. Always the newest `finish`, through a ref, so the handler
  // is registered once.
  const finishRef = useRef(finish);
  finishRef.current = finish;
  useEffect(() => answerHost('screenOff', () => void finishRef.current()), []);

  const cancel = useCallback(async () => {
    if (finished.current) return;
    finished.current = true;
    setCapturing(false);
    session.current?.cancel();
    microphone.current?.stop();
    await writer.undoDraft();
    const locked = isLocked();
    endCapture(locked);
    onFinish(null, locked);
  }, [onFinish, writer, session, microphone]);

  // The phone's back gesture ends the take the way Done does: what was said
  // is kept, and a take with nothing in it leaves nothing behind.
  useBack(true, () => void finish());

  // ---- the line at the top -----------------------------------------------------------
  const locked = isLocked();
  /*
   * The card of things to say while the microphone waits (SayCard.tsx, capture/tips.ts `starters`). Worked out at
   * render rather than once: which note it names must not be the one being written to (the note's own Speak, or the
   * one the take just moved to), over the lock screen it names none, as the rest of the page keeps the note's words
   * off it, and the asks are offered only where an ask said first is run - a note's own Speak, unlocked (`finish`).
   */
  const say = useMemo(() => {
    const own = target?.id ?? writer.noteId;
    const others = locked || !notesRead ? [] : candidates.current.filter((c) => c.id !== own);
    return starters({
      noteTitle: others[0]?.title ?? null,
      keyword: commandWordOn(),
      book: others.find((c) => isBookBody(c.note.body))?.title ?? null,
      asking: target !== null && !locked,
    });
    // `candidates` is a ref and `writer.noteId` a field: `notesRead` says when the first was filled, `moves` when the second changed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, locked, notesRead, moves]);
  const status = statusLine({ phase, error, download, heardWords: segments.length > 0 });

  // A capture that has heard a while and produced nothing is the one worth
  // explaining without being asked: the line that diagnosed the Fold.
  const silent = soundsSilent(engine, diagnostics);
  const hasWords = note.markdown.length > 0;

  return (
    <div className={styles.screen} data-phase={phase} ref={screenRef}>
      {fromAssistant && (phase === 'starting' || phase === 'listening') ? <SideKeyWaves spot={spot} /> : null}
      <div ref={topRef} className={`app-headerPane ${styles.top}`} role="status" aria-live="polite">
        {status ? (
          <span className={styles.where}>{status}</span>
        ) : (
          <>
            {/* Tapping the line shows what the pipeline has done, for diagnosing a silent capture. */}
            <button type="button" className={`app-word ${styles.where}`} onClick={() => setShowDiagnostics((on) => !on)}>
              {whereLine(target, locked)}
            </button>
            {target ? (
              <button type="button" className={`app-word ${styles.newNote}`} onClick={() => void startNewNote()}>
                New note
              </button>
            ) : null}
          </>
        )}
        <span className={styles.counter} aria-label={`Recorded ${counter(recorded)}`}>
          {counter(recorded)}
        </span>
      </div>

      <div className={styles.body}>
        {ghost ? (
          <div key={`ghost-${ghost.key}`} className={styles.ghost} aria-hidden="true">
            <Tail markdown={ghost.markdown} pendingFrom={null} />
          </div>
        ) : null}
        {route?.phase === 'added' ? (
          <ListLanding key={`landing-${route.added.join('|')}`} title={route.title} body={route.body} added={route.added} />
        ) : phase === 'failed' && !hasWords ? (
          <div className={styles.empty}>
            <Opening failed />
            <p className={styles.lead}>Nothing was recorded.</p>
          </div>
        ) : (
          // The note's own page, its older text above and the words written onto its end (LivePage.tsx). Over the lock
          // screen the note being continued shows none of its text.
          <LivePage
            // The editor reads its placeholder once, so the page is remade when the recorder is up: "Say which note." after "Starting…".
            key={`page-${target?.id ?? 'new'}-${moves}-${phase === 'starting' ? 'starting' : 'up'}`}
            base={target && !locked ? target.body : ''}
            markdown={note.markdown}
            under={topRef}
            placeholder={phase === 'starting' ? 'Starting…' : 'Start talking.'}
          />
        )}
        {!hasWords && phase === 'listening' && !route ? <Ghost scene="listening" align="center" className={styles.listenGhost} /> : null}
        {!hasWords && phase !== 'failed' && route?.phase !== 'added' ? <p className={styles.pageHint}>{stopHint(fromAssistant, pressStops, quiet.current !== null)}</p> : null}
      </div>

      {tableView ? (
        <TableCard draft={tableView} heard={itemWords} onDone={finishTable} onCancel={() => cancelTable(null)} />
      ) : pending ? (
        <ConfirmCard
          offer={pending}
          onConfirm={confirmPending}
          onCancel={() => cancelPending(null)}
          hint="Or say “yes” or “no”."
          table={pending.kind === 'table' ? <TablePreview columns={pending.columns} rows={pending.rows} /> : undefined}
        />
      ) : route ? (
        <RouteChip route={route} itemWords={itemWords} />
      ) : !hasWords && phase === 'listening' ? (
        // Before the first word: the whole of what can be said, as a card (SayCard.tsx); once talking has begun, one tip at a time in a pause.
        <SayCard starters={say} />
      ) : tip && phase === 'listening' ? (
        <p key={tip.say} className={styles.tip}>
          Say <strong>“{tip.say}”</strong> {tip.does}.
        </p>
      ) : null}

      {showDiagnostics || silent || diagnostics.errors ? <p className={styles.diagnostics}>{diagnosticsLine(engine, diagnostics)}</p> : null}

      <footer className={styles.footer}>
        <button type="button" className="app-word" onClick={() => void cancel()} disabled={phase === 'finishing'}>
          Discard
        </button>
        <button
          type="button"
          className={`app-pill ${styles.done}`}
          onClick={() => void finish()}
          disabled={phase === 'failed' || phase === 'finishing'}
          aria-label="Stop and save"
        >
          <div className={styles.meter} ref={meterRef} aria-hidden="true" />
          <Square size={16} aria-hidden="true" />
          Done
        </button>
      </footer>
    </div>
  );
}
