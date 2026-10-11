import '../options.dart';
import '../style.dart';
import '../syntax_tree.dart';

/// An operator's name with what is written under and over it set as limits in display style and as scripts
/// beside it otherwise: `\lim_{x \to 0}`, `\max_i`, `\operatorname*{argmax}_\theta`.
///
/// Added to 0.7.4 (README.md, 13). KaTeX decides between the two as it builds, by the style it is building in
/// (functions/op.js: `limits && style.size === DISPLAY`); here it was decided as the formula was read, always
/// for limits, so in a line of text a limit stood under its `lim` and made the line taller.
///
/// It holds both settings, each a tree of its own, and builds the one its style asks for.
class StyleLimitsNode extends SlotableNode<EquationRowNode> {
  /// The name with its limits under and over it.
  final EquationRowNode limits;

  /// The name with the same as scripts.
  final EquationRowNode scripts;

  StyleLimitsNode({required this.limits, required this.scripts});

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      options.style.size == MathStyle.display.size
          ? childBuildResults[0]!
          : childBuildResults[1]!;

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      [options, options];

  @override
  List<EquationRowNode> computeChildren() => [limits, scripts];

  @override
  AtomType get leftType => AtomType.op;

  @override
  AtomType get rightType => AtomType.op;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.style.size != newOptions.style.size;

  @override
  StyleLimitsNode updateChildren(List<EquationRowNode> newChildren) =>
      StyleLimitsNode(limits: newChildren[0], scripts: newChildren[1]);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'limits': limits.toJson(),
      'scripts': scripts.toJson(),
    });
}
