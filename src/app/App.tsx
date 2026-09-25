import { forkShared, readShared } from './share/share.ts';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { HapticsProvider, ToastProvider } from '@glacier/react';
import { UpdateNotice } from './notes/Notices.tsx';
import { HomeScreen } from './home/HomeScreen.tsx';
import { AllNotesScreen } from './notes/AllNotesScreen.tsx';
import type { OpenTask } from './home/dashboard.ts';
import { setItemDone } from './core/boards.ts';
import { NoteScreen } from './editor/NoteScreen.tsx';
import { NoteTabs } from './notes/NoteTabs.tsx';
import { NotesDrawer } from './notes/NotesDrawer.tsx';
import { Aside, AsideCard } from './aside/Aside.tsx';
import { asideContent, readAsideShown, writeAsideShown } from './aside/aside.ts';
import { NoteTree } from './notes/NoteTree.tsx';
import { joinGroup, leaveGroup, newGroup } from './notes/tabGroups.ts';
import { ALL_NOTES, noteIdOf, type Place } from './notes/visited.ts';
import { readSidebarShown, useSidebar, writeSidebarShown } from './core/useWideScreen.ts';
import { SettingsSheet } from './settings/SettingsSheet.tsx';
import { CaptureScreen } from './capture/CaptureScreen.tsx';
import { AcademyScreen } from './academy/AcademyScreen.tsx';
import { CommandBar } from './commands/CommandBar.tsx';
import type { PaletteDoing } from './commands/palette.ts';
import type { NoteView } from './editor/viewMode.ts';
import { academyBannerDue, dismissAcademyBanner } from './academy/banner.ts';
import { WhatsNewSheet } from './notes/WhatsNewSheet.tsx';
import { Guide } from './guide/Guide.tsx';
import { useVoiceModel } from './capture/useVoiceModel.ts';
import { hapticsImpl } from './core/haptics.ts';
import { takeCaptureLaunch } from './core/host.ts';
import { preferences, setPreferences, themeChoice, usePreferences, type ThemePref } from './core/preferences.ts';
import { WispEdgeFilter } from './art/WispEdgeFilter.tsx';
import { useUpdates } from './core/ota.ts';
import { LaunchScreen } from './launch/LaunchScreen.tsx';
import { useSyncStatus } from './core/sync/engine.ts';
import { createNote, getNote, newNoteId, noteTitle, updateNote, useNotes, type Note, listNotes } from './core/store.ts';
import { sameTitle } from './editor/wikiLinks.ts';
import { addBoardNote, addCanvasNote, addHowCanvas, addSampleNote } from './core/seed.ts';
import { canvasNoteBody, isCanvasBody } from './canvas/jsonCanvas.ts';
import { withFrontMatterTitle } from './core/frontMatter.ts';
import { bookNoteBody, bookOf, isBookBody } from './book/book.ts';
import { whereLeft } from './book/bookSpot.ts';
import { NewBookSheet } from './book/NewBookSheet.tsx';
import { NewSheet } from './notes/NewSheet.tsx';
import { chooseWorkspace, fileNewNote, fileNote, useWorkspaces, workspaceOf } from './core/workspaces.ts';
import { useNoteActions } from './notes/useNoteActions.ts';
import { isPlace, noteOnScreen, placeOf, type Screen } from './shell/screen.ts';
import { useCaptureRoute } from './shell/useCaptureRoute.ts';
import { useForkLinks } from './shell/useForkLinks.ts';
import { useGuide } from './shell/useGuide.ts';
import { useHousekeeping } from './shell/useHousekeeping.ts';
import { useOpenTabs } from './shell/useOpenTabs.ts';
import { useRootStamp } from './shell/useRootStamp.ts';
import { useTrail } from './shell/useTrail.ts';
import { useVisibleNotes } from './shell/useVisibleNotes.ts';

/**
 * The whole app: which screen is up, and everything drawn over it.
 *
 * There is no router. Ghost.md has five screens - the home page, the All notes grid, a note, a capture and the
 * Academy (shell/screen.ts) - and a router would be a dependency and a set of edge cases bought to express one piece
 * of state. Everything else is a sheet or a card over whichever screen is up: Settings, the guide, the + sheet, the
 * new book sheet, what's new, the notes drawer, the aside and the palette. The phone's back gesture is a stack of
 * handlers instead of a history (core/back.ts): whatever is on top says what leaving it means, and the home page, at
 * the root, lets Android put the app behind the home screen.
 *
 * The Shell holds that state and the doings that change it. The parts of it that are machines of their own live in
 * shell/ - the open tabs and their groups, the trail the arrows walk, where a capture begins and ends, the guide, a
 * shared link arriving, and the background work that draws nothing - and each says there what has bitten it.
 *
 * `HapticsProvider` is mounted with `enabled={false}` and a native `impl`,
 * which looks contradictory and is not: the flag governs only the kit's own
 * delegated pointerdown tick, which fires at the start of a scroll flick and
 * buzzes all the way down a list. The impl is what `useHaptics()` hands to
 * components, and it is ungated. `installTapHaptics` puts back the tick the
 * flag switched off, on pointerUP, where a tap can be told from a drag.
 */

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
  // A desktop window wide enough keeps the notes in a sidebar beside the open note (core/useWideScreen.ts).
  const sidebar = useSidebar();
  useHousekeeping({ notes, loading, refresh, sidebar });
  const [screen, setScreen] = useState<Screen>({ name: 'list' });
  const [settings, setSettings] = useState(false);
  /** Settings asked to open at the cheat sheet, from the Academy: the moment it was asked for, or 0. */
  const [toCheatSheet, setToCheatSheet] = useState(0);

  // Whether the side key launched the app, asked of the host once (core/host.ts).
  const [launchedByKey] = useState(takeCaptureLaunch);
  const guide = useGuide(launchedByKey);
  const capture = useCaptureRoute({
    screen,
    setScreen,
    refresh,
    flushDeletes: actions.flushDeletes,
    atBoot: launchedByKey && !guide.tooSoonAtBoot,
    tooSoon: guide.onReadingPage,
    sayTooSoon: guide.sayTooSoon,
    clearStage: () => {
      setSettings(false);
      guide.hide();
    },
  });

  // New builds, looked for after launch and on return; applied on reload.
  const updates = useUpdates();
  // The screen opening shows, until the notes are read and the update check has answered (launch/LaunchScreen.tsx).
  const syncStatus = useSyncStatus();
  const [launching, setLaunching] = useState(true);

  // Fetched when the app opens and again whenever it returns to the screen,
  // so the first held side key starts listening instead of downloading.
  const voiceModel = useVoiceModel();

  const [drawer, setDrawer] = useState(false);
  // The docked sidebar, shown or hidden by the top bar's icon (core/useWideScreen.ts `readSidebarShown`).
  const [sidebarShown, setSidebarShown] = useState(readSidebarShown);
  const toggleDock = () => {
    const next = !sidebarShown;
    setSidebarShown(next);
    writeSidebarShown(next);
  };
  // The right-hand aside (aside/Aside.tsx), shown or hidden by the tab row's mirrored icon; kept to this device.
  const [asideShown, setAsideShown] = useState(readAsideShown);
  const toggleAside = () => {
    const next = !asideShown;
    setAsideShown(next);
    writeAsideShown(next);
  };

  // The notes every screen shows: none a pending delete is holding back, none in the trash (shell/useVisibleNotes.ts).
  const { visible: shownNotes, trashed: trashedNotes, live: liveIds } = useVisibleNotes(notes, actions.hidden);

  const shown = noteOnScreen(screen);
  // The notes open as tabs, and their groups (shell/useOpenTabs.ts); and where he has been (shell/useTrail.ts).
  const tabs = useOpenTabs(shown, notes, liveIds);
  const walk = useTrail(placeOf(screen), liveIds);

  const openNote = (id: string) => {
    tabs.replaceNext(null);
    const note = notes.find((n) => n.id === id);
    if (note) setScreen({ name: 'note', note });
    setDrawer(false);
  };
  /**
   * `id` opened from outside it - the home page, the sidebar, the notes list, search: a book goes back to where it was
   * left, the chapter it was being read at (book/bookSpot.ts `whereLeft`). A tab, Back and Forward use `openNote`,
   * and show the note itself.
   */
  const openNoteWhereLeft = (id: string) => {
    const note = notes.find((n) => n.id === id);
    openNote(note ? whereLeft(note, shownNotes, shown).id : id);
  };
  /** `id` opened in the current note's tab. */
  const openNoteWithin = (id: string) => {
    tabs.replaceNext(shown && shown !== id ? shown : null);
    const note = notes.find((n) => n.id === id);
    if (note) setScreen({ name: 'note', note });
    setDrawer(false);
  };

  const backToList = async () => {
    setScreen({ name: 'list' });
    await refresh();
  };

  /** Where one of the arrows said to go (shell/useTrail.ts): the home page, the grid, or a note. */
  const land = (spot: Place | null) => {
    if (!spot) return;
    const id = noteIdOf(spot);
    if (spot === ALL_NOTES) setScreen({ name: 'notes' });
    else if (id === null) void backToList();
    else openNote(id);
  };
  const goBack = () => land(walk.back());
  const goOn = () => land(walk.on());

  const [openCommands, setOpenCommands] = useState<(() => void) | null>(null);
  /*
   * Stable, and the opener kept behind a function of its own: a new identity here would run the palette's effect
   * again on every render, and a setter handed a bare function would take it for an updater and call it mid-render.
   */
  const paletteReady = useCallback((open: () => void) => setOpenCommands(() => open), []);
  const prefs = usePreferences();
  const spaces = useWorkspaces();

  /** One tab closed, or a whole group's; the note being read among them hands over to the tab left beside it. */
  const closeTabs = (ids: readonly string[]) => {
    const next = tabs.close(ids);
    if (next === undefined) return;
    if (next) openNote(next);
    else void backToList();
  };
  const closeTab = (id: string) => closeTabs([id]);

  /** The note by that title in the library, as a `[[link]]` names it (editor/wikiLinks.ts), or undefined. */
  const titled = (title: string) => shownNotes.find((n) => sameTitle(noteTitle(n.body), title));
  /** Whether a note by that title is in the library: what a `[[link]]` is drawn by. */
  const hasTitle = (title: string) => titled(title) !== undefined;
  /** What the aside holds now: the open note's book, or its numbered chapters in order, or nothing (aside/aside.ts). */
  const asideBody = useMemo(() => asideContent(shownNotes, screen.name === 'note' ? screen.note : null), [shownNotes, screen]);
  /** That note's body, for a canvas card that is a note to draw it small (canvas/CanvasView.tsx); null for none. */
  const bodyOfTitle = (title: string) => titled(title)?.body ?? null;

  /**
   * A note just made: filed in the workspace being looked at (core/workspaces.ts), the notes read again, and shown.
   * What the + makes - a note, a canvas, a book - and the note made for a title nobody has written yet end here, in
   * whichever tab the caller asked for before making it: the + and a book take one of their own, and a page made from
   * a book's index takes the book's. A shared link's copy and a Settings sample have ends of their own (`forkFromLink`,
   * `openSample`).
   */
  const showMade = async (body: string) => {
    const note = await createNote(newNoteId(), body, 'editor');
    fileNewNote(note.id);
    await refresh();
    setScreen({ name: 'note', note });
  };

  // A copy of something shared with this person, from its link (share/share.ts): saved into the library, then opened.
  const forkFromLink = async (link: string) => {
    tabs.replaceNext(null);
    const made = await forkShared(await readShared(link));
    await refresh();
    setScreen({ name: 'note', note: made });
  };
  useForkLinks(loading, forkFromLink);

  /**
   * A `[[link]]` tapped: the note by that title, or a new note that starts with it as its heading, so a link is a
   * place to write as well as a place to go. `[[The cabin trip#^friday]]` opens that note on that item: the title half
   * is editor/wikiLinks.ts, the `^anchor` half core/boards.ts, and the note screen does the landing.
   */
  const openTitle = async (title: string, at?: string) => {
    tabs.replaceNext(null);
    // A [[link]] to a book, from outside it, goes back to where the book was left, as the home page's Library does.
    const found = at ? undefined : titled(title);
    const there = found ? whereLeft(found, shownNotes, shown) : null;
    if (there && there !== found) {
      setScreen({ name: 'note', note: there });
      return;
    }
    await openTitleFrom(title, at);
  };
  /** A title opened from inside a book: in the current tab's place. */
  const openTitleWithin = (title: string) => {
    tabs.replaceNext(shown);
    void openTitleFrom(title);
  };
  /** A canvas by that title opened from a book's index, made first if there is none (book/BookView.tsx). */
  const openCanvasWithin = (title: string) => {
    tabs.replaceNext(shown);
    void openTitleFrom(title, undefined, (named) => canvasNoteBody(named, { nodes: [], edges: [] }));
  };
  /** `make` is what a note made for a title nobody has written yet starts as: a heading, or an empty canvas. */
  const openTitleFrom = async (title: string, at?: string, make: (title: string) => string = (named) => `# ${named}\n\n`) => {
    const found = titled(title);
    if (found) {
      setScreen({ name: 'note', note: found, at });
      return;
    }
    // The list in hand can be a moment old - a chapter just made from a book's index is not in it yet - so the store is
    // asked once more before a second note by that title is made.
    const fresh = (await listNotes().catch(() => [])).find((n) => !n.archivedAt && sameTitle(noteTitle(n.body), title));
    if (fresh) {
      await refresh();
      setScreen({ name: 'note', note: fresh, at });
      return;
    }
    await showMade(make(title));
  };

  // Settings > About: a sample note, a board, a canvas or the canvas that explains canvases (core/seed.ts), opened at once.
  const openSample = (add: () => Promise<Note>) => () => {
    tabs.replaceNext(null);
    void (async () => {
      setSettings(false);
      const note = await add();
      await refresh();
      setScreen({ name: 'note', note });
    })();
  };

  /**
   * A book from the + (docs/BOOKS.md): the New book sheet asks its name and which notes are its pages, in what
   * order, and makes one note with that index, opened on it. Filed and kept as a note is.
   */
  const [bookSheet, setBookSheet] = useState(false);
  const newBook = () => setBookSheet(true);
  const createBook = (title: string, pages: readonly string[]) => {
    tabs.replaceNext(null);
    return showMade(bookNoteBody(title, pages));
  };
  /** What can be a page: every note's title but the books' own. */
  const pageTitles = () => shownNotes.filter((n) => !isBookBody(n.body)).map((n) => noteTitle(n.body)).filter((t) => t.trim());

  // Written to the store immediately rather than on first keystroke: a note
  // that exists only in memory is a note that a backgrounded webview loses,
  // and an empty row in the list is a far smaller problem than a lost one.
  // The library holds it as a draft with no file until its first words
  // (docs/LIBRARY.md), so a note opened and left leaves nothing behind.
  // Made while the list shows one workspace, it belongs there (core/workspaces.ts).
  const newNote = () => {
    tabs.replaceNext(null);
    return showMade('');
  };

  /*
   * What the + makes (notes/NewSheet.tsx): a note, a canvas or a book, or a copy from a shared link. The sheet is one
   * for every +, so the choice reads the same wherever it is offered.
   */
  const [newSheet, setNewSheet] = useState(false);

  const newCanvas = () => {
    tabs.replaceNext(null);
    return showMade(canvasNoteBody('Untitled canvas', { nodes: [], edges: [] }));
  };

  // From the editor's Delete: the same undoable delete a swipe does.
  const removeNote = (id: string) => {
    const note = notes.find((n) => n.id === id);
    tabs.drop(id);
    setScreen({ name: 'list' });
    if (note) {
      actions.remove(note);
      return;
    }
    // A note the list has not read yet (one a voice command just made or changed): read it now rather than closing
    // it and deleting nothing.
    void getNote(id)
      .catch(() => null)
      .then((fresh) => {
        if (fresh) actions.remove(fresh);
        return refresh();
      });
  };

  // Glyph Academy offered on the home screen, for someone who has not started it (academy/banner.ts). Read again
  // whenever the list comes back: a lesson passed in there is the card's answer, so it goes.
  const [academyCard, setAcademyCard] = useState(academyBannerDue);
  useEffect(() => {
    if (screen.name === 'list') setAcademyCard(academyBannerDue());
  }, [screen.name]);

  const speak = () => void capture.start(false);
  const speakInto = (id: string) => void capture.start(false, id);

  // The home page, the grid and the open note sit beside the sidebar on a wide desktop window; a capture and the
  // Academy still take the whole window.
  const split = sidebar && isPlace(screen);
  /*
   * The sidebar docked beside the note, rather than a popover over it: a window wide enough, and Docked chosen in
   * Settings. A popover is the default everywhere (Matt: "Sidebar should open and close in a popover not a full
   * sidebar even on desktop", core/preferences.ts `SidebarStyle`). Either way the top bar's icon is the way to it;
   * docked, the icon shows and hides the column.
   */
  const docked = split && prefs.sidebarStyle === 'docked';
  const dockShown = docked && sidebarShown;
  // The aside follows the sidebar's shell: a column beside a docked sidebar, else the drawer's card (aside/Aside.tsx).
  // With nothing to hold - no book, no run of chapters - there is no aside and no toggle for it.
  const asideDocked = docked && asideShown && asideBody !== null;
  // Docking takes over from a card left open, so the notes are never drawn twice.
  useEffect(() => {
    if (docked) setDrawer(false);
  }, [docked]);
  /*
   * The routes that carry the app's tab row (app.css .app-tabBar): the places (shell/screen.ts), which are where a
   * tab means anything. A capture and the Academy are each the whole screen and the way out of them is their own; the
   * bar's height leaves `--app-safe-top` with it, so those screens keep their own top edge.
   */
  const tabBar = isPlace(screen);
  /*
   * And how tall it is: one line of controls, or that line with the open notes under it (app.css `--app-tabs`). The
   * bar is two rows now (Matt: "put the tabs on the next line down"), and the second is not there at all when
   * nothing is open (Matt: "This row can be hidden when there are no tabs open"), so the height has to say which of
   * the two it is - every screen's header clears the bar by `--app-safe-top` without knowing the bar exists.
   */
  useRootStamp('tabs', tabBar ? (tabs.tabs.length ? 'rows' : 'on') : null);
  /*
   * And whether the window is in two panes, said on the root so the stylesheets can ask without holding a copy of the
   * threshold. The rule is one expression in core/useWideScreen.ts; it used to be that expression plus a `900px` in
   * app.css and twice more in settings.css, which is three chances for the app to change shape at three widths.
   */
  useRootStamp('split', sidebar ? 'on' : null);
  /*
   * A canvas renamed from its tab (notes/NoteTabs.tsx): a canvas is named by `title:` in its front matter, since it
   * has no first line to write it in, and the only way to that was the note's own cog.
   *
   * Two ways to write it, and which one depends on whether the note is open. The note being read is the editor's:
   * its live body is a ref that only its own onChange sets, so a saveNote from here would be flushed away by the
   * next keystroke - it is asked instead, and writes it itself. Any other tab has no editor holding it, so it is a
   * plain write, of the body as the store has it rather than as this render remembers it.
   */
  const [rename, setRename] = useState<{ id: string; title: string; asked: number } | null>(null);
  const renameNote = (id: string, title: string) => {
    if (shown === id) {
      setRename({ id, title, asked: Date.now() });
      return;
    }
    void (async () => {
      const note = await getNote(id);
      if (!note) return;
      await updateNote(id, withFrontMatterTitle(note.body, title), note.revision ?? 1);
      await refresh();
    })();
  };
  const noteScreen =
    screen.name === 'note' ? (
      <NoteScreen
        key={screen.note.id}
        note={screen.note}
        onBack={() => void backToList()}
        onDelete={removeNote}
        onSpeak={speakInto}
        onPin={(n) => actions.pin(n)}
        at={screen.at}
        ask={screen.ask}
        review={screen.review}
        onOpenTitle={(title, at) => void openTitle(title, at)}
        hasTitle={hasTitle}
        onOpenWithin={openTitleWithin}
        onNewCanvas={openCanvasWithin}
        book={bookOf(shownNotes, noteTitle(screen.note.body))}
        bodyOfTitle={bodyOfTitle}
        allTitles={() => shownNotes.map((n) => noteTitle(n.body)).filter(Boolean)}
        rename={rename}
        onArchive={(n) => {
          tabs.drop(n.id);
          actions.archive(n, true);
          void backToList();
        }}
      />
    ) : null;
  /*
   * A to-do ticked on the home page: that one line of its note rewritten with its box ticked (core/boards.ts
   * `setItemDone`, the same change the editor's tick makes), and the notes read again.
   */
  const tickTask = async (task: OpenTask) => {
    const note = notes.find((n) => n.id === task.noteId);
    const lines = note?.body.split('\n');
    const line = lines?.[task.line];
    if (!note || !lines || line === undefined) return;
    lines[task.line] = setItemDone(line, true);
    await updateNote(note.id, lines.join('\n'), note.revision ?? 1);
    await refresh();
  };
  /*
   * Every note, from the home page's "All notes": a page of cards (notes/AllNotesScreen.tsx). It used to open the
   * sidebar, which is a tree for jumping to a note you know by name (Matt: "Browsing all notes is super hard there is
   * no good UI it just opens in the sidebar, I'd like a grid view of all the notes"). A note opened from it takes a tab
   * as one opened from anywhere does; its arrow and the phone's back gesture come back home.
   */
  const showAllNotes = () => {
    setDrawer(false);
    setScreen({ name: 'notes' });
  };
  const allNotes = <AllNotesScreen notes={shownNotes} loading={loading} onOpen={openNoteWhereLeft} onBack={() => void backToList()} />;
  /*
   * The home page (home/HomeScreen.tsx): the start page on every screen (Matt: "Add a 'home' button to take us to a
   * dashboard like page"). It took the notes list's place on a phone and the empty "No note open" pane beside the
   * sidebar; the top bar's Glyph mark comes back to it from anywhere.
   */
  const home = (
    <HomeScreen
      notes={shownNotes}
      loading={loading}
      onOpen={(id, at) => {
        if (!at) return openNoteWhereLeft(id);
        const note = notes.find((n) => n.id === id);
        if (note) setScreen({ name: 'note', note, at });
      }}
      onNew={() => setNewSheet(true)}
      onCapture={speak}
      onSettings={() => setSettings(true)}
      onSearch={openCommands ?? undefined}
      onAllNotes={showAllNotes}
      onTick={(task) => void tickTask(task)}
      voiceModel={voiceModel.state}
      onRetryVoiceModel={voiceModel.retry}
      updates={updates}
      showAcademy={academyCard}
      onAcademy={() => setScreen({ name: 'academy' })}
      onHideAcademy={() => {
        dismissAcademyBanner();
        setAcademyCard(false);
      }}
    />
  );

  /*
   * The command palette (commands/palette.ts): what Glyph can do right now, and how. Built here because this is where
   * the app's doings already live - every command below is something a person can also do by hand.
   */
  const paletteWorld = useMemo(
    () => ({
      notes: shownNotes.map((n) => ({ id: n.id, title: noteTitle(n.body) })),
      tabs: tabs.tabs.map((n) => ({ id: n.id, title: noteTitle(n.body) })),
      workspaces: spaces.list.map((w) => ({ id: w.id, name: w.name })),
      workspace: spaces.current?.id ?? null,
      note: screen.name === 'note' ? { id: screen.note.id, title: noteTitle(screen.note.body) } : null,
      filedIn: screen.name === 'note' ? (workspaceOf(screen.note.id)?.id ?? null) : null,
      pinned: screen.name === 'note' ? Boolean(screen.note.starred) : false,
      canBack: walk.canBack,
      canForward: walk.canOn,
      view: prefs.noteView,
      theme: prefs.theme,
      tabGroups: tabs.groups.list.map((g) => ({ id: g.id, name: g.name })),
      tabGroup: screen.name === 'note' ? (tabs.groups.of[screen.note.id] ?? null) : null,
    }),
    [shownNotes, tabs.tabs, spaces, screen, walk.canBack, walk.canOn, prefs.noteView, prefs.theme, tabs.groups],
  );
  const { setGroups } = tabs;
  /*
   * The doings, built on every render: each one closes over this render's tabs, screen and trail. A memo keyed on less
   * than all of them would hand the palette a closure from an older render - "Close tab" would then land on a tab the
   * row no longer has - and one keyed on all of them would be rebuilt every render anyway.
   */
  const paletteDoing: PaletteDoing = {
    openNote,
    openNoteWhereLeft,
    newNote: () => void newNote(),
    speak,
    speakInto,
    closeTab,
    showList: () => void backToList(),
    browseNotes: showAllNotes,
    back: goBack,
    forward: goOn,
    settings: () => setSettings(true),
    cheatSheet: () => {
      setSettings(true);
      setToCheatSheet(Date.now());
    },
    guide: () => guide.show(0),
    academy: () => setScreen({ name: 'academy' }),
    chooseWorkspace,
    fileNote,
    setView: (view: NoteView) => setPreferences({ noteView: view }),
    setTheme: (theme: ThemePref) => setPreferences(themeChoice(theme, preferences())),
    groupTab: (id: string) => setGroups((was) => newGroup(was, id).groups),
    joinTabGroup: (id: string, group: string) => setGroups((was) => joinGroup(was, id, group)),
    leaveTabGroup: (id: string) => setGroups((was) => leaveGroup(was, id)),
    pin: (id: string) => {
      const note = notes.find((n) => n.id === id);
      if (note) actions.pin(note);
    },
    archive: (id: string) => {
      const note = notes.find((n) => n.id === id);
      if (note) actions.archive(note, true);
    },
    remove: removeNote,
  };

  /*
   * An update waiting: the sidebar's to carry on a wide window, where there is no home list to show them
   * (notes/NoteTree.tsx `notices`), docked or floating.
   */
  const notices = <UpdateNotice updates={updates} />;

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
            tabs={tabs.tabs}
            activeId={shown ?? ''}
            onOpen={openNote}
            onClose={closeTab}
            onNew={() => setNewSheet(true)}
            onSidebar={docked ? toggleDock : () => setDrawer((was) => !was)}
            onHome={() => void backToList()}
            atHome={screen.name === 'list'}
            sidebarOpen={docked ? sidebarShown : drawer}
            onAside={asideBody ? toggleAside : undefined}
            asideOpen={asideShown}
            onMove={tabs.move}
            groups={tabs.groups}
            onGroups={setGroups}
            onCloseTabs={closeTabs}
            onGoBack={goBack}
            onGoOn={goOn}
            canGoBack={walk.canBack}
            canGoOn={walk.canOn}
            onRename={renameNote}
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
          onFinish={(note, locked, review, ask) => void capture.finished(note, locked, review, ask)}
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
      ) : split ? (
        <div className="app-split" data-sidebar={dockShown ? 'shown' : 'hidden'} data-aside={asideDocked ? 'shown' : 'hidden'}>
          {/*
            The same tree the pop-up sidebar is (notes/NoteTree.tsx), docked (Matt: "Make the sidebar on desktop the
            same sidebar that shows up in the pop-up sidebar"). It was the whole home list squeezed into a column; the
            one thing that list carried that a desktop has nowhere else to show - an update waiting - comes with it.
          */}
          {dockShown ? (
            <aside className="app-sidebar" aria-label="All notes">
              <NoteTree
                notes={shownNotes}
                activeId={shown}
                onOpen={openNoteWhereLeft}
                onNew={() => setNewSheet(true)}
                onCommands={openCommands ?? undefined}
                onSettings={() => setSettings(true)}
                onSpeak={speak}
                notices={notices}
                trashed={trashedNotes}
                onRestore={actions.restore}
                onDestroy={actions.destroy}
                onEmptyTrash={() => void actions.emptyTrash(trashedNotes)}
              />
            </aside>
          ) : null}
          <main className="app-notePane">
            {noteScreen ?? (screen.name === 'notes' ? allNotes : home)}
          </main>
          {/* The right-hand aside as a column beside a docked sidebar: a book's index, or a run of chapters (aside/Aside.tsx). */}
          {asideDocked && asideBody ? (
            <aside className="app-aside" aria-label="Book index">
              <Aside content={asideBody} onOpen={openNoteWithin} onOpenTitle={openTitleWithin} />
            </aside>
          ) : null}
        </div>
      ) : (
        (noteScreen ?? (screen.name === 'notes' ? allNotes : home))
      )}
      {/* With the sidebar a floating card, the aside is the same card at the right (aside/Aside.tsx `AsideCard`). */}
      {asideShown && !asideDocked && asideBody ? (
        <AsideCard content={asideBody} onOpen={openNoteWithin} onOpenTitle={openTitleWithin} onClose={toggleAside} />
      ) : null}
      <NewSheet open={newSheet} onClose={() => setNewSheet(false)} onNote={() => void newNote()} onCanvas={() => void newCanvas()} onBook={newBook} onFromLink={forkFromLink} />
      <NewBookSheet open={bookSheet} onClose={() => setBookSheet(false)} titles={pageTitles()} isCanvas={(title) => isCanvasBody(bodyOfTitle(title) ?? '')} onCreate={(title, pages) => void createBook(title, pages)} />
      {/* After an update: what it changed, once (notes/WhatsNewSheet.tsx). Not over the guide or a recording. */}
      <WhatsNewSheet sources={updates.status?.sources} hold={guide.open || screen.name === 'capture'} />
      {launching ? <LaunchScreen loading={loading} notes={notes.filter((n) => !n.archivedAt).length} updates={updates} sync={syncStatus} onDone={() => setLaunching(false)} /> : null}
      {/* Every note, in a card over the one being read; the tab row's icon opens it (notes/NotesDrawer.tsx). */}
      <NotesDrawer
        open={drawer}
        notices={split ? notices : undefined}
        notes={shownNotes}
        trashed={trashedNotes}
        onRestore={actions.restore}
        onDestroy={actions.destroy}
        onEmptyTrash={() => void actions.emptyTrash(trashedNotes)}
        activeId={shown}
        onOpen={openNoteWhereLeft}
        onNew={() => {
          setDrawer(false);
          setNewSheet(true);
        }}
        onClose={() => setDrawer(false)}
        onSettings={() => {
          setDrawer(false);
          setSettings(true);
        }}
        onSpeak={() => {
          setDrawer(false);
          speak();
        }}
        onCommands={
          openCommands
            ? () => {
                setDrawer(false);
                openCommands();
              }
            : undefined
        }
      />
      {/* Everything Glyph can do, searched (commands/). ⌘K is the kit's; the drawer's first row is the phone's. */}
      <CommandBar world={paletteWorld} doing={paletteDoing} onReady={paletteReady} />
      <SettingsSheet
        open={settings}
        onClose={() => setSettings(false)}
        updates={updates}
        onGuide={(page) => {
          setSettings(false);
          // A row's press hands its event along; only a number is a page.
          guide.show(typeof page === 'number' ? page : 0);
        }}
        onSample={openSample(addSampleNote)}
        onBoard={openSample(addBoardNote)}
        onCanvas={openSample(addCanvasNote)}
        onHowCanvas={openSample(addHowCanvas)}
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
      {guide.open && screen.name !== 'capture' ? (
        <Guide
          index={guide.page}
          tooSoon={guide.tooSoon}
          onIndex={guide.turn}
          onClose={() => {
            guide.close();
            // The list underneath loaded while the guide was up; ask again now it shows.
            void refresh();
          }}
          onTry={speak}
        />
      ) : null}
    </>
  );
}
