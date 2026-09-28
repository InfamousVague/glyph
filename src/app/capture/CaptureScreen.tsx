import { Ghost } from '../art/Ghost.tsx';
import { Square } from '@glacier/icons';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { answerHost, endCapture, isLocked, setCapturing } from '../core/host.ts';
import { isAndroid } from '../core/platform.ts';
import { applyCommandMutation, createNote, getNote, listNotes, newNoteId, noteTitle, setNoteRecording, type Note } from '../core/store.ts';
import { capitalise } from '../core/text.ts';
import { LONG_NOTE_MS, preferences, setPreferences } from '../core/preferences.ts';
import { enqueueRefine, setRecorderLive } from './refine.ts';
import { enqueueSummary } from '../ai/summaries.ts';
import { reviewAvailable, type ReviewHandoff } from '../ai/review.ts';
import { discardRecording, reassignRecording, type Stopped } from './engine.ts';
import { renderNote, renderTranscript, type Segment } from './markdown.ts';
import { meetingBody, meetingTitle } from './meeting.ts';
import { setLinkTitles } from './spoken/extras.ts';
import { setSpokenFormats } from './spoken/inline.ts';
import { Opening } from './Opening.tsx';
import { QuietWatch } from './quiet.ts';
import type { Placement } from './command.ts';
import { appendToList, placeWords } from './listAppend.ts';
import { listTitle } from './instructionMutation.ts';
import { freshTapeId, setTapeId, tapeId } from '../core/clips.ts';
import { bareWords, readInstruction } from '../ai/instruction.ts';
import { ConfirmCard } from '../ai/ConfirmCard.tsx';
import type { RunKind } from '../ai/kinds.ts';
import { Take, takeMarkdown, type Offer } from './take.ts';
import { hostThrough, type RouteView, type TakeHost } from './takeHost.ts';
import { TakeWriter, type NamedNote } from './takeWriter.ts';
import { chaptersOf, isBookBody } from '../book/book.ts';
import { linkFor } from '../share/share.ts';
import { sameTitle } from '../editor/wikiLinks.ts';
import { withoutLead } from '../core/itemSyntax.ts';
import { plugins } from '../plugins/registry.ts';
import { starters, tipInPause, TIP_AFTER_MS, type Tip } from './tips.ts';
import { SayCard } from './SayCard.tsx';
import { SideKeyWaves } from './SideKeyWaves.tsx';
import { publishVoiceLevel } from './voiceLevel.ts';
import { useSideKeySpot } from './sideKey.ts';
import { LivePage } from './LivePage.tsx';
import { counter } from './tape.ts';
import { ListLanding, NoteChoiceCard } from './CaptureCards.tsx';
import { findKeyword, findMisheard } from './command.ts';
import type { CaptureLanding } from './landing.ts';
import { inOrder, LiveRoute, withoutWords, type LiveCard, type LiveContext, type LiveStep } from './liveRoute.ts';
import { END, placeTake, placingFor, type Placing } from './place.ts';
import { withoutCommands } from './refineText.ts';
import { opensSend, takeBackAt } from './takeBack.ts';
import { lingerMs } from './chip.ts';
import { RouteChip } from './RouteChip.tsx';
import { diagnosticsLine, EMPTY_DIAGNOSTICS, soundsSilent, type Diagnostics } from './diagnostics.ts';
import { commandCandidates } from './candidates.ts';
import { withFinalWords } from './finalWords.ts';
import { appendsTo, onTape, shifted } from './timeline.ts';
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
 * Each committed phrase is read by the live reader (liveRoute.ts) for one family of command, words for a note you
 * name: "Hey Ghost, add a note to House TODOs" switches the page to that note and writes what is said into its list as
 * it is said (Matt: "open the note, and start live writing to that note"); "add … to X" mid-take sends those words to X.
 * A partial phrase never routes anything. Nothing is stored before Done: each note is then read fresh and written once,
 * through `apply_command` for a note that already existed (takeWriter.ts `writeInto`). Anything else a recording asks
 * for is read once, from the final transcript, at Done (ai/instruction.ts), when the live reader did nothing. The
 * sound is kept as it is recorded, under the id of the note it goes with at the stop, so the phone killing the app
 * mid-sentence loses no audio; a cancel deletes it. Every write to a note goes through one chain (takeWriter.ts).
 *
 * A recording from the Speak button or the side key is a new note, or the note its first command named; a note's own
 * Speak adds to that note.
 *
 * Done opens the note the words went into when it already existed, with an Undo (editor/NoteScreen.tsx); otherwise it
 * goes back to the list, the new note at the top, a tap away. A locked phone has already stepped back behind its lock
 * screen without showing the note to whoever is holding it. The review after a recording (ai/review.ts) runs only
 * for a take under three minutes (core/preferences.ts `LONG_NOTE_MS`): a longer one's transcript would not fit the
 * model's window, so it goes back to the list with its better words to come from the queue, its summary too when
 * Settings says so (ai/summaries.ts), and the Done line says why (docs/DESIGN.md §127 section 2).
 *
 * A MEETING in this recorder (`meeting`, the Mac; §127 section 3) is recorded, not read: no live reader, no reader at
 * Done, no "hey Ghost", no quiet stop, no review, no title from the first sentence, and no card of things to say. The
 * page shows the transcript as paragraphs under the date title (capture/meeting.ts, capture/markdown.ts
 * `renderTranscript`), and Done writes that note, records it as a meeting, and queues its better words and its
 * summary, with the line that says to keep the app open while they come. The card's "Meeting instead", before the
 * first word, turns this recorder into that on the Mac; on a phone with the service it lets the microphone go and
 * hands over (`onMeeting`), since the service's `AudioRecord` and this page's cannot both hold it.
 *
 * The pieces are their own modules: the cards (CaptureCards.tsx), the chip (RouteChip.tsx), the lines of words that
 * are not the note (screenText.ts), the diagnostics line (diagnostics.ts), the last words of a stopped decode
 * (finalWords.ts) and where the take sits on its note's tape (timeline.ts). This screen ties them to the live reader
 * (liveRoute.ts), which reads each phrase, and to the take (take.ts), which holds the words and the card after Done.
 */

interface CaptureScreenProps {
  /** Opened by the side key, where the OS has already buzzed. */
  fromAssistant: boolean;
  /** Counts side-key presses during this capture: each one after the first means "stop and save". */
  stopRequests?: number;
  /** Talking into this note (its Speak): the words go on its end. */
  noteId?: string;
  /**
   * Where in that note the words go, when its opener knows better than its title (place.ts `placingFor`): a journal's
   * entry said aloud goes on from its time, or into its to-do list (book/template.ts `openEnd`). Absent, the note's own.
   */
  placing?: Placing;
  /** A meeting from the start: recorded, not read (the Mac; capture/meeting.ts). */
  meeting?: boolean;
  /**
   * Where a meeting can be recorded (capture/meeting.ts): the card offers "Meeting instead" before the first word. On
   * a phone it is called once this page has let the microphone go, and the caller starts the service; on the Mac the
   * recorder turns into a meeting itself and this is not called.
   */
  onMeeting?: () => void;
  /**
   * The take is over. `note` is the saved note, or null when the capture was cancelled or nothing was said. `review`
   * is set when the review after a recording should look at it (ai/review.ts); `ask` when the words were an
   * instruction about the note being continued, to run once it is open.
   */
  onFinish: (note: Note | null, locked: boolean, review?: ReviewHandoff, ask?: SpokenAsk, landing?: CaptureLanding) => void;
}

/** What was said before "New note", for the note it was said for: written at Done with everything else. */
interface Part {
  note: Note | null;
  /** The note it was written into had been switched to by a command, or was the note's own Speak. */
  title: string | null;
  placing: Placing;
  markdown: string;
  /** The same words titled, for a note of their own if the note they were for changed too much to write into. */
  titled: string;
  noteId: string;
}

/** A one-shot's words for another note ("hey Ghost, add call Sam to House TODOs"), written at Done. */
interface Insert {
  note: Note;
  title: string;
  placing: Placing;
  segments: Segment[];
}

/** A spoken instruction about the note being continued ("hey Ghost, fix the spelling"): run on it once it is open (ai/instruction.ts). */
export interface SpokenAsk {
  kind: RunKind;
  instruction?: string;
}

/** How long a quiet after words has to last before "Stop when I go quiet" saves the take. */
const QUIET_STOP_MS = 4000;

/** How long the recorder stays up at Done for a line saying why nothing was kept, so it can be read. */
const SAID_MS = 1500;

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

export function CaptureScreen({ fromAssistant, stopRequests = 0, noteId: aimedAt, placing: aimedPlacing, meeting: meetingFromStart = false, onMeeting, onFinish }: CaptureScreenProps) {
  /** The note this capture is being added to, if it continues one, as the page shows it (`writer.target` is the truth). */
  const [target, setTarget] = useState<Note | null>(null);
  /** A meeting: from the start, or turned into one from the card before the first word (the Mac). */
  const [meeting, setMeeting] = useState(meetingFromStart);
  const meetingRef = useRef(meetingFromStart);
  meetingRef.current = meeting;
  /** When the meeting began, and the date title it is made with. */
  const meetingStartedAt = useRef(Date.now());
  const meetingTitled = useRef(meetingTitle(meetingStartedAt.current));
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
  /** Set when "Stop when I go quiet" is on: watches for the end of talking. Never for a meeting, whose pauses are the room's. */
  const quiet = useRef(preferences().quietStop && !meetingFromStart ? new QuietWatch(QUIET_STOP_MS) : null);
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
  /** What a command read at Done will do once its card is tapped. */
  const [pending, setPendingView] = useState<Offer<Note> | null>(null);
  /** The tape this take writes to: the continued note's, or a new one (core/clips.ts). Read once, when it is first needed. */
  const takeTape = useRef<string | null>(null);
  /** Every phrase the fast model heard, commands and all, for the review to check against a second listen. */
  const heardRef = useRef<string[]>([]);
  /** What each command did, or didn't, in words: the review checks them. */
  const commandLog = useRef<string[]>([]);
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

  /** The live reader: each committed phrase read for a note named (liveRoute.ts). */
  const [live] = useState(() => new LiveRoute<Note>());
  /** Every committed phrase, commands and all, for the stop's last words to be told apart from (finalWords.ts). */
  const committedRef = useRef<Segment[]>([]);
  /** How many of them came before the last "New note": the reader at Done reads only what was said after it. */
  const forkedAt = useRef(0);
  /** Phrases committed before the notes a command can name were read: read once they are. */
  const queued = useRef<Segment[] | null>([]);
  /** Where the words go in the note the page shows (place.ts), and the document it starts from after a switch. */
  const [placing, setPlacingView] = useState<Placing>(END);
  const [pageFrom, setPageFrom] = useState<string | undefined>(undefined);
  /** A card asking which note (liveRoute.ts `LiveCard`). */
  const [choice, setChoice] = useState<LiveCard<Note> | null>(null);
  /** The take was switched to a note by a command, not opened from its own Speak. */
  const [routed, setRouted] = useState(false);
  /** "New note “House chores”" chosen on a card: the note the take goes to is made at Done, with this title. */
  const [pendingTitle, setPendingTitleView] = useState<string | null>(null);
  const pendingTitleRef = useRef<string | null>(null);
  /** The note whose own Speak this is: where Not this note goes back to. */
  const home = useRef<Note | null>(null);
  const parts = useRef<Part[]>([]);
  const inserts = useRef(new Map<number, Insert>());
  /** A run or an ask said mid-take, for the note that opens after Done, and its words as said. */
  const pendingAsk = useRef<SpokenAsk | null>(null);
  const pendingAskSaid = useRef('');
  /** The lines a confirmed card after Done put in its note, for the note's Undo. */
  const confirmedLines = useRef<string[]>([]);
  const titled = target === null && pendingTitle === null;
  /** While an item for another note is being said, its words show in the chip, not in this note. */
  const [itemWords, setItemWords] = useState('');
  // The page as it is spoken: the take's markdown, from what React holds of it, with the phrase still being guessed.
  // A meeting's page is its transcript, paragraphs under the heading, with no cues read into it.
  const note = useMemo(
    () => (meeting ? { markdown: renderTranscript(segments, partial), pendingFrom: null } : takeMarkdown({ segments }, { titled, partial })),
    [segments, partial, titled, meeting],
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
        markdown: (asTitled) => take.markdown({ titled: asTitled }),
        // For the mid-take drafts, which nothing writes now (takeWriter.ts, docs/DESIGN.md §127): any phrase at all,
        // where Done asks `take.hasContent`.
        hasWords: () => take.segments.length > 0,
        candidates: () => candidates.current,
        targetChanged: setTarget,
      }),
  );

  /**
   * The live reader's steps, applied (`applySteps` below), what it is told of the take (`liveContext`), and "New note"
   * (`sealAndFork`): through refs, so the handlers registered once reach the newest render's code.
   */
  const applyRef = useRef<(steps: readonly LiveStep<Note>[]) => void>(() => undefined);
  const liveRef = useRef<() => LiveContext<Note>>(() => ({ notes: [], aim: null, own: false, locked: false }));
  const sealAndForkRef = useRef<() => void>(() => undefined);
  const cancelRef = useRef<() => void>(() => undefined);

  // ---- which note --------------------------------------------------------------------
  // A note's own Speak aims the recording at that note; otherwise it is a new one.
  useEffect(() => {
    let current = true;
    const chosen = aimedAt ? getNote(aimedAt).catch(() => null) : Promise.resolve<Note | null>(null);
    void chosen.then((found) => {
      // Found after a draft was already written to a new note, or after a command switched the take: stay there.
      if (!current || !found || writer.savedDraft || finished.current || live.engaged) return;
      const own = aimedPlacing ?? placingFor(found.body, { own: true });
      home.current = found;
      writer.aim(found, own);
      setPlacingView(own);
    });
    return () => {
      current = false;
    };
    // Decided once, as the capture opens: a new capture is a new mount, and its placing is the screen's, which holds still.
  }, [aimedAt, aimedPlacing, writer, live]);

  // The notes "add to …" can name (candidates.ts). Read once: a capture lasts minutes, and a
  // note made meanwhile is not one someone will name mid-sentence.
  useEffect(() => {
    let current = true;
    void listNotes()
      .then((all) => {
        if (!current) return;
        candidates.current = commandCandidates(all);
        // "Note link weekend trip end link" takes the note's own spelling.
        setLinkTitles(candidates.current.map((c) => c.title));
        setNotesRead(true);
        // Phrases said while the notes were read: read now, in order.
        const waiting = queued.current ?? [];
        queued.current = null;
        for (const segment of waiting) applyRef.current(live.phrase(segment, liveRef.current(), performance.now()));
      })
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, [live]);

  /** "New note", tapped: a fresh one from here, the words so far kept for the note they were said for (`sealAndFork`). */
  const startNewNote = () => {
    // The reader first, so the tap and the spoken cue leave it in one state: a take-back open settles.
    applyRef.current(live.forked());
    sealAndForkRef.current();
    setRoute({ phase: 'moved', title: 'New note' });
    fireNativeHaptic('selection');
  };

  // A settled chip has its moment, then goes.
  useEffect(() => {
    const ms = lingerMs(route);
    if (ms === null) return undefined;
    const timer = window.setTimeout(() => setRoute(null), ms);
    return () => window.clearTimeout(timer);
  }, [route]);

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
        // A meeting is recorded, not read: the guess goes on the page as it is.
        if (meetingRef.current) {
          setPartial(text);
          return;
        }
        // A partial is display only: it routes nothing. While a command is being said, or a note just named waits
        // for its words, it shows in the chip rather than on the page; "scratch that" being said never flashes onto
        // it, wherever it starts in the phrase (the words before it stay on the page), and nor does the send a bare
        // drop is waiting for.
        const takeBack = takeBackAt(text);
        const commanding = live.hearingCommand || takeBack === 0 || (live.sendOpen && opensSend(text)) || (text !== '' && (findKeyword(text) !== null || findMisheard(text, () => true) !== null));
        setItemWords(commanding ? text : takeBack > 0 ? text.slice(takeBack) : '');
        setPartial(commanding ? '' : takeBack > 0 ? text.slice(0, takeBack).trim() : text);
      },
      onSegment: (raw) => {
        quiet.current?.words(performance.now());
        heard();
        heardRef.current.push(raw.text);
        committedRef.current.push(raw);
        setPartial('');
        setItemWords('');
        // A meeting's phrases go straight to the take, unread: no command, no keyword, no take-back.
        if (meetingRef.current) {
          take.listen(raw);
          syncTake();
          return;
        }
        if (queued.current) {
          queued.current.push(raw);
          return;
        }
        // Applied at once, with nothing awaited: a phrase committed straight after a switch lands in the new note.
        applyRef.current(live.phrase(raw, liveRef.current(), performance.now()));
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

  // ---- the card after Done: words for a note, once tapped (capture/take.ts) ------------

  /**
   * Add, tapped on the card after Done: the words go into the note they were
   * read for, its last list growing by them in its own style. The chip and the
   * landing preview show the lines arriving.
   */
  const addItems = async (note: Note, spoken: string, { how, task, many, near, items }: Placement) => {
    try {
      // The offer was made from this exact note snapshot. Confirmation is a
      // compare-and-swap, so a later edit or delete wins instead of being
      // overwritten by the voice command.
      const placed = placeWords(note.body, spoken, { how, task, many, near, items });
      if (!placed.added.length) return;
      confirmedLines.current = placed.added;
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
    } catch (failure) {
      console.warn('[glyph] item not added:', failure);
      setRoute({ phase: 'missed', title: noteTitle(note.body) || 'that note' });
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

  /** The take's segments, copied to what the screen draws. */
  const syncTake = () => {
    segmentsRef.current = take.segments;
    setSegments(take.segments);
  };

  hostImpl.current = {
    route: setRoute,
    offer: setPendingView,
    haptic: (kind) => fireNativeHaptic(kind),
    changed: syncTake,
    // On the writer's chain, so a confirmed card's note is read back after its words are in it (`confirmPending`).
    // A new list is made by `confirmPending` itself.
    addItems: (target, spoken, placement) => void writer.queue(() => addItems(target, spoken, placement)),
  };

  // ---- the live reader (liveRoute.ts) -------------------------------------------------

  /** Whether a note is shared, or is a chapter of a shared book: over the lock screen, never written to. */
  const published = (id: string): boolean => {
    if (linkFor(id)) return true;
    const title = candidates.current.find((c) => c.id === id)?.title;
    return (
      title !== undefined &&
      candidates.current.some((book) => isBookBody(book.note.body) && linkFor(book.id) !== null && chaptersOf(book.note.body).some((chapter) => sameTitle(chapter.title, title)))
    );
  };

  liveRef.current = () => ({
    notes: candidates.current,
    aim: writer.target,
    own: home.current !== null,
    locked: isLocked(),
    published,
  });

  const setPendingTitle = (title: string | null) => {
    pendingTitleRef.current = title;
    setPendingTitleView(title);
  };

  /** The take goes to `note` from here, the words so far with it: the page starts from its text and they wisp in. */
  const switchTo = (note: Note, into: Placing) => {
    writer.aim(note, into, { routed: true });
    writer.refresh(note.id);
    takeTape.current = null;
    setPendingTitle(null);
    setRouted(true);
    setPlacingView(into);
    setPageFrom(isLocked() ? '' : note.body);
    setMoves((n) => n + 1);
  };

  /** The take goes to a note made at Done with `title` ("New note “House chores”" on a card). */
  const switchToNew = (title: string, task: boolean) => {
    const into = placingFor(listTitle(title), { said: { task } });
    writer.aim(null, into);
    takeTape.current = null;
    setPendingTitle(title);
    setRouted(true);
    setPlacingView(into);
    setPageFrom(isLocked() ? '' : listTitle(title));
    setMoves((n) => n + 1);
  };

  /** Not this note: back to the take's own note, a new one or the note whose Speak this is. Nothing was stored. */
  const goHome = () => {
    const own = home.current;
    const into = own ? (own.id === aimedAt && aimedPlacing ? aimedPlacing : placingFor(own.body, { own: true })) : END;
    writer.aim(own, into);
    takeTape.current = null;
    setPendingTitle(null);
    setRouted(false);
    setPlacingView(into);
    setPageFrom(undefined);
    setMoves((n) => n + 1);
  };

  /**
   * "New note", said or tapped: what was said so far is kept for the note it was said for, written at Done with the
   * rest, and the take starts afresh in a new note (take.fork). Discard now takes back the whole take, this part too.
   */
  sealAndForkRef.current = () => {
    const aimedAt = writer.target;
    const title = pendingTitleRef.current;
    parts.current.push({
      note: aimedAt,
      title,
      placing: writer.placing,
      markdown: take.markdown({ titled: !aimedAt && title === null }),
      titled: take.markdown({ titled: true }),
      noteId: writer.noteId,
    });
    take.fork();
    forkedAt.current = committedRef.current.length;
    home.current = null;
    writer.aim(null);
    takeTape.current = null;
    setPendingTitle(null);
    setRouted(false);
    setPlacingView(END);
    setPageFrom(undefined);
    setMoves((n) => n + 1);
  };

  /** A one-shot's words landing in its note: the chip shows them under the list's last lines. */
  const showInsert = (id: number) => {
    const insert = inserts.current.get(id);
    if (!insert?.segments.length) return;
    const placed = placeTake(insert.note.body, renderNote(insert.segments, '', { titled: false }).markdown, insert.placing);
    const added = placed.blocks.flatMap((block) => block.split('\n'));
    setRoute(isLocked() ? { phase: 'done', text: 'Added to the note you named' } : { phase: 'added', title: insert.title, body: placed.body, added, insert: id });
  };

  /** What the live reader said to do with a phrase, done now, in order. Nothing here awaits. */
  const applySteps = (steps: readonly LiveStep<Note>[]) => {
    for (const step of steps) {
      switch (step.kind) {
        case 'words': {
          take.listen(step.segment);
          // A card's words land when it settles, after what was said while it was up: back in the order they were said.
          const ordered = inOrder(take.segments);
          if (ordered !== take.segments) {
            take.segments = ordered;
            syncTake();
          }
          break;
        }
        case 'unword':
          take.segments = withoutWords(take.segments, step.segments);
          syncTake();
          break;
        case 'command':
          take.commandSpans.push(step.span);
          break;
        case 'keyword':
          take.keywordSpans.push(step.span);
          break;
        case 'route':
          switchTo(step.note, step.placing);
          break;
        case 'route-new':
          switchToNew(step.title, step.task);
          break;
        case 'home':
          goHome();
          break;
        case 'placing':
          writer.setPlacing(step.placing);
          setPlacingView(step.placing);
          break;
        case 'insert':
          inserts.current.set(step.id, { note: step.note, title: step.title, placing: step.placing, segments: [...step.segments] });
          break;
        case 'insert-words':
          inserts.current.get(step.id)?.segments.push(...step.segments);
          break;
        case 'insert-unword': {
          const insert = inserts.current.get(step.id);
          if (insert) insert.segments = withoutWords(insert.segments, step.segments);
          break;
        }
        case 'insert-end':
          showInsert(step.id);
          break;
        case 'insert-drop': {
          const insert = inserts.current.get(step.id);
          inserts.current.delete(step.id);
          if (insert) {
            take.segments = inOrder([...take.segments, ...insert.segments]);
            syncTake();
          }
          break;
        }
        case 'new-note':
          sealAndForkRef.current();
          break;
        case 'card':
          setChoice(step.card);
          break;
        case 'ask':
          pendingAsk.current = step.run ? { kind: step.run } : { kind: 'ask', instruction: step.instruction };
          pendingAskSaid.current = step.instruction;
          break;
        case 'chip':
          setRoute(step.view);
          break;
        case 'haptic':
          fireNativeHaptic(step.haptic);
          break;
        case 'log':
          commandLog.current.push(step.line);
          break;
      }
    }
  };
  applyRef.current = applySteps;

  /** Not this note, from the top line: the take goes home, and the card offers the others. */
  const notThisNote = () => applySteps(live.decline(liveRef.current(), performance.now()));

  const confirmPending = () => {
    take.confirm();
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
      // The note the card wrote to opens, with an Undo for the lines it put in.
      const lines = final.create ? [] : confirmedLines.current;
      if (saved && !final.locked) {
        onFinish(saved, final.locked, undefined, undefined, { noteId: saved.id, title: noteTitle(saved.body), blocks: lines, others: [], made: final.create ? [saved.id] : [] });
        return;
      }
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
  /** Cancel tapped on the card: nothing is written, and the take's sound goes as the command's words do. */
  const cancelPending = () => {
    take.cancel();
    const final = finalCommand.current;
    if (!final) return;
    finalCommand.current = null;
    void letGo(final.temporaryId, final.recordedMs, final.ownTape);
    endCapture(final.locked);
    onFinish(null, final.locked);
  };
  cancelRef.current = cancelPending;

  // ---- the counter ---------------------------------------------------------------
  useEffect(() => {
    if (phase !== 'listening') return undefined;
    const timer = window.setInterval(() => {
      setRecorded(session.current?.positionMs() ?? 0);
      setDiagnostics({ ...counts.current });
      const now = performance.now();
      // A command held for its note's name holds the recording open. Once the recording is over, the card of the
      // command read from it waits for a tap, however long it is up.
      const commanding = live.holding;
      if (!finished.current) applyRef.current(live.tick(now, liveRef.current()));
      if (!commanding && quiet.current?.due(now)) void finishRef.current();
      // A pause, once there are words: one tip, until words come again. Before the first word the card of things to
      // say is up instead (SayCard.tsx), and a tip picked under it would be spent unseen. A meeting takes no cues.
      if (!meetingRef.current && heardRef.current.length && now - lastHeard.current > TIP_AFTER_MS) {
        setTip(
          (showing) =>
            showing ??
            tipInPause({
              notes: candidates.current,
              own: writer.noteId,
              target: writer.target,
              pluginTips: (recent) => plugins.tips(recent),
              turn: tipTurn.current,
            }),
        );
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, [phase, take, writer, session, counts, live]);

  // No draft timer: phrase commits are display-only.  The complete transcript
  // is saved exactly once after final instruction classification.

  // ---- ending ----------------------------------------------------------------------
  /**
   * A meeting's Done (the Mac; capture/meeting.ts): the transcript's phrases, the stop's last words among them, into a
   * note titled with the date, its recording kept under it, its place in `prefs.meetings`, and its better words and
   * summary queued behind the recorder. Nothing said is nothing kept.
   */
  const finishMeeting = useCallback(
    async (heardAll: readonly Segment[], stopped: Stopped) => {
      const locked = isLocked();
      const recordedAs = writer.noteId;
      const segments = heardAll.filter((segment) => segment.text.trim());
      if (!segments.length) {
        if (stopped.recordedMs !== null) await discardRecording(recordedAs).catch(() => undefined);
        await writer.undoDraft();
        endCapture(locked);
        onFinish(null, locked);
        return;
      }
      const title = meetingTitled.current;
      // A meeting before it has words or a recording: a sync pass that lists the note from here on must already find
      // it among the meetings, or it would send the audio that `syncMeetingRecordings` keeps on this device.
      setPreferences({ meetings: { ...preferences().meetings, [recordedAs]: meetingStartedAt.current } });
      let saved = await writer.queue(() => writer.persist(recordedAs, meetingBody(title, segments), 'capture'));
      if (stopped.recordedMs !== null && session.current?.keepsAudio) {
        const kept = await setNoteRecording(saved.id, stopped.recordedMs, [...segments]).catch((failure: unknown) => {
          console.warn('[glyph] recording not kept:', failure);
          return null;
        });
        if (kept) saved = kept;
        setTapeId(saved.id, tapeOfTake());
        enqueueRefine({ id: saved.id, fromMs: 0, recordingMs: stopped.recordedMs, baseBody: '', savedBody: saved.body, titled: false, priorSegments: [], promptTail: '', meeting: true });
      }
      if (preferences().summaries !== 'off') enqueueSummary(saved.id, 'meeting');
      fireNativeHaptic('success');
      endCapture(locked);
      if (!locked) {
        setRoute({ phase: 'said', text: 'Keep Ghost.md open while it is written up.' });
        await new Promise<void>((resolve) => window.setTimeout(resolve, SAID_MS));
      }
      onFinish(saved, locked);
    },
    [onFinish, writer, session, tapeOfTake],
  );

  const finish = useCallback(async () => {
    if (finished.current) return;
    finished.current = true;
    setCapturing(false);
    setPhase('finishing');
    microphone.current?.stop();
    // Every command held, every card up and every one-shot open is settled before anything is composed.
    for (const segment of queued.current ?? []) take.listen(segment);
    queued.current = null;
    applyRef.current(live.close(liveRef.current(), performance.now()));
    await writer.refreshed();
    // The tape is kept under the id of the note the take is aimed at now, added to the end of that note's tape when
    // there is one, so its words and its sound stay one timeline (timeline.ts).
    const continued = writer.target;
    const append = appendsTo(continued);
    const ownTape = continued && append ? continued : null;
    const recordedAs = writer.noteId;
    let stopped: Stopped = { recordedMs: null, transcript: null };
    try {
      stopped = (await session.current?.stop({ recordAs: recordedAs, append })) ?? stopped;
    } catch (failure) {
      setError(failureText(failure));
    }

    // Native's stop-time result includes words whose phrase event was still in flight when `stop()` detached event
    // listeners: compared with every phrase committed, commands and all, what it adds is read as one more phrase, so a
    // command still being said at Done is still carried out, and last words are kept (finalWords.ts).
    const committed = [...committedRef.current];
    const heardAll = withFinalWords(committed, stopped.transcript, session.current?.positionMs() ?? committed.at(-1)?.endMs ?? 0);
    // A meeting: nothing is read from it. Its note is the date title over the transcript, kept as a meeting with its
    // better words and its summary to come, and the line says to keep the app open while they do.
    if (meetingRef.current) {
      await finishMeeting(heardAll, stopped);
      return;
    }
    for (const segment of heardAll.slice(committed.length)) {
      committedRef.current.push(segment);
      heardRef.current.push(segment.text);
      applyRef.current(live.final(segment, liveRef.current(), performance.now()));
    }
    await writer.refreshed();
    const locked = isLocked();
    /** The note the take is aimed at now: where its words are written, which a command only the stop heard may have changed. */
    const aimed = writer.target;

    // A command's change still landing, or the take carrying on elsewhere: written before the note is.
    await writer.settled();
    const named = pendingTitleRef.current;
    /** Notes this recording made, and writes to other notes, for the note that opens to know. */
    const made: string[] = [];
    const others: string[] = [];
    /** The titles of the notes written to besides the one that opens, for its toast to name. */
    const intoTitles: string[] = [];
    let lastInsert: { note: Note; blocks: string[] } | null = null;
    const changedMeanwhile = (title: string) => setRoute({ phase: 'said', text: `${title} changed as you spoke, so the words are a note of their own.` });

    // What was said before "New note", each for the note it was said for: written first, whatever the rest of the
    // recording turns out to be, so a refused command or an ask after it takes none of it with it.
    for (const part of parts.current) {
      if (!part.markdown.trim()) continue;
      if (part.note) {
        const written = await writer.writeInto(part.note, part.markdown, part.placing, () => part.titled);
        if (written.own) {
          made.push(written.saved.id);
          changedMeanwhile(noteTitle(part.note.body) || 'That note');
        } else if (written.mutationId) {
          others.push(written.mutationId);
          intoTitles.push(noteTitle(written.saved.body));
        }
      } else {
        const body = part.title ? placeTake(listTitle(part.title), part.markdown, part.placing).body : part.markdown;
        made.push((await createNote(part.noteId, body, 'capture')).id);
      }
    }

    // The reader at Done, when the live reader did nothing: a command said without the keyword, a run or an ask, a
    // new list by name (ai/instruction.ts), read once from the whole transcript; after "New note", from what was said
    // after it, which is the take being finished.
    if (!live.engaged) {
      const since = heardAll.slice(forkedAt.current);
      // Something was taken back: the phrases as the take kept them, by the rule the better words use (a dropped
      // stretch cut, a replacement on the same stretch kept), never the raw transcript with the taken-back words in it.
      const transcript = live.changedWords
        ? withoutCommands({ skip: take.commandSpans, keywordAt: take.keywordSpans, live: take.segments }, since)
            .map((segment) => segment.text)
            .join(' ')
            .trim()
        : forkedAt.current === 0
          ? (stopped.transcript ?? committed.map((segment) => segment.text).join(' ').trim())
          : since.map((segment) => segment.text).join(' ').trim();
      const read = await readInstruction(transcript, candidates.current);
      if (read.kind === 'command') {
        // The stopped audio is already retained under this capture id. The mutation remains pending until this card is
        // explicitly confirmed.
        take.offerFinal(read.plan);
        const aimed = read.plan.kind === 'place' ? read.plan.note.note : null;
        const create = read.plan.kind === 'create-list' ? { title: read.plan.title, items: read.plan.items ?? [] } : undefined;
        finalCommand.current = { note: aimed, ...(create ? { create } : {}), locked, temporaryId: recordedAs, recordedMs: stopped.recordedMs, ownTape };
        setPhase('listening');
        return;
      }
      if (read.kind === 'reject') {
        // Unsupported, destructive, ambiguous, and missing-target command shapes fail closed: do not create a note
        // containing command prose.
        setRoute({ phase: 'said', text: read.reason });
        await letGo(recordedAs, stopped.recordedMs, ownTape);
        await writer.undoDraft();
        endCapture(locked);
        onFinish(null, locked);
        return;
      }
      if ((read.kind === 'run' || read.kind === 'ask') && continued && !locked) {
        // "Hey Ghost, fix the spelling", said into a note: the words are an instruction, not the note's, and the note
        // opens with the run on it (shell/useCaptureRoute.ts, editor/NoteScreen.tsx). The recording of the instruction
        // goes, unless it went on the end of the note's own tape (`letGo`).
        await letGo(recordedAs, stopped.recordedMs, ownTape);
        await writer.undoDraft();
        endCapture(locked);
        onFinish(continued, locked, undefined, read.kind === 'run' ? { kind: read.run } : { kind: 'ask', instruction: read.instruction });
        return;
      }
      if (read.kind === 'ask') {
        // An ask a recording cannot carry out ("make a book called …"): its words are the note, without the keyword.
        const [first, ...rest] = take.segments;
        const bare = first ? bareWords(first.text) : null;
        if (first && bare?.keyed) {
          take.segments = [...(bare.words ? [{ ...first, text: `${capitalise(bare.words)}.` }] : []), ...rest];
          hostImpl.current.changed();
        }
        const said = capitalise(read.instruction);
        setRoute({ phase: 'said', text: `“${said.length > 30 ? `${said.slice(0, 30)}…` : said}” isn't something a recording can do, so the words are saved as a note.` });
      }
      if (read.kind === 'words' && read.notice) setRoute({ phase: 'said', text: read.notice });
    }

    // The one-shots: "add call Sam to House TODOs" said mid-take.
    for (const insert of inserts.current.values()) {
      const markdown = renderNote(insert.segments, '', { titled: false }).markdown;
      if (!markdown.trim()) continue;
      const written = await writer.writeInto(insert.note, markdown, insert.placing, () => renderNote(insert.segments).markdown);
      if (written.own) {
        made.push(written.saved.id);
        changedMeanwhile(insert.title);
        continue;
      }
      if (written.mutationId) {
        others.push(written.mutationId);
        intoTitles.push(insert.title);
      }
      lastInsert = { note: written.saved, blocks: written.blocks };
      take.touched.add(written.saved.id);
      commandLog.current.push(`Added “${written.blocks.map(withoutLead).join('”, “')}” to ${insert.title}${written.spot ? `, ${written.spot}` : ''}`);
    }

    // Nothing that lays out as anything leaves nothing behind for the take's
    // own note. Asked of the laid-out words (take.hasContent), not the transcript: a cue said alone ("Bullet point.",
    // or Whisper echoing its prompt on silence) is held for a sentence that never comes, and saved from the transcript
    // it made an empty note.
    if (!take.hasContent) {
      // The stop has already kept the take's sound. On the end of a note's tape it stays, and the tape's new length is
      // kept with the note's phrases as they were, so the next take's words still line up with their sound; a new
      // note's goes with the note that is not made. A note's own file is never removed here: it is the whole of that
      // note's tape.
      if (stopped.recordedMs !== null) {
        if (continued && append) {
          await setNoteRecording(continued.id, stopped.recordedMs, continued.segments ?? []).catch((failure: unknown) => console.warn('[glyph] recording not kept:', failure));
        } else if (!continued || writer.routed) {
          await discardRecording(recordedAs).catch(() => undefined);
        }
      }
      const opened = lastInsert?.note ?? null;
      // Why nothing was kept, where the recorder would otherwise leave before it could be read: a note named with
      // nothing said for it, or an ask said mid-take with no words of this note to run on.
      const why =
        writer.routed && aimed && !lastInsert && !made.length
          ? `Nothing was said for ${locked ? 'the note you named' : noteTitle(aimed.body) || 'that note'}, so nothing was added.`
          : pendingAsk.current
            ? `Nothing was said for “${capitalise(pendingAskSaid.current)}” to run on, so it didn't run.`
            : null;
      if (why) setRoute({ phase: 'said', text: why });
      await writer.undoDraft();
      endCapture(locked);
      if (why && !(opened && !locked)) await new Promise<void>((resolve) => window.setTimeout(resolve, SAID_MS));
      if (opened && !locked) onFinish(opened, locked, undefined, undefined, { noteId: opened.id, title: noteTitle(opened.body), blocks: lastInsert!.blocks, others: others.slice(0, -1), into: intoTitles.slice(0, -1), made });
      else if (made.length) onFinish((await getNote(made.at(-1)!).catch(() => null)) ?? null, locked);
      else onFinish(null, locked);
      return;
    }

    const markdown = take.markdown({ titled: !aimed && named === null });
    let saved: Note;
    /** The note's text the words were composed onto, for the better words: '' for a new note. */
    let base = '';
    let blocks: string[] = [];
    /** The take went into a note that already existed, switched to by a command: it opens, with no review. */
    let into = false;
    if (writer.routed && aimed) {
      const written = await writer.writeInto(aimed, markdown, writer.placing, () => take.markdown({ titled: true }));
      saved = written.saved;
      if (written.own) {
        made.push(saved.id);
        changedMeanwhile(noteTitle(aimed.body) || 'That note');
      } else {
        into = true;
        base = written.before ?? aimed.body;
        blocks = written.blocks;
        commandLog.current.push(`Wrote to ${noteTitle(saved.body)}${written.spot ? `, ${written.spot}` : ''}`);
      }
    } else if (named !== null) {
      // "New note “House chores”", chosen on a card: made now, titled, with the words where its title says.
      const body = placeTake(listTitle(named), markdown, writer.placing).body;
      const result = await applyCommandMutation({ mutationId: newNoteId(), noteId: writer.noteId, kind: 'create', beforeRevision: null, beforeBody: null, afterBody: body, source: 'capture' }).catch(() => null);
      saved = result?.status === 'applied' ? result.note : await createNote(newNoteId(), body, 'capture');
      made.push(saved.id);
      // The better words go under its title, where the words were written.
      base = listTitle(named);
    } else {
      saved = await writer.queue(async () => writer.persist(writer.noteId, await writer.compose(markdown), 'capture'));
      base = aimed ? ((await writer.baseBody) ?? aimed.body) : '';
    }

    let refineJob: ReviewHandoff['job'] = null;
    if (stopped.recordedMs !== null && session.current?.keepsAudio) {
      /** The note whose tape the take's sound goes on the end of, as it was before this take; null for a tape of its own. */
      let tapeOf: Note | null = into || saved.id === aimed?.id ? aimed : null;
      let recordedMs: number | null = stopped.recordedMs;
      if (saved.id !== recordedAs) {
        // The take ended up in another note than the one its sound was kept under: a command only the stop heard, or a
        // note that changed too much to write into. Sound on the end of a note's own tape stays on it (`letGo`).
        if (ownTape) {
          await letGo(recordedAs, stopped.recordedMs, ownTape);
          recordedMs = null;
        } else {
          if (!into) tapeOf = null;
          recordedMs = await reassignRecording(recordedAs, saved.id, appendsTo(tapeOf)).catch(() => null);
        }
      }
      if (recordedMs !== null) {
        // New phrases sit after the continued tape's, shifted by its length.
        const tape = onTape(tapeOf, take, take.segments);
        const kept = await setNoteRecording(saved.id, recordedMs, tape.segments).catch((failure: unknown) => {
          console.warn('[glyph] recording not kept:', failure);
          return null;
        });
        if (kept) saved = kept;
        // The tape this take wrote to, so the voice memos already in the note know it again when it is opened
        // (core/clips.ts).
        setTapeId(saved.id, tapeOfTake());
        // The better words: the larger model over this take's recording, later, or now in the review after a recording
        // when that runs.
        refineJob = {
          id: saved.id,
          fromMs: tape.fromMs,
          recordingMs: recordedMs,
          baseBody: base,
          savedBody: saved.body,
          titled: !tapeOf && !into && named === null && !aimed,
          priorSegments: tape.prior,
          promptTail: renderNote(tape.prior).plain.slice(-200),
          skip: tape.skip,
          keywordAt: tape.keywordAt,
          // Not the end, or the end with a line the words go on from: the better words are placed the same way.
          ...(writer.placing.kind !== 'end' || writer.placing.lead ? { placing: writer.placing } : {}),
          // The take's own phrases whenever they are not the transcript's: a command carried out, or a take-back.
          ...(live.changedWords ? { live: shifted(take.segments, tape.fromMs) } : {}),
        };
      }
    }
    fireNativeHaptic('success');
    endCapture(locked);
    // A long take: the review's prompt would not fit the model's window, and its job is dictation's.
    const long = refineJob !== null && refineJob.recordingMs - refineJob.fromMs > LONG_NOTE_MS;
    const ask = pendingAsk.current ?? undefined;
    // What the recording left in notes that were there already, and the notes it made, for the note that opens.
    // Its Undo drops the better words only for words it takes out of the note that opens: a take written into it.
    const tookBack = live.tookBackAtDone;
    const landing: CaptureLanding | undefined =
      into || others.length || made.length
        ? { noteId: saved.id, title: noteTitle(saved.body), blocks, others, into: intoTitles, made, ...(refineJob && into ? { fromMs: refineJob.fromMs } : {}), ...(tookBack.length ? { tookBack: [...tookBack] } : {}) }
        : undefined;
    // A take written into a note that already existed opens it with its Undo, and no review: the words are in it as
    // they were said (Matt: "instead of doing the second pass over at the end"). The better words land after the note
    // is left (capture/refine.ts `holdNote`).
    if (into) {
      if (refineJob) enqueueRefine(refineJob);
      onFinish(saved, locked, undefined, ask, landing);
      return;
    }
    // The review after a recording: it runs the better words and the formatting when it is done.
    // Not over a locked phone, whose note is not shown to whoever is holding it, and not for a long take.
    if (!locked && !long && (await reviewAvailable())) {
      const review = { noteId: saved.id, job: refineJob, heard: heardRef.current.join(' '), commands: [...commandLog.current], touched: [...take.touched] };
      if (landing || ask) onFinish(saved, locked, review, ask, landing);
      else onFinish(saved, locked, review);
      return;
    }
    if (refineJob) enqueueRefine(refineJob);
    // A long voice note's summary, when Settings says so: the recorder's own new note, behind its better words. Never
    // for a take into a note that was there, whose tape is not the note.
    const summarized = long && !aimed && saved.source === 'capture' && preferences().summaries === 'long';
    if (summarized) enqueueSummary(saved.id, 'recording');
    if (long && !locked) {
      // The Done line says why the note is not opened for a review, and stays long enough to be read.
      setRoute({ phase: 'said', text: summarized ? 'Long recording. The better words come later. The summary comes later.' : 'Long recording. The better words come later.' });
      await new Promise<void>((resolve) => window.setTimeout(resolve, SAID_MS));
    }
    if (landing || ask) onFinish(saved, locked, undefined, ask, landing);
    else onFinish(saved, locked);
  }, [onFinish, take, writer, tapeOfTake, session, microphone, setPhase, setError, live, finishMeeting]);

  /**
   * "Meeting instead", from the card before the first word. On the Mac this recorder becomes the meeting: the quiet
   * stop goes, and what is heard from here is transcript. On a phone the service records it, and its `AudioRecord`
   * cannot open while this page holds the microphone, so the take is let go first and the caller then starts it.
   */
  const meetingInstead = useCallback(() => {
    if (!isAndroid) {
      quiet.current = null;
      setMeeting(true);
      fireNativeHaptic('selection');
      return;
    }
    if (finished.current) return;
    finished.current = true;
    setCapturing(false);
    session.current?.cancel();
    microphone.current?.stop();
    void discardRecording(writer.noteId).catch(() => undefined);
    void writer.undoDraft();
    endCapture(false);
    onMeeting?.();
  }, [onMeeting, session, microphone, writer]);

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
    // With the card after Done up, Discard is its Cancel: the take was finished, and its sound goes as a Cancel's does.
    if (finished.current) {
      if (finalCommand.current) cancelRef.current();
      return;
    }
    // Nothing was stored mid-take, so there is nothing to take back: the holds and cards are settled and dropped.
    live.close(liveRef.current(), performance.now());
    finished.current = true;
    setCapturing(false);
    session.current?.cancel();
    microphone.current?.stop();
    await writer.undoDraft();
    const locked = isLocked();
    endCapture(locked);
    onFinish(null, locked);
  }, [onFinish, writer, session, microphone, live]);

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
      noteTitle: others.find((c) => !isBookBody(c.note.body))?.title ?? null,
      asking: target !== null && !locked,
    });
    // `candidates` is a ref and `writer.noteId` a field: `notesRead` says when the first was filled, `moves` when the second changed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, locked, notesRead, moves]);
  const status = statusLine({ phase, error, download, heardWords: segments.length > 0 });

  // A capture that has heard a while and produced nothing is the one worth
  // explaining without being asked: the line that diagnosed the Fold.
  const silent = soundsSilent(engine, diagnostics);
  // A note switched to shows its own text already: the card of things to say and the hint under an empty page are done.
  // A meeting's page carries its heading before a word is said, so its words are its phrases.
  const hasWords = meeting ? segments.length > 0 || partial !== '' : note.markdown.length > 0 || routed;
  // "Meeting instead" is offered before the first word, where a meeting can be recorded, and not for a note's own
  // Speak or over the lock screen, where a fresh recording of a meeting is not what the key asked for.
  const offerMeeting = onMeeting !== undefined && !aimedAt && !(fromAssistant && locked) && !meeting;

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
              {whereLine(target, locked, { routed, named: pendingTitle, meeting })}
            </button>
            {meeting ? null : routed ? (
              <button type="button" className={`app-word ${styles.newNote}`} onClick={notThisNote}>
                Not this note
              </button>
            ) : target ? (
              <button type="button" className={`app-word ${styles.newNote}`} onClick={startNewNote}>
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
        {route?.phase === 'added' ? (
          <ListLanding
            key={`landing-${route.added.join('|')}`}
            title={route.title}
            body={route.body}
            added={route.added}
            // Not once Done is writing: the one-shot may be in its note already.
            onUndo={route.insert !== undefined && phase !== 'finishing' && !finished.current ? () => {
              applySteps(live.dropInsert(route.insert!));
              setRoute({ phase: 'said', text: `Not added to ${route.title}.` });
            } : undefined}
          />
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
            key={`page-${target?.id ?? pendingTitle ?? 'new'}-${moves}-${meeting ? 'meeting' : 'take'}-${phase === 'starting' ? 'starting' : 'up'}`}
            base={meeting ? `# ${meetingTitled.current}\n` : locked ? '' : target ? target.body : pendingTitle !== null ? listTitle(pendingTitle) : ''}
            markdown={note.markdown}
            placing={locked ? END : placing}
            from={locked ? undefined : pageFrom}
            under={topRef}
            placeholder={phase === 'starting' ? 'Starting…' : 'Start talking.'}
          />
        )}
        {!hasWords && phase === 'listening' && !route ? <Ghost scene="listening" align="center" className={styles.listenGhost} /> : null}
        {!hasWords && phase !== 'failed' && route?.phase !== 'added' ? <p className={styles.pageHint}>{stopHint(fromAssistant, pressStops, quiet.current !== null)}</p> : null}
      </div>

      {choice && !locked ? (
        <NoteChoiceCard card={choice} onChoose={(chosen) => applySteps(live.answer(choice.id, chosen, liveRef.current()))} />
      ) : pending ? (
        <ConfirmCard offer={pending} onConfirm={confirmPending} onCancel={cancelPending} />
      ) : route ? (
        <RouteChip
          route={route}
          itemWords={itemWords}
          // A take-back's Undo, withheld once Done is writing, as a one-shot's Not this note is.
          onUndo={route.phase === 'tookBack' && route.undo !== undefined && phase !== 'finishing' && !finished.current ? () => applySteps(live.undoTakeBack(route.undo!)) : undefined}
        />
      ) : !hasWords && phase === 'listening' && !meeting ? (
        // Before the first word: the whole of what can be said, as a card (SayCard.tsx); once talking has begun, one tip at a time in a pause.
        <SayCard starters={say} onMeeting={offerMeeting ? meetingInstead : undefined} />
      ) : tip && phase === 'listening' && !meeting ? (
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
