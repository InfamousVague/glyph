/// The GitHub plugin's mark on a note's cog sheet. A port of `src/app/plugins/github/marks.tsx`.
library;

import 'package:flutter/widgets.dart';

import '../../art/svg_path.dart';
import '../../sheet/kit.dart';

/// A branch: a repo, in the app's strokes. Two whole rings (each drawn as two half arcs, since one arc can't close
/// on itself) and a line, with the branch curving from the bottom of the right ring onto the left one.
class RepoMark extends StatelessWidget {
  const RepoMark({super.key, this.size});

  /// Pixels square; the size of the icon theme round it without one (the page's `1em`).
  final double? size;

  static const String d = 'M6 3v12M18 3a3 3 0 1 0 0 6a3 3 0 1 0 0-6M6 15a3 3 0 1 0 0 6a3 3 0 1 0 0-6M18 9a9 9 0 0 1-9 9';

  @override
  Widget build(BuildContext context) => StrokeMark(path: svgPath(d), size: size);
}
