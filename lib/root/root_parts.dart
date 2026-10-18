part of 'ghost_root.dart';

/// What the root puts on screen: everything in [_GhostRootState._whole], made once, and what each part of it is
/// built from. The shell and the screens it is handed (the home page, a note's desk, All notes, an organization's
/// pages, the recorder, the sidebars, the aside, the notifications), and over it the phone at work, Settings, the
/// palette, a note's menu, the + sheet and the new notebook's, a workspace's and an organization's sheets, the way
/// into an account, an invitation, the walkthrough and the launch screen.
///
/// Each is a part (lib/root/selected.dart): it says what it reads, as a record of values, and is built again
/// when that record is another and at no other time. So the pattern for every one of them is two things side by
/// side, what it selects and what it builds, and a part that reads something new must select it too.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which). Nothing here is held:
/// what the parts read (the notes shown, the counts, which sheet is open) are the class's fields.
extension _RootParts on _GhostRootState {
  /// A part of what is on screen: built when [select] answers another value than it drew, and at no other time
  /// (lib/root/selected.dart).
  Widget _part<T>(String name, T Function() select, WidgetBuilder builder) =>
      Selected<T>(listenable: _tick, name: name, select: select, builder: (context, _) => builder(context));

  static const Widget _nothing = SizedBox.shrink();

  /// What [_whole] is made of, once (the field is the class's own).
  Widget _wholeOf() => AccountScope(
    services: _services,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _part('shell', _shellReads, _shellPart),
        // The phone at work, over the app, while a review is on the note being read (lib/scene/at_work.dart).
        // It reads the note's words, and follows its AI, only while a review is on it: with none the scene is not
        // up, and a save of the note, or its AI finding its model as the note opens, is nothing to it.
        _part('atWork', () {
          final ai = _noteAi, id = _noteAiId;
          if (ai == null || id == null) return null;
          final reviewing = ai.reviewKey != null || ai.reviewStage.value != null;
          return (ai, id, reviewing ? _aiAt : 0, reviewing ? _library.noteOf(id) : null, _voice);
        }, _atWorkPart),
        // Settings is handed what its pages read whether it is open or shut (the models, the tapes' room, the
        // updates), so it is built again as those change; never for a runner's turn or the home page's news.
        _part('settings', () => (_settings, _settingsPage, _voice, _voiceAt, _modelsAt, _updatesAt, _voice == null ? null : _tapeFacts, _voice == null || _read, preferences.value.formatModel, _builtReport.value, _claudeOn), _settingsPart),
        // The palette's commands and a note's menu are made from the notes while each is open; shut, neither
        // draws anything, and each is built with the notes as they are the moment it opens.
        _part('commands', () => ((_commands.currentState?.isOpen ?? false) ? _library.value : null, _workspaces.value, _prefsAt, _capture != null), _commandsPart),
        _part('noteMenu', () => _menu.value == null ? null : (_shown, _claudeOn), _noteMenuPart),
        // What the + makes (notes/NewSheet.tsx). The rows read where to make it as they are pressed, since the
        // sheet closes first.
        _part(
          'newSheet',
          () => _newSheet ? (_newInto, _shown, _shell.currentState?.shown, _capture != null, _voiceAt, preferences.value.meetingSound) : null,
          _newSheetPart,
        ),
        _part('newBook', () => _bookSheet == null ? null : (_bookSheet, _bookInto, _shown), _newBookPart),
        _part('workspace', () => _workspace, _workspacePart),
        // The chat with Claude (lib/claude/claude_chat.dart): it hears the runner for itself while it is up.
        _part('askClaude', () => (_askClaude && _claudeOn, _chatAgent, _chatInitial), _askClaudePart),
        // Claude talked to (lib/claude/claude_voice_sheet.dart): it hears the talk for itself while it is up.
        _part('claudeTalk', () => _claudeOn ? _talk : null, _talkPart),
        // A smart notebook's sheet: a search kept by name, or one changed (lib/root/organize.dart).
        OrganizeSheets(organize: _organize),
        if (_services case final services?) ...[
          _part('organization', () => (_organization, _accountAt, _syncAt, _organization == null ? 0 : _presenceAt), (context) => _organizationSheetPart(services)),
          _part('newOrganization', () => (_newOrganization, _accountAt, _syncAt), (context) => _newOrganizationPart(services)),
          // The way in, the first thing on screen once, on an open that is signed out. Never over a recorder
          // (App.tsx: `accountGate.open && !isRecording(screen)`): it waits under one.
          _part('gate', () => (_gate, _gate?.open ?? false, _shell.currentState?.screen.isRecording ?? false, _accountAt, _syncAt), (context) {
            final gate = _gate;
            return gate != null && gate.open && !(_shell.currentState?.screen.isRecording ?? false) ? AccountGate(services: services, onDone: gate.close) : _nothing;
          }),
        ],
        // An invite link that opened the app, and a code held on this device from before, asked about once
        // someone is signed in: nothing is joined until the person says so. Held back while the way into an
        // account is up at launch.
        _part(
          'join',
          () => (_joinRequest, _gate?.open, _accountAt, _syncAt),
          (context) => JoinInvites(
            services: _services,
            request: _joinRequest,
            hold: _services != null && (_gate?.open ?? true),
            onOpen: (id) => _shell.currentState?.openOrganization(id),
            onAccount: _toAccount,
          ),
        ),
        // The walkthrough, over everything but the way into an account, and never over a recorder: it is taken
        // away while a capture is on screen and comes back, at its page, when the capture ends.
        _part('guide', () {
          final guide = _guide;
          if (guide == null || !guide.open || (_gate?.open ?? false) || (_shell.currentState?.screen.isRecording ?? false)) return null;
          return (guide.page, guide.tooSoon, _capture != null, _modelsForGuide);
        }, _guidePart),
        // Something another app shared: its sheet, over the app, one share at a time (lib/share/ui/share_in_sheet.dart).
        _part('shareIn', () => _sharing.isEmpty || _launching ? null : _sharing.first, _shareInPart),
        _part('launch', () => _launching ? (_launchLoading, _launchNotes, _updatesAt, _launchSync, _voice) : null, _launchPart),
      ],
    ),
  );

  /// What the shell is handed: built again when one of these is another, and for nothing else. The screens it
  /// holds are parts of their own.
  Object _shellReads() {
    final prefs = preferences.value;
    return (
      _shellDraws,
      _drafts,
      prefs.topBar,
      prefs.sidebarStyle,
      _workspaces.value,
      // Who is signed in and the organizations joined.
      _accountAt,
      prefs.openNotes,
      prefs.tabGroups,
      // Whether there is a recorder, and a meeting's service, to put on screen.
      _voice != null && _capture != null,
      _voice?.live != null,
      readSidebarShown(_stored),
      readAsideShown(_stored),
      _unread,
      // The app's Claude's bar under the top bar (the Claude plugin's switch).
      _claudeOn,
    );
  }

  /// Whether something unread and wanted waits (`unreadNotifications`). The feed is counted again when the account
  /// said something or Settings › Notifications' switches are others, and at no other time.
  bool get _unread {
    final prefs = preferences.value.notifications;
    if (_unreadAt != _accountAt || !identical(prefs, _unreadFor)) {
      _unreadAt = _accountAt;
      _unreadFor = prefs;
      _unreadNow = unreadNotifications(_services, prefs) > 0;
    }
    return _unreadNow;
  }

  Widget _shellPart(BuildContext context) {
    final prefs = preferences.value;
    final services = _services;
    final signedIn = services?.signedIn ?? false;
    final voice = _voice;
    final capture = _capture;
    // What the shell draws from here on, for the next change to be measured against (`_shellDraws`).
    final shown = _shellNotes = _shown;
    return AppShell(
      key: _shell,
      sheet: widget.sheet ?? context.tokens.sheet,
      notes: shown,
      // A note with no words yet is its own screen's alone, as on the page, whose list never holds it.
      drafts: _drafts,
      topBar: TopBarStyle.parse(prefs.topBar),
      sidebarStyle: prefs.sidebarStyle == 'docked' ? SidebarStyle.docked : SidebarStyle.popover,
      workspaces: _workspaces.value,
      organizations: signedIn ? services!.joined : const [],
      organizationBuilder: services == null ? null : _organizationPage,
      onRenameNote: _rename,
      openNotes: prefs.openNotes,
      tabGroups: prefs.tabGroups,
      // The screen and the tabs are what an entry is left by.
      onOpenNotesChanged: (open) {
        preferences.update((now) => now.copyWith(openNotes: open));
        _left();
      },
      // And the walkthrough steps aside for a recorder, so the parts that read the screen are told.
      onScreenChanged: (screen) {
        _left();
        _extras?.screen(screen);
        _tick.tell();
      },
      untouchedEntryOf: (id) => _untouched.recordOf(id)?.journalId,
      onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
      onSettings: _openSettings,
      // The people icon with no organization joined, and the picker's last row: Settings › Organizations.
      onOrganizations: () => _openSettingsAt('organizations'),
      onNew: _plus,
      // Whether the bell rings: something unread the person asked to see (`unreadCount`).
      unread: _unread,
      onDeleteNote: _delete,
      onRefresh: _library.refresh,
      // Claude in the bar while an AI is online, and the bar that says it is followed (docs/CLAUDE_LIVE.md): each
      // hears Follow for itself.
      // Claude is on the home page's dock now (lib/claude/claude_dock.dart), not in the bar. Under the bar: Follow's
      // bar for an AI through the connector, and the app's own Claude's while it works (docs/CLAUDE_APP.md).
      banner: _claudeBanner(),
      noteBuilder: _note,
      // The recorder, the whole window: a fresh mount for each capture, keyed by the shell.
      captureBuilder: voice == null || capture == null
          ? null
          : (context, shell, screen) => _part(
                'capture',
                () => (screen, _voiceAt),
                (context) => CaptureScreen(
                  recorder: voice.recorder,
                  fromAssistant: screen.fromAssistant,
                  stopRequests: screen.stop,
                  noteId: screen.noteId,
                  placing: screen.placing is Placing ? screen.placing as Placing : null,
                  meeting: screen.meeting,
                  onMeeting: voice.canMeet ? () => unawaited(capture.meeting(false)) : null,
                  onFinish: (note, locked, {review, ask, landing}) => unawaited(capture.finished(note, locked, review: review, ask: ask, landing: landing)),
                ),
              ),
      // Ghost.md Academy, the whole window: out by its arrow, and its contents' way to the cheat sheet.
      academyBuilder: (context, shell) => _part(
        'academy',
        () => shell,
        (context) => AcademyScreen(
          onDone: shell.backToList,
          onCheatSheet: () {
            shell.backToList();
            _openSettingsAt('cheatsheet');
          },
        ),
      ),
      meetingBuilder: voice == null || capture == null || voice.live == null
          ? null
          : (context, shell, screen) => _part(
                'meeting',
                () => (screen, _voiceAt),
                (context) => MeetingScreen(
                  noteId: screen.noteId,
                  fromAssistant: screen.fromAssistant,
                  onLeave: capture.leftMeeting,
                  live: voice.live!,
                  host: _meetingHost(voice, voice.live!),
                ),
              ),
      homeBuilder: _home,
      allNotesBuilder: (context, shell, screen) => _part(
        'allNotes',
        () => (shell.notes, !_read, screen.tapes, _workspaces.value, preferences.value.wispEdge, _claudeOn, _canTalk),
        (context) => AllNotesScreen(
          // The empty page's hint, as home's: the side key on any Android phone (AllNotesScreen.tsx `isAndroid`).
          sideKey: defaultTargetPlatform == TargetPlatform.android,
          notes: shell.notes,
          loading: !_read,
          workspaces: _workspaces,
          stored: _stored,
          tapes: screen.tapes,
          clock: widget.clock,
          onOpen: (id) => _openWhereLeft(shell, id),
          onBack: shell.backToList,
          onRefresh: _pullRefresh,
          onNoteMenu: (note, at) => _menu.open(note.id, at),
          notesInWorkspace: _notesIn,
          onTrashNotes: _trashNotes,
          // An organization's pill opens its page; its sheet's row, its settings.
          onOrganization: _services == null ? null : shell.openOrganization,
          onOrganizationSettings: _services == null ? null : _openOrganizationSettings,
          wisp: preferences.value.wispEdge,
          onSaveSearch: _organize.saveSearch,
          dock: _notesDock(),
        ),
      ),
      // The Tags page, a tag's notes and a smart notebook's (lib/notes/collection_screen.dart).
      collectionBuilder: (context, shell, screen) => _part(
        'collection',
        () => (screen, shell.notes, _workspaces.value, _claudeOn, _canTalk),
        (context) => CollectionScreen(
          kind: screen.kind,
          name: screen.key,
          notes: shell.notes,
          workspaces: _workspaces.value,
          smart: _organize.smart,
          onOpen: (id) => _openWhereLeft(shell, id),
          onBack: screen.kind == CollectionKind.tag && screen.fromTags ? _organize.showTags : shell.backToList,
          onTag: (tag) => _organize.showTag(tag, fromTags: screen.kind == CollectionKind.tags),
          onRenameTag: _organize.renameTag,
          onEditSmart: _organize.editSmart,
          onNoteMenu: _menu.open,
          stored: _stored,
          clock: widget.clock,
          dock: _notesDock(),
        ),
      ),
      sidebarBuilder: (context, shell, close) => _part(
        'sidebar',
        () => _sidebarReads(shell),
        (context) => NotesDrawer(
          open: true,
          notes: shell.notes,
          activeId: shell.shown,
          workspaces: _workspaces,
          stored: _stored,
          onOpen: (id) {
            close();
            _openWhereLeft(shell, id);
          },
          onNew: () {
            close();
            _plus();
          },
          onClose: close,
          onCommands: _search,
          onBrowseFiles: _browseFiles,
          onGraph: () {
            close();
            _showGraph();
          },
          // `notices={split ? notices : undefined}`: a phone has its home page for them.
          notices: splitFits(MediaQuery.sizeOf(context), mouse: mousePointer) ? _sidebarNotices() : const [],
          onSpeak: _capture == null
              ? null
              : () {
                  close();
                  _speak();
                },
          onSettings: () {
            close();
            _openSettings();
          },
          trashed: _trashed,
          onRestore: _actions.restore,
          onDestroy: _actions.destroy,
          onEmptyTrash: () => _actions.emptyTrash(_trashed),
          notesInWorkspace: _notesIn,
          onTrashNotes: _trashNotes,
          onOrganization: _services == null ? null : _openOrganizationSettings,
          onNoteMenu: _menu.open,
          emptyArt: const Ghost(scene: GhostScene.noNotes),
          smart: _organize.smart,
          onSmart: (id) {
            close();
            _organize.showSmart(id);
          },
          onManageSmart: _organize.editSmart,
          onTags: () {
            close();
            _organize.showTags();
          },
        ),
      ),
      dockedSidebarBuilder: (context, shell) => _part('tree', () => _sidebarReads(shell), (context) => _tree(shell)),
      // The docked sidebar and the aside, shown or hidden as this device left them (core/useWideScreen.ts
      // `readSidebarShown`, aside/aside.ts `readAsideShown`).
      sidebarShown: readSidebarShown(_stored),
      onSidebarShownChanged: (shown) => writeSidebarShown(shown, _stored),
      asideShown: readAsideShown(_stored),
      onAsideShownChanged: (shown) => writeAsideShown(shown, _stored),
      // The open note's book or run of chapters, beside it (aside/aside_panel.dart). The version history's
      // tab is a desktop's (`asideHistory`), and waits for one.
      // The open note's book or run of chapters, and on a desktop its version history: with neither there is no
      // aside and no toggle for it (`asideHolds`).
      asideBuilder: (context, shell) {
        final content = _asideOf(shell);
        final history = _asideHistory(context, shell);
        // And, with room for two panes, the open note's links and outline (lib/links/note_links.dart).
        final links = _asideLinks(context, shell), outline = _asideOutline(context, shell);
        return content == null && history == null && links == null
            ? null
            : AsidePanel(content: content, history: history, links: links, outline: outline, stored: _stored, onOpen: shell.openNoteWithin, onOpenTitle: _openTitleWithin);
      },
      asideCardBuilder: (context, shell, close) => AsideCard(
        content: _asideOf(shell),
        history: _asideHistory(context, shell),
        links: _asideLinks(context, shell),
        outline: _asideOutline(context, shell),
        stored: _stored,
        onOpen: shell.openNoteWithin,
        onOpenTitle: _openTitleWithin,
        onClose: close,
      ),
      notificationsBuilder: (context, shell, close) => _part('notifications', () => (preferences.value.notifications, _accountAt, _syncAt), (context) {
        void openNote(String id, String? at) {
          close();
          // A note Claude edited opens at its first changed line; any other where it was left.
          if (at == null) return _openWhereLeft(shell, id);
          shell.openNote(id, at: at);
        }

        void account() {
          close();
          _toAccount();
        }

        // The empty card's ghost, with everything ticked (`Ghost scene="all-ticked" size="small"`).
        const allRead = Ghost(scene: GhostScene.allTicked, size: GhostSize.small);

        if (services != null) {
          return FedNotificationsDrawer(
            services: services,
            onClose: close,
            onOpenNote: openNote,
            onOpenOrganization: (id) {
              close();
              shell.openOrganization(id);
            },
            onAccount: account,
            emptyArt: allRead,
          );
        }
        return NotificationsDrawer(notifications: const [], prefs: preferences.value.notifications, signedIn: false, onClose: close, onOpenNote: openNote, onOpenOrganization: (_) => close(), onAccount: account, emptyArt: allRead);
      }),
    );
  }

  /// What either sidebar reads: the notes and the one on screen, the workspaces, the trash, whether there is a
  /// folder to browse and a recorder to speak to, and the update a wide window's sidebar carries.
  Object _sidebarReads(AppShellState shell) => (shell.notes, shell.shown, _workspaces.value, _trashed, _canBrowse, _capture != null, _updatesAt);

  /// The home page, while it is the screen (the shell takes it down under a note, the grid and an organization's
  /// page, and makes it anew on the way back, as the page's is: lib/shell/app_shell.dart). It is built again for
  /// the notes it shows, its layout, the workspace looked at, a recording, its notices, and the organizations with
  /// who is in them. The lines under its cards are its own to ask for and each card's to hear.
  Widget _home(BuildContext context, AppShellState shell) => _part(
        'home',
        () => (
          shell.notes,
          !_read,
          preferences.value.homeLayout,
          _workspaces.value.current?.id,
          _capture != null,
          _recordingNow,
          _updatesAt,
          _voiceModelLine,
          _accountAt,
          _presenceAt,
          // Claude on the dock, or not (the Claude plugin's switch).
          _claudeOn,
          // Simple mode's Academy card (GHST-103): whether it is due now.
          _academyCardDue,
        ),
        (context) => _homePage(context, shell),
      );

  Widget _homePage(BuildContext context, AppShellState shell) {
    final services = _services;
    final signedIn = services?.signedIn ?? false;
    // The organization the home page is filtered to, for its news.
    final chosen = _workspaces.value.current?.id;
    String? chosenOrg;
    for (final org in services?.joined ?? const <OrgRow>[]) {
      if (orgWorkspaceId(org.id) == chosen) chosenOrg = org.id;
    }
    return HomeScreen(
      notes: shell.notes,
      loading: !_read,
      workspaces: _workspaces,
      layout: homeLayoutOf(preferences.value.homeLayout),
      onOpen: (id) => _openFromHome(shell, id),
      onNew: _plus,
      // The dock's microphone, and the note of the meeting being recorded now.
      onCapture: _capture == null ? null : _speak,
      recording: _recordingNow,
      // `isAndroid ? 'Write it, or hold the side key and say it.'`: the page says the side key on any Android
      // phone, whether or not this build answers it, and the empty page's words are held to the page's.
      sideKey: defaultTargetPlatform == TargetPlatform.android,
      notices: _notices(),
      clock: widget.clock,
      onAllNotes: shell.showAllNotes,
      onSearch: _search,
      // Claude at the head of the dock: Ask Claude, and Claude at work or online (docs/CLAUDE_APP.md); Settings at
      // its foot (docs/DOCK.md).
      claude: _claudeDock(),
      // Talk to Claude under it, where Claude is on and the build can hear.
      claudeTalk: _claudeTalkDock(),
      onSettings: _openSettings,
      // `tabs.drop(note.id)` before an archive or a delete (App.tsx `onSwipe`): the swiped note's tab goes too.
      onSwipe: (note, action) {
        if (action.name != 'pin') _shell.currentState?.dropTab(note.id);
        _actions.swipe(note, action);
      },
      onRefresh: _pullRefresh,
      onNoteMenu: _menu.open,
      onManageWorkspace: (workspace) => _told(() => _workspace = (editing: workspace)),
      organizations: homeOrganizations(services, here: {for (final row in services?.joined ?? const <OrgRow>[]) row.id: _seenIn(row.id)}),
      orgNews: homeOrgNews(services, chosenOrg),
      onOrganization: services == null ? null : shell.openOrganization,
      // Edit on an organization's workspace, from the filters: its settings, opened from nowhere they go back to
      // (`openOrganizationSettings` with no `from`).
      onOrganizationSettings: services == null ? null : _openOrganizationSettings,
      onNewOrganization: signedIn ? () => _told(() => _newOrganization = true) : null,
      headerEdge: _headerEdge,
      dockHalo: _dockHalo,
      ghost: _homeGhost,
      onSaveSearch: _organize.saveSearch,
      // Today's events at the head of the page (docs/CALENDAR.md).
      // None while the Calendar plugin is off (lib/plugins/calendar): the service holds none then.
      events: calendar.events,
    );
  }

  /// The art in the seams the home page leaves for it. Each answers from what it is handed and nothing else, and is
  /// the same function every time the page is built: the page does no work for a seam that is the one it had.
  static Widget _headerEdge(BuildContext context, HomeEdge edge, Widget scroller) => WispEdge(under: edge.under, foot: true, child: scroller);

  static Widget _dockHalo(BuildContext context, HomeDock it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding, scale: it.scale);

  /// Every other page's halo: none while its dock has stepped aside for the keyboard.
  static Widget _pageDockHalo(BuildContext context, DockPlace it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding, shown: it.shown, scale: it.scale);

  /// The dock a page of notes carries, as the home page's (docs/DOCK.md): Claude, Search, a new note, Speak where the
  /// build records, and Settings at its foot.
  PageDockSeam _notesDock() => PageDockSeam(
        claude: _claudeForDock,
        talk: _claudeTalkForDock,
        halo: _pageDockHalo,
        actions: [
          DockAction(id: 'search', label: 'Search and commands', glyph: HomeGlyph.magnifier, motion: DockMotion.lean, onPressed: _search),
          DockAction(id: 'add', label: 'Write a note', glyph: HomeGlyph.plus, motion: DockMotion.turn, onPressed: _plus),
          if (_capture != null) DockAction(id: 'speak', label: 'Speak a voice note', glyph: HomeGlyph.mic, ink: true, onPressed: _speak),
        ],
        foot: DockAction(id: 'settings', label: 'Settings', icon: Lucide.settings, onPressed: _openSettings),
      );

  /// Claude and the halo, for a page whose dock's rings are its own: a note, an organization, Settings.
  PageDockSeam _pageDock() => PageDockSeam(claude: _claudeForDock, talk: _claudeTalkForDock, halo: _pageDockHalo);

  static Widget _homeGhost(BuildContext context, HomeGhost it) => Ghost(
        scene: switch (it.scene) {
          HomeGhostScene.noNotes => GhostScene.noNotes,
          HomeGhostScene.emptyWorkspace => GhostScene.emptyWorkspace,
          HomeGhostScene.searchNothing => GhostScene.searchNothing,
        },
        size: it.lead ? GhostSize.lead : GhostSize.small,
        heightShare: it.heightShare,
      );

  Widget _atWorkPart(BuildContext context) {
    final noteAi = _noteAi, id = _noteAiId;
    if (noteAi == null || id == null) return _nothing;
    final voice = _voice;
    return AtWork(
      noteId: id,
      opening: noteAi.reviewKey,
      heard: noteAi.handoff?.heard ?? '',
      body: _library.noteOf(id)?.body ?? '',
      hasJob: noteAi.handoff?.job != null,
      stage: noteAi.reviewStage.value,
      refining: voice?.recorder.refining?.refining,
      summaryDue: voice?.summaries?.pendingFor(id),
    );
  }

  Widget _settingsPart(BuildContext context) {
    final services = _services;
    final guide = _guide;
    return SettingsSheet(
      open: _settings,
      toPage: _settingsPage,
      onClose: _closeSettings,
      workspaces: _workspaces,
      notesInWorkspace: _notesIn,
      onTrashNotes: _trashNotes,
      // About's Updates rows, in a build that looks for any (lib/root/update_wiring.dart).
      // An iPhone has no update client: About says whose its updates are (iphone_wiring.dart).
      updates: widget.updates == null ? appStoreUpdates() : settingsUpdatesOf(widget.updates!),
      // A build with no service says so where a way in is pressed; one with an account takes it from the scope.
      features: _features(services),
      onOrganization: services == null ? null : _organizationSettings,
      onOpenLink: widget.openLink == null ? null : (url) => unawaited(widget.openLink!(url)),
      onAcademy: () {
        _closeSettings();
        _shell.currentState?.show(const Screen.academy());
      },
      onGuide: guide == null
          ? null
          : () {
              _closeSettings();
              guide.show(0);
            },
      onGuideBook: () => unawaited(_openGuideBook()),
      // Examples' four rows, which were drawn and could not be pressed: nothing had given them a press.
      // The sample note and the example canvas with their picture, where one can be kept.
      onSample: _openExample(() async => sampleNoteWith(await _samplePicture())),
      onBoard: _openExample(() => boardNoteBody),
      onCanvas: _openExample(() async => sampleCanvasBody(await _samplePicture())),
      onHowCanvas: _openExample(howCanvasBody),
      // Claude alone on Settings' dock (docs/DOCK.md).
      dock: _pageDock(),
    );
  }

  Widget _commandsPart(BuildContext context) {
    final guide = _guide;
    return CommandBar.over(
      key: _commands,
      // The open note's blanks for Fill, as its editor counted them (lib/editor/ai/blanks.dart `openNoteBlanks`).
      world: () => paletteWorldFor(
        shell: _shell.currentState!,
        workspaces: _workspaces.value,
        prefs: preferences.value,
        blanks: switch (openNoteBlanks.value) {
          final counted? when counted.noteId == _shell.currentState!.shown => counted.count,
          _ => 0,
        },
        smartNotebooks: [for (final each in _organize.smart.value) (id: each.id, name: each.name)],
      ),
      doing: () => paletteDoingFor(
        shell: _shell.currentState!,
        library: _library,
        workspaces: _workspaces,
        newNote: _new,
        newNotebook: () => _newBook(NewBookKind.notebook),
        newJournal: () => _newBook(NewBookKind.journal),
        newEntry: (id) => unawaited(_newEntry(id)),
        academy: () => _shell.currentState?.show(const Screen.academy()),
        guide: guide == null ? null : () => guide.show(0),
        speak: _capture == null ? null : _speak,
        speakInto: _capture == null ? null : (id) => unawaited(_speakInto(id)),
        openNoteWhereLeft: (id) {
          final note = _library.noteOf(id);
          final shell = _shell.currentState;
          if (note != null && shell != null) shell.openNote(whereLeft(note, _shown, shell.shown, on: _stored).id);
        },
        // App.tsx `archive: (id) => actions.archive(note, true)` and `pin: (id) => actions.pin(note)`: the note's
        // tab stays, and a pin gives the tick an archive gives.
        archive: (id) {
          final note = _library.noteOf(id);
          if (note != null) _actions.archive(note, archived: true);
        },
        pin: (id, _) {
          final note = _library.noteOf(id);
          if (note != null) _actions.pin(note);
        },
        removeNote: _delete,
        // Show it formatted, Show the marks: the preference every note's editor reads.
        setView: (view) => preferences.update((now) => now.copyWith(noteView: view)),
        // The note's runs from the palette go through its screen, as a spoken instruction does (`noteAi`).
        noteAi: (id, kind) {
          final shell = _shell.currentState;
          final now = shell?.screen;
          if (shell != null && now is ScreenNote && now.note.id == id) shell.show(now.asked(Keyed(SpokenAsk(kind: kind), DateTime.now().millisecondsSinceEpoch)));
        },
        settings: _openSettings,
        settingsPage: _openSettingsAt,
        // The links between notes (lib/links): the whole graph, the open note's own, and its links.
        graph: _showGraph,
        localGraph: (id) => _showGraph(focus: id, title: noteTitle(_library.noteOf(id)?.body ?? '')),
        noteLinks: _openNoteLinks,
        today: _organize.today,
        askClaude: _claudeOn ? () => _openAskClaude() : null,
        tags: _organize.showTags,
        openSmart: _organize.showSmart,
      ),
    );
  }

  Widget _noteMenuPart(BuildContext context) => NoteMenuHost(
        controller: _menu,
        notes: _shown,
        onOpen: (note) {
          final shell = _shell.currentState;
          if (shell != null) _openWhereLeft(shell, note.id);
        },
        // The note itself, with a comment started on its first line once its editor is there
        // (core/comments/ask.ts).
        onComment: (note) {
          commentAsks.ask(note.id);
          _shell.currentState?.openNote(note.id);
        },
        onPin: _actions.pin,
        onArchive: (note, archived) => _actions.archive(note, archived: archived),
        onDelete: (note) => _delete(note.id),
      );

  /// The sheet of the oldest share waiting: kept or not, the person goes back to the app they shared from, and the
  /// next share, if one came meanwhile, has its sheet.
  Widget _shareInPart(BuildContext context) {
    if (_sharing.isEmpty) return _nothing;
    final share = _sharing.first;
    return ShareInSheet(
      key: ValueKey('share-in:${share.id}'),
      share: share,
      keeper: _shareKeeper,
      notes: shareTargets(_library.value, trashed: _trash.isTrashed),
      onDone: (kept) {
        _told(() => _sharing.remove(share));
        unawaited(widget.shares?.done());
      },
    );
  }

  Widget _newSheetPart(BuildContext context) {
    final services = _services;
    final voice = _voice;
    final capture = _capture;
    final into = _newInto;
    return NewSheet(
      open: _newSheet,
      onClose: () => _told(() {
        _newSheet = false;
        _newInto = null;
      }),
      onNote: () => _new(into),
      onCanvas: () => _newCanvas(into),
      onBook: () => _newBook(NewBookKind.notebook, into),
      // Today's note (lib/notes/daily_notes.dart): the account's own, not offered from an organization's +.
      onToday: into != null ? null : () => _organize.today(),
      // A journal's entry is the account's own, and is not offered from an organization's +.
      entry: into != null || !_newSheet ? null : _entryRow(),
      // A shared link's copy is read from the account's service: not offered in a build with none.
      onFromLink: into != null || services?.shares == null ? null : _forkFromLink,
      // A meeting is the account's own too, and is offered only where one can be recorded.
      onMeeting: into == null && capture != null && (voice?.canMeet ?? false) ? () => unawaited(capture.meeting(false)) : null,
      sound: into == null && capture != null && (voice?.canMeet ?? false) && (voice?.sound?.supported ?? false)
          ? NewSheetSound(
              // The page's words for it on this platform (`meetingSoundWords`): other apps' sound on
              // Android, the computer's own on a Mac.
              label: voice?.recorder.systemSound?.meetingSoundWords().label ?? 'Include sound from other apps',
              hint: voice?.recorder.systemSound?.meetingSoundWords().hint ??
                  'Android lets Ghost.md hear media and games, never calls. It asks to share your screen each time; only the sound is kept.',
              on: preferences.value.meetingSound,
              onToggle: () => preferences.update((now) => now.copyWith(meetingSound: !now.meetingSound)),
            )
          : null,
    );
  }

  Widget _newBookPart(BuildContext context) => NewBookSheet(
        open: _bookSheet != null,
        kind: _bookSheet ?? NewBookKind.notebook,
        onClose: () => _told(() => _bookSheet = null),
        titles: _bookSheet == null ? const [] : _pageTitles(books: false),
        isCanvas: (title) => isCanvasBody(_reads.titled(title)?.body ?? ''),
        onCreate: (title, pages) => _showMade(bookNoteBody(title, pages), into: _bookInto),
        onCreateJournal: (title, template, place) => _showMade(journal.journalNoteBody(title, template, place)),
        // A journal's "With where you are": the prompt from the press that turned it on, and why it cannot.
        device: _places == null
            ? const EntryPlaceDevice()
            : EntryPlaceDevice(cannot: () => _places.locations.cannotLocate, refused: _places.autoTagRefusal, allowWhere: _places.allowLocationWhere(), ask: _places.askFromPress),
      );

  Widget _workspacePart(BuildContext context) {
    final sheet = _workspace;
    if (sheet == null) return _nothing;
    return WorkspaceManageSheet(
      store: _workspaces,
      editing: sheet.editing,
      onClose: () => _told(() => _workspace = null),
      onOrganization: _services == null ? null : _openOrganizationSettings,
      notesIn: _notesIn,
      onTrashNotes: _trashNotes,
    );
  }

  Widget _organizationSheetPart(AccountServices services) {
    final sheet = _organization;
    if (sheet == null || services.orgs == null) return _nothing;
    return OrganizationSheet(
      key: ValueKey('organization-sheet:${sheet.id}'),
      services: services,
      orgId: sheet.id,
      from: sheet.from,
      // `landOnMembers={orgSettings.from === 'settings'}`: from anywhere else, its list of sections.
      landOnMembers: sheet.from == OrganizationFrom.settings,
      seen: _seenIn(sheet.id),
      onClose: _closeOrganizationSettings,
      // Report a member or a note: an email, handed to the phone.
      onOpenLink: widget.openLink == null ? null : (url) => unawaited(widget.openLink!(url)),
      onNotes: () {
        _told(() => _organization = null);
        _workspaces.chooseWorkspace(orgWorkspaceId(sheet.id));
        _shell.currentState?.backToList();
      },
    );
  }

  Widget _newOrganizationPart(AccountServices services) => NewOrganizationSheet(
        services: services,
        open: _newOrganization,
        onClose: () => _told(() => _newOrganization = false),
        onMade: (id) {
          _told(() => _newOrganization = false);
          _shell.currentState?.openOrganization(id);
        },
      );

  Widget _guidePart(BuildContext context) {
    final guide = _guide;
    if (guide == null || !guide.open || (_gate?.open ?? false) || (_shell.currentState?.screen.isRecording ?? false)) return _nothing;
    return Guide(
      index: guide.page,
      tooSoon: guide.tooSoon,
      onIndex: guide.turn,
      recordsVoice: _capture != null,
      models: _modelsForGuide,
      onClose: () {
        guide.close();
        // The list underneath loaded while the guide was up; ask again now it shows.
        unawaited(_library.refresh().catchError((Object _) {}));
      },
      onAcademy: () {
        guide.close();
        _shell.currentState?.show(const Screen.academy());
      },
    );
  }

  Widget _launchPart(BuildContext context) {
    if (!_launching) return _nothing;
    return LaunchScreen(
      loading: _launchLoading,
      notes: _launchNotes,
      updates: launchUpdatesOf(widget.updates),
      sync: _launchSync,
      recording: _meetingRecording,
      onDone: () => _told(() => _launching = false),
    );
  }
  Widget _tree(AppShellState shell, {VoidCallback? onClose}) {
    return NoteTree(
      notes: shell.notes,
      activeId: shell.shown,
      workspaces: _workspaces,
      stored: _stored,
      onOpen: (id) {
        onClose?.call();
        _openWhereLeft(shell, id);
      },
      onNew: () {
        onClose?.call();
        _plus();
      },
      onClose: onClose,
      onCommands: _search,
      onBrowseFiles: _browseFiles,
      onGraph: () {
        onClose?.call();
        _showGraph();
      },
      notices: _sidebarNotices(),
      onSpeak: _capture == null
          ? null
          : () {
              onClose?.call();
              _speak();
            },
      onSettings: () {
        onClose?.call();
        _openSettings();
      },
      trashed: _trashed,
      onRestore: _actions.restore,
      onDestroy: _actions.destroy,
      onEmptyTrash: () => _actions.emptyTrash(_trashed),
      notesInWorkspace: _notesIn,
      onTrashNotes: _trashNotes,
      // An organization's workspace's "…" is the organization's settings.
      onOrganization: _services == null ? null : _openOrganizationSettings,
      // A mouse's right-click on a row: the note's menu, where the pointer is.
      onNoteMenu: _menu.open,
      emptyArt: const Ghost(scene: GhostScene.noNotes),
      smart: _organize.smart,
      onSmart: (id) {
        onClose?.call();
        _organize.showSmart(id);
      },
      onManageSmart: _organize.editSmart,
      onTags: () {
        onClose?.call();
        _organize.showTags();
      },
    );
  }

  /// A note's screen with its editor: one desk to an open note (lib/root/note_desk.dart). Built again when the
  /// screen is another (the note, what it was opened with), and when what it reads of the app is: the other notes
  /// (the titles that are taken, its place in its notebook, your templates; so a notebook thrown away takes its bar
  /// off the page being read at once, not when its Undo runs out), the trash, the workspaces, the preferences and
  /// the account. Not for a keystroke, the home page's news or a runner's turn; and **not for the note's own
  /// save**, of which the screen it is handed here shows nothing: it is built from the note as it was opened
  /// (`screen.note`, as the page's is), every other note's title, and its notebook's index, and what its editor
  /// holds, its saving and its pin are its own to follow (`_notesBut`).
  Widget _note(BuildContext context, AppShellState shell, ScreenNote screen) => Selected(
        listenable: _tick,
        name: 'note',
        select: () => (screen, _notesBut(screen.note.id), _trash.value, _made?.hidden, _workspaces.value, _prefsAt, _capture != null, _accountAt, _claudeOn),
        builder: (context, _) => _desked(context, shell, screen),
      );

  Widget _desked(BuildContext context, AppShellState shell, ScreenNote screen) => NoteDesk(
        key: ValueKey('desk:${screen.note.id}'),
        noteId: screen.note.id,
        title: noteTitle(screen.note.body),
        world: _desk,
        readOnly: _trash.isTrashed(screen.note.id),
        // What the recorder handed the note it opened (lib/root/capture_route.dart `finished`).
        landing: screen.landing,
        ask: screen.ask,
        review: screen.review,
        say: (message) => _say(context, message),
        builder: (context, editor, seams) => noteScreenBuilder(
          library: _library,
          workspaces: _workspaces,
          actions: () => _actions,
          versions: _versions,
          trash: _trash,
          device: _stored,
          untouched: _untouched,
          editor: editor,
          seams: seams,
          say: _say,
          bookOf: _reads.placeInBook,
          templates: () => _reads.ownTemplates,
          onTemplates: () => unawaited(_openTemplates()),
          // Taken back by the next journal's own: one screen is gone only after the next has come.
          onJournal: (writer) => _journalWriter = writer ?? _journalWriter,
          onSpeak: _capture == null ? null : (id) => unawaited(_speakInto(id)),
          // The bar's History button: the side panel at its History tab, where the window has one; else More's page.
          onHistory: _asideHistoryOf(context, shell) == null ? null : () => _openHistoryAside(shell),
          tags: _places,
          // Claude, about this note, at the head of its dock; the note's own rings under it (docs/DOCK.md).
          dock: _pageDock(),
        )(context, shell, screen),
      );
  /// An organization's dashboard or its log: built again with the notes, the account and its sync, who is in its
  /// notes, and the smoke's switch.
  Widget _organizationPage(BuildContext context, AppShellState shell, ScreenOrganization screen) => Selected(
        listenable: _tick,
        name: 'organization',
        select: () => (screen.orgId, screen.page, shell.notes, _workspaces.value, _accountAt, _syncAt, _presenceAt, preferences.value.wispEdge, _claudeOn, _canTalk),
        builder: (context, _) => _organizationPageOf(context, shell, screen),
      );

  Widget _organizationPageOf(BuildContext context, AppShellState shell, ScreenOrganization screen) {
    final id = screen.orgId;
    final wisp = preferences.value.wispEdge;
    if (screen.page == OrganizationPage.log) {
      return OrganizationLog(services: _services, orgId: id, notes: shell.notes, onBack: () => shell.openOrganization(id), onOpenNote: (note) => _openWhereLeft(shell, note), record: _versions, wisp: wisp);
    }
    return OrganizationScreen(
      services: _services,
      orgId: id,
      notes: shell.notes,
      onBack: shell.backToList,
      onOpenNote: (note) => _openWhereLeft(shell, note),
      onNew: () => _plus(orgWorkspaceId(id)),
      onAllNotes: () {
        _workspaces.chooseWorkspace(orgWorkspaceId(id));
        shell.backToList();
      },
      onSettings: () => _openOrganizationSettings(id, OrganizationFrom.dashboard),
      onOpenOrganization: shell.openOrganization,
      seen: _seenIn(id),
      onJumpTo: (noteId) => _jumpTo(shell, id, noteId),
      onFollow: _follow == null ? null : _followFrom,
      // An AI's Chat: the chat with Claude, opened for it (docs/CLAUDE_APP.md, "The chat").
      onChat: _claudeOn ? (ai) => _openAskClaude(agent: ai.name) : null,
      onLog: () => shell.openOrganizationLog(id),
      onAccount: _toAccount,
      wisp: wisp,
      // Claude, then the page's own New, Invite and cog (docs/DOCK.md).
      dock: _pageDock(),
    );
  }

  /// The voice model's fetch as its line says it.
  static notices.VoiceModel _voiceModelState(VoiceModel? model) => switch (model?.state) {
        VoiceModelStateDownloading(:final received, :final total) => notices.VoiceModelDownloading(received: received, total: total),
        VoiceModelStateFailed(:final message) => notices.VoiceModelFailed(message),
        _ => const notices.VoiceModelQuiet(),
      };

  /// Whether the voice model has a line above the notes, and which: nothing, its fetch, or why it failed. The
  /// fetch's progress is the line's own to follow.
  Object? get _voiceModelLine => switch (_voice?.recorder.voiceModel.state) {
        VoiceModelStateDownloading() => true,
        VoiceModelStateFailed(:final message) => message,
        _ => null,
      };

  /// What is waiting on the person, above the notes (notes/Notices.tsx), in the page's order: a new version of the
  /// app (lib/root/update_wiring.dart, from [GhostRoot.updates]), the simple-or-advanced question for an install
  /// from before there was one (GHST-103), an invitation to an organization where the build has an account, and
  /// the voice model while it is not ready.
  List<Widget> _notices() {
    final updates = widget.updates;
    final services = _services;
    final model = _voice?.recorder.voiceModel;
    return [
      if (updates != null && updates.apk is! ApkPhaseNone) notices.UpdateNotice(updates: updateCardOf(updates)),
      if (_asksExperience) notices.ExperienceCard(onPick: _pickExperience),
      // Simple mode's way into the Academy (GHST-103): for the first week, until a lesson is passed or the cross.
      if (_academyCardDue)
        notices.AcademyCard(
          onOpen: () => _shell.currentState?.show(const Screen.academy()),
          onHide: () => setState(dismissAcademyBanner),
        ),
      if (services != null) InviteWaiting(services: services, onOpen: (id) => _shell.currentState?.openOrganization(id)),
      if (model != null && _voiceModelLine != null)
        ListenableBuilder(listenable: model, builder: (context, _) => notices.VoiceModelStatus(state: _voiceModelState(model), onRetry: model.retry)),
    ];
  }

  /// Whether home asks simple or advanced (GHST-103): the walkthrough has been seen (so it did not ask, or was
  /// skipped before its page) and the choice was never made, here or on another device. Matt, 2026-10-18: new
  /// installs choose in the walkthrough, "existing users see it on the card one time".
  bool get _asksExperience => !preferences.value.experienceChosen && _guide?.open != true && _stored.flag(guideSeenKey, value: '1', unreadable: true).isMarked;

  /// Whether home offers the Academy's card (lib/academy/banner.dart): in simple mode, where the marks are hidden
  /// and the Academy is how they are learnt (Matt: "the academy page should show up on the home screen kinda like
  /// the update banner for new users"); advanced has the cheat sheet and the + list's More in reach already. On
  /// the root's clock, where a test sets one.
  bool get _academyCardDue =>
      preferences.value.simple && academyBannerDue(now: widget.clock == null ? null : DateTime.fromMillisecondsSinceEpoch(widget.clock!(), isUtc: true));

  /// The card's answer: the choice, made for every device, and the card goes with it.
  void _pickExperience(String mode) => preferences.update((now) => now.choosing(mode));

  /// An update waiting: the sidebar's to carry on a wide window, where there is no home list to show it (App.tsx
  /// `notices`, notes/NoteTree.tsx): docked, and floating where the window is in two panes. Nothing while there is
  /// nothing newer, and the tree gives it no room then.
  List<Widget> _sidebarNotices() {
    final updates = widget.updates;
    return [if (updates != null && updates.apk is! ApkPhaseNone) notices.UpdateNotice(updates: updateCardOf(updates))];
  }
}
