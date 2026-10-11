/// The editor's core, in one import: the state (`state/`, a port of @codemirror/state and of the history from
/// @codemirror/commands) and the interfaces extension files are written against (`view/decoration.dart`,
/// `view/widget.dart`, `view/plugin.dart`, from @codemirror/view). See docs/STAGE4.md.
///
/// An extension file from tauri/ that began
///
///     import { RangeSetBuilder, type Extension } from '@codemirror/state';
///     import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';
///
/// begins `import '../editor.dart';` here. One name collides with Flutter's: `Decoration` (painting's, the parent
/// of `BoxDecoration`), so beside this import `package:flutter/widgets.dart` is imported with `hide Decoration`.
library;

export 'state/change.dart';
export 'state/char.dart';
export 'state/history.dart';
export 'state/rangeset.dart';
export 'state/selection.dart';
export 'state/state.dart';
export 'state/text.dart';
export 'state/undo_slot.dart';
export 'view/decoration.dart';
export 'view/plugin.dart';
export 'view/widget.dart';
