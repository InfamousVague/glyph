import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/plain.dart';
import 'edge_strips.dart';

/// The halo round the floating dock (home/HomeScreen.module.css `.dockHalo`): what scrolls toward the dock goes soft
/// and is washed toward the page's ground, most at the pill and fading out [dockBlurReach] past it. Where the
/// wisp's smoke was, torn into tendrils by a tile of noise and bending what scrolled behind it (Matt, 2026-10-24:
/// "replace the smoke effect with a gradient blur on all places that use the wisp smoke", and "remove the smoke on
/// mac too so all versions get blur"), it is now a plain gradient: a blur of the page behind the halo, shown
/// through a soft pill the dock's shape. Nothing in it moves, so a page at rest is painted once.

/// How far past the pill the blur reaches, in px: the halo's inset.
const double dockBlurReach = 48;

/// The halo's blur, and how much of the page's ground washes over it.
const double dockBlurSigma = 12;
const double dockBlurWash = 0.70;

/// The pill the halo is shown through, for a halo [width] by [height] whose dock stands [reach] in from every side:
/// [out] past the dock's own edge, softened by [soft]. Strong at the dock, nothing by the halo's edge.
({RRect pill, double soft}) dockBlurPill(double width, double height, [double reach = dockBlurReach]) {
  final out = (reach * 0.5).roundToDouble(), soft = math.max(1.0, (reach * 0.22).roundToDouble());
  final w = math.max(1.0, width.roundToDouble()), h = math.max(1.0, height.roundToDouble());
  final inset = math.max(0.0, reach - out);
  final innerW = math.max(1.0, w - 2 * inset), innerH = math.max(1.0, h - 2 * inset);
  return (pill: RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, innerW, innerH), Radius.circular(math.min(innerW, innerH) / 2)), soft: soft);
}

/// The halo as a strip of what lies behind the dock: that strip blurred, washed with the page's ground, and shown
/// through [dockBlurPill]. On the page it is an element with a `backdrop-filter` and a `mask-image`. A backdrop
/// filter cannot be shown through a mask in this engine, so the halo is drawn from a picture of the view behind the
/// dock instead (edge_strips.dart), which is the same thing wherever the only thing behind the dock is that view.
class DockBlurStrip extends EdgeStrip {
  const DockBlurStrip({required this.rect, required this.ground, this.haloReach = dockBlurReach});

  /// The halo's own box: the dock's, grown by the reach on every side.
  @override
  final Rect rect;

  /// The page's ground, which washes over the halo.
  final Color ground;

  /// How far past the dock the halo reaches: [dockBlurReach], less while the dock is drawn smaller.
  final double haloReach;

  @override
  double get reach => (dockBlurSigma * 3).ceilToDouble();

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    final whole = Rect.fromLTWH(0, 0, view.width.toDouble(), view.height.toDouble());
    final shape = dockBlurPill(rect.width, rect.height, haloReach);
    // The soft pill, whole at the dock and gone by the halo's edge, laid with [blend] over what is drawn.
    void pill(BlendMode blend) {
      canvas.saveLayer(at, Paint()..blendMode = blend);
      canvas.translate(rect.left, rect.top);
      canvas.drawRRect(shape.pill, Paint()..color = const Color(0xFF000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, shape.soft));
      canvas.restore();
    }

    canvas.save();
    canvas.clipRect(at, doAntiAlias: false);
    canvas.saveLayer(at, Paint());
    // The view as it is, where the pill is not; and the view blurred and washed, where it is, the two added: a blur
    // laid over the view would leave the sharp words showing through its own clear ground.
    canvas.saveLayer(at, Paint());
    canvas.drawImageRect(view, whole, viewRect, Paint());
    pill(BlendMode.dstOut);
    canvas.restore();
    canvas.saveLayer(at, Paint()..blendMode = BlendMode.plus);
    canvas.drawImageRect(view, whole, viewRect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: dockBlurSigma, sigmaY: dockBlurSigma, tileMode: TileMode.clamp));
    canvas.drawRect(at, Paint()..color = ground.withValues(alpha: dockBlurWash));
    pill(BlendMode.dstIn);
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool operator ==(Object other) => other is DockBlurStrip && other.rect == rect && other.ground == ground && other.haloReach == haloReach;

  @override
  int get hashCode => Object.hash(rect, ground, haloReach);
}

/// The halo round a dock at [dock] of [child], which is what scrolls behind it: the low half of [DockBlur], for a
/// screen that places its dock itself and knows where.
///
/// Nothing is drawn while [dock] is null, or smaller than a pill: until a dock is measured the page keeps a plain
/// edge, which nobody sees for longer than a frame. The halo is the dock's own and is drawn whatever the edges'
/// switch says, as the wisp's was; a plain build (lib/app/plain.dart) has none.
class DockBlurHalo extends StatelessWidget {
  const DockBlurHalo({super.key, required this.dock, this.reach = dockBlurReach, required this.child});

  /// The dock's own box, in [child]'s.
  final Rect? dock;

  /// How far past the dock the halo reaches: [dockBlurReach], less while the dock is drawn smaller as the page
  /// scrolls (lib/shell/page_dock.dart `DockShrink`), so the halo is the dock's at every size.
  final double reach;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dock = this.dock;
    final strips = <EdgeStrip>[];
    if (dock != null && dock.width >= 2 && dock.height >= 2 && !ghostPlain) {
      final tokens = GlacierTheme.maybeOf(context);
      strips.add(DockBlurStrip(rect: dock.inflate(reach), ground: tokens?.color('glacier-bg') ?? const Color(0xFF000000), haloReach: reach));
    }
    return EdgeStrips(strips: strips, child: child);
  }
}

/// A dock floating over what scrolls behind it, with the blur round it: [behind] fills the box, [dock] is laid over
/// it at [alignment] inside [padding], and the halo is drawn round wherever that puts it. The home page's dock, with
/// its scroller; and every page's (lib/shell/page_dock.dart), with the page. While [shown] is false (the dock
/// stepped aside for the keyboard) there is no halo, and [behind] is drawn as it is.
///
/// Where [scale] is given, the dock is drawn that much of the box it was laid out in, held to its corner at
/// [alignment] (smaller while the page scrolls, lib/shell/page_dock.dart `DockShrink`): the halo is drawn round the
/// dock as it is drawn, its reach that much of its own, and it alone is built again as the scale moves.
class DockBlur extends StatefulWidget {
  const DockBlur({super.key, required this.behind, required this.dock, this.alignment = Alignment.bottomCenter, this.padding = EdgeInsets.zero, this.shown = true, this.scale});

  final Widget behind;
  final Widget dock;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final bool shown;
  final ValueListenable<double>? scale;

  @override
  State<DockBlur> createState() => _DockBlurState();
}

class _DockBlurState extends State<DockBlur> {
  final GlobalKey _dock = GlobalKey();
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    widget.scale?.addListener(_scaled);
  }

  @override
  void didUpdateWidget(DockBlur old) {
    super.didUpdateWidget(old);
    if (!identical(old.scale, widget.scale)) {
      old.scale?.removeListener(_scaled);
      widget.scale?.addListener(_scaled);
    }
  }

  @override
  void dispose() {
    widget.scale?.removeListener(_scaled);
    super.dispose();
  }

  void _scaled() {
    if (mounted) setState(() {});
  }

  /// The dock's box as it is drawn: [_rect], scaled about its corner at the alignment.
  Rect? _drawn(double scale) {
    final rect = _rect;
    if (rect == null || scale == 1) return rect;
    final corner = widget.alignment.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr).withinRect(rect);
    Offset at(Offset p) => corner + (p - corner) * scale;
    return Rect.fromPoints(at(rect.topLeft), at(rect.bottomRight));
  }

  /// Where the dock was laid, read once the frame that laid it is done: its size is the dock's own (two buttons or
  /// four, a phone or the Fold), so it is measured, as the page measures the halo.
  void _measure() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dock = _dock.currentContext?.findRenderObject();
      final box = context.findRenderObject();
      if (dock is! RenderBox || box is! RenderBox || !dock.hasSize) return;
      final rect = dock.localToGlobal(Offset.zero, ancestor: box) & dock.size;
      if (rect != _rect) setState(() => _rect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final scale = widget.scale?.value ?? 1;
    return Stack(
      fit: StackFit.expand,
      children: [
        DockBlurHalo(dock: widget.shown ? _drawn(scale) : null, reach: dockBlurReach * scale, child: widget.behind),
        Padding(
          padding: widget.padding,
          child: Align(
            alignment: widget.alignment,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _measure();
                return false;
              },
              child: SizeChangedLayoutNotifier(child: KeyedSubtree(key: _dock, child: widget.dock)),
            ),
          ),
        ),
      ],
    );
  }
}
