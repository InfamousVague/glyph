/// The extensions that make a note look like a note, assembled as `src/app/editor/Editor.tsx` assembles them: the
/// language, the highlighter, the line classes, the extended markdown, read-only in both of CodeMirror's senses,
/// the view mode and the look.
///
/// Editor.tsx lists some forty extensions; these are the ones the view's own piece ports (docs/STAGE4.md, piece
/// C). The others (marks and effects, tags, tables, links, pictures, the +, find...) are added by whoever makes
/// the state, through `more`, in their turn. Undo, the key bindings and the prose attributes of the keyboard are
/// the input layer's.
library;

import '../code/code_highlight.dart';
import '../maths/maths.dart';
import '../state/state.dart';
import '../syntax/language.dart';
import 'extended.dart';
import 'glyph_highlight.dart';
import 'glyph_lines.dart';
import 'plugin.dart';
import 'syntax_tree.dart';
import 'view_mode.dart';

/// Editor.tsx `readOnlyExtensions`: read-only in both of CodeMirror's senses. `readOnly` stops transactions from
/// editing; `editable` is what keeps the keyboard from rising over a note that is being dictated rather than
/// typed. (`boxTapsWhileReadOnly` is the to-do boxes' piece's.)
Extension readOnlyExtensions(bool readOnly) => Extension.list(<Extension>[EditorState.readOnlyFacet.of(readOnly), EditorViewLike.editable.of(!readOnly)]);

/// Editor.tsx `lookExtensions`: a look said on the editor for the stylesheets (`data-look`); nothing for the usual
/// look. (A reading note's lead line is `openHeading.ts`'s, with its piece.)
Extension lookExtensions(String? look) => look == null ? const Extension.list(<Extension>[]) : EditorViewLike.editorAttributes.of(<String, String>{'data-look': look});

/// The base of a note's editor.
Extension noteExtensions({
  Iterable<InlineFormatSyntax> formats = const <InlineFormatSyntax>[],
  NoteView display = NoteView.mixed,
  bool readOnly = false,
  String? look,
  bool maths = true,
  List<Extension> more = const <Extension>[],
}) => Extension.list(<Extension>[
  markdownSyntax(glyphMarkdown(formats)),
  glyphHighlight(formats),
  // A fenced block's code coloured by its language, and HTML's tags (lib/editor/code): in Editor.tsx these are
  // the language's own (`glyphMarkdown`'s `codeLanguages`) and the one highlighter's.
  codeHighlight(),
  glyphLines,
  // Superscript, subscript, callouts, definitions, front matter, maths and shortcodes (extended.dart).
  extendedMarkdown(),
  // Maths drawn as its formula off the caret's line (lib/editor/maths), which Editor.tsx lists for every editor.
  // (`maths: false` is for the pictures measured on a page that had only the view's own extensions on it,
  // test/editor/view: there a formula is its source, set as code.)
  if (maths) drawnMaths(),
  ...more,
  readOnlyExtensions(readOnly),
  noteView(display),
  lookExtensions(look),
]);
