/// The home page in simple mode (GHST-105). Matt, 2026-10-18: "The simple mode in the app is not quite right, it
/// still is a bit complex with the tabs and such, spend a significant amount of time looking into simple apps like
/// todoist and others to build out a clean simple UI". Looked at: Apple Notes, Simplenote, Keep, Bear, Todoist,
/// Things, Reminders, TickTick. What they share, and what this is: a large title with a gear, a search under it, one
/// list of rows (a name, one line of how it starts, when) grouped by when it was touched, a + where the thumb is, and
/// two destinations along the foot. No tabs, no bar, no filters, no layouts, no cards: those are the advanced app's
/// (lib/home/home_screen.dart), which this replaces whenever the preference says simple (lib/root/root_parts.dart
/// `_homePage`).
///
/// Top to bottom: the title ("Notes", or "To-dos" on that tab) and the gear; the search, narrowing as it is typed;
/// the notices the root hands over (an update, the simple-or-advanced card, the Academy's card); then the rows,
/// under Pinned, Today, Yesterday, Earlier this week, This month and Earlier (the timeline's own spans and words,
/// lib/home/home_layout.dart). A tap opens the note; a swipe right pins or unpins it; a swipe left deletes it;
/// archive is in the note's menu, from a long press or a right-click. Notebooks, journals and canvases that exist
/// already are rows too, by their names. The To-dos tab shows what the root hands it ([SimpleHome.todos]).
///
/// On a wide window the shell draws this as a column beside the note (lib/shell/app_shell.dart `_plain`), and says
/// so with [SimpleHome.pane]: the Notes/To-dos switch is then a segmented control under the title and the + and the
/// microphone sit at the column's foot, since a bar along the window's foot would be under the note.
///
/// The same column is advanced mode's sidebar on a wide window (Matt, 2026-10-24: "make the sidebar on advanced mode
/// the same as simple but just hide it by default"; lib/root/root_parts.dart `_listColumn`), hidden until the bar's
/// panel icon shows it. There it stands under the advanced app's top bar ([SimpleHome.underBar]), which holds the
/// Mac's window buttons and the cog, so the column draws neither; and on a phone that can show the notes' folder its
/// foot carries Browse files, the old tree's tool that nothing else in advanced mode offers ([SimpleHome.onBrowseFiles]).
/// Nor does it draw the + and the microphone there (Matt, 2026-10-29, of the opened Fold's column: "remove these icons
/// from the sidebar"): the home page's dock beside it has both, so the column's foot is Browse files alone, or nothing.
///
/// What it reads is kept ([_Read]) until the notes, the search or the day change, as the advanced page keeps its own;
/// the rows are built as they are scrolled to.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/book.dart' show JournalCard, journalCards;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/page_scroll.dart';
import '../core/search_hits.dart';
import '../core/swipe.dart';
import '../home/home_layout.dart' show spanWords, spans;
import '../home/home_screen.dart' show GappedColumn;
import '../home/lazy_page.dart';
import '../home/home_text.dart';
import '../notes/note_menu.dart' show NoteMenuArea;
import '../notes/pull_to_refresh.dart';
import '../notes/swipe_row.dart';
import '../notes/when.dart';
import '../shell/desktop/mac_drag_strip.dart';
import '../shell/desktop/mac_lights.dart';
import '../shell/header_pane.dart' show StatusScrim;
import '../shell/header_toolbar.dart';
import 'simple_bar.dart';

export 'simple_bar.dart' show SimpleTab;

/// A run of rows under one heading: Pinned, or one of the timeline's spans; under a search, what was found.
@immutable
class SimpleGroup {
  const SimpleGroup({required this.key, required this.heading, required this.notes});
  final String key;
  final String heading;
  final List<Note> notes;
}

/// The page's groups, in order: the pinned notes first, newest first, then everything else by when it was last
/// touched (lib/home/home_layout.dart `spans`). The archive is left out. [now] is the moment the spans are counted
/// from, any time today.
List<SimpleGroup> simpleGroups(Iterable<Note> all, {int? now}) {
  final live = [for (final note in all) if (note.archivedAt == null) note];
  final pinned = [for (final group in spans(live.where((note) => note.starred), now)) ...group.notes];
  return [
    if (pinned.isNotEmpty) SimpleGroup(key: 'pinned', heading: 'Pinned', notes: pinned),
    for (final group in spans(live.where((note) => !note.starred), now)) SimpleGroup(key: group.span.name, heading: spanWords[group.span]!, notes: group.notes),
  ];
}

/// A row's swipes in simple mode: right to pin or unpin, as every list has it (lib/core/swipe.dart), and left to
/// delete, with no archive detent before it; archive is the menu's.
({List<SwipeAction> start, List<SwipeAction> end}) simpleSwipes(Note note) => (
      start: noteSwipes(note).start,
      end: const [SwipeAction(id: 'delete', label: 'Delete', icon: SwipeIcon.delete, tone: SwipeTone.danger, detent: 0.3, removes: true)],
    );

class SimpleHome extends StatefulWidget {
  const SimpleHome({
    super.key,
    required this.notes,
    this.loading = false,
    required this.onOpen,
    required this.onNew,
    this.onNewLong,
    this.onSpeak,
    this.onSettings,
    this.onSwipe,
    this.onNoteMenu,
    this.onRefresh,
    this.notices = const [],
    this.clock,
    this.tab = SimpleTab.notes,
    this.onTab,
    this.todos,
    this.pane = false,
    this.underBar = false,
    this.onBrowseFiles,
    this.ghost,
  });

  /// Every note the shell shows, the archive included (the page leaves it out).
  final List<Note> notes;

  /// The library is still being read: no empty page is said until it has been.
  final bool loading;

  /// A row tapped.
  final ValueChanged<String> onOpen;

  /// The +: a new note, straight away.
  final VoidCallback onNew;

  /// The + held: the sheet of everything else it can make.
  final VoidCallback? onNewLong;

  /// The microphone. Absent, and there is none: the root hands Talk to Claude where Claude can hear and the
  /// recorder otherwise, one microphone only (GHST-104).
  final VoidCallback? onSpeak;

  /// The gear.
  final VoidCallback? onSettings;

  /// A row swiped past a detent: pinned or unpinned, or deleted. Without it the rows do not swipe.
  final void Function(Note note, NoteSwipe action)? onSwipe;

  /// A row pressed and held, or right-clicked: the note's menu, where the finger or the pointer was.
  final void Function(String id, Offset at)? onNoteMenu;

  /// A pull down from the top: a sync, and the notes read again.
  final Future<void> Function()? onRefresh;

  /// What needs the person, above the rows.
  final List<Widget> notices;

  /// This moment, in milliseconds; the device's own where it is left out.
  final int Function()? clock;

  /// Which list is up, and the switch.
  final SimpleTab tab;
  final ValueChanged<SimpleTab>? onTab;

  /// The To-dos list, built by the root (lib/simple/simple_todos.dart `SimpleTodos`). Absent, a line says where it
  /// will be.
  final Widget? todos;

  /// Drawn as a column beside the note on a wide window: the switch moves under the title and the + and the
  /// microphone to the column's foot.
  final bool pane;

  /// Drawn under the advanced app's top bar, as its sidebar (2026-10-24): the head starts under the bar
  /// (`--app-safe-top`, which carries it) rather than under the notch, and the Mac's window buttons are the bar's to
  /// hold, so there is no row for them here. Simple mode has no bar and leaves this off.
  final bool underBar;

  /// Whether the page draws its search field: not as advanced mode's sidebar while the header toolbar's Grouped
  /// command (the default) or Command centre draws the bar over it, whose title pill is the search (Matt, 2026-10-28: "remove the search bar from the
  /// home page since it's redundant", and then "the search bar still shows up on the home page section": on the opened
  /// Fold the home page's notes column, this page, kept its field when the home page's own went). Simple mode, with
  /// no bar, always has it.
  bool get searchField => !(underBar && headerToolbarVersion.searchPill);

  /// Browse files at the start of the column's foot ([pane]): the notes' folder in the phone's Files app
  /// (lib/core/library_files.dart). The root hands it only to advanced mode's sidebar, on a device that can; the old
  /// tree's tool had it, and simple mode never did.
  final VoidCallback? onBrowseFiles;

  /// The ghost over the empty page's words (lib/art/ghost.dart), where the app hands one in.
  final Widget? ghost;

  @override
  State<SimpleHome> createState() => _SimpleHomeState();
}

/// What the page works out from its notes, kept until what it was made from changes.
class _Read {
  _Read({required this.notes, required this.query, required this.today, required this.groups, required this.journals});
  final List<Note> notes;
  final String query;
  final int today;
  final List<SimpleGroup> groups;
  final Map<String, JournalCard> journals;
}

class _SimpleHomeState extends State<SimpleHome> {
  final ScrollController _scroller = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'Simple search');
  String _query = '';
  _Read? _read;

  @override
  void initState() {
    super.initState();
    headerToolbarChoice.addListener(_versionChanged);
  }

  /// The bar's version chosen: the field goes or comes back, and what it had typed goes with it, so the column is
  /// never narrowed by a search there is no field to see.
  void _versionChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.searchField && _query.isNotEmpty) {
        _search.clear();
        _query = '';
      }
    });
  }

  @override
  void dispose() {
    headerToolbarChoice.removeListener(_versionChanged);
    _scroller.dispose();
    _search.dispose();
    _field.dispose();
    super.dispose();
  }

  int get _now => widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  _Read _reading(int today) {
    final had = _read;
    final notes = widget.notes;
    if (had != null && had.query == _query && had.today == today && sameNotes(had.notes, notes)) return had;
    final live = [for (final note in notes) if (note.archivedAt == null) note];
    final searching = _query.trim().isNotEmpty;
    final groups = searching
        // What was found, the nearest first, as one run of rows: a search is a question, not a timeline.
        ? [
            if (findNotes(live, _query, scope: SearchScope(notes: notes)) case final found when found.isNotEmpty) SimpleGroup(key: 'found', heading: 'Found', notes: [for (final one in found) one.note]),
          ]
        : simpleGroups(live, now: today);
    return _read = _Read(notes: List<Note>.of(notes, growable: false), query: _query, today: today, groups: groups, journals: journalCards(notes));
  }

  void _typed(String query) => setState(() => _query = query);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final now = _now;
    final at = DateTime.fromMillisecondsSinceEpoch(now);
    final read = _reading(DateTime(at.year, at.month, at.day).millisecondsSinceEpoch);
    final pane = widget.pane;
    final notesTab = widget.tab == SimpleTab.notes;
    final searched = read.query.trim().isNotEmpty;
    final hasNotes = read.notes.any((note) => note.archivedAt == null);

    final safeTop = t.len('app-safe-top');
    final safeBottom = t.len('app-safe-bottom');
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
    // On the Mac the window's buttons have a row of their own over the page ([_LightsRow]), and the title starts
    // just under it, as Settings' head does under theirs; elsewhere the page starts under the notch. Under the
    // advanced app's bar the bar holds them, and the page starts under the bar.
    final overlay = titlebarOverlay(t) && !widget.underBar;
    final headTop = overlay ? t.space(1) : safeTop + t.space(3);
    final gap = t.space(3);
    final hairline = t.len('glacier-hairline');
    final rule = BorderSide(color: t.color('app-rule'), width: hairline);
    // Room at the foot: the bar and the floating pair over it, or in a pane the foot row the pair stands in.
    final actionsRoom = SimpleActions.heightOf(t) + t.space(4) * 2;
    final foot = pane ? t.space(6) : safeBottom + SimpleBar.heightOf(t) + actionsRoom;

    final actions = SimpleActions(onNew: widget.onNew, onNewLong: widget.onNewLong, onSpeak: widget.onSpeak);

    final head = <Widget>[
      _Header(title: notesTab ? 'Notes' : 'To-dos', onSettings: widget.onSettings),
      if (pane && widget.onTab != null) _Switch(tab: widget.tab, onTab: widget.onTab!),
      if (widget.searchField && notesTab && (hasNotes || searched)) _SearchField(controller: _search, focusNode: _field, onQuery: _typed),
      if (widget.notices.isNotEmpty) GappedColumn(gap: gap, children: widget.notices),
    ];

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsetsDirectional.fromSTEB(gutterStart, headTop, gutterEnd, 0),
        sliver: SliverToBoxAdapter(child: GappedColumn(gap: gap, after: gap, children: head)),
      ),
      if (!notesTab)
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(gutterStart, 0, gutterEnd, foot),
          sliver: SliverToBoxAdapter(child: widget.todos ?? _Line('Your open to-dos will show here.')),
        )
      else ...[
        if (!widget.loading && !hasNotes)
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(gutterStart, 0, gutterEnd, foot),
            sliver: SliverToBoxAdapter(child: _Empty(hint: widget.onSpeak != null ? 'Write it, or tap the mic and say it.' : 'Tap + to write it.', ghost: widget.ghost)),
          )
        else if (!widget.loading && searched && read.groups.isEmpty)
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(gutterStart, 0, gutterEnd, foot),
            sliver: SliverToBoxAdapter(child: _Line('Nothing has “${read.query.trim()}”.')),
          ),
        for (final (i, group) in read.groups.indexed) ...[
          SliverPadding(
            key: ValueKey('simple-group-${group.key}'),
            padding: EdgeInsetsDirectional.fromSTEB(gutterStart, i == 0 ? 0 : t.space(5), gutterEnd, t.space(1)),
            sliver: SliverToBoxAdapter(child: _Heading(words: group.heading, count: group.notes.length)),
          ),
          SliverPadding(
            padding: EdgeInsetsDirectional.fromSTEB(gutterStart, 0, gutterEnd, i == read.groups.length - 1 ? foot : 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, n) {
                  final note = group.notes[n];
                  final row = SimpleRow(
                    key: ValueKey('simple-row-${note.id}'),
                    note: note,
                    now: now,
                    entries: read.journals[note.id]?.count,
                    onOpen: widget.onOpen,
                    onSwipe: widget.onSwipe,
                    onMenu: widget.onNoteMenu,
                  );
                  // A hairline between rows, and none over the first or under the last: the heading and the air
                  // after the group rule those off.
                  return n == 0 ? row : DecoratedBox(position: DecorationPosition.foreground, decoration: BoxDecoration(border: Border(top: rule)), child: row);
                },
                childCount: group.notes.length,
                addAutomaticKeepAlives: false,
                addSemanticIndexes: false,
              ),
            ),
          ),
        ],
      ],
    ];

    Widget page(PullDown? pull) => ScrollConfiguration(
          behavior: const _Still(),
          child: PageScroll(key: const ValueKey('simple-scroll'), controller: _scroller, pull: pull, slivers: slivers),
        );
    final scroller = widget.onRefresh == null ? page(null) : PullToRefresh(controller: _scroller, onRefresh: widget.onRefresh!, top: headTop, builder: (context, pull) => page(pull));

    final Widget body;
    if (pane && widget.underBar) {
      // Advanced mode's sidebar: the list, and Browse files at its foot where there is one; no + and no microphone,
      // which are the dock's.
      final browse = widget.onBrowseFiles;
      body = Column(
        children: [
          Expanded(child: scroller),
          if (browse != null)
            Container(
              padding: EdgeInsetsDirectional.fromSTEB(gutterStart, t.space(3), gutterEnd, safeBottom + t.space(3)),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: hairline))),
              child: Row(children: [_BrowseFiles(onPressed: browse), const Spacer()]),
            ),
        ],
      );
    } else if (pane) {
      // Beside the note: the list, and the pair in a foot row of their own.
      body = Column(
        children: [
          Expanded(child: scroller),
          Container(
            padding: EdgeInsetsDirectional.fromSTEB(gutterStart, t.space(3), gutterEnd, safeBottom + t.space(3)),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: hairline))),
            child: widget.onBrowseFiles == null
                ? Align(alignment: AlignmentDirectional.centerEnd, child: actions)
                : Row(children: [_BrowseFiles(onPressed: widget.onBrowseFiles!), const Spacer(), actions]),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: scroller),
                PositionedDirectional(end: gutterEnd, bottom: t.space(4), child: actions),
              ],
            ),
          ),
          SimpleBar(tab: widget.tab, onTab: (tab) => widget.onTab?.call(tab)),
        ],
      );
    }

    return ColoredBox(
      color: t.color('glacier-bg'),
      child: _AboveKeyboard(
        child: Stack(
          children: [
            Positioned.fill(child: overlay ? Column(children: [const _LightsRow(), Expanded(child: body)]) : body),
            // The phone's clock stands on paper, not on the rows scrolling under it.
            const StatusScrim(),
          ],
        ),
      ),
    );
  }
}

/// The Mac app's row for its three window buttons, over the page and nothing else in it (Matt, 2026-10-24: "in
/// simple mode we need to move the title under the traffic lights there is a bunch of empty white space on the
/// left"). Simple mode has no bar to set them into, and the page used to make room for them beside the title by
/// pushing the whole head in by `--app-traffic-lights`: the title, the switch, the search and the notices all began
/// 72px in while the rows under them began at the gutter, an empty column down the start of the list. Now the
/// buttons have this row to themselves, as Settings' head starts below theirs (lib/settings/settings_screen.dart
/// `_head`, the same 2.25rem), and says where its centre is so they sit on it (lib/shell/desktop/mac_lights.dart);
/// the title starts the page under it at the gutter, the gear at its end, and everything under them is as wide as
/// the rows. Its empty ground drags the window and zooms it on a double click, as the tab bar's does. Not drawn off
/// the Mac (`data-titlebar`), so a phone, a Fold and every other window keep the page as it was.
class _LightsRow extends StatelessWidget {
  const _LightsRow();

  @override
  Widget build(BuildContext context) => MacLightsRow(
        child: SizedBox(key: const ValueKey('simple-lights'), width: double.infinity, height: context.tokens.lenOf('2.25rem'), child: const MacDragStrip()),
      );
}

/// The page's window ends at the keyboard, less the phone's home bar, which the page always stands clear of
/// (lib/home/home_screen.dart has the same): the bar and the + ride over the keys while the search is typed.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = math.max(0.0, media.viewInsets.bottom - context.tokens.len('app-safe-bottom'));
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: MediaQuery(data: media.copyWith(size: Size(media.size.width, media.size.height - keyboard), viewInsets: media.viewInsets.copyWith(bottom: 0)), child: child),
    );
  }
}

/// The platform's overscroll glow and stretch left off, and no scrollbar of its own.
class _Still extends GhostScrollBehavior {
  const _Still();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// The title, large, and the gear at the row's end.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onSettings});
  final String title;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('3xl');
    final ring = t.len('app-ring');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, size, weight: 'bold', color: t.color('app-ink'), tracking: t.len('app-tracking-title', em: size), height: 1.15)),
          ),
        ),
        if (onSettings != null)
          GlacierPressable(
            key: const ValueKey('simple-settings'),
            semanticLabel: 'Settings',
            onPressed: onSettings,
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              child: Container(
                width: ring,
                height: ring,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null),
                child: AppIcon(Lucide.settings, size: 22, strokeWidth: 1.9, color: t.color('app-ink-2')),
              ),
            ),
          ),
      ],
    );
  }
}

/// Browse files, a quiet ring the size of the gear's with the folder's mark in it (the tree's tool, notes/NoteTree.tsx
/// `Browse files`), at the start of the column's foot across from the + and the microphone.
class _BrowseFiles extends StatelessWidget {
  const _BrowseFiles({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    return GlacierPressable(
      key: const ValueKey('simple-browse-files'),
      semanticLabel: 'Browse files',
      onPressed: onPressed,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          width: ring,
          height: ring,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null),
          child: AppIcon(Lucide.folderOpen, size: 22, strokeWidth: 1.9, color: t.color('app-ink-2')),
        ),
      ),
    );
  }
}

/// Notes or To-dos as a segmented control under the title, for the column beside a note.
class _Switch extends StatelessWidget {
  const _Switch({required this.tab, required this.onTab});
  final SimpleTab tab;
  final ValueChanged<SimpleTab> onTab;

  @override
  Widget build(BuildContext context) => GlacierSegmentedControl(
        key: const ValueKey('simple-switch'),
        ariaLabel: 'Notes or to-dos',
        fullWidth: true,
        size: GlacierSegmentedSize.sm,
        value: tab.name,
        onValueChange: (value) => onTab(SimpleTab.values.byName(value)),
        options: const [
          GlacierSegmentedOption(value: 'notes', label: Text('Notes')),
          GlacierSegmentedOption(value: 'todos', label: Text('To-dos')),
        ],
      );
}

/// A group's heading: the word, and how many, quiet.
class _Heading extends StatelessWidget {
  const _Heading({required this.words, required this.count});
  final String words;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      header: true,
      label: '$words, $count',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: t.space(1)),
        child: Row(
          children: [
            Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))),
            SizedBox(width: t.space(2)),
            Text('$count', style: tabular(pageText(t, sm, color: t.color('app-ink-3')))),
          ],
        ),
      ),
    );
  }
}

/// One quiet line of words.
class _Line extends StatelessWidget {
  const _Line(this.words);
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(padding: EdgeInsets.symmetric(vertical: t.space(4)), child: Text(words, style: pageText(t, t.fontSize('md'), color: t.color('app-ink-3'))));
  }
}

/// A library with nothing in it: the ghost, a lead and the hint.
class _Empty extends StatelessWidget {
  const _Empty({required this.hint, required this.ghost});
  final String hint;
  final Widget? ghost;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ghost = this.ghost;
    final size = t.fontSize('xl');
    return Padding(
      padding: EdgeInsets.only(top: t.space(6), bottom: t.space(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ghost != null) ...[ghost, SizedBox(height: t.space(5))],
          Text('A blank page.', style: pageText(t, size, weight: 'semibold', color: t.color('glacier-text-subtle'), tracking: t.len('app-tracking-title', em: size))),
          SizedBox(height: t.space(2)),
          Text(hint, style: pageText(t, t.fontSize('md'), color: t.color('glacier-text-muted'))),
        ],
      ),
    );
  }
}

/// A note on one row: a small pin where it is pinned, its name, one line of how it starts under it, and when it was
/// touched at the end. No kind mark: a notebook says "3 pages" and a canvas "4 cards" on its line instead. Swipes
/// right to pin and left to delete; held, or right-clicked, its menu.
class SimpleRow extends StatefulWidget {
  const SimpleRow({super.key, required this.note, required this.onOpen, this.now, this.entries, this.onSwipe, this.onMenu});

  final Note note;
  final ValueChanged<String> onOpen;
  final int? now;

  /// A journal's entries, where it is one.
  final int? entries;
  final void Function(Note note, NoteSwipe action)? onSwipe;
  final void Function(String id, Offset at)? onMenu;

  @override
  State<SimpleRow> createState() => _SimpleRowState();
}

class _SimpleRowState extends State<SimpleRow> {
  /// Where the last touch went down, for the menu a long press opens there.
  Offset _downAt = Offset.zero;

  static String _counted(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final note = widget.note;
    final facts = NoteFacts.of(note);
    final title = facts.title;
    final String lead;
    if (widget.entries != null) {
      lead = _counted(widget.entries!, 'entry', 'entries');
    } else if (facts.isBook) {
      lead = _counted(facts.chapters.length, 'page', 'pages');
    } else if (facts.isCanvas) {
      final cards = facts.canvasCards ?? 0;
      lead = cards > 0 ? _counted(cards, 'card', 'cards') : 'No cards yet';
    } else {
      lead = facts.shownFirstLine;
    }
    final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final ink3 = t.color('app-ink-3');
    final said = [title.isEmpty ? 'Untitled' : title, if (note.starred) 'pinned', if (lead.isNotEmpty) lead, when(note.updatedAt, widget.now)].join(', ');
    final onMenu = widget.onMenu;

    final row = GlacierPressable(
      onPressed: () => widget.onOpen(note.id),
      onLongPress: onMenu == null ? null : () => onMenu(note.id, _downAt),
      semanticLabel: said,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: 0,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(12)),
          padding: EdgeInsets.symmetric(vertical: t.space(3)),
          color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null,
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (note.starred) ...[
                            Transform.rotate(angle: -12 * math.pi / 180, child: AppIcon(Lucide.pin, size: 0.85 * md, strokeWidth: 2, color: ink3)),
                            SizedBox(width: 0.35 * md),
                          ],
                          Flexible(
                            child: Text(
                              title.isNotEmpty ? facts.shownTitle : 'Untitled',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: pageText(t, md, weight: 'semibold', color: title.isEmpty ? ink3 : t.color('app-ink')),
                            ),
                          ),
                        ],
                      ),
                      if (lead.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(lead, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: ink3)),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: t.space(3)),
                Padding(
                  // On the name's line, whatever the second line does.
                  padding: EdgeInsets.only(top: (md - xs) * 0.6),
                  child: Text(when(note.updatedAt, widget.now), softWrap: false, style: tabular(pageText(t, xs, color: ink3))),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final swipes = widget.onSwipe;
    final Widget swiped = swipes == null
        ? row
        : SwipeRow(
            start: simpleSwipes(note).start,
            end: simpleSwipes(note).end,
            onAction: (id) {
              final action = noteSwipeOf(id);
              if (action != null) swipes(note, action);
            },
            child: row,
          );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _downAt = event.position,
      child: NoteMenuArea(onMenu: onMenu == null ? null : (at) => onMenu(note.id, at), child: swiped),
    );
  }
}

/// The search: a field in a soft pill, the magnifier at its start, a cross to clear it once something is typed.
/// The same field the advanced page has (lib/home/home_filters.dart) less its filters' button, its operator chips
/// and its Save; those are advanced.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onQuery});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onQuery;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_redraw);
    widget.focusNode.addListener(_redraw);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    widget.focusNode.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final focused = widget.focusNode.hasFocus;
    final md = t.fontSize('md');
    final style = pageText(t, md, color: t.color('app-ink'));
    const words = 'Search';
    final empty = widget.controller.text.isEmpty;

    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: style,
      cursorColor: t.color('app-ink'),
      cursorWidth: 1,
      backgroundCursorColor: t.color('app-ink-3'),
      selectionColor: focused ? t.color('glacier-selection') : null,
      selectionControls: GlacierTextSelectionControls(color: t.color('glacier-accent-solid')),
      showSelectionHandles: _handles,
      contextMenuBuilder: (context, editable) => GlacierTextSelectionToolbar(tokens: t, editable: editable),
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: true,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      textCapitalization: TextCapitalization.none,
      onChanged: widget.onQuery,
      onSelectionChanged: (selection, cause) {
        final show = !empty && (cause == SelectionChangedCause.longPress || cause == SelectionChangedCause.doubleTap || cause == SelectionChangedCause.drag || cause == SelectionChangedCause.tap) && _gestures.shouldShowSelectionHandles;
        if (show != _handles) setState(() => _handles = show);
      },
      rendererIgnoresPointer: true,
      keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
    );

    return TextFieldTapRegion(
      child: Semantics(
        label: words,
        textField: true,
        onTap: () => editableTextKey.currentState?.requestKeyboard(),
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(10)),
          padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(2)),
          decoration: BoxDecoration(
            color: t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)'),
            border: Border.all(color: focused ? t.color('glacier-border-strong') : t.colorOf('transparent'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('md')),
          ),
          child: Row(
            children: [
              AppIcon(Lucide.search, size: 18, strokeWidth: 2.1, color: focused ? t.color('app-ink-2') : t.color('app-ink-3')),
              SizedBox(width: t.space(2)),
              Expanded(
                child: _gestures.buildGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: t.space(8)),
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          if (empty) ExcludeSemantics(child: Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('app-ink-3')))),
                          DefaultTextEditingShortcuts(child: editable),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!empty) ...[
                SizedBox(width: t.space(2)),
                GlacierPressable(
                  onPressed: () {
                    widget.controller.clear();
                    widget.onQuery('');
                    widget.focusNode.requestFocus();
                  },
                  semanticLabel: 'Clear the search',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    child: Container(
                      width: t.space(6),
                      height: t.space(6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                      child: AppIcon(Lucide.x, size: 14, strokeWidth: 2.4, color: t.color('app-ink-2')),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
