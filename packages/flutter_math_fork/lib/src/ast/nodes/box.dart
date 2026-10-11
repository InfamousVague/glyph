import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../render/constants.dart';
import '../../render/layout/custom_layout.dart';
import '../../render/layout/reset_dimension.dart';
import '../../render/layout/shift_baseline.dart';
import '../../render/utils/render_box_layout.dart';
import '../../render/utils/render_box_offset.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';
import '../types.dart';
import 'left_right.dart' show makeStackedDelim;

/// What is in it, drawn, in a box measured otherwise than by what is in it: `\smash` (no height, no depth),
/// `\mathllap`, `\mathrlap` and `\mathclap` (no width, what is in it over its neighbour to one side or both),
/// `\vcenter` (its middle on the axis), and `\pmb` (drawn twice, a hair apart, for a bolder stroke).
///
/// Added to 0.7.4 (README.md, 16). KaTeX: functions/smash.js, lap.js, vcenter.js, pmb.js.
class BoxNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;
  final bool zeroWidth;
  final bool zeroHeight;
  final bool zeroDepth;

  /// Where what is in a box of no width lies: from its start on, up to its end, or about its middle.
  final CrossAxisAlignment align;

  /// Whether the box's middle is set on the maths axis.
  final bool onAxis;

  /// Whether it is drawn twice, 0.02em across and 0.01em down (KaTeX's `text-shadow` on `.pmb`).
  final bool doubled;

  /// The kind of atom it is; what is in it says where this is null.
  final AtomType? type;

  /// What its depth is taken to be less than it is, down to none: a `CD`'s last, empty row, which KaTeX counts
  /// where it sets the diagram about the axis and nothing reaches into.
  final Measurement? lessDepth;

  BoxNode({
    required this.body,
    this.zeroWidth = false,
    this.zeroHeight = false,
    this.zeroDepth = false,
    this.align = CrossAxisAlignment.center,
    this.onAxis = false,
    this.doubled = false,
    this.type,
    this.lessDepth,
  });

  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    var widget = childBuildResults[0]!.widget;
    if (doubled) {
      widget = _Doubled(
        shift: Offset(0.02.cssEm.toLpUnder(options), 0.01.cssEm.toLpUnder(options)),
        child: widget,
      );
    }
    if (onAxis) {
      widget = ShiftBaseline(
        relativePos: 0.5,
        offset: options.fontMetrics.axisHeight.cssEm.toLpUnder(options),
        child: widget,
      );
    }
    if (lessDepth != null) {
      widget = _LessDeep(by: lessDepth!.toLpUnder(options), child: widget);
    }
    if (zeroWidth || zeroHeight || zeroDepth) {
      widget = ResetDimension(
        width: zeroWidth ? 0 : null,
        height: zeroHeight ? 0 : null,
        depth: zeroDepth ? 0 : null,
        horizontalAlignment: align,
        child: widget,
      );
    }
    return BuildResult(
      options: options,
      italic: zeroWidth ? 0.0 : childBuildResults[0]!.italic,
      widget: widget,
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => type ?? body.leftType;

  @override
  AtomType get rightType => type ?? body.rightType;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  BoxNode updateChildren(List<EquationRowNode> newChildren) => BoxNode(
        body: newChildren[0],
        zeroWidth: zeroWidth,
        zeroHeight: zeroHeight,
        zeroDepth: zeroDepth,
        align: align,
        onAxis: onAxis,
        doubled: doubled,
        type: type,
        lessDepth: lessDepth,
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.toJson(),
      if (lessDepth != null) 'lessDepth': lessDepth.toString(),
      if (zeroWidth) 'zeroWidth': true,
      if (zeroHeight) 'zeroHeight': true,
      if (zeroDepth) 'zeroDepth': true,
      if (onAxis) 'onAxis': true,
      if (doubled) 'doubled': true,
    });
}

class _Doubled extends SingleChildRenderObjectWidget {
  const _Doubled({required this.shift, required Widget child})
      : super(child: child);

  final Offset shift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDoubled(shift);

  @override
  void updateRenderObject(BuildContext context, _RenderDoubled renderObject) =>
      renderObject.shift = shift;
}

class _RenderDoubled extends RenderProxyBox {
  _RenderDoubled(this._shift);

  Offset _shift;
  set shift(Offset value) {
    if (value == _shift) return;
    _shift = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset + _shift);
    context.paintChild(child, offset);
  }
}

/// One of four, by the style it is built in: `\mathchoice{display}{text}{script}{scriptscript}`.
///
/// Added to 0.7.4 (README.md, 16). KaTeX: functions/mathchoice.js.
class StyleChoiceNode extends SlotableNode<EquationRowNode> {
  /// For display, text, script and scriptscript style, in that order.
  final List<EquationRowNode> choices;

  StyleChoiceNode({required this.choices}) : assert(choices.length == 4);

  static int _index(MathOptions options) {
    final size = options.style.size;
    if (size == MathStyle.display.size) return 0;
    if (size == MathStyle.text.size) return 1;
    if (size == MathStyle.script.size) return 2;
    return 3;
  }

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      childBuildResults[_index(options)]!;

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      List.filled(4, options, growable: false);

  @override
  List<EquationRowNode> computeChildren() => choices;

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      _index(oldOptions) != _index(newOptions);

  @override
  StyleChoiceNode updateChildren(List<EquationRowNode> newChildren) =>
      StyleChoiceNode(choices: newChildren);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({'choices': choices.map((choice) => choice.toJson()).toList()});
}

/// The two marks an angle is drawn round what is in it with.
enum AngleKind {
  /// `\angl`, the actuary's: a rule over it and a rule down its right.
  actuarial,

  /// `\phase`, steinmetz's: an angle that opens to the right, under it and before it.
  phase,
}

/// What is in it with an angle drawn round it: `\angl{n}` and `\phase{x}`.
///
/// Added to 0.7.4 (README.md, 20). KaTeX: functions/enclose.js (`angl`, `phase`), stretchy.js `encloseSpan`,
/// svgGeometry.js `phasePath`, and `.anglpad` and `.angl` of katex.less.
class AngleNode extends SlotableNode<EquationRowNode> {
  final EquationRowNode body;
  final AngleKind kind;

  AngleNode({required this.body, required this.kind});

  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    final rule =
        options.fontMetrics.defaultRuleThickness.cssEm.toLpUnder(options);
    return BuildResult(
      options: options,
      widget: kind == AngleKind.actuarial
          ? _Angle(
              kind: kind,
              color: options.color,
              // The rule, three of it clear between the rule and what is under it, and room below down to a
              // quarter of an em where what is in it does not reach so far.
              rule: rule,
              above: 4 * rule,
              minDepth: 0.25.cssEm.toLpUnder(options),
              side: 0.03889.cssEm.toLpUnder(options),
              unit: 0,
              child: childBuildResults[0]!.widget,
            )
          : _Angle(
              kind: kind,
              color: options.color,
              // "A couple of dimensions from the steinmetz package": the line's weight and the room over it.
              rule: 0.6.pt.toLpUnder(options),
              above: 0.35.ex.toLpUnder(options),
              minDepth: 0,
              side: 0,
              // The angle is drawn in thousandths of an em.
              unit: 0.001.cssEm.toLpUnder(options),
              child: childBuildResults[0]!.widget,
            ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  AngleNode updateChildren(List<EquationRowNode> newChildren) =>
      AngleNode(body: newChildren[0], kind: kind);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({'body': body.toJson(), 'kind': kind.toString()});
}

class _Angle extends SingleChildRenderObjectWidget {
  const _Angle({
    required this.kind,
    required this.color,
    required this.rule,
    required this.above,
    required this.minDepth,
    required this.side,
    required this.unit,
    required Widget child,
  }) : super(child: child);

  final AngleKind kind;
  final Color color;
  final double rule, above, minDepth, side, unit;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAngle(this);

  @override
  void updateRenderObject(BuildContext context, _RenderAngle renderObject) =>
      renderObject.look = this;
}

class _RenderAngle extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderAngle(this._look);

  _Angle _look;
  set look(_Angle value) {
    final old = _look;
    _look = value;
    if (old.kind != value.kind ||
        old.rule != value.rule ||
        old.above != value.above ||
        old.minDepth != value.minDepth ||
        old.side != value.side ||
        old.unit != value.unit) {
      markNeedsLayout();
    } else if (old.color != value.color) {
      markNeedsPaint();
    }
  }

  double _baseline = 0;
  Offset _at = Offset.zero;

  /// The box for a child of this size standing `height` above its baseline, where it is put in it, and how far
  /// the box's own baseline is from its top.
  (Size, Offset, double) _around(Size child, double height) {
    final depth = child.height - height;
    if (_look.kind == AngleKind.actuarial) {
      final below = math.max(depth, _look.minDepth);
      return (
        Size(child.width + 2 * _look.side, _look.above + height + below),
        Offset(_look.side, _look.above),
        _look.above + height,
      );
    }
    // The angle is as tall as what is in it, the line and the room over the line; it is half as wide as it is
    // tall, and what is in it starts after it and the line.
    final tall = child.height + _look.rule + _look.above;
    final before = tall / 2 + _look.rule;
    return (Size(child.width + before, tall), Offset(before, 0), height);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return Size.zero;
    final size = child.getDryLayout(const BoxConstraints());
    return _around(size, size.height).$1;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      computeMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final child = this.child;
    if (child == null) return 0;
    final width = child.getMaxIntrinsicWidth(double.infinity);
    final tall = child.getMaxIntrinsicHeight(double.infinity);
    return _around(Size(width, tall), tall).$1.width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final child = this.child;
    if (child == null) return 0;
    final tall = child.getMaxIntrinsicHeight(double.infinity);
    return _around(Size(0, tall), tall).$1.height;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      return;
    }
    child.layout(const BoxConstraints(), parentUsesSize: true);
    final height =
        child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ??
            child.size.height;
    final (box, at, baseline) = _around(child.size, height);
    size = box;
    _at = at;
    _baseline = baseline;
    (child.parentData! as BoxParentData).offset = at;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _at,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _at);
    final paint = Paint()..color = _look.color;
    final canvas = context.canvas;
    if (_look.kind == AngleKind.actuarial) {
      // The box's own top and right edge, as a border of the rule's width is drawn inside its box.
      canvas.drawRect(offset & Size(size.width, _look.rule), paint);
      canvas.drawRect(
          Offset(offset.dx + size.width - _look.rule, offset.dy) &
              Size(_look.rule, size.height),
          paint);
      return;
    }
    // KaTeX's `phasePath(y)`: `M400000 y H0 L x 0 l65 45 L145 y-80 H400000z`, x half of y, cut off at the box.
    final unit = _look.unit;
    if (unit <= 0) return;
    final y = size.height / unit, x = y / 2, far = size.width / unit;
    final path = Path()
      ..moveTo(far, y)
      ..lineTo(0, y)
      ..lineTo(x, 0)
      ..relativeLineTo(65, 45)
      ..lineTo(145, y - 80)
      ..lineTo(far, y - 80)
      ..close();
    canvas.save();
    canvas.clipRect(offset & size);
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(unit);
    canvas.drawPath(path, paint);
    canvas.restore();
  }
}

/// What is in it, taken to be [by] less deep than it is, and never less than not deep at all.
class _LessDeep extends SingleChildRenderObjectWidget {
  const _LessDeep({required this.by, required Widget child})
      : super(child: child);

  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLessDeep(by);

  @override
  void updateRenderObject(BuildContext context, _RenderLessDeep renderObject) =>
      renderObject.by = by;
}

class _RenderLessDeep extends RenderShiftedBox {
  _RenderLessDeep(this._by) : super(null);

  double _by;
  set by(double value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  double _baseline = 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(constraints) ?? Size.zero;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size.zero;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    _baseline =
        child.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ??
            child.size.height;
    final depth = math.max(0.0, child.size.height - _baseline - _by);
    size = Size(child.size.width, _baseline + depth);
    (child.parentData! as BoxParentData).offset = Offset.zero;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;
}

/// A delimiter that is always built of pieces (an arrow up or down, two bars) at the size `\Big` gives it, with a
/// label to its left and one to its right that take no room of their own: an arrow of a `CD`, whose row and
/// column are as tall and as wide as the arrow alone.
///
/// Added to 0.7.4 (README.md, 20). KaTeX: environments/cd.js (`\Big` of the arrow; `\\cdleft`, `\\cdright`,
/// `\\cdparent`: a label in script style, its height and depth zeroed, `bottom: 0.8em` less its depth),
/// delimiter.js (`sizedDelim`: one that always stacks is stacked to 1.8em for `\Big`), and `.cd-label-left` and
/// `.cd-label-right` of katex.less (`calc(50% + 0.3em)` from the other side).
///
/// And any delimiter that always stacks at any of the four sizes, with no labels: `\big|`, `\Big\Vert`,
/// `\bigg\uparrow`. The published package set these as one glyph of the size's face, which has none for them, so
/// they were drawn at the size of a line.
class StackedDelimNode extends SlotableNode<EquationRowNode> {
  /// The delimiter, as left_right.dart's `stackDelimiterConfs` knows it.
  final String delim;

  /// How tall it is built to be at least: 1.2, 1.8, 2.4 and 3 ems for `\big`, `\Big`, `\bigg` and `\Bigg`
  /// (`sizeToMaxHeight`).
  final Measurement height;

  /// The kind of atom it is (`\bigl` opens, `\bigr` closes, `\bigm` relates).
  final AtomType type;
  final EquationRowNode left;
  final EquationRowNode right;

  StackedDelimNode({
    required this.delim,
    required this.height,
    this.type = AtomType.ord,
    EquationRowNode? left,
    EquationRowNode? right,
  })  : left = left ?? EquationRowNode.empty(),
        right = right ?? EquationRowNode.empty();

  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    // The label's own em: it is set in script style.
    final small = options.havingStyle(options.style.sup());
    return BuildResult(
      options: options,
      widget: CustomLayout<int>(
        delegate: SideLabelsDelegate(
          gap: 0.3.cssEm.toLpUnder(small),
          rise: 0.8.cssEm.toLpUnder(small),
        ),
        children: <Widget>[
          CustomLayoutId(
            id: 0,
            child: makeStackedDelim(
                delim, height.toLpUnder(options), Mode.math, options),
          ),
          CustomLayoutId(id: 1, child: childBuildResults[0]!.widget),
          CustomLayoutId(id: 2, child: childBuildResults[1]!.widget),
        ],
      ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) {
    final small = options.havingStyle(options.style.sup());
    return [small, small];
  }

  @override
  List<EquationRowNode> computeChildren() => [left, right];

  @override
  AtomType get leftType => type;

  @override
  AtomType get rightType => type;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier;

  @override
  StackedDelimNode updateChildren(List<EquationRowNode> newChildren) =>
      StackedDelimNode(
        delim: delim,
        height: height,
        type: type,
        left: newChildren[0],
        right: newChildren[1],
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'delim': delim,
      'height': height.toString(),
      if (left.children.isNotEmpty) 'left': left.toJson(),
      if (right.children.isNotEmpty) 'right': right.toJson(),
    });
}

/// The body (0) as it is; the left label (1) ending [gap] before its middle and the right one (2) starting [gap]
/// after it, each with its baseline [rise] above the body's foot.
class SideLabelsDelegate extends CustomLayoutDelegate<int> {
  SideLabelsDelegate({required this.gap, required this.rise});

  final double gap;
  final double rise;

  var height = 0.0;

  @override
  double computeDistanceToActualBaseline(
          TextBaseline baseline, Map<int, RenderBox> childrenTable) =>
      height;

  @override
  double getIntrinsicSize({
    required Axis sizingDirection,
    required bool max,
    required double extent,
    required double Function(RenderBox child, double extent) childSize,
    required Map<int, RenderBox> childrenTable,
  }) =>
      childSize(childrenTable[0]!, double.infinity);

  @override
  Size computeLayout(
    BoxConstraints constraints,
    Map<int, RenderBox> childrenTable, {
    bool dry = true,
  }) {
    final body = childrenTable[0]!;
    final size = body.getLayoutSize(infiniteConstraint, dry: dry);
    final sides = [
      for (final id in const [1, 2])
        childrenTable[id]!.getLayoutSize(infiniteConstraint, dry: dry),
    ];
    if (dry) return size;
    double above(RenderBox box) =>
        box.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true) ??
        box.size.height;
    height = above(body);
    body.offset = Offset.zero;
    final left = childrenTable[1]!, right = childrenTable[2]!;
    final line = size.height - rise;
    left.offset =
        Offset(size.width / 2 - gap - sides[0].width, line - above(left));
    right.offset = Offset(size.width / 2 + gap, line - above(right));
    return size;
  }
}
