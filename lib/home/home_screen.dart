/// The home page: the notebooks and the notes, a search over them, and filters, drawn one of four ways. A port of
/// `src/app/home/HomeScreen.tsx` with HomeScreen.module.css and HomeLayouts.module.css (docs/DESIGN.md §147, §148,
/// §151, §152, §178).
///
/// At its top, the search: the page narrows as it is typed, every word anywhere in a note. Beside it, one button for
/// the filters - All, Notebooks, Notes, Pinned, and the workspace - with a chip under the search for each one on
/// (`home_filters.dart`). Then the notebooks and the notes in the layout chosen in Settings: the sections
/// `home_layout.dart` `homePlan` lays out, each drawn as cards, rows or lines. At the foot, the way to All notes; and
/// floating at the bottom right, the dock: Search, +, and Speak nearest the thumb.
///
/// The page sits under the app's tab bar, which is not drawn here: it pads by `--app-safe-top` (the notch and the
/// bar), `--app-safe-bottom` and the gutters, and puts up only the glass pane the bar sits on (app.css
/// `.app-headerPane`, the shell's `HeaderPane`), as the web page's own `<header>` does.
///
/// What differs from the web page:
/// - What it reads from the app is handed in: the layout (`usePreferences().homeLayout`), the workspaces
///   (`useWorkspaces()`), the organizations and who is in them (`useOrgs`, `usePresence`, the notifications' feed),
///   the meeting being recorded (`useMeetingState`), and the notices above the notes (an update, an invitation,
///   the voice model: `notes/Notices.tsx`, as [notices]). The lines the phone wrote under titles it asks for
///   itself, as the page does (`useGists(carded)`, format/gist.dart `Gists`): its first [homeGisted] cards, with
///   its search and its filter, and each card hears its own line.
/// - Two sheets it opened are callbacks: the workspace's (`notes/WorkspaceSheet.tsx`, [onManageWorkspace]) and a new
///   organization's (`home/NewOrganizationSheet.tsx`, [onNewOrganization]).
/// - The smoke is not drawn here. The wisp under the header and at the foot (`art/wispEdge.ts`) and the halo round
///   the dock (`art/dockSmoke.ts`) are two seams, [headerEdge] and [dockHalo], shaped for `lib/art`'s widgets:
///   `headerEdge: (context, edge, scroller) => WispEdge(under: edge.under, foot: true, child: scroller)` and
///   `dockHalo: (context, it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding)`.
/// - The ghosts of the empty pages (`art/Ghost.tsx`) are a third seam, [ghost]; without it the words stand alone.
/// - Another workspace, filter or layout glides the page back to its top, as on the web, but from wherever the new,
///   shorter page left it: the web first gives the page room at its foot to hold its place (`core/glideToTop.ts`).
/// - An organization's events dock beside the notes on a wide page, but do not stick as the page scrolls.
/// - A mouse's right-click on a note is [onNoteMenu], told where the pointer was, as the web's context menu.
/// - **Only what is near the screen is built** (lib/home/lazy_page.dart): the page is a `CustomScrollView`, each
///   section's notes a sliver that builds its rows as they are scrolled to, where the web has every row in the
///   document. Where things stand is the same; how far the page scrolls is known as far as it has been laid out.
///   A row's entrance still plays once, when it comes to be on the page and not when it is scrolled to
///   (home_parts.dart `Arrivals`).
/// - **The page is built once for what it shows.** What it works out from its notes ([_Read]) is kept until the
///   notes, the workspaces, the search, the filter, the layout or the day change, and its widgets ([_Drawn]) until
///   anything they draw does: built again with the same of everything (whoever holds the page builds it often, for
///   reasons of its own, with a new list of the same notes and new callbacks each time), it hands back the widgets
///   it made, and nothing under them is built. So the callbacks are called through the page as it is now, and the
///   three seams ([headerEdge], [dockHalo], [ghost]) are asked when the page is made and must answer the same for
///   the same arguments. The notices and the lines the phone writes under titles are read where they are drawn,
///   and built alone when they change.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/page_scroll.dart';
import '../core/book.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/search_ahead.dart';
import '../core/swipe.dart';
import '../core/workspaces.dart';
import '../format/gist.dart' show Gists;
import '../notes/pull_to_refresh.dart';
import '../perf/frame_log.dart';
import '../shell/header_pane.dart';
import 'home_filters.dart';
import 'home_icons.dart';
import 'home_layout.dart';
import 'home_org_events.dart';
import 'home_organizations.dart';
import 'home_parts.dart';
import 'home_rows.dart';
import 'home_text.dart';
import 'lazy_page.dart';
import 'note_card.dart';

/// Which ghost an empty page asks for (`<Ghost scene=...>`): a library with nothing in it, a workspace with nothing
/// in it, or a search or filter that found nothing.
enum HomeGhostScene { noNotes, emptyWorkspace, searchNothing }

/// Where the page's smoke goes, for whoever draws it: how far down the header pane reaches and how much room the
/// dock stands in at the foot, with the scroller's own controller to drift the smoke by.
@immutable
class HomeEdge {
  const HomeEdge({required this.under, required this.foot, required this.controller});

  /// The header pane's height, as the page pads under it (`--wisp-under`): the top bar and the notch.
  final double under;

  /// The room at the foot the page keeps clear for the dock (`padding-block-end` of the scroller).
  final double foot;
  final ScrollController controller;
}

/// The wisp under the header and at the foot: given the page's scroller, answers it with its smoke on.
typedef HomeEdgeBuilder = Widget Function(BuildContext context, HomeEdge edge, Widget scroller);

/// The dock over what scrolls behind it, for whoever draws its halo: the halo softens and bends what is behind the
/// dock, so it is handed both, with where the dock stands.
@immutable
class HomeDock {
  const HomeDock({required this.behind, required this.dock, required this.alignment, required this.padding});

  /// What scrolls behind the dock: the page's scroller, the whole of the screen's box.
  final Widget behind;

  /// The dock itself: Search, +, and Speak.
  final Widget dock;

  /// Where the dock stands in the screen's box: its bottom end corner, in from the edges by [padding].
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
}

/// The halo round the dock: given the dock and what is behind it, answers the two laid together with the halo
/// between them, the dock at [HomeDock.alignment] inside [HomeDock.padding] of the box it is given (the whole
/// screen's). The halo reaches past the dock's own box (the web's is 3rem out on every side).
typedef HomeDockHaloBuilder = Widget Function(BuildContext context, HomeDock dock);

/// The ghost an empty page asks for, as the web page asked `<Ghost>`: which scene, at which of its sizes, and the
/// share of the window's height the page's own stylesheet holds it to where it sets one over the size's.
@immutable
class HomeGhost {
  const HomeGhost({required this.scene, required this.lead, this.heightShare});

  final HomeGhostScene scene;

  /// `size="lead"`, the picture leading the page (the empty library); otherwise `small`, over a line of words.
  final bool lead;

  /// `calc(38dvh * var(--ghost-ratio))`, 0.38, where the ghost is stacked over its words on a phone; null where the
  /// size's own share stands (45% for a lead, 40% for a small one).
  final double? heightShare;
}

/// An empty page's ghost, laid in the room the page gives it (the column's width, or half of it beside its words):
/// it takes its own size from that and from [HomeGhost]. For `lib/art`'s widget:
/// `ghost: (context, it) => Ghost(scene: ..., size: it.lead ? GhostSize.lead : GhostSize.small, heightShare: it.heightShare)`.
typedef HomeGhostBuilder = Widget Function(BuildContext context, HomeGhost ghost);

/// How many of the first cards get a line written under their titles (format/gist.dart), the rest waiting for a
/// scroll (`GISTED`).
const int homeGisted = 16;

/// The home page (`src/app/home/HomeScreen.tsx`): the search and its filters, the notebooks and the notes in the
/// layout chosen, the way to All notes, and the dock. What it read from the app on the web it is handed here, what
/// left the page there is a callback here, and its smoke and its ghosts are seams ([headerEdge], [dockHalo],
/// [ghost]); the library doc above says each difference.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.notes,
    this.loading = false,
    required this.workspaces,
    this.layout = HomeLayout.spotlight,
    required this.onOpen,
    required this.onNew,
    this.onCapture,
    this.onSearch,
    required this.onAllNotes,
    this.onSwipe,
    this.onRefresh,
    this.onManageWorkspace,
    this.onNewOrganization,
    this.onOrganization,
    this.onOrganizationSettings,
    this.onNoteMenu,
    this.organizations = const [],
    this.orgNews = const [],
    this.recording,
    this.gists,
    this.notices = const [],
    this.clock,
    this.sideKey,
    this.headerEdge,
    this.dockHalo,
    this.ghost,
  });

  /// Every note of the library, the archive included (the page leaves it out).
  final List<Note> notes;

  /// The library is still being read: no empty page is said until it has been.
  final bool loading;

  /// The workspaces, and which one the page is filtered to.
  final WorkspaceStore workspaces;

  /// How the notebooks and the notes are laid out (Settings › Appearance).
  final HomeLayout layout;

  /// A note opened.
  final ValueChanged<String> onOpen;

  /// The dock's +: a new note.
  final VoidCallback onNew;

  /// Speak: left out where nothing records, and Speak with it.
  final VoidCallback? onCapture;

  /// The command palette; absent, and the dock has no Search.
  final VoidCallback? onSearch;

  /// Every note, as a grid of cards.
  final VoidCallback onAllNotes;

  /// A note swiped past a detent: pinned or unpinned, archived, or deleted. Without it the notes do not swipe.
  final void Function(Note note, NoteSwipe action)? onSwipe;

  /// A pull down from the top: a sync, and the notes read again. Without it the page does not pull.
  final Future<void> Function()? onRefresh;

  /// A workspace to rename, colour or remove, or null for a new one: the workspace's sheet.
  final ValueChanged<Workspace?>? onManageWorkspace;

  /// A new organization, from the filters' panel; absent signed out.
  final VoidCallback? onNewOrganization;

  /// An organization's dashboard. Absent, the page draws no organizations.
  final ValueChanged<String>? onOrganization;

  /// An organization's settings, from "Edit" on its workspace; absent, the dashboard.
  final ValueChanged<String>? onOrganizationSettings;

  /// A note pressed and held: its menu.
  final void Function(String id, Offset at)? onNoteMenu;

  /// The organizations this account has joined, and who is in each now.
  final List<HomeOrg> organizations;

  /// The team's news of the organization the page is filtered to.
  final List<OrgNews> orgNews;

  /// The meeting being recorded now, by its note's id: its row says so.
  final String? recording;

  /// What each note is about in a line, by note id, where a picture or a test brings its own. Left out, the page
  /// asks for them itself, as the web's does (`useGists(carded)`): the first [homeGisted] cards it draws, with its
  /// search and its filter, are the ones the phone writes a line for, and the ones that show theirs.
  final Map<String, String>? gists;

  /// What needs the person, above the notes: an update ready, an invitation, the voice model's download.
  final List<Widget> notices;

  /// This moment, in milliseconds; the device's own where it is left out.
  final int Function()? clock;

  /// Whether the phone has a side key to hold and speak (the web's `isAndroid`); this platform's answer where it is
  /// left out.
  final bool? sideKey;

  /// The wisp under the header and at the foot, to be dropped in (see [HomeEdgeBuilder]).
  final HomeEdgeBuilder? headerEdge;

  /// The halo round the dock, to be dropped in (see [HomeDockHaloBuilder]).
  final HomeDockHaloBuilder? dockHalo;

  /// The empty pages' ghosts, to be dropped in (see [HomeGhostBuilder]).
  final HomeGhostBuilder? ghost;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// What the page works out from its notes: which of them it lists and how they are laid out, every page's notebook
/// and every journal's card. Made again only when what it was made from changes ([_HomeScreenState._reading]).
class _Read {
  _Read({
    required this.notes,
    required this.spaces,
    required this.query,
    required this.filter,
    required this.layout,
    required this.today,
    required this.lists,
    required this.counts,
    required this.inBooks,
    required this.journals,
    required this.plan,
  });

  // What it was made from.
  final List<Note> notes;
  final Workspaces spaces;
  final String query;
  final HomeFilter filter;
  final HomeLayout layout;
  final int today;

  // What was made.
  final HomeLists lists;
  final Map<HomeFilter, int> counts;
  final Map<String, BookPlace> inBooks;
  final Map<String, JournalCard> journals;
  final HomePlan plan;
}

/// Everything the page's widgets are made from besides what [_Read] holds. Two builds with the same of all of it
/// draw the same page, and the second hands back the first's widgets, so nothing under them is built again.
@immutable
class _Drawn {
  const _Drawn({
    required this.read,
    required this.tokens,
    required this.minute,
    required this.loading,
    required this.recording,
    required this.organizations,
    required this.orgNews,
    required this.sideKey,
    required this.keyboard,
    required this.seams,
  });

  final _Read read;
  final Tokens tokens;

  /// The minute it is: what "20 min ago" is counted from changes with it.
  final int minute;
  final bool loading;
  final String? recording;
  final List<HomeOrg> organizations;
  final List<OrgNews> orgNews;
  final bool sideKey;

  /// Whether the keyboard is up: the home bar is under it then.
  final bool keyboard;

  /// Which of the things the page may be handed it was handed, a bit each: a callback left out is a button not
  /// drawn, and a seam left out is a page drawn without it.
  final int seams;

  bool same(_Drawn other) =>
      identical(read, other.read) &&
      identical(tokens, other.tokens) &&
      minute == other.minute &&
      loading == other.loading &&
      recording == other.recording &&
      (identical(organizations, other.organizations) || listEquals(organizations, other.organizations)) &&
      (identical(orgNews, other.orgNews) || listEquals(orgNews, other.orgNews)) &&
      sideKey == other.sideKey &&
      keyboard == other.keyboard &&
      seams == other.seams;
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroller = ScrollController();
  final GlobalKey<HomeFiltersState> _filters = GlobalKey<HomeFiltersState>();

  /// When each card, row and line came to be on the page, for its entrance.
  final Arrivals _arrivals = Arrivals();

  /// The notices above the notes, as handed over at the last build: read by the page where they stand.
  final ValueNotifier<List<Widget>> _notices = ValueNotifier<List<Widget>>(const <Widget>[]);

  /// What each note is about in a line, for the page's first cards: read by each card for its own note, so a line
  /// the phone has just written draws one card again and nothing else. And when each line came to be there.
  final ValueNotifier<Map<String, String>> _gists = ValueNotifier<Map<String, String>>(const <String, String>{});
  final Arrivals _gistArrivals = Arrivals();

  /// The lines' runner, shown this page's first cards each time they change and heard as it writes one
  /// (format/gist.dart `Gists`, the page's `useGists`); none where the lines are handed in.
  Gists? _runner;

  /// The lines as they are now: a card whose own line is another is the only thing drawn again.
  void _takeGists(Map<String, String> now) {
    if (identical(_gists.value, now) || mapEquals(_gists.value, now)) return;
    _gistArrivals.keep(now.keys);
    _gists.value = now;
  }

  void _gistsSpoke() {
    if (_runner case final runner?) _takeGists(runner.value);
  }

  String _query = '';
  final SearchAhead _ahead = SearchAhead();
  HomeFilter _filter = HomeFilter.all;
  String? _glideKey;
  _Read? _read;
  _Drawn? _drawn;
  Widget? _page;

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_redraw);
    if (widget.gists == null) _runner = Gists()..addListener(_gistsSpoke);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaces != widget.workspaces) {
      oldWidget.workspaces.removeListener(_redraw);
      widget.workspaces.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_redraw);
    _runner
      ?..removeListener(_gistsSpoke)
      ..dispose();
    _scroller.dispose();
    _notices.dispose();
    _gists.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  /// Another workspace, filter or layout: the page glides back to its top rather than jumping there.
  void _glide(String key) {
    if (_glideKey == null || _glideKey == key) {
      _glideKey = key;
      return;
    }
    _glideKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroller.hasClients || _scroller.position.pixels <= 0) return;
      if (context.tokens.reducedMotion) {
        _scroller.jumpTo(0);
      } else {
        _scroller.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
    });
  }

  int get _now => widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  // What the page's widgets call, whoever handed the page its callbacks at the build they were made in: the widgets
  // are kept from one build to the next, and the callbacks are made anew at each.
  void _open(String id) => widget.onOpen(id);
  void _menu(String id, Offset at) => widget.onNoteMenu?.call(id, at);
  void _new() => widget.onNew();
  void _capture() => widget.onCapture?.call();
  void _search() => widget.onSearch?.call();
  void _allNotes() => widget.onAllNotes();
  Future<void> _refresh() async => widget.onRefresh?.call();
  void _manage(Workspace? which) => widget.onManageWorkspace?.call(which);
  void _newOrganization() => widget.onNewOrganization?.call();
  void _organization(String id) => widget.onOrganization?.call(id);
  void _organizationSettings(String id) => (widget.onOrganizationSettings ?? widget.onOrganization)?.call(id);

  /// What the page works out from its notes, made again only when the notes, the workspaces, the search, the
  /// filter, the layout or the day changed. Whoever hands the page its notes may make a new list of the same notes
  /// at every build, so they are asked note by note ([sameNotes]).
  _Read _reading(Workspaces spaces, int today) {
    final had = _read;
    final notes = widget.notes;
    if (had != null && identical(had.spaces, spaces) && had.query == _query && had.filter == _filter && had.layout == widget.layout && had.today == today && sameNotes(had.notes, notes)) {
      return had;
    }
    if (ghostPerf) Perf.count('home.read');
    final workspace = spaces.current?.id;
    final inSpace = widget.workspaces.inWorkspace(notes, workspace, (note) => note.id);
    final began = ghostPerf ? Perf.now() : 0;
    final lists = homeLists(inSpace, _query, _filter);
    if (ghostPerf) Perf.add('home.lists', began);
    final read = _Read(
      // A list of the page's own: the one handed over may be changed after.
      notes: List<Note>.of(notes, growable: false),
      spaces: spaces,
      query: _query,
      filter: _filter,
      layout: widget.layout,
      today: today,
      lists: lists,
      counts: homeCounts(inSpace),
      // Every page's notebook, for a card's and a row's mark.
      inBooks: bookIndex(inSpace),
      journals: journalCards(notes),
      // The day the spans are counted from: a new plan when it turns, not on every draw.
      plan: homePlan(widget.layout, lists, now: today),
    );
    // Whatever the page lists now has arrived, or arrives now.
    _arrivals.keep([
      for (final section in read.plan.sections)
        for (final (at, note) in section.notes.indexed) ...[
          _placed(section, at, note),
          if (section.draw == SectionDraw.cards) _name(section, note),
        ],
    ]);
    // A line under each card's title, for the first cards only: the runner asks about what is on screen, as the
    // page lays it out now, what it searched for and filtered to included (`useGists(carded)`).
    if (_runner case final runner?) {
      runner.show(cardsIn(read.plan).take(homeGisted).toList(growable: false));
      _takeGists(runner.value);
    }
    return _read = read;
  }

  /// What a note is called on the page, for when it arrived: the section it is in and how it is drawn there. A card
  /// that is one to a row is known by this; it keeps its place among its fellows as they move.
  static String _name(HomeSection section, Note note) => '${section.key}/${section.draw.name}/${note.id}';

  /// And with where it stands in its section: a row, a line, and a card across a row of cards are known by their
  /// place too, and arrive again when it changes, as each was made again when the list was a column.
  static String _placed(HomeSection section, int at, Note note) => '${section.key}/${section.draw.name}/$at/${note.id}';

  // Under [_KeyboardWatch], which says whether the keyboard is up as a yes or a no: the page asked the window for
  // the keyboard's height here, another number at every frame of its rise, and was built again at each of them
  // (on the phone, opening search over it: home.build=26 in the 42 frames, tool/perf.sh android search).
  @override
  Widget build(BuildContext context) => _KeyboardWatch(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    if (ghostPerf) Perf.count('home.build');
    final t = context.tokens;
    final spaces = widget.workspaces.value;
    final workspace = spaces.current?.id;
    _glide('${workspace ?? 'all'}|${_filter.name}|${widget.layout.name}');

    final now = _now;
    final at = DateTime.fromMillisecondsSinceEpoch(now);
    final read = _reading(spaces, DateTime(at.year, at.month, at.day).millisecondsSinceEpoch);
    final drawn = _Drawn(
      read: read,
      tokens: t,
      minute: now ~/ 60000,
      loading: widget.loading,
      recording: widget.recording,
      organizations: widget.organizations,
      orgNews: widget.orgNews,
      sideKey: widget.sideKey ?? defaultTargetPlatform == TargetPlatform.android,
      // The home bar is under the keyboard while it is up: nothing to stand clear of then.
      keyboard: _KeyboardUp.of(context),
      seams: (widget.onCapture != null ? 1 : 0) |
          (widget.onSearch != null ? 2 : 0) |
          (widget.onSwipe != null ? 4 : 0) |
          (widget.onRefresh != null ? 8 : 0) |
          (widget.onNoteMenu != null ? 16 : 0) |
          (widget.onOrganization != null ? 32 : 0) |
          (widget.onOrganizationSettings != null ? 64 : 0) |
          (widget.onNewOrganization != null ? 128 : 0) |
          (widget.headerEdge != null ? 256 : 0) |
          (widget.dockHalo != null ? 512 : 0) |
          (widget.ghost != null ? 1024 : 0),
    );
    // The notices are made anew by whoever hands them over, at every build: the page reads them where they stand,
    // and nothing else of it is built for them.
    if (!listEquals(_notices.value, widget.notices)) _notices.value = widget.notices;
    if (widget.gists case final given?) _takeGists(given);

    var page = _page;
    final was = _drawn;
    if (page == null || was == null || !was.same(drawn)) {
      if (ghostPerf) Perf.count('home.page');
      _drawn = drawn;
      page = _page = _made(context, drawn, now);
    }
    // The page's window ends at the keyboard: on the phone the web's frame is padded by it (MainActivity's insets
    // listener), so the dock and the smoke at the foot ride above the keys and `dvh` is of what is left. Always
    // wrapped, so a keyboard coming up moves the page and does not rebuild it.
    return _AboveKeyboard(child: page);
  }

  /// The page's widgets, for everything [drawn] holds. [now] is the moment "20 min ago" is counted from.
  Widget _made(BuildContext context, _Drawn drawn, int now) {
    final t = drawn.tokens;
    final read = drawn.read;
    final spaces = read.spaces;
    final workspace = spaces.current?.id;
    // The organization the page is filtered to, when the chosen workspace is one's.
    final orgSpace = workspace == null ? null : orgIdOf(workspace);
    final notes = read.notes;
    final counts = read.counts;
    final inBooks = read.inBooks;
    final journals = read.journals;
    final plan = read.plan;
    final layout = read.layout;
    final query = read.query, filter = read.filter;
    final recording = drawn.recording;
    final organizations = drawn.organizations;

    final searched = query.trim().isNotEmpty;
    final hasNotes = counts[HomeFilter.all]! > 0;
    // The search and its filters stay while there is anything to find, or a workspace to leave.
    final tools = notes.any((n) => n.archivedAt == null) || spaces.list.isNotEmpty;
    // Whether the layout draws anything: what the search and the filter found, as the layout places it.
    final found = plan.sections.isNotEmpty;

    // The header pane is the bar's height, and the page pads under it by what the web measured of it: a whole pixel.
    final safeTop = t.len('app-safe-top');
    final under = safeTop.roundToDouble() > safeTop ? safeTop.roundToDouble() : safeTop;
    final ring = t.len('app-ring');
    final top = under + t.space(1) + t.space(2) + t.space(6);
    // Room at the foot for the dock's column to stand clear of the last lines.
    final safeBottom = drawn.keyboard ? 0.0 : t.len('app-safe-bottom');
    final foot = safeBottom + t.space(4) + ring * 4 + t.space(2) * 5 + t.space(6);
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');

    final swipes = widget.onSwipe != null;
    final onMenu = widget.onNoteMenu == null ? null : _menu;
    // Right to pin, left to archive, further left to delete: every card, row and line swipes.
    NoteSwipes? swipe(Note note) {
      if (!swipes) return null;
      final actions = noteSwipes(note);
      return (
        start: actions.start,
        end: actions.end,
        onAction: (id) {
          final action = noteSwipeOf(id);
          if (action != null) widget.onSwipe?.call(note, action);
        },
      );
    }

    // The workspace a line's note is filed in, for its pill. None while the page is filtered to one.
    Workspace? filedIn(Note note) {
      if (workspace != null) return null;
      final id = spaces.of[note.id];
      if (id == null) return null;
      for (final space in spaces.list) {
        if (space.id == id) return space;
      }
      return null;
    }

    // The cards' arrival is staggered down the page, whichever section each is in: each section's notes are
    // numbered on from the section before.
    final firsts = <int>[];
    var order = 0;
    for (final section in plan.sections) {
      firsts.add(order);
      order += section.notes.length;
    }

    final hairline = t.len('glacier-hairline');
    final rule = BorderSide(color: t.color('app-rule'), width: hairline);

    /// The notebook a row's note is a page of, and that notebook's workflow, which a ticket's status is placed in.
    List<String>? workflowOf(BookPlace? place) => place == null ? null : NoteFacts.of(place.book).statuses;

    /// A section's notes, as a sliver of the page [width] wide: only the ones near the screen are built.
    Widget body(HomeSection section, int first, double width) {
      final list = section.notes;
      switch (section.draw) {
        case SectionDraw.cards:
          return SliverNoteCards(
            count: list.length,
            width: width,
            itemBuilder: (context, i, fill) {
              final note = list[i];
              final place = placeOf(inBooks, note);
              return Gisted(
                gists: _gists,
                id: note.id,
                builder: (context, gist) => NoteCard(
                  key: ValueKey('card-${note.id}'),
                  note: note,
                  index: first + i,
                  onOpen: _open,
                  now: now,
                  gist: gist,
                  place: place,
                  entries: journals[note.id],
                  fill: fill,
                  swipe: swipe(note),
                  onMenu: onMenu,
                  since: _arrivals.since(fill ? _placed(section, i, note) : _name(section, note)),
                  gistSince: _gistArrivals.since(note.id),
                ),
              );
            },
            idOf: (i) => list[i].id,
          );
        case SectionDraw.rows:
        case SectionDraw.lines:
          final last = list.length - 1;
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final note = list[i];
                final place = placeOf(inBooks, note);
                final since = _arrivals.since(_placed(section, i, note));
                final Widget row = section.draw == SectionDraw.rows
                    ? HomeRow(
                        key: ValueKey('row-${note.id}'),
                        note: note,
                        index: first + i,
                        onOpen: _open,
                        now: now,
                        bookName: place?.title,
                        workflow: workflowOf(place),
                        entries: journals[note.id]?.count,
                        live: note.id == recording,
                        swipe: swipe(note),
                        onMenu: onMenu,
                        since: since,
                      )
                    : HomeLine(
                        key: ValueKey('line-${note.id}'),
                        note: note,
                        index: first + i,
                        onOpen: _open,
                        now: now,
                        bookName: place?.title,
                        workflow: workflowOf(place),
                        live: note.id == recording,
                        swipe: swipe(note),
                        space: filedIn(note),
                        onMenu: onMenu,
                        since: since,
                      );
                // A hairline over the list, between its rows, and under it: the list's own over its first row and
                // under its last, and each row after the first with one over it.
                Widget ruled = Padding(padding: EdgeInsets.only(top: hairline), child: row);
                ruled = i == 0
                    ? DecoratedBox(decoration: BoxDecoration(border: Border(top: rule, bottom: i == last ? rule : BorderSide.none)), child: i == last ? Padding(padding: EdgeInsets.only(bottom: hairline), child: ruled) : ruled)
                    : DecoratedBox(position: DecorationPosition.foreground, decoration: BoxDecoration(border: Border(top: rule)), child: ruled);
                if (i == last && i != 0) ruled = DecoratedBox(decoration: BoxDecoration(border: Border(bottom: rule)), child: Padding(padding: EdgeInsets.only(bottom: hairline), child: ruled));
                return KeyedSubtree(key: _Slot('$i/${note.id}'), child: ruled);
              },
              childCount: list.length,
              addAutomaticKeepAlives: false,
              // The rows are said as they were: no place in a list is added to what a screen reader hears.
              addSemanticIndexes: false,
            ),
          );
      }
    }

    final sm = t.fontSize('sm');
    final ink3 = t.color('app-ink-3');
    Widget? mark(SectionMark? mark) => switch (mark) {
          SectionMark.notebook => HomeIcon(HomeGlyph.notebook, size: 1.1 * sm, color: ink3),
          SectionMark.note => HomeIcon(HomeGlyph.note, size: 15, color: ink3),
          // The pin leans, as it does on a row.
          SectionMark.pinned => Transform.rotate(angle: -12 * 3.141592653589793 / 180, child: HomeIcon(HomeGlyph.pin, size: 1.1 * sm, color: ink3)),
          SectionMark.recent => HomeIcon(HomeGlyph.clock, size: 1.1 * sm, color: ink3),
          null => null,
        };

    final gap = t.space(3);
    final showGhost = widget.ghost == null ? null : (BuildContext context, HomeGhost it) => widget.ghost!(context, it);

    /// What stands in the page's main column, [width] wide: an empty page's words, the sections, and the way to All
    /// notes, each a sliver with the room over it (`display: grid; gap`, and a section's own air).
    List<({Widget sliver, double above})> column(double width) {
      final blocks = <({Widget sliver, double above})>[];
      void add(Widget sliver, [double more = 0]) => blocks.add((sliver: sliver, above: (blocks.isEmpty ? 0 : gap) + more));
      if (!drawn.loading && !hasNotes) {
        add(SliverToBoxAdapter(
          child: _Empty(
            workspace: spaces.current,
            hint: drawn.sideKey ? 'Write it, or hold the side key and say it.' : (widget.onCapture != null ? 'Write it, or tap Speak and say it.' : 'Tap + to write it.'),
            ghost: showGhost,
          ),
        ));
      } else if (!drawn.loading && hasNotes && !found) {
        add(SliverToBoxAdapter(
          child: _Nothing(
            lead: searched ? 'Nothing has “${query.trim()}”.' : (filter == HomeFilter.pinned ? 'Nothing is pinned.' : 'Nothing here.'),
            hint: searched ? 'Try fewer words, or look through All notes.' : null,
            ghost: showGhost,
          ),
        ));
      }
      if (found) {
        for (final (at, section) in plan.sections.indexed) {
          // A section: one quiet heading - a mark, the word, how many - then its notes.
          add(
            SliverToBoxAdapter(
              key: ValueKey('section-${section.key}'),
              child: Padding(padding: EdgeInsets.only(bottom: t.space(2)), child: HomeHeading(mark: mark(section.mark), words: section.heading, count: section.count)),
            ),
            t.space(3),
          );
          blocks.add((sliver: body(section, firsts[at], width), above: 0));
        }
      }
      if (hasNotes) add(SliverToBoxAdapter(child: _AllNotes(words: plan.cut > 0 ? '${plan.cut} more in All notes' : 'All notes · ${counts[HomeFilter.all]}', onPressed: _allNotes)));
      return blocks;
    }

    final hasOrganization = widget.onOrganization != null;
    // The search first, the page narrowing as it is typed, and its filters beside it. Not on a blank page. Then
    // what needs the person, and the organizations joined.
    final head = <Widget>[
      if (tools)
        HomeFilters(
          key: _filters,
          query: query,
          onQuery: (query) => setState(() => _query = query),
          // What the search reads of each note, made as the field takes the keyboard.
          onSearching: () => _ahead.begin(() => widget.notes, alive: () => mounted),
          filter: filter,
          onFilter: (filter) => setState(() => _filter = filter),
          counts: counts,
          workspaces: widget.workspaces,
          onManage: _manage,
          onNewOrganization: widget.onNewOrganization == null ? null : _newOrganization,
          onOrganization: widget.onOrganizationSettings != null || hasOrganization ? _organizationSettings : null,
        ),
      ValueListenableBuilder<List<Widget>>(
        valueListenable: _notices,
        builder: (context, notices, _) => notices.isEmpty ? const SizedBox.shrink() : _Gapped(gap: gap, children: notices),
      ),
      // The organizations joined, a card each; not while searching, nor inside one workspace.
      if (hasOrganization && !searched && workspace == null && organizations.isNotEmpty) HomeOrganizations(orgs: organizations, notes: notes, filed: spaces.of, onOpen: _organization),
    ];

    /// The page's slivers in a window [viewport] wide, made once for a width: the pull that lowers the page builds
    /// its scroller again at every move, with these same slivers.
    double? madeFor;
    var made = const <Widget>[];
    var madeWide = false;
    List<Widget> slivers(double viewport) {
      if (madeFor == viewport) return made;
      // The column the layouts ask their width of (`@container home-page`).
      final inner = math.max(0.0, viewport - gutterStart - gutterEnd);
      final wide = inner >= t.lenOf('44rem');
      final rows = layout == HomeLayout.list || layout == HomeLayout.timeline;
      // Wider, the rows' layouts keep one readable column.
      final across = math.min(inner, t.lenOf(wide && rows ? '48rem' : '64rem'));
      final side = (inner - across) / 2;
      Widget padded(Widget sliver, {double above = 0, double below = 0}) =>
          SliverPadding(padding: EdgeInsetsDirectional.fromSTEB(gutterStart + side, above, gutterEnd + side, below), sliver: sliver);

      final List<({Widget sliver, double above})> blocks;
      final bool follows;
      if (orgSpace != null && !searched) {
        final events = HomeOrgEvents(
          orgId: orgSpace,
          name: spaces.current!.name,
          notes: notes,
          filed: spaces.of,
          here: [for (final org in organizations) if (org.id == orgSpace) ...org.here],
          news: drawn.orgNews,
          onOpenNote: _open,
          onOpen: _organization,
          now: now,
        );
        follows = true;
        if (inner >= t.lenOf('52rem')) {
          // Docked to the right of the notes on a page wide enough.
          final beside = t.lenOf('18rem'), between = t.space(4);
          final main = column(math.max(0.0, across - between - beside));
          blocks = [
            (
              sliver: SliverCrossAxisGroup(
                slivers: [
                  SliverCrossAxisExpanded(
                    flex: 1,
                    sliver: SliverMainAxisGroup(slivers: [for (final block in main) block.above > 0 ? SliverPadding(padding: EdgeInsets.only(top: block.above), sliver: block.sliver) : block.sliver]),
                  ),
                  SliverConstrainedCrossAxis(maxExtent: between, sliver: const SliverToBoxAdapter(child: SizedBox.shrink())),
                  SliverConstrainedCrossAxis(maxExtent: beside, sliver: SliverToBoxAdapter(child: events)),
                ],
              ),
              above: 0,
            ),
          ];
        } else {
          // Narrower, the card sits over them.
          final main = column(across);
          blocks = [
            (sliver: SliverToBoxAdapter(child: events), above: 0),
            for (final (i, block) in main.indexed) (sliver: block.sliver, above: i == 0 ? t.space(4) + block.above : block.above),
          ];
        }
      } else {
        blocks = column(across);
        follows = blocks.isNotEmpty;
      }

      madeFor = viewport;
      madeWide = wide;
      return made = [
        // Blocks one under another with a gap between them; the head's own gap is under it only while it draws
        // anything, and something follows.
        padded(SliverToBoxAdapter(child: _Gapped(gap: gap, after: follows ? gap : 0, children: head)), above: top, below: blocks.isEmpty ? foot : 0),
        for (final (i, block) in blocks.indexed) padded(block.sliver, above: block.above, below: i == blocks.length - 1 ? foot : 0),
      ];
    }

    Widget page(PullDown? pull) {
      final Widget scroller = ScrollConfiguration(
        // `overscroll-behavior: contain`: the page stops at its ends, with no glow and no stretch of the platform's.
        behavior: const _Still(),
        child: LayoutBuilder(
          builder: (context, box) {
            final all = slivers(box.maxWidth);
            return _HomeWidth(wide: madeWide, child: PageScroll(key: const ValueKey('home-scroll'), controller: _scroller, pull: pull, slivers: all));
          },
        ),
      );
      final edge = widget.headerEdge;
      return edge == null ? scroller : edge(context, HomeEdge(under: under, foot: foot, controller: _scroller), scroller);
    }

    // One scroller for the whole page, under the top bar.
    final behind = widget.onRefresh == null ? page(null) : PullToRefresh(controller: _scroller, onRefresh: _refresh, top: top, builder: (context, pull) => page(pull));
    // The dock: a floating column in the bottom right, the palette, write, then Speak nearest the thumb.
    final dock = HomeDock(
      behind: behind,
      dock: _Dock(onNew: _new, onCapture: widget.onCapture == null ? null : _capture, onSearch: widget.onSearch == null ? null : _search),
      alignment: AlignmentDirectional.bottomEnd,
      padding: EdgeInsetsDirectional.only(end: t.len('app-safe-right') + t.space(4), bottom: safeBottom + t.space(4)),
    );
    return _screen(t, widget.dockHalo, dock);
  }

  Widget _screen(Tokens t, HomeDockHaloBuilder? halo, HomeDock dock) {
    return ColoredBox(
      color: t.color('glacier-bg'),
      // Nothing drawn here widens the window: the halo is cut only where it was past the window anyway.
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: halo != null
                  ? halo(context, dock)
                  : Stack(
                      fit: StackFit.expand,
                      children: [dock.behind, Padding(padding: dock.padding, child: Align(alignment: dock.alignment, child: dock.dock))],
                    ),
            ),
            // The top bar: no word at all, only the pane the app's tab bar sits on, at exactly the bar's height.
            const HeaderPane(child: _SaidOnly('Home')),
          ],
        ),
      ),
    );
  }
}

/// The name a row is kept by in its list, where only the rows near the screen are built: its place and its note, so
/// a row whose place moves is made again there, as it was when the list was a column (a row was the child of the
/// box that ruled it off, and that box was known by where it stood). A key of its own kind, so the row's own key
/// (`row-<id>`) still finds one widget.
class _Slot extends ValueKey<String> {
  const _Slot(super.value);
}

/// Whether the keyboard is up, said to the page as a yes or a no ([_KeyboardUp]): what it wants to know (whether
/// the phone's own bar is there to stand clear of) changes twice a keyboard, not at every frame of one.
class _KeyboardWatch extends StatelessWidget {
  const _KeyboardWatch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => _KeyboardUp(up: MediaQuery.viewInsetsOf(context).bottom > 0, child: child);
}

class _KeyboardUp extends InheritedWidget {
  const _KeyboardUp({required this.up, required super.child});
  final bool up;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_KeyboardUp>()?.up ?? false;

  @override
  bool updateShouldNotify(_KeyboardUp oldWidget) => oldWidget.up != up;
}

/// The page's window ends at the keyboard: padded by it, and what is under it told that the window is that much
/// shorter and has no keyboard in it. Built at every frame of the keyboard's rise; the page under it is not.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: MediaQuery(
        data: media.copyWith(size: Size(media.size.width, media.size.height - keyboard), viewInsets: media.viewInsets.copyWith(bottom: 0)),
        child: child,
      ),
    );
  }
}

/// The page's own width, for the parts that ask it (`@container home-page (min-width: 44rem)`).
class _HomeWidth extends InheritedWidget {
  const _HomeWidth({required this.wide, required super.child});
  final bool wide;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_HomeWidth>()?.wide ?? false;

  @override
  bool updateShouldNotify(_HomeWidth old) => old.wide != wide;
}

/// `display: grid; gap: <gap>`: its children one under another.
/// Blocks one under another with [gap] between them, as the page's `display: grid; gap` lays its sections out, with
/// one thing the grid does by itself and a Column of boxes does not: **a block with nothing in it takes no room, and
/// no gap either.** On the page a notice with nothing to say is not in the tree at all (`Notices.tsx` renders null),
/// so nothing stands between the search row and the first section. Here a notice decides inside its own build (the
/// invitation's card listens to the account), so it is in the list while it draws nothing, and its gap put the first
/// section 14px low on a signed-in phone (measured on the Fold beside the page).
///
/// [after] is room under the last block that takes any: the gap to whatever follows these blocks on the page, where
/// that is laid out apart from them (the page's sections are slivers of their own). None under blocks that all
/// take no room.
class _Gapped extends MultiChildRenderObjectWidget {
  const _Gapped({required this.gap, this.after = 0, required super.children});
  final double gap;
  final double after;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGapped(gap, after);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderGapped renderObject) {
    renderObject
      ..gap = gap
      ..after = after;
  }
}

class _GappedParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderGapped extends RenderBox with ContainerRenderObjectMixin<RenderBox, _GappedParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GappedParentData> {
  _RenderGapped(this._gap, this._after);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _after;
  set after(double value) {
    if (value == _after) return;
    _after = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GappedParentData) child.parentData = _GappedParentData();
  }

  double _run(BoxConstraints constraints, {required bool place}) {
    final inner = BoxConstraints(minWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.minWidth, maxWidth: constraints.maxWidth);
    var y = 0.0, any = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final Size size;
      if (place) {
        child.layout(inner, parentUsesSize: true);
        size = child.size;
      } else {
        size = child.getDryLayout(inner);
      }
      if (size.height <= 0) {
        if (place) (child.parentData! as _GappedParentData).offset = Offset(0, y);
        continue;
      }
      if (any) y += _gap;
      if (place) (child.parentData! as _GappedParentData).offset = Offset(0, y);
      y += size.height;
      any = true;
    }
    return any ? y + _after : y;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.minWidth, _run(constraints, place: false)));

  @override
  void performLayout() {
    final height = _run(constraints, place: true);
    size = constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.minWidth, height));
  }

  double _tall(double width, double Function(RenderBox child) of) {
    var y = 0.0, any = false;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final h = of(child);
      if (h <= 0) continue;
      if (any) y += _gap;
      y += h;
      any = true;
    }
    return any ? y + _after : y;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _tall(width, (child) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _tall(width, (child) => child.getMaxIntrinsicHeight(width));

  @override
  double computeMinIntrinsicWidth(double height) {
    var most = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final w = child.getMinIntrinsicWidth(double.infinity);
      if (w > most) most = w;
    }
    return most;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var most = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final w = child.getMaxIntrinsicWidth(double.infinity);
      if (w > most) most = w;
    }
    return most;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// The platform's overscroll glow and stretch left off, and no scrollbar of its own.
class _Still extends GhostScrollBehavior {
  const _Still();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// `.saidOnly` (app.css `.app-unseen`): the screen's name for a screen reader alone, one pixel square and taking no
/// room, since the page has no visible title.
class _SaidOnly extends StatelessWidget {
  const _SaidOnly(this.words);
  final String words;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 0,
      child: OverflowBox(
        alignment: AlignmentDirectional.topStart,
        minWidth: 1,
        maxWidth: 1,
        minHeight: 1,
        maxHeight: 1,
        child: Semantics(header: true, label: words, child: const SizedBox.square(dimension: 1)),
      ),
    );
  }
}

/// `.empty`: a library, or a workspace, with nothing in it. Stacked on a phone; wider, the ghost and its words side by
/// side, two equal columns, the ghost against the gap.
class _Empty extends StatelessWidget {
  const _Empty({required this.workspace, required this.hint, required this.ghost});

  final Workspace? workspace;
  final String hint;
  final HomeGhostBuilder? ghost;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final wide = _HomeWidth.of(context);
    final size = t.fontSize('3xl'), md = t.fontSize('md');
    final lead = Text(
      workspace != null ? 'Nothing in ${workspace!.name} yet.' : 'A blank page.',
      style: pageText(t, size, weight: 'semibold', color: t.color('glacier-text-subtle'), height: t.len('glacier-leading-3xl'), tracking: t.len('app-tracking-title', em: size)),
    );
    final hintStyle = pageText(t, md, color: t.color('glacier-text-muted'), height: t.len('glacier-leading-md'));
    // `max-inline-size: 28ch`: twenty-eight of the face's own noughts.
    final nought = TextPainter(text: TextSpan(text: '0', style: hintStyle), textDirection: TextDirection.ltr)..layout();
    final words = ConstrainedBox(constraints: BoxConstraints(maxWidth: 28 * nought.width), child: Text(hint, style: hintStyle));
    nought.dispose();
    final scene = workspace != null ? HomeGhostScene.emptyWorkspace : HomeGhostScene.noNotes;
    final build = ghost;
    return Padding(
      padding: EdgeInsets.only(top: t.space(6), bottom: t.space(8)),
      child: LayoutBuilder(
        builder: (context, box) {
          // The ghost in grey under the words' weight. Stacked over its words it leaves them room above the dock: 38%
          // of the window's height, where beside them it may have a lead's full 45%.
          Widget? art({required bool stacked}) => build?.call(context, HomeGhost(scene: scene, lead: true, heightShare: stacked ? 0.38 : null));
          if (!wide) {
            final drawn = art(stacked: true);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (drawn != null) ...[drawn, SizedBox(height: t.space(5))],
                lead,
                SizedBox(height: t.space(3)),
                words,
              ],
            );
          }
          final drawn = art(stacked: false);
          return Row(
            children: [
              Expanded(child: drawn == null ? const SizedBox.shrink() : Align(alignment: AlignmentDirectional.centerEnd, child: drawn)),
              SizedBox(width: t.space(10)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [lead, SizedBox(height: t.space(3)), words]),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `.nothing`: a search or filter that found nothing: a small ghost and a line.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.lead, required this.hint, required this.ghost});

  final String lead;
  final String? hint;
  final HomeGhostBuilder? ghost;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final build = ghost;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (build != null) ...[build(context, const HomeGhost(scene: HomeGhostScene.searchNothing, lead: false)), SizedBox(height: t.space(2))],
          Text(lead, style: pageText(t, t.fontSize('xl'), weight: 'semibold', color: t.color('app-ink-2'))),
          if (hint != null) ...[SizedBox(height: t.space(2)), Text(hint!, style: pageText(t, t.fontSize('md'), color: t.color('app-ink-3')))],
        ],
      ),
    );
  }
}

/// `.allNotes`: the way to the grid of every note: the grid's mark, the words and the count, on one line, a group's
/// air above it.
class _AllNotes extends StatelessWidget {
  const _AllNotes({required this.words, required this.onPressed});

  final String words;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    return Padding(
      padding: EdgeInsets.only(top: t.space(8)),
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: words,
        builder: (context, state) {
          // `.app-word:active`, then `.allNotes:hover`, over the page's quiet ink.
          final color = state.pressed ? t.color('glacier-text') : (state.hovered ? t.color('app-ink') : t.color('glacier-text-subtle'));
          return GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('sm'),
            child: Container(
              constraints: BoxConstraints(minHeight: t.space(12)),
              padding: EdgeInsets.symmetric(vertical: t.space(4)),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    HomeIcon(HomeGlyph.grid, size: md, color: color),
                    SizedBox(width: t.space(2)),
                    Expanded(child: Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, md, weight: 'medium', color: color))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.dock`: write, Speak and the palette as a floating column locked to the bottom right, on every screen. Search on
/// top, write in the middle, Speak last, nearest the thumb, still the one ink-filled thing, as a circle the size of
/// the other two so the column is one width.
class _Dock extends StatelessWidget {
  const _Dock({required this.onNew, required this.onCapture, required this.onSearch});

  final VoidCallback onNew;
  final VoidCallback? onCapture;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final ring = t.len('app-ring');
    final radius = BorderRadius.circular(t.radius('full'));
    final turn = t.transition('app-turn');
    // The glyphs are `1.15rem`, the size `.round` sets.
    final glyph = t.lenOf('1.15rem');
    return Semantics(
      container: true,
      label: 'New note',
      // Each button its own, however few there are: one alone would otherwise be read as the dock itself.
      explicitChildNodes: true,
      child: ClipRRect(
        borderRadius: radius,
        // One of the bars' group where there is one (lib/notes/tabs/bar_parts.dart `BarGlass`).
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
            foregroundDecoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: radius),
            decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 82%, transparent)'), borderRadius: radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSearch != null) ...[
                  // The magnifier leans in when pressed, rather than turning.
                  _Round(
                    key: const ValueKey('dock-search'),
                    label: 'Search and commands',
                    onPressed: onSearch!,
                    builder: (pressed) => AnimatedScale(scale: pressed ? 0.9 : 1, duration: turn.duration, curve: turn.curve, child: HomeIcon(HomeGlyph.magnifier, size: glyph, color: t.color('glacier-text'))),
                  ),
                  SizedBox(height: gap),
                ],
                // A new note: the + gives a quarter turn when pressed.
                _Round(
                  key: const ValueKey('dock-add'),
                  label: 'Write a note',
                  onPressed: onNew,
                  builder: (pressed) => AnimatedRotation(turns: pressed ? 0.25 : 0, duration: turn.duration, curve: turn.curve, child: HomeIcon(HomeGlyph.plus, size: glyph, color: t.color('glacier-text'))),
                ),
                if (onCapture != null) ...[
                  SizedBox(height: gap),
                  // Speak is the screen's one ink pill: the thing Ghost.md is for, where the thumb already is.
                  GlacierPressable(
                    key: const ValueKey('dock-speak'),
                    onPressed: onCapture,
                    semanticLabel: 'Speak a voice note',
                    builder: (context, state) => GlacierFocusRing(
                      visible: state.focused,
                      offset: 3,
                      color: t.color('app-ink'),
                      child: AnimatedScale(
                        scale: state.pressed ? 0.98 : 1,
                        duration: t.duration('glacier-duration-fast'),
                        curve: t.curve('glacier-ease-out'),
                        child: Container(
                          width: ring,
                          height: ring,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle),
                          child: HomeIcon(HomeGlyph.mic, size: 18, strokeWidth: 2.2, color: t.color('app-paper')),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.round`: an icon in a ring the height of the Speak pill, there but a step quieter than the one filled thing on
/// the screen. Each gives a small move when pressed.
class _Round extends StatelessWidget {
  const _Round({super.key, required this.label, required this.onPressed, required this.builder});

  final String label;
  final VoidCallback onPressed;
  final Widget Function(bool pressed) builder;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          width: ring,
          height: ring,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.color('glacier-bg'), shape: BoxShape.circle, border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line'))),
          child: builder(state.pressed),
        ),
      ),
    );
  }
}
