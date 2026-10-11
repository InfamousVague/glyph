import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Blocks one under another as a page lays them out: each as wide as the box that holds them, and the margin between
/// two the larger of the two rather than their sum (`margin-block` collapsing).
///
/// The sheet's kit and the sidebar's tree are written as paragraphs, lists and rows with margins of their own
/// (`.title { margin: 0 0 var(--glacier-space-4) }`, `.folder { margin-block: 1px }`), and their places on the page
/// depend on those margins collapsing: a heading's `space-2` above meets the group before it's `space-3` below and
/// 13.39px lies between them, not 22.32. A [Column] adds margins; this does what the page does, so a rule ports as it
/// is written. It covers the cases those stylesheets have, not all of CSS: blocks in normal flow, top to bottom.
///
/// A [CssFlow] is itself a block: [margin] is its own (the vertical halves collapse with its neighbours' when it
/// stands in another flow; outside one they are simply kept clear), [padding] is inside its box, and [decoration] is
/// painted on the box between the two. With [collapse], and no padding on that edge, its first child's top margin
/// and its last child's bottom margin collapse THROUGH it into its own, as they do through a `ul` with no padding:
/// the list's first row's margin becomes the list's.
class CssFlow extends MultiChildRenderObjectWidget {
  const CssFlow({super.key, this.margin = EdgeInsets.zero, this.padding = EdgeInsets.zero, this.decoration, this.collapse = false, super.children});

  /// A block of one child with margins: `p { margin: 0 0 1em }`.
  CssFlow.block({super.key, this.margin = EdgeInsets.zero, this.padding = EdgeInsets.zero, this.decoration, required Widget child})
      : collapse = false,
        super(children: [child]);

  final EdgeInsets margin;
  final EdgeInsets padding;

  /// Painted behind the children on the border box: what is left of the width inside [margin], top to bottom.
  final Decoration? decoration;
  final bool collapse;

  @override
  RenderCssFlow createRenderObject(BuildContext context) =>
      RenderCssFlow(margin: margin, padding: padding, decoration: decoration, collapse: collapse, configuration: createLocalImageConfiguration(context));

  @override
  void updateRenderObject(BuildContext context, RenderCssFlow renderObject) {
    renderObject
      ..margin = margin
      ..padding = padding
      ..decoration = decoration
      ..collapse = collapse
      ..configuration = createLocalImageConfiguration(context);
  }
}

class _FlowParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object of a [CssFlow]. Its size is its margin box across and its border box down: the vertical margins
/// are told to the flow it stands in ([marginTop], [marginBottom]), which places it; standing in anything else, they
/// are inside its size, as padding would be.
class RenderCssFlow extends RenderBox with ContainerRenderObjectMixin<RenderBox, _FlowParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _FlowParentData> {
  RenderCssFlow({required EdgeInsets margin, required EdgeInsets padding, Decoration? decoration, required bool collapse, required ImageConfiguration configuration})
      : _margin = margin,
        _padding = padding,
        _decoration = decoration,
        _collapse = collapse,
        _configuration = configuration;

  EdgeInsets _margin;
  EdgeInsets get margin => _margin;
  set margin(EdgeInsets value) {
    if (value == _margin) return;
    _margin = value;
    markNeedsLayout();
  }

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  Decoration? _decoration;
  Decoration? get decoration => _decoration;
  set decoration(Decoration? value) {
    if (value == _decoration) return;
    _painter?.dispose();
    _painter = null;
    _decoration = value;
    markNeedsPaint();
  }

  bool _collapse;
  bool get collapse => _collapse;
  set collapse(bool value) {
    if (value == _collapse) return;
    _collapse = value;
    markNeedsLayout();
  }

  ImageConfiguration _configuration;
  ImageConfiguration get configuration => _configuration;
  set configuration(ImageConfiguration value) {
    if (value == _configuration) return;
    _configuration = value;
    markNeedsPaint();
  }

  BoxPainter? _painter;
  double _marginTop = 0, _marginBottom = 0;

  /// This block's margins as they stand after its layout: its own, or the larger of its own and the child's that
  /// collapsed through it.
  double get marginTop => _marginTop;
  double get marginBottom => _marginBottom;

  /// Whether what holds this places it by its margins.
  bool get _inFlow => parent is RenderCssFlow;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FlowParentData) child.parentData = _FlowParentData();
  }

  @override
  void detach() {
    _painter?.dispose();
    _painter = null;
    super.detach();
  }

  static (double, double) _marginsOf(RenderBox child) => child is RenderCssFlow ? (child._marginTop, child._marginBottom) : (0, 0);

  @override
  void performLayout() {
    final bounded = constraints.hasBoundedWidth;
    final width = bounded ? constraints.maxWidth : double.infinity;
    final inner = bounded ? math.max(0.0, width - _margin.horizontal - _padding.horizontal) : double.infinity;
    final throughTop = _collapse && _padding.top == 0;
    final throughBottom = _collapse && _padding.bottom == 0;
    final left = _margin.left + _padding.left;

    var y = _padding.top;
    var widest = 0.0;
    var top = _margin.top;
    double? pending;
    var child = firstChild;
    while (child != null) {
      child.layout(bounded ? BoxConstraints.tightFor(width: inner) : const BoxConstraints(), parentUsesSize: true);
      final (above, below) = _marginsOf(child);
      if (pending == null) {
        // The first child: its margin joins this box's own, or is kept inside it.
        if (throughTop) {
          top = math.max(top, above);
        } else {
          y += above;
        }
      } else {
        y += math.max(pending, above);
      }
      (child.parentData! as _FlowParentData).offset = Offset(left, y);
      y += child.size.height;
      widest = math.max(widest, child.size.width);
      pending = below;
      child = childAfter(child);
    }
    var bottom = _margin.bottom;
    if (pending != null) {
      if (throughBottom) {
        bottom = math.max(bottom, pending);
      } else {
        y += pending;
      }
    }
    y += _padding.bottom;
    _marginTop = top;
    _marginBottom = bottom;

    // Outside a flow nothing reads the margins, so they are kept clear here: the children move down by the top one.
    final outside = _inFlow ? 0.0 : top;
    if (outside != 0) {
      child = firstChild;
      while (child != null) {
        final data = child.parentData! as _FlowParentData;
        data.offset = data.offset.translate(0, outside);
        child = childAfter(child);
      }
    }
    _boxTop = outside;
    _boxHeight = y;
    size = constraints.constrain(Size(bounded ? width : widest + _margin.horizontal + _padding.horizontal, y + (_inFlow ? 0 : top + bottom)));
  }

  double _boxTop = 0, _boxHeight = 0;

  /// The border box, in this render object's own coordinates.
  Rect get borderBox => Rect.fromLTWH(_margin.left, _boxTop, math.max(0, size.width - _margin.horizontal), _boxHeight);

  double _childrenHeight(double width, double Function(RenderBox child, double width) of) {
    final inner = math.max(0.0, width - _margin.horizontal - _padding.horizontal);
    var y = _padding.vertical + _margin.vertical;
    var child = firstChild;
    while (child != null) {
      y += of(child, inner);
      child = childAfter(child);
    }
    return y;
  }

  double _childrenWidth(double Function(RenderBox child) of) {
    var widest = 0.0;
    var child = firstChild;
    while (child != null) {
      widest = math.max(widest, of(child));
      child = childAfter(child);
    }
    return widest + _margin.horizontal + _padding.horizontal;
  }

  // Asked by nothing these surfaces do; answered without the collapsing, which only ever makes the true height less.
  @override
  double computeMinIntrinsicHeight(double width) => _childrenHeight(width, (child, inner) => child.getMinIntrinsicHeight(inner));

  @override
  double computeMaxIntrinsicHeight(double width) => _childrenHeight(width, (child, inner) => child.getMaxIntrinsicHeight(inner));

  @override
  double computeMinIntrinsicWidth(double height) => _childrenWidth((child) => child.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _childrenWidth((child) => child.getMaxIntrinsicWidth(double.infinity));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final decoration = _decoration;
    if (decoration != null) {
      final box = borderBox;
      (_painter ??= decoration.createBoxPainter(markNeedsPaint)).paint(context.canvas, offset + box.topLeft, _configuration.copyWith(size: box.size));
    }
    defaultPaint(context, offset);
  }
}
