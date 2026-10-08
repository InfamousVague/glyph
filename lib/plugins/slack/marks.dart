/// The Slack plugin's mark on a note's More sheet. A port of `src/app/plugins/slack/marks.tsx`.
library;

import 'package:flutter/widgets.dart';

import '../../art/svg_path.dart';
import '../../sheet/kit.dart';

/// A hash, the way a Slack channel is written, in the app's strokes.
class SlackMark extends StatelessWidget {
  const SlackMark({super.key, this.size});

  /// Pixels square; the size of the icon theme round it without one (the page's `1em`).
  final double? size;

  static const String d = 'M4 9h16M4 15h16M10 3 8 21M16 3l-2 18';

  @override
  Widget build(BuildContext context) => StrokeMark(path: svgPath(d), size: size);
}
