/// The note's bookmark button. Ports `src/app/editor/useBookmark.ts`: the bookmark is written in the note as `§§`
/// (`bookmark_line.dart`), and pressed, it goes on the line being read or written, moving from wherever it was;
/// pressed on the line that already has it, it comes off. The note opens at it.
///
/// "The line being read" is the caret's own line first and the top of the page second: a bookmark marks the
/// words being read, not the top of the page.
///
/// A bookmark kept on this device from before bookmarks were written in is ribboned while it lasts and goes on
/// the first press: the note carries its own from then on.
///
/// What differs: the web's is a React hook; this is a [ChangeNotifier] the note screen keeps. Where the page is
/// being read (`notePlace.ts` `caretPlace`, `placeOf`) and the bookmark kept on the device (`readBookmark`,
/// `writeBookmark`) are the note screen's to say, through [here], [readKept] and [writeKept]; the wait for a
/// document long enough to hold the kept place is the caller's too ([showKept] when the words have arrived).
library;

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show HapticKind, haptic;

import '../editor.dart';
import 'bookmark_line.dart';

class NoteBookmark extends ChangeNotifier {
  NoteBookmark({required this.view, required this.say, this.here, this.readKept, this.writeKept}) : _marked = bookmarkLineOf(view.state.doc) != null || readKept?.call() != null;

  final EditorViewLike view;

  /// Tells the person what the press did.
  final void Function(String message) say;

  /// The position being read: the caret's where the editor has it, else the top of the page; null for neither.
  final int? Function()? here;

  /// The bookmark kept on this device from before bookmarks were written in, and its taking off.
  final int? Function()? readKept;
  final void Function(int? pos)? writeKept;

  bool _marked;

  /// Whether the note has a bookmark, in its words or kept on this device: the button is lit.
  bool get marked => _marked;

  /// The note's words changed under the button (another device, an undo): the light follows them.
  void sync() => _set(bookmarkLineOf(view.state.doc) != null || readKept?.call() != null);

  void _set(bool value) {
    if (value == _marked) return;
    _marked = value;
    notifyListeners();
  }

  /// The kept bookmark ribboned in the note, so the place can be seen.
  void showKept() => view.dispatch(TransactionSpec(effects: showBookmark.of(readKept?.call())));

  /// The button's press.
  void press() {
    final state = view.state;
    // Where there is nobody to say where the page is being read (a test of the button alone), the caret's line
    // while the editor has the focus.
    final at = here != null ? here!() : (view.hasFocus ? state.selection.main.head : null);
    final current = bookmarkLineOf(state.doc);
    final kept = readKept?.call();
    final target = at != null ? markedLine(state, at) : (state.doc.length > 0 ? 1 : null);
    final was = current ?? (kept != null ? markedLine(state, kept) : null);
    if (kept != null) writeKept?.call(null);
    if (target == null) {
      say('Write something first, then bookmark the line.');
      return;
    }
    if (was == target) {
      view.dispatch(placeBookmark(state, null));
      view.dispatch(TransactionSpec(effects: showBookmark.of(null)));
      _set(false);
      haptic(HapticKind.warning);
      say('Bookmark taken off.');
      return;
    }
    view.dispatch(placeBookmark(state, target));
    view.dispatch(TransactionSpec(effects: showBookmark.of(null)));
    _set(true);
    haptic(HapticKind.success);
    // The words it landed on are said back, so the place is known without scrolling to it.
    final words = markedWords(view.state, view.state.doc.line(target).from);
    final said = was == null ? 'Bookmarked at' : 'Bookmark moved to';
    say(words != null ? '$said “$words”. This note opens here.' : '$said this line. This note opens here.');
  }
}
