/// How much of its ink each entry of the editor's sliver is drawn with: the hook focus mode dims the page through
/// (lib/editor/focus/focus_mode.dart).
///
/// An entry is a line, or a block widget over several (a table, a board, a picture), as the sliver builds them. A
/// shade answers an opacity for an entry by its first and last line, and says when that answer changes; the sliver
/// paints each entry through a layer of what every shade answers together, and listens to each for the next frame
/// of a fade. Dimming the entry whole, rather than giving its words a paler ink, keeps a link's colour, a code
/// block's card and a picture in step with the words beside them, and lays nothing out again for a frame of a fade.
library;

import 'package:flutter/foundation.dart';

import '../state/state.dart';
import 'plugin.dart';

/// A shade over the editor's entries.
abstract class EntryShade implements Listenable {
  /// Whether any entry is drawn under 1 now, or is on its way there or back.
  bool get dims;

  /// The opacity of the entry from line [first] to line [last] (1-based, both included): 1 for drawn as it is.
  double opacityOf(int first, int last);
}

/// The shades a view's entries are drawn under: each asked of the view, so that a view plugin can be one.
final Facet<EntryShade? Function(EditorViewLike view), List<EntryShade? Function(EditorViewLike view)>> entryShades = Facet.define();
