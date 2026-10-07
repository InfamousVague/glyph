import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/back.dart';
import '../sheet/css.dart';
import '../sheet/press_group.dart';

/// The name the sidebar's icon and its card share (`[data-sidebar-toggle]`): what [FloatingCardToggle] wraps the
/// icon in, and what the notes drawer names as its toggle.
const String sidebarToggle = '[data-sidebar-toggle]';

/// The bell's, for the notifications' card (`[data-notifications-toggle]`).
const String notificationsToggle = '[data-notifications-toggle]';

/// Which edge of the window a [FloatingCard] hangs at: the start for the drawer, the end for the aside and the bell.
enum FloatingCardSide { start, end }

/// Marks the icon that opens a [FloatingCard], so a press on it is not a press outside the card: the card stays
/// for the icon's own tap to close it (Matt: "I should be able to click the sidebar button again to close the
/// sidebar"). Wrap the icon in this with the name the card is given as its `toggle`.
///
/// The web named the icon with a selector (`toggle="[data-sidebar-toggle]"`) and asked `closest()` of each press;
/// here the icon and the card are one [TapRegion] group, of that name.
class FloatingCardToggle extends StatelessWidget {
  const FloatingCardToggle({super.key, required this.toggle, required this.child});

  /// The card's own `toggle`.
  final Object toggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => TapRegion(groupId: toggle, child: child);
}

/// A card that floats over the note, hung from the top bar's icon that opened it: the notes drawer at the left
/// (notes_drawer.dart), the aside at the right, and the notifications under the bell (notifications_drawer.dart). A
/// port of `src/app/notes/FloatingCard.tsx` and `FloatingCard.module.css`.
///
/// The page stays live beside it rather than behind a scrim; the card closes on a press outside it, on Escape and
/// the phone's back gesture (core/back.dart), and on whatever its contents close it for. The icon that opened it is
/// left to close it: each card names its own icon ([toggle], [FloatingCardToggle]), and a press there is not a press
/// outside. Drawn only while it is open: the caller builds it, and its going is the close.
///
/// What differs from the web:
/// - It is drawn in the app's overlay from wherever it is built, and takes no room there.
/// - [toggle] is the name of a [TapRegion] group rather than a selector; the icon is wrapped in a
///   [FloatingCardToggle] of the same name. A sheet the card's contents open joins the group (sheet/press_group.dart),
///   as on the page it is the card's own descendant.
/// - The page waited a tick before listening for presses, so that the press that opened the card did not close it;
///   here the press is over before the card is built.
/// - `100dvh` is the window less the keyboard, which shortens the page's window and not this one's.
class FloatingCard extends StatefulWidget {
  const FloatingCard({super.key, this.side = FloatingCardSide.start, this.wide = false, required this.label, required this.toggle, required this.onClose, required this.child});

  final FloatingCardSide side;

  /// A little wider than the drawer's, for rows of sentences: the notifications.
  final bool wide;

  /// What a screen reader calls the card.
  final String label;

  /// The name of the icon that opened it ([FloatingCardToggle]), which a press outside the card does not count.
  final Object toggle;
  final VoidCallback onClose;

  /// What is inside pads itself and scrolls its own middle; the card only holds it and rounds it.
  final Widget child;

  @override
  State<FloatingCard> createState() => _FloatingCardState();
}

class _FloatingCardState extends State<FloatingCard> with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController()..show();

  /// `animation: drawerIn 180ms var(--glacier-ease-out)`.
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  CurvedAnimation? _eased;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final t = context.tokens;
    _eased = CurvedAnimation(parent: _enter, curve: t.curve('glacier-ease-out'));
    // `@media (prefers-reduced-motion: reduce) { .card { animation: none } }`
    if (t.reducedMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _eased?.dispose();
    _enter.dispose();
    super.dispose();
  }

  Widget _overlay(BuildContext overlayContext) {
    final t = context.tokens;
    final media = MediaQuery.of(overlayContext);
    final end = widget.side == FloatingCardSide.end;
    final rtl = Directionality.of(overlayContext) == TextDirection.rtl;
    final atRight = end != rtl;
    final opacity = _eased!;
    final radius = t.radius('lg');
    final line = snapBorder(overlayContext, 1);

    // `inline-size: min(20rem, calc(100vw - var(--glacier-space-10)))`, or for `[data-wide]`
    // `min(26rem, calc(100vw - var(--app-safe-left) - var(--app-safe-right) - var(--glacier-space-6)))`.
    final width = widget.wide
        ? t.lenOf('min(26rem, calc(100vw - var(--app-safe-left) - var(--app-safe-right) - var(--glacier-space-6)))')
        : t.lenOf('min(20rem, calc(100vw - var(--glacier-space-10)))');
    // `max-block-size: calc(100dvh - var(--app-safe-top) - var(--app-safe-bottom) - var(--glacier-space-2) - var(--glacier-space-3))`
    final dvh = media.size.height - media.viewInsets.bottom;
    final tallest = math.max(0.0, dvh - t.len('app-safe-top') - t.len('app-safe-bottom') - t.space(2) - t.space(3));
    // `inset-block-start: calc(var(--app-safe-top) + var(--glacier-space-2))`
    final top = t.len('app-safe-top') + t.space(2);
    // `inset-inline-start: calc(var(--app-safe-left) + var(--glacier-space-3))`, or at the end
    // `inset-inline-end: calc(var(--app-safe-right) + var(--glacier-space-3))`.
    final inset = (end ? t.len('app-safe-right') : t.len('app-safe-left')) + t.space(3);

    final Widget surface = CustomPaint(
      // `box-shadow: var(--app-float-shadow)`, outside the box only: the card is see-through, and a shadow under it
      // would darken the glass and be blurred into it.
      painter: _OuterShadow(t.cssShadows('app-float-shadow'), radius, opacity),
      child: FadeTransition(
        opacity: opacity,
        // In the tree to a screen reader from the frame it mounts, as an element at `opacity: 0` is.
        alwaysIncludeSemantics: true,
        child: ClipRRect(
          // `border-radius: var(--glacier-radius-lg); overflow: hidden`
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            // `backdrop-filter: var(--app-float-blur)`: the ordinary blur under the clip (a bounded one filled only
            // part of a panel on the Fold, packages/glacier popover.dart).
            filter: ui.ImageFilter.blur(sigmaX: blurSigma(t, 'app-float-blur'), sigmaY: blurSigma(t, 'app-float-blur')),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // `background: color-mix(in srgb, var(--glacier-bg) 88%, var(--glacier-text) 4%)`
                color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 88%, var(--glacier-text) 4%)'),
                // `border: 1px solid var(--glacier-border-subtle)`
                border: Border.all(color: t.color('glacier-border-subtle'), width: line),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Padding(
                padding: EdgeInsets.all(line),
                // `color: var(--glacier-text)` and the page's own type, for whatever inside sets none.
                child: DefaultTextStyle(style: pageText(t, 16, color: t.color('glacier-text')), child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );

    final Widget card = TapRegion(
      groupId: widget.toggle,
      // A press anywhere but the card, its icon, and what the card has opened over the page.
      onTapOutside: (_) => widget.onClose(),
      child: PressGroup(
        id: widget.toggle,
        child: Semantics(
          // `role="dialog" aria-modal="false" aria-label={label}`
          role: SemanticsRole.dialog,
          container: true,
          explicitChildNodes: true,
          label: widget.label,
          child: AnimatedBuilder(
            animation: opacity,
            child: surface,
            builder: (context, child) {
              // `@keyframes drawerIn { from { opacity: 0; transform: translateY(-6px) scale(0.97) } }`, growing out
              // of the icon above it: `transform-origin: top left`, or `top right` at the end.
              final at = opacity.value;
              return Transform(
                alignment: end ? Alignment.topRight : Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translateByDouble(0, -6 * (1 - at), 0, 1)
                  ..scaleByDouble(0.97 + 0.03 * at, 0.97 + 0.03 * at, 1, 1),
                child: child,
              );
            },
          ),
        ),
      ),
    );

    // `.over { position: fixed; inset: 0; pointer-events: none }`: only the card takes presses.
    return OnBack(
      onBack: widget.onClose,
      child: Align(
        alignment: atRight ? Alignment.topRight : Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(top: top, left: atRight ? 0 : inset, right: atRight ? inset : 0),
          child: ConstrainedBox(
            key: const ValueKey('floating-card'),
            constraints: BoxConstraints(maxHeight: tallest),
            child: SizedBox(width: width, child: card),
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

/// The outer layers of a `box-shadow`, drawn as CSS draws them: only outside the box, and as strong as the card is
/// there yet.
class _OuterShadow extends CustomPainter {
  _OuterShadow(this.shadows, this.radius, this.opacity) : super(repaint: opacity);
  final List<CssShadow> shadows;
  final double radius;
  final Animation<double> opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final box = RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, math.min(radius, size.shortestSide / 2))));
    var reach = 0.0;
    for (final shadow in shadows) {
      if (!shadow.inset) reach = math.max(reach, shadow.offset.distance + shadow.spread.abs() + shadow.blur * 2 + 1);
    }
    canvas.save();
    // Everywhere the shadows could fall, less the box itself.
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach))
        ..addRRect(box),
    );
    for (final shadow in shadows) {
      if (shadow.inset) continue;
      final paint = Paint()..color = shadow.color.withValues(alpha: shadow.color.a * opacity.value);
      // A CSS blur radius is twice the sigma of the Gaussian it asks for.
      if (shadow.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, shadow.sigma);
      canvas.drawRRect(box.shift(shadow.offset).inflate(shadow.spread), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadow old) => old.radius != radius || !identical(old.shadows, shadows) || !identical(old.opacity, opacity);
}
