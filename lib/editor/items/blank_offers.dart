/// A new note's blank page, in the editor: the block after its first line that holds the names it can be given
/// and, under them, whatever the screen puts there (the template cards and the ghost). Ports the block of
/// `src/app/editor/nameChips.ts`: `pageField`'s decoration, `build` and `OffersWidget` (docs/DESIGN.md §144).
///
/// **Inside the editor**, as a block after line 1, so it follows the line wherever the map's box above puts it,
/// the page scrolls it with the words, and a line made under the first (Enter on a blank page) is under the names
/// and cards too, as on the page. The first line is the one after the front matter, where the note has any, and
/// the block is drawn only while that line has no words, whatever the screen offers.
///
/// What differs:
/// - The page's field kept everything the block waits for (what is offered, the focus, the focus inside the block,
///   the page ready for words) and the screen told it of each. Here the screen keeps those, as it did before the
///   block was in the editor (lib/note/note_screen.dart `offersShown`), and tells the editor one thing: whether the
///   block is offered now ([setBlankOffers]).
/// - What is drawn in the block is the screen's own widget, built where the block is ([blankOffers]'s `host`),
///   which is the page's `host` element and its chips in one: the screen draws the chips too.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../view/extended.dart' show frontMatter;

/// Whether the screen offers the block now: the names, or its own element, with the editor focused and the page
/// ready for words (`setOffers`, `focusChanged`, `insideChanged` and `pageReady` as one answer).
final StateEffectType<bool> setBlankOffers = StateEffect.define<bool>();

/// What draws the block's inside, for an editor that has the block at all.
final Facet<WidgetBuilder, WidgetBuilder?> _host = Facet.define<WidgetBuilder, WidgetBuilder?>(combine: (values) => values.isEmpty ? null : values.first);

class _OffersWidget extends EditorWidget {
  const _OffersWidget(this.host);

  final WidgetBuilder host;

  @override
  bool eq(_OffersWidget other) => identical(other.host, host);

  // `ignoreEvent(): true`: a press on a chip or a card is its own, and never moves the caret.
  @override
  bool takesPointer(_) => true;

  @override
  Widget build(BuildContext context) => Builder(builder: host);
}

typedef _Page = ({bool offered, DecorationSet decorations});

/// The block after the first line of words, while it is offered and that line is blank; nothing otherwise.
DecorationSet _build(EditorState state, bool offered) {
  final host = state.facet(_host);
  if (!offered || host == null) return Decoration.none;
  final front = frontMatter(state.doc);
  final first = front != null ? front.to + 1 : 1;
  if (first > state.doc.lines) return Decoration.none;
  final line = state.doc.line(first);
  if (line.text.trim().isNotEmpty) return Decoration.none;
  return Decoration.set(<Range<Decoration>>[Decoration.widget(widget: _OffersWidget(host), block: true, side: 1).range(line.to)]);
}

final StateField<_Page> _page = StateField.define<_Page>(
  create: (state) => (offered: false, decorations: Decoration.none),
  update: (value, tr) {
    var offered = value.offered;
    var told = false;
    for (final effect in tr.effects) {
      final said = setBlankOffers.cast(effect);
      if (said != null) {
        offered = said.value;
        told = true;
      }
    }
    // A note that is not offered the block reads nothing of its words for it, at a letter or at any other change.
    if (!told && (!tr.docChanged || !offered)) return value;
    return (offered: offered, decorations: _build(tr.state, offered));
  },
  provide: (field) => EditorViewLike.decorations.from<_Page>(field, (value) => value.decorations),
);

/// Whether the block is drawn now (`offersShown`).
bool blankOffersShown(EditorState state) => (state.fieldOrNull(_page)?.decorations.size ?? 0) > 0;

/// Whether the editor was last told the block is offered.
bool blankOffered(EditorState state) => state.fieldOrNull(_page)?.offered ?? false;

/// The blank page's block for a note's editor: `host` builds its inside, the names and what goes under them. The
/// same function each time, or the block is made again.
Extension blankOffers(WidgetBuilder host) => Extension.list(<Extension>[_host.of(host), _page]);
