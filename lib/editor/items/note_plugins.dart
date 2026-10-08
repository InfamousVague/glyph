/// How plugins reach the open note (lib/plugins/types.dart): through the editor, so each change a plugin makes is
/// one undo and saves like typing, and anything a plugin has to say shows on the note the way a picture's problem
/// does. Ports `src/app/editor/notePlugins.ts`.
///
/// Plain functions over the view: the note desk builds them when it needs them, and the editor reads the ones it
/// is given at the moment they are used (swipe_items.dart `action`, suggestions.dart `suggest`), so a plugin
/// switched on or off is followed without the editor being rebuilt.
///
/// What differs: the registry is a parameter of [itemSend] and [lineOffers], the app's own (`plugins`) unless
/// another is given, so a test asks its own.
library;

import '../../plugins/registry.dart';
import '../../plugins/types.dart';
import '../editor.dart';
import 'suggestions.dart';
import 'swipe_items.dart';

class _Editing implements NoteEditing {
  _Editing(this.noteId, this._view, this._body, this._say);

  @override
  final String noteId;
  final EditorViewLike? _view;
  final String Function() _body;
  final void Function(String message) _say;

  @override
  String body() => _view?.state.doc.toString() ?? _body();

  @override
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next) {
    final view = _view;
    if (view == null) return false;
    final doc = view.state.doc;
    for (var n = 1; n <= doc.lines; n += 1) {
      final line = doc.line(n);
      if (find(line.text, n)) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: line.from, to: line.to, insert: next(line.text))));
        return true;
      }
    }
    return false;
  }

  @override
  void say(String message) => _say(message);
}

/// The note as plugins change it. `view` is the editor, when there is one; `body` answers the live document when
/// there is not (a canvas or a book drawn in its place); `say` puts a sentence on the note.
NoteEditing noteEditing(String noteId, EditorViewLike? view, String Function() body, void Function(String message) say) => _Editing(noteId, view, body, say);

/// What a plugin does with one of this note's items, where one takes them (a Notion board, a GitHub issue): the
/// swipe on an item (swipe_items.dart) and the press-and-hold menu's send are the same action. Null where no
/// switched-on plugin takes this note's items.
SwipeAction? itemSend(String noteId, NoteEditing editing, {Registry? registry}) {
  final action = (registry ?? plugins).itemAction(noteId);
  return action == null ? null : SwipeAction(label: action.label, busyLabel: action.busyLabel, run: (text) => action.run(text, editing));
}

/// The quiet words after lines a plugin could act on (suggestions.dart), for the note's words as they are now.
List<LineSuggestion> lineOffers(String noteId, NoteEditing editing, String text, {Registry? registry}) => <LineSuggestion>[
  for (final s in (registry ?? plugins).suggestions(noteId, text)) LineSuggestion(line: s.line, label: s.label, busyLabel: s.busyLabel, run: () => s.run(editing)),
];
