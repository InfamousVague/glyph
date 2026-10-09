/// The note's comments in the app's sheet (lib/sheet/sheet.dart: a centred card on a desktop, a drawer from the
/// bottom on a phone): one thread's card, a new comment's field, or every thread in the note as a list, each row
/// opening its card. A port of `src/app/editor/CommentSheet.tsx`. What each press does is the note screen's
/// (note_comments.dart), which writes it into the editor, or the canvas's (lib/canvas/canvas_comments.dart).
library;

import 'package:flutter/widgets.dart';

import '../../note/version_history.dart' show SheetBack;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'card.dart';

/// What the sheet is showing (`CommentPage`).
sealed class CommentPage {
  const CommentPage();
}

/// One thread's card.
class ThreadPage extends CommentPage {
  const ThreadPage(this.id);
  final String id;

  @override
  bool operator ==(Object other) => other is ThreadPage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A new comment's field, over the words it is about.
class NewPage extends CommentPage {
  const NewPage(this.quote);
  final String? quote;

  @override
  bool operator ==(Object other) => other is NewPage && other.quote == quote;

  @override
  int get hashCode => quote.hashCode;
}

/// Every thread, as a list.
class ListPage extends CommentPage {
  const ListPage();

  @override
  bool operator ==(Object other) => other is ListPage;

  @override
  int get hashCode => 0;
}

class CommentSheet extends StatelessWidget {
  const CommentSheet({
    super.key,
    required this.page,
    required this.threads,
    required this.people,
    required this.quoteOf,
    required this.onClose,
    required this.onOpen,
    required this.onList,
    required this.onAdd,
    required this.onReply,
    required this.onResolve,
    required this.onReopen,
    required this.onDelete,
    this.now,
  });

  final CommentPage page;
  final List<CardThread> threads;
  final CardPeople people;

  /// The words a thread is about, as the note has them now; null for one after a line's words.
  final String? Function(String id) quoteOf;
  final VoidCallback onClose;
  final ValueChanged<String> onOpen;

  /// Back to the list from a thread, where there is more than one.
  final VoidCallback onList;
  final ValueChanged<String> onAdd;
  final void Function(String id, String words) onReply;
  final ValueChanged<String> onResolve;
  final ValueChanged<String> onReopen;
  final ValueChanged<String> onDelete;

  /// This moment in ms, for the cards; the clock's unless given.
  final int? now;

  @override
  Widget build(BuildContext context) {
    switch (page) {
      case NewPage(:final quote):
        return Sheet(
          label: 'New comment',
          onClose: onClose,
          children: [SheetTitle.text('New comment'), sheetBlock(NewComment(quote: quote, onSave: onAdd))],
        );
      case ListPage():
        return Sheet(
          label: 'Comments',
          onClose: onClose,
          children: [
            SheetTitle.text('Comments'),
            if (threads.isNotEmpty)
              sheetBlock(CommentList(threads: threads, people: people, onOpen: onOpen, now: now))
            else
              const SheetNote('No comments yet. Select some words, or put the caret on a line, and press Comment.'),
          ],
        );
      case ThreadPage(:final id):
        final thread = threads.where((each) => each.id == id).firstOrNull;
        final several = threads.length > 1;
        return Sheet(
          label: 'Comment thread',
          onClose: onClose,
          onBack: several ? onList : onClose,
          children: [
            if (several) SheetBack(label: 'All comments', onPressed: onList),
            if (thread != null)
              sheetBlock(
                CommentThread(
                  // A thread's own state (Delete armed, a reply half written) is not the next thread's.
                  key: ValueKey<String>('card ${thread.id}'),
                  thread: thread,
                  people: people,
                  quote: quoteOf(thread.id),
                  onReply: (words) => onReply(thread.id, words),
                  onResolve: () => onResolve(thread.id),
                  onReopen: () => onReopen(thread.id),
                  onDelete: () => onDelete(thread.id),
                  now: now,
                ),
              )
            else
              const SheetNote('This thread is not in the note any more.'),
          ],
        );
    }
  }
}
