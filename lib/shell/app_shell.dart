import 'package:flutter/foundation.dart' show setEquals;
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
import '../share/app_links.dart' show MarketPlace;
import '../simple/simple_pane.dart';
import 'app_tab_bar.dart';
import 'header_toolbar.dart';
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

/// How the side panel (the aside) opens on a wide window (`SidebarStyle`, core/preferences.ts): a card over the note,
/// which is the default everywhere, or a column docked beside it.
///
/// It chose the notes' sidebar's shell too until 2026-10-24, when the sidebar on a wide window became simple mode's
/// list, a column whichever is chosen (Matt: "make the sidebar on advanced mode the same as simple but just hide it by
/// default"; [AppShellState._panes]). The card of the tree is a narrow window's now, where it always was.
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

/// Something the bar draws that hears for itself what it shows ([AppShell.barChip]): built again when [changes]
/// says so, and drawn only while [build] answers a widget.
typedef ShellBarChip = ({Listenable changes, Widget? Function(BuildContext context) build});

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
    this.headerToolbar,
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
    this.collectionBuilder,
    this.marketBuilder,
    this.captureBuilder,
    this.meetingBuilder,
    this.academyBuilder,
    this.sidebarBuilder,
    this.dockedSidebarBuilder,
    this.asideBuilder,
    this.asideCardBuilder,
    this.notificationsBuilder,
    this.emptyPaneBuilder,
    this.onSettings,
    this.onOrganizations,
    this.onNew,
    this.onSearch,
    this.onDeleteNote,
    this.onRenameNote,
    this.onRefresh,
    this.untouchedEntryOf,
    this.liveTitles,
    this.barChip,
    this.banner,
    this.backStack,
    this.leavesAtRoot = false,
    this.simple = false,
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

  /// Which of the header toolbar's five versions draws the bar's line of controls (lib/shell/header_toolbar.dart).
  /// Null is this device's own choice, Settings › Developer › Header toolbar, heard as it changes; a test names one.
  final HeaderToolbarVersion? headerToolbar;
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

  /// Whether the sidebar beside the note is showing, as kept to this device; null until it has ever been toggled,
  /// when it is hidden (shell/wide_screen.dart `sidebarShownAtFirst`).
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

  /// The Tags page, a tag's notes and a smart notebook's (shell/screen.dart [ScreenCollection]).
  final ShellScreenBuilder<ScreenCollection>? collectionBuilder;

  /// The Market: plugins, themes and fonts (lib/market/market_screen.dart, shell/screen.dart [ScreenMarket]).
  final ShellScreenBuilder<ScreenMarket>? marketBuilder;
  final ShellOrganizationBuilder? organizationBuilder;
  final ShellScreenBuilder<ScreenCapture>? captureBuilder;
  final ShellScreenBuilder<ScreenMeeting>? meetingBuilder;
  final ShellBuilder? academyBuilder;

  /// The floating list of every note, over the screen (notes/NotesDrawer.tsx): a narrow window's sidebar.
  final ShellOverlayBuilder? sidebarBuilder;

  /// Advanced mode's sidebar on a wide window, a column beside the note: simple mode's list since 2026-10-24
  /// (lib/simple/simple_home.dart, `underBar`), where it was the tree (notes/NoteTree.tsx, docked).
  final ShellBuilder? dockedSidebarBuilder;
  final ShellAsideBuilder? asideBuilder;
  final ShellAsideCardBuilder? asideCardBuilder;

  /// The notifications, a card at the right under the bell (notes/NotificationsDrawer.tsx).
  final ShellOverlayBuilder? notificationsBuilder;

  /// Simple mode's right pane while no note is open on a wide window (GHST-105, [_plain]): the ghost and "Pick a
  /// note, or make one." Absent, the same words without the ghost.
  final ShellBuilder? emptyPaneBuilder;

  /// Settings, from the cog. Absent, a stand-in card opens.
  final VoidCallback? onSettings;

  /// Settings › Account › Organizations, from the people icon when you belong to none, and from the picker's last
  /// row. Absent, the same stand-in opens.
  final VoidCallback? onOrganizations;

  /// A new note in a new tab, from the + at the end of the row. Absent, there is no +.
  final VoidCallback? onNew;

  /// The command palette (lib/commands/command_bar.dart), for the header toolbar's versions that offer it in the
  /// bar. Absent, they offer it nowhere, and the Command centre's pill opens its own menu.
  final VoidCallback? onSearch;

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

  /// The Claude chip in the bar, before the people icon, while an AI is online (lib/shell/ai_chip.dart).
  final ShellBarChip? barChip;

  /// A slim bar under the top bar, over the screen: Follow's "Following Claude · Stop" (lib/shell/ai_chip.dart
  /// `FollowBar`), which draws nothing while nobody is followed.
  final Widget? banner;

  /// The back stack; the app's own unless a test brings one.
  final BackStack? backStack;

  /// Whether a back gesture with nothing to close puts the app behind the home screen. The web app's never does.
  final bool leavesAtRoot;

  /// Simple mode (GHST-103; Matt, 2026-10-17: "simple mode has a much more approachable UI with fancy features
  /// hidden behind more"; then GHST-105, 2026-10-18: "it still is a bit complex with the tabs and such"). The
  /// places are drawn plain ([_plain]): no control row and no tab row, no drawer, no docked sidebar, no aside, and
  /// no row of open notes kept beyond the one on screen. A wide window is the list beside the note instead. The
  /// bar's own simple trim (no people icon, bell, Forward or groups) stays in [_bar] for whoever draws it with
  /// `simple` and the bar both, which nothing does now. The root reads the preference and says.
  final bool simple;

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
  VisibleNotes _see() => visibleNotes(_library, hidden: widget.drafts.isEmpty ? widget.hidden : {...widget.hidden, ...widget.drafts}, trash: widget.trash);

  /// The library as the store has it now: the shell's own, or a newer one it was handed between two builds
  /// ([takeNotes]).
  List<Note> get _library => _taken ?? widget.notes;
  List<Note>? _taken;

  /// The library as the store has it now, taken without a build: for a change the shell draws nothing of. An open
  /// note saved changes none of what the shell draws (its tab says the title its editor has, lib/core/live_titles.dart;
  /// the page's own list is not read again for an editor's save at all), and building the bar, the panes and the
  /// aside again for each save was a frame's work every time the typing paused. What the shell is asked afterwards
  /// (the notes its screens list, a note opened by its id, the tabs at its next build) answers from these.
  void takeNotes(List<Note> notes) {
    if (identical(notes, _library)) return;
    _taken = notes;
    _seen = _see();
    _tabs.update(shown: shown, notes: notes, live: _seen.live);
    _walk.live = _seen.live;
  }

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
    // The bar's version decides its height too (`data-header`), so the whole shell hears a change of it.
    headerToolbarChoice.addListener(_versionChanged);
  }

  void _versionChanged() {
    if (mounted && widget.headerToolbar == null) setState(() {});
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    // A library handed over by a build is the newest there is: what was taken between builds gives way to it.
    if (!identical(old.notes, widget.notes)) _taken = null;
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
    headerToolbarChoice.removeListener(_versionChanged);
    _tabs.dispose();
    _walk.dispose();
    _barTools.dispose();
    super.dispose();
  }

  /// What follows from the screen and the library: a note shown is a note open, and arriving somewhere is recorded.
  /// In simple mode the row is the note on screen and nothing else (GHST-105): a note left on the way home is a tab
  /// closed, and a row kept from advanced is cut to the note showing.
  void _sync() {
    _tabs.update(shown: shown, notes: _library, live: _seen.live);
    if (widget.simple) _tabs.trimTo(shown);
    _walk.live = _seen.live;
    _walk.arrive(_screen.place);
  }

  /// Whether simple mode draws the home page as a column beside the note (GHST-105, [_plain]): simple, on a window
  /// wide enough for two panes. The root asks, to build the page for its column and the note without its Back.
  bool listPane(BuildContext context) => widget.simple && splitFits(MediaQuery.sizeOf(context), mouse: _mouse);

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
    for (final note in _library) {
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
        // Simple mode opens every note in the one tab there is (GHST-105): the note shown gives its place to the
        // next, so the row never grows, and the preferences are written once for the open rather than once to add
        // and once to trim.
        final from = shown;
        _tabs.replaceNext(widget.simple && from != null && from != id ? from : null);
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

  /// The Tags page, a tag's notes or a smart notebook's, from the sidebar, the palette or a tag in a note: the notes'
  /// card closes first.
  void showCollection(CollectionKind kind, {String key = '', bool fromTags = false}) => _change(() {
        _drawer = false;
        _screen = ScreenCollection(kind, key: key, fromTags: fromTags);
      });

  /// The Market, from the sidebar, the palette or Settings' row, at [plugin]'s page when one is named, or where a
  /// `ghostmd://market` [link] lands: the notes' card closes first, as for the Tags page.
  void showMarket({String? plugin, MarketPlace? link}) => _change(() {
        _drawer = false;
        _screen = ScreenMarket(plugin: plugin, link: link);
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
    final next = !(_sidebarShown ?? sidebarShownAtFirst);
    _change(() => _sidebarShown = next);
    widget.onSidebarShownChanged?.call(next);
  }

  void _toggleAside() {
    final next = !_asideShown;
    _change(() => _asideShown = next);
    widget.onAsideShownChanged?.call(next);
  }

  /// The aside opened, and kept so (`setAsideShown(true); writeAsideShown(true)`): the bar's History button, which
  /// turns it to its History tab first (aside/aside.dart `showAsideTab`).
  void showAside() {
    if (!_asideShown) _change(() => _asideShown = true);
    widget.onAsideShownChanged?.call(true);
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
  /// The home page is taken down under the other three and made anew on the way back, as the page's is (App.tsx
  /// `noteScreen ?? (… ?? home)`: a `<HomeScreen>` unmounted and mounted again). So it comes back as the page's does:
  /// at its top, its search empty and its filter on All (both are that component's own state), and its cards and
  /// rows arriving again, each after the one before. Kept alive under a note it came back where it had been
  /// scrolled to, with the search it had and nothing arriving, which the page never does; and an entrance is its
  /// card's own first frames, so a page kept and only shown again cannot play one.
  Widget _place(BuildContext context) {
    final screen = _screen;
    switch (screen) {
      case ScreenNote():
        return OnBack(
          key: const ValueKey('back:note'),
          onBack: backToList,
          // A note's screen is made anew for each note.
          child: KeyedSubtree(key: ValueKey('note:${screen.note.id}'), child: widget.noteBuilder?.call(context, this, screen) ?? NotePlaceholder(note: screen.note)),
        );
      case ScreenNotes():
        return OnBack(
          key: const ValueKey('back:notes'),
          onBack: backToList,
          child: widget.allNotesBuilder?.call(context, this, screen) ?? AllNotesPlaceholder(notes: notes, tapes: screen.tapes, onOpen: openNote),
        );
      case ScreenCollection():
        return OnBack(
          key: const ValueKey('back:collection'),
          // A tag's notes opened from the Tags page go back there; anything else goes home.
          onBack: screen.kind == CollectionKind.tag && screen.fromTags ? () => showCollection(CollectionKind.tags) : backToList,
          child: KeyedSubtree(
            key: ValueKey('collection:${screen.kind.name}/${screen.key}'),
            child: widget.collectionBuilder?.call(context, this, screen) ?? WholeScreenPlaceholder(what: 'a page of notes', onDone: backToList),
          ),
        );
      case ScreenMarket():
        return OnBack(
          key: const ValueKey('back:market'),
          onBack: backToList,
          // Made anew for each plugin it is opened at, and each link, so a link lands on that plugin's page.
          child: KeyedSubtree(
            key: ValueKey('market:${screen.plugin ?? ''}:${screen.link ?? ''}'),
            child: widget.marketBuilder?.call(context, this, screen) ?? WholeScreenPlaceholder(what: 'the Market', onDone: backToList),
          ),
        );
      case ScreenOrganization():
        final log = screen.page == OrganizationPage.log;
        return OnBack(
          key: const ValueKey('back:organization'),
          onBack: log ? () => openOrganization(screen.orgId) : backToList,
          child: KeyedSubtree(
            key: ValueKey('organization:${screen.orgId}/${screen.page?.name ?? ''}'),
            child: widget.organizationBuilder?.call(context, this, screen) ??
                OrganizationPlaceholder(name: _orgName(screen.orgId), log: log, onLog: () => openOrganizationLog(screen.orgId)),
          ),
        );
      default:
        return widget.homeBuilder?.call(context, this) ?? HomePlaceholder(notes: notes, onOpen: openNote, onAllNotes: showAllNotes);
    }
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
    // Simple mode's places are drawn plain (GHST-105): no bar over them, no sidebar beside them, no aside.
    final plain = widget.simple && screen.isPlace;
    // The sidebar beside the note, rather than a card over it: any window wide enough, whichever style is chosen
    // (Matt, 2026-10-24: "make the sidebar on advanced mode the same as simple but just hide it by default"). The
    // style is the aside's alone now ([_frame]); a narrow window keeps the card.
    final docked = split && !plain;
    final sidebarShown = _sidebarShown ?? sidebarShownAtFirst;
    final dockShown = docked && sidebarShown;
    // Docking takes over from a card left open, so the notes are never drawn twice; and plain has no card at all.
    if (docked || plain) _drawer = false;
    final tabBar = screen.isPlace && !plain;
    final stamps = <String, String?>{
      // How tall the bar is: one line of controls, or that line with the open notes under it; nothing where there
      // is no bar, so `--app-safe-top` is the notch alone.
      'tabs': tabBar ? barRows(topBar, _tabs.tabs.length).stamp : null,
      // Whether the window is in two panes, said on the root so nothing else holds a copy of the threshold.
      'split': sidebar ? 'on' : null,
      // The bar's style, for its heights and grounds; Classic stamps nothing.
      'topbar': topBar == TopBarStyle.classic ? null : topBar.id,
      // Grouped command is a size larger, the bar with it (app.css `[data-header='large']`; Matt, 2026-10-28: "make the
      // elements a size larger"); only where there is a bar for it to draw.
      'header': tabBar && (widget.headerToolbar ?? headerToolbarVersion) == HeaderToolbarVersion.groupedCommand ? 'large' : null,
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
          // The bar's slot for a screen's own tools is offered only where there is a bar: without it a note draws
          // its tools in a header of its own (lib/note/note_screen.dart `inBar`), which is what simple mode's plain
          // places want.
          child: plain
              ? Builder(builder: (context) => _frame(context, tabBar: tabBar, plain: true, split: split, sidebar: sidebar, docked: docked, dockShown: dockShown, sidebarShown: sidebarShown, quietBar: quietBar))
              : TopBarToolsScope(
                  notifier: _barTools,
                  child: Builder(builder: (context) => _frame(context, tabBar: tabBar, plain: false, split: split, sidebar: sidebar, docked: docked, dockShown: dockShown, sidebarShown: sidebarShown, quietBar: quietBar)),
                ),
        ),
      ),
    );
  }

  /// The screen and everything over it, for one build. [plain] is simple mode's frame (GHST-105): the place, or
  /// the list beside the place on a wide window ([sidebar]), with no bar and nothing of the bar's; the banner then
  /// sits under the notch.
  Widget _frame(
    BuildContext context, {
    required bool tabBar,
    required bool plain,
    required bool split,
    required bool sidebar,
    required bool docked,
    required bool dockShown,
    required bool sidebarShown,
    required bool quietBar,
  }) {
    // The aside is a column with Docked chosen, else a card: the style it shared with the sidebar until the sidebar
    // became a column on every wide window (2026-10-24), and kept for the aside so nobody's side panel moved. Simple
    // mode has none: the note's screen keeps its history and links in More.
    final aside = tabBar && !widget.simple ? widget.asideBuilder?.call(context, this) : null;
    final asideHolds = aside != null;
    final asideDocked = docked && widget.sidebarStyle == SidebarStyle.docked && _asideShown && asideHolds;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (plain)
          _plain(context, split: sidebar)
        else if (!tabBar)
          _whole(context)
        else
          // One window or two panes, the place is the same child of the same row: a phone folded open or
          // shut keeps the screen it had - its scroll, its caret, what was typed - where the page made
          // the note again in another part of the tree.
          _panes(context, split: split, dockShown: split && dockShown, aside: split && asideDocked ? aside : null),
        if (tabBar) _bar(context, docked: docked, sidebarShown: sidebarShown, quietBar: quietBar, asideHolds: asideHolds),
        if (widget.banner case final banner?)
          Positioned(
            top: tabBar ? (split ? 0 : context.tokens.len('app-inset-top')) + AppTabBar.heightOf(context.tokens) : context.tokens.len('app-inset-top'),
            left: 0,
            right: 0,
            child: banner,
          ),
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
  }

  /// Simple mode's frame for a place (GHST-105; Matt, 2026-10-18: "it still is a bit complex with the tabs and
  /// such"): the place alone, the whole window, as a phone has it, with nothing of the shell's drawn over it. The
  /// phone's back gesture is the place's own [OnBack], as ever; a note draws its own Back where it needs one
  /// (lib/note/note_screen.dart `back`).
  ///
  /// On a window wide enough for two panes ([split]) the home page is a column at the start, kept up whatever is
  /// on the right, and the place is the rest: the note being read, or with none open a quiet pane that says to pick
  /// one. So a note opened from the list shows beside it, and the list never goes away. The panes wear the page's
  /// class while the window is split, as the advanced frame's do ([_panes]).
  Widget _plain(BuildContext context, {required bool split}) {
    if (!split) return _place(context);
    final t = context.tokens;
    final window = MediaQuery.sizeOf(context).width;
    final rule = BorderSide(color: t.color('glacier-border-subtle'));
    final screen = _screen;
    return GlacierScope(
      classes: const {'app-split'},
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Your notes',
            child: Container(
              width: simpleListColumn(window),
              decoration: BoxDecoration(border: Border(right: rule)),
              child: ClipRect(
                child: KeyedSubtree(key: const ValueKey('simple:list'), child: widget.homeBuilder?.call(context, this) ?? HomePlaceholder(notes: notes, onOpen: openNote, onAllNotes: showAllNotes)),
              ),
            ),
          ),
          Expanded(
            key: const ValueKey('pane:place'),
            child: ClipRect(
              child: screen is ScreenList
                  ? KeyedSubtree(key: const ValueKey('simple:empty'), child: widget.emptyPaneBuilder?.call(context, this) ?? const SimpleEmptyPane())
                  : _place(context),
            ),
          ),
        ],
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
  /// The notes' column is simple mode's (Matt, 2026-10-24: "make the sidebar on advanced mode the same as simple but
  /// just hide it by default"): the same width, rule and name as [_plain]'s, holding what [AppShell.dockedSidebarBuilder]
  /// builds, which the root makes simple's list. It starts under the bar as every pane does, and the bar and the Mac's
  /// window buttons are the whole window's, so neither moves as it comes and goes; nor does the note, whose pane is
  /// the same child of the row with the column or without it.
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
              key: const ValueKey('pane:list'),
              container: true,
              explicitChildNodes: true,
              label: 'Your notes',
              child: Container(
                width: simpleListColumn(window),
                decoration: BoxDecoration(border: Border(right: rule)),
                child: ClipRect(child: widget.dockedSidebarBuilder?.call(context, this) ?? PanePlaceholder(what: 'the notes, docked', notes: notes, onOpen: openNote)),
              ),
            ),
          Expanded(key: const ValueKey('pane:place'), child: ClipRect(child: _place(context))),
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
    final chip = widget.barChip;
    // Simple mode's bar: no people icon, no bell, no Forward, no aside, and tabs with no groups.
    final simple = widget.simple;
    final named = widget.headerToolbar;
    return ListenableBuilder(
      listenable: Listenable.merge([_barTools, ?chip?.changes, if (named == null) headerToolbarChoice]),
      builder: (context, _) => AppTabBar(
        style: widget.topBar,
        child: NoteTabs(
          style: widget.topBar,
          // The line of controls in the version Developer chose; a change draws the bar again at once.
          version: named ?? headerToolbarVersion,
          toolsModel: _barTools.model,
          filters: _barTools.filters,
          onSearch: widget.onSearch,
          onAllNotes: showAllNotes,
          tabs: _tabs.tabs,
          activeId: shown ?? '',
          workspaces: widget.workspaces,
          liveTitles: widget.liveTitles,
          finePointer: widget.finePointer,
          tools: _barTools.tools,
          tail: _barTools.tail,
          presence: chip?.build(context),
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
          onGoOn: simple ? null : goOn,
          canGoBack: _walk.canBack,
          canGoOn: _walk.canOn,
          grouping: !simple,
          onNotifications: quietBar || simple
              ? null
              : () => _change(() {
                    _drawer = false;
                    _notificationsOpen = !_notificationsOpen;
                  }),
          onSettings: quietBar ? null : openSettings,
          onOrganizations: quietBar || simple ? null : openOrganizations,
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
