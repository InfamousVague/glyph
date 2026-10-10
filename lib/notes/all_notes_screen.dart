/// Every note, as a page of cards. A port of `src/app/notes/AllNotesScreen.tsx` with AllNotesScreen.module.css
/// (Matt: "Browsing all notes is super hard there is no good UI it just opens in the sidebar, I'd like a grid view of
/// all the notes in the 'all notes' section").
///
/// A glass bar with the way home and the search, and under it the workspace pills, one line of order words, and the
/// grid of cards (lib/home/note_card.dart, drawn dense): one to a row on a phone, three or four on the Fold opened
/// out, more across a desktop window. The search is over the notes' words, the pills choose which notes, the order
/// is the last touched or by name, the archive is shown when asked for, and only the notes with a tape when the
/// Tapes word is on (docs/DESIGN.md §127, §132). A tap on a card opens the note; the arrow goes home, and so does
/// the phone's back gesture, which the shell hears for this screen (lib/shell/app_shell.dart wraps it in `OnBack`).
///
/// The rules - what the search finds, the order, the archive, the tapes - are lib/notes/all_notes.dart.
///
/// What differs from the web page:
/// - What it read from the app is handed in: the workspaces (`useWorkspaces()`), the lines the phone wrote under
///   titles (`useGists`, as [AllNotesScreen.gists]), where the order is kept ([AllNotesScreen.stored]), and what
///   the device can do, for the empty page's hint (`isAndroid`, `recordsVoice`: [AllNotesScreen.sideKey],
///   [AllNotesScreen.speaks]).
/// - **The order words are a Chromium page's**, the Fold's own WebView: a `<button>` there has one pixel of padding
///   above and below its word, so a word is 20px tall at the phone's size. WebKit gives a button two above and three
///   below, and the same line is 23px on an iPhone. Measured in both; see test/allnotes.
/// - A note's menu (`notes/noteMenu.ts`) opens on a mouse's right-click, as on the page, and on a long press too,
///   which is how lib/home/note_card.dart offers it: [AllNotesScreen.onNoteMenu] is told which note and where.
/// - The cards' AI corner mark and where a note was written are the card's own gaps (see lib/home/note_card.dart).
/// - The glide back to the top borrows more room than the page did (lib/core/glide_to_top.dart).
/// - The smoke under the bar is [WispEdge], asked for with [AllNotesScreen.wisp] (the `wispEdge` preference); the
///   page's hook also measured the bar, where here its height is worked out from the same rules that lay it out.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/page_scroll.dart';
import '../art/art.dart';
import '../core/book.dart';
import '../core/glide_to_top.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/stored.dart';
import '../core/workspaces.dart';
import '../home/home_parts.dart';
import '../home/home_text.dart';
import '../home/lazy_page.dart';
import '../home/note_card.dart';
import '../perf/frame_log.dart';
import '../shell/desktop/desktop_scrollbar.dart' show desktopScrollbarWidth;
import '../shell/header_pane.dart';
import '../shell/wide_screen.dart' show mousePointer;
import 'all_notes.dart';
import 'pull_to_refresh.dart';
import 'workspace_bar.dart';
import 'workspace_sheet.dart';

/// How many of the cards on the page have their gist written (`GISTED`): the first screens of them.
const int allNotesGisted = 24;

/// A `<button>`'s own padding above and below its words in Chromium, the Fold's WebView (the user agent's
/// `padding-block: 1px`). The order words ask for no padding of their own, so this is what draws.
const double _buttonPadBlock = 1;

/// The All notes page (`src/app/notes/AllNotesScreen.tsx`). What it read from the app is handed in, and its menu,
/// its smoke and its hint are parameters; the library doc lists each difference.
class AllNotesScreen extends StatefulWidget {
  const AllNotesScreen({
    super.key,
    required this.notes,
    this.loading = false,
    required this.workspaces,
    required this.onOpen,
    required this.onBack,
    this.tapes = false,
    this.onRefresh,
    this.onOrganization,
    this.onOrganizationSettings,
    this.onNoteMenu,
    this.notesInWorkspace,
    this.onTrashNotes,
    this.gists = const {},
    this.stored,
    this.clock,
    this.sideKey = false,
    this.speaks = false,
    this.wisp = true,
  });

  /// Every note the app shows: the trash and the notes hidden by a delete already taken out.
  final List<Note> notes;
  final bool loading;
  final WorkspaceStore workspaces;
  final ValueChanged<String> onOpen;

  /// Home.
  final VoidCallback onBack;

  /// Opened with the Tapes word already on, from the home page's Tapes heading, its "See all".
  final bool tapes;

  /// A pull down from the top (lib/notes/pull_to_refresh.dart): a sync, and the notes read again.
  final Future<void> Function()? onRefresh;

  /// An organization's dashboard, from its workspace's pill tapped again.
  final ValueChanged<String>? onOrganization;

  /// An organization's settings, from its workspace's sheet; absent, the dashboard.
  final ValueChanged<String>? onOrganizationSettings;

  /// A note's menu asked for, by a mouse's right-click or a long press: which note, and where in the window.
  final void Function(Note note, Offset at)? onNoteMenu;

  /// For the workspace's sheet (lib/notes/workspace_sheet.dart): which notes a delete would ask about, and the way
  /// to put them in the trash with it.
  final List<String> Function(String workspaceId)? notesInWorkspace;
  final void Function(List<String> noteIds)? onTrashNotes;

  /// What each note is about in a line, by its id (`format/gist.ts`), for the first [allNotesGisted] cards.
  final Map<String, String> gists;

  /// Where the order chosen is kept; the app's own unless given.
  final Stored? stored;

  /// The moment "20 min ago" is counted from; this one where it is left out.
  final int Function()? clock;

  /// The phone has a side key that records (`isAndroid`), for the empty page's hint.
  final bool sideKey;

  /// This device records voice (`recordsVoice`), for the empty page's hint.
  final bool speaks;

  /// Whether the cards go to smoke under the bar (the `wispEdge` preference).
  final bool wisp;

  @override
  State<AllNotesScreen> createState() => _AllNotesScreenState();
}

class _AllNotesScreenState extends State<AllNotesScreen> {
  final ScrollController _scroller = ScrollController();
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'Search your notes');
  late final GlideToTop _glide = GlideToTop(_scroller, onRoom: _redraw);
  late AllNotesSort _sort = readSort(widget.stored);
  late bool _tapes = widget.tapes;
  bool _archived = false;
  String _query = '';

  /// The workspace's sheet: shut, a new one, or one to change.
  ({Workspace? editing})? _manage;

  /// Where the pointer last went down on a card, for a menu a long press asks for.
  Offset _pressedAt = Offset.zero;

  /// The page under its bar, by a key of its own: a desktop's scrollbar is put round it as a different tree once
  /// the page is known to have more than it shows (lib/shell/desktop/desktop_scrollbar.dart), and without a key
  /// that follows it there every card and every preview was made from nothing a second time, the frame after the
  /// page opened and again each time a search took it under a screen and back.
  final GlobalKey _page = GlobalKey(debugLabel: 'all notes page');

  /// The least a row of cards can be tall: a card's padding and one line of its name.
  static const double _leastRow = 24;

  /// The room a desktop's scrollbar is about to take from the page, where it has not taken it yet: twelve pixels
  /// at the page's end, a frame after the page is first laid out with more than it shows. Laid out with that room
  /// already left, the cards are where they stay, and the frame after lays nothing out again (it was every card,
  /// a second time, three pixels narrower). Only where the cards are certain to be more than the page shows: a
  /// page that left the room and then had no scrollbar would stand twelve pixels short.
  double _scrollbarAhead(BoxConstraints box, int cards, double width, double window, Tokens t, double under) {
    if (!widget.wisp || !mousePointer || under <= 0 || cards == 0 || !box.hasBoundedHeight) return 0;
    // More than it shows already: the scrollbar has its room, and the page is given what is left.
    if (_scroller.hasClients && _scroller.position.hasContentDimensions && _scroller.position.maxScrollExtent > 0) return 0;
    final columns = NoteCards.columnsFor(width, window, gap: t.space(3), least: t.lenOf('12rem'));
    final rows = (cards + columns - 1) ~/ columns;
    return rows * _leastRow > box.maxHeight ? desktopScrollbarWidth : 0;
  }

  /// What the page worked out from its notes last ([_reading]).
  _Read? _read;

  /// The cards as they were made last, and what they were made from: built again with the same of it, the page
  /// hands back these, so no card is built again for a search field's caret or a pull's move, nor for a letter
  /// typed that leaves the same notes on the page.
  Widget? _cards;
  ({_Read read, double width, Tokens tokens, int minute, bool menu, int given})? _cardsFor;

  /// How many rows of other cards the page has been given so far: a row with the page and a row a frame after,
  /// for [_rowsAhead] frames, then all of them (0). Twenty-five cards near the screen, each a note drawn small,
  /// were made in the one frame the page opened in, or a letter was typed in (measured on a Mac: 47.7 ms and 23.6,
  /// where a frame has 16.7). Nothing is seen later than it was: a card waits 40 ms for each card before it, 320
  /// at the most, before it begins to arrive, and takes its arrival up from when it came to be on the page
  /// (lib/home/home_parts.dart `Arrive.since`), so a row made a frame late is made before it shows.
  int _rowsGiven = 0;
  bool _giving = false;
  static const int _rowsAhead = 10;

  /// The cards built while the rows are being given, by their place (and whether a card fills its row's cell): a
  /// row given a frame ago is handed back as it was built, and is not built again for the row that follows it.
  /// Let go a frame after the last row is given, so a card scrolled away and come back to is made as it is then.
  final Map<int, Widget> _cardAt = <int, Widget>{};
  bool _keeping = false;

  /// How many rows of other cards are given at once: every row down to the last that holds a card that was on the
  /// page before this frame, by the name its arrival is kept under (its note's where cards are one to a row, its
  /// place and its note's across a row); one row where no card was. The rows after are only now arriving, and are
  /// given a frame apart. Nothing (0, all of them at once) where a card that was there stands past the rows that
  /// would be given apart.
  int _rowsThere(List<Note> shown, int columns) {
    var last = -1;
    for (var i = shown.length - 1; i >= 0 && last < 0; i -= 1) {
      if (_arrivals.since(columns > 1 ? '$i/${shown[i].id}' : shown[i].id) > Duration.zero) last = i;
    }
    if (last < 0) return 1;
    final rows = last ~/ columns + 1;
    return rows >= _rowsAhead ? 0 : rows;
  }

  /// One more row a frame from now, or all of them once [_rowsAhead] have been given.
  void _giveMore() {
    if (_giving) return;
    _giving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _giving = false;
      if (!mounted || _rowsGiven == 0) return;
      setState(() => _rowsGiven = _rowsGiven >= _rowsAhead ? 0 : _rowsGiven + 1);
    });
  }

  /// The rows are all given: what was kept of them while they were is let go once this frame is drawn.
  void _letGo() {
    if (!_keeping) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_rowsGiven != 0) return;
      _keeping = false;
      _cardAt.clear();
    });
  }

  static bool _sameList(List<Note> a, List<Note> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// Whether two readings draw the same cards: the same notes shown, each in the same notebook and with the same
  /// journal's entries.
  static bool _sameCards(_Read a, _Read b) => identical(a, b) || (identical(a.shown, b.shown) && identical(a.inBooks, b.inBooks) && identical(a.journals, b.journals));

  /// When each card came to be on the page, for its entrance.
  final Arrivals _arrivals = Arrivals();

  /// What each note is about in a line, as handed over at the last build: read by each card for its own note. And
  /// when each line came to be there.
  final ValueNotifier<Map<String, String>> _gists = ValueNotifier<Map<String, String>>(const <String, String>{});
  final Arrivals _gistArrivals = Arrivals();

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_redraw);
    _focus.addListener(_redraw);
    _focus.addListener(_readAhead);
  }

  bool _readingAhead = false;

  /// What the search reads of each note ([searchText]) made as the field takes the keyboard, a millisecond and a
  /// half of it after each frame, so the first letter typed finds it made: it made every note's in its own frame
  /// (measured on a Mac over 354 notes: 7.9 ms, where a letter after it took 0.3).
  void _readAhead() {
    if (!_focus.hasFocus || _readingAhead) return;
    _readingAhead = true;
    var at = 0;
    void some(Duration _) {
      if (!mounted) return;
      final notes = widget.notes;
      final clock = Stopwatch()..start();
      while (at < notes.length && clock.elapsedMicroseconds < 1500) {
        searchText(notes[at]);
        at += 1;
      }
      if (at >= notes.length) {
        _readingAhead = false;
        return;
      }
      WidgetsBinding.instance
        ..addPostFrameCallback(some)
        ..scheduleFrame();
    }

    WidgetsBinding.instance.addPostFrameCallback(some);
  }

  @override
  void didUpdateWidget(AllNotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaces != widget.workspaces) {
      oldWidget.workspaces.removeListener(_redraw);
      widget.workspaces.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_redraw);
    _focus.removeListener(_redraw);
    _focus.removeListener(_readAhead);
    _glide.dispose();
    _scroller.dispose();
    _field.dispose();
    _focus.dispose();
    _gists.dispose();
    super.dispose();
  }

  // What a card calls, whoever handed the page its callbacks at the build the card was made in.
  void _open(String id) => widget.onOpen(id);

  /// What the page works out from its notes: which it shows and in what order, how many are archived or have a
  /// tape, every page's notebook and every journal's card. Made again only when the notes, the workspaces, the
  /// search or one of the page's own switches changed; whoever hands the page its notes may make a new list of the
  /// same notes at every build, so they are asked note by note ([sameNotes]).
  _Read _reading(Workspaces spaces) {
    final had = _read;
    final notes = widget.notes;
    if (had != null && identical(had.spaces, spaces) && had.query == _query && had.sort == _sort && had.archived == _archived && had.tapes == _tapes && sameNotes(had.notes, notes)) {
      return had;
    }
    if (ghostPerf) Perf.count('allnotes.read');
    final inSpace = widget.workspaces.inWorkspace(notes, spaces.current?.id, (note) => note.id);
    final began = ghostPerf ? Perf.now() : 0;
    var shown = browseNotes(inSpace, Browse(query: _query, sort: _sort, archived: _archived, tapes: _tapes));
    if (ghostPerf) Perf.add('allnotes.browse', began);
    // The same notes in the same order as were shown (a letter typed that every note shown still has): the list
    // there was, so the cards made for it are the cards.
    if (had != null && _sameList(had.shown, shown)) shown = had.shown;
    // A card one to a row is known by its note; across a row, by its place too (lib/home/note_card.dart
    // `SliverNoteCards`), and arrives again when that changes.
    _arrivals.keep([
      for (final (at, note) in shown.indexed) ...[note.id, '$at/${note.id}'],
    ]);
    return _read = _Read(
      // A list of the page's own: the one handed over may be changed after.
      notes: List<Note>.of(notes, growable: false),
      spaces: spaces,
      query: _query,
      sort: _sort,
      archived: _archived,
      tapes: _tapes,
      shown: shown,
      inArchive: archivedCount(inSpace),
      // How many notes have a tape, among the notes the page can show: the archive's count only while it is shown.
      withTape: tapeCount(_archived ? inSpace : inSpace.where((n) => n.archivedAt == null)),
      live: inSpace.where((n) => n.archivedAt == null).length,
      // Every page's book, for the cards' marks.
      inBooks: bookIndex(notes),
      journals: journalCards(notes),
    );
  }

  /// The grid of cards [width] wide, as a sliver that builds the rows near the screen.
  Widget _grid(_Read read, double width, double window, Tokens t, int? now) {
    final cards = _cards;
    final was = _cardsFor;
    final shown = read.shown;
    final minute = (now ?? DateTime.now().millisecondsSinceEpoch) ~/ 60000;
    final menu = widget.onNoteMenu != null;
    final columns = NoteCards.columnsFor(width, window, gap: t.space(3), least: t.lenOf('12rem'));
    // Other notes to show: the rows whose cards are only now arriving are given a frame apart (all but the first
    // as the page opens; after a letter typed, the rows under the last card that stayed where it stood). A card
    // that was on the page is given with the page: taken away, it would be gone for the frames before its row was
    // given again. Nor are rows given apart where nothing arrives but is simply there (reduced motion), nor to a
    // page that is scrolled down, which is as long as its rows and given a few would be back at its top.
    if (cards == null || was == null || !_sameCards(was.read, read)) {
      final down = _scroller.hasClients && _scroller.position.hasPixels && _scroller.position.pixels > 0;
      final there = down || t.reducedMotion ? 0 : _rowsThere(shown, columns);
      _cardAt.clear();
      _keeping = there != 0;
      _rowsGiven = there;
    }
    var given = _rowsGiven == 0 ? shown.length : math.min(shown.length, _rowsGiven * columns);
    if (given >= shown.length) {
      given = shown.length;
      _rowsGiven = 0;
      _letGo();
    } else {
      _giveMore();
    }
    final made = (read: read, width: width, tokens: t, minute: minute, menu: menu, given: given);
    final same = cards != null && was != null && _sameCards(was.read, made.read) && identical(was.tokens, made.tokens) && was.minute == made.minute && was.menu == made.menu;
    if (same && was.width == made.width && was.given == made.given) return cards;
    if (ghostPerf) {
      // Which of what the cards are made from was new.
      Perf.count('allnotes.cards');
      if (was != null) {
        if (!_sameCards(was.read, made.read)) Perf.count('allnotes.cards for the notes');
        if (was.width != made.width) Perf.count('allnotes.cards for the width');
        if (!identical(was.tokens, made.tokens)) Perf.count('allnotes.cards for the tokens');
        if (was.minute != made.minute) Perf.count('allnotes.cards for the minute');
      }
    }
    _cardsFor = made;
    Widget build(int i, bool fill) {
      if (ghostPerf) Perf.count('allnotes.card');
      final note = shown[i];
      Widget card(String? gist) => NoteCard(
            key: ValueKey('card-${note.id}'),
            note: note,
            index: i,
            onOpen: _open,
            now: now,
            gist: gist,
            place: placeOf(read.inBooks, note),
            entries: read.journals[note.id],
            dense: true,
            fill: fill,
            onMenu: made.menu ? (_) => widget.onNoteMenu?.call(note, _pressedAt) : null,
            since: _arrivals.since(fill ? '$i/${note.id}' : note.id),
            gistSince: _gistArrivals.since(note.id),
          );
      // The first screens of cards say what each note is about: each reads its own line.
      final Widget drawn = i < allNotesGisted ? Gisted(gists: _gists, id: note.id, builder: (context, gist) => card(gist)) : card(null);
      if (!made.menu) return drawn;
      // The right-click a card answers: the note's menu at the pointer (notes/noteMenu.ts).
      return Listener(
        onPointerDown: (event) {
          _pressedAt = event.position;
          if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) widget.onNoteMenu?.call(note, event.position);
        },
        child: drawn,
      );
    }

    return _cards = SliverSemantics(
      container: true,
      label: 'Notes',
      sliver: SliverNoteCards(
        count: given,
        width: width,
        windowWidth: window,
        idOf: (i) => shown[i].id,
        itemBuilder: (context, i, fill) => _keeping ? (_cardAt[fill ? i : -1 - i] ??= build(i, fill)) : build(i, fill),
      ),
    );
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _setSort(AllNotesSort sort) {
    // The order chosen is kept for next time.
    writeSort(sort, widget.stored);
    setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('allnotes.build');
    final t = context.tokens;
    final spaces = widget.workspaces.value;
    final workspace = spaces.current?.id;
    final read = _reading(spaces);
    final shown = read.shown;
    final inArchive = read.inArchive;
    final withTape = read.withTape;
    final live = read.live;
    final searched = _query.trim().isNotEmpty;
    // What a search is counted out of: the tapes when only they are shown, else the notes, and the archive with them.
    final outOf = _tapes ? withTape : live + (_archived ? inArchive : 0);
    final now = widget.clock?.call();
    if (!identical(_gists.value, widget.gists) && !mapEquals(_gists.value, widget.gists)) {
      _gistArrivals.keep(widget.gists.keys);
      _gists.value = widget.gists;
    }

    // The bar: `padding-block: calc(var(--app-safe-top) + var(--glacier-space-2)) var(--glacier-space-2)` round a
    // search as tall as its field (`min-block-size: var(--glacier-space-8)`) and its hairlines.
    final safeTop = t.len('app-safe-top');
    final hairline = t.len('glacier-hairline');
    final bar = safeTop + t.space(2) * 2 + t.space(8) + hairline * 2;
    // art/wispEdge.ts writes the bar's height into `--wisp-under` as a whole pixel, the nearest (measured: a bar of
    // 101.97 pads the page by 102, and one of 124.34 by 124).
    final under = bar.roundToDouble();
    // `padding-block-start: calc(max(var(--wisp-under, 0px), var(--app-safe-top)) + var(--glacier-space-4))`
    final top = math.max(under, safeTop) + t.space(4);
    // Another workspace, order, archive or tapes chosen: the page glides back to its top rather than jumping there.
    final room = _glide.keyed('${workspace ?? 'all'}|${_sort.id}|${_archived ? 'archive' : ''}|${_tapes ? 'tapes' : ''}', still: t.reducedMotion);
    // `padding-block-end: calc(var(--app-safe-bottom) + var(--glacier-space-10))`
    final foot = t.len('app-safe-bottom') + t.space(10) + room;
    final hasSpaces = spaces.list.isNotEmpty;
    final window = MediaQuery.sizeOf(context).width;
    // `padding-inline: var(--app-gutter-start) var(--app-gutter-end)`
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');

    Widget page(PullDown? pull) {
      final Widget scroller = ScrollConfiguration(
        key: _page,
        // `overscroll-behavior: contain`: the page stops at its ends, with no glow and no stretch of the platform's.
        behavior: const _Still(),
        child: LayoutBuilder(
          builder: (context, box) {
            // What a desktop's scrollbar will take a frame from now, left for it now.
            final ahead = _scrollbarAhead(box, shown.length, math.max(0.0, box.maxWidth - desktopScrollbarWidth - gutterStart - gutterEnd), window, t, under);
            // The page's own column, inside its gutters.
            final inner = math.max(0.0, box.maxWidth - ahead - gutterStart - gutterEnd);
            // `@container all-notes (min-width: 44rem)`.
            final wide = inner >= t.lenOf('44rem');
            // What stands over the cards: the workspaces, the order words, and the empty page's ghost.
            final head = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSpaces) ...[
                  WorkspaceBar(
                    store: widget.workspaces,
                    onManage: (which) => setState(() => _manage = (editing: which)),
                    onOrganization: widget.onOrganization,
                  ),
                  // The row's margin under it and the line's above it collapse into the larger, the row's.
                  SizedBox(height: math.max(WorkspaceBar.marginBelow(t), t.space(3))),
                ] else
                  // `.controls { margin-block: var(--glacier-space-3) var(--glacier-space-3) }`
                  SizedBox(height: t.space(3)),
                // The order, the tapes, and the archive: one line of words over the cards.
                _Controls(
                  key: const ValueKey('all-notes-controls'),
                  columnGap: t.space(3),
                  rowGap: t.space(1),
                  children: [
                    Semantics(
                      container: true,
                      label: 'Order',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        // `.sorts { display: inline-flex; gap: var(--glacier-space-1) }`
                        spacing: t.space(1),
                        children: [
                          for (final each in sorts) _Word(key: ValueKey('sort-${each.id}'), label: each.label, on: _sort == each, radio: true, onPressed: () => _setSort(each)),
                        ],
                      ),
                    ),
                    // Only the notes with a tape, in the archive toggle's shape; not offered while there are none.
                    if (withTape > 0) _Word(key: const ValueKey('tapes-word'), label: 'Tapes · $withTape', icon: AppIcons.cassette, on: _tapes, onPressed: () => setState(() => _tapes = !_tapes)),
                    // How many, and the archive's word: one group taking the rest of the line, so on a phone the two
                    // wrap together.
                    Row(
                      key: const ValueKey('all-notes-counts'),
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      spacing: t.space(3),
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            searched ? '${shown.length} of $outOf' : (shown.length == 1 ? '1 note' : '${shown.length} notes'),
                            key: const ValueKey('all-notes-tally'),
                            maxLines: 1,
                            softWrap: false,
                            // `.tally { font-variant-numeric: tabular-nums; color: var(--app-ink-3) }`
                            style: tabular(pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
                          ),
                        ),
                        if (inArchive > 0) _Word(key: const ValueKey('archive-word'), label: 'Archived · $inArchive', icon: AppIcons.archiveBox, on: _archived, onPressed: () => setState(() => _archived = !_archived)),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: t.space(3)),
                if (!widget.loading && !searched && live == 0 && !_archived)
                  _Empty(
                    scene: spaces.current != null ? GhostScene.emptyWorkspace : GhostScene.noNotes,
                    lead: spaces.current != null ? 'Nothing in ${spaces.current!.name} yet.' : 'A blank page.',
                    hint: widget.sideKey ? 'Write it, or hold the side key and say it.' : (widget.speaks ? 'Write it, or tap Speak and say it.' : 'Tap + to write it.'),
                    wide: wide,
                  )
                else if (searched && shown.isEmpty)
                  _Empty(
                    scene: GhostScene.searchNothing,
                    lead: 'Nothing has “${_query.trim()}”.',
                    hint: _archived || inArchive == 0 ? 'Try fewer words.' : 'Try fewer words, or look in the archive.',
                    wide: wide,
                  ),
              ],
            );
            return PageScroll(
              key: const ValueKey('all-notes-scroll'),
              controller: _scroller,
              pull: pull,
              slivers: [
                SliverPadding(padding: EdgeInsetsDirectional.fromSTEB(gutterStart, top, gutterEnd + ahead, shown.isEmpty ? foot : 0), sliver: SliverToBoxAdapter(child: head)),
                // The cards: only the rows of them near the screen are built.
                if (shown.isNotEmpty) SliverPadding(padding: EdgeInsetsDirectional.fromSTEB(gutterStart, 0, gutterEnd + ahead, foot), sliver: _grid(read, inner, window, t, now)),
              ],
            );
          },
        ),
      );
      // `useWispEdge(scroller, 'all-notes', topBar)`: smoke under the bar, and no foot.
      return widget.wisp ? WispEdge(under: under, child: scroller) : scroller;
    }

    final onRefresh = widget.onRefresh;
    final manage = _manage;
    return ColoredBox(
      // `.screen { background: var(--glacier-bg) }`
      color: t.color('glacier-bg'),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(child: onRefresh == null ? page(null) : PullToRefresh(controller: _scroller, onRefresh: onRefresh, top: top, builder: (context, pull) => page(pull))),
            // The bar: the arrow home, the page's name for a screen reader, and the search taking the rest of the line.
            HeaderPane(
              child: Padding(
                key: const ValueKey('all-notes-bar'),
                // `padding-inline: var(--app-gutter-start) var(--app-gutter-end)`, the arrow pulled out by
                // `margin-inline-start: calc(-1 * var(--glacier-space-2))`.
                padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start') - t.space(2), t.space(2), t.len('app-gutter-end'), t.space(2)),
                child: Row(
                  // `display: flex; align-items: center; gap: var(--glacier-space-2)`
                  spacing: t.space(2),
                  children: [
                    GlacierPressable(
                      key: const ValueKey('all-notes-back'),
                      onPressed: widget.onBack,
                      semanticLabel: 'Back to home',
                      builder: (context, state) => GlacierFocusRing(
                        visible: state.focused,
                        child: SizedBox.square(
                          // `inline-size: var(--glacier-space-8); block-size: var(--glacier-space-8)`
                          dimension: t.space(8),
                          child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink'))),
                        ),
                      ),
                    ),
                    // The search, the page's main tool, in the bar where it stays as the cards scroll under it.
                    Expanded(
                      // The page's name rides on the search's box, out of the row's flow as the page's `h1` is.
                      child: Stack(
                        children: [
                          const Positioned(left: 0, top: 0, child: _SaidOnly('All notes')),
                          _Search(
                            controller: _field,
                            focusNode: _focus,
                            onQuery: (words) => setState(() => _query = words),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (manage != null)
              WorkspaceManageSheet(
                store: widget.workspaces,
                editing: manage.editing,
                onClose: () => setState(() => _manage = null),
                onOrganization: widget.onOrganizationSettings ?? widget.onOrganization,
                notesIn: widget.notesInWorkspace,
                onTrashNotes: widget.onTrashNotes,
              ),
          ],
        ),
      ),
    );
  }
}

/// What the page works out from its notes ([_AllNotesScreenState._reading]), and what it was worked out from.
class _Read {
  _Read({
    required this.notes,
    required this.spaces,
    required this.query,
    required this.sort,
    required this.archived,
    required this.tapes,
    required this.shown,
    required this.inArchive,
    required this.withTape,
    required this.live,
    required this.inBooks,
    required this.journals,
  });

  final List<Note> notes;
  final Workspaces spaces;
  final String query;
  final AllNotesSort sort;
  final bool archived;
  final bool tapes;

  final List<Note> shown;
  final int inArchive;
  final int withTape;
  final int live;
  final Map<String, BookPlace> inBooks;
  final Map<String, JournalCard> journals;
}

/// The platform's overscroll glow and stretch left off, and no scrollbar of its own.
class _Still extends GhostScrollBehavior {
  const _Still();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// `.saidOnly` (app.css `.app-unseen`): the page's name for a screen reader alone, taking no room in the bar's row.
class _SaidOnly extends StatelessWidget {
  const _SaidOnly(this.words);
  final String words;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 0,
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

/// `.search`: a pill of the faint ink wash with the glass mark at its start, the field through the middle and, once
/// there are words, an x to clear them. And `.field`, `.searchMark` and `.clear`.
class _Search extends StatefulWidget {
  const _Search({required this.controller, required this.focusNode, required this.onQuery});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onQuery;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> implements TextSelectionGestureDetectorBuilderDelegate {
  late final TextSelectionGestureDetectorBuilder _gestures = TextSelectionGestureDetectorBuilder(delegate: this);
  bool _handles = false;

  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final focused = widget.focusNode.hasFocus;
    // `.field { font-size: var(--glacier-font-size-md); color: var(--app-ink) }`
    final md = t.fontSize('md');
    final style = pageText(t, md, color: t.color('app-ink'));
    const words = 'Search your notes';
    // `data-filled`: the x is there once there are words that are not blank.
    final filled = widget.controller.text.trim().isNotEmpty;
    final empty = widget.controller.text.isEmpty;
    // `.search { color: var(--app-ink-3) }`, `.search:focus-within { color: var(--app-ink-2) }`: the mark's colour.
    final quiet = focused ? t.color('app-ink-2') : t.color('app-ink-3');
    final hairline = t.len('glacier-hairline');

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
      // `enterKeyHint="search"`, and no correcting, capitals or spell check of the keyboard's.
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      textCapitalization: TextCapitalization.none,
      onChanged: (text) {
        widget.onQuery(text);
        setState(() {});
      },
      onSelectionChanged: (selection, cause) {
        // Handles are a finger's: none for a selection the keyboard or the program made.
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
          key: const ValueKey('all-notes-search'),
          // `padding-inline: var(--glacier-space-3) var(--glacier-space-1)`
          padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(1)),
          decoration: BoxDecoration(
            // `background: color-mix(in oklch, var(--app-ink) 4%, transparent)`
            color: t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)'),
            // `border: var(--glacier-hairline) solid var(--glacier-border-subtle)`; focused, `--glacier-border-strong`.
            border: Border.all(color: focused ? t.color('glacier-border-strong') : t.color('glacier-border-subtle'), width: hairline),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Row(
            // `display: flex; align-items: center; gap: var(--glacier-space-2)`
            spacing: t.space(2),
            children: [
              // `<Search size={16} strokeWidth={2.2} />`
              AppIcon(Lucide.search, key: const ValueKey('all-notes-search-mark'), size: 16, strokeWidth: 2.2, color: quiet),
              Expanded(
                child: _gestures.buildGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.text,
                    child: ConstrainedBox(
                      key: const ValueKey('all-notes-field'),
                      // `.field { min-block-size: var(--glacier-space-8) }`
                      constraints: BoxConstraints(minHeight: t.space(8)),
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [
                          // `.field::placeholder { color: var(--app-ink-3) }`
                          if (empty) ExcludeSemantics(child: Text(words, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('app-ink-3')))),
                          DefaultTextEditingShortcuts(child: editable),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (filled)
                GlacierPressable(
                  key: const ValueKey('all-notes-clear'),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onQuery('');
                    widget.focusNode.requestFocus();
                    setState(() {});
                  },
                  semanticLabel: 'Clear the search',
                  builder: (context, state) => GlacierFocusRing(
                    visible: state.focused,
                    child: DecoratedBox(
                      // The glyph's own size, on `color-mix(in oklch, var(--app-ink) 8%, transparent)`, round.
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                      // `<X size={14} strokeWidth={2.4} />`, in `color: var(--app-ink-2)`.
                      child: AppIcon(Lucide.x, size: 14, strokeWidth: 2.4, color: t.color('app-ink-2')),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.sortWord`, `.tapesWord`, `.archiveWord`: a pill of nothing until chosen, then the ink wash with the ink's own
/// colour. An order word is a radio; Tapes and Archived are toggles, each with its mark a touch over the word's size.
class _Word extends StatelessWidget {
  const _Word({super.key, required this.label, this.icon, required this.on, this.radio = false, required this.onPressed});

  final String label;
  final DrawnIcon? icon;
  final bool on;
  final bool radio;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    // `.controls { color: var(--app-ink-2) }`, inherited; chosen, `color: var(--app-ink)`.
    final color = on ? t.color('app-ink') : t.color('app-ink-2');
    return GlacierPressable(
      onPressed: onPressed,
      toggled: radio ? null : on,
      selected: radio ? on : null,
      haptic: HapticKind.selection,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          // `padding-inline: var(--glacier-space-3)`, and the button's own pixel above and below.
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: _buttonPadBlock),
          decoration: BoxDecoration(
            // Chosen: `background: color-mix(in oklch, var(--app-ink) 6%, transparent)`.
            color: on ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null,
            // `border: var(--glacier-hairline) solid transparent`; chosen, `--glacier-border-subtle`.
            border: Border.all(color: on ? t.color('glacier-border-subtle') : const Color(0x00000000), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            // `display: inline-flex; align-items: center; gap: 0.35em`
            spacing: 0.35 * sm,
            children: [
              // `.tapesMark, .archiveMark { font-size: 1.05em }`
              if (icon != null) DrawnIconView(icon!, size: 1.05 * sm, color: color),
              // `font-size: sm; font-weight: medium; white-space: nowrap`
              Text(label, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.controls`: `display: flex; flex-wrap: wrap; align-items: center; gap: <rowGap> <columnGap>`, whose last child
/// (`.counts`, `flex: 1 1 auto`) takes the rest of its line. The line no longer fits a phone held upright with the
/// Tapes word beside the order words, so it wraps: the order words and Tapes on one line, the tally and Archived
/// together on the next.
class _Controls extends MultiChildRenderObjectWidget {
  const _Controls({super.key, required this.columnGap, required this.rowGap, super.children});

  final double columnGap;
  final double rowGap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderControls(columnGap, rowGap);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderControls)
      ..columnGap = columnGap
      ..rowGap = rowGap;
  }
}

class _ControlsData extends ContainerBoxParentData<RenderBox> {}

class _RenderControls extends RenderBox with ContainerRenderObjectMixin<RenderBox, _ControlsData>, RenderBoxContainerDefaultsMixin<RenderBox, _ControlsData> {
  _RenderControls(this._columnGap, this._rowGap);

  double _columnGap;
  set columnGap(double value) {
    if (value == _columnGap) return;
    _columnGap = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) return;
    _rowGap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ControlsData) child.parentData = _ControlsData();
  }

  /// The children in lines, as `flex-wrap` breaks them: each at its own width, a new line where the next does not fit.
  List<List<RenderBox>> _lines(double width, List<double> widths) {
    final lines = <List<RenderBox>>[];
    var used = 0.0, i = 0;
    for (var child = firstChild; child != null; child = childAfter(child), i += 1) {
      final w = widths[i];
      if (lines.isEmpty || used + _columnGap + w > width + 0.01) {
        lines.add([child]);
        used = w;
      } else {
        lines.last.add(child);
        used += _columnGap + w;
      }
    }
    return lines;
  }

  List<double> get _widths => [for (var child = firstChild; child != null; child = childAfter(child)) child.getMaxIntrinsicWidth(double.infinity)];

  @override
  double computeMinIntrinsicWidth(double height) => _widths.fold(0, math.max);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final widths = _widths;
    return widths.fold<double>(widths.isEmpty ? 0 : _columnGap * (widths.length - 1), (sum, w) => sum + w);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _heightAt(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightAt(width);

  double _heightAt(double width) {
    final lines = _lines(width, _widths);
    var height = lines.isEmpty ? 0.0 : _rowGap * (lines.length - 1);
    for (final line in lines) {
      height += line.fold<double>(0, (tallest, child) => math.max(tallest, child.getMaxIntrinsicHeight(double.infinity)));
    }
    return height;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final widths = _widths;
    final lines = _lines(width, widths);
    var y = 0.0;
    for (final line in lines) {
      var used = 0.0;
      for (final child in line) {
        final grows = child == lastChild;
        if (grows) {
          // `flex: 1 1 auto`: the rest of the line.
          final rest = math.max(0.0, width - used);
          child.layout(BoxConstraints.tightFor(width: rest), parentUsesSize: true);
        } else {
          child.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
        }
        used += child.size.width + _columnGap;
      }
      final tall = line.fold<double>(0, (tallest, child) => math.max(tallest, child.size.height));
      var x = 0.0;
      for (final child in line) {
        (child.parentData! as _ControlsData).offset = Offset(x, y + (tall - child.size.height) / 2);
        x += child.size.width + _columnGap;
      }
      y += tall + _rowGap;
    }
    size = constraints.constrain(Size(width, lines.isEmpty ? 0 : y - _rowGap));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// `.empty`: the empty page, and the search that found nothing: the ghost and a line, as on the home page. Stacked
/// on a phone; from 44rem of column the ghost stands beside its words, three fifths to two
/// (`grid-template-columns: minmax(0, 3fr) minmax(0, 2fr)`), the words in the middle of its height.
class _Empty extends StatelessWidget {
  const _Empty({required this.scene, required this.lead, required this.hint, required this.wide});

  final GhostScene scene;
  final String lead;
  final String hint;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('3xl'), md = t.fontSize('md');
    // `.emptyLead`: 3xl, semibold, the title's tracking, in the subtle text.
    final leadLine = t.len('glacier-leading-3xl');
    final leadWords = CssLines(
      lineHeight: leadLine * size,
      child: Text(lead, style: pageText(t, size, weight: 'semibold', color: t.color('glacier-text-subtle'), height: leadLine, tracking: t.len('app-tracking-title', em: size))),
    );
    // `.emptyHint`: md, in the muted text, `max-inline-size: 28ch`: twenty-eight of the face's own noughts.
    final hintLine = t.len('glacier-leading-md');
    final hintStyle = pageText(t, md, color: t.color('glacier-text-muted'), height: hintLine);
    final nought = TextPainter(text: TextSpan(text: '0', style: hintStyle), textDirection: TextDirection.ltr)..layout();
    final hintWords = ConstrainedBox(constraints: BoxConstraints(maxWidth: 28 * nought.width), child: CssLines(lineHeight: hintLine * md, child: Text(hint, style: hintStyle)));
    nought.dispose();
    final words = [leadWords, SizedBox(height: t.space(3)), Align(alignment: AlignmentDirectional.centerStart, child: hintWords)];
    return Padding(
      key: const ValueKey('all-notes-empty'),
      // `.empty { padding-block: var(--glacier-space-6) var(--glacier-space-8) }`
      padding: EdgeInsets.only(top: t.space(6), bottom: t.space(8)),
      child: LayoutBuilder(
        builder: (context, box) {
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Stacked over its words the ghost leaves them room: `min(100%, 36rem, calc(38dvh * ratio))`.
                Ghost(key: const ValueKey('all-notes-ghost'), scene: scene, size: GhostSize.lead, heightShare: 0.38),
                // `.emptyArt { margin-block-end: var(--glacier-space-5) }`
                SizedBox(height: t.space(5)),
                ...words,
              ],
            );
          }
          // `column-gap: var(--glacier-space-6)`
          final gap = t.space(6);
          final first = (box.maxWidth - gap) * 3 / 5;
          // Beside its words: `inline-size: min(100%, 36rem, calc(45dvh * ratio))`.
          final artWidth = Ghost.widthFor(scene, GhostSize.lead, available: first, windowHeight: MediaQuery.sizeOf(context).height, rem: t.lenOf('1rem'));
          final artHeight = artWidth / scene.ratio;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: first, child: Ghost(key: const ValueKey('all-notes-ghost'), scene: scene, size: GhostSize.lead)),
              SizedBox(width: gap),
              // The lead against the foot of its row and the hint against the head of its own, in rows the ghost's
              // height is shared between: the words stand in the middle of the ghost's height.
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: artHeight),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: words),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
