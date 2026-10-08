/// The block half of the renderer: the things an inline run cannot reach. Ports `src/app/editor/glyphLines.ts`.
///
/// The highlighter can colour and resize a run of text, but it cannot put space above a heading, draw the bar down
/// the side of a quote, hang a list's text off its marker, or paint a ground behind a fenced block: those are
/// properties of the LINE. Hence one small plugin that gives each line the classes of the blocks it is in
/// (`looks/markdown_look.dart` says what they mean), and for a list item the measured width of its marker, so
/// wrapped lines hang under the first letter of the words.
///
/// What differs:
/// - The marker is measured with the view's own text measure ([EditorView.measureText]) where the web appends a
///   ruler element to the scroller; the same runs (the marker, with a to-do's box in the `taskMarker` class), and
///   the width taken as the page takes it: up to a sixty-fourth of a pixel, then to two decimals.
/// - Beside `style: --hang: <n>px` the line decoration carries `data-hang-chars`, how many characters the marker
///   is. The page's `text-indent` needs no such thing; the line's render object draws the marker and the words as
///   two paragraphs and has to know where one ends (`line.dart`).
/// - `document.fonts`' `loadingdone` is `PaintingBinding.systemFonts`.
library;

import 'package:flutter/painting.dart' show PaintingBinding;

import '../../core/item_syntax.dart';
import '../looks/look.dart' show layoutUnitCeil;
import '../looks/markdown_look.dart';
import '../state/rangeset.dart';
import '../state/state.dart';
import 'decoration.dart';
import 'editor_view.dart';
import 'plugin.dart';
import 'syntax_tree.dart';

/// Which line class a syntax node contributes to every line it covers.
const Map<String, String> _lineClass = <String, String>{
  'ATXHeading1': MarkdownClass.lineH1,
  'ATXHeading2': MarkdownClass.lineH2,
  'ATXHeading3': MarkdownClass.lineH3,
  'ATXHeading4': MarkdownClass.lineH4,
  'ATXHeading5': MarkdownClass.lineH4,
  'ATXHeading6': MarkdownClass.lineH4,
  'Blockquote': MarkdownClass.lineQuote,
  'ListItem': MarkdownClass.lineItem,
  'FencedCode': MarkdownClass.lineCode,
  'CodeBlock': MarkdownClass.lineCode,
  'HorizontalRule': MarkdownClass.lineHr,
};

/// A list line's marker as far as its words: the indent, `-` or `10.`, a task's box, and the spaces after them.
final RegExp _hanging = RegExp('^(\\s*$markerPattern[ \\t]+(?:$boxPattern[ \\t]+)?)\\S');

/// A to-do's box inside a marker.
final RegExp _boxIn = RegExp(boxPattern);

/// How wide a marker is, measured in the editor's own face. Kept for each face and size, so a note costs one
/// measure for each kind of marker.
final Map<String, double> _widths = <String, double>{};

double _markerWidth(EditorViewLike view, String marker) {
  if (view is! EditorView) return 0;
  final look = view.look;
  if (look == null) return 0;
  // Ticked or not, a box is the same width: one measure for both.
  final key = '${look.env.key}|${marker.replaceFirst(_boxIn, '[ ]')}';
  final known = _widths[key];
  if (known != null) return known;
  // A to-do's box is set in the monospace face (`.taskMarker`), so `[ ]` and `[x]` are one width.
  final box = _boxIn.firstMatch(marker);
  final width = box == null
      ? view.measureText(<(String, String?)>[(marker, null)])
      : view.measureText(<(String, String?)>[(marker.substring(0, box.start), null), (box.group(0)!, MarkdownClass.taskMarker), (marker.substring(box.end), null)]);
  return _widths[key] = layoutUnitCeil(width);
}

DecorationSet _buildLines(EditorViewLike view) {
  final doc = view.state.doc;
  // One line can be covered by more than one node (a heading inside a quote is both), so classes gather for each
  // line before any decoration is made. Keyed by line start, which is also where the decoration must sit.
  final perLine = <int, List<String>>{};
  final tree = syntaxTree(view.state);
  for (final range in view.visibleRanges) {
    tree.iterate(
      from: range.from,
      to: range.to,
      enter: (node) {
        final cls = _lineClass[node.name];
        if (cls == null) return null;
        final first = doc.lineAt(node.from).number;
        // `node.to` sits just past the block, which on a block ending in a newline is the first character of the
        // next line; stepping back one keeps the decoration off a line the node does not really cover.
        final last = doc.lineAt(node.to - 1 > node.from ? node.to - 1 : node.from).number;
        for (var n = first; n <= last; n += 1) {
          final at = doc.line(n).from;
          final classes = <String>[cls];
          // A block of code is one card: its first and last lines carry the corners.
          if (cls == MarkdownClass.lineCode) {
            if (n == first) classes.add(MarkdownClass.lineCodeTop);
            if (n == last) classes.add(MarkdownClass.lineCodeFoot);
          }
          // A quote's first and last lines hold the space between it and the lines around it.
          if (cls == MarkdownClass.lineQuote) {
            if (n == first) classes.add(MarkdownClass.lineQuoteTop);
            if (n == last) classes.add(MarkdownClass.lineQuoteFoot);
          }
          (perLine[at] ??= <String>[]).addAll(classes);
        }
        return null;
      },
    );
  }

  // `RangeSetBuilder.add` must be called in ascending order, and a line decoration's range must be empty and sit
  // at the line's start.
  final builder = RangeSetBuilder<Decoration>();
  for (final at in perLine.keys.toList()..sort()) {
    final classes = perLine[at]!;
    final marker = classes.contains(MarkdownClass.lineItem) ? _hanging.firstMatch(doc.lineAt(at).text)?.group(1) : null;
    final attributes = marker == null ? null : <String, String>{'style': '--hang: ${_markerWidth(view, marker).toStringAsFixed(2)}px', 'data-hang-chars': '${marker.length}'};
    builder.add(at, at, Decoration.line(className: classes.join(' '), attributes: attributes));
  }
  return builder.finish();
}

class _GlyphLines extends PluginValue {
  _GlyphLines(this.view) {
    decorations = _buildLines(view);
    PaintingBinding.instance.systemFonts.addListener(_onFonts);
  }

  final EditorViewLike view;
  late DecorationSet decorations;

  /// Set when a face finished loading, so markers measured in the fallback face are measured again.
  bool _remeasure = false;

  void _onFonts() {
    _widths.clear();
    _remeasure = true;
    view.dispatch(const TransactionSpec());
  }

  @override
  void destroy() => PaintingBinding.instance.systemFonts.removeListener(_onFonts);

  @override
  void update(ViewUpdate update) {
    // While an IME is composing, MAP the decorations through the changes instead of rebuilding them: a composition
    // never changes which block a line is, so the mapped set is correct as well as safe.
    if (update.view.composing) {
      if (update.docChanged) decorations = decorations.map(update.changes);
      return;
    }
    if (_remeasure ||
        update.docChanged ||
        update.viewportChanged ||
        // The text size setting: the markers are a different width now.
        update.geometryChanged ||
        !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      _remeasure = false;
      decorations = _buildLines(update.view);
    }
  }
}

/// The plugin: `glyphLines` in the web's Editor.tsx.
final ViewPlugin<PluginValue> glyphLines = ViewPlugin.define<PluginValue>((view) => _GlyphLines(view), decorations: (value) => (value as _GlyphLines).decorations);
