/// The seam between a note's screen and its editor: what `src/app/editor/NoteScreen.tsx` hands the `Editor`
/// component (`editor/Editor.tsx`), as a value, and the one function that turns it into the editor's sliver.
///
/// The screen never builds an editor itself. It makes a [NoteEditorSpec] each time it builds and calls its
/// [NoteEditorBuilder], which answers a SLIVER for the page's scroll view; the editor tells the screen its
/// `EditorView` through [NoteEditorSpec.onView], and from then on the screen works through the view as the page
/// does (`view.dispatch`, `view.state.doc`).
///
/// The view itself is made and kept by [NoteEditorHost]: the state with the note's base extensions and undo, the
/// display and the look in compartments the screen's switches reconfigure, and the listener that tells the screen
/// of every change. What DRAWS the view is the host's [NoteEditorHost.draw]:
/// - [readOnlyNoteEditor], the default, draws it with an `EditorSliver`: the note as the page draws it, taking
///   every change the screen dispatches (a name, a look, a version put back), with no caret and no keyboard;
/// - piece D's widget (lib/editor/editor_widget.dart `Editor`, the view with its keyboard and gestures) is one
///   line where the app is wired:
///
///       editor: (context, spec) => NoteEditorHost(spec: spec, draw: (context, view, env) =>
///           Editor(view: view, env: env, meHue: spec.meHue, footClear: spec.footClear, headerInset: spec.headClear)),
///
///   with the input's own extensions, and every other piece's, in [NoteEditorSpec.extensions].
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/looks/look.dart';
import '../editor/view/base.dart';
import '../editor/view/editor_view.dart';
import '../editor/view/sliver.dart';
import '../editor/view/view_mode.dart';

/// `Editor`'s props, as the note's screen passes them. The ones whose pieces are not built yet (the +, the blank
/// page's names, wiki links, comments, blanks, the tape) are not here: each arrives as an [extensions] entry or a
/// field of its own with its piece.
@immutable
class NoteEditorSpec {
  const NoteEditorSpec({
    required this.value,
    required this.onChange,
    required this.onView,
    this.display = NoteView.mixed,
    this.readOnly = false,
    this.look,
    this.zoom = 1,
    this.pageWidth,
    this.headClear = 0,
    this.footClear = 0,
    this.placeholder = 'Write something.',
    this.meHue,
    this.extensions = const <Extension>[],
  });

  /// The note's words as the screen was opened with them; a change to it is put into the editor whole.
  final String value;

  /// Every change to the words, the screen's own dispatches included.
  final ValueChanged<String> onChange;

  /// The editor's view, once it has one (`onView`).
  final ValueChanged<EditorView> onView;

  /// Marks and formatting both, or just the formatted text (`display`).
  final NoteView display;

  /// A note that may not be written in: one in the Trash.
  final bool readOnly;

  /// `look`: `reading`, `map`, or null for the usual one.
  final String? look;

  /// The pinch's zoom (`--note-zoom`): what [noteLookEnv] multiplies the note's sizes by.
  final double zoom;

  /// How wide the note's page is, for a page to read's column; the window's where it is left out.
  final double? pageWidth;

  /// How much of the page's top the header's glass covers, and of its foot the smoke (`footClear`): the line being
  /// typed is kept clear of both.
  final double headClear;
  final double footClear;

  final String placeholder;

  /// The hue the person wears, for their own selection (`data-me-hue`).
  final String? meHue;

  /// The extensions of pieces plugged in by whoever wires the app, after the base ones.
  final List<Extension> extensions;
}

/// Builds the editor for a note's screen: a SLIVER, for the page's scroll view.
typedef NoteEditorBuilder = Widget Function(BuildContext context, NoteEditorSpec spec);

/// Draws a host's view: a SLIVER.
typedef NoteEditorDraw = Widget Function(BuildContext context, EditorView view, LookEnv env);

/// The stand-in until piece D's `Editor` is wired: the note drawn, with no caret and no keyboard.
Widget readOnlyNoteEditor(BuildContext context, NoteEditorSpec spec) => NoteEditorHost(spec: spec);

/// The sizes a note's page gives its editor: `NoteScreen.module.css` `.page`, which redefines `--app-body` and
/// `--app-h1` to `--app-h6` as the kit's steps times the Text size setting times the pinch's zoom, and
/// `.body[data-look='reading']`, whose title is the kit's 5xl and whose words, from 600px, sit in a column of 36rem.
///
/// What differs: the reading column is made by widening the gutters to the column's edges, where the page centres
/// the content box; a line's own ground (a code block's, a quote's bar) then starts at the column and not at the
/// page's edge, which is where the page draws it too.
LookEnv noteLookEnv(BuildContext context, {double zoom = 1, String? look, String? meHue, int tabSize = 4, double? pageWidth}) {
  final t = context.tokens;
  double step(String name) => t.lenOf('calc(var(--glacier-font-size-$name) * var(--app-text-scale))') * zoom;
  final reading = look == 'reading';
  var gutter = t.len('app-gutter');
  final width = pageWidth ?? MediaQuery.sizeOf(context).width;
  if (reading && MediaQuery.sizeOf(context).width >= 600) gutter = math.max(gutter, (width - t.lenOf('36rem')) / 2);
  return LookEnv(
    t: t,
    body: step('lg'),
    headings: <double>[step(reading ? '5xl' : '4xl'), step('3xl'), step('2xl'), step('xl'), step('lg'), step('md')],
    gutter: gutter,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    dark: t.isDark,
    meHue: meHue,
    attrs: look == null ? const <String, String>{} : <String, String>{'data-look': look},
    tabSize: tabSize,
  );
}

/// Makes and keeps the `EditorView` for a note's screen, as `Editor.tsx` makes CodeMirror's, and has it drawn.
class NoteEditorHost extends StatefulWidget {
  const NoteEditorHost({super.key, required this.spec, this.draw});

  final NoteEditorSpec spec;

  /// What draws the view; an `EditorSliver`, which takes no typing, where it is left out.
  final NoteEditorDraw? draw;

  @override
  State<NoteEditorHost> createState() => _NoteEditorHostState();
}

class _NoteEditorHostState extends State<NoteEditorHost> {
  final Compartment _display = Compartment();
  final Compartment _look = Compartment();
  late EditorView _view = _make(widget.spec.value);

  EditorView _make(String doc) => EditorView(
        state: EditorState.create(
          doc: doc,
          extensions: noteExtensions(
            readOnly: widget.spec.readOnly,
            more: <Extension>[
              history(),
              _display.of(noteView(widget.spec.display)),
              _look.of(lookExtensions(widget.spec.look)),
              EditorViewLike.updateListener.of((update) {
                if (update.docChanged) widget.spec.onChange(update.state.doc.toString());
              }),
              // The line a change lands on stays clear of the header's glass and the foot's smoke.
              EditorViewLike.scrollMargins.of((_) => EdgeInsets.only(top: widget.spec.headClear, bottom: widget.spec.footClear)),
              ...widget.spec.extensions,
            ],
          ),
        ),
      );

  @override
  void initState() {
    super.initState();
    _tell();
  }

  /// After the frame, as the page's effect runs after the editor is in the document.
  void _tell() {
    final view = _view;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(view, _view)) widget.spec.onView(view);
    });
  }

  @override
  void didUpdateWidget(NoteEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.spec, now = widget.spec;
    if (was.readOnly != now.readOnly || !identical(was.extensions, now.extensions)) {
      // Another configuration: a new view over the words as they are.
      final doc = _view.state.doc.toString();
      _view.destroy();
      _view = _make(doc);
      _tell();
      return;
    }
    final effects = <StateEffect<Object?>>[
      if (was.display != now.display) _display.reconfigure(noteView(now.display)),
      if (was.look != now.look) _look.reconfigure(lookExtensions(now.look)),
    ];
    if (effects.isNotEmpty) _view.dispatch(TransactionSpec(effects: effects));
    // The words changed from outside the editor: a canvas's JSON or a book's Markdown, asked for.
    if (was.value != now.value) {
      final doc = _view.state.doc.toString();
      if (doc != now.value) _view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: doc.length, insert: now.value)));
    }
  }

  @override
  void dispose() {
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final env = noteLookEnv(context, zoom: spec.zoom, look: spec.look, meHue: spec.meHue, tabSize: _view.state.tabSize, pageWidth: spec.pageWidth);
    return widget.draw?.call(context, _view, env) ?? EditorSliver(view: _view, env: env, meHue: spec.meHue);
  }
}
