/// The + beside the line, in one import: which line it is drawn on (plus_line.dart), the + as the editor keeps it
/// (insert_plus.dart) and as it is drawn (plus_layer.dart), its list (add_list.dart) and what the rows are and
/// write (add_rows.dart, query_templates.dart). See each file for the web file it ports.
///
/// A note's screen needs three things of it:
///
///     final plus = PlusController(allowed: () => writingWords);        // once, with the screen
///     EditorState.create(doc: ..., extensions: [..., plus.extension]);  // among the editor's extensions
///     PlusLayer(view: view, controller: plus, config: AddConfig(...), child: thePageScrollView)
///
/// and `plus.recheck(view)` when what `allowed` answers has changed.
library;

export 'add_list.dart';
export 'add_rows.dart';
export 'insert_plus.dart';
export 'plus_layer.dart';
export 'plus_line.dart';
export 'query_templates.dart';
