/// A block under a note's title, in the editor: the doc page's "Edited 2 hr ago by ana · Owner: bo" line (lib/note/
/// doc_page.dart; Matt, 2026-10-31, docs/TEAMSPACES.md: "the doc page UI"), drawn where Notion draws a page's
/// properties, under its name and over its first words.
///
/// **Inside the editor**, as a block after the title's line, as the blank page's names are a block after line 1
/// (lib/editor/items/blank_offers.dart): the title is the note's own first line of words, so the line follows it
/// wherever a map card or the banner above puts it, and scrolls with the words. The title is the first line after the
/// front matter, where it has words; a note whose first line is blank has no block.
///
/// The screen keeps what the block says and tells the editor one thing, whether the block is drawn ([setAfterTitle]);
/// what is drawn is the screen's own widget, built where the block is ([afterTitle]'s `host`).
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../view/extended.dart' show frontMatter;

/// Whether the screen wants the block drawn now.
final StateEffectType<bool> setAfterTitle = StateEffect.define<bool>();

final Facet<WidgetBuilder, WidgetBuilder?> _host = Facet.define<WidgetBuilder, WidgetBuilder?>(combine: (values) => values.isEmpty ? null : values.first);

class _AfterTitleWidget extends EditorWidget {
  const _AfterTitleWidget(this.host);

  final WidgetBuilder host;

  @override
  bool eq(_AfterTitleWidget other) => identical(other.host, host);

  // A press on the line is the line's own (a name, a time), never the caret's.
  @override
  bool takesPointer(_) => true;

  @override
  Widget build(BuildContext context) => Builder(builder: host);
}

typedef _Block = ({bool on, int line, DecorationSet decorations});

/// The title's line: the first after the front matter, where it has words; 0 for none.
int _titleLine(EditorState state) {
  final front = frontMatter(state.doc);
  final first = front != null ? front.to + 1 : 1;
  if (first > state.doc.lines) return 0;
  return state.doc.line(first).text.trim().isEmpty ? 0 : first;
}

_Block _build(EditorState state, bool on) {
  final host = state.facet(_host);
  final line = on && host != null ? _titleLine(state) : 0;
  if (line == 0) return (on: on, line: 0, decorations: Decoration.none);
  final at = state.doc.line(line).to;
  return (on: on, line: line, decorations: Decoration.set(<Range<Decoration>>[Decoration.widget(widget: _AfterTitleWidget(host!), block: true, side: 1).range(at)]));
}

final StateField<_Block> _block = StateField.define<_Block>(
  create: (state) => (on: false, line: 0, decorations: Decoration.none),
  update: (value, tr) {
    var on = value.on;
    var told = false;
    for (final effect in tr.effects) {
      final said = setAfterTitle.cast(effect);
      if (said != null) {
        on = said.value;
        told = true;
      }
    }
    if (!told && (!tr.docChanged || !on)) return value;
    // Built again at a change while it is on: the title's line is a few lines in at most, and the widget is the same
    // one (`eq`), so the editor keeps what it drew.
    return _build(tr.state, on);
  },
  provide: (field) => EditorViewLike.decorations.from<_Block>(field, (value) => value.decorations),
);

/// Whether the block is drawn now.
bool afterTitleShown(EditorState state) => (state.fieldOrNull(_block)?.decorations.size ?? 0) > 0;

/// Whether the editor was last told to draw the block.
bool afterTitleOn(EditorState state) => state.fieldOrNull(_block)?.on ?? false;

/// The block under the title for a note's editor: `host` builds what it holds. The same function each time, or the
/// block is made again.
Extension afterTitle(WidgetBuilder host) => Extension.list(<Extension>[_host.of(host), _block]);
