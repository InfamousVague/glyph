import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { answerHost, endCapture, isLocked, setCapturing } from '../core/host.ts';
import { deleteNote, getNote, listNotes, newNoteId, noteTitle, saveNote, setNoteRecording, type Note } from '../core/store.ts';
import { preferences } from '../core/preferences.ts';
import { isTauri } from '../core/tauri.ts';
import { openMicrophone, type Microphone } from './audio.ts';
import { appendBody, continuationNote, rememberCapture } from './continuation.ts';
import { enqueueRefine, setRecorderLive } from './refine.ts';
import { enqueueFormat, setFormattingPaused } from '../format/queue.ts';
import { startCapture, type CaptureSession, type EngineKind } from './engine.ts';
import { renderNote, type Segment } from './markdown.ts';
import { Opening, Saved } from './Opening.tsx';
import { QuietWatch } from './quiet.ts';
import { type Candidate } from './route.ts';
import { findKeyword, planCommand, reply, type Placement, type Plan } from './command.ts';
import { placeWords } from './listAppend.ts';
import { appendBlock, cellsOf, fitRow, saysDone, tableMarkdown } from './table.ts';
import { applyLinks, type SentLink } from '../core/itemLinks.ts';
import { plugins } from '../plugins/registry.ts';
import type { CaptureContext, VoiceCommand } from '../plugins/types.ts';
import { tips, TIP_AFTER_MS, type Tip } from './tips.ts';
import { SideKeyWaves } from './SideKeyWaves.tsx';
import { useSideKeySpot } from './sideKey.ts';
import { Tail } from './Tail.tsx';
import { counter } from './tape.ts';
import styles from './CaptureScreen.module.css';

/**
 * A note being spoken.
 *
 * One screen for both ways in - the Speak button and the held side key - and
 * it shows one thing: the note taking shape as you say it, set large, the
 * spoken cues turning into dimmed markdown marks as they land. A small line at
 * the top says where the words are going; a counter says how long; Discard and
 * Done are the only buttons. Until the first words arrive, a drawing of sound
 * beginning is the whole screen, so the microphone being live is visible before
 * a word has been understood.
 *
 * Opened by a held side key, so everything here is ordered around one promise:
 * the microphone is listening before anything else is ready. The microphone is
 * opened first, the model loads while it listens, and samples captured in the
 * meantime are held and replayed rather than dropped. The first words of a
 * voice note are usually its subject, and a capture screen that needs a second
 * to warm up loses exactly them.
 *
 * The note is saved WHILE it is spoken, not when it ends. The phone can kill
 * the app mid-sentence, and a note that only reached the store at Done would be
 * a note that never existed. So each committed phrase is written under an id
 * chosen at mount; a cancel deletes it; Done writes the final version.
 *
 * With memo mode on (the default), a recording - from the Speak button or the
 * side key - goes onto the last spoken note rather than starting another
 * (continuation.ts), with "New note" one tap away; tapping it makes the new
 * note the one that grows from then on. Over the lock screen the note it continues is not named, and none of its
 * text is shown.
 *
 * Done goes back to the list, whatever started the capture: the new note is at
 * the top, a tap away, and a locked phone has already stepped back behind its
 * lock screen without showing the note to whoever is holding it.
 */

interface CaptureScreenProps {
  /** Opened by the side key, where the OS has already buzzed. */
  fromAssistant: boolean;
  /** Counts side-key presses during this capture: each one after the first means "stop and save". */
  stopRequests?: number;
  /** Talking into this note (its Speak): the words go on its end, whatever memo mode says. */
  noteId?: string;
  /** The saved note, or null when the capture was cancelled or nothing was said. */
  onFinish: (note: Note | null, locked: boolean) => void;
}

type Phase = 'starting' | 'listening' | 'finishing' | 'failed';

/** How often the in-progress note is written to the store. */
const DRAFT_SAVE_MS = 1000;

/** After "Glyph", this long without a word that makes a command, and it gives up. */
const COMMAND_QUIET_MS = 4500;
/** "New items for …": a pause this long after the last one, and they are asked about. */
const ITEMS_QUIET_MS = 2500;
/** A note named with nothing said for it: this long, and it gives up. */
const AWAIT_MS = 9000;
/** A table being said, and nothing for it: this long, and it is dropped. */
const TABLE_QUIET_MS = 45_000;
/** A command asked about and not answered: this long, and it is not done. */
const CONFIRM_MS = 20_000;

/** How long a quiet after words has to last before "Stop when I go quiet" saves the take. */
const QUIET_STOP_MS = 4000;

const ENGINE_LABEL: Record<EngineKind, string> = {
  whisper: 'On-device Whisper',
  browser: 'Browser speech recognition',
  simulated: 'Simulated voice',
};

export function CaptureScreen({ fromAssistant, stopRequests = 0, noteId: aimedAt, onFinish }: CaptureScreenProps) {
  /** The note being written: a new id, or the note this capture continues. */
  const noteId = useRef(newNoteId());
  /** The note this capture is being added to, if it continues one. */
  const [target, setTarget] = useState<Note | null>(null);
  const targetRef = useRef<Note | null>(null);
  /**
   * The continued note's text before this capture, read from the store once,
   * when first needed - after the editor that may have been open has flushed
   * its last keystrokes. A promise, so two drafts racing both get the text from
   * BEFORE either of them wrote.
   */
  const baseBody = useRef<Promise<string> | null>(null);

  const [phase, setPhase] = useState<Phase>('starting');
  const [segments, setSegments] = useState<Segment[]>([]);
  const [partial, setPartial] = useState('');
  const [engine, setEngine] = useState<EngineKind | null>(null);
  const [download, setDownload] = useState<{ received: number; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  /** Milliseconds on the recording, copied from the session a few times a second. */
  const [recorded, setRecorded] = useState(0);
  const [diagnostics, setDiagnostics] = useState<Diagnostics>(EMPTY_DIAGNOSTICS);
  const [showDiagnostics, setShowDiagnostics] = useState(false);

  // Mirrors the render state reads at Done, which runs after the last events
  // have landed but before React has necessarily re-rendered with them.
  const segmentsRef = useRef<Segment[]>([]);
  const sessionRef = useRef<CaptureSession | null>(null);
  const micRef = useRef<Microphone | null>(null);
  const meterRef = useRef<HTMLDivElement>(null);
  const screenRef = useRef<HTMLDivElement>(null);
  /** Set when "Stop when I go quiet" is on: watches for the end of talking. */
  const quiet = useRef(preferences().quietStop ? new QuietWatch(QUIET_STOP_MS) : null);
  /** Whether this phone stops a recording when the side key is pressed (generation 12). */
  const [pressStops, setPressStops] = useState(false);
  const spot = useSideKeySpot();

  /** The notes a spoken "add to …" can name, most recent first; loaded as the capture opens. */
  const candidates = useRef<(Candidate & { note: Note })[]>([]);
  /**
   * The routing chip: a note being named while it is still being said, then
   * the note the words moved to (or a name that matched nothing).
   */
  const [route, setRoute] = useState<RouteView>(null);
  /** Bumped when words move to another note, to replay the lines writing out. */
  const [moves, setMoves] = useState(0);
  /** The words as they looked just before a move, sliding away. */
  const [ghost, setGhost] = useState<{ markdown: string; key: number } | null>(null);
  /**
   * After "new item for AttackFM" said on its own: the note whose list the next
   * phrase goes into, and for "new items" every phrase until a pause.
   */
  /**
   * After "Glyph": the command being said, across phrases. `said` is what was
   * heard from the keyword on, to put back in the note if no command comes.
   */
  const listening = useRef<{ words: string; said: Segment[]; lastAt: number } | null>(null);
  /** A command named its note but not what goes in it: the next phrases are that. */
  const awaiting = useRef<{ plan: Extract<Plan<Candidate & { note: Note }>, { kind: 'await' }>; words: string[]; lastAt: number } | null>(null);
  /** What a command will do once it is confirmed, by "yes" or a tap. */
  const pendingRef = useRef<{ offer: Offer; at: number } | null>(null);
  const [pending, setPendingView] = useState<Offer | null>(null);
  /** "Glyph, add a table to …": the table being asked for, column labels first, then row by row. */
  const tabling = useRef<TableDraft | null>(null);
  const [tableView, setTableView] = useState<TableDraft | null>(null);
  /** Tables made for the note being recorded: they follow its words. */
  const tablesRef = useRef<string[]>([]);
  const [tables, setTables] = useState<string[]>([]);
  /** Recording spans that were commands, for the better-words pass to leave out. */
  const commandSpans = useRef<Array<{ startMs: number; endMs: number }>>([]);
  /** Phrases that were words and then "Glyph": the better words keep only what came before it. */
  const keywordSpans = useRef<Array<{ startMs: number; endMs: number }>>([]);
  /** The last thing said, for plugin commands like "send that to Notion": a phrase of this take, or items added to another note. */
  const lastSaid = useRef<{ kind: 'take'; text: string } | { kind: 'items'; noteId: string; lines: string[] } | null>(null);
  /** When words were last heard, for the tips in a pause. */
  const lastHeard = useRef(performance.now());
  const [tip, setTip] = useState<Tip | null>(null);
  const tipTurn = useRef(0);
  const savedDraft = useRef(false);
  const finished = useRef(false);
  /*
   * What the pipeline has actually done, counted where it happens and copied to
   * the screen a few times a second. The line itself is essential: the first
   * real capture on the Fold transcribed nothing and said "Listening" the whole
   * time, because an error during listening was stored and never shown.
   * "Heard 8.2 s · 0 phrases" and "heard 0.0 s" point at different halves of
   * the chain, which is the whole diagnosis without a debugger attached.
   */
  const counts = useRef<Diagnostics>({ ...EMPTY_DIAGNOSTICS });

  const titled = target === null;
  /** While an item for another note is being said, its words show in the chip, not in this note. */
  const [itemWords, setItemWords] = useState('');
  /** Words of this take a plugin linked to something (a Notion task): links wherever the cues put them. */
  const [sentLinks, setSentLinks] = useState<SentLink[]>([]);
  const sentLinksRef = useRef<SentLink[]>([]);
  const note = useMemo(() => {
    const rendered = renderNote(segments, itemWords ? '' : partial, { titled });
    const linked = sentLinks.length ? { ...rendered, markdown: applyLinks(rendered.markdown, sentLinks), pendingFrom: null } : rendered;
    return tables.length ? { ...linked, markdown: withTables(linked.markdown, tables) } : linked;
  }, [segments, partial, titled, itemWords, sentLinks, tables]);

  // No background pass over an earlier recording while this one is live: same cores.
  useEffect(() => {
    setRecorderLive(true);
    // Nor a formatting pass: the recorder has the cores while it is on screen.
    setFormattingPaused(true);
    return () => {
      setRecorderLive(false);
      setFormattingPaused(false);
    };
  }, []);

  // The screen stays on while this runs, and pressing the side key (which
  // turns it off) stops it: the only sign of the key Android gives an app.
  useEffect(() => {
    setPressStops(setCapturing(true));
    return () => void setCapturing(false);
  }, []);

  // ---- which note --------------------------------------------------------------------
  // A note's own Speak aims the recording at that note. Otherwise memo mode
  // covers every recording, the Speak button as much as the side key: it was
  // once side-key only, and a recording started from the list made a new note
  // with memo mode on.
  useEffect(() => {
    let current = true;
    const chosen = aimedAt ? getNote(aimedAt).catch(() => null) : continuationNote(preferences().memo);
    void chosen.then((found) => {
      // Found after a draft was already written to a new note: stay with that one.
      if (!current || !found || savedDraft.current || finished.current) return;
      targetRef.current = found;
      noteId.current = found.id;
      setTarget(found);
    });
    return () => {
      current = false;
    };
    // Decided once, as the capture opens: a new capture is a new mount.
  }, [aimedAt]);

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
      })
      .catch(() => undefined);
    return () => {
      current = false;
    };
  }, []);

  /** The body to store: this capture's markdown, below the continued note's text if there is one. */
  const compose = useCallback(async (markdown: string): Promise<string> => {
    const continued = targetRef.current;
    if (!continued) return markdown;
    baseBody.current ??= getNote(continued.id)
      .catch(() => null)
      .then((stored) => stored?.body ?? continued.body);
    return appendBody(await baseBody.current, markdown);
  }, []);

  /** Undoes whatever drafts wrote: the continued note gets its text back, a new note goes. */
  const undoDraft = useCallback(async () => {
    if (!savedDraft.current) return;
    savedDraft.current = false;
    const continued = targetRef.current;
    if (continued) await saveNote(continued.id, (await baseBody.current) ?? continued.body, continued.source);
    else await deleteNote(noteId.current);
  }, []);

  /** "New note": this capture stops continuing the last one. */
  const startNewNote = useCallback(async () => {
    if (!targetRef.current) return;
    await undoDraft();
    targetRef.current = null;
    baseBody.current = null;
    noteId.current = newNoteId();
    setTarget(null);
    fireNativeHaptic('selection');
    // The next draft save writes the words so far to the new note.
    setSegments([...segmentsRef.current]);
  }, [undoDraft]);

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
      if (chosen.id === noteId.current) return;
      setGhost({ markdown: renderNote(segmentsRef.current, '', { titled: !targetRef.current }).markdown, key: Date.now() });
      await undoDraft();
      // The full note, for its recording and phrases: this take's tape goes on the end of them.
      const full = (await getNote(chosen.id).catch(() => null)) ?? chosen;
      targetRef.current = full;
      baseBody.current = null;
      noteId.current = full.id;
      setTarget(full);
      setMoves((n) => n + 1);
      // The next draft save writes the words so far to the note.
      setSegments([...segmentsRef.current]);
    },
    [undoDraft],
  );

  // The moved chip and the sliding words have their moment, then go.
  useEffect(() => {
    const settled = route?.phase === 'moved' || route?.phase === 'missed' || route?.phase === 'added' || route?.phase === 'said' || route?.phase === 'done' || (route?.phase === 'plugin' && route.state !== 'working');
    if (!settled || !route) return undefined;
    const timer = window.setTimeout(() => setRoute(null), route.phase === 'added' || route.phase === 'said' ? 3200 : 2200);
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

  // ---- commands: "Glyph", then what to do, then yes or no ---------------------------

  const commandWordOn = () => preferences().commandWord;

  /** The chip while a command is heard: the note it names, as soon as it can tell. */
  const showGuess = (text: string) => {
    const wait = awaiting.current;
    if (wait) {
      setRoute({ phase: 'waiting', title: wait.plan.note.title, many: wait.plan.many, leave: wait.plan.how === 'leave' });
      return;
    }
    const heard = listening.current;
    const found = heard ? null : commandWordOn() ? findKeyword(text) : null;
    const words = heard ? `${heard.words} ${text}`.trim() : found ? found.after : commandWordOn() ? null : text;
    setRoute((current) => {
      const guessing = current === null || current.phase === 'hearing' || current.phase === 'command';
      if (!guessing) return current;
      if (words === null || (!heard && !found && !words)) return current?.phase === 'hearing' || current?.phase === 'command' ? null : current;
      const plugin = plugins.voiceCommands().find((voice) => voice.parse(words) !== null);
      const plan = plugin ? null : planCommand(words, { notes: candidates.current, targets: itemWordsOfPlugins() });
      if (!plan || plan.kind === 'no-note') {
        // Without the keyword, only something that reads as a command shows at all.
        if (!heard && !found && !plugin) return current?.phase === 'hearing' || current?.phase === 'command' ? null : current;
        return { phase: 'command', words: heard ? heard.words : '' };
      }
      if (plan.kind === 'new') return { phase: 'hearing', name: 'new note', guess: 'New note', lead: 'Start' };
      if (plan.kind === 'table') return { phase: 'hearing', name: 'table', guess: plan.note?.title ?? 'this note', lead: 'Table for' };
      const lead = plan.kind === 'move' ? 'Move to' : plan.how === 'item' ? 'New item for' : 'Add to';
      if (current?.phase === 'hearing' && current.guess === plan.note.title && current.lead === lead) return current;
      return { phase: 'hearing', name: plan.note.title, guess: plan.note.title, lead };
    });
  };

  /**
   * Items spoken for another note's list go straight into that note: its last
   * list grows by them, in its own style, while this take carries on where it
   * was. The chip and the landing preview show the lines arriving.
   */
  const addItems = async (
    note: Note,
    spoken: string,
    { task, many, target = null, leave = false }: { task: boolean; many: boolean; target?: string | null; leave?: boolean },
  ) => {
    try {
      const fresh = (await getNote(note.id).catch(() => null)) ?? note;
      // "Leave a note for …": into the list it fits, or its own paragraph.
      const { body, added } = placeWords(fresh.body, spoken, { how: leave ? 'leave' : 'item', task, many });
      if (!added.length) return;
      await saveNote(fresh.id, body, fresh.source);
      // The take may be writing onto this very note: its drafts build on the
      // grown body from now on, or the next one would put the old list back.
      if (targetRef.current?.id === fresh.id) {
        baseBody.current = Promise.resolve(body);
        targetRef.current = { ...fresh, body };
      }
      const known = candidates.current.find((c) => c.id === fresh.id);
      if (known) known.note = { ...fresh, body };
      setRoute({ phase: 'added', title: noteTitle(body) || 'that note', body, added });
      fireNativeHaptic('success');
      lastSaid.current = { kind: 'items', noteId: fresh.id, lines: added };
      // "…in Notion": the plugin that offers the word takes the lines from here.
      if (target) plugins.itemTargets().find((t) => t.word === target)?.afterAdd(fresh.id, added, captureContext);
    } catch (failure) {
      console.warn('[glyph] item not added:', failure);
      setRoute({ phase: 'missed', title: noteTitle(note.body) || 'that note' });
    }
  };

  // ---- plugins, by voice --------------------------------------------------------------

  /** What a plugin's voice command may do to this take (plugins/types.ts). Refs and setters only, so any render's copy works. */
  const captureContext: CaptureContext = {
    noteId: () => noteId.current,
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
      const at = segmentsRef.current[segmentsRef.current.length - 1]?.endMs ?? 0;
      segmentsRef.current = [...segmentsRef.current, { text: markdown, startMs: at, endMs: at }];
      setSegments(segmentsRef.current);
    },
    updateNote: async (id, change) => {
      const fresh = await getNote(id);
      if (!fresh) return;
      const body = change(fresh.body);
      if (body === fresh.body) return;
      await saveNote(id, body, fresh.source);
      // The take may be writing onto this very note: its drafts build on the new body from now on.
      if (targetRef.current?.id === id) {
        baseBody.current = Promise.resolve(body);
        targetRef.current = { ...fresh, body };
      }
      const known = candidates.current.find((c) => c.id === id);
      if (known) known.note = { ...fresh, body };
    },
  };

  /** The words switched-on plugins let an item command end a note's name with ("…in Notion"). */
  const itemWordsOfPlugins = () => plugins.itemTargets().map((t) => t.word);

  const setPending = (offer: Offer | null) => {
    pendingRef.current = offer ? { offer, at: performance.now() } : null;
    setPendingView(offer);
  };

  /** A command understood: shown, with what it will do, until yes or no. */
  const offer = (plan: Plan<Candidate & { note: Note }>, span: { startMs: number; endMs: number }) => {
    listening.current = null;
    awaiting.current = null;
    setItemWords('');
    if (plan.kind === 'no-note' || plan.kind === 'await' || plan.kind === 'table') return;
    if (plan.kind === 'place') {
      const note = plan.note.note;
      const preview = placeWords(note.body, plan.text, plan);
      if (!preview.added.length) return;
      setPending({ kind: 'place', note, title: plan.note.title, text: plan.text, placement: plan, added: preview.added, into: preview.into, span });
    } else if (plan.kind === 'move') {
      setPending({ kind: 'move', note: plan.note.note, title: plan.note.title, span });
    } else {
      setPending({ kind: 'new', span });
    }
    setRoute(null);
    fireNativeHaptic('selection');
  };

  const offerPlugin = (voice: VoiceCommand, parsed: unknown, span: { startMs: number; endMs: number }) => {
    listening.current = null;
    awaiting.current = null;
    setItemWords('');
    const { title, action } = voice.describe(parsed, captureContext);
    setPending({ kind: 'plugin', voice, parsed, title, action, span });
    setRoute(null);
    fireNativeHaptic('selection');
  };

  /** Yes: the command does what it showed. */
  const confirmPending = () => {
    const held = pendingRef.current?.offer;
    if (!held) return;
    setPending(null);
    if (held.kind === 'place') {
      void addItems(held.note, held.text, { task: held.placement.task, many: held.placement.many, target: held.placement.target, leave: held.placement.how === 'leave' });
    } else if (held.kind === 'table') {
      if (held.note) void addTable(held.note, held.title, held.markdown);
      else {
        tablesRef.current = [...tablesRef.current, held.markdown];
        setTables(tablesRef.current);
        setRoute({ phase: 'done', text: 'Table added' });
        fireNativeHaptic('success');
      }
    } else if (held.kind === 'move') {
      void routeTo(held.note);
    } else if (held.kind === 'new') {
      setRoute({ phase: 'moved', title: 'New note' });
      void startNewNote();
    } else {
      const keep = held.voice.run(held.parsed, captureContext);
      if (keep) {
        // Words the command keeps in the note ("book the cabin, send that to Notion").
        segmentsRef.current = [...segmentsRef.current, { text: keep, startMs: held.span.startMs, endMs: held.span.endMs }];
        setSegments(segmentsRef.current);
      }
    }
  };

  /** No, or no answer: nothing happens, and the chip says so. */
  const cancelPending = (why: string | null) => {
    if (!pendingRef.current) return;
    setPending(null);
    if (why) setRoute({ phase: 'said', text: why });
  };

  /** No command came after the keyword: what was said goes back into the note, as words. */
  const giveBack = (why: string) => {
    const heard = listening.current;
    listening.current = null;
    setItemWords('');
    if (!heard) return;
    if (heard.said.length) {
      const back = new Set(heard.said.map((s) => `${s.startMs}:${s.endMs}`));
      commandSpans.current = commandSpans.current.filter((span) => !back.has(`${span.startMs}:${span.endMs}`));
      keywordSpans.current = keywordSpans.current.filter((span) => !back.has(`${span.startMs}:${span.endMs}`));
      segmentsRef.current = [...segmentsRef.current, ...heard.said].sort((x, y) => x.startMs - y.startMs);
      setSegments(segmentsRef.current);
      lastSaid.current = { kind: 'take', text: heard.said.map((s) => s.text).join(' ') };
    }
    setRoute({ phase: 'said', text: why });
  };

  /** The command so far, read again with every phrase: a plan to confirm, a note to wait on, or more to hear. */
  const decide = (words: string, span: { startMs: number; endMs: number }) => {
    const plugin = plugins.voiceCommands().find((voice) => voice.parse(words) !== null);
    if (plugin) return offerPlugin(plugin, plugin.parse(words), span);
    const plan = planCommand(words, { notes: candidates.current, targets: itemWordsOfPlugins() });
    if (!plan) {
      setRoute({ phase: 'command', words });
      return;
    }
    if (plan.kind === 'no-note') {
      giveBack(`No note called “${plan.name}”, so it stays here.`);
      fireNativeHaptic('warning');
      return;
    }
    if (plan.kind === 'table') {
      listening.current = null;
      setItemWords('');
      setTable({ note: plan.note?.note ?? null, title: plan.note?.title ?? 'this note', columns: plan.columns, rows: [], lastAt: performance.now() });
      setRoute(null);
      fireNativeHaptic('selection');
      return;
    }
    if (plan.kind === 'await') {
      listening.current = null;
      awaiting.current = { plan, words: [], lastAt: performance.now() };
      setItemWords('');
      setRoute({ phase: 'waiting', title: plan.note.title, many: plan.many, leave: plan.how === 'leave' });
      fireNativeHaptic('selection');
      return;
    }
    offer(plan, span);
  };

  const setTable = (draft: TableDraft | null) => {
    tabling.current = draft;
    setTableView(draft ? { ...draft, columns: [...draft.columns], rows: draft.rows.map((row) => [...row]) } : null);
  };

  /** The rows are done: the table as it will look, and a yes. */
  const finishTable = () => {
    const draft = tabling.current;
    if (!draft) return;
    setTable(null);
    setItemWords('');
    if (!draft.columns.length) {
      setRoute({ phase: 'said', text: 'No table: it had no columns.' });
      return;
    }
    setPending({ kind: 'table', note: draft.note, title: draft.title, columns: draft.columns, rows: draft.rows, markdown: tableMarkdown(draft.columns, draft.rows), span: { startMs: 0, endMs: 0 } });
    fireNativeHaptic('selection');
  };

  const cancelTable = (why: string | null) => {
    if (!tabling.current) return;
    setTable(null);
    setItemWords('');
    if (why) setRoute({ phase: 'said', text: why });
  };

  /** A confirmed table for another note: its own block at the end of that note. */
  const addTable = async (note: Note, title: string, markdown: string) => {
    try {
      const fresh = (await getNote(note.id).catch(() => null)) ?? note;
      const body = appendBlock(fresh.body, markdown);
      await saveNote(fresh.id, body, fresh.source);
      if (targetRef.current?.id === fresh.id) {
        baseBody.current = Promise.resolve(body);
        targetRef.current = { ...fresh, body };
      }
      const known = candidates.current.find((c) => c.id === fresh.id);
      if (known) known.note = { ...fresh, body };
      setRoute({ phase: 'done', text: `Table added to ${title}` });
      fireNativeHaptic('success');
    } catch (failure) {
      console.warn('[glyph] table not added:', failure);
      setRoute({ phase: 'said', text: `The table didn’t go into ${title}.` });
    }
  };

  /**
   * A committed phrase, read for commands (capture/command.ts). With the
   * keyword on, only "Glyph" starts one: the words before it stay, and the
   * words after it, in this phrase and the next, are the command. It is shown
   * and asks; "yes" or a tap does it, "no" or silence doesn't. Answers what of
   * the phrase goes into the note.
   */
  const takeCommand = (segment: Segment): Segment | null => {
    const now = performance.now();
    const text = segment.text;
    const span = { startMs: segment.startMs, endMs: segment.endMs };
    const skip = () => commandSpans.current.push(span);
    const keywordOn = commandWordOn();
    const found = keywordOn ? findKeyword(text) : null;

    // A table being asked for: every phrase is its next piece, until "done".
    const draft = tabling.current;
    if (draft) {
      skip();
      const said = (findKeyword(text)?.after ?? text).trim();
      draft.lastAt = now;
      setItemWords('');
      if (reply(said) === 'no' || /^(?:cancel|never ?mind|forget (?:it|the table)|no table)\b/i.test(said)) {
        cancelTable('No table.');
        return null;
      }
      if (!draft.columns.length) {
        const labels = cellsOf(said);
        if (labels.length) setTable({ ...draft, columns: labels });
        return null;
      }
      if (saysDone(said)) {
        finishTable();
        return null;
      }
      const cells = cellsOf(said);
      if (cells.length) setTable({ ...draft, rows: [...draft.rows, fitRow(cells, draft.columns.length)] });
      return null;
    }

    // A command asked "shall I?": this phrase may be the answer.
    if (pendingRef.current) {
      const answer = reply(text);
      if (answer) {
        skip();
        if (answer === 'yes') confirmPending();
        else cancelPending('Not done.');
        return null;
      }
      // Talking on: the words go in the note and the question stays, unless a new command starts.
      if (!found) {
        lastSaid.current = { kind: 'take', text };
        return segment;
      }
      cancelPending(null);
    }

    // A note was named: this phrase is what goes in it.
    const wait = awaiting.current;
    if (wait && !found) {
      skip();
      wait.words.push(text.replace(/[\s.,;:!?]+$/, ''));
      wait.lastAt = now;
      if (!wait.plan.many) offer({ ...wait.plan, kind: 'place', text: wait.words.join(', ') }, span);
      return null;
    }
    awaiting.current = null;

    // After the keyword: more of the command.
    const heard = listening.current;
    if (heard && !found) {
      skip();
      heard.words = `${heard.words} ${text}`.trim();
      heard.said.push(segment);
      heard.lastAt = now;
      setItemWords('');
      decide(heard.words, span);
      return null;
    }

    if (keywordOn && !found) {
      lastSaid.current = { kind: 'take', text };
      return segment;
    }

    if (!keywordOn) {
      // No keyword needed: a phrase is a command only if it reads as one, and it still asks.
      const plugin = plugins.voiceCommands().find((voice) => voice.parse(text) !== null);
      const plan = plugin ? null : planCommand(text, { notes: candidates.current, targets: itemWordsOfPlugins() });
      if (!plugin && (!plan || plan.kind === 'no-note')) {
        lastSaid.current = { kind: 'take', text };
        return segment;
      }
      skip();
      listening.current = { words: text, said: [], lastAt: now };
      decide(text, span);
      return null;
    }

    // "Glyph": the words before it stay; the rest is the command.
    const before = found!.before;
    const from = text.slice(before.length).trim();
    if (before) keywordSpans.current.push(span);
    else skip();
    listening.current = { words: found!.after, said: [{ ...segment, text: from }], lastAt: now };
    setItemWords('');
    fireNativeHaptic('light');
    if (found!.after) decide(found!.after, span);
    else setRoute({ phase: 'command', words: '' });
    if (!before) return null;
    lastSaid.current = { kind: 'take', text: before };
    return { ...segment, text: before };
  };

  // The timer is set up once per phase; these keep it calling the newest copies.
  const giveBackRef = useRef(giveBack);
  giveBackRef.current = giveBack;
  const offerRef = useRef(offer);
  offerRef.current = offer;
  const cancelPendingRef = useRef(cancelPending);
  cancelPendingRef.current = cancelPending;
  const cancelTableRef = useRef(cancelTable);
  cancelTableRef.current = cancelTable;

  // ---- start ------------------------------------------------------------------
  useEffect(() => {
    let cancelled = false;
    const held: Float32Array[] = [];

    async function start() {
      const simulate = new URLSearchParams(window.location.search).has('simulate');
      try {
        if (isTauri() && !simulate) {
          micRef.current = await openMicrophone({
            onChunk: (samples) => {
              counts.current.heardSamples += samples.length;
              if (sessionRef.current) sessionRef.current.push(samples);
              else held.push(samples);
            },
            onLevel: (rms) => {
              // Straight to a custom property: five updates a second is too many
              // React renders for a meter nobody reads precisely. The screen
              // carries it too, for the side key's rings to swell with.
              const level = String(Math.min(1, rms * 8));
              meterRef.current?.style.setProperty('--level', level);
              screenRef.current?.style.setProperty('--level', level);
              quiet.current?.level(rms, performance.now());
            },
          });
          counts.current.deviceRate = micRef.current.deviceRate;
          console.info(`[glyph] microphone open at ${micRef.current.deviceRate} Hz, context ${micRef.current.state()}`);
        }
        const session = await startCapture({
          onPartial: (text) => {
            if (text) {
              counts.current.partials += 1;
              quiet.current?.words(performance.now());
              heard();
            }
            setPartial(text);
            // Words of a command show in the chip, not in the note.
            const commanding = listening.current !== null || awaiting.current !== null || tabling.current !== null || (commandWordOn() && findKeyword(text) !== null);
            setItemWords(commanding ? text : '');
            showGuess(text);
          },
          onSegment: (raw) => {
            counts.current.segments += 1;
            quiet.current?.words(performance.now());
            heard();
            counts.current.lastError = null;
            const segment = takeCommand(raw);
            setPartial('');
            if (!segment) return;
            segmentsRef.current = [...segmentsRef.current, segment];
            setSegments(segmentsRef.current);
          },
          onError: (message) => {
            counts.current.errors += 1;
            counts.current.lastError = message;
            console.warn('[glyph] capture error:', message);
            setError(message);
          },
          onModelProgress: (received, total) => setDownload({ received, total }),
        });
        if (cancelled) {
          session.cancel();
          return;
        }
        sessionRef.current = session;
        if (session.wantsSamples) held.splice(0).forEach((samples) => session.push(samples));
        else micRef.current?.stop();
        setEngine(session.kind);
        setDownload(null);
        setPhase('listening');
        console.info(`[glyph] capture started with ${session.kind}`);
        if (!fromAssistant) fireNativeHaptic('medium');
      } catch (failure) {
        if (cancelled) return;
        micRef.current?.stop();
        setError(failure instanceof Error ? failure.message : String(failure));
        setPhase('failed');
        fireNativeHaptic('error');
      }
    }
    void start();

    return () => {
      cancelled = true;
      if (!finished.current) {
        sessionRef.current?.cancel();
        micRef.current?.stop();
      }
    };
    // Started once per mount; a new capture is a new mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- the counter ---------------------------------------------------------------
  useEffect(() => {
    if (phase !== 'listening') return undefined;
    const timer = window.setInterval(() => {
      setRecorded(sessionRef.current?.positionMs() ?? 0);
      setDiagnostics({ ...counts.current });
      const now = performance.now();
      // A command being said, or waiting for its yes, holds the recording open.
      const commanding = listening.current !== null || awaiting.current !== null || pendingRef.current !== null || tabling.current !== null;
      if (tabling.current && now - tabling.current.lastAt > TABLE_QUIET_MS) cancelTableRef.current('No table: nothing was said for it for a while.');
      if (!commanding && quiet.current?.due(now)) void finishRef.current();
      // The keyword said, and then nothing that makes a command: the words go back in the note.
      if (listening.current && now - listening.current.lastAt > COMMAND_QUIET_MS) {
        giveBackRef.current(listening.current.words ? 'No command there, so the words stay in the note.' : 'Say a command after “Glyph”.');
      }
      const wait = awaiting.current;
      if (wait && wait.words.length && now - wait.lastAt > ITEMS_QUIET_MS) {
        // "New items for work": every phrase until a pause, then asked all at once.
        offerRef.current({ ...wait.plan, kind: 'place', text: wait.words.join(', ') }, { startMs: 0, endMs: 0 });
      } else if (wait && !wait.words.length && now - wait.lastAt > AWAIT_MS) {
        awaiting.current = null;
        setItemWords('');
        setRoute({ phase: 'said', text: `Nothing said for ${wait.plan.note.title}, so nothing was added.` });
      }
      const held = pendingRef.current;
      if (held && now - held.at > CONFIRM_MS) cancelPendingRef.current('Not done. Say “yes” or tap to confirm a command.');
      // A pause: one tip, until words come again.
      if (now - lastHeard.current > TIP_AFTER_MS) {
        setTip((showing) => {
          if (showing) return showing;
          const recent = candidates.current.find((c) => c.id !== noteId.current)?.title ?? null;
          const keyword = commandWordOn();
          const pluginTips = plugins.tips(recent ?? null).map((t) => (keyword ? { ...t, say: `Glyph, ${t.say.charAt(0).toLowerCase()}${t.say.slice(1)}` } : t));
          const list = [...tips({ noteTitle: recent, continuing: targetRef.current !== null, keyword }), ...pluginTips];
          return list[tipTurn.current % list.length] ?? null;
        });
      }
    }, 250);
    return () => window.clearInterval(timer);
  }, [phase]);

  // ---- the draft, saved as it is spoken ------------------------------------------
  useEffect(() => {
    if (!segments.length) return undefined;
    const timer = window.setTimeout(() => {
      if (finished.current) return;
      savedDraft.current = true;
      const id = noteId.current;
      void compose(withTables(applyLinks(renderNote(segmentsRef.current, '', { titled: !targetRef.current }).markdown, sentLinksRef.current), tablesRef.current)).then((body) =>
        saveNote(id, body, 'capture'),
      );
    }, DRAFT_SAVE_MS);
    return () => window.clearTimeout(timer);
  }, [segments, target, compose]);

  // ---- ending ----------------------------------------------------------------------
  const finish = useCallback(async () => {
    if (finished.current) return;
    finished.current = true;
    setCapturing(false);
    setPhase('finishing');
    micRef.current?.stop();
    // The tape is kept under the note's id, added to the end of the continued
    // note's tape when there is one, so its words and its sound stay one timeline.
    const continued = targetRef.current;
    let stopped: { recordedMs: number | null } = { recordedMs: null };
    try {
      stopped = (await sessionRef.current?.stop({ recordAs: noteId.current, append: continued !== null })) ?? stopped;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    }

    const spoken = segmentsRef.current;
    const { plain } = renderNote(spoken);
    const locked = isLocked();

    if (!plain.trim() && !tablesRef.current.length) {
      await undoDraft();
      endCapture(locked);
      onFinish(null, locked);
      return;
    }

    const markdown = withTables(applyLinks(renderNote(spoken, '', { titled: !targetRef.current }).markdown, sentLinksRef.current), tablesRef.current);
    const saved = await saveNote(noteId.current, await compose(markdown), 'capture');
    if (stopped.recordedMs !== null && sessionRef.current?.keepsAudio) {
      // New phrases sit after the continued tape's, shifted by its length.
      const offset = continued?.recordingMs ?? 0;
      const prior = continued?.segments ?? [];
      const all = [...prior, ...spoken.map((s) => ({ ...s, startMs: s.startMs + offset, endMs: s.endMs + offset }))];
      await setNoteRecording(saved.id, stopped.recordedMs, all).catch((failure: unknown) => console.warn('[glyph] recording not kept:', failure));
      // The better words, later: the larger model over this take's recording.
      const base = continued ? ((await baseBody.current) ?? continued.body) : '';
      enqueueRefine({
        id: saved.id,
        fromMs: offset,
        recordingMs: stopped.recordedMs,
        baseBody: base,
        savedBody: saved.body,
        titled: !continued,
        priorSegments: prior,
        promptTail: renderNote(prior).plain.slice(-200),
        skip: commandSpans.current.map((span) => ({ startMs: span.startMs + offset, endMs: span.endMs + offset })),
        keywordAt: keywordSpans.current.map((span) => ({ startMs: span.startMs + offset, endMs: span.endMs + offset })),
      });
    }
    // The staged rewrite (format/queue.ts): a quick draft, then slower models
    // revising it. After the refine job, which it waits for.
    enqueueFormat(saved.id);
    rememberCapture(saved.id);
    fireNativeHaptic('success');
    endCapture(locked);
    onFinish(saved, locked);
  }, [onFinish, compose, undoDraft]);

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
    sessionRef.current?.cancel();
    micRef.current?.stop();
    await undoDraft();
    const locked = isLocked();
    endCapture(locked);
    onFinish(null, locked);
  }, [onFinish, undoDraft]);

  // The phone's back gesture ends the take the way Done does: what was said
  // is kept, and a take with nothing in it leaves nothing behind.
  useBack(true, () => void finish());

  // ---- the line at the top -----------------------------------------------------------
  const locked = isLocked();
  let status: string | null = null;
  if (phase === 'failed') status = error ?? 'Could not start';
  else if (download) status = `Downloading voice model ${Math.round(download.received / 1e6)} / ${Math.round(download.total / 1e6)} MB`;
  else if (phase === 'starting') status = 'Starting';
  else if (phase === 'finishing') status = 'Saving';
  else if (error && !segments.length) status = `Problem: ${error}`;
  const where = target ? (locked ? 'Adding to your last note' : `Adding to “${noteTitle(target.body)}”`) : 'New note';

  // A capture that has heard a while and produced nothing is the one worth
  // explaining without being asked: the line that diagnosed the Fold.
  const silent = engine === 'whisper' && diagnostics.heardSamples > 8 * 16_000 && !diagnostics.partials && !diagnostics.segments;
  const hasWords = note.markdown.length > 0;

  return (
    <div className={styles.screen} data-phase={phase} ref={screenRef}>
      {fromAssistant && (phase === 'starting' || phase === 'listening') ? <SideKeyWaves spot={spot} /> : null}
      <div className={styles.top} role="status" aria-live="polite">
        {status ? (
          <span className={styles.where}>{status}</span>
        ) : (
          <>
            {/* Tapping the line shows what the pipeline has done, for diagnosing a silent capture. */}
            <button type="button" className={`app-word ${styles.where}`} onClick={() => setShowDiagnostics((on) => !on)}>
              {where}
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
        ) : target && phase !== 'finishing' ? (
          <NoteContext key={`context-${target.id}-${moves}`} note={target} />
        ) : null}
        {phase === 'finishing' && hasWords ? (
          <Saved />
        ) : hasWords ? (
          <div key={`words-${noteId.current}-${moves}`} className={styles.written} data-moved={moves ? '' : undefined}>
            <Tail markdown={note.markdown} pendingFrom={note.pendingFrom} />
          </div>
        ) : (
          <div className={styles.empty}>
            <Opening failed={phase === 'failed'} />
            <p className={styles.lead}>{phase === 'failed' ? 'Nothing was recorded.' : 'Start talking.'}</p>
            {phase === 'failed' ? null : (
              <p className={styles.hint}>{stopHint(fromAssistant, pressStops, quiet.current !== null)}</p>
            )}
          </div>
        )}
      </div>

      {tableView ? (
        <TableCard draft={tableView} heard={itemWords} onDone={finishTable} onCancel={() => cancelTable(null)} />
      ) : pending ? (
        <ConfirmCard offer={pending} onConfirm={confirmPending} onCancel={() => cancelPending(null)} />
      ) : route ? (
        <p
          className={styles.route}
          data-phase={
            route.phase === 'plugin' ? (route.state === 'done' ? 'moved' : route.state === 'failed' ? 'missed' : 'hearing') : route.phase === 'command' ? 'hearing' : route.phase === 'said' ? 'missed' : route.phase === 'done' ? 'moved' : route.phase
          }
          role="status"
        >
          {route.phase === 'hearing' ? (
            <>
              <span className={styles.routeDots} aria-hidden="true" />
              {route.guess ? (
                <>
                  {route.lead} <strong>{route.guess}</strong>
                </>
              ) : (
                <>Looking for “{route.name}”</>
              )}
            </>
          ) : route.phase === 'waiting' ? (
            itemWords ? (
              <>
                <strong>{route.title}:</strong> {itemWords}
              </>
            ) : (
              <>
                <span className={styles.routeDots} aria-hidden="true" />
                {route.leave ? 'Say the note for' : route.many ? 'Say the items for' : 'Say the item for'} <strong>{route.title}</strong>
              </>
            )
          ) : route.phase === 'plugin' ? (
            route.state === 'failed' ? (
              <>{route.title}</>
            ) : (
              <>
                <span className={route.state === 'working' ? styles.routeDots : styles.routeTick} aria-hidden="true" />
                {route.lead ? `${route.lead} ` : null}
                <strong>{route.title}</strong>
              </>
            )
          ) : route.phase === 'command' ? (
            <>
              <span className={styles.routeDots} aria-hidden="true" />
              <span>
                <strong>Glyph</strong>
                {route.words || partialCommand(itemWords) ? `: ${[route.words, partialCommand(itemWords)].filter(Boolean).join(' ')}` : ', listening for a command'}
              </span>
            </>
          ) : route.phase === 'said' ? (
            <>{route.text}</>
          ) : route.phase === 'done' ? (
            <>
              <span className={styles.routeTick} aria-hidden="true" />
              {route.text}
            </>
          ) : route.phase === 'added' ? (
            <>
              <span className={styles.routeTick} aria-hidden="true" />
              {route.added.length === 1 ? 'Added to' : `${route.added.length} added to`} <strong>{route.title}</strong>
            </>
          ) : route.phase === 'moved' ? (
            <>
              <span className={styles.routeTick} aria-hidden="true" />
              {route.title === 'New note' ? 'New note' : (
                <>
                  Now on <strong>{route.title}</strong>
                </>
              )}
            </>
          ) : (
            <>No note called “{route.title}”, so it stays here</>
          )}
        </p>
      ) : tip && phase === 'listening' ? (
        <p key={tip.say} className={styles.tip}>
          Say <strong>“{tip.say}”</strong> {tip.does}.
        </p>
      ) : null}

      {showDiagnostics || silent || diagnostics.errors ? (
        <p className={styles.diagnostics}>{[engine ? ENGINE_LABEL[engine] : null, describe(diagnostics)].filter(Boolean).join(' · ')}</p>
      ) : null}

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
          <span className={styles.doneMark} aria-hidden="true" />
          Done
        </button>
      </footer>
    </div>
  );
}

/** The take's markdown with its tables after its words. */
function withTables(markdown: string, tables: readonly string[]): string {
  return tables.reduce((body, table) => appendBlock(body, table), markdown).replace(/\n$/, '');
}

/** A table being asked for: its note (null for the one being recorded), its labels, its rows so far. */
interface TableDraft {
  note: Note | null;
  title: string;
  columns: string[];
  rows: string[][];
  lastAt: number;
}

/** A command understood and waiting for yes or no: what it will do, shown on the card. */
type Offer =
  | { kind: 'place'; note: Note; title: string; text: string; placement: Placement; added: string[]; into: 'list' | 'paragraph'; span: { startMs: number; endMs: number } }
  | { kind: 'move'; note: Note; title: string; span: { startMs: number; endMs: number } }
  | { kind: 'new'; span: { startMs: number; endMs: number } }
  | { kind: 'table'; note: Note | null; title: string; columns: string[]; rows: string[][]; markdown: string; span: { startMs: number; endMs: number } }
  | { kind: 'plugin'; voice: VoiceCommand; parsed: unknown; title: string; action: string; span: { startMs: number; endMs: number } };

type RouteView =
  | { phase: 'hearing'; name: string; guess: string | null; lead: 'Add to' | 'New item for' | 'Move to' | 'Start' | 'Table for' }
  /** Something a command did, with a tick. */
  | { phase: 'done'; text: string }
  /** After "Glyph": the command's words so far. */
  | { phase: 'command'; words: string }
  /** A sentence about what did not happen. */
  | { phase: 'said'; text: string }
  | { phase: 'waiting'; title: string; many: boolean; leave: boolean }
  | { phase: 'added'; title: string; body: string; added: string[] }
  | { phase: 'moved'; title: string }
  | { phase: 'missed'; title: string }
  /** A plugin's voice command: working ("Sending to Board"), done ("In Notion on Board"), or why not. */
  | { phase: 'plugin'; state: 'working' | 'done' | 'failed'; lead: string | null; title: string }
  | null;

/** The words of a command still being said, with the keyword taken off if it is in them. */
function partialCommand(text: string): string {
  return (findKeyword(text)?.after ?? text).trim();
}

/**
 * "Shall I?": what a command understood will do, before it does anything.
 *
 * The note's name, the lines as they will land (in its list, or as a
 * paragraph), and the two answers. "Yes" or "no" said aloud answer it as well
 * as a tap does, and saying nothing for a while is a no.
 */
function ConfirmCard({ offer, onConfirm, onCancel }: { offer: Offer; onConfirm: () => void; onCancel: () => void }) {
  const show = (line: string) => line.replace(/^\s*(?:- \[[ xX]\] |[-*+] |\d+[.)] )/, '');
  let heading: string;
  let action: string;
  let lines: string[] = [];
  let detail: string | null = null;
  switch (offer.kind) {
    case 'place':
      heading = `Add to ${offer.title}`;
      action = 'Add';
      lines = offer.added.map(show);
      detail = offer.into === 'list' ? 'In its list' : 'As a new paragraph';
      if (offer.placement.target) detail += `, then to ${offer.placement.target.charAt(0).toUpperCase()}${offer.placement.target.slice(1)}`;
      break;
    case 'move':
      heading = `Move this recording to ${offer.title}`;
      action = 'Move';
      break;
    case 'new':
      heading = 'Start a new note from here';
      action = 'Start';
      break;
    case 'table':
      heading = `Add this table to ${offer.title}`;
      action = 'Add';
      detail = `${offer.rows.length} ${offer.rows.length === 1 ? 'row' : 'rows'}, at the end of the note`;
      break;
    default:
      heading = offer.title;
      action = offer.action;
  }
  return (
    <section className={styles.confirm} aria-live="assertive" aria-label={heading}>
      <p className={styles.confirmHeading}>{heading}</p>
      {lines.map((line, i) => (
        <p key={i} className={styles.confirmLine}>
          {line}
        </p>
      ))}
      {offer.kind === 'table' ? <TablePreview columns={offer.columns} rows={offer.rows} /> : null}
      {detail ? <p className={styles.confirmDetail}>{detail}</p> : null}
      <div className={styles.confirmActions}>
        <button type="button" className="app-word" onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="app-pill" onClick={onConfirm}>
          {action}
        </button>
      </div>
      <p className={styles.confirmHint}>Or say “yes” or “no”.</p>
    </section>
  );
}

/** A table as it will look, small, scrolling sideways inside the card when it is wide. */
function TablePreview({ columns, rows }: { columns: readonly string[]; rows: readonly (readonly string[])[] }) {
  return (
    <div className={styles.tableWrap}>
      <table className={styles.table}>
        <thead>
          <tr>
            {columns.map((label, i) => (
              <th key={i}>{label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, r) => (
            <tr key={r}>
              {columns.map((_, i) => (
                <td key={i}>{row[i] ?? ''}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * "And what will the column labels be?": the table being said, one question
 * at a time. Matt wanted the recorder to guide a table rather than expect it in
 * one breath, so the card asks for the labels, then the first row, then the
 * next or "done", showing the table as it grows and the words being heard
 * for the piece it asked for.
 */
function TableCard({ draft, heard, onDone, onCancel }: { draft: TableDraft; heard: string; onDone: () => void; onCancel: () => void }) {
  const question = !draft.columns.length ? 'What will the column labels be?' : draft.rows.length ? 'Next row? Or say “done”.' : 'What goes in the first row?';
  const hint = !draft.columns.length ? 'Say them with commas, like “bug, owner, status”.' : `In order: ${draft.columns.join(', ')}.`;
  const words = heard ? (findKeyword(heard)?.after ?? heard) : '';
  return (
    <section className={styles.confirm} aria-live="polite" aria-label={`Table for ${draft.title}`}>
      <p className={styles.confirmHeading}>Table for {draft.title}</p>
      <p className={styles.tableQuestion}>{question}</p>
      {draft.columns.length ? <TablePreview columns={draft.columns} rows={draft.rows} /> : null}
      {words ? <p className={styles.confirmDetail}>“{words}”</p> : <p className={styles.confirmHint}>{hint}</p>}
      <div className={styles.confirmActions}>
        <button type="button" className="app-word" onClick={onCancel}>
          Cancel
        </button>
        {draft.columns.length ? (
          <button type="button" className="app-pill" onClick={onDone}>
            That’s all
          </button>
        ) : null}
      </div>
    </section>
  );
}

/**
 * Items landing in another note's list: the note's name, the list's last lines
 * as they were, and the new lines arriving under them with a tick each.
 */
function ListLanding({ title, body, added }: { title: string; body: string; added: string[] }) {
  const lines = body.split('\n');
  const end = lines.lastIndexOf(added[added.length - 1] ?? '');
  const start = end - added.length + 1;
  const before = lines.slice(Math.max(0, start - 2), Math.max(0, start)).filter((line) => line.trim());
  const show = (line: string) => line.replace(/^\s*(?:- \[[ xX]\] |[-*+] |\d+[.)] )/, '');
  return (
    <div className={styles.landing} aria-label={`Added to ${title}`}>
      <p className={styles.contextTitle}>{title}</p>
      {before.map((line, i) => (
        <p key={`b${i}`} className={styles.contextLine}>
          {show(line)}
        </p>
      ))}
      {added.map((line, i) => (
        <p key={`a${i}`} className={styles.landed} style={{ animationDelay: `${120 + i * 140}ms` }}>
          <span className={styles.landedTick} aria-hidden="true" />
          {show(line)}
        </p>
      ))}
    </div>
  );
}

/**
 * The note being written on, above the words: its title and its last couple
 * of lines, faint, so it is always plain which note the words are landing in.
 */
function NoteContext({ note }: { note: Note }) {
  const lines = note.body
    .split('\n')
    .map((line) => line.replace(/^\s*(?:#{1,6}\s+|- \[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+|>\s+)/, '').replace(/\*\*/g, '').trim())
    .filter((line) => line && !line.startsWith('!['));
  const title = noteTitle(note.body) || 'Untitled';
  const last = lines.filter((line) => line !== title).slice(-2);
  return (
    <div className={styles.context} aria-label={`Writing on ${title}`}>
      <p className={styles.contextTitle}>{title}</p>
      {last.map((line, i) => (
        <p key={i} className={styles.contextLine}>
          {line}
        </p>
      ))}
    </div>
  );
}

/** What ends this recording, in a line under "Start talking." */
function stopHint(fromSideKey: boolean, pressStops: boolean, quietStops: boolean): string {
  const key = pressStops ? 'press the side key' : fromSideKey ? 'hold the side key again' : null;
  if (quietStops) return key ? `Stop talking to finish, or ${key}.` : 'Stop talking to finish, or tap Done.';
  if (key) return `${key[0]!.toUpperCase()}${key.slice(1)} to stop.`;
  return 'Tap Done to stop.';
}

interface Diagnostics {
  heardSamples: number;
  deviceRate: number | null;
  partials: number;
  segments: number;
  errors: number;
  lastError: string | null;
}

const EMPTY_DIAGNOSTICS: Diagnostics = {
  heardSamples: 0,
  deviceRate: null,
  partials: 0,
  segments: 0,
  errors: 0,
  lastError: null,
};

/** "heard 8.2 s at 48 kHz · 3 guesses · 1 phrase", plus the last error if there is one. */
function describe(d: Diagnostics): string {
  const parts = [`heard ${(d.heardSamples / 16_000).toFixed(1)} s${d.deviceRate ? ` at ${Math.round(d.deviceRate / 1000)} kHz` : ''}`];
  parts.push(`${d.partials} ${d.partials === 1 ? 'guess' : 'guesses'}`);
  parts.push(`${d.segments} ${d.segments === 1 ? 'phrase' : 'phrases'}`);
  if (d.errors) parts.push(`${d.errors} ${d.errors === 1 ? 'error' : 'errors'}: ${d.lastError ?? ''}`);
  return parts.join(' · ');
}
