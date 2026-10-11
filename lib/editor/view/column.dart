/// The editor drawn whole, in a column: every line built and laid out at once, with no scroll view of its own and
/// no viewport to keep. What a read-only preview is drawn with (`markdown_view.dart`), and anything else short
/// enough to draw in full; a note being edited is an `EditorSliver`.
///
/// The lines are the same objects the sliver draws (`EditorView.buildEntry`). The view must have been made with
/// `wholeDocument: true`, so its plugins decorate all of it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../looks/look.dart';
import 'editor_view.dart';
import 'plugin.dart';

class EditorColumn extends StatefulWidget {
  const EditorColumn({super.key, required this.view, this.env, this.sheets = const <LookSheet>[], this.meHue});

  final EditorView view;

  /// What the stylesheets read; the page's own sizes at the tokens above when null.
  final LookEnv? env;

  /// Stylesheets of the host's own, over the extensions'.
  final List<LookSheet> sheets;
  final String? meHue;

  @override
  State<EditorColumn> createState() => _EditorColumnState();
}

class _EditorColumnState extends State<EditorColumn> {
  /// What was last built, the look it was built with, and whether the view has said anything since. A column is
  /// drawn inside things that build often (a card on the home page, a card being dragged across a canvas), and it
  /// projected and resolved every one of its lines at each of those builds, though the view had not changed.
  Widget? _built;
  Look? _builtLook;
  bool _stale = true;

  void _changed() {
    _stale = true;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.view.addListener(_changed);
  }

  @override
  void didUpdateWidget(EditorColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      oldWidget.view.removeListener(_changed);
      widget.view.addListener(_changed);
      _stale = true;
    }
  }

  @override
  void dispose() {
    widget.view.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    assert(view.wholeDocument, 'A column draws the whole document: make the view with wholeDocument.');
    final env = widget.env ?? LookEnv.page(context.tokens, devicePixelRatio: MediaQuery.devicePixelRatioOf(context), meHue: widget.meHue, tabSize: view.state.tabSize);
    view.setEnv(env, more: widget.sheets);
    // Nothing follows lines by number here: the changes are taken so they do not pile up.
    final changes = view.takeChanges();
    final dirty = view.takeDirty();
    final look = view.look!;
    final built = _built;
    // Nothing the view shows has changed since the lines were built, and the look is the one they were built
    // with: the very widgets, which Flutter then leaves as they are.
    if (built != null && !_stale && changes == null && dirty.isNone && identical(look, _builtLook)) return built;
    _stale = false;
    _builtLook = look;
    final doc = view.state.doc, blocks = view.blocks;
    final top = look.env.contentTop, bottom = look.env.contentBottom;
    return _built = EditorViewScope(
      view: view,
      child: Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var n = 1; n <= doc.lines; n = blocks.lastLineOf(n) + 1) view.buildEntry(n)!,
          ],
        ),
      ),
    );
  }
}
