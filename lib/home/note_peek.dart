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
/// - A picture is drawn under its line and a film as its still, as the page's `peek` draws them
///   (`inlineImages`, `videoCards` with `still`), from the pictures the app keeps where the card is under a
///   [PeekPictures]; with none over it, each is its line. A table is its rows as typed, a diagram and a query
///   their fences.
/// - **One preview.** The sidebar's rows and cards draw this too ([NotePeek.plain], with the room over it left to
///   the row), where two files drew a note small until the second was folded into this one.
/// - Nothing is kept between draws and nothing waits to come near the screen: a card's lines cost well under a
///   millisecond here, where an editor cost the web 25 to 30.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/canvas_body.dart';
import '../core/images.dart' show PictureStore;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart';
import '../editor/items/items.dart' show itemExtensions;
import '../editor/markdown_view.dart';
import '../editor/media/media.dart' show MediaSeams, mediaExtensions;
import '../editor/state/state.dart' show Extension;

/// Where a preview's pictures and a film's still are drawn from: the app's own store, put over everything that
/// draws a note small (lib/root). The page's cards asked the app's one module for a picture; a widget asks what is
/// above it.
class PeekPictures extends InheritedWidget {
  const PeekPictures({super.key, required this.store, required super.child});

  final PictureStore? store;

  static PictureStore? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PeekPictures>()?.store;

  @override
  bool updateShouldNotify(PeekPictures oldWidget) => !identical(oldWidget.store, store);
}

/// The preview of a note's [body] on its card. Draws nothing for a canvas (its body is JSON) or a note with nothing
/// under its title.
class NotePeek extends StatelessWidget {
  const NotePeek({super.key, required this.body, this.markdown, this.fill = false, this.dense = false, this.margin = true});

  final String body;

  /// What is drawn of [body], where it was read before this was made (lib/core/note_facts.dart `peek`:
  /// `peekMarkdown(body)`, and nothing for a canvas). A list reads each note once and hands this over; left out,
  /// the body is read at every build.
  final String? markdown;

  /// `.peek { margin-block-start: var(--glacier-space-2) }`: the room over the preview on a card. A sidebar's row
  /// keeps its own (`.rowPeek`), and asks for none.
  final bool margin;

  /// What is drawn small of [body]: nothing for a canvas (its body is JSON), else the note after its title.
  static String _drawn(String body) => isCanvasBody(body) ? '' : peekMarkdown(body);

  /// The preview as a list's row or a sidebar's card takes it (lib/notes/note_peek.dart `NotePeekBuilder`): the
  /// drawing alone, or null where there is nothing after the title.
  static Widget? plain(BuildContext context, String body) {
    final markdown = _drawn(body);
    return markdown.isEmpty ? null : NotePeek(body: body, markdown: markdown, margin: false);
  }

  /// [plain] for a note, whose words are read once and kept (lib/core/note_facts.dart).
  static Widget? ofNote(BuildContext context, Note note) {
    final markdown = NoteFacts.of(note).peek;
    return markdown.isEmpty ? null : NotePeek(body: note.body, markdown: markdown, margin: false);
  }

  /// The card is stretched to its row's height: the preview takes the room there is, up to its six lines
  /// (NoteCard.module.css `.peek { flex: 1 }` under `max-block-size`).
  final bool fill;

  /// A dense card: `.item[data-dense] .peek { max-block-size: calc(1.6em * 4.2) }`.
  final bool dense;

  /// Whether [body] has anything to draw small.
  static bool has(String body) => _drawn(body).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final markdown = this.markdown ?? _drawn(body);
    if (markdown.isEmpty) return const SizedBox.shrink();
    // `max-block-size: calc(1.6em * 6.2)`, and the fade over the last `1.8em`.
    final drawn = MarkdownView(markdown: markdown, lines: dense ? 4.2 : 6.2, fill: fill, extensions: peekExtensions(PeekPictures.of(context)));
    if (!margin) return drawn;
    return Padding(
      // `.peek { margin-block-start: var(--glacier-space-2) }`
      padding: EdgeInsets.only(top: context.tokens.space(2)),
      child: drawn,
    );
  }
}

/// The items a card draws in the words: the editor's own, as a preview has them (no taps, no anchors).
final List<Extension> _items = <Extension>[itemExtensions(peek: true)];

/// The same with the pictures of one store: a list to a store, since another list is another editor
/// (lib/editor/markdown_view.dart).
final Expando<List<Extension>> _withPictures = Expando<List<Extension>>('peek extensions');

/// What a note drawn small draws in its words (Editor.tsx's lines under `peek`): the items, and with a [store] its
/// pictures and a film's still, a link as its short words and no card.
List<Extension> peekExtensions(PictureStore? store) => store == null ? _items : _withPictures[store] ??= <Extension>[itemExtensions(peek: true), mediaExtensions(seams: MediaSeams(pictures: store), peek: true)];
