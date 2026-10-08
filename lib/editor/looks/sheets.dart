/// The stylesheets an editor's extensions bring: CodeMirror's `EditorView.theme` and `EditorView.baseTheme`, as a
/// facet of [LookSheet]s.
///
/// An extension file that ended `EditorView.baseTheme({'.cm-tag': {...}})` ends `baseTheme(LookSheet('tags.ts',
/// [...]))` here, and its rules join the cascade the view resolves classes through. A plugin's format look (the
/// twelve marks) registers the same way: a sheet whose rules set a [RunPainter] on the run, which is the hook its
/// drawing goes through.
library;

import '../state/state.dart';
import 'look.dart';

/// The sheets in force over an editor, in precedence order: the first wins a tie.
final Facet<LookSheet, List<LookSheet>> lookSheets = Facet.define<LookSheet, List<LookSheet>>();

/// CodeMirror's `EditorView.theme(spec)`: a stylesheet for this editor. Its rules are scoped by a class of their
/// own there, so write each rule's `classes` one higher than its selector shows.
Extension editorTheme(LookSheet sheet) => lookSheets.of(sheet);

/// CodeMirror's `EditorView.baseTheme(spec)`: as [editorTheme], but under every theme.
Extension baseTheme(LookSheet sheet) => Prec.lowest(lookSheets.of(sheet));
