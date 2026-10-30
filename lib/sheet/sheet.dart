import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/back.dart';
import 'css.dart';
import 'flow.dart';
import 'press_group.dart';
import 'sheet_drag.dart';

/// A sheet from the bottom over the dimmed page, where a thumb already is: the one shell every bottom sheet shares.
/// A port of `src/app/editor/Sheet.tsx`, with the look it draws in, `editor/NoteSettings.module.css` (`.scrim`,
/// `.sheet`, `.grip`), which is the app's sheet stylesheet in all but its name.
///
/// A scrim over the window that closes the sheet on a tap; the panel, a dialog that keeps its own taps; a grip along
/// its top that takes a pull down (sheet_drag.dart); and the back gesture, or Escape, closing it before it leaves
/// whatever is under it (core/back.dart). It is mounted only while it is open, and takes the gesture for as long as
/// it is: build it while the sheet is up, and stop building it to close. The rows inside are kit.dart's.
///
/// On a desktop (`data-platform='desktop'`) it is a window in the middle of the screen rather than a drawer from its
/// foot: the same panel, its corners all rounded, at a reading width, with no grip.
///
/// What differs from the web:
/// - It is drawn in the app's overlay, over everything, wherever it is built; where it is built it takes no room. On
///   the page it is `position: fixed`, which the sidebar's card traps inside itself (a `backdrop-filter` makes its
///   box the containing block): measured there on 2026-10-07, a workspace's sheet opened from the pop-up sidebar was
///   318px wide inside the card with its seventh colour cut off. Here it opens over the window from there too.
/// - [children] are laid out as the page lays out the sheet's own blocks, their margins collapsing (flow.dart).
/// - The keyboard: the page's window is shortened by it, and the sheet with the window; here the scrim is padded by
///   the keyboard's height and the sheet's `85dvh` is of what is left.
/// - What held the focus as the sheet opens gives it up (the page's press on a button blurs the editor).
/// - `className` (the panel's own look, on top of the sheet's) is not taken; nothing built so far asks for it.
/// - `--sheet-ground` and `--sheet-inset-top`, which a pinned strip inside a sheet reads, are not published.
/// - A screen reader is given a way to dismiss it (`onDismiss`), where the page's scrim was a bare `div`.
class Sheet extends StatefulWidget {
  const Sheet({super.key, required this.label, required this.onClose, this.onBack, this.onScrimPointerDown, this.centred, required this.children});

  /// How many sheets are up now, anywhere in the app: what waits for every other sheet to be put away before it comes
  /// (the What's new card, lib/changelog/whats_new.dart, never over a plugin's setup or any other question). Told a
  /// frame after a sheet comes or goes, never while one is being built.
  static ValueListenable<int> get shown => _shown;
  static final ValueNotifier<int> _shown = ValueNotifier(0);
  static int _counted = 0;

  static void _count(int by) {
    _counted += by;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _shown.value = _counted)
      ..scheduleFrame();
  }

  /// What the dialog is called, for a screen reader.
  final String label;

  /// A tap on the scrim, or a pull down on the grip.
  final VoidCallback onClose;

  /// The back gesture; [onClose] unless the sheet has pages of its own to step back through first.
  final VoidCallback? onBack;

  /// A press on the scrim, before its tap: the canvas's + sheet keeps it from the canvas's own gestures under it.
  final void Function(PointerDownEvent event)? onScrimPointerDown;

  /// A window in the middle rather than a drawer from the foot, with no grip: true for a wide window that is not a
  /// desktop's (the opened Fold), false for a drawer even there. Null is the platform's: a window on a desktop.
  final bool? centred;

  /// The sheet's blocks, top to bottom, under the grip.
  final List<Widget> children;

  @override
  State<Sheet> createState() => _SheetState();
}

class _SheetState extends State<Sheet> with TickerProviderStateMixin {
  // Told to show before it is attached, so the sheet is up from the frame this is built in.
  final OverlayPortalController _portal = OverlayPortalController()..show();

  /// `animation: scrim-in 200ms ease-out both` and the panel's `sheet-in` (or `modal-in`), off one clock: the longer
  /// of the two is its whole length.
  late final AnimationController _enter = AnimationController(vsync: this);

  /// The spring back to rest after a pull let go short (`SPRING`).
  late final AnimationController _spring = AnimationController(vsync: this, duration: SheetDrag.springDuration);
  double _from = 0;

  /// How far down the panel is drawn under the finger.
  final ValueNotifier<double> _pulled = ValueNotifier(0);
  late final SheetDrag _drag = SheetDrag(onMove: _move, onClose: () => widget.onClose());
  int? _pointer;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // On the page the press that opens a sheet takes the focus from the note being written (a button's press blurs
    // the editor), so the keyboard goes down and the sheet has the screen; a Flutter press takes no focus, and the
    // sheet stood squeezed over the keyboard. What held the focus gives it up here; a field of the sheet's own that
    // asks for it as it is built still gets it.
    FocusManager.instance.primaryFocus?.unfocus();
    Sheet._count(1);
    _spring.addListener(() => _pulled.value = _from * (1 - SheetDrag.springCurve.transform(_spring.value)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final t = context.tokens;
    _enter.duration = Duration(milliseconds: _centred(t) ? 200 : 320);
    if (t.reducedMotion) {
      // `@media (prefers-reduced-motion: reduce) { .scrim, .sheet { animation: none } }`
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  static bool _desktop(Tokens t) => t.attrs['platform'] == 'desktop';

  /// A window in the middle: [Sheet.centred], else a desktop's.
  bool _centred(Tokens t) => widget.centred ?? _desktop(t);

  void _move(double dy, {required bool animated}) {
    _spring.stop();
    if (!animated) {
      _pulled.value = dy;
      return;
    }
    _from = _pulled.value;
    _spring.forward(from: 0);
  }

  @override
  void dispose() {
    Sheet._count(-1);
    _enter.dispose();
    _spring.dispose();
    _pulled.dispose();
    super.dispose();
  }

  /// `.grip`: a band the width of the sheet answers the finger, and the bar itself is drawn inside it.
  Widget _grip(Tokens t) {
    double ms(PointerEvent event) => event.timeStamp.inMicroseconds / 1000;
    return CssFlow.block(
      // `margin-block-end: var(--glacier-space-1)`
      margin: EdgeInsets.only(bottom: t.space(1)),
      child: ExcludeSemantics(
        child: Listener(
          key: const ValueKey('sheet-grip'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            // `if (!event.isPrimary) return`: the first finger down has the handle, and no other.
            if (_pointer != null) return;
            _pointer = event.pointer;
            _drag.down(event.position.dy, ms(event));
          },
          onPointerMove: (event) {
            if (event.pointer == _pointer) _drag.move(event.position.dy, ms(event));
          },
          onPointerUp: (event) {
            if (event.pointer != _pointer) return;
            _pointer = null;
            _drag.end(event.position.dy, ms(event));
          },
          onPointerCancel: (event) {
            if (event.pointer != _pointer) return;
            _pointer = null;
            _drag.end(event.position.dy, ms(event));
          },
          // `touch-action: none`: a drag that starts on the handle is the handle's, and the sheet does not scroll.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                // `padding-block: var(--glacier-space-3)`
                padding: EdgeInsets.symmetric(vertical: t.space(3)),
                child: Center(
                  // `.grip::before { inline-size: 2.75rem; block-size: 4px; border-radius: 2px; background: var(--glacier-border-strong) }`
                  child: Container(
                    width: t.lenOf('2.75rem'),
                    height: 4,
                    decoration: BoxDecoration(color: t.color('glacier-border-strong'), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext overlayContext) {
    final t = context.tokens;
    final media = MediaQuery.of(overlayContext);
    final desktop = _centred(t);
    final keyboard = media.viewInsets.bottom;
    // `100dvh`: the window as it is now, less the keyboard that the page's window is shortened by.
    final dvh = media.size.height - keyboard;
    final line = snapBorder(overlayContext, 1);
    final edge = t.color('glacier-border-subtle');
    final radius = Radius.circular(t.radius('xl'));
    // `--sheet-ground: var(--app-paper-2); background: var(--sheet-ground)`
    final ground = t.color('app-paper-2');

    final Widget blocks = DefaultTextStyle(
      style: pageText(t, 16, color: t.color('glacier-text')),
      child: CssFlow(children: [if (!desktop) _grip(t), ...widget.children]),
    );

    final Widget panel;
    if (desktop) {
      // `:root[data-platform='desktop'] .sheet`: `inline-size: min(100%, 34rem); max-block-size: min(82dvh, 48rem);
      // padding: var(--glacier-space-5); border: 1px solid var(--glacier-border-subtle);
      // border-radius: var(--glacier-radius-xl); box-shadow: var(--app-float-shadow)`.
      panel = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: t.lenOf('34rem'), maxHeight: math.min(dvh * 0.82, t.lenOf('48rem'))),
        child: DecoratedBox(
          decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.all(radius), boxShadow: t.shadow('app-float-shadow')),
          child: ClipRRect(
            borderRadius: BorderRadius.all(radius),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(border: Border.all(color: edge, width: line), borderRadius: BorderRadius.all(radius)),
              child: SingleChildScrollView(padding: EdgeInsets.all(line + t.space(5)), child: blocks),
            ),
          ),
        ),
      );
    } else {
      // `.sheet`: `inline-size: 100%; max-block-size: 85dvh; overflow-y: auto;
      // padding: var(--glacier-space-2) var(--app-gutter-end) calc(var(--app-safe-bottom) + var(--glacier-space-5)) var(--app-gutter-start);
      // border-radius: var(--glacier-radius-xl) var(--glacier-radius-xl) 0 0; border-block-start: 1px solid var(--glacier-border-subtle)`.
      final corners = BorderRadius.vertical(top: radius);
      panel = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dvh * 0.85),
        child: ClipRRect(
          borderRadius: corners,
          child: CustomPaint(
            foregroundPainter: _TopEdge(color: edge, width: line, radius: radius.x),
            child: ColoredBox(
              color: ground,
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    t.len('app-gutter-start'),
                    line + t.space(2),
                    t.len('app-gutter-end'),
                    t.len('app-safe-bottom') + t.space(5),
                  ),
                  child: blocks,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The panel keeps its own taps (`onClick={(e) => e.stopPropagation()}`): it lies over the scrim, and what is hit
    // first is all that is asked.
    final Widget dialog = Semantics(
      role: SemanticsRole.dialog,
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: widget.label,
      onDismiss: widget.onClose,
      child: GestureDetector(key: const ValueKey('sheet-panel'), behavior: HitTestBehavior.opaque, onTap: () {}, excludeFromSemantics: true, child: panel),
    );

    final Widget placed = AnimatedBuilder(
      animation: Listenable.merge([_enter, _pulled]),
      child: dialog,
      builder: (context, child) {
        final ms = _enter.value * _enter.duration!.inMilliseconds;
        if (desktop) {
          // `@keyframes modal-in { from { transform: translateY(8px) scale(0.98); opacity: 0 } }`, 180ms ease-out.
          final at = Curves.easeOut.transform((ms / 180).clamp(0.0, 1.0));
          return Opacity(
            opacity: at,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(0, 8 * (1 - at), 0, 1)
                ..scaleByDouble(0.98 + 0.02 * at, 0.98 + 0.02 * at, 1, 1),
              child: child,
            ),
          );
        }
        // `@keyframes sheet-in { from { transform: translateY(40%); opacity: 0 } }`, 320ms cubic-bezier(0.2, 0.9, 0.3, 1).
        final at = SheetDrag.springCurve.transform((ms / 320).clamp(0.0, 1.0));
        return Opacity(
          opacity: at,
          child: FractionalTranslation(
            translation: Offset(0, 0.4 * (1 - at)),
            child: Transform.translate(offset: Offset(0, _pulled.value), child: child),
          ),
        );
      },
    );

    // `.scrim`: `position: fixed; inset: 0; display: flex; align-items: flex-end;
    // background: color-mix(in oklch, var(--glacier-bg) 55%, transparent)`.
    final Widget scrim = Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerDown: widget.onScrimPointerDown,
            child: GestureDetector(
              key: const ValueKey('sheet-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              excludeFromSemantics: true,
              child: ColoredBox(color: t.colorOf('color-mix(in oklch, var(--glacier-bg) 55%, transparent)')),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            // On a desktop, `align-items: center; justify-content: center; padding: var(--glacier-space-6)`.
            padding: desktop ? EdgeInsets.all(t.space(6)).add(EdgeInsets.only(bottom: keyboard)) : EdgeInsets.only(bottom: keyboard),
            child: Align(alignment: desktop ? Alignment.center : Alignment.bottomCenter, child: placed),
          ),
        ),
      ],
    );

    return OnBack(
      onBack: widget.onBack ?? widget.onClose,
      child: PressGroup.join(
        context,
        // `aria-modal="true"`: nothing under the sheet is read while it is up.
        child: BlockSemantics(
          child: AnimatedBuilder(
            animation: _enter,
            child: scrim,
            // `@keyframes scrim-in { from { opacity: 0 } }`, 200ms ease-out, on the scrim and so on all it holds.
            builder: (context, child) {
              final ms = _enter.value * _enter.duration!.inMilliseconds;
              return Opacity(opacity: Curves.easeOut.transform((ms / 200).clamp(0.0, 1.0)), child: child);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: _overlay,
      child: const SizedBox.shrink(),
    );
  }
}

/// `border-block-start: 1px solid` on a box whose top corners are rounded: the line follows the two corners and stops
/// where the sides begin, which have no border.
class _TopEdge extends CustomPainter {
  const _TopEdge({required this.color, required this.width, required this.radius});
  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(radius, size.shortestSide / 2);
    final outer = RRect.fromRectAndCorners(Offset.zero & size, topLeft: Radius.circular(r), topRight: Radius.circular(r));
    // The padding box under a border that is only on top: the same corners, flattened by the border's width.
    final inner = RRect.fromRectAndCorners(
      Rect.fromLTRB(0, width, size.width, size.height),
      topLeft: Radius.elliptical(r, math.max(0, r - width)),
      topRight: Radius.elliptical(r, math.max(0, r - width)),
    );
    canvas.drawDRRect(outer, inner, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TopEdge old) => old.color != color || old.width != width || old.radius != radius;
}
