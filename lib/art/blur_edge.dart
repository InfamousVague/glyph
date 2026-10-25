import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/plain.dart';
import '../shell/desktop/desktop_scrollbar.dart';
import 'edge_backdrop.dart';
import 'edge_strips.dart';

// ---- the numbers ---------------------------------------------------------------------------------------------------

/// How deep the blur under a header runs, and how soft it is at the header's foot. Kept to a band: the blur is
/// drawn from a picture of the strip it covers, three times, and the band is all of the page that is.
const double blurEdgeDepth = 40;
const double blurEdgeSigma = 8;

/// How much of the page's ground is laid over the blur at its edge, fading to none at its inner end.
const double blurEdgeWash = 0.55;

/// How long the blur under a header takes to come in once the page is scrolled under it, and to go once it is back
/// at its top. None with reduced motion.
const Duration blurEdgeTurn = Duration(milliseconds: 160);

/// How deep the blur at a page's foot runs, and the fade at the foot's edge: the words go from sharp, to blurred,
/// to gone where the dock (or the window) begins.
const double blurEdgeFootDepth = 64;
const double blurEdgeFootFade = 28;

/// How far above a view's bottom edge the foot's blur reaches words: a note's editor keeps its caret this far clear
/// of the edge where the foot blurs ([footBlurs]).
const double blurEdgeFootClear = blurEdgeFootDepth;

/// The switch the edges read: `preferences().wispEdge` (Settings › Appearance › Motion, "Blur at the edges"). Off,
/// no edge blurs and a page slips under its header with a clean edge. The app's preferences are not this
/// directory's, so whoever owns them sets this when the person's choice is read and when it changes
/// (lib/root/ghost_root.dart).
class BlurEdgeSettings extends ChangeNotifier {
  BlurEdgeSettings._();
  static final BlurEdgeSettings instance = BlurEdgeSettings._();

  bool _wanted = true;

  bool get wanted => _wanted;
  set wanted(bool value) {
    if (value == _wanted) return;
    _wanted = value;
    notifyListeners();
  }

  /// Puts the switch back as the app starts with it.
  void reset() {
    _wanted = true;
    notifyListeners();
  }
}

/// Whether a page's foot blurs the words under it, for a note's editor to keep its caret [blurEdgeFootClear] clear
/// of the edge. Only the switch decides: the blur does not move, so it stays with reduced motion, as the wisp's
/// fade stayed when its bend went.
bool footBlurs(bool wanted) => wanted;

// ---- the view ------------------------------------------------------------------------------------------------------

/// The app's standard soft edge for anything that scrolls under a header, and its foot: a gradient blur, where the
/// wisp's smoke was (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places that use the
/// wisp smoke", and then "remove the smoke on mac too so all versions get blur"). Content slipping up behind the
/// header goes soft over [blurEdgeDepth] below the header's foot, softest at the header, and is washed toward the
/// page's ground; words scrolling off the foot go soft over [blurEdgeFootDepth] and fade out at the edge. The same
/// on a Mac, an iPhone and every desktop.
///
/// On Android the same strips are blurred as a backdrop filter, a band of the screen whose shader grows the
/// softness toward the edge, under the same wash, and the view is cleared by laying the page's ground over it where
/// a strip's mask would clear it (Matt, 2026-10-25, on the Fold: "the blur works now but it's super laggy";
/// [edgeLook], [EdgeBackdropBand], [EdgeShade]). Where the engine cannot filter by a shader the strips only fade:
/// the page's ground from none at each strip's inner end to [edgeFadeWash] at its edge. Neither takes a picture of
/// the view, and the switch, the turn in and reduced motion are as they are for the blur.
///
/// Wrap the thing that scrolls: `BlurEdge(under: headerHeight, foot: true, child: ListView(...))`. The scroller is
/// found by the notifications it sends, so [child] must hold one vertical scroller, the outermost.
///
/// - [under] is the height of a header the scroller runs beneath; the blur starts at its foot. With none, the blur
///   is at the view's own top edge, and the view fades out over the status bar's height and 8px more ([safeTop],
///   `--app-safe-top` by default) with the blur running a band past that.
/// - [foot] blurs the foot while there is more below; [footOver] is the height of what stands over the foot (a
///   dock), so the blur happens at its top edge and the view is gone below it.
/// - [onChanged] is told whether the top is blurred.
///
/// Nothing is drawn until the view is scrolled off its top and can scroll; nothing at all with the switch off
/// ([BlurEdgeSettings.wanted]). The blur does not move, so reduced motion keeps it, and takes away only its turn in
/// and out ([blurEdgeTurn]). A plain build (lib/app/plain.dart) shades the edges with the page's ground and takes no
/// picture of the view.
///
/// The header is a number here, not an element measured; whoever lays out the header knows its height and pads the
/// scroller. Its scrollbar under a header is lib/shell/desktop/desktop_scrollbar.dart's. The strips of the view that
/// blur are drawn through pictures of themselves and the rest of the view is left as it paints (edge_strips.dart).
class BlurEdge extends StatefulWidget {
  const BlurEdge({super.key, required this.child, this.under = 0, this.foot = false, this.footOver = 0, this.safeTop, this.onChanged, this.scrollbar = true});

  final Widget child;
  final double under;
  final bool foot;
  final double footOver;

  /// The phone's status bar and whatever bar stands under it, where the view has no header: `--app-safe-top` when
  /// left out.
  final double? safeTop;
  final ValueChanged<bool>? onChanged;

  /// Whether the view wears a desktop's scrollbar under its header (lib/shell/desktop/desktop_scrollbar.dart). A
  /// note's page does not: measured in the page's own engine, its scroller keeps a scrollbar of no width whatever
  /// it holds, where the home page's is 12 px.
  final bool scrollbar;

  @override
  State<BlurEdge> createState() => _BlurEdgeState();
}

class _BlurEdgeState extends State<BlurEdge> with SingleTickerProviderStateMixin {
  double _pixels = 0, _max = 0;
  bool _worn = false, _footWorn = false;
  bool _still = false;
  double _safeTop = 0;
  Color _ground = const Color(0x00000000);
  late final AnimationController _turn = AnimationController(vsync: this, duration: blurEdgeTurn);

  bool get _wanted => BlurEdgeSettings.instance.wanted;

  @override
  void initState() {
    super.initState();
    BlurEdgeSettings.instance.addListener(_settingsChanged);
    // The backdrop's shader is loaded as the first page with soft edges is made, to be there by its first scroll.
    if (edgeLook == EdgeLook.backdrop) EdgeBackdropProgram.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _still = media.disableAnimations;
    final tokens = GlacierTheme.maybeOf(context);
    _safeTop = widget.safeTop ?? (tokens?.raw('app-safe-top') != null ? tokens!.len('app-safe-top') : media.viewPadding.top);
    if (tokens != null) _ground = tokens.color('glacier-bg');
    if (_still && _turn.isAnimating) _turn.value = _worn ? 1 : 0;
  }

  @override
  void didUpdateWidget(BlurEdge old) {
    super.didUpdateWidget(old);
    if (old.safeTop != widget.safeTop && widget.safeTop != null) _safeTop = widget.safeTop!;
    if (old.foot != widget.foot || old.under != widget.under) _check();
  }

  @override
  void dispose() {
    BlurEdgeSettings.instance.removeListener(_settingsChanged);
    _turn.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    if (!mounted) return;
    _check();
    _rebuild();
  }

  /// Builds again for a change that came in a notification, which may arrive while the frame is being built.
  void _rebuild() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Turns the top's blur in or out: at once with reduced motion.
  void _turnTo(bool on) {
    if (_still) {
      _turn.value = on ? 1 : 0;
    } else {
      on ? _turn.forward() : _turn.reverse();
    }
  }

  /// Which ends this view wears at this scroll.
  void _check() {
    if (!mounted) return;
    if (!_wanted) {
      if (_worn || _footWorn) {
        _worn = false;
        _footWorn = false;
        _turn.value = 0;
        widget.onChanged?.call(false);
        _rebuild();
      }
      return;
    }
    // Scrolled off its top AND able to scroll: a view that stops scrolling keeps its place, and must not go on
    // blurring.
    final more = _max > 4;
    final scrolled = _pixels > 4 && more;
    // The foot blurs while there is still something below the view's bottom edge to scroll to.
    final ending = widget.foot && more && _pixels < _max - 4;
    if (ending != _footWorn) {
      _footWorn = ending;
      _rebuild();
    }
    if (scrolled == _worn) return;
    _worn = scrolled;
    _rebuild();
    widget.onChanged?.call(scrolled);
    _turnTo(scrolled);
  }

  bool _metrics(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return false;
    _pixels = metrics.pixels - metrics.minScrollExtent;
    _max = metrics.maxScrollExtent - metrics.minScrollExtent;
    _check();
    return false;
  }

  List<EdgeStrip> _strips(Size size) {
    if (!_wanted || ghostPlain) return const [];
    final width = size.width, height = size.height;
    final strips = <EdgeStrip>[];
    final wash = _ground.withValues(alpha: blurEdgeWash);
    final shown = Curves.easeOut.transform(_turn.value.clamp(0.0, 1.0));
    final inset = widget.foot ? widget.footOver : 0.0;

    if (_turn.value > 0 || _worn) {
      if (widget.under > 0) {
        // Under a header the header hides the top; the blur hangs from its foot.
        final rect = Rect.fromLTWH(0, widget.under, width, math.min(blurEdgeDepth, math.max(0, height - widget.under)));
        if (_turn.value > 0) strips.add(EdgeBlurStrip(rect: rect, side: EdgeSide.top, sigma: blurEdgeSigma, wash: wash, opacity: shown));
      } else {
        // With none the view dissolves into the status bar's own ground, and is soft for a band below that.
        final topFade = _safeTop + 8;
        final rect = Rect.fromLTRB(0, 0, width, math.min(height, topFade + blurEdgeDepth));
        strips.add(EdgeBlurStrip(rect: rect, side: EdgeSide.top, sigma: blurEdgeSigma, wash: wash, opacity: shown, fade: EdgeFade(clearUntil: 0, wholeFrom: topFade)));
      }
    }

    final edge = height - inset;
    if (_footWorn) {
      final rect = Rect.fromLTRB(0, math.max(0, edge - blurEdgeFootDepth), width, edge);
      strips.add(EdgeBlurStrip(rect: rect, side: EdgeSide.bottom, sigma: blurEdgeSigma, wash: wash, fade: EdgeFade(wholeUntil: edge - blurEdgeFootFade, clearFrom: edge)));
    }
    if ((_footWorn || _worn) && inset > 0) {
      // The view still ends where the dock begins.
      strips.add(EdgeFadeStrip(rect: Rect.fromLTRB(0, math.max(0, edge), width, height), fade: EdgeFade(wholeUntil: edge, clearFrom: edge)));
    }
    return strips;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => notification.depth == 0 && _metrics(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => notification.depth == 0 && _metrics(notification.metrics),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return widget.child;
            final size = constraints.biggest;
            return ListenableBuilder(
              listenable: _turn,
              // A plain build shades the page's two edges with its own ground, and takes no picture of the view.
              builder: (context, child) {
                if (ghostPlain) {
                  return CustomPaint(
                    foregroundPainter: _wanted && (_worn || _footWorn)
                        ? PlainShade(ground: _ground, top: _worn ? widget.under : null, foot: _footWorn ? size.height - widget.footOver : null)
                        : null,
                    child: child,
                  );
                }
                final strips = _strips(size);
                return switch (edgeLook) {
                  EdgeLook.blur => EdgeStrips(strips: strips, child: child),
                  // The page's ground over the edges, and nothing taken of the view (edge_strips.dart [EdgeShade]).
                  EdgeLook.fade => CustomPaint(foregroundPainter: strips.isEmpty ? null : EdgeShade(strips: strips, ground: _ground), child: child),
                  // The blur as a backdrop filter, a band for each strip, under the strips' wash and fades
                  // (edge_backdrop.dart).
                  EdgeLook.backdrop => Stack(
                      fit: StackFit.expand,
                      children: [
                        child!,
                        for (final strip in strips.whereType<EdgeBlurStrip>())
                          Positioned.fromRect(rect: strip.rect, child: IgnorePointer(child: EdgeBackdropBand(side: strip.side, sigma: strip.sigma * strip.opacity))),
                        if (strips.isNotEmpty) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: EdgeShade(strips: strips, ground: _ground, wash: blurEdgeWash)))),
                      ],
                    ),
                };
              },
              // Where there is a mouse, a view under a header wears the page's own scrollbar, from the header's
              // foot down (app.css `[data-under-header]`); nothing on a phone.
              child: widget.scrollbar ? DesktopScrollbar(under: widget.under, child: widget.child) : widget.child,
            );
          },
        ),
      ),
    );
  }
}

/// How far a plain build's shade runs from a page's edge, and how much of the ground it is where it begins.
const double plainShadeDepth = 36;
const double plainShadeFull = 0.92;

/// A plain build's edges (lib/app/plain.dart; Matt, 2026-10-12: "use a slight mask gradient that fades content under
/// it or a gradient overlay"): the page's ground laid over what scrolls under a header and into the foot, fading to
/// nothing over [plainShadeDepth]. Two rectangles and no layer, where the blur takes a picture of the view.
class PlainShade extends CustomPainter {
  const PlainShade({required this.ground, this.top, this.foot});

  final Color ground;

  /// Where the header ends, when the page is scrolled under it; null with nothing to shade there.
  final double? top;

  /// Where the foot begins (the dock's top, or the view's own end), when more is under it; null otherwise.
  final double? foot;

  @override
  void paint(Canvas canvas, Size size) {
    final full = ground.withValues(alpha: plainShadeFull), none = ground.withValues(alpha: 0);
    if (top case final at?) {
      // Whatever is behind the header is under its own darker glass; from its edge the shade runs out.
      final rect = Rect.fromLTRB(0, at, size.width, math.min(size.height, at + plainShadeDepth));
      if (!rect.isEmpty) canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [full, none]));
    }
    if (foot case final at?) {
      final rect = Rect.fromLTRB(0, math.max(0, at - plainShadeDepth), size.width, at);
      if (!rect.isEmpty) canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [none, full]));
      // Past the foot's edge (beside and under the dock) the ground stands whole.
      if (at < size.height) canvas.drawRect(Rect.fromLTRB(0, at, size.width, size.height), Paint()..color = full);
    }
  }

  @override
  bool shouldRepaint(PlainShade old) => old.ground != ground || old.top != top || old.foot != foot;
}
