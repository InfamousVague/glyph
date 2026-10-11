/// Notion's mark, in the app's strokes. A port of `src/app/plugins/notion/marks.tsx`.
///
/// What differs: the page handed [StrokeMark] an SVG path's `d` ("M5 4h10l4 4v12H5zM9 16V9l6 7V9"); here it is the
/// same drawing as a [Path] (lib/sheet/kit.dart has no reader of path data).
library;

import 'package:flutter/widgets.dart';

import '../../sheet/kit.dart' show StrokeMark;

/// `M5 4h10l4 4v12H5z` and `M9 16V9l6 7V9`, on the 24 grid.
final Path _notion = Path()
  ..moveTo(5, 4)
  ..lineTo(15, 4)
  ..lineTo(19, 8)
  ..lineTo(19, 20)
  ..lineTo(5, 20)
  ..close()
  ..moveTo(9, 16)
  ..lineTo(9, 9)
  ..lineTo(15, 16)
  ..lineTo(15, 9);

/// A page with an N on it: Notion's mark.
class NotionMark extends StatelessWidget {
  const NotionMark({super.key, this.size});

  /// Pixels square, or the size of the icon theme it is drawn in.
  final double? size;

  @override
  Widget build(BuildContext context) => StrokeMark(path: _notion, size: size);
}
