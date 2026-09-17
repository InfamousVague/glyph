import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { HapticsProvider, ToastProvider } from '@glacier/react';
import { NotesList } from './notes/NotesList.tsx';
import { NoteScreen } from './editor/NoteScreen.tsx';
import { NoNoteOpen } from './notes/NoNoteOpen.tsx';
import { NoteTabs } from './notes/NoteTabs.tsx';
import { NotesDrawer } from './notes/NotesDrawer.tsx';
import { addOpen, afterClose, closeOpen, moveOpen, openOnly } from './notes/openTabs.ts';
import { backFrom, canGoBack, canGoOn, FIRST, noteIdOf, notePlace, onFrom, placeAt, went, type Place } from './notes/visited.ts';
import { useSidebar } from './core/useWideScreen.ts';
import { SettingsSheet } from './settings/SettingsSheet.tsx';
import { ReviewScreen } from './review/ReviewScreen.tsx';
import type { ReviewHandoff } from './review/useReview.ts';
import { SortScreen } from './sort/SortScreen.tsx';
import { readScratch, type Scratch } from './capture/scratch.ts';
import { CaptureScreen } from './capture/CaptureScreen.tsx';
import { AcademyScreen } from './academy/AcademyScreen.tsx';
import { academyBannerDue, dismissAcademyBanner } from './academy/banner.ts';
import { startRefining } from './capture/refine.ts';
import { startFormatting } from './format/queue.ts';
import { startSync } from './core/sync/engine.ts';
import { WhatsNewSheet } from './notes/WhatsNewSheet.tsx';
import { Guide } from './guide/Guide.tsx';
import { clearGuideProgress, isReadingPage, launchedTooSoon, markGuideStarted, rememberGuidePage } from './guide/tooSoon.ts';
import { useVoiceModel } from './capture/useVoiceModel.ts';
import { installBack } from './core/back.ts';
import { hapticsImpl, installTapHaptics } from './core/haptics.ts';
import { answerHost, takeCaptureLaunch } from './core/host.ts';
import { applyPreferences } from './core/preferences.ts';
import { WispEdgeFilter } from './art/WispEdgeFilter.tsx';
import { settleBoot, useUpdates } from './core/ota.ts';
import { isTauri } from './core/tauri.ts';
import { getNote, newNoteId, NOTE_SAVED, noteTitle, saveNote, useNotes, type Note } from './core/store.ts';
import { sameTitle } from './editor/wikiLinks.ts';
import { addBoardNote, addSampleNote, sampleNoteSeeded, seedSampleNote } from './core/seed.ts';
import { fileNewNote } from './core/workspaces.ts';
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
  clearGuideProgress();
}

type Screen =
  | { name: 'list' }
  | {
      name: 'note';
      note: Note;
      /** The item to land on, `^anchor`, when the note was opened by a link that pointed inside it (core/boards.ts). */
      at?: string;
    }
  | {
      name: 'capture';
      key: number;
      fromAssistant: boolean;
      stop: number;
      /** Talking into this note, from its Speak: the words go here, and the capture comes back here. */
      noteId?: string;
    }
  /** After Stop: the slower models check the take, and the person commits what they find (review/). */
  | { name: 'review'; handoff: ReviewHandoff }
  /** After a memo: where its parts go, proposed, and filed when committed (sort/). */
  | { name: 'sort'; scratch: Scratch }
  /** Glyph Academy: markdown taught a mark at a time, open from Settings whenever it is wanted (academy/). */
  | { name: 'academy' };

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
  const [screen, setScreen] = useState<Screen>(() => {
    const launch = takeCaptureLaunch();
    // The side key held before the guide got to it: the guide again, not a recording (guide/tooSoon.ts).
    if (launch && launchedTooSoon(guideSeen())) return { name: 'list' };
    return launch ? { name: 'capture', key: Date.now(), fromAssistant: true, stop: 0 } : { name: 'list' };
  });
  // Read by the side-key handler, which is registered once.
  const screenRef = useRef(screen);
  screenRef.current = screen;
  const [settings, setSettings] = useState(false);
  /** Settings asked to open at the cheat sheet, from the Academy: the moment it was asked for, or 0. */
  const [toCheatSheet, setToCheatSheet] = useState(0);
  // The walkthrough opens by itself once, on the first launch that is not a
  // side-key capture - a person who held the key is already mid-sentence.
  const [guide, setGuide] = useState(() => screen.name !== 'capture' && !guideSeen());
  // "Not yet, finish reading.": a relaunch, or the side key, while the guide was still on a reading page.
  const [tooSoon, setTooSoon] = useState(() => screen.name !== 'capture' && launchedTooSoon(guideSeen()));

  const [guidePage, setGuidePage] = useState(0);
  // Read by the side-key handler, which is registered once.
  const guideRef = useRef({ open: guide, page: guidePage });
  guideRef.current = { open: guide, page: guidePage };
  // Where the guide is, kept for a relaunch (guide/tooSoon.ts); gone once it is finished.
  useEffect(() => {
    if (guide) {
      markGuideStarted();
      rememberGuidePage(guidePage);
    }
  }, [guide, guidePage]);

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
        // On a reading page of the guide the key is too soon: the line, not a recording.
        if (guideRef.current.open && isReadingPage(guideRef.current.page)) {
          setTooSoon(true);
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
  // Sync, for a device signed in to an account (docs/SYNC.md); nothing happens without one.
  useEffect(() => startSync(), []);
  // A desktop window wide enough keeps the notes in a sidebar beside the open note (core/useWideScreen.ts).
  const sidebar = useSidebar();
  // The list beside a note shows its title and order as it is written: read again a moment after each save.
  useEffect(() => {
    if (!sidebar) return undefined;
    let timer = 0;
    const saved = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => void refresh(), 300);
    };
    window.addEventListener(NOTE_SAVED, saved);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener(NOTE_SAVED, saved);
    };
  }, [sidebar, refresh]);

  const openNote = (id: string) => {
    const note = notes.find((n) => n.id === id);
    if (note) setScreen({ name: 'note', note });
    setDrawer(false);
  };

  /*
   * The notes a person has open, as tabs over a note (notes/openTabs.ts). Every way into a note ends in a
   * `screen` of its own, so the row is kept here rather than at each of them: a note shown is a note open.
   */
  const [open, setOpen] = useState<string[]>([]);
  const [drawer, setDrawer] = useState(false);
  const shown = screen.name === 'note' ? screen.note.id : null;
  useEffect(() => {
    if (shown) setOpen((was) => addOpen(was, shown));
  }, [shown]);
  // A note deleted here or on another device leaves no tab behind.
  const liveIds = useMemo(() => new Set(notes.map((n) => n.id)), [notes]);
  const openTabs = useMemo(() => openOnly(open, liveIds).map((id) => notes.find((n) => n.id === id)!), [open, liveIds, notes]);
  /*
   * Where he has been, and the arrows that walk it (notes/visited.ts, drawn in the tab bar). Matt: "Add the back and
   * forward arrows in the top bar to the right of the button used to toggle the sidebar and make sure we have full
   * forward and backwards support".
   *
   * The trail records arriving somewhere rather than every way of getting there, so it does not matter which of the
   * many paths into a note was taken - a tab, a link in the words, the floating list, a swipe back. `jumped` is how
   * the arrows say "this move was me": without it, going back would itself be recorded as somewhere new and forward
   * would never mean anything.
   */
  const [trail, setTrail] = useState(FIRST);
  const jumped = useRef(false);
  const place: Place | null = screen.name === 'note' ? notePlace(screen.note.id) : screen.name === 'list' ? 'list' : null;
  useEffect(() => {
    if (!place) return;
    if (jumped.current) {
      jumped.current = false;
      return;
    }
    setTrail((was) => went(was, place));
  }, [place]);
  /** A place worth landing on: the list always, a note only while it still exists. */
  const stillThere = useCallback(
    (spot: Place) => {
      const id = noteIdOf(spot);
      return id === null ? true : liveIds.has(id);
    },
    [liveIds],
  );
  const land = (spot: Place) => {
    jumped.current = true;
    const id = noteIdOf(spot);
    if (id === null) void backToList();
    else openNote(id);
  };
  const goBack = () => {
    const next = backFrom(trail, stillThere);
    const spot = next && placeAt(next);
    if (!next || !spot) return;
    setTrail(next);
    land(spot);
  };
  const goOn = () => {
    const next = onFrom(trail, stillThere);
    const spot = next && placeAt(next);
    if (!next || !spot) return;
    setTrail(next);
    land(spot);
  };

  const closeTab = (id: string) => {
    const next = id === shown ? afterClose(openOnly(open, liveIds), id) : null;
    setOpen((was) => closeOpen(was, id));
    if (id !== shown) return;
    if (next) openNote(next);
    else void backToList();
  };

  /** Whether a note by that title is in the library: what a `[[link]]` is drawn by (editor/wikiLinks.ts). */
  const hasTitle = (title: string) => notes.some((n) => sameTitle(noteTitle(n.body), title));

  /**
   * A `[[link]]` tapped: the note by that title, or a new note that starts with it as its heading, so a link is a
   * place to write as well as a place to go.
   */
  /**
   * A [[link]] in the words. `[[The cabin trip#^friday]]` opens that note on that item: the title half is
   * editor/wikiLinks.ts, the `^anchor` half core/boards.ts, and the note screen does the landing.
   */
  const openTitle = async (title: string, at?: string) => {
    const found = notes.find((n) => sameTitle(noteTitle(n.body), title));
    if (found) {
      setScreen({ name: 'note', note: found, at });
      return;
    }
    const made = await saveNote(newNoteId(), `# ${title}\n\n`, 'editor');
    fileNewNote(made.id);
    await refresh();
    setScreen({ name: 'note', note: made });
  };

  // A fresh library gets the sample note once (core/seed.ts): a few seconds
  // after the first read comes back empty, past the store's own re-asks, so a
  // slow first answer from the phone is never mistaken for an empty library.
  useEffect(() => {
    if (loading || sampleNoteSeeded()) return undefined;
    const timer = window.setTimeout(() => {
      void seedSampleNote(notes.length).then((made) => made && refresh());
    }, 4000);
    return () => window.clearTimeout(timer);
  }, [loading, notes.length, refresh]);

  // Settings > About: another sample note, opened at once.
  const sampleNote = async () => {
    setSettings(false);
    const note = await addSampleNote();
    await refresh();
    setScreen({ name: 'note', note });
  };

  const boardNote = async () => {
    setSettings(false);
    const note = await addBoardNote();
    await refresh();
    setScreen({ name: 'note', note });
  };

  const newNote = async () => {
    // Written to the store immediately rather than on first keystroke: a note
    // that exists only in memory is a note that a backgrounded webview loses,
    // and an empty row in the list is a far smaller problem than a lost one.
    // The library holds it as a draft with no file until its first words
    // (docs/LIBRARY.md), so a note opened and left leaves nothing behind.
    const note = await saveNote(newNoteId(), '', 'editor');
    // Made while the list shows one workspace: it belongs there (core/workspaces.ts).
    fileNewNote(note.id);
    await refresh();
    setScreen({ name: 'note', note });
  };

  // From the editor's Delete: the same undoable delete a swipe does.
  const removeNote = (id: string) => {
    const note = notes.find((n) => n.id === id);
    setOpen((was) => closeOpen(was, id));
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

  // A memo said and not yet sorted: one finished while the phone was locked, left with Back, or cut off when the app
  // was killed mid-memo (capture/scratch.ts). Read again whenever the list comes back.
  const [memoWaiting, setMemoWaiting] = useState(() => readScratch() !== null);
  useEffect(() => {
    if (screen.name === 'list') setMemoWaiting(readScratch() !== null);
  }, [screen.name]);

  // Glyph Academy offered on the home screen, for someone who has not started it (academy/banner.ts). Read again
  // whenever the list comes back: a lesson passed in there is the card's answer, so it goes.
  const [academyCard, setAcademyCard] = useState(academyBannerDue);
  useEffect(() => {
    if (screen.name === 'list') setAcademyCard(academyBannerDue());
  }, [screen.name]);

  const captureFinished = useCallback(
    async (note: Note | null, locked: boolean, review?: ReviewHandoff, sort?: Scratch) => {
      // A memo: sorted now, or, over a locked phone, waiting on the list until it is unlocked.
      if (sort) {
        await refresh();
        setMemoWaiting(true);
        setScreen(locked ? { name: 'list' } : { name: 'sort', scratch: sort });
        return;
      }
      // A spoken note lands in the workspace the list is showing, unless it is filed already.
      if (note) fileNewNote(note.id);
      await refresh();
      if (note && review) {
        setScreen({ name: 'review', handoff: review });
        return;
      }
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

  // The list and the open note sit side by side on a wide desktop window; the capture, review and sort
  // flows still take the whole window.
  const split = sidebar && (screen.name === 'list' || screen.name === 'note');
  /*
   * The routes that carry the app's tab row (app.css .app-tabBar): the list and a note, which are the two places a
   * tab means anything. A capture, a review, a sort and the Academy are each the whole screen and the way out of them
   * is their own; the bar's height leaves `--app-safe-top` with it, so those screens keep their own top edge.
   */
  const tabBar = screen.name === 'list' || screen.name === 'note';
  useEffect(() => {
    const root = document.documentElement;
    if (tabBar) root.dataset.tabs = 'on';
    else delete root.dataset.tabs;
    return () => {
      delete root.dataset.tabs;
    };
  }, [tabBar]);
  const noteScreen =
    screen.name === 'note' ? (
      <NoteScreen
        key={screen.note.id}
        note={screen.note}
        onBack={() => void backToList()}
        showBack={!split}
        onDelete={removeNote}
        onSpeak={speakInto}
        onPin={(n) => actions.pin(n)}
        at={screen.at}
        onOpenTitle={(title, at) => void openTitle(title, at)}
        hasTitle={hasTitle}
        onArchive={(n) => {
          setOpen((was) => closeOpen(was, n.id));
          actions.archive(n, true);
          void backToList();
        }}
      />
    ) : null;
  const notesList = (
    <NotesList
      selectedId={screen.name === 'note' ? screen.note.id : undefined}
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
      showAcademy={academyCard}
      onAcademy={() => setScreen({ name: 'academy' })}
      onHideAcademy={() => {
        dismissAcademyBanner();
        setAcademyCard(false);
      }}
      memoWaiting={memoWaiting}
      onSortMemo={() => {
        const waiting = readScratch();
        if (waiting) setScreen({ name: 'sort', scratch: { ...waiting, done: true } });
        else setMemoWaiting(false);
      }}
    />
  );

  return (
    <>
      {/* Under the status bar: what scrolls up fades out before it reaches the phone's clock and icons. */}
      <div className="app-statusScrim" aria-hidden="true" />
      {/* The Mac app's title bar: drags the window (app.css .app-dragBar; nothing on a phone). */}
      <div className="app-dragBar" data-tauri-drag-region aria-hidden="true" />
      {/*
        The app's own tab row, one bar of one height on every route that has it (app.css .app-tabBar). It used to be
        a row each screen's header carried, so it was as tall as that screen felt like being (Matt: "I want the tab
        nav to be the same height and dimensions across every route so make it part of the main app layout, also put
        the sidebar toggle in the same row as the tabs"). The screens know nothing about it: `--app-safe-top` carries
        its height, which is what every header already pads by.
      */}
      {tabBar ? (
        <div className="app-tabBar">
          <NoteTabs
            tabs={openTabs}
            activeId={screen.name === 'note' ? screen.note.id : ''}
            onOpen={openNote}
            onClose={closeTab}
            onSidebar={split ? undefined : () => setDrawer((was) => !was)}
            sidebarOpen={drawer}
            onMove={(id, to) => setOpen((was) => moveOpen(was, openTabs.map((n) => n.id), id, to))}
            onGoBack={goBack}
            onGoOn={goOn}
            canGoBack={canGoBack(trail, stillThere)}
            canGoOn={canGoOn(trail, stillThere)}
          />
        </div>
      ) : null}
      {/* The wisp edge's filter, for every view that scrolls under a header (art/wispEdge.ts). */}
      <WispEdgeFilter />
      {screen.name === 'capture' ? (
        <CaptureScreen
          key={screen.key}
          fromAssistant={screen.fromAssistant}
          stopRequests={screen.stop}
          noteId={screen.noteId}
          onFinish={(note, locked, review, sort) => void captureFinished(note, locked, review, sort)}
        />
      ) : screen.name === 'academy' ? (
        <AcademyScreen
          onDone={() => setScreen({ name: 'list' })}
          onCheatSheet={() => {
            setScreen({ name: 'list' });
            setSettings(true);
            setToCheatSheet(Date.now());
          }}
        />
      ) : screen.name === 'sort' ? (
        <SortScreen
          key={screen.scratch.id}
          scratch={screen.scratch}
          onDone={(id) => {
            void (async () => {
              setMemoWaiting(readScratch() !== null);
              await refresh();
              if (id) fileNewNote(id);
              const fresh = id ? await getNote(id).catch(() => null) : null;
              setScreen(fresh ? { name: 'note', note: fresh } : { name: 'list' });
            })();
          }}
        />
      ) : screen.name === 'review' ? (
        <ReviewScreen
          key={screen.handoff.noteId}
          handoff={screen.handoff}
          onDone={(id) => {
            void (async () => {
              await refresh();
              const fresh = await getNote(id).catch(() => null);
              setScreen(fresh ? { name: 'note', note: fresh } : { name: 'list' });
            })();
          }}
        />
      ) : split ? (
        <div className="app-split">
          <aside className="app-sidebar" aria-label="All notes">
            {notesList}
          </aside>
          <main className="app-notePane">
            {noteScreen ?? <NoNoteOpen onNew={() => void newNote()} onCapture={() => setScreen({ name: 'capture', key: Date.now(), fromAssistant: false, stop: 0 })} />}
          </main>
        </div>
      ) : (
        (noteScreen ?? notesList)
      )}
      {/* After an update: what it changed, once (notes/WhatsNewSheet.tsx). Not over the guide or a recording. */}
      <WhatsNewSheet sources={updates.status?.sources} hold={guide || screen.name === 'capture'} />
      {/* Every note, in a card over the one being read; the tab row's icon opens it (notes/NotesDrawer.tsx). */}
      <NotesDrawer
        open={drawer && screen.name === 'note'}
        notes={notes}
        activeId={shown}
        onOpen={openNote}
        onNew={() => {
          setDrawer(false);
          void newNote();
        }}
        onClose={() => setDrawer(false)}
      />
      <SettingsSheet
        open={settings}
        onClose={() => setSettings(false)}
        updates={updates}
        onGuide={(page) => {
          setSettings(false);
          // A row's press hands its event along; only a number is a page.
          setGuidePage(typeof page === 'number' ? page : 0);
          setGuide(true);
        }}
        onSample={() => void sampleNote()}
        onBoard={() => void boardNote()}
        onAcademy={() => {
          setSettings(false);
          setScreen({ name: 'academy' });
        }}
        toCheatSheet={toCheatSheet}
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
          tooSoon={tooSoon}
          onIndex={(index) => {
            setGuidePage(index);
            setTooSoon(false);
          }}
          onClose={() => {
            markGuideSeen();
            setGuide(false);
            // The list underneath loaded while the guide was up; ask again now it shows.
            void refresh();
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
