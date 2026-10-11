import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../render/constants.dart';
import '../../render/layout/custom_layout.dart';
import '../../render/layout/layout_builder_baseline.dart';
import '../../render/layout/min_dimension.dart';
import '../../render/layout/reset_baseline.dart';
import '../../render/svg/svg_geomertry.dart';
import '../../render/svg/svg_string.dart';
import '../../render/utils/render_box_offset.dart';
import '../../render/utils/render_box_layout.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

/// Square root node.
///
/// Examples:
/// - Word:   `\sqrt`   `\sqrt(index & base)`
/// - Latex:  `\sqrt`   `\sqrt[index]{base}`
/// - MathML: `msqrt`   `mroot`
class SqrtNode extends SlotableNode {
  /// The index.
  final EquationRowNode? index;

  /// The sqrt-and.
  final EquationRowNode base;

  SqrtNode({
    required this.index,
    required this.base,
  });

  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    final baseResult = childBuildResults[1]!;
    final indexResult = childBuildResults[0];
    return BuildResult(
      options: options,
      widget: CustomLayout<_SqrtPos>(
        delegate: SqrtLayoutDelegate(
          options: options,
          baseOptions: baseResult.options,
          // indexOptions: indexResult?.options,
        ),
        children: <Widget>[
          CustomLayoutId(
            id: _SqrtPos.base,
            child: MinDimension(
              minHeight: options.fontMetrics.xHeight.cssEm.toLpUnder(options),
              topPadding: 0,
              child: baseResult.widget,
            ),
          ),
          CustomLayoutId(
            id: _SqrtPos.surd,
            // we use IgnorePointer here to ignore root image during hit test,
            // so 'SelectionManagerMixin.getRenderLineAtOffset' can find
            // render lines in the base widget
            child: IgnorePointer(
              child: LayoutBuilderPreserveBaseline(
                builder: (context, constraints) => sqrtSvg(
                  minDelimiterHeight: constraints.minHeight,
                  baseWidth: constraints.minWidth,
                  options: options,
                ),
              ),
            ),
          ),
          if (index != null)
            CustomLayoutId(
              id: _SqrtPos.ind,
              child: indexResult!.widget,
            ),
        ],
      ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [
        options.havingStyle(MathStyle.scriptscript),
        options.havingStyle(options.style.cramp()),
      ];

  @override
  List<EquationRowNode?> computeChildren() => [index, base];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  SqrtNode updateChildren(List<EquationRowNode?> newChildren) => SqrtNode(
        index: newChildren[0],
        base: newChildren[1]!,
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'index': index?.toJson(),
      'base': base.toJson(),
    });

  SqrtNode copyWith({
    EquationRowNode? index,
    EquationRowNode? base,
  }) =>
      SqrtNode(
        index: index ?? this.index,
        base: base ?? this.base,
      );
}

enum _SqrtPos {
  base,
  ind, // Name collision here
  surd,
}

// Square roots are handled in the TeXbook pg. 443, Rule 11.
class SqrtLayoutDelegate extends CustomLayoutDelegate<_SqrtPos> {
  final MathOptions options;
  final MathOptions baseOptions;
  // final MathOptions indexOptions;

  SqrtLayoutDelegate({
    required this.options,
    required this.baseOptions,
    // required this.indexOptions,
  });
  var heightAboveBaseline = 0.0;
  var svgHorizontalPos = 0.0;
  var svgVerticalPos = 0.0;

  @override
  double computeDistanceToActualBaseline(
          TextBaseline baseline, Map<_SqrtPos, RenderBox> childrenTable) =>
      heightAboveBaseline;

  @override
  double getIntrinsicSize({
    required Axis sizingDirection,
    required bool max,
    required double extent,
    required double Function(RenderBox child, double extent) childSize,
    required Map<_SqrtPos, RenderBox> childrenTable,
  }) =>
      0;

  @override
  Size computeLayout(
    BoxConstraints constraints,
    Map<_SqrtPos, RenderBox> childrenTable, {
    bool dry = true,
  }) {
    final base = childrenTable[_SqrtPos.base]!;
    final index = childrenTable[_SqrtPos.ind];
    final surd = childrenTable[_SqrtPos.surd]!;

    final Size baseSize = base.getLayoutSize(infiniteConstraint, dry: dry);
    final Size indexSize = index?.getLayoutSize(
          infiniteConstraint,
          dry: dry,
        ) ??
        Size.zero;

    final baseHeight = dry ? 0 : base.layoutHeight;
    final baseWidth = baseSize.width;
    final indexHeight = dry ? 0 : index?.layoutHeight ?? 0.0;
    final indexWidth = indexSize.width;

    final theta = baseOptions.fontMetrics.defaultRuleThickness.cssEm
        .toLpUnder(baseOptions);
    var phi = baseOptions.style > MathStyle.text
        ? baseOptions.fontMetrics.xHeight.cssEm.toLpUnder(baseOptions)
        : theta;
    var psi = theta + 0.25 * phi.abs();

    final minSqrtHeight = baseSize.height + psi + theta;
    final surdConstraints = BoxConstraints(
      minWidth: baseWidth,
      minHeight: minSqrtHeight,
    );
    final Size surdSize = surd.getLayoutSize(surdConstraints, dry: dry);

    final advanceWidth = getSqrtAdvanceWidth(minSqrtHeight, baseWidth, options);

    // Parameters for index
    // from KaTeX/src/katex.less
    final indexRightPadding = -10.0.mu.toLpUnder(options);
    // KaTeX chose a way to large value (5mu). We will use a smaller one.
    final indexLeftPadding = 0.5.pt.toLpUnder(options);

    // Horizontal layout
    final sqrtHorizontalPos =
        math.max(0.0, indexLeftPadding + indexSize.width + indexRightPadding);
    final width = sqrtHorizontalPos + surdSize.width;

    // Vertical layout
    final ruleWidth = dry ? 0 : surd.layoutHeight;

    if (!dry) {
      final delimDepth = dry ? surdSize.height : surd.layoutDepth;

      if (delimDepth > baseSize.height + psi) {
        psi += 0.5 * (delimDepth - baseSize.height - psi);
      }
    }

    // Changed from 0.7.4 (README.md, 2): KaTeX sets a kern of the rule's own width above the root's rule
    // (functions/sqrt.js, the last child of its vlist), which is part of the root's height: a root stood
    // 0.04 em short without it.
    final bodyHeight = baseHeight + psi + ruleWidth + ruleWidth;
    final bodyDepth = surdSize.height + ruleWidth - bodyHeight;
    final indexShift = 0.6 * (bodyHeight - bodyDepth);
    final sqrtVerticalPos =
        math.max(0.0, indexHeight + indexShift - bodyHeight);
    final height = sqrtVerticalPos + surdSize.height + ruleWidth;

    // Position children
    if (!dry) {
      svgHorizontalPos = sqrtHorizontalPos;
      heightAboveBaseline = bodyHeight + sqrtVerticalPos;

      base.offset = Offset(
          sqrtHorizontalPos + advanceWidth, heightAboveBaseline - baseHeight);
      index?.offset = Offset(sqrtHorizontalPos - indexRightPadding - indexWidth,
          heightAboveBaseline - indexShift - indexHeight);
      surd.offset = Offset(sqrtHorizontalPos, sqrtVerticalPos + ruleWidth);
    }

    return Size(width, height);
  }
}

const vbPad = 80;
const emPad = vbPad / 1000;

/// What KaTeX's `sqrtImage` (delimiter.js) makes for a root that must reach [minDelimiterHeight], in logical
/// pixels, where [options] are in force.
///
/// Changed from 0.7.4 (README.md, 21). The published package chose the surd "at a strategy of its own": the first
/// of KaTeX_Main's and the four sizes, each at TEXT size, that is taller than the body. That is KaTeX's answer
/// where the root stands in text, and not where the type is smaller (over a fraction's bar in a line, in a
/// script, under a sum): there KaTeX sets a surd no taller than an em of the smaller type if that reaches
/// (`sizeMultiplier = 1.0`, "mimic a \textfont radical"), and the package set one an em of the text's, a half
/// taller, and as much wider. This is `sqrtImage` line for line, in the units it works in: ems of the type the
/// root stands in.
class Surd {
  const Surd._(this.path, this.em, this.fontHeight, this.height, this.advance, this.rule, this.viewBoxHeight);

  /// Which of svg_geomertry.dart's pictures: `sqrtMain`, `sqrtSize1` to `sqrtSize4`, `sqrtTall`.
  final String path;

  /// How many logical pixels a thousand units of the picture are.
  final double em;

  /// The picture's own height in its ems (1 for KaTeX_Main's, 1.2 to 3 for the sizes); null for the tall one,
  /// which is as tall as it is asked to be.
  final double? fontHeight;

  /// `texHeight`: the surd's height, in logical pixels, without the room left over its rule.
  final double height;

  /// How far along the body starts, and KaTeX's `ruleWidth`, in logical pixels.
  final double advance, rule;
  final double viewBoxHeight;

  factory Surd.of(double minDelimiterHeight, MathOptions options) {
    // An em of the type the root stands in, and how large that type is beside the text's where no size was said
    // (`options.havingBaseSizing().sizeMultiplier`: 1, 0.7 in a script, 0.5 in a script's script).
    final cur = 1.0.cssEm.toLpUnder(options);
    final base = MathSize.normalsize.underStyle(options.style).sizeMultiplier;
    final height = cur <= 0 ? 0.0 : minDelimiterHeight / cur;
    final thickness = options.fontMetrics.sqrtRuleThickness;
    // `traverseSequence("\\surd", height * newOptions.sizeMultiplier, stackLargeDelimiterSequence, newOptions)`.
    // `newOptions` is in text style whatever the root's was, so the sequence is entered at its third place:
    // KaTeX_Main's surd at text size (an em), then the four sizes, then the one that is drawn to measure.
    final sought = height * base;
    if (1.0 > sought) {
      // "mimic a \textfont radical", "mimic a \scriptfont radical", or the style's own.
      final by = height < 1.0 ? 1.0 : (height < 1.4 ? 0.7 : base);
      return Surd._('sqrtMain', cur / by, 1.0, cur / by, 0.833 * cur / by, thickness * by * cur, 1000.0 + vbPad);
    }
    const sizes = <double>[1.2, 1.8, 2.4, 3.0];
    for (var n = 0; n < sizes.length; n++) {
      if (sizes[n] > sought) {
        return Surd._('sqrtSize${n + 1}', cur / base, sizes[n], sizes[n] * cur / base, cur / base, thickness * base * cur, (1000 + vbPad) * sizes[n]);
      }
    }
    return Surd._('sqrtTall', cur, null, minDelimiterHeight, 1.056 * cur, thickness * base * cur, (1000 * height).floorToDouble() + vbPad);
  }
}

double getSqrtAdvanceWidth(
        double minDelimiterHeight, double baseWidth, MathOptions options) =>
    Surd.of(minDelimiterHeight, options).advance;

Widget sqrtSvg({
  required double minDelimiterHeight,
  required double baseWidth,
  required MathOptions options,
}) {
  final surd = Surd.of(minDelimiterHeight, options);
  const extraViniculum = 0.0;
  // TODO: support Settings.minRuleThickness.
  final pad = emPad * surd.em;
  // `span.style.minWidth`: 0.853em, 1.02em or 0.742em of the picture's own.
  final least = (surd.path == 'sqrtMain' ? 0.853 : (surd.path == 'sqrtTall' ? 0.742 : 1.02)) * surd.em;
  final viewPortWidth = math.max(surd.advance + baseWidth, least);
  final viewPortHeight = surd.height + pad;
  final viewBoxWidth = viewPortWidth / surd.em * 1000;
  final svgPath = sqrtPath(surd.path, extraViniculum, surd.viewBoxHeight);
  return ResetBaseline(
    height: surd.rule,
    child: MinDimension(
      topPadding: -pad,
      child: svgWidgetFromPath(
        svgPath,
        Size(viewPortWidth, viewPortHeight),
        Rect.fromLTWH(0, 0, viewBoxWidth, surd.viewBoxHeight),
        options.color,
        align: Alignment.topLeft,
        // KaTeX_Main's surd is stretched to its box, which is its own shape; the others keep theirs and are
        // cut at the box (`preserveAspectRatio="xMinYMin slice"`).
        fit: surd.path == 'sqrtMain' ? BoxFit.fill : BoxFit.cover,
      ),
    ),
  );
}
