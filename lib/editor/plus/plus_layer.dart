/// The + as it is drawn, and the one widget a note's screen puts round its editor for it. Ports the half of
/// `src/app/editor/insertPlus.ts` that was a `<button>` and its base theme (`.cm-plus`), and the few lines of
/// `editor/NoteScreen.tsx` that held the list open (`adding`, `plusHooks`, `addKeys`).
///
/// [PlusController] is what the screen makes once: its [PlusController.extension] goes among the editor's
/// extensions, and [PlusLayer] wraps whatever box holds the editor (the page's scroll view), draws the + over it
/// beside the empty line, and mounts the list (add_list.dart) while the + has asked for it.
///
/// **The +** is the gutter's width and its row's height, its target and no more: two strokes, round-capped, in the
/// third ink, 12px at the default spacing and never under 8px, in the middle of the gutter; beside a line's lead,
/// 10px and at the gutter's outer edge. It rises 2px into place as it comes, on typing's own arc, and fades on a
/// deleted letter's beat. Open, it is a ×: the same strokes, turned, in the ink.
///
/// What differs:
/// - **It is placed as it is painted.** The page wrote `top`, `height` and `left` on the button from a measure; here
///   the layer asks the editor where the row is each time it paints ([PlusView.measure]), so a scroll moves it in
///   the same frame, and it cannot be seen beside the line it last stood by.
/// - **A press on it never reaches the editor** because it is above the editor, not because its events are
///   stopped; a long press is taken so press and hold does not start under it.
/// - `:focus-visible` is the ring Flutter shows for a focus that came from the keyboard.
/// - `@media (hover: hover) and (pointer: fine) { .cm-plus:hover }` is a mouse over it on a desktop
///   (shell/wide_screen.dart `mousePointer`): on a phone the page's guard is not met, with a mouse or without.
/// - The controller is new: on the page the three pieces of state were the screen's own hooks.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor.dart';
import '../view/editor_view.dart';
import 'add_list.dart';
import 'insert_plus.dart';
import '../../shell/wide_screen.dart' show mousePointer;

/// The + and its list, as a note's screen holds them: whether the screen allows a + now, the opening the + asked
/// for, and the door the editor's keys reach the list by.
class PlusController extends ChangeNotifier {
  PlusController({bool Function()? allowed}) : _allowed = allowed ?? _always;

  static bool _always() => true;

  bool Function() _allowed;

  /// Whether the screen allows a + now: a note of words, shown, with nothing writing into it. Asked on every look;
  /// after it changes, [recheck].
  set allowed(bool Function() value) => _allowed = value;

  /// Where the editor's keys reach the list while the editor keeps the focus.
  final AddListKeys keys = AddListKeys();

  /// What the + asked for, while its list is up.
  PlusOpening? get opening => _opening;
  PlusOpening? _opening;

  /// What the editor's + is told (`plusHooks`).
  late final PlusHooks hooks = PlusHooks(
    allowed: () => _allowed(),
    onOpen: (opening) {
      // A finger's press on the + has the app's tap tick already; a mouse, a key or a / has none.
      if (opening.by != PlusBy.touch) haptic(HapticKind.selection);
      _opening = opening;
      notifyListeners();
    },
    onClose: close,
    onKey: (key) => keys.current?.call(key) ?? false,
  );

  /// The + beside an empty line: among the editor's extensions, once.
  late final Extension extension = insertPlus(hooks);

  /// The list is to close.
  void close() {
    if (_opening == null) return;
    _opening = null;
    notifyListeners();
  }

  /// The screen's own reasons changed (an AI run started or ended, the view switched): the + looks again, and a
  /// list that is no longer allowed closes.
  void recheck(EditorViewLike view) {
    view.dispatch(TransactionSpec(effects: plusRecheck.of(null)));
    if (!_allowed()) close();
  }
}

/// Draws the + over [child] (the box the editor is in: the page's scroll view) and, with a [controller], the list
/// the + opens.
class PlusLayer extends StatefulWidget {
  const PlusLayer({super.key, required this.view, required this.child, this.controller, this.config = const AddConfig(), this.pane, this.clock, this.coarse});

  /// The editor's view, whose state has [insertPlus] (or [PlusController.extension]) in it; null while there is
  /// none yet, when [child] is drawn alone, in the same place in the tree as it will be with one.
  final EditorViewLike? view;

  /// Holds the list open; without one only the + is drawn, and whoever made the hooks mounts the list.
  final PlusController? controller;

  /// What the screen can put in (add_list.dart).
  final AddConfig config;

  /// The note's pane, for the crease.
  final Rect? Function()? pane;

  /// The time, and whether the pointer is a finger, for a test to say.
  final DateTime Function()? clock;
  final bool? coarse;
  final Widget child;

  @override
  State<PlusLayer> createState() => _PlusLayerState();
}

class _PlusLayerState extends State<PlusLayer> {
  final GlobalKey _follower = GlobalKey();
  PlusView? _plus;

  void _changed() {
    if (!mounted) return;
    // During a frame's build or layout (the editor tells its plugins of a scroll from inside layout) this waits
    // for the frame to end.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _changed());
      return;
    }
    _find();
    setState(() {});
  }

  /// The +'s plugin in the view: looked for again whenever the view says something changed, since a reconfigured
  /// editor makes its plugins anew.
  void _find() {
    final view = widget.view;
    final found = view == null ? null : plusViewOf(view);
    if (identical(found, _plus)) return;
    _plus?.removeListener(_changed);
    _plus = found;
    found?.addListener(_changed);
  }

  void _viewChanged() {
    if (!mounted) return;
    final view = widget.view;
    if (!identical(view == null ? null : plusViewOf(view), _plus)) _changed();
  }

  void _listen(EditorViewLike? view) {
    if (view is EditorView) view.addListener(_viewChanged);
  }

  void _unlisten(EditorViewLike? view) {
    if (view is EditorView) view.removeListener(_viewChanged);
  }

  @override
  void initState() {
    super.initState();
    _listen(widget.view);
    widget.controller?.addListener(_changed);
    _find();
  }

  @override
  void didUpdateWidget(PlusLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      _unlisten(oldWidget.view);
      _listen(widget.view);
      _find();
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _unlisten(widget.view);
    widget.controller?.removeListener(_changed);
    final plus = _plus;
    if (plus != null && !plus.gone) plus.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final plus = _plus != null && !_plus!.gone ? _plus : null;
    final gutter = t.len('app-gutter');
    plus?.gutter = gutter;
    // The row's height as the editor last laid it out: a build may read it, where a layout may not.
    final row = plus?.measure();
    final view = widget.view;
    final opening = view == null ? null : widget.controller?.opening;
    return NotificationListener<ScrollNotification>(
      // The note scrolled: the + goes with its line, in the same frame.
      onNotification: (_) {
        _follower.currentContext?.findRenderObject()?.markNeedsPaint();
        return false;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (event) => plus?.hover(event.kind, event.position),
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            widget.child,
            if (plus != null)
              Positioned.fill(
                child: _PlusFollower(
                  key: _follower,
                  plus: plus,
                  gutter: gutter,
                  height: row?.height,
                  // Its look, so a change of it is laid out and painted again.
                  stamp: Object.hash(plus.look, plus.line, plus.lead, plus.expanded, plus.cuts),
                  child: PlusButton(plus: plus, gutter: gutter),
                ),
              ),
            if (opening != null)
              AddList(
                // One list for each opening: a second press of / after a close starts afresh.
                key: ObjectKey(opening),
                view: view!,
                opening: opening,
                pane: widget.pane,
                onClose: widget.controller!.close,
                keys: widget.controller!.keys,
                config: widget.config,
                clock: widget.clock,
                coarse: widget.coarse,
              ),
          ],
        ),
      ),
    );
  }
}

/// Puts the + beside its line's row, wherever the editor has it now.
class _PlusFollower extends SingleChildRenderObjectWidget {
  const _PlusFollower({super.key, required this.plus, required this.gutter, required this.height, required this.stamp, required super.child});

  final PlusView plus;
  final double gutter;

  /// The row's height, when it is known.
  final double? height;
  final Object stamp;

  @override
  RenderPlusFollower createRenderObject(BuildContext context) => RenderPlusFollower(plus, gutter, stamp)..height = height;

  @override
  void updateRenderObject(BuildContext context, RenderPlusFollower renderObject) {
    renderObject
      ..plus = plus
      ..gutter = gutter
      ..height = height
      ..stamp = stamp;
  }
}

/// The +'s place: fills the box over the editor, and lays the + out the gutter's width and its row's height, at the
/// row, read from the editor as it paints.
class RenderPlusFollower extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  RenderPlusFollower(this._plus, this._gutter, this._stamp);

  PlusView _plus;
  set plus(PlusView value) {
    if (identical(value, _plus)) return;
    _plus = value;
    markNeedsLayout();
  }

  double _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsLayout();
  }

  Object _stamp;
  set stamp(Object value) {
    if (value == _stamp) return;
    _stamp = value;
    markNeedsLayout();
  }

  Offset _at = Offset.zero;
  double _height = 0;
  bool _drawn = false;
  bool _again = false;

  /// The row's height as whoever builds this last read it; null leaves it as it was.
  set height(double? value) {
    if (value == null || value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  /// The row, in this box's own coordinates.
  ({Offset at, double height})? _row() {
    if (_plus.gone || !attached) return null;
    final box = _plus.measure();
    if (box == null) return null;
    return (at: globalToLocal(Offset(box.left, box.top)), height: box.height);
  }

  /// The +'s box on the screen while it is drawn.
  Rect? get plusRect => !_drawn || child == null ? null : localToGlobal(_at) & child!.size;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// The + is laid out at the row's height as it was last read: a layout may not ask another box its size, so the
  /// height is read when this is built and when it paints, and a paint that finds it changed asks for the layout
  /// again.
  @override
  void performLayout() => child?.layout(BoxConstraints.tightFor(width: _gutter, height: _height));

  @override
  void paint(PaintingContext context, Offset offset) {
    _drawn = false;
    final child = this.child;
    if (child == null || _plus.look == PlusLook.off && !_plus.expanded) return;
    final row = _row();
    if (row == null) return;
    _at = row.at;
    _drawn = true;
    if ((row.height - _height).abs() > 0.01 && !_again) {
      _again = true;
      final height = row.height;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _again = false;
        if (!attached) return;
        _height = height;
        markNeedsLayout();
        SchedulerBinding.instance.scheduleFrame();
      });
    }
    context.paintChild(child, offset + _at);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.translateByDouble(_at.dx, _at.dy, 0, 1);

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    // Waiting out the settle, or leaving: never under a finger.
    if (child == null || !_drawn || !(_plus.look == PlusLook.shown || _plus.expanded)) return false;
    final row = _row();
    if (row != null) _at = row.at;
    return result.addWithPaintOffset(offset: _at, position: position, hitTest: (result, position) => child.hitTest(result, position: position));
  }
}

/// The + itself (`.cm-plus`): see the library's note.
class PlusButton extends StatefulWidget {
  const PlusButton({super.key, required this.plus, required this.gutter});

  final PlusView plus;
  final double gutter;

  @override
  State<PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<PlusButton> with SingleTickerProviderStateMixin {
  /// `cubic-bezier(0.2, 0.8, 0.2, 1)`, typing's own arc.
  static const Cubic _arrive = Cubic(0.2, 0.8, 0.2, 1);

  late final AnimationController _shown = AnimationController(vsync: this, value: _wanted ? 1 : 0);
  final FocusNode _focus = FocusNode(debugLabel: 'plus');
  int _cuts = 0;
  bool _pressed = false;
  bool _hovered = false;
  bool _focusVisible = false;
  PointerDeviceKind _kind = PointerDeviceKind.touch;

  PlusView get _plus => widget.plus;

  /// `[data-state='shown'], [aria-expanded='true']`.
  bool get _wanted => _plus.look == PlusLook.shown || _plus.expanded;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _cuts = _plus.cuts;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(PlusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  /// Its opacity and rise follow its look: in over [plusInMs] on the arc, out over [plusOutMs], at once when cut.
  void _follow() {
    final cut = _plus.cuts != _cuts;
    _cuts = _plus.cuts;
    final wanted = _wanted;
    if (cut) {
      _shown.value = wanted ? 1 : 0;
      return;
    }
    if (wanted) {
      if (_shown.status == AnimationStatus.forward || _shown.value == 1) return;
      // Reduced motion: `transition: opacity 160ms linear`.
      _shown.animateTo(1, duration: Duration(milliseconds: _still ? 160 : plusInMs), curve: _still ? Curves.linear : _arrive);
    } else {
      if (_shown.status == AnimationStatus.reverse || _shown.value == 0) return;
      if (_still) {
        _shown.value = 0;
      } else {
        _shown.animateBack(0, duration: const Duration(milliseconds: plusOutMs), curve: Curves.easeOut);
      }
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _press(PlusBy by) {
    if (!_plus.gone) _plus.press(by);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final plus = _plus;
    final lead = plus.lead;
    final still = _still;
    // 12px at the default spacing, and smaller with the gutter, never past 8px; beside a lead, 10px.
    final size = t.lenOf(lead ? 'clamp(8px, calc(var(--app-gutter, 1rem) - 12px), 0.625rem)' : 'clamp(8px, calc(var(--app-gutter, 1rem) - 6px), 0.75rem)');
    final ink = _pressed || plus.expanded
        ? t.color('app-ink')
        : _hovered && mousePointer
        ? t.color('app-ink-2')
        : t.color('app-ink-3');
    final turn = t.transition('app-turn');
    Widget drawing = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: ink),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      builder: (context, color, _) => CustomPaint(size: Size.square(size), painter: _PlusPainter(color ?? ink)),
    );
    // Open, the + is a ×: the same strokes, turned.
    drawing = AnimatedRotation(turns: plus.expanded ? 0.125 : 0, duration: still ? Duration.zero : turn.duration, curve: turn.curve, child: drawing);
    Widget button = Align(alignment: lead ? Alignment.centerLeft : Alignment.center, child: Padding(padding: EdgeInsets.only(left: lead ? 2 : 0), child: drawing));
    if (_focusVisible) button = CustomPaint(foregroundPainter: _FocusPainter(t.color('glacier-focus-ring')), child: button);
    button = AnimatedBuilder(
      animation: _shown,
      child: button,
      builder: (context, child) {
        // Focused from the keyboard it is seen whatever its look.
        final at = _focusVisible ? 1.0 : _shown.value;
        return Opacity(opacity: at.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, still ? 0 : 2 * (1 - at)), child: child));
      },
    );
    return Semantics(
      button: true,
      label: 'Add to this note',
      expanded: plus.expanded,
      onTap: () => _press(PlusBy.keyboard),
      excludeSemantics: true,
      // `:hover` is a pointer over the button in whichever highlight mode the phone is in (the kit's pressable says why).
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
        focusNode: _focus,
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _press(PlusBy.keyboard);
              return null;
            },
          ),
        },
        onShowFocusHighlight: (on) => setState(() => _focusVisible = on),
        onFocusChange: (on) {
          if (!plus.gone) plus.buttonFocus(on);
        },
        child: HapticTarget(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => setState(() {
              _kind = details.kind ?? PointerDeviceKind.touch;
              _pressed = true;
            }),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () => _press(_kind == PointerDeviceKind.mouse || _kind == PointerDeviceKind.stylus ? PlusBy.pointer : PlusBy.touch),
            // A long press on the + is not press and hold's.
            onLongPress: () {},
            onSecondaryTap: () {},
            child: button,
          ),
        ),
        ),
      ),
    );
  }
}

/// Two strokes, round-capped, drawn in the ink the button is: `M6 1.5v9M1.5 6h9` on a box of 12, 1.5 wide.
class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 12;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(6 * unit, 1.5 * unit), Offset(6 * unit, 10.5 * unit), paint);
    canvas.drawLine(Offset(1.5 * unit, 6 * unit), Offset(10.5 * unit, 6 * unit), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color;
}

/// `outline: 2px solid var(--glacier-focus-ring); outline-offset: -2px`.
class _FocusPainter extends CustomPainter {
  const _FocusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusPainter old) => old.color != color;
}
