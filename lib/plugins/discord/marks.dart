/// The Discord plugin's mark on a note's More sheet and its pages: a speech bubble with two lines in it, a chat
/// message, in the app's strokes.
///
/// Not Discord's own mark. The Slack plugin, the one this follows, is drawn as a hash (slack/marks.dart), not Slack's
/// logo, and Notion and GitHub as a page and a branch in strokes; a brand's own art is drawn only where the brand
/// handed it over to be (Claude's and Lovart's, lib/claude/claude_mark.dart, lib/plugins/lovart/lovart_mark.dart),
/// and never where a store's listing can show it (docs/store/). The Market's tile is the plugin's Lucide icon,
/// `message-square`, the same bubble.
library;

import 'package:flutter/widgets.dart';

import '../../art/svg_path.dart';
import '../../sheet/kit.dart';

class DiscordMark extends StatelessWidget {
  const DiscordMark({super.key, this.size});

  /// Pixels square; the size of the icon theme round it without one.
  final double? size;

  /// Lucide's `message-square`, and two lines of words inside it.
  static const String d = 'M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2zM7 8h10M7 12h6';

  @override
  Widget build(BuildContext context) => StrokeMark(path: svgPath(d), size: size);
}
