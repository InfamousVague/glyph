import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../render/layout/reset_dimension.dart';
import '../../render/layout/shift_baseline.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

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

  BoxNode({
    required this.body,
    this.zeroWidth = false,
    this.zeroHeight = false,
    this.zeroDepth = false,
    this.align = CrossAxisAlignment.center,
    this.onAxis = false,
    this.doubled = false,
    this.type,
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
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.toJson(),
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
