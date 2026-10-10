import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/rendering.dart' show RenderOffstage;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/back.dart';
import '../core/live_titles.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/tabs.dart';
import '../core/workspaces.dart';
import '../notes/note_tabs.dart';
import '../perf/frame_log.dart';
import 'app_tab_bar.dart';
import 'open_tabs.dart';
import 'placeholders.dart';
import 'root_stamps.dart';
import 'screen.dart';
import 'top_bar.dart';
import 'top_bar_tools.dart';
import 'trail.dart';
import 'visible_notes.dart';
import 'visited.dart';
import 'wide_screen.dart';

/// How the notes sidebar opens on a wide window (`SidebarStyle`, core/preferences.ts): a card over the note, which is
/// the default everywhere, or a column docked beside it.
enum SidebarStyle { popover, docked }

/// Builds one of the shell's screens. [shell] is the way to everything the screen may ask of it.
typedef ShellBuilder = Widget Function(BuildContext context, AppShellState shell);

/// Builds a note's screen for [screen], which carries the note and what it was opened with.
typedef ShellNoteBuilder = Widget Function(BuildContext context, AppShellState shell, ScreenNote screen);

/// Builds an organization's dashboard, or its log.
typedef ShellOrganizationBuilder = Widget Function(BuildContext context, AppShellState shell, ScreenOrganization screen);

/// Builds a screen that takes the whole window.
typedef ShellScreenBuilder<S extends Screen> = Widget Function(BuildContext context, AppShellState shell, S screen);

/// Builds something that is over the screen until [close] is called: the notifications, the notes' card.
typedef ShellOverlayBuilder = Widget Function(BuildContext context, AppShellState shell, VoidCallback close);

/// Builds the aside for the screen that is up, or answers null where there is nothing for it to hold - no book, no
/// run of chapters, no note's history - in which case there is no aside and no toggle for it.
typedef ShellAsideBuilder = Widget? Function(BuildContext context, AppShellState shell);

/// The same aside as a card at the right, hung from the bar's mirrored icon (aside/aside_panel.dart `AsideCard`);
/// `close` is the icon's own toggle. Only asked while [ShellAsideBuilder] answers something.
typedef ShellAsideCardBuilder = Widget Function(BuildContext context, AppShellState shell, VoidCallback close);

/// The whole app's frame: which screen is up, and everything drawn over it. Ports the frame of the web app's
/// App.tsx with app.css (`.app-tabBar`, `.app-split`, `.app-sidebar`, `.app-notePane`, `.app-aside`,
/// `.app-statusScrim`) and the stamps of shell/useRootStamp.ts.
///
/// There is no router. Ghost.md has seven screens (shell/screen.dart), and everything else is a sheet or a card over
/// whichever is up. The shell holds the screen, the open tabs and their groups (shell/open_tabs.dart) and the trail
/// the arrows walk (shell/trail.dart); it draws the tab bar on the places, quiet on a phone reading a note (the
/// people icon, the bell and the cog step out, the bar being the note's own tools'); and under the bar the screen,
/// alone or, on a window wide enough, in a pane beside the docked sidebar and the aside. The phone's back gesture is
/// the stack of core/back.dart: whatever is on top says what leaving it means.
///
/// The screens themselves are plugged in: a builder for the home page, a note, the All notes grid, an
/// organization's pages, the three that take the whole window, the notes' sidebar (as a card or docked), the aside
/// and the notifications; callbacks for what the shell only asks for (Settings, the organizations' list, a new
/// note, a note deleted or renamed from its tab). Wherever one is not given, a stand-in that says so is drawn
/// (shell/placeholders.dart), so the frame can be walked before the screens are ported.
///
/// What is the shell's and what is not, of App.tsx: the screen, the tabs, the trail, the bar's wiring, the split
/// and the overlays' open-or-shut are here. The library's own doings (making, filing, deleting and pinning notes,
/// titles and links, books, journals, tickets, queries, templates), captures and meetings, sync, the launch screen,
/// the guide, the account gate and the palette are their modules' to bring, through the builders and [AppShellState].
///
/// Differs from the web:
/// - The preferences are another module's: the bar's style, the sidebar's, the row of open notes and its groups, and
///   whether the docked sidebar and the aside show come in by the constructor, and each change goes out by a callback.
/// - The stamps are laid over the shell's own subtree (shell/root_stamps.dart), which needs the token [sheet].
/// - A window in two panes is asked of the window's size and of the device ([finePointer], [mobile]), not of media
///   queries; a mouse joined to a phone is not seen.
/// - `land` asks [AppShell.untouchedEntryOf] which journal an untouched entry is of, the records being the root's.
/// - The Mac's title bar (`data-titlebar`) is the tab bar's to wear: its top row keeps the window buttons' room and
///   says where they sit (notes/note_tabs.dart, shell/desktop/mac_lights.dart), and its empty ground is the drag
///   strip (`.app-dragBar`, shell/app_tab_bar.dart, shell/desktop/mac_drag_strip.dart).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.sheet,
    required this.notes,
    this.hidden = const {},
    this.trash = const {},
    this.drafts = const {},
    this.topBar = TopBarStyle.classic,
    this.sidebarStyle = SidebarStyle.popover,
    this.workspaces = const Workspaces(),
    this.organizations = const [],
    this.unread = false,
    this.openNotes = const [],
    this.tabGroups = TabGroups.none,
    this.onOpenNotesChanged,
    this.onTabGroupsChanged,
    this.sidebarShown,
    this.onSidebarShownChanged,
    this.asideShown = false,
    this.onAsideShownChanged,
    this.initialScreen = const Screen.list(),
    this.onScreenChanged,
    this.homeBuilder,
    this.noteBuilder,
    this.allNotesBuilder,
    this.organizationBuilder,
    this.captureBuilder,
    this.meetingBuilder,
    this.academyBuilder,
    this.sidebarBuilder,
    this.dockedSidebarBuilder,
    this.asideBuilder,
    this.asideCardBuilder,
    this.notificationsBuilder,
    this.onSettings,
    this.onOrganizations,
    this.onNew,
    this.onDeleteNote,
    this.onRenameNote,
    this.onRefresh,
    this.untouchedEntryOf,
    this.liveTitles,
    this.backStack,
    this.leavesAtRoot = false,
    this.mobile,
    this.finePointer,
  });

  /// The app's token sheet, the one its theme was made with: the shell stamps its layout over it.
  final TokenSheet sheet;

  /// The library as the store has it.
  final List<Note> notes;

  /// The ids a pending delete is holding back, and the trash, each id with when it was thrown away: neither is shown
  /// by any screen, drawn as a tab, or landed on by an arrow (shell/visible_notes.dart).
  final Set<String> hidden;
  final Map<String, int> trash;

  /// The ids of notes made here that have no words and no file yet (lib/core/core_library.dart `isDraft`). The
  /// page's list never holds one, so it is in no list, has no tab and is no place an arrow lands on until its first
  /// words are kept: only its own screen, which it is handed straight to, shows it. With no other tab open a new
  /// note's page therefore starts a row of tabs higher (seen beside the Tauri app, whose "Write something." stood
  /// 46px over the port's, which drew an "Untitled" tab for it).
  final Set<String> drafts;

  /// How the top bar is laid out (Settings › Appearance).
  final TopBarStyle topBar;
  final SidebarStyle sidebarStyle;

  /// The workspaces, for the pill a filed note's tab wears.
  final Workspaces workspaces;

  /// The organizations you belong to, for the people icon's picker.
  final List<OrgLike> organizations;

  /// Whether something unread and wanted has arrived: the bell's dot.
  final bool unread;

  /// The row of open notes and the groups over it, as they were kept, and where each change goes to be kept.
  final List<String> openNotes;
  final TabGroups tabGroups;
  final ValueChanged<List<String>>? onOpenNotesChanged;
  final ValueChanged<TabGroups>? onTabGroupsChanged;

  /// Whether the docked sidebar is showing, as kept to this device; null until it has ever been toggled, when it
  /// shows where there is a mouse and starts hidden under a finger.
  final bool? sidebarShown;
  final ValueChanged<bool>? onSidebarShownChanged;

  /// Whether the aside is showing, as kept to this device.
  final bool asideShown;
  final ValueChanged<bool>? onAsideShownChanged;

  /// The screen the app opens on: the home page, as it always has.
  final Screen initialScreen;
  final ValueChanged<Screen>? onScreenChanged;

  final ShellBuilder? homeBuilder;
  final ShellNoteBuilder? noteBuilder;
  final ShellScreenBuilder<ScreenNotes>? allNotesBuilder;
  final ShellOrganizationBuilder? organizationBuilder;
  final ShellScreenBuilder<ScreenCapture>? captureBuilder;
  final ShellScreenBuilder<ScreenMeeting>? meetingBuilder;
  final ShellBuilder? academyBuilder;

  /// The floating list of every note, over the screen (notes/NotesDrawer.tsx).
  final ShellOverlayBuilder? sidebarBuilder;

  /// The same list as a column beside the note (notes/NoteTree.tsx, docked).
  final ShellBuilder? dockedSidebarBuilder;
  final ShellAsideBuilder? asideBuilder;
  final ShellAsideCardBuilder? asideCardBuilder;

  /// The notifications, a card at the right under the bell (notes/NotificationsDrawer.tsx).
  final ShellOverlayBuilder? notificationsBuilder;

  /// Settings, from the cog. Absent, a stand-in card opens.
  final VoidCallback? onSettings;

  /// Settings › Account › Organizations, from the people icon when you belong to none, and from the picker's last
  /// row. Absent, the same stand-in opens.
  final VoidCallback? onOrganizations;

  /// A new note in a new tab, from the + at the end of the row. Absent, there is no +.
  final VoidCallback? onNew;

  /// A tab's note deleted from its menu; the shell has closed its tab and left it. Absent, the menu has no Delete.
  final ValueChanged<String>? onDeleteNote;

  /// A canvas or a book renamed from its tab. Absent, no tab offers it.
  final void Function(String id, String title)? onRenameNote;

  /// The notes read again, asked for on the way back to the home page.
  final VoidCallback? onRefresh;

  /// The journal the note [id] is an entry of while nobody has written in it (`untouchedRecord(id)?.journalId`), or
  /// null: an arrow from such an entry to its own journal gives the journal the entry's tab.
  final String? Function(String id)? untouchedEntryOf;

  final LiveTitles? liveTitles;

  /// The back stack; the app's own unless a test brings one.
  final BackStack? backStack;

  /// Whether a back gesture with nothing to close puts the app behind the home screen. The web app's never does.
  final bool leavesAtRoot;

  /// A phone or a tablet, whatever its window's width; the device's answer unless a test says.
  final bool? mobile;

  /// Whether the pointer is a mouse; the device's answer unless a test says.
  final bool? finePointer;

  /// The shell above [context], for a screen to ask things of.
  static AppShellState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ShellScope>();
    assert(scope != null, 'No AppShell above this widget.');
    return scope!.shell;
  }

  static AppShellState? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.shell;

  @override
  State<AppShell> createState() => AppShellState();
}

/// The shell as its screens see it: which screen is up, and the ways to change that.
class AppShellState extends State<AppShell> {
  late Screen _screen = widget.initialScreen;
  late final OpenTabsController _tabs =
      OpenTabsController(open: widget.openNotes, groups: widget.tabGroups, onOpenChanged: (open) => widget.onOpenNotesChanged?.call(open), onGroupsChanged: (groups) => widget.onTabGroupsChanged?.call(groups));
  final TrailController _walk = TrailController();
  final TopBarTools _barTools = TopBarTools();
  late VisibleNotes _seen = _see();

  /// The notes every screen is handed: none held back by a pending delete, none in the trash, and no draft.
  VisibleNotes _see() => visibleNotes(widget.notes, hidden: widget.drafts.isEmpty ? widget.hidden : {...widget.hidden, ...widget.drafts}, trash: widget.trash);

  bool _drawer = false;
  bool _notificationsOpen = false;

  /// The stand-in for Settings, open, and what it was opened at.
  String? _settings;
  late bool? _sidebarShown = widget.sidebarShown;
  late bool _asideShown = widget.asideShown;

  /// Which screen is up.
  Screen get screen => _screen;

  /// The notes every screen shows: none a pending delete is holding back, none in the trash.
  List<Note> get notes => _seen.visible;

  /// The notes in the trash, for its folder in the tree.
  List<Note> get trashed => _seen.trashed;

  /// The open tabs and their groups.
  OpenTabsController get tabs => _tabs;

  /// Where he has been.
  TrailController get trail => _walk;

  /// The id of the note on screen, or null.
  String? get shown => _screen.noteOnScreen;

  bool get drawerOpen => _drawer;
  bool get notificationsOpen => _notificationsOpen;

  LiveTitles get _live => widget.liveTitles ?? liveTitles;
  bool get _mouse => widget.finePointer ?? mousePointer;
  bool get _mobile => widget.mobile ?? mobileDevice;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.notes, widget.notes) || !identical(old.hidden, widget.hidden) || !identical(old.trash, widget.trash) || !setEquals(old.drafts, widget.drafts)) {
      _seen = _see();
    }
    // Another device's row, or its groups, read again from the preferences.
    if (!identical(old.tabGroups, widget.tabGroups)) _tabs.groupsFromElsewhere(widget.tabGroups);
    if (!identical(old.openNotes, widget.openNotes)) _tabs.openFromElsewhere(widget.openNotes);
    if (old.sidebarShown != widget.sidebarShown && widget.sidebarShown != null) _sidebarShown = widget.sidebarShown;
    if (old.asideShown != widget.asideShown) _asideShown = widget.asideShown;
    _sync();
  }

  @override
  void dispose() {
    // No shell, no stamps of its own on the root: once the tree has settled.
    Future<void>.microtask(() => shellStamps.value = const <String, String?>{});
    _tabs.dispose();
    _walk.dispose();
    _barTools.dispose();
    super.dispose();
  }

  /// What follows from the screen and the library: a note shown is a note open, and arriving somewhere is recorded.
  void _sync() {
    _tabs.update(shown: shown, notes: widget.notes, live: _seen.live);
    _walk.live = _seen.live;
    _walk.arrive(_screen.place);
  }

  void _change(VoidCallback change) {
    if (!mounted) return;
    final was = _screen;
    setState(() {
      change();
      _sync();
    });
    if (_screen != was) widget.onScreenChanged?.call(_screen);
  }

  Note? _noteOf(String id) {
    for (final note in widget.notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  // ---- the going (App.tsx) -----------------------------------------------------------------------------------------

  /// Puts [next] up, whatever it is: a capture begun, the Academy, a note opened at an item or to be written in.
  void show(Screen next) => _change(() => _screen = next);

  /// [id] in a tab of its own: a tab pressed, an arrow's step, a title tapped on the home page. With [caret], a note
  /// just made, opened to be written in (App.tsx `showMade`).
  void openNote(String id, {String? at, Caret? caret}) => _change(() {
        _tabs.replaceNext(null);
        final note = _noteOf(id);
        if (note != null) _screen = ScreenNote(note, at: at, caret: caret);
        _drawer = false;
      });

  /// [id] opened in the current note's tab: a page of the book being read, or one just made from its index.
  void openNoteWithin(String id, {Caret? caret}) => _change(() {
        final from = shown;
        _tabs.replaceNext(from != null && from != id ? from : null);
        final note = _noteOf(id);
        if (note != null) _screen = ScreenNote(note, caret: caret);
        _drawer = false;
      });

  /// The home page, with the notes read again.
  void backToList() {
    _change(() => _screen = const Screen.list());
    widget.onRefresh?.call();
  }

  /// Every note, from the home page's "All notes": a page of cards. With [tapes], only the notes with a recording.
  void showAllNotes({bool tapes = false}) => _change(() {
        _drawer = false;
        _screen = ScreenNotes(tapes: tapes);
      });

  /// An organization's dashboard, over nothing: Settings and the notes' card close first.
  void openOrganization(String orgId) => _change(() {
        _settings = null;
        _drawer = false;
        _screen = ScreenOrganization(orgId);
      });

  /// Its audit log, a page under the dashboard.
  void openOrganizationLog(String orgId) => _change(() {
        _settings = null;
        _drawer = false;
        _screen = ScreenOrganization(orgId, page: OrganizationPage.log);
      });

  /// Where one of the arrows said to go: the home page, the grid, or a note. From an entry nobody has written in to
  /// its own journal, the journal takes the entry's tab, as its bar's way back does: New entry gave the entry the
  /// journal's tab, and Back otherwise opened the journal in a second one and kept the entry open in its own, so it
  /// was never left and never taken back.
  void _land(Place? spot) {
    if (spot == null) {
      // Nowhere to go, though the trail may have moved over a place that is gone.
      if (mounted) setState(() {});
      return;
    }
    final id = noteIdOf(spot);
    if (spot == allNotesPlace) {
      show(const Screen.notes());
    } else if (id == null) {
      backToList();
    } else if (shown != null && widget.untouchedEntryOf?.call(shown!) == id) {
      openNoteWithin(id);
    } else {
      openNote(id);
    }
  }

  /// One step back through where he has been, and forward again.
  void goBack() => _land(_walk.back());
  void goOn() => _land(_walk.on());

  /// One tab closed, or a whole group's; the note being read among them hands over to the tab left beside it.
  void closeTabs(Iterable<String> ids) {
    _live.drop(ids);
    final landing = _tabs.close(ids);
    if (!landing.leaves) {
      if (mounted) setState(() {});
      return;
    }
    final to = landing.to;
    if (to != null) {
      openNote(to);
    } else {
      backToList();
    }
  }

  void closeTab(String id) => closeTabs([id]);

  /// Takes a note's tab out of the row and leaves the note, if it was the one being read: it is being deleted or
  /// archived.
  void dropTab(String id) {
    _tabs.drop(id);
    if (shown == id) {
      backToList();
    } else if (mounted) {
      setState(() {});
    }
  }

  /// The notifications drawer, over whatever screen is up, which stays where it was. The bell toggles it.
  void showNotifications() => _change(() {
        _drawer = false;
        _notificationsOpen = true;
      });

  void closeNotifications() => _change(() => _notificationsOpen = false);

  /// The notes' card, over the note being read.
  void closeSidebar() => _change(() => _drawer = false);

  void _toggleDock() {
    final next = !(_sidebarShown ?? sidebarShownByDefault(mouse: _mouse));
    _change(() => _sidebarShown = next);
    widget.onSidebarShownChanged?.call(next);
  }

  void _toggleAside() {
    final next = !_asideShown;
    _change(() => _asideShown = next);
    widget.onAsideShownChanged?.call(next);
  }

  /// Settings, from the cog; and Settings › Organizations, from the people icon.
  void openSettings() {
    final ask = widget.onSettings;
    if (ask != null) return ask();
    _change(() => _settings = 'Settings');
  }

  void openOrganizations() {
    final ask = widget.onOrganizations;
    if (ask != null) return ask();
    _change(() => _settings = 'Settings › Organizations');
  }

  void _delete(String id) {
    dropTab(id);
    widget.onDeleteNote?.call(id);
  }

  // ---- the frame -------------------------------------------------------------------------------------------------

  String _orgName(String id) {
    for (final org in widget.organizations) {
      if (org.id == id) return org.name;
    }
    return id;
  }

  /// The place that is up, with what leaving it means: a note, the grid and an organization's dashboard go home; an
  /// organization's log goes back to its dashboard; the home page is the root, and has nothing to leave.
  ///
  /// The home page stays where it is under the other three: built, laid out and not drawn, its animations stopped
  /// and nothing in it able to hold the keyboard, so coming back to it is showing it again and not building every
  /// card of it from nothing (measured on 354 notes: the one frame that came back to it was 500 to 1,700 ms). Whoever
  /// builds it is told by [screen] that it is covered, and is to do no work meanwhile. [aside] is how wide the column
  /// beside the place is, which only a note has: the home page under it is laid out without it.
  Widget _place(BuildContext context, {double aside = 0}) {
    final screen = _screen;
    final Widget? over;
    switch (screen) {
      case ScreenNote():
        over = OnBack(
          key: const ValueKey('back:note'),
          onBack: backToList,
          // A note's screen is made anew for each note.
          child: KeyedSubtree(key: ValueKey('note:${screen.note.id}'), child: widget.noteBuilder?.call(context, this, screen) ?? NotePlaceholder(note: screen.note)),
        );
      case ScreenNotes():
        over = OnBack(
          key: const ValueKey('back:notes'),
          onBack: backToList,
          child: widget.allNotesBuilder?.call(context, this, screen) ?? AllNotesPlaceholder(notes: notes, tapes: screen.tapes, onOpen: openNote),
        );
      case ScreenOrganization():
        final log = screen.page == OrganizationPage.log;
        over = OnBack(
          key: const ValueKey('back:organization'),
          onBack: log ? () => openOrganization(screen.orgId) : backToList,
          child: KeyedSubtree(
            key: ValueKey('organization:${screen.orgId}/${screen.page?.name ?? ''}'),
            child: widget.organizationBuilder?.call(context, this, screen) ??
                OrganizationPlaceholder(name: _orgName(screen.orgId), log: log, onLog: () => openOrganizationLog(screen.orgId)),
          ),
        );
      default:
        over = null;
    }
    final covered = over != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Kept(
          key: const ValueKey('place:home'),
          covered: covered,
          wider: aside,
          child: TickerMode(
            enabled: !covered,
            child: ExcludeFocus(
              excluding: covered,
              child: widget.homeBuilder?.call(context, this) ?? HomePlaceholder(notes: notes, onOpen: openNote, onAllNotes: showAllNotes),
            ),
          ),
        ),
        ?over,
      ],
    );
  }

  /// A screen that takes the whole window, and its own way out.
  Widget _whole(BuildContext context) {
    final screen = _screen;
    void home() => show(const Screen.list());
    return switch (screen) {
      ScreenCapture() => OnBack(
          key: ValueKey('capture:${screen.key}'),
          onBack: home,
          child: widget.captureBuilder?.call(context, this, screen) ?? WholeScreenPlaceholder(what: screen.meeting ? 'a meeting being recorded' : 'a capture', onDone: home),
        ),
      ScreenMeeting() => OnBack(
          key: ValueKey('meeting:${screen.key}'),
          onBack: home,
          child: widget.meetingBuilder?.call(context, this, screen) ?? WholeScreenPlaceholder(what: 'a meeting being recorded', onDone: home),
        ),
      _ => OnBack(
          key: const ValueKey('back:academy'),
          onBack: home,
          child: widget.academyBuilder?.call(context, this) ?? WholeScreenPlaceholder(what: 'the Academy', onDone: home),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('shell.build');
    final window = MediaQuery.sizeOf(context);
    final screen = _screen;
    final topBar = widget.topBar;
    // A window wide enough keeps the notes in a pane beside the open note; a capture and the Academy still take the
    // whole window.
    final sidebar = splitFits(window, mouse: _mouse);
    final split = sidebar && screen.isPlace;
    // A phone reading a note: the bar holds the note's own tools, so the people icon, the bell and the cog step out.
    final quietBar = _mobile && screen is ScreenNote;
    // The sidebar docked beside the note, rather than a card over it: a window wide enough, and Docked chosen.
    final docked = split && widget.sidebarStyle == SidebarStyle.docked;
    final sidebarShown = _sidebarShown ?? sidebarShownByDefault(mouse: _mouse);
    final dockShown = docked && sidebarShown;
    // Docking takes over from a card left open, so the notes are never drawn twice.
    if (docked) _drawer = false;
    final tabBar = screen.isPlace;
    final stamps = <String, String?>{
      // How tall the bar is: one line of controls, or that line with the open notes under it.
      'tabs': tabBar ? barRows(topBar, _tabs.tabs.length).stamp : null,
      // Whether the window is in two panes, said on the root so nothing else holds a copy of the threshold.
      'split': sidebar ? 'on' : null,
      // The bar's style, for its heights and grounds; Classic stamps nothing.
      'topbar': topBar == TopBarStyle.classic ? null : topBar.id,
    };

    // The page's root is told too: what is drawn outside the shell reads the same attributes (root_stamps.dart).
    publishShellStamps(stamps);

    return BackScope(
      stack: widget.backStack,
      leavesAtRoot: widget.leavesAtRoot,
      child: RootStamps(
        sheet: widget.sheet,
        stamps: stamps,
        child: _ShellScope(
          shell: this,
          // Rebuilt with every change of the shell's, so whatever asked for the shell is built again.
          stamp: Object(),
          child: TopBarToolsScope(
            notifier: _barTools,
            child: Builder(
              builder: (context) {
                // The aside follows the sidebar's shell: a column beside a docked sidebar, else a card.
                final aside = tabBar ? widget.asideBuilder?.call(context, this) : null;
                final asideHolds = aside != null;
                final asideDocked = docked && _asideShown && asideHolds;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!tabBar)
                      _whole(context)
                    else
                      // One window or two panes, the place is the same child of the same row: a phone folded open or
                      // shut keeps the screen it had - its scroll, its caret, what was typed - where the page made
                      // the note again in another part of the tree.
                      _panes(context, split: split, dockShown: split && dockShown, aside: split && asideDocked ? aside : null),
                    if (tabBar) _bar(context, docked: docked, sidebarShown: sidebarShown, quietBar: quietBar, asideHolds: asideHolds),
                    // The notifications, a card at the right under the bell.
                    if (_notificationsOpen)
                      OnBack(
                        key: const ValueKey('back:notifications'),
                        onBack: closeNotifications,
                        child: widget.notificationsBuilder?.call(context, this, closeNotifications) ??
                            CardPlaceholder(what: 'notifications', atEnd: true, wide: true, onClose: closeNotifications),
                      ),
                    // With the sidebar a floating card, the aside is the same card at the right.
                    if (_asideShown && !asideDocked && asideHolds)
                      OnBack(
                        key: const ValueKey('back:aside'),
                        onBack: _toggleAside,
                        child: widget.asideCardBuilder?.call(context, this, _toggleAside) ?? _AsideCard(onClose: _toggleAside, child: aside),
                      ),
                    // Every note, in a card over the one being read; the tab row's icon opens it.
                    if (_drawer)
                      OnBack(
                        key: const ValueKey('back:drawer'),
                        onBack: closeSidebar,
                        child: widget.sidebarBuilder?.call(context, this, closeSidebar) ??
                            CardPlaceholder(
                              what: 'all your notes',
                              onClose: closeSidebar,
                              children: [for (final note in notes.take(8)) PlaceholderRow(label: _tabTitle(note), onPressed: () => openNote(note.id))],
                            ),
                      ),
                    if (_settings != null)
                      OnBack(
                        key: const ValueKey('back:settings'),
                        onBack: () => _change(() => _settings = null),
                        child: CardPlaceholder(what: _settings!, atEnd: true, onClose: () => _change(() => _settings = null)),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _tabTitle(Note note) {
    final title = _live.titleNow(note.id, note.updatedAt, noteTitle(note.body));
    return title.isEmpty ? 'Untitled' : title;
  }

  /// `.app-split`: the notes in a phone-width column on the left, the open note in the rest, the aside in a third
  /// column. Each pane is its screen as it is on a phone, sized to its column. With neither column it is the place alone,
  /// the whole window, as a phone has it.
  ///
  /// The panes wear the page's class while the window is split, for the rules that ask for it: an editor's room
  /// under its last line is `.app-split`'s (editor/looks/look.dart `LookEnv.splitRoom`).
  Widget _panes(BuildContext context, {required bool split, required bool dockShown, required Widget? aside}) {
    final t = context.tokens;
    final window = MediaQuery.sizeOf(context).width;
    final rule = BorderSide(color: t.color('glacier-border-subtle'));
    return GlacierScope(
      classes: split ? const {'app-split'} : const {},
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dockShown)
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'All notes',
              child: Container(
                width: sidebarColumn(window),
                decoration: BoxDecoration(border: Border(right: rule)),
                child: ClipRect(child: widget.dockedSidebarBuilder?.call(context, this) ?? PanePlaceholder(what: 'the notes, docked', notes: notes, onOpen: openNote)),
              ),
            ),
          Expanded(key: const ValueKey('pane:place'), child: ClipRect(child: _place(context, aside: aside == null ? 0 : asideColumn(window)))),
          if (aside != null)
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Side panel',
              child: Container(width: asideColumn(window), decoration: BoxDecoration(border: Border(left: rule)), child: ClipRect(child: aside)),
            ),
        ],
      ),
    );
  }

  /// The app's own tab row, one bar of one height on every screen that has it.
  Widget _bar(BuildContext context, {required bool docked, required bool sidebarShown, required bool quietBar, required bool asideHolds}) {
    return ListenableBuilder(
      listenable: _barTools,
      builder: (context, _) => AppTabBar(
        style: widget.topBar,
        child: NoteTabs(
          style: widget.topBar,
          tabs: _tabs.tabs,
          activeId: shown ?? '',
          workspaces: widget.workspaces,
          liveTitles: widget.liveTitles,
          finePointer: widget.finePointer,
          tools: _barTools.tools,
          tail: _barTools.tail,
          onOpen: openNote,
          onClose: closeTab,
          onNew: widget.onNew,
          onSidebar: docked ? _toggleDock : () => _change(() => _drawer = !_drawer),
          onHome: backToList,
          atHome: _screen is ScreenList,
          sidebarOpen: docked ? sidebarShown : _drawer,
          onAside: asideHolds ? _toggleAside : null,
          asideOpen: _asideShown,
          onMove: (id, to, {grouped = false}) {
            _tabs.move(id, to, grouped: grouped);
            setState(() {});
          },
          groups: _tabs.groups,
          onGroups: (next) {
            _tabs.setGroups(next);
            setState(() {});
          },
          onCloseTabs: closeTabs,
          onGoBack: goBack,
          onGoOn: goOn,
          canGoBack: _walk.canBack,
          canGoOn: _walk.canOn,
          onNotifications: quietBar
              ? null
              : () => _change(() {
                    _drawer = false;
                    _notificationsOpen = !_notificationsOpen;
                  }),
          onSettings: quietBar ? null : openSettings,
          onOrganizations: quietBar ? null : openOrganizations,
          // The people icon's picker: the ones you belong to, a pick straight to its dashboard.
          organizations: widget.organizations,
          onOrganization: openOrganization,
          unread: widget.unread,
          atNotifications: _notificationsOpen,
          onRename: widget.onRenameNote,
          onDelete: widget.onDeleteNote == null ? null : _delete,
        ),
      ),
    );
  }
}

/// A place kept under another: built and laid out, and neither drawn nor pressed, as [Offstage] keeps its child.
/// What differs is the room it is laid out in. A note with its aside docked beside it stands in a narrower pane
/// than the home page ever does, and the page laid out in that (a row of an organization's card eleven pixels too
/// wide for it) is a layout nobody will see and an error in a debug build; so while it is covered it is laid out
/// [wider] by the column it does not share, which is the room it has when it is come back to.
class _Kept extends Offstage {
  const _Kept({super.key, required bool covered, this.wider = 0, super.child}) : super(offstage: covered);

  final double wider;

  @override
  RenderOffstage createRenderObject(BuildContext context) => _RenderKept(offstage: offstage, wider: wider);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderKept renderObject) {
    super.updateRenderObject(context, renderObject);
    renderObject.wider = wider;
  }
}

class _RenderKept extends RenderOffstage {
  _RenderKept({required super.offstage, required double wider}) : _wider = wider;

  double _wider;
  set wider(double value) {
    if (value == _wider) return;
    _wider = value;
    if (offstage) markNeedsLayout();
  }

  @override
  void performLayout() {
    if (!offstage || _wider == 0 || !constraints.hasBoundedWidth) return super.performLayout();
    child?.layout(BoxConstraints(minWidth: constraints.minWidth + _wider, maxWidth: constraints.maxWidth + _wider, minHeight: constraints.minHeight, maxHeight: constraints.maxHeight));
  }

  /// What is not drawn is nowhere. Asked where something in it is, a covered place answers with no place at all,
  /// so whatever finds a thing by where it stands in the window does not find one under the note: the walk that
  /// measures the app looks for a word or a label through every element there is (lib/shell/phone_tour.dart), and
  /// with the home page kept it pressed the page's own "Home" under the note in place of the bar's.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (offstage) return transform.setZero();
    super.applyPaintTransform(child, transform);
  }
}

/// The aside as a card at the right, over the screen and under the bar: where the web draws `AsideCard`
/// (aside/Aside.tsx), which is the notes' floating card on the other side.
class _AsideCard extends StatelessWidget {
  const _AsideCard({required this.onClose, required this.child});
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => CardPlaceholder(what: 'the side panel', atEnd: true, onClose: onClose, children: [child]);
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({required this.shell, required this.stamp, required super.child});
  final AppShellState shell;
  final Object stamp;

  @override
  bool updateShouldNotify(_ShellScope old) => !identical(old.stamp, stamp);
}
