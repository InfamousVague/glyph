/// The + beside the line (Matt: "Add a + button next to the line we're typing in, in the empty gutter padding and
/// add a menu to add things like geotag cards images videos and more"). It opens the list of things to add
/// (add_list.dart); where each goes is commands/inserts.dart. A port of `src/app/editor/insertPlus.ts`.
///
/// **Where.** The only empty room beside a line is the line's own start padding, the gutter every line already
/// leaves (`--app-gutter`), so the + sits there beside the caret's line: two strokes in the third ink, no ring,
/// since the app's ring is wider than the phone's gutter. It is drawn over the editor, not in the lines
/// (plus_layer.dart), so nothing in the lines moves. Its target is that line's gutter and nothing more: a tap in
/// another line's gutter, or on this line's first letter, still lands where it always did.
///
/// **When.** On an empty line only (Matt: "EMPTY LINES ONLY, on every platform, Mac hover included"); the rule and
/// its gates are plus_line.dart. It comes once the caret has rested there for [settleMs], so Enter, Enter in a run
/// never flickers it, and the first letter typed makes the line one with words and takes it away at once. A + that
/// had not finished arriving goes with no fade. Nothing about it waits for the keyboard to finish composing:
/// showing and hiding it never touches the lines. A note opened to be read shows nothing: the note screen never
/// focuses the editor on its own.
///
/// **The press.** A tap or a click turns the + into a × and asks for the list; the editor keeps its focus, so the
/// list is driven from the editor's keys (Up, Down, Enter, Escape, Left and Right). Any other key, a change or a
/// caret move closes it. Enter on the + itself, reached by the keyboard, opens the list with the focus in it.
///
/// A change that leaves the caret on the same empty line (a space, Enter ending an empty item) leaves the + where
/// it is, rather than blinking it out and back.
///
/// It sits level with the caret's row: the middle of the line's own row, inside the border and padding a quote's
/// last line or a callout's carries below its words. Beside a line with a lead (`- `, `2. `, `> `) it is drawn
/// smaller and at the gutter's outer edge, or it and the lead's own mark would read as one, "+-".
///
/// While shown, its line carries `cm-plusLine`, for the bookmark's edge in the same gutter to step aside; the class
/// is only changed while nothing is being composed.
///
/// What differs:
/// - **The plugin is the +'s mind, not its body.** The web's plugin made a `<button>` in the scroller and styled it
///   with a base theme; here [PlusView] keeps what the + is ([PlusView.look], [PlusView.lead], [PlusView.expanded],
///   the line) and plus_layer.dart draws it and tells it of a press ([PlusView.press]), a hover
///   ([PlusView.hover]) and its own focus ([PlusView.buttonFocus]). So `aria-label`, `aria-haspopup` and
///   `aria-expanded` are the drawn button's semantics, and the DOM's `pointerdown`/`mousedown`/`touchstart`/
///   `contextmenu` guards have no counterpart: a press on the + never reaches the editor because the + is above it.
/// - **A [PlusOpening] carries the +'s box as a function** ([PlusOpening.rect], in the screen's coordinates, asked
///   afresh each time) where the web's carried the button element; for `/` it is the caret's place.
/// - **Where the + goes is asked, not written**: [PlusView.measure] is `measureRow`, and the layer asks it as it
///   paints, so there is no `place`/`placeNow` and nothing can be painted where it last stood.
/// - `performance.now()` is a timer that ends the arrival, since a test's clock does not move a stopwatch.
/// - `prefersStill()` is the platform's own reduce-motion switch.
/// - **The lit row is kept, not announced**: `aria-controls` and `aria-activedescendant` on the editor's content
///   have no counterpart, so [plusMenuOf] holds what they said for whoever builds the editor's semantics.
/// - **`/` and the list's keys arrive as the view's `keyDown` handlers** (plugin.dart), which the input layer runs
///   before its keymap; [openPlusSlash] is the same door for an input layer that sees a hardware `/` another way.
/// - The bookmark's own rule (`.cm-bookmarked.cm-plusLine::before { opacity: 0 }`) is the bookmark's piece's to
///   write against the class.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderObject;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Offset, Rect, WidgetsBinding;

import '../../core/item_syntax.dart' show jsTrim;
import '../editor.dart';
import '../view/editor_view.dart';
import 'plus_line.dart';

/// How long the caret rests on an empty line before the + comes: long enough that Enter, Enter never flickers it,
/// and short enough to read as at once (`SETTLE_MS`).
const int settleMs = 150;

/// The + arriving, on typing's own arc; a keystroke inside it takes it at once (`IN_MS`).
const int plusInMs = 350;

/// The + leaving, a deleted letter's beat (`OUT_MS`).
const int plusOutMs = 140;

/// The keys the open list takes from the editor.
enum PlusKey { up, down, enter, escape, left, right }

/// How the list was opened: a fine pointer (the Mac), a finger, the keyboard on the + itself, or `/` typed on an
/// empty line (focus goes into the list).
enum PlusBy { pointer, touch, keyboard, slash }

/// The + pressed: where it is (the list is placed against its row), and how it was pressed.
class PlusOpening {
  const PlusOpening({required this.rect, required this.line, required this.by});

  /// The +'s box on the screen now, or for `/` the caret's place; null when it is not laid out.
  final Rect? Function() rect;

  /// The line the + was beside, counting from 1.
  final int line;
  final PlusBy by;

  @override
  String toString() => 'PlusOpening(line $line, ${by.name})';
}

/// What the screen answers the + with.
class PlusHooks {
  const PlusHooks({required this.allowed, required this.onOpen, required this.onClose, required this.onKey});

  /// Whether the screen allows a + now: asked on every look.
  final bool Function() allowed;
  final void Function(PlusOpening opening) onOpen;

  /// The list is to close: a key it does not take, a change, a caret move, the × pressed.
  final void Function() onClose;

  /// A key while the list is open from the editor: whether the list took it.
  final bool Function(PlusKey key) onKey;
}

/// The list open, as the editor knows it: its id and the row lit, for a screen reader.
class PlusMenu {
  const PlusMenu({required this.list, this.active});

  final String list;
  final String? active;

  @override
  bool operator ==(Object other) => other is PlusMenu && other.list == list && other.active == active;

  @override
  int get hashCode => Object.hash(list, active);
}

/// The screen's own reasons changed (an AI run started or ended, the view switched): the + looks again.
final StateEffectType<Object?> plusRecheck = StateEffect.define<Object?>();

/// The list opened or closed (null), or its lit row moved.
final StateEffectType<PlusMenu?> plusMenu = StateEffect.define<PlusMenu?>();

/// The line the + is shown beside, by its start, or null.
final StateEffectType<int?> _plusShown = StateEffect.define<int?>();

final StateField<PlusMenu?> _menuField = StateField.define<PlusMenu?>(
  create: (_) => null,
  update: (value, tr) {
    var next = value;
    for (final effect in tr.effects) {
      final menu = plusMenu.cast(effect);
      if (menu != null) next = menu.value;
    }
    return next;
  },
);

/// The list as the editor knows it, or null while it is closed: what the web wrote on the content as
/// `aria-controls` and `aria-activedescendant`.
PlusMenu? plusMenuOf(EditorState state) => state.fieldOrNull<PlusMenu?>(_menuField);

/// Whether the list is open, for a caller outside the plugin.
bool plusOpen(EditorViewLike view) => view.state.fieldOrNull<PlusMenu?>(_menuField) != null;

/// The list closed, as the editor knows it: the × turns back into a +. Before a row writes, so the write is not
/// read as a change made with the list open.
void closePlus(EditorViewLike view) {
  final plus = plusViewOf(view);
  if (plusOpen(view) && !(plus?.gone ?? false)) view.dispatch(TransactionSpec(effects: plusMenu.of(null)));
}

final StateField<int?> _shownField = StateField.define<int?>(
  create: (_) => null,
  update: (value, tr) {
    var next = value != null && tr.docChanged ? tr.changes.mapPos(value, -1) : value;
    for (final effect in tr.effects) {
      final shown = _plusShown.cast(effect);
      if (shown != null) next = shown.value;
    }
    return next;
  },
);

final Decoration _plusLineMark = Decoration.line(className: 'cm-plusLine');

/// The class on the +'s line, at its start however it moved.
final Extension _plusLineClass = EditorViewLike.decorations.compute(<Object>[_shownField], (state) {
  final pos = state.field<int?>(_shownField);
  if (pos == null) return Decoration.none;
  final at = pos < state.doc.length ? pos : state.doc.length;
  return Decoration.set(<Range<Decoration>>[_plusLineMark.range(state.doc.lineAt(at).from)]);
});

/// Where the + is, for the list to be placed against and the layer to draw it: in the coordinates asked for.
typedef PlusBox = ({double top, double height, double left});

/// How the + looks: not there, waiting out the settle, shown, or fading.
enum PlusLook { off, waiting, shown, leaving }

/// The plugin a state was given, for a caller that has only the view.
final Facet<ViewPlugin<PlusView>, ViewPlugin<PlusView>?> _plusPlugin = Facet.define<ViewPlugin<PlusView>, ViewPlugin<PlusView>?>(
  combine: (values) => values.isNotEmpty ? values[0] : null,
);

/// The +'s plugin in `view`, or null where the editor has none.
PlusView? plusViewOf(EditorViewLike view) {
  final plugin = view.state.facet(_plusPlugin);
  return plugin == null ? null : view.plugin(plugin);
}

/// `/` typed on an empty line with a hardware keyboard: opens the list as a command palette at the caret and
/// answers true, in which case the `/` is not to be written. For an input layer that hears the key itself; a key
/// that comes through the view's `keyDown` handlers is already answered.
bool openPlusSlash(EditorViewLike view) {
  if (plusOpen(view)) return false;
  return plusViewOf(view)?.openSlash() ?? false;
}

/// The row of line `number`: the line's box less the border and padding round its words, which a quote's last line
/// and a callout's carry below them. An empty line is one row, so this is the caret's row. In `ancestor`'s
/// coordinates, the screen's when null; null where the line is not drawn (`measureRow`).
PlusBox? measureRow(EditorViewLike view, int number, {RenderObject? ancestor}) {
  if (view is! EditorView || number > view.state.doc.lines) return null;
  final line = view.lineAt(view.state.doc.line(number).from);
  if (line == null || !line.attached || !line.hasSize) return null;
  final look = line.spec.look;
  final above = look.borderTop + look.paddingTop;
  final below = look.borderBottom + look.paddingBottom;
  final inner = line.size.height - above - below;
  final origin = line.localToGlobal(Offset.zero, ancestor: ancestor);
  return (top: origin.dy + (inner > 0 ? above : 0), height: inner > 0 ? inner : line.size.height, left: origin.dx);
}

/// The +, as the editor keeps it: CodeMirror's plugin value. The layer that draws it listens ([addListener]).
class PlusView extends PluginValue {
  PlusView(this.view, this.hooks) {
    _reconsider(false);
  }

  final EditorViewLike view;
  final PlusHooks hooks;

  final ChangeNotifier _changes = _Notifier();

  /// Called when anything the layer draws from may have changed.
  void addListener(VoidCallback listener) => _changes.addListener(listener);
  void removeListener(VoidCallback listener) => _changes.removeListener(listener);
  void _changed() => (_changes as _Notifier).tell();

  PlusLook _look = PlusLook.off;

  /// `data-state`.
  PlusLook get look => _look;

  /// The line the + is for, counting from 1.
  int? get line => _line;
  int? _line;

  /// Whether its line has a lead, which it keeps clear of (`data-lead`).
  bool get lead => _lead;
  bool _lead = false;

  /// Whether the list is open: the + is a × (`aria-expanded`).
  bool get expanded => _expanded;
  bool _expanded = false;

  /// Counts the times the + was taken away at once, with no fade (`data-cut`): the layer drops its transition when
  /// this moves.
  int get cuts => _cuts;
  int _cuts = 0;

  /// Whether the plugin has left its view.
  bool get gone => _gone;
  bool _gone = false;

  /// The gutter's width, which the layer says: the +'s own width.
  double gutter = 0;

  /// The drawn +'s box on the screen, which the layer says; without a layer, the row's own.
  Rect? Function()? buttonRect;

  bool _arriving = false;
  bool _buttonFocused = false;
  Timer? _settleTimer;
  Timer? _leaveTimer;
  Timer? _arriveTimer;

  /// Where a `/` menu is placed against, at the caret; forgotten when that menu closes.
  int? _slashAt;

  /// The +'s box on the screen: the layer's, or the row's with the gutter's width.
  Rect? _rect() {
    final own = buttonRect?.call();
    if (own != null) return own;
    final box = measure();
    return box == null ? null : Rect.fromLTWH(box.left, box.top, gutter, box.height);
  }

  /// The row the + sits beside, in `ancestor`'s coordinates (the screen's when null), or null when it has no line
  /// or the line is not drawn.
  PlusBox? measure({RenderObject? ancestor}) => _line == null ? null : measureRow(view, _line!, ancestor: ancestor);

  /// `/` typed on an empty line opens the list as a command palette at the caret (Matt: make the structured types
  /// "easier to create"). The `/` is not inserted; the list takes the focus into its filter, so what is typed next
  /// filters it rather than landing in the note. The caret's place is what the card is placed against, as the +
  /// is for the gutter menu.
  bool openSlash() {
    if (_gone || plusOpen(view) || !hooks.allowed()) return false;
    final state = view.state;
    final main = state.selection.main;
    if (!main.empty) return false;
    final line = state.doc.lineAt(main.head);
    if (jsTrim(line.text).isNotEmpty) return false;
    if (view.coordsAtPos(main.head) == null) return false;
    final at = main.head;
    _slashAt = at;
    hooks.onOpen(
      PlusOpening(
        rect: () {
          final coords = view.coordsAtPos(at < view.state.doc.length ? at : view.state.doc.length);
          if (coords == null) return null;
          return Rect.fromLTWH(coords.left, coords.top, 0, coords.height < 1 ? 1 : coords.height);
        },
        line: line.number,
        by: PlusBy.slash,
      ),
    );
    return true;
  }

  @override
  void update(ViewUpdate update) {
    final open = update.state.fieldOrNull<PlusMenu?>(_menuField) != null;
    if (!open && _slashAt != null) _slashAt = null;
    if (_expanded != open) {
      _expanded = open;
      _changed();
    }
    if (open) {
      // The list is up: the + stays, a ×, whatever the rules say. What the person does in the note closes it.
      if (update.docChanged || update.selectionSet) scheduleMicrotask(hooks.onClose);
      if (update.geometryChanged || update.viewportChanged) _changed();
      return;
    }
    final menuMoved = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(plusMenu) || effect.isOf(plusRecheck)));
    if (update.docChanged || update.selectionSet || update.focusChanged || menuMoved) {
      _reconsider(update.docChanged || update.selectionSet);
    } else if (update.geometryChanged || update.viewportChanged) {
      _changed();
    }
    _markLine();
  }

  @override
  void destroy() {
    _gone = true;
    _settleTimer?.cancel();
    _leaveTimer?.cancel();
    _arriveTimer?.cancel();
    _slashAt = null;
    _changes.dispose();
  }

  /// The line the + belongs beside now, by the rules (plus_line.dart).
  Line? _target() {
    final focused = view.hasFocus || _buttonFocused;
    return plusLine(view.state, PlusContext(focused: focused, editable: view.state.facet(EditorViewLike.editable), allowed: hooks.allowed()));
  }

  /// Looks again: the + stays where it is, goes, or waits to come beside another line.
  void _reconsider(bool changed) {
    if (_gone || plusOpen(view)) return;
    _settleTimer?.cancel();
    final line = _target();
    if (_look == PlusLook.shown) {
      // Still beside the same empty line, however it changed: it stays, rather than blinking out and back.
      if (line != null && line.number == _line) {
        _setLead(line.text);
        _changed();
        return;
      }
      _out(changed);
    }
    _line = line?.number;
    _setLead(line?.text ?? '');
    if (line == null) {
      if (_look != PlusLook.leaving) _set(PlusLook.off);
      return;
    }
    if (_look != PlusLook.leaving) _set(PlusLook.waiting);
    _settleTimer = Timer(const Duration(milliseconds: settleMs), _show);
  }

  void _show() {
    if (_gone) return;
    _settleTimer?.cancel();
    _leaveTimer?.cancel();
    final line = _target();
    if (line == null || line.number != _line) {
      _reconsider(false);
      return;
    }
    _setLead(line.text);
    _set(PlusLook.shown);
    _arriving = true;
    _arriveTimer?.cancel();
    _arriveTimer = Timer(const Duration(milliseconds: plusInMs), () => _arriving = false);
    _markLine();
  }

  void _setLead(String text) {
    final lead = jsTrim(text).isNotEmpty;
    if (lead == _lead) return;
    _lead = lead;
    _changed();
  }

  /// The + going: on a deleted letter's beat, or at once when it had not finished arriving or motion is asked to be
  /// still.
  void _out(bool changed) {
    _leaveTimer?.cancel();
    if ((changed && _arriving) || _prefersStill()) {
      _cuts += 1;
      _set(PlusLook.waiting);
      return;
    }
    _set(PlusLook.leaving);
    _leaveTimer = Timer(const Duration(milliseconds: plusOutMs), () {
      if (_look != PlusLook.leaving) return;
      _set(_line == null ? PlusLook.off : PlusLook.waiting);
    });
  }

  void _set(PlusLook look) {
    _look = look;
    _changed();
    _markLine();
  }

  /// The +'s line carries `cm-plusLine` while the + is shown there, changed only while nothing is composed.
  void _markLine() {
    scheduleMicrotask(() {
      if (_gone || view.composing) return;
      final state = view.state;
      final want = _look == PlusLook.shown && _line != null && _line! <= state.doc.lines ? state.doc.line(_line!).from : null;
      final now = state.fieldOrNull<int?>(_shownField);
      final nowLine = now == null ? null : state.doc.lineAt(now < state.doc.length ? now : state.doc.length).from;
      if (nowLine != want) view.dispatch(TransactionSpec(effects: _plusShown.of(want)));
    });
  }

  /// The + pressed, and how: it opens the list, or as a × closes it. `PlusBy.keyboard` is Enter or Space on the +
  /// itself.
  void press(PlusBy by) {
    if (_gone) return;
    if (plusOpen(view)) {
      hooks.onClose();
      return;
    }
    if (_look == PlusLook.waiting && by == PlusBy.keyboard) _show();
    if (_look != PlusLook.shown || _line == null) return;
    hooks.onOpen(PlusOpening(rect: _rect, line: _line!, by: by));
  }

  /// The drawn + took or lost the keyboard's focus. Tab reaches it while it waits: taking the focus shows it at
  /// once.
  void buttonFocus(bool focused) {
    if (_gone) return;
    _buttonFocused = focused;
    if (focused) {
      if (_look == PlusLook.waiting) _show();
    } else {
      scheduleMicrotask(() => _reconsider(false));
    }
  }

  /// A pointer moved over the editor: a fine one over the +'s place while it waits brings it at once.
  void hover(PointerDeviceKind kind, Offset global) {
    if (_gone || kind != PointerDeviceKind.mouse || _look != PlusLook.waiting) return;
    final box = _rect();
    if (box != null && global.dx >= box.left && global.dx <= box.right && global.dy >= box.top && global.dy <= box.bottom) _show();
  }

  bool _prefersStill() => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
}

class _Notifier extends ChangeNotifier {
  bool _disposed = false;

  void tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

PlusKey? _keyOf(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return PlusKey.up;
  if (key == LogicalKeyboardKey.arrowDown) return PlusKey.down;
  if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return PlusKey.enter;
  if (key == LogicalKeyboardKey.escape) return PlusKey.escape;
  if (key == LogicalKeyboardKey.arrowLeft) return PlusKey.left;
  if (key == LogicalKeyboardKey.arrowRight) return PlusKey.right;
  return null;
}

bool _isModifier(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.shift ||
    key == LogicalKeyboardKey.shiftLeft ||
    key == LogicalKeyboardKey.shiftRight ||
    key == LogicalKeyboardKey.control ||
    key == LogicalKeyboardKey.controlLeft ||
    key == LogicalKeyboardKey.controlRight ||
    key == LogicalKeyboardKey.alt ||
    key == LogicalKeyboardKey.altLeft ||
    key == LogicalKeyboardKey.altRight ||
    key == LogicalKeyboardKey.meta ||
    key == LogicalKeyboardKey.metaLeft ||
    key == LogicalKeyboardKey.metaRight ||
    key == LogicalKeyboardKey.capsLock ||
    key == LogicalKeyboardKey.fn;

/// While the list is open from the editor, its keys go to it; any other key closes it and does what it always
/// does. Answers whether the key was taken (`menuKeys`): exposed for an input layer that routes keys itself.
bool plusMenuKey(PlusHooks hooks, KeyEvent event, EditorViewLike view) {
  if (event is KeyUpEvent || !plusOpen(view)) return false;
  final key = _keyOf(event.logicalKey);
  if (key != null && hooks.onKey(key)) return true;
  if (_isModifier(event.logicalKey)) return false;
  hooks.onClose();
  return false;
}

/// Whether a key is a plain `/`: no Control, Alt or Command with it, and nothing being composed.
bool _isSlash(KeyEvent event, EditorViewLike view) {
  if (event is! KeyDownEvent) return false;
  if (event.character != '/' && !(event.character == null && event.logicalKey == LogicalKeyboardKey.slash)) return false;
  final held = HardwareKeyboard.instance;
  return !held.isMetaPressed && !held.isControlPressed && !held.isAltPressed && !view.composing;
}

/// The + beside an empty line, and what opens its list: only the note screen installs it.
Extension insertPlus(PlusHooks hooks) {
  final plugin = ViewPlugin.fromClass<PlusView>((view) => PlusView(view, hooks));
  return Extension.list(<Extension>[
    _menuField,
    _shownField,
    _plusLineClass,
    _plusPlugin.of(plugin),
    plugin,
    // While the list is open its keys are the list's, before any other handler.
    Prec.highest(EditorViewLike.eventHandlers(EditorEventHandlers(keyDown: (event, view) => plusMenuKey(hooks, event, view)))),
    // `/` typed on an empty line opens the list as a command palette at the caret; the plugin does the opening.
    Prec.highest(
      EditorViewLike.eventHandlers(
        EditorEventHandlers(
          keyDown: (event, view) {
            if (!_isSlash(event, view) || plusOpen(view)) return false;
            return view.plugin(plugin)?.openSlash() ?? false;
          },
        ),
      ),
    ),
  ]);
}
