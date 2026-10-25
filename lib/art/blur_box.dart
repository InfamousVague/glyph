import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'blur_edge.dart';
import 'edge_strips.dart';

/// The gradient blur for a small box that scrolls inside a page: a board's lane with more cards than it shows
/// ([BlurFoot]) and the tab row's ends ([BlurSides]). Where the wisp's smoke was (Matt, 2026-10-24: "replace the
/// smoke effect with a gradient blur on all places that use the wisp smoke", on every platform): what slides off the
/// box's open edge goes soft toward it and fades out at it. Nothing about it moves, so a box at rest costs nothing
/// after the paint that drew it. On Android a box's ends are their fades alone, as with the edges' switch off
/// ([edgeLook], [EdgeMasked]): a lane scrolled took a picture of its foot at every frame, and a backdrop's blur
/// cannot be faded out to a box's own ground.

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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return widget.child;
        // A box keeps its own picture: a row of tabs is painted again when a tab changes, not on every frame the
        // page under it scrolls, and a strip that was not painted again makes no pictures. Its strips know where
        // they were laid: edge_strips.dart.
        final strips = widget.build(constraints.biggest, BlurEdgeSettings.instance.wanted);
        // Where the edges are not the strips' (Android, [edgeLook]), a box's ends are its mask alone: no picture of
        // the box is taken, and a lane scrolled inside its mask paints nothing of the mask again.
        return RepaintBoundary(child: edgeLook == EdgeLook.blur ? EdgeStrips(strips: strips, child: widget.child) : EdgeMasked(strips: strips, child: widget.child));
      },
    );
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
/// [plainFade] alone.
class BlurSides extends StatelessWidget {
  const BlurSides({super.key, required this.start, required this.end, this.fade = blurSidesFade, this.plainFade = blurSidesFade, required this.child});

  final bool start, end;
  final double fade, plainFade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlurBoxed(
      build: (size, wanted) {
        if (!start && !end) return const [];
        final wide = size.width;
        final length = wanted ? fade : plainFade;
        final mask = EdgeFade(clearUntil: start ? 0 : -1e9, wholeFrom: start ? length : -1e9, wholeUntil: end ? wide - length : 1e9, clearFrom: end ? wide : 1e9);
        if (!wanted || wide <= blurSidesDepth * 2) {
          return [
            if (start) EdgeFadeStrip(rect: Rect.fromLTWH(0, 0, math.min(length, wide), size.height), fade: mask, axis: Axis.horizontal),
            if (end) EdgeFadeStrip(rect: Rect.fromLTWH(math.max(0, wide - length), 0, math.min(length, wide), size.height), fade: mask, axis: Axis.horizontal),
          ];
        }
        final depth = math.max(blurSidesDepth, length);
        return [
          if (start) EdgeBlurStrip(rect: Rect.fromLTWH(0, 0, depth, size.height), side: EdgeSide.left, sigma: blurSidesSigma, fade: mask),
          if (end) EdgeBlurStrip(rect: Rect.fromLTWH(wide - depth, 0, depth, size.height), side: EdgeSide.right, sigma: blurSidesSigma, fade: mask),
        ];
      },
      child: child,
    );
  }
}
