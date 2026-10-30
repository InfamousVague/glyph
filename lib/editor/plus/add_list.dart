/// The + beside the line's list (insert_plus.dart is the +, add_rows.dart what the rows are and write). A port of
/// `src/app/editor/AddList.tsx` with `AddList.module.css`.
///
/// A short card against the +'s own row, never over it: below the row, or above it when the keyboard leaves no room
/// below, or on the larger side, scrolling, when neither holds it all. Above, it may cover the header and the tabs,
/// as far as the status bar (Matt: "Allow the header to be overlapped by the popup menus"). Its left edge is the
/// text's. On the opened Fold it keeps to one side of the crease, the window's middle: at the text when it fits
/// before the crease, past the crease when it does not, and across it only when neither side has room
/// ([placeList]).
///
/// It is not a sheet, which would take the page and the keyboard with it, and not the sideways band of press and
/// hold. It is the list the + promised: the things reached for and More, which turns the list over to the rest in
/// the same card, with Back at its top (Matt: "Fuller but hide extras behind nested menu"). More and Back are the
/// doors between the pages, so neither ever scrolls: the rows between the doors scroll under a fade while the doors
/// stay put.
///
/// **Focus.** Pressed with a finger or a mouse, the list never takes the focus: the editor keeps it, with its
/// caret and the keyboard, and the list is driven from the editor's keys (Up and Down move the lit row, Enter
/// chooses it, Escape closes, Left goes back, Right goes into More). Opened from the keyboard on the + itself, the
/// focus comes into the list. A step that asks which note to link to, and the `/` palette's filter, are the places
/// the list takes the focus on purpose, for its field.
///
/// The lit row wears the kit's ring only once a key has moved it; lit by the pointer, or first as the list opens,
/// it has the pressed paper and no ring, which would otherwise follow the mouse about.
///
/// **Closing.** A row chosen closes the list first and then does what it says. So do a press anywhere else, a wheel
/// outside it, Escape, the back gesture, the × pressed again, any other key, and any change or caret move in the
/// note. A scroll does not: the keyboard rising shortens the page and the editor scrolls the caret into view, so
/// the list follows the + instead, and closes only once the + has left the screen. On More or a step, the back
/// gesture goes back a page, as Back and Left do.
///
/// What differs:
/// - **What the screen hands it is one object** ([AddConfig]): the web's `onPicture`, `onPlace`, `onVideo`,
///   `titles`, `canvases` and `own`, and beside them what the web read from elsewhere or always had: Local only
///   (`preferences().localOnly`), the effects (the plugin registry), and whether the rows whose blocks later stages
///   draw are offered yet ([AddConfig.boards], [AddConfig.databases], [AddConfig.tickets], [AddConfig.blanks]). A
///   row with no callback, or not offered, is left out, in the web's order.
/// - **It draws itself in the app's root overlay**, where the page's was `position: fixed`; mounted anywhere, it is
///   placed in the window.
/// - **It is placed while it is laid out** ([RenderAddCard]) where the page measured its own boxes after React had
///   drawn them, so a page turned is never drawn a frame at the wrong height. The page's sums are kept, its whole
///   pixels included (`offsetHeight` and `scrollHeight` are whole numbers), so the card lands where the page's
///   does: see [RenderAddCard.performLayout].
/// - **The +'s box is asked for after each frame the app draws**, where the page listened for scroll and resize.
/// - **With the focus in the list (opened from the + by the keyboard) the list is one focus stop**, and its row is
///   ringed and chosen with Enter or Space, where each of the page's rows was a `<button>` with a roving tab stop.
/// - **A press outside is heard on the pointer router**; a drag outside (`touchmove`) begins with that press, so it
///   has no listener of its own.
/// - The lit row is not announced through the editor (`aria-activedescendant`): [plusMenuOf] keeps it.
/// - The time is this file's `stamp` (add_rows.dart), English and day first.
/// - A row's `:hover` paper is for a mouse (`coarse` false); the kit's press dip is not on a row, as on the page.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/page_scroll.dart';
import '../../art/app_icon.dart';
import '../../art/icons.dart';
import '../../art/lucide.g.dart';
import '../../core/back.dart';
import '../../core/book.dart';
import '../../core/canvas_body.dart';
import '../../core/properties.dart';
import '../../shell/pop_menu.dart' show coarsePointer;
import '../editor.dart';
import 'add_rows.dart';
import 'insert_plus.dart';

/// The list's id, as the editor is told it ([PlusMenu.list]).
const String addListId = 'add-list';

/// How far the list sits from the +'s row, above or below it.
const double _gap = 6;

/// How near the list comes to the screen's edges and to the crease.
const double _edge = 8;
const double _creaseGap = 16;

/// The opened Fold: a finger on a window this wide (`(pointer: coarse) and (min-width: 600px)`).
const double _openedFold = 600;

final RegExp _notIdLetter = RegExp('[^a-z0-9-]', caseSensitive: false);

/// A row's id in the list, as the editor is told it.
String addRowId(String id) => 'add-${id.replaceAll(_notIdLetter, '-')}';

/// Where the editor's keys reach the list while the editor keeps the focus (the web's `keys` ref): the list sets
/// [current] while it is up, and the +'s `onKey` hook calls it.
class AddListKeys {
  bool Function(PlusKey key)? current;
}

/// What the screen itself can put in, beyond what every note can hold: absent, the row is not there.
class AddConfig {
  const AddConfig({
    this.onPicture,
    this.onPlace,
    this.onVideo,
    this.onFile,
    this.onScan,
    this.titles,
    this.canvases,
    this.own = '',
    this.localOnly = false,
    this.effects = const <PlusEffect>[],
    this.inserts = const <PlusInsert>[],
    this.boards = false,
    this.databases = false,
    this.tickets = false,
    this.blanks = false,
    this.onPerson,
    this.simple = false,
    this.toggles = false,
  });

  /// A picture: the screen opens its picker.
  final VoidCallback? onPicture;

  /// A place: the screen asks where the phone is and writes its line.
  final VoidCallback? onPlace;

  /// A video, where this build adds films.
  final VoidCallback? onVideo;

  /// A file: the screen opens the device's file picker. A scan: the screen opens the document scanner.
  final VoidCallback? onFile;
  final VoidCallback? onScan;

  /// Every note's title, for A note; absent where notes cannot be opened.
  final List<String> Function()? titles;

  /// Every canvas's title, for A canvas; absent where a canvas cannot be framed.
  final List<String> Function()? canvases;

  /// This note's own title, which it does not link to.
  final String own;

  /// The person's Local only: a place is drawn dimmed, with the reason under it.
  final bool localOnly;

  /// The effects that are on, each a row at More's end (the marks' piece hands them over).
  final List<PlusEffect> effects;

  /// What the switched-on plugins put in a line, each a row at More's end with the plugin's mark ([PlusInsert]).
  final List<PlusInsert> inserts;

  /// Whether a board, a database, Make this a ticket and a blank for the AI are offered: each is on once the editor
  /// draws what the row writes (stages 5 and 8).
  final bool boards;
  final bool databases;
  final bool tickets;
  final bool blanks;

  /// A person: the screen opens the contacts to pick from and writes the one picked ([writePerson]); absent where
  /// Settings › Contacts is off.
  final VoidCallback? onPerson;

  /// Simple mode (`Preferences.simple`, GHST-103): the basics on the first page with a line each, the rest behind
  /// More (add_rows.dart `simpleTopRows`). Read as the list opens, with the other gates.
  final bool simple;

  /// Whether A toggle is offered: once the editor draws `<details>` as one (lib/editor/view/section_folds.dart).
  final bool toggles;
}

/// Where the card goes ([placeList]): its corner, its width, and how tall its scrolling rows may be (null for as
/// tall as they are).
class ListPlace {
  const ListPlace({required this.x, required this.y, required this.width, this.cap});

  final double x;
  final double y;
  final double width;
  final double? cap;

  @override
  bool operator ==(Object other) => other is ListPlace && other.x == x && other.y == y && other.width == width && other.cap == cap;

  @override
  int get hashCode => Object.hash(x, y, width, cap);

  @override
  String toString() => 'ListPlace($x, $y, $width wide, cap $cap)';
}

/// Against the +'s row: below it, above it, or on the larger side; beside the text, and clear of the crease
/// (`place`). Null once the + has scrolled out of sight: the list has nothing to be beside, and closes.
///
/// `row` is the +'s box, `viewTop` and `viewBottom` what the keyboard leaves of the window, `statusBar` the
/// phone's inset. `natural` is the card's whole height and `chrome` what of it is not the rows that scroll.
/// `rowHeight` is one row's, `full` the card's own width, `window` the window's. `opened` is the opened Fold;
/// `paneRight` the right edge of the note's pane.
ListPlace? placeList({
  required Rect row,
  required double viewTop,
  required double viewBottom,
  double statusBar = 0,
  required double natural,
  required double chrome,
  double rowHeight = 44,
  required double full,
  required double window,
  bool opened = false,
  double? paneRight,
  double rem = 16,
}) {
  // The + scrolled out of sight. (A + with no box has not been laid out yet.)
  if (row.height > 0 && (row.bottom <= viewTop || row.top >= viewBottom)) return null;
  // Over the header and the tabs if it must, never under the status bar.
  final top = math.max(viewTop, statusBar) + _edge;
  final bottom = viewBottom - _edge;
  final least = rowHeight * 3 + 8;
  final below = bottom - (row.bottom + _gap);
  final above = row.top - _gap - top;
  double y;
  var height = natural;
  if (natural <= below) {
    y = row.bottom + _gap;
  } else if (natural <= above) {
    y = row.top - _gap - natural;
  } else if (below >= above) {
    height = math.max(below, least);
    y = row.bottom + _gap;
  } else {
    height = math.max(above, least);
    y = row.top - _gap - height;
  }
  final cap = height < natural ? math.max(0.0, height - chrome) : null;

  // Across: the text's left edge, and on a folding phone opened out, one side of the crease.
  final text = row.right;
  var x = text;
  var width = full;
  if (opened) {
    final crease = window / 2;
    final before = crease - _creaseGap - text;
    final right = (paneRight ?? window) - row.width;
    final past = right - (crease + _creaseGap);
    if (text < crease && before < full) {
      if (before >= 12 * rem) {
        width = before;
      } else if (past >= 12 * rem) {
        x = crease + _creaseGap;
        width = math.min(full, past);
      }
    }
  }
  x = math.max(_edge, math.min(x, window - width - _edge));
  return ListPlace(x: x, y: y, width: width, cap: cap);
}

/// The palette's rows that match what is typed, by their words or their read-aloud label; all of them when nothing
/// is.
List<AddRow> filterRows(List<AddRow> rows, String looking) {
  final q = looking.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((row) => row.words.toLowerCase().contains(q) || (row.label?.toLowerCase().contains(q) ?? false)).toList();
}

/// Whether the note can be made a ticket: not one already, and not a notebook or a canvas, whose front matter is
/// theirs.
bool madeTicket(String body) => !isTicket(body) && !isBookBody(body) && !isCanvasBody(body);

enum _Page { top, all, more, board, database, note, canvas }

enum _Turn { forward, back }

const Map<String, LucideIcon> _icons = <String, LucideIcon>{
  'picture': Lucide.imagePlus,
  'video': Lucide.film,
  'file': Lucide.filePlus,
  'scan': Lucide.scanText,
  'time': Lucide.clock,
  'table': Lucide.table,
  'note': Lucide.fileText,
  'person': Lucide.contactRound,
  'todo': Lucide.listTodo,
  'link': Lucide.link,
  'more': Lucide.ellipsis,
  'heading': Lucide.heading,
  'bullets': Lucide.list,
  'numbers': Lucide.listOrdered,
  'quote': Lucide.textQuote,
  'callout': Lucide.info,
  'toggle': Lucide.chevronsDownUp,
  'choice': Lucide.circleDot,
  'code': Lucide.squareCode,
  'divider': Lucide.minus,
  'board': Lucide.squareKanban,
  'query': Lucide.database,
  'dated': Lucide.calendarPlus,
  'ticket': Lucide.ticket,
  'chart': Lucide.network,
  'formula': Lucide.squareRadical,
  'canvas': Lucide.workflow,
  'footnote': Lucide.asterisk,
  'tag': Lucide.hash,
  'counter': Lucide.gauge,
  'sum': Lucide.calculator,
  'blank': Lucide.squareDashed,
  'blankCells': Lucide.grid2x2Plus,
};

/// Each ready-made database's mark, by what it lists and how it is shown (query_templates.dart).
const Map<String, LucideIcon> _databaseIcons = <String, LucideIcon>{
  'week': Lucide.listTodo,
  'late': Lucide.alarmClock,
  'people': Lucide.users,
  'month': Lucide.calendarDays,
  'board': Lucide.squareKanban,
  'tickets': Lucide.table,
  'timeline': Lucide.chartGantt,
  'recent': Lucide.history,
  'count': Lucide.sigma,
  'own': Lucide.pencilLine,
};

/// A row as it is drawn: a row of the list, or Back.
class _Shown {
  const _Shown(this.id, this.words, {this.row});
  const _Shown.back() : id = 'back', words = 'Back', row = null;

  final String id;
  final String words;
  final AddRow? row;

  bool get isBack => row == null;
  bool get onward => row?.step == AddStep.more || row?.step == AddStep.board || row?.step == AddStep.database;
}

/// The + beside the line's list. It is up for as long as it is in the tree: its owner mounts it when the + asks
/// (`PlusHooks.onOpen`) and takes it down on [onClose].
class AddList extends StatefulWidget {
  const AddList({
    super.key,
    required this.view,
    required this.opening,
    required this.onClose,
    required this.keys,
    this.pane,
    this.config = const AddConfig(),
    this.clock,
    this.coarse,
  });

  final EditorViewLike view;
  final PlusOpening opening;

  /// The note's pane, for the crease: the box of the page that scrolls the note, on the screen.
  final Rect? Function()? pane;
  final VoidCallback onClose;

  /// Where the editor's keys reach the list while the editor keeps the focus.
  final AddListKeys keys;
  final AddConfig config;

  /// The time, for the time row; the device's unless a test says.
  final DateTime Function()? clock;

  /// Whether the pointer is a finger; the device's answer unless a test says.
  final bool? coarse;

  @override
  State<AddList> createState() => AddListState();
}

class AddListState extends State<AddList> with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _cardKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _field = TextEditingController();
  final FocusNode _fieldFocus = FocusNode(debugLabel: 'add-list field');
  final FocusNode _listFocus = FocusNode(debugLabel: 'add-list');
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  late final AnimationController _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  late final AddGates _gates;
  late _Page _page;
  _Turn? _turn;
  int _turns = 0;
  late DateTime _now;
  late int _active;
  bool _keyed = false;
  String _more = '';
  Timer? _minute;
  VoidCallback? _offBack;
  bool _closed = false;
  bool _looking = true;
  bool Function(PlusKey key)? _ownKeys;
  Rect? _lastAnchor;

  PlusBy get _by => widget.opening.by;

  /// The editor keeps the focus unless the list took it: the keyboard on the + itself, or `/`, which focuses the
  /// palette's filter.
  bool get _driven => _by != PlusBy.keyboard && _by != PlusBy.slash;
  bool get _palette => _page == _Page.all;
  bool get _step => _page == _Page.note || _page == _Page.canvas;
  bool get _coarse => widget.coarse ?? coarsePointer;

  DateTime _clock() => (widget.clock ?? DateTime.now)();

  /// The page shown and the row lit, for a test and for whoever asks.
  String get page => _page.name;
  int get active => _active;

  /// Whether a key moved the lit row last (`data-keys`).
  bool get keyed => (_driven && _keyed) || _palette;

  /// The card's box on the screen, once it is laid out.
  Rect? get cardRect => _card?.cardRect;

  /// The rows shown, by their words: the menu's rows on a menu's page (Back among them), none on a step.
  List<String> get words => <String>[for (final row in _rows) row.words];

  RenderAddCard? get _card => _cardKey.currentContext?.findRenderObject() as RenderAddCard?;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    final state = widget.view.state;
    // The gates, read once as the list opens (add_rows.dart).
    _gates = readGates(
      picture: config.onPicture != null,
      video: config.onVideo != null,
      file: config.onFile != null,
      scan: config.onScan != null,
      place: config.onPlace != null,
      note: config.titles != null,
      canvas: config.canvases != null,
      localOnly: config.localOnly,
      // Read from the +'s line as the list opens, beside the others: a table straight above with an empty cell.
      tableAbove: emptyCellsAbove(state, state.selection.main.head) != null,
      // A note that is not a ticket, a notebook or a canvas can be made a ticket (docs/DESIGN.md §160).
      ticket: config.tickets && madeTicket(state.doc.toString()),
      board: config.boards,
      database: config.databases,
      blank: config.blanks,
      person: config.onPerson != null,
      simple: config.simple,
      toggles: config.toggles,
      effects: config.effects,
      inserts: config.inserts,
    );
    // `/` on an empty line opens straight onto the filterable palette of everything.
    _page = _by == PlusBy.slash ? _Page.all : _Page.top;
    // A fine pointer lights the first row, so the keys have a place to start from.
    _active = _by == PlusBy.touch ? -1 : 0;
    _now = _clock();
    _tick();
    _ownKeys = _onEditorKey;
    widget.keys.current = _ownKeys;
    _field.addListener(_typed);
    _fieldFocus.onKeyEvent = _onFieldKey;
    _listFocus.onKeyEvent = _onListKey;
    _scroll.addListener(_measureFade);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _lastAnchor = widget.opening.rect();
    _portal.show();
    _tell();
    _focusList();
    SchedulerBinding.instance.addPostFrameCallback(_look);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The phone's back gesture goes back a page, as Back does, and closes the list from its first.
    _offBack ??= BackScope.of(context).onBack(() {
      if (_page == _Page.top) {
        _close(true);
      } else {
        _go(_Page.top, _Turn.back);
      }
      return true;
    });
    if (_entrance.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    }
  }

  @override
  void didUpdateWidget(AddList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.keys, widget.keys)) {
      if (identical(oldWidget.keys.current, _ownKeys)) oldWidget.keys.current = null;
      widget.keys.current = _ownKeys;
    }
  }

  @override
  void dispose() {
    _looking = false;
    _minute?.cancel();
    _offBack?.call();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    if (identical(widget.keys.current, _ownKeys)) widget.keys.current = null;
    // Gone from the page: the editor hears the list closed, however it closed. After this frame's work, since the
    // editor's own listeners may rebuild.
    final view = widget.view;
    scheduleMicrotask(() => closePlus(view));
    _entrance.dispose();
    _scroll.dispose();
    _field.dispose();
    _fieldFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  // -- the time ------------------------------------------------------------------------------------------------------

  /// The time row says what it will write: read as the list opens, and again at the turn of each minute while it is
  /// open.
  void _tick() {
    final at = _clock();
    final rest = 60000 - (at.millisecondsSinceEpoch % 60000);
    _minute = Timer(Duration(milliseconds: rest), () {
      if (!mounted) return;
      setState(() => _now = _clock());
      _tick();
    });
  }

  // -- the rows ------------------------------------------------------------------------------------------------------

  List<_Shown> get _rows {
    final naming = onNamingLine(widget.view.state);
    List<_Shown> of(List<AddRow> rows) => <_Shown>[for (final row in rows) _Shown(row.id, row.words, row: row)];
    return switch (_page) {
      _Page.top => of(topRows(_gates, _now, naming)),
      _Page.all => of(filterRows(allRows(_gates, _now, naming), _field.text)),
      // Simple's More holds the time row, which says the minute the list was opened at, as the first page's does.
      _Page.more => <_Shown>[const _Shown.back(), ...of(moreRows(_gates, _now, naming))],
      _Page.board => <_Shown>[const _Shown.back(), ...of(boardRows())],
      _Page.database => <_Shown>[const _Shown.back(), ...of(databaseRows())],
      _Page.note || _Page.canvas => const <_Shown>[],
    };
  }

  List<String> get _found {
    if (!_step) return const <String>[];
    final titles = (_page == _Page.note ? widget.config.titles : widget.config.canvases)?.call() ?? const <String>[];
    return linkableTitles(titles, widget.config.own, _field.text);
  }

  void _haptic(HapticKind kind) => HapticsProvider.of(context)(kind);

  /// The list closed: told to the editor first, so the × turns back and what a row writes is not read as a change
  /// under it.
  void _close(bool refocus) {
    if (_closed) return;
    _closed = true;
    final view = widget.view;
    closePlus(view);
    widget.onClose();
    if (refocus && !view.hasFocus) view.focus();
  }

  void _go(_Page next, _Turn way) {
    _haptic(HapticKind.selection);
    setState(() {
      _turn = way;
      _turns += 1;
      _page = next;
      _field.removeListener(_typed);
      _field.clear();
      _field.addListener(_typed);
      _active = _driven && _by == PlusBy.touch ? -1 : 0;
    });
    // A page turned opens at its top, with Back first, wherever the page before was scrolled to.
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _tell();
    _focusList();
  }

  /// A row's press: dimmed, a step, or the list closed and then what the row does.
  void _choose(_Shown shown) {
    final row = shown.row;
    if (row == null) {
      _go(_Page.top, _Turn.back);
      return;
    }
    if (row.dimmed != null) {
      _haptic(HapticKind.warning);
      return;
    }
    final step = row.step;
    if (step != null) {
      _go(
        switch (step) {
          AddStep.more => _Page.more,
          AddStep.board => _Page.board,
          AddStep.database => _Page.database,
          AddStep.note => _Page.note,
          AddStep.canvas => _Page.canvas,
        },
        _Turn.forward,
      );
      return;
    }
    _haptic(HapticKind.selection);
    final view = widget.view;
    final config = widget.config;
    // The time the row says, not the clock's: pressed just past the minute, before the row has turned, it wrote
    // 14:06 under a row that said 14:05.
    final now = _now;
    _close(false);
    if (row.id == 'picture') {
      config.onPicture?.call();
    } else if (row.id == 'video') {
      config.onVideo?.call();
    } else if (row.id == 'file') {
      config.onFile?.call();
    } else if (row.id == 'scan') {
      config.onScan?.call();
    } else if (row.id == 'place') {
      config.onPlace?.call();
    } else if (row.id == 'person') {
      config.onPerson?.call();
    } else if (writeRow(view, row.id, now, effects: config.effects, inserts: config.inserts) && !view.hasFocus) {
      view.focus();
    }
  }

  /// A note or a canvas chosen in a step: written where the caret was, and the note has the focus back.
  void _pick(String title) {
    _haptic(HapticKind.selection);
    final view = widget.view;
    final canvas = _page == _Page.canvas;
    _close(false);
    if (canvas) {
      writeCanvasFrame(view, title);
    } else {
      writeNoteLink(view, title);
    }
    view.focus();
  }

  /// The editor names the lit row to a screen reader while it keeps the focus (insert_plus.dart).
  void _tell() {
    final rows = _rows;
    final id = _driven && _active >= 0 && _active < rows.length ? addRowId(rows[_active].id) : null;
    final view = widget.view;
    // After this frame's work: the editor's listeners may rebuild, and this may be called while building.
    scheduleMicrotask(() {
      if (!mounted || _closed || plusViewOf(view)?.gone == true) return;
      if (plusMenuOf(view.state) == PlusMenu(list: addListId, active: id)) return;
      view.dispatch(TransactionSpec(effects: plusMenu.of(PlusMenu(list: addListId, active: id))));
    });
  }

  void _move(int by) {
    final rows = _rows;
    if (rows.isEmpty) return;
    setState(() {
      _keyed = true;
      _active = _active < 0 ? (by > 0 ? 0 : rows.length - 1) : (_active + by + rows.length) % rows.length;
    });
    _tell();
    _reveal();
  }

  /// The lit row kept in sight as the keys move it.
  void _reveal() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _active < 0) return;
      final rows = _rows;
      if (_active >= rows.length) return;
      final context = _rowKeys[rows[_active].id]?.currentContext;
      if (context == null || Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  /// The editor's keys, while it keeps the focus.
  bool _onEditorKey(PlusKey key) {
    if (!mounted || _closed) return false;
    if (key == PlusKey.escape) {
      _close(false);
      return true;
    }
    if (_step) return false;
    if (key == PlusKey.up || key == PlusKey.down) {
      _move(key == PlusKey.up ? -1 : 1);
      return true;
    }
    if (key == PlusKey.left) {
      if (_page == _Page.top) return false;
      _go(_Page.top, _Turn.back);
      return true;
    }
    final rows = _rows;
    if (_active < 0 || _active >= rows.length) return false;
    final row = rows[_active];
    if (key == PlusKey.right) {
      if (!row.onward) return false;
      _choose(row);
      return true;
    }
    _choose(row);
    return true;
  }

  /// The same keys when the focus is in the list itself.
  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close(true);
      return KeyEventResult.handled;
    }
    final inField = _fieldFocus.hasFocus;
    if (key == LogicalKeyboardKey.arrowLeft && _page != _Page.top && !inField) {
      _go(_Page.top, _Turn.back);
      return KeyEventResult.handled;
    }
    final rows = _rows;
    if ((key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) && !inField && rows.isNotEmpty) {
      _move(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.space) && !inField && rows.isNotEmpty && event is KeyDownEvent) {
      _choose(rows[math.max(0, _active).clamp(0, rows.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The field's own keys: in the palette Up and Down move the lit row and Enter takes it; in a step Enter takes the
  /// first title found.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final enter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
    if (_palette) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _move(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _move(-1);
        return KeyEventResult.handled;
      }
      if (enter) {
        _submit();
        return KeyEventResult.handled;
      }
    } else if (_step && enter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Enter in the field, from a key or from the keyboard's own button.
  void _submit() {
    if (_palette) {
      final rows = _rows;
      if (rows.isEmpty) return;
      _choose(_active >= 0 && _active < rows.length ? rows[_active] : rows.first);
    } else if (_step) {
      final found = _found;
      if (found.isNotEmpty) _pick(found.first);
    }
  }

  /// What is typed in the field: a step's titles are looked up again; the palette lights its first match, so Enter
  /// takes the obvious one.
  void _typed() {
    if (!mounted) return;
    setState(() {
      if (_palette) _active = 0;
    });
    _tell();
  }

  /// Opened from the keyboard, the focus is in the list, and again on each page. The palette and a step put it in
  /// their field instead, however the list was opened.
  void _focusList() {
    final field = _palette || _step;
    if (_driven && !field) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) return;
      final node = field ? _fieldFocus : _listFocus;
      if (!node.hasPrimaryFocus) node.requestFocus();
    });
  }

  // -- what closes it, and what does not ---------------------------------------------------------------------------------

  /// It closes on a press anywhere but itself and the +, and on a wheel outside it.
  void _onPointer(PointerEvent event) {
    if (_closed || !mounted) return;
    if (event is! PointerDownEvent && event is! PointerSignalEvent) return;
    final card = cardRect;
    if (card != null && card.contains(event.position)) return;
    final plus = widget.opening.rect();
    if (plus != null && plus.width > 0 && plus.contains(event.position)) return;
    _close(false);
  }

  ({double top, double bottom}) _view() {
    final media = MediaQuery.of(context);
    return (top: 0, bottom: media.size.height - media.viewInsets.bottom);
  }

  /// Re-anchored to the + after each frame the app draws: the keyboard rising scrolls the note. A scroll of the
  /// list's own rows is the list's. Once the + has left the screen, the list closes.
  void _look(Duration _) {
    if (!mounted || !_looking || _closed) return;
    final row = widget.opening.rect();
    if (row != null) {
      final room = _view();
      if (row.height > 0 && (row.bottom <= room.top || row.top >= room.bottom)) {
        _close(false);
        return;
      }
      if (row != _lastAnchor) setState(() => _lastAnchor = row);
    }
    _measureFade();
    SchedulerBinding.instance.addPostFrameCallback(_look);
  }

  /// Rows past an edge fade there.
  void _measureFade() {
    if (!mounted || !_scroll.hasClients) return;
    final at = _scroll.position;
    if (!at.hasContentDimensions) return;
    final start = at.pixels > 1;
    final end = at.pixels < at.maxScrollExtent - 1;
    final more = <String>[if (start) 'start', if (end) 'end'].join(' ');
    if (more != _more) setState(() => _more = more);
  }

  // -- drawing -------------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // The tokens where the list is asked for (the note's own hue), handed to the overlay it draws in.
    final t = context.tokens;
    final media = MediaQuery.of(context);
    return OverlayPortal(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (overlay) => _card_(overlay, t, media),
      child: const SizedBox.shrink(),
    );
  }

  Widget _card_(BuildContext overlay, Tokens t, MediaQueryData media) {
    final rows = _rows;
    final space1 = t.space(1);
    final ink = t.color('app-ink');
    final rem = t.lenOf('1rem');
    final still = media.disableAnimations;
    // The doors between the pages never scroll away: Back held at the top of a step page, More at the foot of the
    // first.
    final head = (_page == _Page.more || _page == _Page.board || _page == _Page.database) && rows.isNotEmpty && rows.first.isBack ? 0 : -1;
    final foot = _page == _Page.top && rows.isNotEmpty && rows.last.id == 'more' ? rows.length - 1 : -1;
    final turn = still ? null : _turn;

    Widget turned(String part, Widget child) => _Turned(key: ValueKey<String>('${_page.name}-$part-$_turns'), turn: turn, curve: t.curve('glacier-ease-out'), child: child);

    Widget menuRow(int index) {
      final shown = rows[index];
      final row = shown.row;
      final lit = (_driven || _palette) && index == _active;
      // With the focus in the list its row wears the focus ring, as a focused button does.
      final focused = !_driven && !_palette && _listFocus.hasFocus && index == math.max(0, _active);
      return _RowView(
        key: _rowKeys.putIfAbsent(shown.id, GlobalKey.new),
        t: t,
        icon: _iconFor(shown.id, t),
        words: shown.words,
        why: row?.dimmed,
        hint: row?.hint,
        label: row?.label,
        onward: shown.onward,
        lit: lit,
        ringed: (lit && keyed) || focused,
        coarse: _coarse,
        onTap: () => _choose(shown),
        onMouse: () {
          if (!_driven && !_palette) return;
          if (_active == index && !_keyed) return;
          setState(() {
            _keyed = false;
            _active = index;
          });
          _tell();
        },
      );
    }

    final Widget headBox;
    if (_step) {
      headBox = Padding(
        padding: EdgeInsets.fromLTRB(space1, space1, space1, 0),
        child: turned('head', _RowView(t: t, icon: _iconFor('back', t), words: 'Back', coarse: _coarse, onTap: () => _go(_Page.top, _Turn.back))),
      );
    } else if (head >= 0) {
      headBox = Padding(padding: EdgeInsets.fromLTRB(space1, space1, space1, 0), child: turned('head', menuRow(head)));
    } else {
      headBox = const SizedBox.shrink();
    }
    final footBox = foot >= 0 ? Padding(padding: EdgeInsets.fromLTRB(space1, 0, space1, space1), child: turned('foot', menuRow(foot))) : const SizedBox.shrink();

    final List<Widget> page;
    if (_step) {
      final note = _page == _Page.note;
      final found = _found;
      page = <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), space1),
          child: Text(note ? 'Which note?' : 'Which canvas?', style: t.textAt(t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-3'))),
        ),
        _FieldView(t: t, controller: _field, focusNode: _fieldFocus, placeholder: note ? 'Type part of its title' : 'Type part of its name', label: note ? 'Part of the note’s title' : 'Part of the canvas’s name', onSubmitted: _submit),
        for (final title in found) _RowView(t: t, icon: _iconFor(note ? 'note' : 'canvas', t), words: title, coarse: _coarse, onTap: () => _pick(title)),
        if (found.isEmpty)
          _NoneView(
            t: t,
            words: _field.text.trim().isNotEmpty ? (note ? 'No note by that name.' : 'No canvas by that name.') : (note ? 'No notes yet.' : 'No canvases yet.'),
          ),
      ];
    } else if (_palette) {
      page = <Widget>[
        _FieldView(t: t, controller: _field, focusNode: _fieldFocus, placeholder: 'Type to filter', label: 'Filter what to add', onSubmitted: _submit),
        if (rows.isNotEmpty) for (var index = 0; index < rows.length; index += 1) menuRow(index) else _NoneView(t: t, words: 'Nothing by that name.', paragraph: true),
      ];
    } else {
      page = <Widget>[
        for (var index = 0; index < rows.length; index += 1)
          if (index != head && index != foot) menuRow(index),
      ];
    }

    final room = _view();
    final pane = widget.pane?.call();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: _step ? (_page == _Page.note ? 'Which note?' : 'Which canvas?') : 'Add to this note',
      // Its rows say their own tick; the app's tap tick lets them off.
      child: HapticTarget(
        kind: null,
        child: DefaultTextStyle(
          style: t.textAt(t.fontSize('md'), color: ink),
          child: Focus(
            focusNode: _listFocus,
            // A press on the list must not take the editor's focus: it is reached by the keyboard alone.
            canRequestFocus: !_driven,
            skipTraversal: _driven || _palette || _step,
            onFocusChange: (_) {
              if (mounted) setState(() {});
            },
            child: AddCard(
              key: _cardKey,
              anchor: _lastAnchor,
              viewTop: room.top,
              viewBottom: room.bottom,
              statusBar: t.len('app-inset-top'),
              window: media.size.width,
              full: t.lenOf('min(16rem, calc(100vw - 2 * var(--app-gutter)))'),
              opened: _coarse && media.size.width >= _openedFold,
              paneRight: pane?.right,
              rem: rem,
              rowHeight: t.lenOf('2.75rem'),
              // What the page's layout effect waits on: the page, how many rows, and what is typed.
              epoch: Object.hash(_page, rows.length, _field.text),
              background: t.color('app-paper-2'),
              border: t.color('app-rule'),
              hairline: t.len('glacier-hairline'),
              shadow: t.shadowOf('0 10px 28px rgba(0, 0, 0, 0.28)'),
              entrance: CurvedAnimation(parent: _entrance, curve: t.curve('glacier-ease-out')),
              children: <Widget>[
                headBox,
                _RowsView(controller: _scroll, more: _more, padding: space1, child: turned('rows', Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: page))),
                footBox,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconFor(String id, Tokens t) {
    final ink = t.color('app-ink-3');
    if (id == 'back') return AppIcon(Lucide.chevronLeft, size: 18, color: ink);
    if (id.startsWith('query:')) return AppIcon(_databaseIcons[id.substring('query:'.length)] ?? Lucide.database, size: 18, color: ink);
    // The place is the app's own mark, the one on the More sheet's Add my location.
    if (id == 'place') return DrawnIconView(AppIcons.locate, size: 18, color: ink);
    if (id.startsWith('insert:')) {
      for (final insert in widget.config.inserts) {
        final mark = insert.mark;
        if ('insert:${insert.id}' == id && mark != null) return Builder(builder: (context) => mark(context, 18));
      }
      return AppIcon(Lucide.sparkles, size: 18, color: ink);
    }
    if (id.startsWith('effect:')) {
      LucideIcon? mark;
      for (final effect in widget.config.effects) {
        if ('effect:${effect.name}' == id) mark = effect.icon;
      }
      return AppIcon(mark ?? Lucide.sparkles, size: 18, color: ink);
    }
    return AppIcon(_icons[id] ?? Lucide.sparkles, size: 18, color: ink);
  }
}

/// A page turned: More and back, a step to choose a note, each slides in from the side it came from
/// (`.page[data-turn]`: 180ms, from clear and 12px aside).
class _Turned extends StatelessWidget {
  const _Turned({super.key, required this.turn, required this.curve, required this.child});

  final _Turn? turn;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final turn = this.turn;
    if (turn == null) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: curve,
      child: child,
      builder: (context, value, child) {
        if (value >= 1) return child!;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset((1 - value) * (turn == _Turn.forward ? 12 : -12), 0), child: child),
        );
      },
    );
  }
}

/// What scrolls: the rows, when neither side of the +'s row has room for all of them. More rows past an edge: the
/// list fades there instead of cutting a row (`.rows`, `[data-more]`).
class _RowsView extends StatelessWidget {
  const _RowsView({required this.controller, required this.more, required this.padding, required this.child});

  final ScrollController controller;
  final String more;
  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = more.contains('start'), end = more.contains('end');
    // The mask is always there, clear of the rows when no edge fades: were it put on and taken off, the rows under
    // it would be made anew each time, and lose where they were scrolled to and the field its keyboard.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final fade = bounds.height <= 0 ? 0.0 : (32 / bounds.height).clamp(0.0, 0.5);
        const clear = Color(0x00000000), solid = Color(0xFF000000);
        return ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          <Color>[start ? clear : solid, solid, solid, end ? clear : solid],
          <double>[0, start ? fade : 0, end ? 1 - fade : 1, 1],
        );
      },
      child: ScrollConfiguration(
        behavior: const _NoBars(),
        child: SingleChildScrollView(controller: controller, padding: EdgeInsets.all(padding), child: child),
      ),
    );
  }
}

class _NoBars extends GhostScrollBehavior {
  const _NoBars();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// A row: an icon in the third ink and the words in ink, a thumb's height (`.row`).
class _RowView extends StatefulWidget {
  const _RowView({
    super.key,
    required this.t,
    required this.icon,
    required this.words,
    required this.coarse,
    required this.onTap,
    this.why,
    this.hint,
    this.label,
    this.onward = false,
    this.lit = false,
    this.ringed = false,
    this.onMouse,
  });

  final Tokens t;
  final Widget icon;
  final String words;
  final String? why;

  /// What the row makes, in a line under its words (simple's first page); the reason takes its place on a dimmed
  /// row, since why it cannot be pressed matters more than what it would have made.
  final String? hint;
  final String? label;
  final bool onward;
  final bool lit;
  final bool ringed;
  final bool coarse;
  final VoidCallback onTap;
  final VoidCallback? onMouse;

  @override
  State<_RowView> createState() => _RowViewState();
}

class _RowViewState extends State<_RowView> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final dimmed = widget.why != null;
    final ink3 = t.color('app-ink-3');
    final size = t.fontSize('md');
    final words = t.textAt(size, weight: 'medium', color: dimmed ? ink3 : t.color('app-ink'));
    final ground = widget.lit || _pressed || (_hovered && !widget.coarse) ? t.color('app-paper-3') : null;
    const radius = BorderRadius.all(Radius.circular(12));
    Widget row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
        child: Row(
          children: <Widget>[
            SizedBox.square(dimension: 18, child: widget.icon),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.words, style: words),
                  // A choice the person made stands in the way: the row and its reason in the third ink. Or, on
                  // simple's first page, what the row makes, in the same ink and place.
                  if (dimmed)
                    Text(widget.why!, style: t.textAt(t.fontSize('sm'), color: ink3))
                  else if (widget.hint != null)
                    Text(widget.hint!, style: t.textAt(t.fontSize('sm'), color: ink3)),
                ],
              ),
            ),
            // More's own mark: there is a page behind it. On the page it is a drawing in a line of text, standing on
            // the line's baseline: the top 16px of a box one line tall.
            if (widget.onward) ...<Widget>[
              SizedBox(width: t.space(3)),
              SizedBox(height: (words.height ?? 1.25) * size, child: Align(alignment: Alignment.topCenter, child: AppIcon(Lucide.chevronRight, size: 16, color: ink3))),
            ],
          ],
        ),
      ),
    );
    row = DecoratedBox(decoration: BoxDecoration(color: ground, borderRadius: radius), child: row);
    if (widget.ringed) row = CustomPaint(foregroundPainter: _Ring(t.color('glacier-focus-ring')), child: row);
    return Semantics(
      button: true,
      enabled: !dimmed,
      label: widget.label ?? (dimmed ? '${widget.words}, ${widget.why}' : (widget.hint != null ? '${widget.words}, ${widget.hint}' : widget.words)),
      onTap: widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: dimmed ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (event) {
          if (event.kind != PointerDeviceKind.mouse) return;
          setState(() => _hovered = true);
          widget.onMouse?.call();
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: row,
        ),
      ),
    );
  }
}

/// `outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px`: the ring inside the row's own edge.
class _Ring extends CustomPainter {
  const _Ring(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(11)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.color != color;
}

/// A step's field, and the palette's filter (`.field`).
class _FieldView extends StatefulWidget {
  const _FieldView({required this.t, required this.controller, required this.focusNode, required this.placeholder, required this.label, required this.onSubmitted});

  final Tokens t;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final String label;
  final VoidCallback onSubmitted;

  @override
  State<_FieldView> createState() => _FieldViewState();
}

class _FieldViewState extends State<_FieldView> {
  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_changed);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final ink = t.color('app-ink');
    final style = t.textAt(t.fontSize('md'), color: ink);
    final hairline = t.len('glacier-hairline');
    final empty = widget.controller.text.isEmpty;
    Widget field = Stack(
      children: <Widget>[
        // First, and always in the same place: the field must stay the one it was as its placeholder comes and goes.
        EditableText(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: true,
          style: style,
          cursorColor: ink,
          cursorWidth: 1,
          backgroundCursorColor: t.color('app-ink-3'),
          selectionColor: t.color('glacier-selection'),
          keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onSubmitted(),
        ),
        // A browser's own placeholder ink: the words at their colour, a little over half as strong.
        if (empty) IgnorePointer(child: Text(widget.placeholder, maxLines: 1, overflow: TextOverflow.clip, style: style.copyWith(color: const Color(0xFF757575)))),
      ],
    );
    field = DecoratedBox(
      decoration: BoxDecoration(color: t.color('app-paper'), border: Border.all(color: t.color('app-rule'), width: hairline), borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Padding(padding: EdgeInsets.symmetric(vertical: t.space(2) + hairline, horizontal: t.space(3) + hairline), child: field),
    );
    return Semantics(
      textField: true,
      label: widget.label,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(2), t.space(1), t.space(2), t.space(2)),
        // `.field:focus-visible { outline: 2px solid var(--glacier-focus-ring); outline-offset: 2px }`
        child: GlacierFocusRing(visible: widget.focusNode.hasFocus, radius: 12, offset: 2, width: 2, child: field),
      ),
    );
  }
}

/// A step with nothing to offer, or a filter nothing matches (`.none`). The palette's is a paragraph on the page,
/// with a paragraph's own margins, a line of its text above and below; a step's is an item of its list, with none.
class _NoneView extends StatelessWidget {
  const _NoneView({required this.t, required this.words, this.paragraph = false});

  final Tokens t;
  final String words;
  final bool paragraph;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: t.space(2) + (paragraph ? t.fontSize('sm') : 0), horizontal: t.space(3)),
    child: Text(words, style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
  );
}

/// The card, placed against the +'s row as it is laid out (`.list`): paper-2 with a hairline and press and hold's
/// shadow, 18px corners, and three parts down it - what is held at its top, the rows that scroll, what is held at
/// its foot. It fills the window and takes a press only on the card.
class AddCard extends MultiChildRenderObjectWidget {
  const AddCard({
    super.key,
    required this.anchor,
    required this.viewTop,
    required this.viewBottom,
    required this.statusBar,
    required this.window,
    required this.full,
    required this.opened,
    required this.paneRight,
    required this.rem,
    required this.rowHeight,
    required this.epoch,
    required this.background,
    required this.border,
    required this.hairline,
    required this.shadow,
    required this.entrance,
    required super.children,
  }) : assert(children.length == 3);

  /// The +'s box on the screen, as it was when the list was last built.
  final Rect? anchor;
  final double viewTop;
  final double viewBottom;
  final double statusBar;
  final double window;
  final double full;
  final bool opened;
  final double? paneRight;
  final double rem;
  final double rowHeight;

  /// Changes when the page's own placing would run again for what is in the card: the page, the rows, the filter.
  final Object epoch;
  final Color background;
  final Color border;
  final double hairline;
  final List<BoxShadow> shadow;
  final Animation<double> entrance;

  @override
  RenderAddCard createRenderObject(BuildContext context) => RenderAddCard(this);

  @override
  void updateRenderObject(BuildContext context, RenderAddCard renderObject) => renderObject.spec = this;
}

class _CardSlot extends ContainerBoxParentData<RenderBox> {}

/// Lays the card's three parts out and places it ([placeList]).
class RenderAddCard extends RenderBox with ContainerRenderObjectMixin<RenderBox, _CardSlot>, RenderBoxContainerDefaultsMixin<RenderBox, _CardSlot> {
  RenderAddCard(this._spec);

  AddCard _spec;
  set spec(AddCard value) {
    final was = _spec;
    _spec = value;
    if (!identical(was.entrance, value.entrance)) {
      if (attached) {
        was.entrance.removeListener(markNeedsPaint);
        value.entrance.addListener(markNeedsPaint);
      }
    }
    markNeedsLayout();
  }

  Rect? _cardLocal;
  ListPlace? _place;
  Object? _placedFor;

  /// The card's box on the screen.
  Rect? get cardRect => _cardLocal == null || !attached ? null : MatrixUtils.transformRect(getTransformTo(null), _cardLocal!);

  /// How tall the rows that scroll may be now, or null for as tall as they are (`max-block-size` on `.rows`).
  double? get cap => _place?.cap;

  /// Where the card was last placed.
  ListPlace? get place => _place;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardSlot) child.parentData = _CardSlot();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _spec.entrance.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _spec.entrance.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// A whole pixel as the page's `offsetHeight` and `scrollHeight` are: the nearest one.
  static double _whole(double value) => (value + 0.5).floorToDouble();

  /// Places the card and lays its parts out.
  ///
  /// The page reads its own boxes to do this, after they are drawn: `chrome = card.offsetHeight -
  /// rows.offsetHeight` and `natural = chrome + rows.scrollHeight`, each a whole number of pixels, and with the
  /// rows still capped as the last placing left them. Those sums are made here from the parts' real heights
  /// rounded the same way, so the card is where the page puts it to the fraction of a pixel; and they are made
  /// once for each thing the page would place again for (the +'s box, the window, the page of rows), not on every
  /// layout, since the sums are not the same the second time round.
  @override
  void performLayout() {
    final spec = _spec;
    final head = firstChild!, rows = childAfter(head)!, foot = childAfter(rows)!;
    final row = spec.anchor;
    final local = row == null ? null : MatrixUtils.transformRect(Matrix4.inverted(getTransformTo(null)), row);
    final b = spec.hairline;

    // The card's width, which the crease may narrow, comes of the same sums; the heights need it first.
    final across = local == null
        ? null
        : placeList(row: local, viewTop: double.negativeInfinity, viewBottom: double.infinity, natural: 0, chrome: 0, full: spec.full, window: spec.window, opened: spec.opened, paneRight: spec.paneRight, rem: spec.rem);
    final width = across?.width ?? _place?.width ?? spec.full;
    final inner = BoxConstraints.tightFor(width: math.max(0, width - 2 * b));
    head.layout(inner, parentUsesSize: true);
    foot.layout(inner, parentUsesSize: true);
    final scrollNatural = rows.getMaxIntrinsicHeight(inner.maxWidth);

    final key = Object.hash(local, spec.viewTop, spec.viewBottom, spec.statusBar, spec.window, spec.full, spec.opened, spec.paneRight, spec.epoch, scrollNatural, head.size.height, foot.size.height);
    if (local != null && key != _placedFor) {
      final capped = math.min(scrollNatural, _place?.cap ?? double.infinity);
      final chrome = _whole(2 * b + head.size.height + foot.size.height + capped) - _whole(capped);
      final natural = chrome + _whole(scrollNatural);
      final placed = placeList(
        row: local,
        viewTop: spec.viewTop,
        viewBottom: spec.viewBottom,
        statusBar: spec.statusBar,
        natural: natural,
        chrome: chrome,
        rowHeight: spec.rowHeight,
        full: spec.full,
        window: spec.window,
        opened: spec.opened,
        paneRight: spec.paneRight,
        rem: spec.rem,
      );
      // Out of sight: the list is about to close, and stays where it was until it does.
      if (placed != null) {
        _place = placed;
        _placedFor = key;
      }
    }
    final place = _place;
    rows.layout(BoxConstraints(minWidth: inner.maxWidth, maxWidth: inner.maxWidth, maxHeight: place?.cap ?? double.infinity), parentUsesSize: true);
    if (place == null) {
      _cardLocal = null;
      return;
    }
    final height = 2 * b + head.size.height + rows.size.height + foot.size.height;
    _cardLocal = Rect.fromLTWH(place.x, place.y, width, height);
    var y = place.y + b;
    for (final child in <RenderBox>[head, rows, foot]) {
      (child.parentData! as _CardSlot).offset = Offset(place.x + b, y);
      y += child.size.height;
    }
  }

  @override
  bool get alwaysNeedsCompositing => _spec.entrance.value < 1;

  @override
  void paint(PaintingContext context, Offset offset) {
    final card = _cardLocal;
    if (card == null) return;
    final spec = _spec;
    final at = spec.entrance.value;
    void draw(PaintingContext context, Offset offset) {
      final box = card.shift(offset);
      const radius = BorderRadius.all(Radius.circular(18));
      final decoration = BoxDecoration(color: spec.background, border: Border.all(color: spec.border, width: spec.hairline), borderRadius: radius, boxShadow: spec.shadow);
      final painter = decoration.createBoxPainter();
      painter.paint(context.canvas, box.topLeft, ImageConfiguration(size: box.size));
      painter.dispose();
      // `overflow: hidden`: the parts are cut to the card's corners, inside its hairline.
      final clip = radius.toRRect(box).deflate(spec.hairline);
      context.pushClipRRect(needsCompositing, offset, box, clip.shift(-offset), (context, offset) => defaultPaint(context, offset));
    }

    if (at >= 1) {
      draw(context, offset);
      return;
    }
    // Press and hold's arrival: a short rise, from nothing (`listIn`: clear, 4px low and 0.98 of its size).
    final centre = card.center;
    final scale = 0.98 + 0.02 * at;
    final rise = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy + 4 * (1 - at), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    context.pushOpacity(offset, (at.clamp(0.0, 1.0) * 255).round(), (context, offset) {
      context.pushTransform(needsCompositing, offset, rise, draw);
    });
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final card = _cardLocal;
    if (card == null || !card.contains(position)) return false;
    defaultHitTestChildren(result, position: position);
    // The card itself is a press on the list: nothing under it hears it.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
