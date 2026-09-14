import { useCallback, useEffect, useRef, useState } from 'react';
import { HapticsProvider, ToastProvider } from '@glacier/react';
import { NotesList } from './notes/NotesList.tsx';
import { NoteScreen } from './editor/NoteScreen.tsx';
import { SettingsSheet } from './settings/SettingsSheet.tsx';
import { CaptureScreen } from './capture/CaptureScreen.tsx';
import { startRefining } from './capture/refine.ts';
import { startFormatting } from './format/queue.ts';
import { Guide } from './guide/Guide.tsx';
import { useVoiceModel } from './capture/useVoiceModel.ts';
import { installBack } from './core/back.ts';
import { hapticsImpl, installTapHaptics } from './core/haptics.ts';
import { answerHost, takeCaptureLaunch } from './core/host.ts';
import { applyPreferences } from './core/preferences.ts';
import { settleBoot, useUpdates } from './core/ota.ts';
import { isTauri } from './core/tauri.ts';
import { getNote, newNoteId, saveNote, useNotes, type Note } from './core/store.ts';
import { useNoteActions } from './notes/useNoteActions.ts';

/**
 * The whole app: a list, a note, a capture, and a settings sheet.
 *
 * There is no router. Glyph has three screens and a sheet, and a router would
 * be a dependency and a set of edge cases bought to express one piece of state.
 * The phone's back gesture is a stack of handlers instead (core/back.ts): the
 * screen on top says what leaving it means, and the list, at the root, lets
 * Android put the app behind the home screen.
 *
 * A capture can begin three ways, and all three arrive at the same screen: the
 * side key while Glyph is closed (read once at boot), the side key while Glyph
 * is open (pushed by the activity into `window.__glyph.capture`), and the
 * microphone button in the list. Each capture is a fresh mount, keyed, so a
 * second press mid-capture cannot inherit the first one's microphone.
 *
 * `HapticsProvider` is mounted with `enabled={false}` and a native `impl`,
 * which looks contradictory and is not: the flag governs only the kit's own
 * delegated pointerdown tick, which fires at the start of a scroll flick and
 * buzzes all the way down a list. The impl is what `useHaptics()` hands to
 * components, and it is ungated. `installTapHaptics` puts back the tick the
 * flag switched off, on pointerUP, where a tap can be told from a drag.
 */

const GUIDE_KEY = 'glyph-guide-seen';

function guideSeen(): boolean {
  try {
    return localStorage.getItem(GUIDE_KEY) === '1';
  } catch {
    // No storage: showing it every launch would be worse than never.
    return true;
  }
}

function markGuideSeen(): void {
  try {
    localStorage.setItem(GUIDE_KEY, '1');
  } catch {
    // Seen for this run, at least.
  }
}

type Screen =
  | { name: 'list' }
  | { name: 'note'; note: Note }
  | {
      name: 'capture';
      key: number;
      fromAssistant: boolean;
      stop: number;
      /** Talking into this note, from its Speak: the words go here, and the capture comes back here. */
      noteId?: string;
    };

export function App() {
  return (
    <HapticsProvider enabled={false} impl={hapticsImpl}>
      <ToastProvider>
        <Shell />
      </ToastProvider>
    </HapticsProvider>
  );
}

/** Everything under the providers, so it can raise toasts (Undo) itself. */
function Shell() {
  const { notes, loading, refresh } = useNotes();
  const actions = useNoteActions(refresh);
  const [screen, setScreen] = useState<Screen>(() =>
    takeCaptureLaunch() ? { name: 'capture', key: Date.now(), fromAssistant: true, stop: 0 } : { name: 'list' },
  );
  // Read by the side-key handler, which is registered once.
  const screenRef = useRef(screen);
  screenRef.current = screen;
  const [settings, setSettings] = useState(false);
  // The walkthrough opens by itself once, on the first launch that is not a
  // side-key capture - a person who held the key is already mid-sentence.
  const [guide, setGuide] = useState(() => screen.name !== 'capture' && !guideSeen());
  const [guidePage, setGuidePage] = useState(0);

  useEffect(() => {
    // First, before anything that might reload: this frontend mounted, so the
    // build the loader staked on it is safe. See core/ota.ts.
    settleBoot();
    applyPreferences();
    // The phone's back gesture and Escape: each screen registers what
    // leaving it means (core/back.ts); this installs the answer once.
    const uninstallBack = installBack();
    const untap = installTapHaptics();
    return () => {
      uninstallBack();
      untap();
    };
  }, []);

  // New builds, looked for after launch and on return; applied on reload.
  const updates = useUpdates();

  // The side key, while Glyph is already open.
  //
  // During a capture it is the stop button: holding the key again saves, the
  // way pressing a tape recorder's key a second time does. (Letting go cannot
  // stop it - Android tells the assistant app when the key is held, and never
  // when it is released.)
  //
  // Otherwise it clears the stage: the sheet, the walkthrough, an open note
  // (whose editor flushes as it unmounts) and the keyboard all go, so the bare
  // recorder is the only thing on screen - and when it ends, the app lands on
  // the note or the list, not back in a menu.
  useEffect(
    () =>
      answerHost('capture', () => {
        const current = screenRef.current;
        if (current.name === 'capture') {
          setScreen({ ...current, stop: current.stop + 1 });
          return;
        }
        if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
        setSettings(false);
        setGuide(false);
        setScreen({ name: 'capture', key: Date.now(), fromAssistant: true, stop: 0 });
      }),
    [],
  );

  // Fetched when the app opens and again whenever it returns to the screen,
  // so the first held side key starts listening instead of downloading.
  const voiceModel = useVoiceModel();

  // The better words after a recording, worked out in the background; the list
  // is refreshed when a note's words change.
  useEffect(() => startRefining(() => void refresh()), [refresh]);
  // The staged formatting passes after a recording: draft, then revisions.
  useEffect(() => startFormatting(() => void refresh()), [refresh]);

  const openNote = (id: string) => {
    const note = notes.find((n) => n.id === id);
    if (note) setScreen({ name: 'note', note });
  };

  const newNote = async () => {
    // Written to the store immediately rather than on first keystroke: a note
    // that exists only in memory is a note that a backgrounded webview loses,
    // and an empty row in the list is a far smaller problem than a lost one.
    const note = await saveNote(newNoteId(), '', 'editor');
    await refresh();
    setScreen({ name: 'note', note });
  };

  // From the editor's Delete: the same undoable delete a swipe does.
  const removeNote = (id: string) => {
    const note = notes.find((n) => n.id === id);
    setScreen({ name: 'list' });
    if (note) actions.remove(note);
    else void refresh();
  };

  // A capture over the list takes the Undo toast's place; a delete it hides
  // becomes final rather than silently waiting behind the recorder.
  const { flushDeletes } = actions;
  useEffect(() => {
    if (screen.name === 'capture') flushDeletes();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [screen.name]);

  const backToList = async () => {
    setScreen({ name: 'list' });
    await refresh();
  };

  const captureFinished = useCallback(
    async (note: Note | null, locked: boolean) => {
      await refresh();
      // Talking into a note from the note: back to that note, read fresh, since
      // its words just changed (and a Formatted view compares against them).
      // Otherwise the list, the new note at its top: reading it back is a tap
      // away, and a locked phone has already stepped back behind its lock
      // screen, so nothing of the note is shown to whoever is holding it.
      const current = screenRef.current;
      const from = current.name === 'capture' ? current.noteId : undefined;
      if (from && !locked) {
        const fresh = await getNote(note?.id ?? from).catch(() => null);
        if (fresh) {
          setScreen({ name: 'note', note: fresh });
          return;
        }
      }
      setScreen({ name: 'list' });
    },
    [refresh],
  );

  const speakInto = (id: string) => setScreen({ name: 'capture', key: Date.now(), fromAssistant: false, stop: 0, noteId: id });

  return (
    <>
      {screen.name === 'capture' ? (
        <CaptureScreen
          key={screen.key}
          fromAssistant={screen.fromAssistant}
          stopRequests={screen.stop}
          noteId={screen.noteId}
          onFinish={(note, locked) => void captureFinished(note, locked)}
        />
      ) : screen.name === 'note' ? (
        <NoteScreen
          key={screen.note.id}
          note={screen.note}
          onBack={() => void backToList()}
          onDelete={removeNote}
          onSpeak={speakInto}
          onPin={(n) => actions.pin(n)}
          onArchive={(n) => {
            actions.archive(n, true);
            void backToList();
          }}
        />
      ) : (
        <NotesList
          notes={notes}
          loading={loading}
          onOpen={openNote}
          onNew={() => void newNote()}
          onCapture={() => setScreen({ name: 'capture', key: Date.now(), fromAssistant: false, stop: 0 })}
          voiceModel={voiceModel.state}
          onRetryVoiceModel={voiceModel.retry}
          updates={updates}
          onSettings={() => setSettings(true)}
          actions={actions}
          canFlag={canFlag(updates)}
        />
      )}
      <SettingsSheet
        open={settings}
        onClose={() => setSettings(false)}
        updates={updates}
        onGuide={(page = 0) => {
          setSettings(false);
          setGuidePage(page);
          setGuide(true);
        }}
      />
      {/*
        Not over a capture. The side key can arrive while the guide is open -
        most often BECAUSE of it, testing step 2 - and a guide drawn over the
        capture screen hides the recording the person just started. It steps
        aside and comes back when the capture ends, so they carry on where
        they were.
      */}
      {guide && screen.name !== 'capture' ? (
        <Guide
          index={guidePage}
          onIndex={setGuidePage}
          onClose={() => {
            markGuideSeen();
            setGuide(false);
          }}
          onTry={() => setScreen({ name: 'capture', key: Date.now(), fromAssistant: false, stop: 0 })}
        />
      ) : null}
    </>
  );
}

/**
 * Whether star and archive exist on this binary. They need native generation 3
 * (store.rs's flags); an over-the-air page on an older APK keeps delete only,
 * rather than offering a swipe whose command is not there. A browser keeps its
 * notes in localStorage and has had flags all along.
 */
function canFlag(updates: ReturnType<typeof useUpdates>): boolean {
  if (!isTauri()) return true;
  return (updates.status?.nativeGeneration ?? 0) >= 3;
}
