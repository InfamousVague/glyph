/// Swiping a list item left in the note hands it to a plugin's item action (lib/plugins/types.dart `ItemAction`):
/// the Notion plugin's sends it as a task. Ports `src/app/editor/swipeItems.ts`.
///
/// Matt chose all three ways for a list item to become a task: saying it, swiping the item, and sending a whole
/// list. This is the swipe. When a switched-on plugin offers an action on this note, a to-do or bullet line that is
/// not a link yet can be dragged left: the line follows the finger, a tile behind it grows with the action's word,
/// and letting go past the point where it counts runs it (the tile says so until it is done; the Notion action
/// makes the line's words a link to the task). Short of it, the line goes back.
///
/// Only a mostly horizontal drag that starts on such a line counts; anything else is left to the editor, so typing,
/// selecting and scrolling are as they were.
///
/// What differs:
/// - The page moved the line's element with a transform and kept a tile of its own in the scroller. Here both are
///   decorations made from one field of the state ([swipeOf]): the line is shifted by its margins (as far out at
///   the start as in at the end, so its words wrap where they did), and the tile is an inline widget at the line's
///   end that draws over the line's own box, at its far edge.
/// - The line does not ease back over 200ms when let go: it is back at once. The view has nothing that moves a
///   line between two layouts.
/// - A press is found on a line by the view's own hit test, where the page asked the event's target for its
///   `.cm-line`. `pointerdown` with `button === 0` is a first button or a touch.
/// - `swipeItemTheme` is the tile's own widget and one rule for the line; it comes with [swipeItemAction], and the
///   name is kept for whoever adds it as Editor.tsx does.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/detent_feel.dart';
import '../../core/item_links.dart';
import '../editor.dart';
import '../input/felt.dart' show fireMicroTick;
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
import '../view/line.dart' show RenderEditorLine;

/// How far a finger moves before the drag is one way or the other (`INTENT_PX`).
const double swipeIntentPx = 12;

/// How much of the line's width counts (`ARM_FRACTION`).
const double swipeArmFraction = 0.3;

/// What a swipe runs (`SwipeAction`).
class SwipeAction {
  const SwipeAction({required this.label, required this.busyLabel, required this.run});

  /// The tile's word while dragged, and while it runs.
  final String label;
  final String busyLabel;

  /// Runs on the item's words; resolves when it is done.
  final Future<void> Function(String text) run;
}

/// A swipe as it is drawn: the line (where it starts), how far it is moved (`translateX`, nothing or less), and
/// the tile: how wide, of what width that is a share, and its word. No tile while `reach` is null.
@immutable
class SwipeDrawn {
  const SwipeDrawn({required this.line, this.dx = 0, this.reach, this.width = 1, this.word = ''});

  final int line;
  final double dx;
  final double? reach;
  final double width;
  final String word;

  /// How far along to the point where it counts (`--progress`).
  double get progress {
    final along = (reach ?? 0) / (width * swipeArmFraction);
    return along > 1 ? 1 : along;
  }

  /// `data-armed`.
  bool get armed => progress >= 1;

  @override
  bool operator ==(Object other) => other is SwipeDrawn && other.line == line && other.dx == dx && other.reach == reach && other.width == width && other.word == word;

  @override
  int get hashCode => Object.hash(line, dx, reach, width, word);
}

final StateEffectType<SwipeDrawn?> _drawn = StateEffect.define<SwipeDrawn?>();

final StateField<SwipeDrawn?> _swipe = StateField.define<SwipeDrawn?>(
  create: (_) => null,
  update: (value, tr) {
    var next = value;
    if (next != null && tr.docChanged) {
      final at = tr.state.doc.lineAt(tr.changes.mapPos(next.line, -1)).from;
      if (at != next.line) next = SwipeDrawn(line: at, dx: next.dx, reach: next.reach, width: next.width, word: next.word);
    }
    for (final effect in tr.effects) {
      if (effect.isOf(_drawn)) next = effect.value as SwipeDrawn?;
    }
    return next;
  },
  compare: (a, b) => a == b,
  provide: (field) => EditorViewLike.decorations.from<SwipeDrawn?>(field, _decorate),
);

DecorationSet _decorate(SwipeDrawn? swipe) {
  if (swipe == null) return Decoration.none;
  final ranges = <Range<Decoration>>[];
  if (swipe.dx != 0) ranges.add(Decoration.line(className: 'cm-swipeLine', attributes: <String, String>{'style': '--swipe: ${swipe.dx.toStringAsFixed(2)}px'}).range(swipe.line));
  return Decoration.set(ranges, true);
}

/// The swipe being drawn in `state`, or null.
SwipeDrawn? swipeOf(EditorState state) => state.fieldOrNull<SwipeDrawn?>(_swipe);

/// The tile behind the line, filling toward the point where it counts, with the action's word. In the page's ink:
/// grey while dragged, ink once it counts.
class SwipeTileWidget extends EditorWidget {
  const SwipeTileWidget(this.swipe);

  final SwipeDrawn swipe;

  @override
  bool eq(SwipeTileWidget other) => other.swipe == swipe;

  @override
  bool takesPointer(_) => false;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // '.cm-swipeItem': { position: 'absolute', display: 'flex', alignItems: 'center', justifyContent: 'center',
    //   overflow: 'hidden', whiteSpace: 'nowrap', fontSize: '0.75rem', fontWeight: '700', letterSpacing: '0.06em',
    //   textTransform: 'uppercase', borderRadius: '10px', color: 'var(--glacier-text-muted)',
    //   background: 'var(--app-wash, var(--glacier-surface-sunken))',
    //   opacity: 'calc(0.4 + var(--progress, 0) * 0.6)', pointerEvents: 'none', zIndex: '2' }
    // '.cm-swipeItem[data-armed]': { color: 'var(--app-paper, var(--glacier-bg))',
    //   background: 'var(--app-ink, var(--glacier-text))' }
    // `letterSpacing` is not drawn: the page computes `letter-spacing: normal` for the tile (measured with the
    // rest, 2026-10-08), so its letters stand as close as the face sets them, and so do these.
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    final face = look?.line(LookElement(null)).base.style ?? t.textAt(12, mono: true);
    final size = t.lenOf('0.75rem');
    final armed = swipe.armed;
    return ExcludeSemantics(
      child: SwipeTile(
        reach: swipe.reach ?? 0,
        word: swipe.word.toUpperCase(),
        style: face.copyWith(fontSize: size, fontWeight: FontWeight.w700, color: armed ? t.color('app-paper') : t.color('glacier-text-muted'), decoration: TextDecoration.none, height: 1),
        ground: armed ? t.color('app-ink') : t.color('app-wash'),
        opacity: 0.4 + swipe.progress * 0.6,
      ),
    );
  }
}

/// The tile's box: it takes no room where it is built (the end of its line) and paints over the line's own box,
/// from the far edge in.
class SwipeTile extends LeafRenderObjectWidget {
  const SwipeTile({super.key, required this.reach, required this.word, required this.style, required this.ground, required this.opacity});

  final double reach;
  final String word;
  final TextStyle style;
  final Color ground;
  final double opacity;

  @override
  RenderSwipeTile createRenderObject(BuildContext context) => RenderSwipeTile(this);

  @override
  void updateRenderObject(BuildContext context, RenderSwipeTile renderObject) => renderObject.tile = this;
}

class RenderSwipeTile extends RenderBox {
  RenderSwipeTile(this._tile);

  SwipeTile _tile;
  set tile(SwipeTile value) {
    _tile = value;
    markNeedsPaint();
  }

  SwipeTile get tile => _tile;

  @override
  void performLayout() => size = constraints.constrain(Size.zero);

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size.zero);

  @override
  bool hitTestSelf(Offset position) => false;

  RenderEditorLine? get _line {
    for (RenderObject? above = parent; above != null; above = above.parent) {
      if (above is RenderEditorLine) return above;
    }
    return null;
  }

  /// Where the tile is drawn, in this box's own coordinates: the line's box, `right: 0`, `reach` wide. The line is
  /// moved by its margins, and the tile stays at the page's edge.
  Rect? get tileRect {
    final line = _line;
    if (line == null || !line.hasSize) return null;
    final origin = globalToLocal(line.localToGlobal(Offset.zero));
    final reach = _tile.reach < 0 ? 0.0 : _tile.reach;
    return Rect.fromLTWH(origin.dx + line.size.width - reach, origin.dy, reach, line.size.height);
  }

  /// How wide the word is set, for a test to hold against the page's.
  double get wordWidth {
    final painter = TextPainter(text: TextSpan(text: _tile.word, style: _tile.style), textDirection: TextDirection.ltr, maxLines: 1, textScaler: TextScaler.noScaling)..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// The same, on the screen.
  Rect? get globalTileRect {
    final rect = tileRect;
    return rect?.shift(localToGlobal(Offset.zero));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = tileRect?.shift(offset);
    if (rect == null || rect.width <= 0) return;
    final canvas = context.canvas;
    final alpha = (_tile.opacity.clamp(0, 1) * 255).round();
    canvas.saveLayer(rect, Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
    final round = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas
      ..clipRRect(round)
      ..drawRRect(round, Paint()..color = _tile.ground);
    final painter = TextPainter(text: TextSpan(text: _tile.word, style: _tile.style), textDirection: TextDirection.ltr, maxLines: 1, textScaler: TextScaler.noScaling)..layout();
    // Centred, its trailing letter-space with it, as the page centres the run.
    painter.paint(canvas, Offset(rect.left + (rect.width - painter.width) / 2, rect.top + (rect.height - painter.height) / 2));
    painter.dispose();
    canvas.restore();
  }
}

class _Gesture {
  _Gesture({required this.id, required this.x, required this.y, required this.line, required this.text, required this.action, required this.width});

  final int id;
  final double x;
  final double y;

  /// Where the line starts.
  final int line;
  final String text;
  final SwipeAction action;
  final double width;
  String intent = 'undecided';
  double dx = 0;
  final Approaching approaching = Approaching();
}

class _Swipes extends PluginValue {
  _Swipes(this.view, this.action);

  final EditorViewLike view;
  final SwipeAction? Function() action;
  _Gesture? _gesture;
  bool _gone = false;

  @override
  void destroy() => _gone = true;

  void _draw(SwipeDrawn? drawn) {
    if (_gone) return;
    if (drawn == null && view.state.fieldOrNull<SwipeDrawn?>(_swipe) == null) return;
    view.dispatch(TransactionSpec(effects: _drawn.of(drawn)));
  }

  /// The line under a press: its start, and how wide it is drawn.
  ({int from, double width})? _lineUnder(Offset at) {
    final v = view;
    if (v is EditorView) {
      final hit = v.hitAt(at);
      final line = hit?.line;
      if (hit == null || !hit.inside || line == null) return null;
      return (from: v.state.doc.lineAt(hit.pos).from, width: line.size.width > 0 ? line.size.width : 1);
    }
    final pos = view.posAtCoords(at);
    return pos == null ? null : (from: view.state.doc.lineAt(pos).from, width: 1);
  }

  bool down(PointerDownEvent event) {
    final primary = event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryMouseButton;
    final offered = primary ? action() : null;
    if (offered == null) return false;
    final under = _lineUnder(event.position);
    if (under == null) return false;
    final docLine = view.state.doc.lineAt(under.from);
    final item = itemAt(docLine.text, docLine.number);
    if (item == null) return false;
    _gesture = _Gesture(id: event.pointer, x: event.position.dx, y: event.position.dy, line: docLine.from, text: item.text, action: offered, width: under.width);
    return false;
  }

  bool move(PointerMoveEvent event) {
    final g = _gesture;
    if (g == null || g.id != event.pointer) return false;
    final dx = event.position.dx - g.x, dy = event.position.dy - g.y;
    if (g.intent == 'undecided') {
      if (dx.abs() < swipeIntentPx && dy.abs() < swipeIntentPx) return false;
      g.intent = dx < 0 && dx.abs() > dy.abs() * 1.5 ? 'horizontal' : 'vertical';
      if (g.intent == 'vertical') {
        _gesture = null;
        return false;
      }
    }
    final wasArmed = -g.dx >= g.width * swipeArmFraction;
    g.dx = dx < 0 ? dx : 0;
    final distance = -g.dx / g.width;
    // Felt coming, then felt arriving; backing out of it, the lightest tick (lib/core/detent_feel.dart).
    if (tickNow(g.approaching, const <double>[swipeArmFraction], distance, event.timeStamp.inMicroseconds / 1000)) fireMicroTick();
    final isArmed = distance >= swipeArmFraction;
    if (isArmed != wasArmed) haptic(isArmed ? HapticKind.medium : HapticKind.selection);
    _draw(SwipeDrawn(line: _lineNow(g), dx: g.dx, reach: -g.dx, width: g.width, word: g.action.label));
    // `event.preventDefault()`: the drag is the swipe's.
    return true;
  }

  /// Where the gesture's line starts now: the field carries it through changes of the note.
  int _lineNow(_Gesture g) => view.state.fieldOrNull<SwipeDrawn?>(_swipe)?.line ?? g.line;

  bool up(PointerUpEvent event) {
    final g = _gesture;
    if (g == null || g.id != event.pointer) return false;
    _gesture = null;
    if (g.intent != 'horizontal') return false;
    final armed = -g.dx >= g.width * swipeArmFraction;
    if (!armed) {
      _draw(null);
      return true;
    }
    _draw(SwipeDrawn(line: _lineNow(g), reach: g.width * swipeArmFraction, width: g.width, word: g.action.busyLabel));
    unawaited(Future<void>.sync(() => g.action.run(g.text)).catchError((Object _) {}).whenComplete(() => _draw(null)));
    return true;
  }

  bool cancel(PointerCancelEvent event) {
    _gesture = null;
    _draw(null);
    return false;
  }
}

// '.cm-scroller': { position: 'relative' } has no counterpart. The line under the finger:
// `g.line.style.transform = translateX(${g.dx}px)`.
final LookSheet _theme = LookSheet('editor/swipeItems.ts', <LookRule>[
  LookRule('cm-swipeLine', classes: 4, (p, e) {
    final by = p.element?.styleLength('--swipe') ?? 0;
    p
      ..marginStart = p.marginStart + by
      ..marginEnd = p.marginEnd - by;
  }),
]);

/// The tile's look and the moved line's (`swipeItemTheme`).
final Extension swipeItemTheme = baseTheme(_theme);

DecorationSet _tile(EditorState state) {
  final swipe = state.fieldOrNull<SwipeDrawn?>(_swipe);
  if (swipe == null || swipe.reach == null || swipe.line > state.doc.length) return Decoration.none;
  final line = state.doc.lineAt(swipe.line);
  return Decoration.set(<Range<Decoration>>[Decoration.widget(widget: SwipeTileWidget(swipe), side: 1).range(line.to)]);
}

final Extension _tiles = EditorViewLike.decorations.of((EditorViewLike view) => _tile(view.state));

/// A list item not linked yet follows a finger dragged left, and letting go past the point where it counts runs
/// `action`'s answer on the item's words. `action` is the action on this note right now, or null for none: read
/// when a swipe starts.
Extension swipeItemAction({required SwipeAction? Function() action}) {
  late final ViewPlugin<_Swipes> plugin;
  plugin = ViewPlugin.define<_Swipes>(
    (view) => _Swipes(view, action),
    eventHandlers: EditorEventHandlers(
      pointerDown: (event, view) => view.plugin(plugin)?.down(event) ?? false,
      pointerMove: (event, view) => view.plugin(plugin)?.move(event) ?? false,
      pointerUp: (event, view) => view.plugin(plugin)?.up(event) ?? false,
      pointerCancel: (event, view) => view.plugin(plugin)?.cancel(event) ?? false,
    ),
  );
  return Extension.list(<Extension>[_swipe, _tiles, plugin, swipeItemTheme]);
}
