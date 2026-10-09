/// A desktop's scrollbar for a view that scrolls under a header: app.css `[data-under-header]::-webkit-scrollbar`
/// (Matt: "On the home page the scrollbar goes behind the header"). Only where there is a mouse
/// (`@media (hover: hover) and (pointer: fine)`): on a phone the thin one that shows while scrolling is the right one.
///
/// As the page's:
///
/// - **It takes its 12 px from the view.** Styling a scrollbar in WebKit gives up the overlay one, so a view that
///   has more than it shows is 12 px narrower inside and whatever is centred in it sits 6 px to the left; a view
///   that shows all it has gives up nothing.
/// - **No track**, and none of it above the header's foot (`margin-block-start: max(var(--wisp-under), …)`).
/// - **A slim rounded thumb in the page's ink**: 6 px across inside 3 px of clear border, 22% of the ink, 40% under
///   the mouse.
///
/// It reads the view's scroll from the notifications that pass it, so it wraps whatever scrolls
/// (lib/art/wisp_edge.dart puts it round every view with a header). A press on the thumb drags the view; a press
/// on the bare track pages it, as the Mac's own does.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../wide_screen.dart' show mousePointer;

/// The scrollbar's width (`inline-size: 12px`), the clear border round its thumb and the least a thumb is tall.
const double desktopScrollbarWidth = 12;
const double desktopScrollbarBorder = 3;
const double desktopScrollbarLeast = 24;

/// Where the thumb is in a track [track] tall, for a view showing [viewport] of [viewport] + [max], scrolled
/// [pixels]: its top and its height.
({double top, double height}) desktopThumb({required double track, required double viewport, required double max, required double pixels}) {
  if (track <= 0 || viewport <= 0 || max <= 0) return (top: 0, height: 0);
  final height = math.min(track, math.max(desktopScrollbarLeast, track * viewport / (viewport + max)));
  final at = (pixels / max).clamp(0.0, 1.0);
  return (top: (track - height) * at, height: height);
}

class DesktopScrollbar extends StatefulWidget {
  const DesktopScrollbar({super.key, required this.child, this.under = 0, this.mouse});

  /// The view that scrolls.
  final Widget child;

  /// The header's height: the track begins under it. Nothing is drawn for a view with no header, as on the page.
  final double under;

  /// Whether there is a mouse; the platform's answer when left out.
  final bool? mouse;

  @override
  State<DesktopScrollbar> createState() => _DesktopScrollbarState();
}

class _DesktopScrollbarState extends State<DesktopScrollbar> {
  double _pixels = 0, _max = 0, _viewport = 0;
  ScrollPosition? _position;
  bool _hover = false;
  double? _dragFrom, _dragPixels;

  bool get _on => (widget.mouse ?? mousePointer) && widget.under > 0;

  bool _heard(ScrollMetrics metrics, BuildContext? from) {
    if (!_on || metrics.axis != Axis.vertical) return false;
    final pixels = metrics.pixels - metrics.minScrollExtent, max = metrics.maxScrollExtent - metrics.minScrollExtent, viewport = metrics.viewportDimension;
    if (from != null) _position = Scrollable.maybeOf(from)?.position ?? _position;
    if (pixels == _pixels && max == _max && viewport == _viewport) return false;
    final had = _max > 0;
    _pixels = pixels;
    _max = max;
    _viewport = viewport;
    // The view gives up its 12 px, or takes them back, a frame after it is known to need them.
    if ((max > 0) != had) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
    return false;
  }

  void _to(double pixels) {
    final position = _position;
    if (position == null) return;
    position.jumpTo(pixels.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return widget.child;
    final t = context.tokens;
    final overflows = _max > 0;
    final listening = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => notification.depth == 0 && _heard(notification.metrics, notification.context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => notification.depth == 0 && _heard(notification.metrics, notification.context),
        child: Padding(padding: EdgeInsets.only(right: overflows ? desktopScrollbarWidth : 0), child: widget.child),
      ),
    );
    if (!overflows) return listening;
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = math.max(0.0, constraints.maxHeight - widget.under);
        final thumb = desktopThumb(track: track, viewport: _viewport, max: _max, pixels: _pixels);
        final ink = t.colorOf('color-mix(in oklch, var(--app-ink) ${_hover || _dragFrom != null ? 40 : 22}%, transparent)');
        return Stack(
          children: [
            listening,
            // The track: bare, and a press on it pages the view toward the press.
            Positioned(
              top: widget.under,
              right: 0,
              bottom: 0,
              width: desktopScrollbarWidth,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (event.buttons != kPrimaryButton) return;
                  final y = event.localPosition.dy;
                  if (y < thumb.top) _to(_pixels - _viewport);
                  if (y > thumb.top + thumb.height) _to(_pixels + _viewport);
                },
              ),
            ),
            Positioned(
              top: widget.under + thumb.top,
              right: 0,
              width: desktopScrollbarWidth,
              height: thumb.height,
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (event.buttons != kPrimaryButton) return;
                    _dragFrom = event.position.dy;
                    _dragPixels = _pixels;
                    setState(() {});
                  },
                  onPointerMove: (event) {
                    final from = _dragFrom, pixels = _dragPixels;
                    if (from == null || pixels == null || track <= thumb.height) return;
                    _to(pixels + (event.position.dy - from) * _max / (track - thumb.height));
                  },
                  onPointerUp: (_) => setState(() => _dragFrom = _dragPixels = null),
                  onPointerCancel: (_) => setState(() => _dragFrom = _dragPixels = null),
                  child: Padding(
                    padding: const EdgeInsets.all(desktopScrollbarBorder),
                    child: DecoratedBox(decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(999))),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
