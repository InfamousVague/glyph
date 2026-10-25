import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'blur_edge.dart';
import 'edge_backdrop.dart';
import 'edge_strips.dart';

/// The gradient blur for a small box that scrolls inside a page: a board's lane with more cards than it shows
/// ([BlurFoot]) and the tab row's ends ([BlurSides]). Where the wisp's smoke was (Matt, 2026-10-24: "replace the
/// smoke effect with a gradient blur on all places that use the wisp smoke", on every platform): what slides off the
/// box's open edge goes soft toward it and fades out at it. Nothing about it moves, so a box at rest costs nothing
/// after the paint that drew it.
///
/// On Android a box's ends are blurred as a page's are, by a backdrop band of the screen for each end
/// (lib/art/edge_backdrop.dart), over the box's own fade (Matt, 2026-10-25, on the Fold: "the cassette area needs to
/// have a blur not a gradient"). They were the fades alone ([EdgeMasked]): a lane scrolled took a picture of its foot
/// at every frame, and a backdrop's blur cannot be faded out to a box's own ground. Now the box is drawn through its
/// fade as it was, clear at its edge, and the bands are laid over it in a [BackdropGroup] of the box's own, so they
/// read the box as it was just drawn and not a backdrop a page around it read before; each band's softness is its
/// strip's as much as the end shows, and its blur clears again toward the edge over the fade's length
/// ([EdgeBackdropBand.clear]), so nothing the blur gathered stands past the fade. Two bands at most, no picture. Where
/// the engine cannot filter by a shader ([EdgeLook.fade]) the ends are their fades alone.

/// A lane's foot: how deep its blur runs at most (half the lane, on a short one), and how soft at the edge.
const double blurFootDepth = 32;
const double blurFootSigma = 5;

/// A row's open end: how far in its blur runs, and how soft at the edge. Smaller than a page's: a tab's words are
/// small.
const double blurSidesDepth = 28;
const double blurSidesSigma = 4;

/// The fade a row's open end wears (notes/NoteTabs.module.css `--tab-fade-start`, `--tab-fade-end`).
const double blurSidesFade = 12;

/// Draws [child] through the strips [build] gives for a box of its size: what [BlurFoot] and [BlurSides] share.
class BlurBoxed extends StatefulWidget {
  const BlurBoxed({super.key, required this.build, required this.child});

  /// The strips for a box of this size; [wanted] is the edges' switch ([BlurEdgeSettings.wanted]).
  final List<EdgeStrip> Function(Size size, bool wanted) build;
  final Widget child;

  @override
  State<BlurBoxed> createState() => _BlurBoxedState();
}

class _BlurBoxedState extends State<BlurBoxed> {
  @override
  void initState() {
    super.initState();
    BlurEdgeSettings.instance.addListener(_changed);
    // The bands' shader, as a page with soft edges loads it: a box may be the first thing on the screen to blur.
    if (edgeLook == EdgeLook.backdrop) EdgeBackdropProgram.load();
  }

  @override
  void dispose() {
    BlurEdgeSettings.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    List<EdgeStrip> strips(Size size) => widget.build(size, BlurEdgeSettings.instance.wanted);
    return LayoutBuilder(
      builder: (context, constraints) {
        final Widget drawn;
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          // A box as tall as what it holds (a row of cassettes, lib/home/meeting_shelf.dart) is not a size to build
          // strips for here: its strips are made once it is laid out ([_LaidStrips]).
          drawn = _LaidStrips(build: strips, child: widget.child);
        } else if (edgeLook == EdgeLook.blur) {
          // A box keeps its own picture: a row of tabs is painted again when a tab changes, not on every frame the
          // page under it scrolls, and a strip that was not painted again makes no pictures. Its strips know where
          // they were laid: edge_strips.dart.
          drawn = EdgeStrips(strips: strips(constraints.biggest), child: widget.child);
        } else {
          // Where the edges are not the strips' (Android, [edgeLook]), a box's ends are its mask: no picture of the
          // box is taken, and a lane scrolled inside its mask paints nothing of the mask again.
          drawn = EdgeMasked(strips: strips(constraints.biggest), child: widget.child);
        }
        if (edgeLook != EdgeLook.backdrop) return RepaintBoundary(child: drawn);
        // And over the mask, a band for each end that blurs, read in a group of the box's own. The bands are laid
        // out at the box's own size once it has one, which a box as tall as what it holds has only then.
        return RepaintBoundary(
          child: BackdropGroup(
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                drawn,
                Positioned.fill(child: IgnorePointer(child: LayoutBuilder(builder: (context, box) => BoxBands(strips: strips(box.biggest))))),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// How much of a box's fade its band's blur clears over again at the edge ([EdgeBackdropBand.clear]): all of it. On
/// the ghostflutter2 emulator with none, a sixth of a cassette's colour stood at the shelf's edge and stopped there;
/// over half the fade, the glow the blur draws above and below a cassette still stopped in a line at the edge
/// (build/feature-shots/shelf-blur/edge-clear-*.png).
const double blurBoxClear = 1;

/// A box's ends as backdrop bands (Android, [EdgeLook.backdrop]): a band where each [EdgeBlurStrip] lies, as soft as
/// the strip as much as it shows ([EdgeBlurStrip.opacity]), its blur clearing again toward the edge over the strip's
/// fade ([blurBoxClear]). A fade alone has no band.
class BoxBands extends StatelessWidget {
  const BoxBands({super.key, required this.strips});

  final List<EdgeStrip> strips;

  /// How long [strip]'s fade is at its edge, the ramp from whole to clear, or none.
  static double fadeAt(EdgeBlurStrip strip) {
    final fade = strip.fade;
    if (fade == null) return 0;
    const nowhere = 1e8;
    final length = switch (strip.side) {
      EdgeSide.top || EdgeSide.left => fade.wholeFrom > -nowhere ? fade.wholeFrom - fade.clearUntil : 0.0,
      EdgeSide.bottom || EdgeSide.right => fade.wholeUntil < nowhere ? fade.clearFrom - fade.wholeUntil : 0.0,
    };
    return math.max(0, length);
  }

  @override
  Widget build(BuildContext context) {
    final blurs = strips.whereType<EdgeBlurStrip>().where((strip) => strip.sigma * strip.opacity > 0).toList();
    return Stack(
      children: [
        for (final strip in blurs)
          Positioned.fromRect(
            rect: strip.rect,
            child: EdgeBackdropBand(side: strip.side, sigma: strip.sigma * strip.opacity.clamp(0.0, 1.0), clear: fadeAt(strip) * blurBoxClear),
          ),
      ],
    );
  }
}

/// [child] drawn through the strips [build] gives for the size it is laid out at, where the box's size is its own
/// and a [LayoutBuilder] above it is told no height: the strips are made as the box is laid out, and again when
/// [build] changes. The rest is [BlurBoxed]'s: [EdgeStrips] where the edges are the strips, [EdgeMasked] elsewhere.
class _LaidStrips extends SingleChildRenderObjectWidget {
  const _LaidStrips({required this.build, super.child});

  final List<EdgeStrip> Function(Size size) build;

  @override
  RenderBox createRenderObject(BuildContext context) =>
      edgeLook == EdgeLook.blur ? _RenderLaidStrips(build: build, ratio: MediaQuery.devicePixelRatioOf(context)) : _RenderLaidMask(build: build);

  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) {
    switch (renderObject) {
      case _RenderLaidStrips strips:
        strips
          ..ratio = MediaQuery.devicePixelRatioOf(context)
          ..build = build;
      case _RenderLaidMask mask:
        mask.build = build;
    }
  }
}

class _RenderLaidStrips extends RenderEdgeStrips {
  _RenderLaidStrips({required List<EdgeStrip> Function(Size size) build, required super.ratio}) : _build = build, super(strips: const []);

  List<EdgeStrip> Function(Size size) _build;
  set build(List<EdgeStrip> Function(Size size) value) {
    _build = value;
    if (hasSize) strips = value(size);
  }

  @override
  void performLayout() {
    super.performLayout();
    strips = _build(size);
  }
}

class _RenderLaidMask extends RenderEdgeMasked {
  _RenderLaidMask({required List<EdgeStrip> Function(Size size) build}) : _build = build, super(strips: const []);

  List<EdgeStrip> Function(Size size) _build;
  set build(List<EdgeStrip> Function(Size size) value) {
    _build = value;
    if (hasSize) strips = value(size);
  }

  @override
  void performLayout() {
    super.performLayout();
    strips = _build(size);
  }
}

/// A lane's foot: wrap the lane's scroller, and say whether there is [more] below than it shows
/// (editor/boards/height.ts `laneFoot`, which marks a lane with `data-more`).
///
/// With more below, the cards go soft over the lane's last [blurFootDepth] (half a short lane) and fade out over
/// [plainFade], the stylesheet's `1.2em`, which the caller gives in px; with the edges' switch off, the fade alone.
/// With no more below, the lane is drawn as it is.
class BlurFoot extends StatelessWidget {
  const BlurFoot({super.key, required this.more, required this.plainFade, required this.child});

  final bool more;
  final double plainFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlurBoxed(
      build: (size, wanted) {
        if (!more) return const [];
        final tall = size.height;
        final fade = EdgeFade(wholeUntil: tall - plainFade, clearFrom: tall);
        if (!wanted) return [EdgeFadeStrip(rect: Rect.fromLTRB(0, math.max(0, tall - plainFade), size.width, tall), fade: fade)];
        final depth = math.max(plainFade, math.min(blurFootDepth, tall / 2));
        return [EdgeBlurStrip(rect: Rect.fromLTRB(0, math.max(0, tall - depth), size.width, tall), side: EdgeSide.bottom, sigma: blurFootSigma, fade: fade)];
      },
      child: child,
    );
  }
}

/// A row's open ends: wrap the row that scrolls sideways, and say which ends have tabs past them
/// (notes/useTabOutline.ts, which marks the ends; notes/NoteTabs.module.css, which fades them).
///
/// An open end goes soft over [blurSidesDepth] and fades out over [fade]; with the edges' switch off, it fades over
/// [plainFade] alone. [startShown] and [endShown] are how much of each end shows, 0 to 1, for a row whose ends go
/// as it nears them ([sideShown]): the fade that much of its length, the blur that much of itself.
class BlurSides extends StatelessWidget {
  const BlurSides({
    super.key,
    required this.start,
    required this.end,
    this.fade = blurSidesFade,
    this.plainFade = blurSidesFade,
    this.startShown = 1,
    this.endShown = 1,
    required this.child,
  });

  final bool start, end;
  final double fade, plainFade;
  final double startShown, endShown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlurBoxed(
      build: (size, wanted) {
        final starts = start && startShown > 0, ends = end && endShown > 0;
        if (!starts && !ends) return const [];
        final wide = size.width;
        final length = wanted ? fade : plainFade;
        final first = length * startShown.clamp(0.0, 1.0), last = length * endShown.clamp(0.0, 1.0);
        final mask = EdgeFade(clearUntil: starts ? 0 : -1e9, wholeFrom: starts ? first : -1e9, wholeUntil: ends ? wide - last : 1e9, clearFrom: ends ? wide : 1e9);
        if (!wanted || wide <= blurSidesDepth * 2) {
          return [
            if (starts) EdgeFadeStrip(rect: Rect.fromLTWH(0, 0, math.min(length, wide), size.height), fade: mask, axis: Axis.horizontal),
            if (ends) EdgeFadeStrip(rect: Rect.fromLTWH(math.max(0, wide - length), 0, math.min(length, wide), size.height), fade: mask, axis: Axis.horizontal),
          ];
        }
        final depth = math.max(blurSidesDepth, length);
        return [
          if (starts) EdgeBlurStrip(rect: Rect.fromLTWH(0, 0, depth, size.height), side: EdgeSide.left, sigma: blurSidesSigma, fade: mask, opacity: startShown.clamp(0.0, 1.0)),
          if (ends) EdgeBlurStrip(rect: Rect.fromLTWH(wide - depth, 0, depth, size.height), side: EdgeSide.right, sigma: blurSidesSigma, fade: mask, opacity: endShown.clamp(0.0, 1.0)),
        ];
      },
      child: child,
    );
  }
}

/// How much of a row's end shows with [past] logical pixels of the row past it, 0 to 1: all of it with a whole
/// [blurSidesDepth] or more to come, none with nothing, and a straight line between, so an end goes as the row is
/// scrolled to it and is gone when it gets there (a fling that ends there takes it out as it slows).
double sideShown(double past) => (past / blurSidesDepth).clamp(0.0, 1.0);
