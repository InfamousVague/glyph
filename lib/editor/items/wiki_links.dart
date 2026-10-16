/// A link from one note to another, written the way every notes app writes it. Ports
/// `src/app/editor/wikiLinks.ts`.
///
///     The deposit is in [[The cabin trip]].
///
/// A name that matches a note's title opens it; a name that matches nothing is drawn as a name waiting to be
/// written, and tapping it makes that note and opens it. Matching is by the title as a person would say it
/// (`lib/core/title_key.dart`). Nothing is stored: the link IS the title.
///
/// A `#` in the brackets points inside a note rather than at one: `[[#^ship-page]]` is somewhere in THIS note
/// and is left to `anchors.dart`; `[[The cabin trip#^friday]]` is a note and a place in it, the title resolved
/// here and the anchor passed on.
///
/// What differs:
/// - The options are a facet, [wikiOptions], so whoever makes the editor says how a title is looked up and what
///   opening one does, and may say it again later without making the editor again; `wikiLinks(options)` puts them
///   there, as the web's call did. The tickets' and the queries' options the web keeps on the same object are
///   their own pieces'.
/// - The underline (an offset, a thickness, a dashed style, a colour mixed from the words') is a painted layer.
library;

import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';

export '../../core/title_key.dart' show sameTitle;

/// `[[Another note]]`: the brackets, and the title between them.
final RegExp _wiki = RegExp(r'\[\[([^\]\n]{1,120})\]\]');

class WikiLink {
  const WikiLink({required this.from, required this.to, required this.title, required this.anchor, this.label});

  /// The whole thing, brackets included.
  final int from;
  final int to;

  /// The title as it is written in the note: everything before a `#`.
  final String title;

  /// What followed the first `#`, `^` and all, for a link that points at a place inside the note.
  final String? anchor;

  /// What followed a `|`, `[[Lisbon|the capital]]`: the words the link is read as, as Obsidian writes them
  /// (lib/links). The title is what comes before it.
  final String? label;

  @override
  bool operator ==(Object other) => other is WikiLink && other.from == from && other.to == to && other.title == title && other.anchor == anchor && other.label == label;

  @override
  int get hashCode => Object.hash(from, to, title, anchor, label);

  @override
  String toString() => 'WikiLink($from, $to, "$title", $anchor)';
}

/// Every wiki link in the text, counting positions from `offset`.
List<WikiLink> wikiLinksIn(String text, [int offset = 0]) {
  final found = <WikiLink>[];
  for (final match in _wiki.allMatches(text)) {
    final whole = (match.group(1) ?? '').trim();
    // `[[Title|words]]`: the title is before the bar.
    final bar = whole.indexOf('|');
    final inside = bar >= 0 ? whole.substring(0, bar) : whole;
    final label = bar >= 0 ? whole.substring(bar + 1).trim() : '';
    final hash = inside.indexOf('#');
    final title = (hash >= 0 ? inside.substring(0, hash) : inside).trim();
    // `[[#^anchor]]` is a place in this note, not a note: another hand draws it.
    if (title.isEmpty) continue;
    final anchor = hash >= 0 ? inside.substring(hash + 1).trim() : '';
    found.add(WikiLink(from: offset + match.start, to: offset + match.end, title: title, anchor: anchor.isEmpty ? null : anchor, label: label.isEmpty ? null : label));
  }
  return found;
}

class WikiOptions {
  const WikiOptions({required this.known, required this.open, this.body});

  /// Whether a note by that title exists; a link to one that does not is drawn as waiting.
  final bool Function(String title) known;

  /// Opens the note by that title, making it first where there is none. `anchor` is what followed a `#`, if any.
  final void Function(String title, [String? anchor]) open;

  /// The note's body by title, or null where there is none: what `![[A canvas]]` draws.
  final String? Function(String title)? body;
}

/// How a title is looked up and opened in this editor; null where a note cannot be opened, and no link is drawn.
final Facet<WikiOptions, WikiOptions?> wikiOptions = Facet.define<WikiOptions, WikiOptions?>(combine: (values) => values.isEmpty ? null : values.first);

final Map<String, Decoration> _titled = <String, Decoration>{};

Decoration _mark(bool waiting, [String? title]) => Decoration.mark(className: waiting ? 'cm-wiki cm-wikiNew' : 'cm-wiki', attributes: title == null ? null : <String, String>{'title': title});

/// The links on each line, counted from the line's start, kept for every line of a document (`LineFact`). A link
/// never runs over a line's end, so the note's links are its lines' links.
final LineFact<List<WikiLink>> _linked = LineFact<List<WikiLink>>((text) {
  if (!text.contains('[[')) return null;
  final found = wikiLinksIn(text);
  return found.isEmpty ? null : found;
});

DecorationSet _decorate(EditorState state) {
  final options = state.facet(wikiOptions);
  if (options == null) return Decoration.none;
  final builder = RangeSetBuilder<Decoration>();
  // Whether a title is a note's is asked each time, since the library changes; where the links are is kept.
  for (final line in _linked.of(state.doc)) {
    for (final link in line.fact) {
      final waiting = !options.known(link.title);
      builder.add(line.from + link.from, line.from + link.to, _titled['$waiting|${link.title}'] ??= _mark(waiting, link.title));
    }
  }
  return builder.finish();
}

void _underline(Props p, {required bool waiting}) {
  // textDecoration: 'underline', textDecorationStyle: 'solid', textUnderlineOffset: '0.2em',
  // textDecorationThickness: '0.06em', textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)'
  p
    ..underline = false
    ..painter = MarkPaint.add(p.painter, UnderlineLayer(offset: p.em(0.2), thickness: p.em(0.06), opacity: 0.45, style: waiting ? UnderlineStyle.dashed : UnderlineStyle.solid));
}

bool _isNew(LookElement element, LineContext context) => element.has('cm-wikiNew');
bool _isKnown(LookElement element, LineContext context) => !element.has('cm-wikiNew');

final LookSheet _theme = LookSheet('editor/wikiLinks.ts', <LookRule>[
  // '.cm-wiki, .cm-wiki *': { textDecoration: 'underline', ... }
  // A note that is not written yet: the same words, dashed, so it reads as a place to go rather than a mistake.
  // '.cm-wikiNew, .cm-wikiNew *': { textDecorationStyle: 'dashed', color: 'var(--app-ink-3, …)' }
  for (final under in const <bool>[false, true]) ...<LookRule>[
    LookRule('cm-wiki', classes: 2, under: under, when: _isKnown, null, box: (p, e) => _underline(p, waiting: false)),
    LookRule('cm-wiki', classes: 2, under: under, when: _isNew, (p, e) => p.color = e.t.color('app-ink-3'), box: (p, e) => _underline(p, waiting: true)),
  ],
]);

class _WikiLinks extends PluginValue {
  _WikiLinks(EditorViewLike view) : decorations = _decorate(view.state);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || !identical(update.state.facet(wikiOptions), update.startState.facet(wikiOptions))) decorations = _decorate(update.state);
  }
}

final Extension _wikiLinks = Extension.list(<Extension>[
  ViewPlugin.define<_WikiLinks>(
    _WikiLinks.new,
    decorations: (value) => value.decorations,
    eventHandlers: EditorEventHandlers(
      mouseDown: (event, view) {
        final options = view.state.facet(wikiOptions);
        if (options == null) return false;
        final pos = view.posAtCoords(event.position);
        if (pos == null) return false;
        final line = view.state.doc.lineAt(pos);
        final link = wikiLinksIn(line.text, line.from).where((found) => pos >= found.from && pos <= found.to).firstOrNull;
        if (link == null) return false;
        // The press does not reach the editor, so the caret stays where it was and the note simply opens.
        options.open(link.title, link.anchor);
        return true;
      },
    ),
  ),
  baseTheme(_theme),
]);

/// Links between notes: `[[Title]]` opens that note, or makes it. With `given`, these are the editor's options;
/// without, they are whatever [wikiOptions] holds, and nothing is drawn while it holds none.
Extension wikiLinks([WikiOptions? given]) => given == null ? _wikiLinks : Extension.list(<Extension>[wikiOptions.of(given), _wikiLinks]);
