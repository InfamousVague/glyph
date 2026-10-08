/// A mark's example, drawn by the note's own editor. A port of `src/app/guide/MarkExample.tsx` with
/// `MarkExample.module.css` (Matt: "make sure were using the real formatters as some things like spoilers isnt using
/// the right one (wisp)").
///
/// The pages that show the marks used to draw their own version of each one, which meant the sheet and the note
/// could disagree: a spoiler was a blur here and smoke there. This is the editor itself, read-only, with the same
/// extensions and the same plugins the note has. A mark that changes in the app changes here on its own.
///
/// The example sits in its card as in a room of its own (`.room`): no ground, no scrolling, no padding, no caret and
/// no gutter (`--app-gutter: 0px`), so a quote or a block of code stands clear of the card by its own padding.
///
/// What differs:
/// - The page builds a row's editor when the row comes within a screen of the window (an `IntersectionObserver`),
///   because an editor costs it 25 to 30 ms; here a row's lines are made in well under a millisecond, and a lazy
///   list builds only the rows near the screen anyway. [MarkExample.near] is what is left of it: false holds the
///   line's room with its words (`.waiting`), for a caller that has its own reason to wait.
/// - The editor is its lines in a column (lib/editor/view/column.dart), as a card's preview draws a note, with the
///   marks' and the items' extensions; it takes no input and no taps. Tables are drawn; pictures, link cards, films,
///   a board and a query are their lines until those pieces are handed in through [MarkExample.extensions].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/items/items.dart';
import '../editor/looks/look.dart';
import '../editor/marks/marks.dart';
import '../editor/tables/tables.dart';
import '../editor/view/base.dart';
import '../editor/view/column.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/view_mode.dart';
import '../plugins/registry.dart';
import 'marks.dart';

/// `.room :global(.cm-scroller) { font-family: inherit }` and `.example :global(.cm-scroller) { line-height: inherit }`:
/// the page's face and the page's leading, not the note's. Every line starts from them, and a line or a run with a
/// face or a leading of its own (a heading, code) keeps that. Only the family is the page's: whether the face is cut
/// for its size and which of its features are on stay as the note's face left them, as on the page.
final LookSheet _room = LookSheet('MarkExample.module.css', <LookRule>[
  LookRule('cm-line', (p, e) {
    p
      ..families = e.t.families('glacier-font-sans')
      ..mono = false
      ..lineHeight = e.t.len('glacier-leading-md');
  }, classes: 0),
]);

class MarkExample extends StatefulWidget {
  const MarkExample({super.key, required this.row, this.marks = false, this.near = true, this.formats, this.extensions = const <Extension>[]});

  final MarkRow row;

  /// The line with its marks showing (`display: 'mixed'`); otherwise the line as it comes out.
  final bool marks;

  /// False holds the line's room with its words until the caller says the row is near.
  final bool near;

  /// The inline formattings in force; the switched-on plugins' when null.
  final List<GlyphFormat>? formats;

  /// More extensions, after the marks' and the items'.
  final List<Extension> extensions;

  @override
  State<MarkExample> createState() => _MarkExampleState();
}

class _MarkExampleState extends State<MarkExample> {
  EditorView? _view;
  List<GlyphFormat> _formats = const [];
  Registry? _registry;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  /// The switched-on plugins' marks, followed while this is up.
  void _listen() {
    final given = widget.formats;
    final now = given == null ? plugins : null;
    if (!identical(now, _registry)) {
      _registry?.removeListener(_switched);
      _registry = now?..addListener(_switched);
    }
    final next = given ?? plugins.formats();
    if (!listEquals(next, _formats)) {
      _formats = next;
      _drop();
    }
  }

  void _switched() {
    if (!mounted) return;
    final next = plugins.formats();
    if (listEquals(next, _formats)) return;
    setState(() {
      _formats = next;
      _drop();
    });
  }

  void _drop() {
    _view?.destroy();
    _view = null;
  }

  EditorView _make() => EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: widget.row.typed,
      extensions: noteExtensions(
        formats: _formats,
        // The marks themselves are on the other side of the card; this side is the line as it comes out.
        display: widget.marks ? NoteView.mixed : NoteView.formatted,
        readOnly: true,
        more: <Extension>[markExtensions(_formats), itemExtensions(), drawnTables(), ...widget.extensions],
      ),
    ),
  );

  @override
  void didUpdateWidget(MarkExample old) {
    super.didUpdateWidget(old);
    _listen();
    if (old.row.typed != widget.row.typed || old.marks != widget.marks || !identical(old.extensions, widget.extensions)) _drop();
  }

  @override
  void dispose() {
    _registry?.removeListener(_switched);
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!widget.near) {
      // Something the height of a line while the editor is on its way, so the page does not jump as it fills in.
      final row = widget.row;
      return ExcludeSemantics(
        child: Text(row.words.isEmpty ? row.name : row.words, style: t.textAt(t.fontSize('md'), height: t.len('glacier-leading-md'), color: t.color('glacier-text-subtle'))),
      );
    }
    final view = _view ??= _make();
    // The note's own sizes, in a room with no gutter and no padding of its own.
    final env = LookEnv(
      t: t,
      body: t.len('app-body'),
      headings: <double>[for (var level = 1; level <= 6; level++) t.len('app-h$level')],
      gutter: 0,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      dark: t.isDark,
      tabSize: view.state.tabSize,
      contentTop: 0,
      contentBottom: 0,
    );
    return IgnorePointer(child: EditorColumn(view: view, env: env, sheets: <LookSheet>[_room]));
  }
}
