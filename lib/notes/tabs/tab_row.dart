import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/tabs.dart';

/// Which shape a tab takes (`data-shape`, notes/NoteTabs.tsx): a tab on a line (Classic and the Ledger), a word on an
/// index line (the Masthead), or a capsule (the Islands).
enum TabShape { tab, indexLine, capsule }

/// What a child of the row is: Home pinned at its start (the Ledger), a tab, a group's chip, or the + at its end.
enum RowKind { homeTab, tab, chip, newTab }

/// How long a press is held before a tab is picked up (`HOLD_MS`, core/gestures.ts).
const Duration holdTime = Duration(milliseconds: 220);

/// One thing in the row, as notes/note_tabs.dart builds it, with what the row needs to know of it to lay it out and
/// to say what a dragged tab is over.
@immutable
class TabRowEntry {
  const TabRowEntry({required this.kind, this.id, this.groupId, this.count = 1, this.collapsed = false, this.center = false, this.marginStart = 0, this.marginEnd = 0, required this.child});

  final RowKind kind;

  /// A tab's note, or a chip's group.
  final String? id;

  /// The group a tab is in.
  final String? groupId;

  /// How many tabs a chip stands for.
  final int count;

  /// A chip folded shut: it is its tabs in the order.
  final bool collapsed;

  /// `align-self: center`: a chip and the +, where a tab stands on the row's line.
  final bool center;
  final double marginStart;
  final double marginEnd;
  final Widget child;
}

/// The row of tabs (`.tabs`, notes/NoteTabs.module.css), with what is drawn around its tabs rather than in them and
/// what a finger or a mouse does on it: the web's `tabRow` of notes/NoteTabs.tsx with notes/useTabOutline.ts and
/// notes/useTabDrag.ts.
///
/// - **The line and the outline.** The baseline the tabs stand on runs the row's length with a gap under the tab
///   being read, whose outline stops a curve's height above the line and whose curves carry each side on down to
///   it. The outline slides from tab to tab when another is opened, taking on its width as it goes, the gap in the
///   line with it. The Masthead's index line is an unbroken rule; a capsule stands on nothing.
/// - **The ends.** An end with tabs past it fades, the left only once the row has been scrolled from its start.
/// - **The gesture.** Pressed and held, a tab is picked up and carried along the row, into a group or out of one;
///   pulled sideways first, the row pans, and a flick carries on and slows to a stop (notes/tabDrag.ts `coasted`);
///   held under a finger and let go where it was, the tab's menu opens ([onHeld]). A mouse's right-click opens it
///   too. A wheel turned up or down moves the row sideways (core/scrollSideways.ts).
///
/// Differs from the web:
/// - The page panned the row by hand, because a finger on it might be about to pick a tab up; the gesture arena
///   tells the two apart here, so the row is a scroller of the platform's own, which a sideways pull takes over
///   after the platform's touch slop rather than 6px. A flick still slows by `coasted`.
/// - The smoke at a fading end (art/wispSides.ts) is not ported: the fade is the whole of it, as on the web's
///   desktop.
/// - The outline's line, its sides and its curves are one stroked path where the page drew a gradient, a border and
///   two radial gradients that met.
/// - The page's row clipped whatever stood above it, which in the Ledger cut the top of the outline off a tab that
///   wears a workspace's pill (a pixel taller than the row is made). Nothing is clipped above the row here.
/// - Motion's speed in Settings (`motionScale`) is not read: the slide is 220ms.
class TabRow extends StatefulWidget {
  const TabRow({
    super.key,
    required this.shape,
    required this.entries,
    required this.activeId,
    this.groups = TabGroups.none,
    this.onMove,
    this.onGroups,
    this.onHeld,
    required this.gap,
    required this.paddingStart,
    required this.paddingEnd,
    required this.minHeight,
    this.lineColor,
    this.fade = 12,
    this.clipRadius,
    this.frame,
    this.closeKeys = const {},
  });

  final TabShape shape;
  final List<TabRowEntry> entries;

  /// The tab being read, or empty.
  final String activeId;
  final TabGroups groups;

  /// A tab moved to `to` in the order as drawn; `grouped` says the drag has settled its group already. Absent, no
  /// tab moves.
  final void Function(String id, int to, {bool grouped})? onMove;

  /// Absent, there are no groups to drag into, and no menu for a hold to open.
  final ValueChanged<TabGroups>? onGroups;

  /// A tab's menu asked for: a finger held on it and let go where it was, or a mouse's right-click.
  final ValueChanged<String>? onHeld;

  final double gap;
  final double paddingStart;
  final double paddingEnd;

  /// `min-block-size`: a tab's height, tabs or none, so a group's chip does not drop when every tab is folded into it.
  final double minHeight;

  /// The baseline's colour: `--tab-line`, or the Masthead's `--app-rule`. Null and the row stands on nothing.
  final Color? lineColor;

  /// How far an open end fades (`--tab-fade-start`, `--tab-fade-end`): 12px, or 32px under a mouse.
  final double fade;

  /// The Islands' row is a capsule of its own: what runs past it is cut to its round.
  final double? clipRadius;

  /// What the row is drawn in, where it has a ground of its own: the Islands' capsule of glass. It is inside the
  /// fade, as the page's mask was on the capsule itself: an end with tabs past it fades the glass and its hairline
  /// with the tabs, and the capsule's shadow is not cast while either end is open.
  final Widget Function(Widget row)? frame;

  /// Each tab's cross, by the tab's id: a press that lands on it never picks the tab up.
  final Map<String, GlobalKey> closeKeys;

  @override
  State<TabRow> createState() => _TabRowState();
}

class _TabRowState extends State<TabRow> with TickerProviderStateMixin {
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'tab row body');
  final ScrollController _scroll = ScrollController();
  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));

  /// Where the finger carrying a tab is, across the window; null while a tab is held and has not been moved.
  final ValueNotifier<double?> _dragX = ValueNotifier(null);

  String? _slideFrom;
  String? _moving;
  String? _settling;
  double _settleFrom = 0;
  double _grabbed = 0;
  double _heldAt = 0;
  bool _travelled = false;
  PointerDeviceKind _kind = PointerDeviceKind.touch;

  /// The groups as they were when the tab was picked up, and the group it is in now. Each move says where it belongs
  /// from these, not from the last move's answer: a tab dragged out of a group of one empties it, and an empty group
  /// goes, so worked out move by move, passing over the next tab would lose the group for good.
  TabGroups _base = TabGroups.none;
  String? _joined;
  String? _dropInto;

  bool _fadeStart = false, _fadeEnd = false;

  RenderTabRowBody? get _body => _bodyKey.currentContext?.findRenderObject() as RenderTabRowBody?;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_mark);
    SchedulerBinding.instance.addPostFrameCallback((_) => _mark());
  }

  @override
  void didUpdateWidget(TabRow old) {
    super.didUpdateWidget(old);
    // The tab being read slides to the one opened. Nothing slides from a tab that has closed, to or from the home
    // page, while a tab is being dragged, or for someone who has asked their phone for less motion.
    final from = old.activeId, to = widget.activeId;
    if (from != to) {
      final has = {for (final e in widget.entries) if (e.kind == RowKind.tab) e.id};
      if (from.isNotEmpty && to.isNotEmpty && _moving == null && has.contains(from) && has.contains(to) && !context.tokens.reducedMotion) {
        _slideFrom = from;
        _slide.forward(from: 0);
      } else {
        _slideFrom = null;
        _slide.value = 1;
      }
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _mark());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _slide.dispose();
    _settle.dispose();
    _dragX.dispose();
    super.dispose();
  }

  /// Which ends of the row have tabs past them: the right while there are, the left once the row has been scrolled
  /// away from its start and never at the start itself.
  void _mark() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final past = position.maxScrollExtent;
    final start = past > 1 && position.pixels > 1;
    final end = past > 1 && position.pixels < past - 1;
    if (start == _fadeStart && end == _fadeEnd) return;
    setState(() {
      _fadeStart = start;
      _fadeEnd = end;
    });
  }

  // ---- the gesture (notes/useTabDrag.ts) -----------------------------------------------------------------------------

  bool _onCross(String id, Offset at) {
    final box = widget.closeKeys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(at);
  }

  void _takeHold(String id, Offset at) {
    final body = _body;
    final home = body?.globalLeftOf(id);
    // The cross is not a handle: pressing it means close, whatever the finger does next.
    if (widget.onMove == null || body == null || home == null || _onCross(id, at)) return;
    _settle.stop();
    _settling = null;
    _base = widget.groups;
    _joined = _base.of[id];
    _dropInto = null;
    _travelled = false;
    _heldAt = at.dx;
    // Where along the tab it was taken hold of, so it hangs off the finger at the point it was picked up.
    _grabbed = at.dx - home;
    _dragX.value = null;
    setState(() => _moving = id);
  }

  void _along(String id, Offset at) {
    final body = _body;
    final onMove = widget.onMove;
    if (_moving != id || body == null || onMove == null) return;
    if (!_travelled && (at.dx - _heldAt).abs() < 1) return;
    _travelled = true;
    final into = groupAt(body.spotsOf(id), at.dx);
    _dropInto = null;
    if (into.settled && into.group != _joined) {
      final group = into.group;
      // A folded group takes the tab only when it is let go: joining it hides the tab, and a tab hidden under the
      // finger cannot be carried on.
      final folded = group != null && _base.list.any((g) => g.id == group && g.collapsed);
      if (folded) {
        _dropInto = group;
      } else {
        _joined = group;
        widget.onGroups?.call(group != null ? joinGroup(_base, id, group) : leaveGroup(_base, id));
      }
    }
    onMove(id, placeAt(body.stopsOf(id), at.dx), grouped: true);
    // After the row has been told where the tab belongs: the tab follows the finger even between two places.
    _dragX.value = at.dx;
  }

  void _letGo(String id) {
    if (_moving != id) return;
    final dropInto = _dropInto;
    if (dropInto != null) widget.onGroups?.call(joinGroup(_base, id, dropInto));
    // Let go and it settles into its place, rather than snapping there.
    final from = _body?.carriedBy(id) ?? 0;
    if (_travelled && from != 0 && !context.tokens.reducedMotion) {
      _settling = id;
      _settleFrom = from;
      _settle.forward(from: 0);
    }
    // Held in one place and let go: the menu a mouse gets from a right-click.
    final menu = !_travelled && _kind != PointerDeviceKind.mouse && widget.onGroups != null;
    _dragX.value = null;
    _dropInto = null;
    setState(() => _moving = null);
    if (menu) {
      // One tick for the press, however long it was held (core/haptics.ts `tickHeld`).
      HapticsProvider.of(context)(HapticKind.selection);
      widget.onHeld?.call(id);
    }
  }

  void _rightClick(String id) {
    if (_kind != PointerDeviceKind.mouse || widget.onGroups == null) return;
    widget.onHeld?.call(id);
  }

  /// A wheel turned up or down moves the row sideways (core/scrollSideways.ts).
  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    final delta = event.scrollDelta;
    if (delta.dx.abs() >= delta.dy.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      position.jumpTo((position.pixels + delta.dy).clamp(position.minScrollExtent, position.maxScrollExtent));
    });
  }

  Widget _held(TabRowEntry entry) {
    final id = entry.id!;
    return Listener(
      onPointerDown: (event) => _kind = event.kind,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: holdTime, debugOwner: this),
            (recognizer) => recognizer
              ..onLongPressStart = ((details) => _takeHold(id, details.globalPosition))
              ..onLongPressMoveUpdate = ((details) => _along(id, details.globalPosition))
              ..onLongPressEnd = ((_) => _letGo(id))
              ..onLongPressCancel = (() => _letGo(id)),
          ),
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer.onSecondaryTapUp = ((_) => _rightClick(id)),
          ),
        },
        child: entry.child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final behavior = ScrollConfiguration.of(context).copyWith(scrollbars: false, overscroll: false, dragDevices: PointerDeviceKind.values.toSet());
    Widget row = ScrollConfiguration(
      behavior: behavior,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const CoastPhysics(),
        clipBehavior: Clip.none,
        child: TabRowBody(
          key: _bodyKey,
          shape: widget.shape,
          gap: widget.gap,
          paddingStart: widget.paddingStart,
          paddingEnd: widget.paddingEnd,
          minHeight: widget.minHeight,
          lineColor: widget.lineColor,
          // `--tab-flare: 7px`, the size of the curve where the line bends up into the active tab.
          flare: 7,
          radius: t.radius('md'),
          activeId: widget.activeId,
          slideFrom: _slideFrom,
          slide: _slide,
          movingId: _moving,
          dragX: _dragX,
          grabbed: _grabbed,
          settlingId: _settling,
          settleFrom: _settleFrom,
          settle: _settle,
          settleCurve: t.curve('glacier-ease-out'),
          children: [
            for (final entry in widget.entries)
              _RowSlot(
                key: ValueKey('${entry.kind.name}:${entry.id ?? ''}'),
                entry: entry,
                child: entry.kind == RowKind.tab && entry.id != null ? _held(entry) : entry.child,
              ),
          ],
        ),
      ),
    );
    row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _mark());
        return false;
      },
      child: Listener(onPointerSignal: _onSignal, child: row),
    );
    final radius = widget.clipRadius;
    if (radius != null) row = ClipRRect(borderRadius: BorderRadius.circular(radius), child: row);
    final frame = widget.frame;
    if (frame != null) row = frame(row);
    if (_fadeStart || _fadeEnd) {
      // `mask-image: linear-gradient(to right, transparent 0, #000 start, #000 calc(100% - end), transparent 100%)`
      final start = _fadeStart ? widget.fade : 0.0, end = _fadeEnd ? widget.fade : 0.0;
      row = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final w = math.max(bounds.width, 1.0);
          return LinearGradient(
            colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: [0, (start / w).clamp(0.0, 1.0), (1 - end / w).clamp(0.0, 1.0), 1],
          ).createShader(bounds);
        },
        child: row,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      // Not a tab bar to a screen reader, whose tab bar may hold nothing but tabs: this one holds chips, crosses
      // and the + as well.
      label: 'Notes you have open',
      child: row,
    );
  }
}

/// A flick along the row keeps going and slows to a stop by notes/tabDrag.ts `coasted`: a fifteenth of its speed lost
/// each frame, until it is too slow to see or the row reaches its end (Matt: "Scrolling through the tabs doesn't have
/// momentum").
class CoastPhysics extends ClampingScrollPhysics {
  const CoastPhysics({super.parent});

  @override
  CoastPhysics applyTo(ScrollPhysics? ancestor) => CoastPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // In pixels a millisecond, as the page measured the finger; slower than a twentieth and it was not a flick.
    final pace = velocity / 1000;
    if (pace.abs() <= 0.05 || position.maxScrollExtent <= position.minScrollExtent) return null;
    if ((pace < 0 && position.pixels <= position.minScrollExtent) || (pace > 0 && position.pixels >= position.maxScrollExtent)) return null;
    return _CoastSimulation(position.pixels, pace, position.maxScrollExtent);
  }
}

class _CoastSimulation extends Simulation {
  _CoastSimulation(this._from, this._pace, this._end);

  final double _from;
  final double _pace;
  final double _end;

  static const double _frame = 16.67;

  /// The row after [time] seconds: `coasted`, a frame at a time.
  ({double left, double pace, bool done}) _at(double time) {
    var left = _from, pace = _pace, done = false;
    var ms = time * 1000;
    while (ms > 0 && !done) {
      final step = math.min(ms, _frame);
      final next = coasted(left, pace, step, _end);
      left = next.left;
      pace = next.pace;
      done = next.done;
      ms -= step;
    }
    return (left: left.clamp(0.0, _end), pace: pace, done: done);
  }

  @override
  double x(double time) => _at(time).left;

  @override
  double dx(double time) => _at(time).pace * 1000;

  @override
  bool isDone(double time) => _at(time).done;
}

// ---- the row's own box --------------------------------------------------------------------------------------------

class _RowParentData extends ContainerBoxParentData<RenderBox> {
  RowKind kind = RowKind.tab;
  String? id;
  String? groupId;
  int count = 1;
  bool collapsed = false;
  bool center = false;
  double marginStart = 0;
  double marginEnd = 0;
}

class _RowSlot extends ParentDataWidget<_RowParentData> {
  const _RowSlot({super.key, required this.entry, required super.child});

  final TabRowEntry entry;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _RowParentData;
    var layout = false, paint = false;
    if (data.kind != entry.kind || data.id != entry.id || data.groupId != entry.groupId || data.count != entry.count || data.collapsed != entry.collapsed) {
      data
        ..kind = entry.kind
        ..id = entry.id
        ..groupId = entry.groupId
        ..count = entry.count
        ..collapsed = entry.collapsed;
      paint = true;
    }
    if (data.center != entry.center || data.marginStart != entry.marginStart || data.marginEnd != entry.marginEnd) {
      data
        ..center = entry.center
        ..marginStart = entry.marginStart
        ..marginEnd = entry.marginEnd;
      layout = true;
    }
    final parent = renderObject.parent;
    if (layout) {
      parent?.markNeedsLayout();
    } else if (paint) {
      parent?.markNeedsPaint();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => TabRowBody;
}

/// The row inside its scroller: its children side by side on the row's line, the baseline under them with its gap
/// under the tab being read, that tab's outline, and the tab a finger is carrying drawn where the finger is.
class TabRowBody extends MultiChildRenderObjectWidget {
  const TabRowBody({
    super.key,
    required this.shape,
    required this.gap,
    required this.paddingStart,
    required this.paddingEnd,
    required this.minHeight,
    required this.lineColor,
    required this.flare,
    required this.radius,
    required this.activeId,
    required this.slideFrom,
    required this.slide,
    required this.movingId,
    required this.dragX,
    required this.grabbed,
    required this.settlingId,
    required this.settleFrom,
    required this.settle,
    required this.settleCurve,
    required super.children,
  });

  final TabShape shape;
  final double gap, paddingStart, paddingEnd, minHeight;
  final Color? lineColor;
  final double flare, radius;
  final String activeId;
  final String? slideFrom;
  final Animation<double> slide;
  final String? movingId;
  final ValueListenable<double?> dragX;
  final double grabbed;
  final String? settlingId;
  final double settleFrom;
  final Animation<double> settle;

  /// `transition: transform 140ms var(--glacier-ease-out)`: a tab let go settles into its place.
  final Curve settleCurve;

  @override
  RenderTabRowBody createRenderObject(BuildContext context) => RenderTabRowBody()..take(this);

  @override
  void updateRenderObject(BuildContext context, RenderTabRowBody renderObject) => renderObject.take(this);
}

/// [TabRowBody]'s box: the layout of the row, what a dragged tab is over, and the line drawn round the tab being read.
class RenderTabRowBody extends RenderBox with ContainerRenderObjectMixin<RenderBox, _RowParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  TabRowBody? _spec;

  /// The curve the outline slides by (`cubic-bezier(0.2, 0.7, 0.2, 1)`, notes/useTabOutline.ts).
  static const Cubic _glide = Cubic(0.2, 0.7, 0.2, 1);

  void take(TabRowBody next) {
    final was = _spec;
    _spec = next;
    if (was == null) {
      markNeedsLayout();
    } else {
      if (was.gap != next.gap || was.paddingStart != next.paddingStart || was.paddingEnd != next.paddingEnd || was.minHeight != next.minHeight || was.shape != next.shape) {
        markNeedsLayout();
      }
      markNeedsPaint();
    }
    if (attached) {
      if (!identical(was?.slide, next.slide)) {
        was?.slide.removeListener(markNeedsPaint);
        next.slide.addListener(markNeedsPaint);
      }
      if (!identical(was?.dragX, next.dragX)) {
        was?.dragX.removeListener(markNeedsPaint);
        next.dragX.addListener(markNeedsPaint);
      }
      if (!identical(was?.settle, next.settle)) {
        was?.settle.removeListener(markNeedsPaint);
        next.settle.addListener(markNeedsPaint);
      }
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _spec?.slide.addListener(markNeedsPaint);
    _spec?.dragX.addListener(markNeedsPaint);
    _spec?.settle.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _spec?.slide.removeListener(markNeedsPaint);
    _spec?.dragX.removeListener(markNeedsPaint);
    _spec?.settle.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) child.parentData = _RowParentData();
  }

  Iterable<(RenderBox, _RowParentData)> get _slots sync* {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      yield (child, child.parentData! as _RowParentData);
    }
  }

  (RenderBox, _RowParentData)? _tab(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final slot in _slots) {
      if (slot.$2.kind == RowKind.tab && slot.$2.id == id) return slot;
    }
    return null;
  }

  // ---- layout --------------------------------------------------------------------------------------------------------

  @override
  double computeMinIntrinsicWidth(double height) => computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final spec = _spec!;
    var width = spec.paddingStart + spec.paddingEnd;
    var n = 0;
    for (final (child, data) in _slots) {
      width += data.marginStart + child.getMaxIntrinsicWidth(double.infinity) + data.marginEnd;
      n += 1;
    }
    return width + (n > 1 ? (n - 1) * spec.gap : 0);
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    var height = _spec!.minHeight;
    for (final (child, _) in _slots) {
      height = math.max(height, child.getMaxIntrinsicHeight(double.infinity));
    }
    return height;
  }

  @override
  void performLayout() {
    final spec = _spec!;
    var x = spec.paddingStart;
    var tallest = spec.minHeight;
    var first = true;
    for (final (child, data) in _slots) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      if (!first) x += spec.gap;
      first = false;
      x += data.marginStart;
      data.offset = Offset(x, 0);
      x += child.size.width + data.marginEnd;
      tallest = math.max(tallest, child.size.height);
    }
    size = constraints.constrain(Size(x + spec.paddingEnd, tallest));
    // Real tabs stand on a line: every tab's foot on the row's baseline. A chip and the + sit in its middle, and so
    // does everything in a capsule.
    for (final (child, data) in _slots) {
      final middle = data.center || spec.shape == TabShape.capsule;
      data.offset = Offset(data.offset.dx, middle ? (size.height - child.size.height) / 2 : size.height - child.size.height);
    }
  }

  // ---- what a dragged tab is over (notes/useTabDrag.ts `stopsOf`, `spotsOf`) ---------------------------------------

  double _globalX(double local) => localToGlobal(Offset(local, 0)).dx;

  /// Where a tab stands in the window, by its layout and not by where a finger has carried it.
  double? globalLeftOf(String id) {
    final slot = _tab(id);
    return slot == null ? null : _globalX(slot.$2.offset.dx);
  }

  /// The tabs and folded chips in the row, measured, all but the one being dragged.
  List<RowStop> stopsOf(String dragging) => [
        for (final (child, data) in _slots)
          if ((data.kind == RowKind.tab && data.id != dragging) || (data.kind == RowKind.chip && data.collapsed))
            RowStop(left: _globalX(data.offset.dx), width: child.size.width, tabs: data.kind == RowKind.tab ? 1 : data.count),
      ];

  /// The tabs, chips and the + in the row, measured, all but the one being dragged.
  List<DropSpot> spotsOf(String dragging) => [
        for (final (child, data) in _slots)
          if (data.kind != RowKind.homeTab && !(data.kind == RowKind.tab && data.id == dragging))
            DropSpot(
              left: _globalX(data.offset.dx),
              right: _globalX(data.offset.dx) + child.size.width,
              group: switch (data.kind) { RowKind.chip => data.id, RowKind.tab => data.groupId, _ => null },
            ),
      ];

  /// How far from its place the tab [id] is drawn now: under a finger, or settling back after one.
  double carriedBy(String id) {
    final spec = _spec!;
    final slot = _tab(id);
    if (slot == null) return 0;
    final x = spec.dragX.value;
    if (spec.movingId == id && x != null) return (x - spec.grabbed - _globalX(slot.$2.offset.dx)).roundToDouble();
    if (spec.settlingId == id && spec.settle.isAnimating) return spec.settleFrom * (1 - spec.settleCurve.transform(spec.settle.value));
    return 0;
  }

  /// The tab [id]'s box in the row, as drawn.
  Rect? _drawn(String? id) {
    final slot = _tab(id);
    if (slot == null) return null;
    return (slot.$2.offset & slot.$1.size).shift(Offset(carriedBy(id!), 0));
  }

  // ---- paint ---------------------------------------------------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    final spec = _spec!;
    final line = spec.lineColor;
    if (line != null) _paintLine(context.canvas, offset, spec, line);
    for (final (child, data) in _slots) {
      final at = offset + data.offset;
      final id = data.kind == RowKind.tab ? data.id : null;
      if (id == null) {
        context.paintChild(child, at);
        continue;
      }
      final dx = carriedBy(id);
      final moving = spec.movingId == id;
      if (moving) {
        // `.tab[data-moving] { box-shadow: 0 6px 18px rgb(0 0 0 / 35%) }`
        final r = spec.shape == TabShape.capsule ? child.size.height / 2 : spec.radius;
        final box = (at.translate(dx, 0) & child.size);
        final shape = spec.shape == TabShape.tab
            ? RRect.fromRectAndCorners(box, topLeft: Radius.circular(r), topRight: Radius.circular(r))
            : RRect.fromRectAndRadius(box, Radius.circular(spec.shape == TabShape.capsule ? r : 0));
        context.canvas.save();
        context.canvas.clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(box.inflate(60))
            ..addRRect(shape),
        );
        context.canvas.drawRRect(shape.shift(const Offset(0, 6)), Paint()
          ..color = const Color.fromRGBO(0, 0, 0, 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
        context.canvas.restore();
      }
      if (moving && spec.dragX.value == null) {
        // `.tab[data-moving] { transform: scale(1.04) }`: held, and not yet carried anywhere.
        final centre = at + child.size.center(Offset.zero);
        final lifted = Matrix4.identity()
          ..translateByDouble(centre.dx, centre.dy, 0, 1)
          ..scaleByDouble(1.04, 1.04, 1, 1)
          ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
        context.pushTransform(needsCompositing, Offset.zero, lifted, (context, _) => context.paintChild(child, at));
      } else {
        context.paintChild(child, at.translate(dx, 0));
      }
    }
  }

  /// The baseline the tabs stand on, the outline of the one being read, and the curves joining the two: one line
  /// that runs along and goes up round the active tab.
  void _paintLine(Canvas canvas, Offset offset, TabRowBody spec, Color color) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    final y = offset.dy + size.height - 0.5;
    // Past the row's own end too: on a row that fits, the line runs on to the window's edge.
    final far = offset.dx + size.width + 100000;
    final to = spec.shape == TabShape.tab ? _drawn(spec.activeId) : null;
    if (to == null) {
      canvas.drawLine(Offset(offset.dx, y), Offset(far, y), stroke);
      return;
    }
    var left = to.left, width = to.width;
    final from = spec.slide.isAnimating ? _drawn(spec.slideFrom) : null;
    if (from != null) {
      final t = _glide.transform(spec.slide.value);
      left = from.left + (to.left - from.left) * t;
      width = from.width + (to.width - from.width) * t;
    }
    final f = spec.flare;
    final r = math.max(0.0, math.min(spec.radius, width / 2) - 0.5);
    final x0 = offset.dx + left + 0.5, x1 = offset.dx + left + width - 0.5;
    final top = offset.dy + to.top + 0.5;
    // The outline's sides stop a curve's height above the line; the curve carries each on down to it.
    final foot = offset.dy + to.top + math.max(0.0, to.height - f);
    final arc = Radius.circular(f - 0.5);
    final path = Path()
      ..moveTo(offset.dx, y)
      ..lineTo(x0 - (f - 0.5), y)
      ..arcToPoint(Offset(x0, foot), radius: arc, clockwise: false)
      ..lineTo(x0, top + r)
      ..arcToPoint(Offset(x0 + r, top), radius: Radius.circular(r))
      ..lineTo(x1 - r, top)
      ..arcToPoint(Offset(x1, top + r), radius: Radius.circular(r))
      ..lineTo(x1, foot)
      ..arcToPoint(Offset(x1 + (f - 0.5), y), radius: arc, clockwise: false)
      ..lineTo(far, y);
    canvas.drawPath(path, stroke);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
