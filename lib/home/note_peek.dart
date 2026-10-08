/// A note drawn small on its card: the first lines of it after its title, at a fraction of the note's size, clipped
/// to about six lines with the last one fading out where there is more.
///
/// Ports `src/app/notes/NotePeek.tsx`. On the web a card's preview is the note's own editor (CodeMirror, read-only,
/// in its formatted view and `peek` mode) given `peekMarkdown(body)`, so whatever a note draws its card draws. Here
/// it is the same: [MarkdownView] (lib/editor/markdown_view.dart), which draws the editor's own lines in the web's
/// `.peek` box. It was drawn by hand until the editor's view was ported; nothing of that is left.
///
/// What differs, until the pieces of the editor that draw them are ported (docs/STAGE4.md, pieces E to H):
/// - The items drawn in the words are the editor's own (`lib/editor/items`): a `#tag`, a to-do's fields as chips,
///   a counter, a sum's answer, a choice's box, a footnote's marker, the bookmark's ribbon and a heading's count of
///   its to-dos, as on the web's card. Links between notes are not drawn on a card, as there (it is given no way to
///   open one).
/// - Ghost.md's own marks (`==highlight==`, `||spoiler||`, the five effects) keep their signs here until whoever
///   wires the cards hands them `marks` and `markExtensions(marks)` (`lib/editor/marks`): the smoke and the effects
///   move without rest, which a card's tests and a long list of cards should take on knowingly.
/// - A table is its rows as typed, a picture its line, a diagram and a query their fences.
/// - Nothing is kept between draws and nothing waits to come near the screen: a card's lines cost well under a
///   millisecond here, where an editor cost the web 25 to 30.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';
import '../editor/items/items.dart' show itemExtensions;
import '../editor/markdown_view.dart';
import '../editor/state/state.dart' show Extension;

/// The preview of a note's [body] on its card. Draws nothing for a canvas (its body is JSON) or a note with nothing
/// under its title.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body, this.fill = false, this.dense = false});

  final String body;

  /// The card is stretched to its row's height: the preview takes the room there is, up to its six lines
  /// (NoteCard.module.css `.peek { flex: 1 }` under `max-block-size`).
  final bool fill;

  /// A dense card: `.item[data-dense] .peek { max-block-size: calc(1.6em * 4.2) }`.
  final bool dense;

  /// Whether [body] has anything to draw small.
  static bool has(String body) => !isCanvasBody(body) && peekMarkdown(body).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (isCanvasBody(body)) return const SizedBox.shrink();
    final markdown = peekMarkdown(body);
    if (markdown.isEmpty) return const SizedBox.shrink();
    return Padding(
      // `.peek { margin-block-start: var(--glacier-space-2) }`
      padding: EdgeInsets.only(top: context.tokens.space(2)),
      // `max-block-size: calc(1.6em * 6.2)`, and the fade over the last `1.8em`.
      child: MarkdownView(markdown: markdown, lines: dense ? 4.2 : 6.2, fill: fill, extensions: _items),
    );
  }
}

/// The items a card draws in the words: the editor's own, as a preview has them (no taps, no anchors).
final List<Extension> _items = <Extension>[itemExtensions(peek: true)];
