/// Many tickets picked in a query, and the bar that changes them together (Matt, 2026-10-31: "Select many cards on a
/// board, or rows in a table or list query (shift/cmd-click, a selection box on desktop, long-press then tap on
/// phone). A bar appears with: Status, Assignee, Labels, Due, Priority, Move to notebook, Delete (to Trash)").
///
/// **Picking.** On a desktop, a click with Command (Control off a Mac) adds a ticket or takes it out, a click with
/// Shift picks every ticket from the last one picked to it, and a box dragged from the query's empty ground picks
/// every ticket it touches. On a phone a press held on a ticket picks it, and while any are picked a tap picks or
/// lets go of another instead of opening it. Escape, or the bar's cross, lets go of them all. Only tickets are
/// picked: a to-do's fields are its line's, and a note has none of these.
///
/// **The bar.** Over the foot of the window while any are picked: how many, then Status, Assignee, Labels, Due,
/// Priority, Move to notebook and Delete. Each opens the app's own sheet for it (fields/field_picker.dart, the label
/// picker) and writes what is chosen to every ticket picked as one batch, through the root ([BulkActions]): all or
/// nothing, one Undo for all, and what failed said (lib/tickets/bulk.dart). In simple mode (GHST-103) the bar keeps
/// Status, Assignee and Labels, the rest behind More, which opens in place.
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/query/query.dart' show QueryRow, RecordKind;
import '../../editor/fields/field_picker.dart';
import '../../editor/fields/field_picks.dart';
import '../../editor/items/field_menu.dart' show DayPicker;
import '../../home/home_text.dart' show pageText, tabular;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../bulk.dart';
import '../labels.dart';
import 'label_picker.dart';

/// What the root does with the tickets picked: each a batch of its own, said in a toast with its Undo.
class BulkActions {
  const BulkActions({required this.edit, required this.move, required this.trash, required this.notebooks, required this.labels, this.people, this.coloursOf});

  /// [edit] written to every ticket, by note id.
  final Future<void> Function(List<String> noteIds, BulkEdit edit) edit;

  /// Every ticket's page moved into the notebook of that id.
  final Future<void> Function(List<String> noteIds, String notebookId) move;

  /// Every ticket into the Trash, with one Undo.
  final void Function(List<String> noteIds) trash;

  /// The notebooks a ticket can be moved to, by id and title.
  final List<({String id, String title})> Function() notebooks;

  /// The labels the library uses, the most used first.
  final List<String> Function() labels;

  /// The people the library names, for Assignee.
  final List<String> Function()? people;

  /// A ticket's notebook's label colours.
  final Map<String, String> Function(String noteId)? coloursOf;
}

/// The tickets picked in one query, by row key, in the order they were picked; and where each is drawn, for the
/// box dragged over them.
class QuerySelection extends ChangeNotifier {
  final List<String> _keys = [];
  String? _anchor;
  final Map<String, GlobalKey> _boxes = {};

  /// A press that picked: the tap it ends in opens nothing.
  bool swallowTap = false;

  bool get any => _keys.isNotEmpty;
  int get length => _keys.length;
  List<String> get keys => List.unmodifiable(_keys);
  bool has(String key) => _keys.contains(key);

  /// Picked, or let go of where it was.
  void toggle(String key) {
    if (!_keys.remove(key)) _keys.add(key);
    _anchor = key;
    notifyListeners();
  }

  /// Every key from the last picked to [key] in [order] picked, as Shift picks a run.
  void range(List<String> order, String key) {
    final from = _anchor == null ? -1 : order.indexOf(_anchor!);
    final to = order.indexOf(key);
    if (from < 0 || to < 0) return toggle(key);
    final (a, b) = from <= to ? (from, to) : (to, from);
    for (final each in order.sublist(a, b + 1)) {
      if (!_keys.contains(each)) _keys.add(each);
    }
    _anchor = key;
    notifyListeners();
  }

  /// [keys] picked, besides those already where [adding].
  void pick(Iterable<String> keys, {bool adding = false}) {
    if (!adding) _keys.clear();
    for (final key in keys) {
      if (!_keys.contains(key)) _keys.add(key);
    }
    notifyListeners();
  }

  void clear() {
    if (_keys.isEmpty) return;
    _keys.clear();
    _anchor = null;
    notifyListeners();
  }

  /// Only the keys still drawn: a ticket that left the query is let go of.
  void keepOnly(Set<String> drawn) {
    final before = _keys.length;
    _keys.removeWhere((key) => !drawn.contains(key));
    _boxes.removeWhere((key, _) => !drawn.contains(key));
    if (_keys.length != before) notifyListeners();
  }

  /// Where a row is drawn.
  GlobalKey boxOf(String key) => _boxes[key] ??= GlobalKey(debugLabel: 'picked $key');

  /// The keys whose rows a box in global coordinates touches.
  List<String> touched(Rect box) {
    final found = <String>[];
    for (final MapEntry(:key, :value) in _boxes.entries) {
      final object = value.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      final rect = object.localToGlobal(Offset.zero) & object.size;
      if (rect.overlaps(box)) found.add(key);
    }
    return found;
  }

  /// Whether a point in global coordinates is on a row.
  bool onRow(Offset at) {
    for (final value in _boxes.values) {
      final object = value.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      if ((object.localToGlobal(Offset.zero) & object.size).contains(at)) return true;
    }
    return false;
  }
}

/// Whether the keys held say a click picks rather than opens: Command or Control, or Shift for a run.
bool _picking() {
  final keys = HardwareKeyboard.instance;
  return keys.isMetaPressed || keys.isControlPressed || keys.isShiftPressed;
}

/// A ticket's card or row that can be picked: the press that picks it heard, and drawn picked.
class QuerySelectable extends StatefulWidget {
  const QuerySelectable({super.key, required this.selection, required this.row, required this.order, required this.child, this.radius = 0, this.boxed = true, this.drawn = true});

  final QuerySelection selection;
  final QueryRow row;

  /// Every pickable row's key in the order drawn, for Shift's run.
  final List<String> Function() order;
  final Widget child;
  final double radius;

  /// Whether this is where the row is drawn, for the box dragged over it: a table's row is its name's cell, and its
  /// other cells only hear the press.
  final bool boxed;

  /// Whether it is drawn picked here: a table's row is grounded whole by the table instead.
  final bool drawn;

  /// Whether [row] can be picked at all.
  static bool can(QueryRow row) => row.kind == RecordKind.ticket;

  @override
  State<QuerySelectable> createState() => _QuerySelectableState();
}

class _QuerySelectableState extends State<QuerySelectable> {
  Offset? _down;
  Duration? _at;
  PointerDeviceKind? _kind;

  void _pressed(PointerDownEvent event) {
    widget.selection.swallowTap = false;
    _down = event.position;
    _at = event.timeStamp;
    _kind = event.kind;
  }

  void _lifted(PointerUpEvent event) {
    final down = _down, at = _at;
    _down = null;
    if (down == null || at == null || (event.position - down).distance > 12) return;
    final key = widget.row.key;
    final selection = widget.selection;
    final mouse = _kind == PointerDeviceKind.mouse || _kind == PointerDeviceKind.trackpad;
    if (mouse && _picking()) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        selection.range(widget.order(), key);
      } else {
        selection.toggle(key);
      }
      selection.swallowTap = true;
      fireMotor(HapticKind.selection);
      return;
    }
    // A press held on a phone: picked, and the tap it ends in opens nothing.
    if (!mouse && event.timeStamp - at >= const Duration(milliseconds: 450)) {
      selection.toggle(key);
      selection.swallowTap = true;
      fireMotor(HapticKind.medium);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!QuerySelectable.can(widget.row)) return widget.child;
    final t = context.tokens;
    final picked = widget.selection.has(widget.row.key);
    return Listener(
      onPointerDown: _pressed,
      onPointerUp: _lifted,
      onPointerCancel: (_) => _down = null,
      child: GestureDetector(
        // While any are picked, a tap anywhere on a ticket picks it or lets it go.
        onTap: widget.selection.any
            ? () {
                if (widget.selection.swallowTap) {
                  widget.selection.swallowTap = false;
                  return;
                }
                widget.selection.toggle(widget.row.key);
                fireMotor(HapticKind.selection);
              }
            : null,
        behavior: HitTestBehavior.translucent,
        child: KeyedSubtree(
          key: widget.boxed ? widget.selection.boxOf(widget.row.key) : null,
          child: Semantics(
            selected: picked,
            child: !widget.drawn
                ? widget.child
                : DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: picked
                        ? BoxDecoration(
                            color: t.color('glacier-accent-9').withValues(alpha: 0.10),
                            border: Border.all(color: t.color('glacier-accent-9'), width: 1.5),
                            borderRadius: BorderRadius.circular(widget.radius),
                          )
                        : const BoxDecoration(),
                    child: widget.child,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The box dragged from a query's empty ground with a mouse, which picks every ticket it touches: Shift held adds them
/// to those picked.
class SelectionBox extends StatefulWidget {
  const SelectionBox({super.key, required this.selection, required this.child});

  final QuerySelection selection;
  final Widget child;

  @override
  State<SelectionBox> createState() => _SelectionBoxState();
}

class _SelectionBoxState extends State<SelectionBox> {
  Offset? _from;
  Offset? _to;
  bool _adding = false;

  Offset _local(Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached ? box.globalToLocal(global) : global;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final from = _from, to = _to;
    final dragged = from != null && to != null && (to - from).distance > 6;
    return Listener(
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse || event.buttons != kPrimaryMouseButton) return;
        if (widget.selection.onRow(event.position)) return;
        _adding = HardwareKeyboard.instance.isShiftPressed || HardwareKeyboard.instance.isMetaPressed;
        setState(() {
          _from = event.position;
          _to = event.position;
        });
      },
      onPointerMove: (event) {
        if (_from == null) return;
        setState(() => _to = event.position);
      },
      onPointerUp: (event) {
        final from = _from, to = _to;
        setState(() {
          _from = null;
          _to = null;
        });
        if (from == null || to == null || (to - from).distance <= 6) return;
        final touched = widget.selection.touched(Rect.fromPoints(from, to));
        if (touched.isEmpty && !_adding) return widget.selection.clear();
        widget.selection.pick(touched, adding: _adding);
        if (touched.isNotEmpty) fireMotor(HapticKind.selection);
      },
      onPointerCancel: (_) => setState(() {
        _from = null;
        _to = null;
      }),
      child: Stack(
        children: [
          widget.child,
          if (dragged)
            Positioned.fromRect(
              rect: Rect.fromPoints(_local(from), _local(to)),
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('selection-box'),
                  decoration: BoxDecoration(color: t.color('glacier-accent-9').withValues(alpha: 0.08), border: Border.all(color: t.color('glacier-accent-9'), width: 1)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the bar's sheet is.
enum _BulkSheet { status, assignee, labels, due, priority, move }

/// The bar over the foot of the window while tickets are picked.
class BulkBar extends StatefulWidget {
  const BulkBar({super.key, required this.selection, required this.rows, required this.actions, required this.today, this.dayPicker, this.simple = false});

  final QuerySelection selection;

  /// The rows picked, as the query draws them now.
  final List<QueryRow> Function() rows;
  final BulkActions actions;
  final String today;
  final DayPicker? dayPicker;
  final bool simple;

  @override
  State<BulkBar> createState() => _BulkBarState();
}

class _BulkBarState extends State<BulkBar> {
  final OverlayPortalController _portal = OverlayPortalController();
  _BulkSheet? _sheet;
  bool _more = false;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(BulkBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.selection, widget.selection)) {
      old.selection.removeListener(_changed);
      widget.selection.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final up = widget.selection.any || _sheet != null;
    if (up && !_portal.isShowing) {
      _portal.show();
    } else if (!up && _portal.isShowing) {
      _portal.hide();
      _more = false;
    }
    if (mounted) setState(() {});
  }

  List<String> get _ids => [for (final row in widget.rows()) row.noteId];

  void _edit(BulkEdit edit) => unawaited(widget.actions.edit(_ids, edit));

  void _open(_BulkSheet sheet) {
    fireMotor(HapticKind.selection);
    setState(() => _sheet = sheet);
    _changed();
  }

  void _close() {
    setState(() => _sheet = null);
    _changed();
  }

  String get _record {
    final count = widget.selection.length;
    return count == 1 ? '1 ticket' : '$count tickets';
  }

  /// What every row picked says in [read], or null where they differ.
  String? _same(String? Function(QueryRow row) read) {
    final rows = widget.rows();
    if (rows.isEmpty) return null;
    final first = read(rows.first);
    return rows.every((row) => read(row) == first) ? first : null;
  }

  Widget? _sheetFor(_BulkSheet sheet) {
    final rows = widget.rows();
    if (rows.isEmpty) return null;
    switch (sheet) {
      case _BulkSheet.status:
        return FieldPicker(
          pick: StatusPick(value: null, workflow: rows.first.workflow),
          label: 'Status',
          record: _record,
          onClose: _close,
          onPick: (value) => _edit(SetField('status', value)),
        );
      case _BulkSheet.assignee:
        return FieldPicker(
          pick: PersonPick(value: null, people: widget.actions.people?.call() ?? const []),
          label: 'Assignee',
          record: _record,
          onClose: _close,
          onPick: (value) => _edit(SetField('assignee', value)),
        );
      case _BulkSheet.priority:
        return FieldPicker(pick: const PriorityPick(value: null), label: 'Priority', record: _record, onClose: _close, onPick: (value) => _edit(SetField('priority', value)));
      case _BulkSheet.due:
        return FieldPicker(
          pick: DayPick(value: _same((row) => row.due), today: widget.today),
          label: 'Due',
          record: _record,
          dayPicker: widget.dayPicker,
          onClose: _close,
          onPick: (value) => _edit(SetField('due', value)),
        );
      case _BulkSheet.labels:
        final all = <String>[], some = <String>[];
        for (final row in rows) {
          for (final label in row.labels) {
            if (all.any((each) => sameLabel(each, label)) || some.any((each) => sameLabel(each, label))) continue;
            (rows.every((other) => other.labels.any((each) => sameLabel(each, label))) ? all : some).add(label);
          }
        }
        return LabelPicker(
          chosen: all,
          some: some,
          known: widget.actions.labels(),
          colours: widget.actions.coloursOf?.call(rows.first.noteId) ?? const {},
          record: _record,
          onClose: _close,
          onToggle: (label, on) => _edit(on ? ChangeLabels(add: [label]) : ChangeLabels(remove: [label])),
        );
      case _BulkSheet.move:
        final notebooks = widget.actions.notebooks();
        return Sheet(
          label: 'Move to notebook',
          onClose: _close,
          children: [
            const SheetTitle(child: Text('Move to notebook')),
            SheetNote('$_record, each a page of the notebook picked.'),
            SheetGroup(
              children: [
                if (notebooks.isEmpty) const SheetRow(label: 'No notebooks yet.'),
                for (final notebook in notebooks)
                  SheetRow(
                    key: ValueKey('bulk-move:${notebook.id}'),
                    label: notebook.title,
                    onPress: () {
                      _close();
                      unawaited(widget.actions.move(_ids, notebook.id));
                    },
                  ),
              ],
            ),
          ],
        );
    }
  }

  Widget _bar(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs'), sm = t.fontSize('sm');
    final count = widget.selection.length;
    Widget button(String key, String label, LucideIcon icon, VoidCallback onPressed, {bool danger = false}) => GlacierPressable(
          key: ValueKey('bulk-$key'),
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
              decoration: BoxDecoration(color: state.hovered || state.pressed ? t.color('app-paper-2') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: t.space(1),
                children: [
                  AppIcon(icon, size: sm + 1, strokeWidth: 2.1, color: danger ? t.color('glacier-red-11') : t.color('app-ink-2')),
                  Text(label, maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: danger ? t.color('glacier-red-11') : t.color('app-ink'))),
                ],
              ),
            ),
          ),
        );
    final quiet = widget.simple && !_more;
    final buttons = <Widget>[
      button('status', 'Status', Lucide.circleCheck, () => _open(_BulkSheet.status)),
      button('assignee', 'Assignee', Lucide.userPlus, () => _open(_BulkSheet.assignee)),
      button('labels', 'Labels', Lucide.tag, () => _open(_BulkSheet.labels)),
      if (!quiet) ...[
        button('due', 'Due', Lucide.calendarDays, () => _open(_BulkSheet.due)),
        button('priority', 'Priority', Lucide.flag, () => _open(_BulkSheet.priority)),
        button('move', 'Move', Lucide.folderInput, () => _open(_BulkSheet.move)),
        button('delete', 'Delete', Lucide.trash2, () {
          final ids = _ids;
          widget.selection.clear();
          widget.actions.trash(ids);
        }, danger: true),
      ] else
        button('more', 'More', Lucide.ellipsis, () => setState(() => _more = true)),
    ];
    final safe = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: t.space(3),
      right: t.space(3),
      bottom: safe + t.space(4),
      child: Center(
        child: Semantics(
          container: true,
          label: '$count picked',
          child: Container(
            key: const ValueKey('bulk-bar'),
            constraints: BoxConstraints(maxWidth: t.lenOf('46rem')),
            padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
            decoration: BoxDecoration(
              color: t.color('app-paper'),
              border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
              borderRadius: BorderRadius.circular(t.radius('lg')),
              boxShadow: [BoxShadow(color: const Color(0x33000000), blurRadius: 18, offset: Offset(0, t.space(1)))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space(2)),
                  child: Text(count == 1 ? '1 picked' : '$count picked', key: const ValueKey('bulk-count'), style: tabular(pageText(t, xs, weight: 'semibold', color: t.color('app-ink-2')))),
                ),
                Flexible(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: buttons))),
                button('clear', 'Let go', Lucide.x, widget.selection.clear),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet == null ? null : _sheetFor(_sheet!);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Stack(
        children: [
          if (widget.selection.any && sheet == null)
            // Escape lets go of every ticket picked.
            CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.selection.clear},
              child: Focus(autofocus: true, child: Stack(children: [_bar(context)])),
            ),
          ?sheet,
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }
}
