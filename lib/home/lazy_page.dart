/// A page of notes that builds only what is near the screen: the scroller the home page and All notes share, and
/// what a pull to refresh does to it.
///
/// Both pages were one `SingleChildScrollView` over a `Column`: every card and row built, laid out and painted,
/// near the screen or not, and all of it again whenever the page was. Measured walking a library of 354 notes
/// (tool/perf.sh, 2026-10-10), coming back to the home page was one frame of 500 to 1,700 ms, most of it 350 rows
/// under "Today". They are a `CustomScrollView` now, each list in them a sliver that builds the rows on and near
/// the screen ([PageScroll]).
///
/// What a page keeps as it was:
/// - **Where everything stands.** A sliver is laid out from the same widths and the same gaps the column was;
///   test/home and test/allnotes hold the rectangles and the pictures.
/// - **The pull.** A pull to refresh lowers the page's content inside its scroller, under the top bar
///   (lib/notes/pull_to_refresh.dart `PullLowered`: a translate, with a transition while it settles). A sliver
///   cannot be wrapped in a box's transform, so each is drawn lower by [SliverShift], which moves what is painted
///   and where a touch lands and nothing of the layout, as a translate does.
/// - **Whoever finds the scroller by what it says** (the smoke under the header, the desktop's scrollbar): it is
///   still the one vertical scroller under them, and says the same things.
///
/// What differs, and cannot but: how far the page scrolls is known only as far as its rows have been laid out, as
/// with any list built as it is scrolled; past that it is counted from the rows seen so far, and put right as the
/// rest come by.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../notes/pull_to_refresh.dart';

/// A page's scroller: [slivers] in a `CustomScrollView`, lowered by [pull] where the page pulls to refresh.
///
/// The slivers handed in are kept as they are from one pull's move to the next: only how far down they are drawn
/// changes, so nothing in them is built again while a finger drags the page.
class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.controller, this.pull, required this.slivers});

  final ScrollController controller;

  /// How far the page's content is down, and the physics it scrolls with meanwhile; null for a page that does not
  /// pull.
  final PullDown? pull;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final pull = this.pull;
    if (pull == null) return CustomScrollView(controller: controller, slivers: slivers);
    // `translate: 0 <px>`, with `transition: translate 240ms ease-out` while it settles and none under the finger.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: pull.offset),
      duration: pull.settling ? const Duration(milliseconds: 240) : Duration.zero,
      curve: context.tokens.curve('glacier-ease-out'),
      builder: (context, dy, _) => CustomScrollView(
        controller: controller,
        physics: pull.physics,
        slivers: [for (final sliver in slivers) SliverShift(dy: dy, sliver: sliver)],
      ),
    );
  }
}

/// A sliver drawn [dy] lower than it is laid out: `translate: 0 <dy>px` for a sliver. Its place in the scroller,
/// its size and what it builds are as they would be; what it paints and where a touch finds it are [dy] down.
class SliverShift extends SingleChildRenderObjectWidget {
  const SliverShift({super.key, required this.dy, required Widget sliver}) : super(child: sliver);

  final double dy;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSliverShift(dy);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderSliverShift).dy = dy;
}

class _RenderSliverShift extends RenderProxySliver {
  _RenderSliverShift(this._dy);

  double _dy;
  set dy(double value) {
    if (value == _dy) return;
    _dy = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sliver = child;
    if (sliver != null) context.paintChild(sliver, _dy == 0 ? offset : offset.translate(0, _dy));
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_dy != 0) transform.translateByDouble(0, _dy, 0, 1);
  }

  @override
  bool hitTest(SliverHitTestResult result, {required double mainAxisPosition, required double crossAxisPosition}) {
    final sliver = child;
    if (sliver == null) return false;
    if (_dy == 0) return super.hitTest(result, mainAxisPosition: mainAxisPosition, crossAxisPosition: crossAxisPosition);
    // The touch is asked of the sliver where it was drawn, before this one's own measure is asked: what was moved
    // down past its end is still it.
    return result.addWithAxisOffset(
      paintOffset: Offset(0, _dy),
      mainAxisOffset: _dy,
      crossAxisOffset: 0,
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
      hitTest: sliver.hitTest,
    );
  }
}

/// A card with its note's line of what it is about, read from the lines its page was last handed: built again when
/// its own note's line changes, and not when another's does. The phone writes the lines one at a time in the
/// background, and a page that was handed them as one map drew every card again for each.
class Gisted extends StatefulWidget {
  const Gisted({super.key, required this.gists, required this.id, required this.builder});

  final ValueListenable<Map<String, String>> gists;
  final String id;
  final Widget Function(BuildContext context, String? gist) builder;

  @override
  State<Gisted> createState() => _GistedState();
}

class _GistedState extends State<Gisted> {
  late String? _gist = widget.gists.value[widget.id];

  @override
  void initState() {
    super.initState();
    widget.gists.addListener(_changed);
  }

  @override
  void didUpdateWidget(Gisted oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.gists, widget.gists)) {
      oldWidget.gists.removeListener(_changed);
      widget.gists.addListener(_changed);
    }
    _gist = widget.gists.value[widget.id];
  }

  @override
  void dispose() {
    widget.gists.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.gists.value[widget.id];
    if (next != _gist && mounted) setState(() => _gist = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _gist);
}
