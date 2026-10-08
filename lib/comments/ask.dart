/// "Add a comment" from a note's menu in a list. A port of `src/app/core/comments/ask.ts`. (Matt: "add them to the
/// context menu for a note ... so we can quickly click to add comments".)
///
/// The note is opened, and its screen starts a comment on its first line once its editor is there. Said through
/// here rather than through the screen's route, so a note already open hears it too; taken by the one screen it
/// names, once.
///
/// What differs: the page's module store is [CommentAsks], a [ValueListenable] (`useCommentAsk`), with the app's
/// one as [commentAsks].
library;

import 'package:flutter/foundation.dart';

/// A comment wanted on a note: which, and when it was asked for, in ms.
typedef CommentAsk = ({String noteId, int at});

/// The comment asked for, if one is waiting to be taken.
class CommentAsks extends ValueNotifier<CommentAsk?> {
  CommentAsks() : super(null);

  /// A comment wanted on [noteId]'s first line, as soon as it is open (`askComment`).
  void ask(String noteId, [int? now]) => value = (noteId: noteId, at: now ?? DateTime.now().millisecondsSinceEpoch);

  /// Whether a comment was asked for on [noteId], the ask taken so nothing hears it twice (`takeCommentAsk`).
  bool take(String noteId) {
    final asked = value;
    if (asked == null || asked.noteId != noteId) return false;
    value = null;
    return true;
  }
}

/// The app's own.
final CommentAsks commentAsks = CommentAsks();
