import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A box that stays in sight at the top of the page it is a sliver of, over the slivers after it: `position:
/// sticky; top: 0; z-index: 2` on the first box of a block (book/BookView.module.css `.readBar`, in `.book`).
///
/// It is the first sliver of a group ([SliverMainAxisGroup]) and takes no room in it: the head's place in the flow
/// is kept by whatever follows (a notebook read straight through keeps a box of the bar's own height at the top of
/// its first run), so this draws the head where that place is until the page has scrolled it up to [top] from the
/// top of the scroll view, and from then on at [top], for as long as there is group left for it to stand in. A
/// group draws its first sliver last and asks it first what a press landed on, which is the `z-index`; and it
/// moves a sliver whose drawing would pass its own end up with that end, which is a sticky box going up with the
/// foot of the box that holds it.
///
/// [top] is the room the page keeps at its top (lib/note/page_head.dart): where a sticky box in a padded scroll
/// container comes to rest. [inset] is how far down its box the head itself begins (the notebook's padding over
/// the bar, which is part of the box so that the box starts where the run under it does): that much of the box is
/// let go above [top].
///
/// It says nothing of itself to whoever asks how far to scroll to show something (`maxScrollObstructionExtent` is
/// none): a page of the notebook gone to from the rail arrives at the top of the scroll view, under the bar, as
/// the web's `scrollIntoView({ block: 'start' })` leaves it.
///
/// Nothing is built or laid out again in the head as the page scrolls: it is one layer, moved.
class StuckHead extends SingleChildRenderObjectWidget {
  const StuckHead({super.key, this.top = 0, this.inset = 0, required Widget super.child});

  final double top;
  final double inset;

  @override
  RenderStuckHead createRenderObject(BuildContext context) => RenderStuckHead(top: top, inset: inset);

  @override
  void updateRenderObject(BuildContext context, RenderStuckHead renderObject) {
    renderObject
      ..top = top
      ..inset = inset;
  }
}

class RenderStuckHead extends RenderSliverSingleBoxAdapter {
  RenderStuckHead({double top = 0, double inset = 0})
      : _top = top,
        _inset = inset;

  double _top;
  set top(double value) {
    if (value == _top) return;
    _top = value;
    markNeedsLayout();
  }

  double _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsLayout();
  }

  /// Where the box is drawn, from this sliver's own start.
  double _at = 0;

  /// How far down from where it stands the head was last drawn: nothing while it is where its place is kept.
  double get shift => _at + constraints.scrollOffset;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = switch (constraints.axis) {
      Axis.vertical => child.size.height,
      Axis.horizontal => child.size.width,
    };
    final scrolled = constraints.scrollOffset;
    // Where this sliver starts in the scroll view: at its top once the group's start has gone past it, else as far
    // down as the room left for painting says.
    final start = scrolled > 0 ? 0.0 : math.max(0.0, constraints.viewportMainAxisExtent - constraints.remainingPaintExtent);
    // Where the box stands, and where it is held: the head in it no higher than [top].
    final at = math.max(-scrolled, _top - _inset - start);
    _at = at;
    final paintExtent = clampDouble(at + extent, 0, constraints.remainingPaintExtent);
    geometry = SliverGeometry(
      paintExtent: paintExtent,
      // No room of its own in the flow.
      layoutExtent: 0,
      maxPaintExtent: math.max(paintExtent, extent),
      hitTestExtent: paintExtent,
      hasVisualOverflow: true,
    );
    (child.parentData! as SliverPhysicalParentData).paintOffset = switch (constraints.axis) {
      Axis.vertical => Offset(0, at),
      Axis.horizontal => Offset(at, 0),
    };
  }

  @override
  double childMainAxisPosition(RenderBox child) => _at;
}
