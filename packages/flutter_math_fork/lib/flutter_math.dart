/// Basic utilities to render math equations.
///
/// Please refer to README for usage.
library flutter_math_fork;

export 'src/ast/options.dart' show MathOptions, FontOptions;
export 'src/ast/size.dart' show MathSize;
export 'src/ast/style.dart' show MathStyle;
export 'src/encoder/exception.dart';
export 'src/parser/tex/parse_error.dart';
export 'src/parser/tex/settings.dart';
export 'src/widgets/exception.dart';
export 'src/widgets/math.dart';
export 'src/widgets/selectable.dart' show SelectableMath;
// Added to 0.7.4 (README.md, 19): where an equation array's rows are, for whoever sets a number beside each.
export 'src/render/layout/eqn_array.dart' show RenderEqnArray;
