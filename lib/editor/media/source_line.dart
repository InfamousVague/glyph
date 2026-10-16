/// Where a note came from, under its title: a clip's `source:` (the web clipper, clipper/, writes it with `clipped:`;
/// Obsidian's clipper writes the same key) as one quiet line, `From field.example/art…tml`, whose tap opens the page.
///
/// The front matter is folded to its keys' names (lib/editor/view/extended.dart, "source · clipped · tags"), so the
/// address itself was only seen by opening the block. This puts it where it is read: under the first line of words,
/// shortened as every address the app shows is ([shortUrl]). Only an http or https address is drawn; anything else
/// in `source:` is the person's own word for it and stays in the front matter alone.
///
/// A block widget after the title's line, from a [StateField], as the blank page's offers are
/// (lib/editor/items/blank_offers.dart): it scrolls with the words and moves with the title. It reads the note's
/// front matter, at most forty lines, and only when the words change.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/front_matter.dart';
import '../../core/link_preview.dart' show LinkOpener;
import '../../core/open_link.dart' show canOpenLink;
import '../../core/short_url.dart';
import '../editor.dart';
import '../items/open_heading.dart' show firstWordsLine;
import '../view/editor_view.dart';
import '../view/extended.dart' show frontMatter;

/// A note's source, when its front matter has one the app may open: an http(s) address in `source:`.
String? sourceOf(String body) {
  final said = frontMatterValue(body, 'source');
  if (said == null) return null;
  final uri = Uri.tryParse(said);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || !canOpenLink(said)) return null;
  return said;
}

class SourceLineWidget extends EditorWidget {
  const SourceLineWidget(this.url, this.open);

  final String url;
  final LinkOpener? open;

  @override
  bool eq(SourceLineWidget other) => other.url == url && identical(other.open, open);

  @override
  double get estimatedHeight => 30;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final env = view is EditorView ? view.look?.env : null;
    final body = env?.body ?? t.len('app-body');
    final gutter = env?.gutter ?? t.len('app-gutter');
    // The folded front matter's size and ink (`.cm-frontFold`), so the two read as one quiet layer over the words.
    final size = body * 0.84;
    final ink = t.color('app-ink-3');
    final style = t.textAt(size, mono: true, color: ink, height: 1.7);
    final shown = shortUrl(url);
    return Semantics(
      link: true,
      label: 'From $shown',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open == null ? null : () => open!(url),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, t.space(1), gutter, t.space(1)),
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                const TextSpan(text: 'From '),
                TextSpan(text: shown, style: style.copyWith(decoration: TextDecoration.underline, decorationColor: ink)),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}

DecorationSet _build(EditorState state, LinkOpener? open) {
  // The front matter's own lines and nothing past them: a long note is not read whole at every letter.
  final front = frontMatter(state.doc);
  if (front == null) return Decoration.none;
  final url = sourceOf(state.doc.sliceString(state.doc.line(front.from).from, state.doc.line(front.to).to));
  if (url == null) return Decoration.none;
  final title = firstWordsLine(state);
  if (title == null) return Decoration.none;
  return Decoration.set(<Range<Decoration>>[Decoration.widget(widget: SourceLineWidget(url, open), block: true, side: 1).range(title.to)]);
}

/// The line under the title of a note with a `source:`, its tap handed to [open] (the phone's opener).
Extension sourceLine({LinkOpener? open}) {
  final field = StateField.define<DecorationSet>(
    create: (state) => _build(state, open),
    update: (value, tr) => tr.docChanged ? _build(tr.state, open) : value,
    provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field, (value) => value),
  );
  return field;
}
