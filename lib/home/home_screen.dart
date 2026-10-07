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
///   the meeting being recorded (`useMeetingState`), the lines the phone wrote under titles (`useGists`), and the
///   notices above the notes (an update, an invitation, the voice model: `notes/Notices.tsx`, as [notices]).
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
/// - A note's long press is [onNoteMenu], where the web opened its context menu.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/note.dart';
import '../core/swipe.dart';
import '../core/workspaces.dart';
import '../notes/pull_to_refresh.dart';
import '../shell/header_pane.dart';
import 'home_filters.dart';
import 'home_icons.dart';
import 'home_layout.dart';
import 'home_org_events.dart';
import 'home_organizations.dart';
import 'home_rows.dart';
import 'home_text.dart';
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
    this.gists = const {},
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
  final ValueChanged<String>? onNoteMenu;

  /// The organizations this account has joined, and who is in each now.
  final List<HomeOrg> organizations;

  /// The team's news of the organization the page is filtered to.
  final List<OrgNews> orgNews;

  /// The meeting being recorded now, by its note's id: its row says so.
  final String? recording;

  /// What each note is about in a line, by note id, where the phone has written it.
  final Map<String, String> gists;

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

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroller = ScrollController();
  final GlobalKey<HomeFiltersState> _filters = GlobalKey<HomeFiltersState>();
  String _query = '';
  HomeFilter _filter = HomeFilter.all;
  String? _glideKey;

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_redraw);
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
    _scroller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final spaces = widget.workspaces.value;
    final workspace = spaces.current?.id;
    // The organization the page is filtered to, when the chosen workspace is one's.
    final orgSpace = workspace == null ? null : orgIdOf(workspace);
    _glide('${workspace ?? 'all'}|${_filter.name}|${widget.layout.name}');

    final notes = widget.notes;
    final inSpace = widget.workspaces.inWorkspace(notes, workspace, (note) => note.id);
    final lists = homeLists(inSpace, _query, _filter);
    final counts = homeCounts(inSpace);
    // Every page's notebook, for a card's and a row's mark.
    final inBooks = bookIndex(inSpace);
    final journals = journalCards(notes);
    final now = _now;
    // The day the spans are counted from: a new plan when it turns, not on every draw.
    final at = DateTime.fromMillisecondsSinceEpoch(now);
    final today = DateTime(at.year, at.month, at.day).millisecondsSinceEpoch;
    final plan = homePlan(widget.layout, lists, now: today);

    final searched = _query.trim().isNotEmpty;
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
    final foot = t.len('app-safe-bottom') + t.space(4) + ring * 4 + t.space(2) * 5 + t.space(6);

    // The cards' arrival is staggered down the page, whichever section each is in.
    var order = 0;
    // Right to pin, left to archive, further left to delete: every card, row and line swipes.
    NoteSwipes? swipe(Note note) {
      final onSwipe = widget.onSwipe;
      if (onSwipe == null) return null;
      final actions = noteSwipes(note);
      return (
        start: actions.start,
        end: actions.end,
        onAction: (id) {
          final action = noteSwipeOf(id);
          if (action != null) onSwipe(note, action);
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

    Widget drawn(HomeSection section) {
      final hairline = t.len('glacier-hairline');
      final rule = BorderSide(color: t.color('app-rule'), width: hairline);
      switch (section.draw) {
        case SectionDraw.cards:
          final first = order;
          order += section.notes.length;
          return NoteCards(
            count: section.notes.length,
            itemBuilder: (context, i, fill) {
              final note = section.notes[i];
              final place = placeOf(inBooks, note);
              return NoteCard(
                key: ValueKey('card-${note.id}'),
                note: note,
                index: first + i,
                onOpen: widget.onOpen,
                now: now,
                gist: widget.gists[note.id],
                place: place,
                notebook: place?.book.body,
                entries: journals[note.id],
                fill: fill,
                swipe: swipe(note),
                onMenu: widget.onNoteMenu,
              );
            },
          );
        case SectionDraw.rows:
        case SectionDraw.lines:
          // A hairline over the list, between its rows, and under it.
          return DecoratedBox(
            decoration: BoxDecoration(border: Border(top: rule, bottom: rule)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: hairline),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, note) in section.notes.indexed)
                    DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(border: i == 0 ? null : Border(top: rule)),
                      child: Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : hairline),
                        child: section.draw == SectionDraw.rows
                            ? HomeRow(
                                key: ValueKey('row-${note.id}'),
                                note: note,
                                index: order++,
                                onOpen: widget.onOpen,
                                now: now,
                                bookName: placeOf(inBooks, note)?.title,
                                notebook: placeOf(inBooks, note)?.book.body,
                                entries: journals[note.id]?.count,
                                live: note.id == widget.recording,
                                swipe: swipe(note),
                                onMenu: widget.onNoteMenu,
                              )
                            : HomeLine(
                                key: ValueKey('line-${note.id}'),
                                note: note,
                                index: order++,
                                onOpen: widget.onOpen,
                                now: now,
                                bookName: placeOf(inBooks, note)?.title,
                                notebook: placeOf(inBooks, note)?.book.body,
                                live: note.id == widget.recording,
                                swipe: swipe(note),
                                space: filedIn(note),
                                onMenu: widget.onNoteMenu,
                              ),
                      ),
                    ),
                ],
              ),
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

    // What stands in the page's main column: an empty page's words, the sections, and the way to All notes.
    final main = <Widget>[
      if (!widget.loading && !hasNotes)
        _Empty(
          workspace: spaces.current,
          hint: (widget.sideKey ?? defaultTargetPlatform == TargetPlatform.android)
              ? 'Write it, or hold the side key and say it.'
              : (widget.onCapture != null ? 'Write it, or tap Speak and say it.' : 'Tap + to write it.'),
          ghost: widget.ghost,
        )
      else if (!widget.loading && hasNotes && !found)
        _Nothing(
          lead: searched ? 'Nothing has “${_query.trim()}”.' : (_filter == HomeFilter.pinned ? 'Nothing is pinned.' : 'Nothing here.'),
          hint: searched ? 'Try fewer words, or look through All notes.' : null,
          ghost: widget.ghost,
        ),
      if (found)
        for (final section in plan.sections)
          Padding(
            key: ValueKey('section-${section.key}'),
            // A section: one quiet heading - a mark, the word, how many - then its notes.
            padding: EdgeInsets.only(top: t.space(3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                HomeHeading(mark: mark(section.mark), words: section.heading, count: section.count),
                SizedBox(height: t.space(2)),
                drawn(section),
              ],
            ),
          ),
      if (hasNotes) _AllNotes(words: plan.cut > 0 ? '${plan.cut} more in All notes' : 'All notes · ${counts[HomeFilter.all]}', onPressed: widget.onAllNotes),
    ];

    final onOrganization = widget.onOrganization;
    Widget page(PullDown? pull) {
      final column = LayoutBuilder(
        builder: (context, box) {
          // The column the layouts ask their width of (`@container home-page`).
          final wide = box.maxWidth >= t.lenOf('44rem');
          final rows = widget.layout == HomeLayout.list || widget.layout == HomeLayout.timeline;
          final gap = t.space(3);
          Widget notesAndEvents = _Gapped(gap: gap, children: main);
          if (orgSpace != null && !searched) {
            final events = HomeOrgEvents(
              orgId: orgSpace,
              name: spaces.current!.name,
              notes: notes,
              filed: spaces.of,
              here: [for (final org in widget.organizations) if (org.id == orgSpace) ...org.here],
              news: widget.orgNews,
              onOpenNote: widget.onOpen,
              onOpen: (id) => onOrganization?.call(id),
              now: now,
            );
            // Docked to the right of the notes on a page wide enough; narrower, the card sits over them.
            notesAndEvents = box.maxWidth >= t.lenOf('52rem')
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: notesAndEvents), SizedBox(width: t.space(4)), SizedBox(width: t.lenOf('18rem'), child: events)],
                  )
                : _Gapped(gap: t.space(4), children: [events, notesAndEvents]);
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // Wider, the rows' layouts keep one readable column.
              constraints: BoxConstraints(maxWidth: t.lenOf(wide && rows ? '48rem' : '64rem')),
              child: _HomeWidth(
                wide: wide,
                child: _Gapped(
                  gap: gap,
                  children: [
                    // The search first, the page narrowing as it is typed, and its filters beside it. Not on a blank page.
                    if (tools)
                      HomeFilters(
                        key: _filters,
                        query: _query,
                        onQuery: (query) => setState(() => _query = query),
                        filter: _filter,
                        onFilter: (filter) => setState(() => _filter = filter),
                        counts: counts,
                        workspaces: widget.workspaces,
                        onManage: (which) => widget.onManageWorkspace?.call(which),
                        onNewOrganization: widget.onNewOrganization,
                        onOrganization: widget.onOrganizationSettings ?? onOrganization,
                      ),
                    if (widget.notices.isNotEmpty) _Gapped(gap: gap, children: widget.notices),
                    // The organizations joined, a card each; not while searching, nor inside one workspace.
                    if (onOrganization != null && !searched && workspace == null && widget.organizations.isNotEmpty)
                      HomeOrganizations(orgs: widget.organizations, notes: notes, filed: spaces.of, onOpen: onOrganization),
                    notesAndEvents,
                  ],
                ),
              ),
            ),
          );
        },
      );
      final scroller = ScrollConfiguration(
        // `overscroll-behavior: contain`: the page stops at its ends, with no glow and no stretch of the platform's.
        behavior: const _Still(),
        child: SingleChildScrollView(
          key: const ValueKey('home-scroll'),
          controller: _scroller,
          physics: pull?.physics ?? const ClampingScrollPhysics(),
          padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), top, t.len('app-gutter-end'), foot),
          child: pull == null ? column : PullLowered(pull: pull, child: column),
        ),
      );
      final edge = widget.headerEdge;
      return edge == null ? scroller : edge(context, HomeEdge(under: under, foot: foot, controller: _scroller), scroller);
    }

    final onRefresh = widget.onRefresh;
    // One scroller for the whole page, under the top bar.
    final behind = onRefresh == null ? page(null) : PullToRefresh(controller: _scroller, onRefresh: onRefresh, top: top, builder: (context, pull) => page(pull));
    // The dock: a floating column in the bottom right, the palette, write, then Speak nearest the thumb.
    final dock = HomeDock(
      behind: behind,
      dock: _Dock(onNew: widget.onNew, onCapture: widget.onCapture, onSearch: widget.onSearch),
      alignment: AlignmentDirectional.bottomEnd,
      padding: EdgeInsetsDirectional.only(end: t.len('app-safe-right') + t.space(4), bottom: t.len('app-safe-bottom') + t.space(4)),
    );
    final halo = widget.dockHalo;
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

/// The page's own width, for the parts that ask it (`@container home-page (min-width: 44rem)`).
class _HomeWidth extends InheritedWidget {
  const _HomeWidth({required this.wide, required super.child});
  final bool wide;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_HomeWidth>()?.wide ?? false;

  @override
  bool updateShouldNotify(_HomeWidth old) => old.wide != wide;
}

/// `display: grid; gap: <gap>`: its children one under another.
class _Gapped extends StatelessWidget {
  const _Gapped({required this.gap, required this.children});
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (at, child) in children.indexed) ...[if (at > 0) SizedBox(height: gap), child],
        ],
      );
}

/// The platform's overscroll glow and stretch left off, and no scrollbar of its own.
class _Still extends ScrollBehavior {
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
        child: BackdropFilter(
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
                    builder: (pressed) => AnimatedScale(scale: pressed ? 0.9 : 1, duration: turn.duration, curve: turn.curve, child: HomeIcon(HomeGlyph.search, size: glyph, color: t.color('glacier-text'))),
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
                          child: HomeIcon(HomeGlyph.mic, size: 18, color: t.color('app-paper')),
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
