/// The words a comment's card says about people and times (card.dart), and the shape a thread is drawn from. A port
/// of `src/app/editor/commentWords.ts`, with `CardComment` and `CardThread` from `editor/CommentCard.tsx`, which the
/// card, the sheet and the editor's drawing all read.
///
/// What differs:
/// - A thread as the card draws it is a record, the one lib/canvas/comments.dart already answers (`threadsOf`): the
///   same type, since a record is its fields, so a canvas's threads go to the card as they are and a note's through
///   [cardThread].
/// - `ago` read a time with `Date.parse`, which takes more than ISO 8601 (an engine's own extras); here it is
///   [DateTime.tryParse], which takes what the fence writes and what a person would write in its place.
library;

import '../../notes/when.dart';
import '../format.dart' show Thread;

/// One comment, as the card draws it (`CardComment`): who, when (ISO 8601) and the words.
typedef CardComment = ({String by, String at, String words});

/// A thread, as the card draws it (`CardThread`): a note's ([cardThread]) or a canvas's.
typedef CardThread = ({String id, CardComment head, List<CardComment> replies, ({String by, String at})? resolved});

/// A note's thread as the card draws it.
CardThread cardThread(Thread thread) => (
      id: thread.id,
      head: (by: thread.head.by, at: thread.head.at, words: thread.head.words),
      replies: [for (final reply in thread.replies) (by: reply.by, at: reply.at, words: reply.words)],
      resolved: thread.resolved == null ? null : (by: thread.resolved!.by, at: thread.resolved!.at),
    );

/// Who wears which colour (lib/comments/colours.dart), and who "you" are, for the names (`CardPeople`).
class CardPeople {
  const CardPeople({required this.colour, required this.me});

  /// The hue a handle wears here: a workspace hue, `ink` for none.
  final String Function(String handle) colour;

  /// This person's handle, written "You"; `me` is always you.
  final String me;
}

/// A person as the card names them: "You" for this person (`nameOf`).
String nameOf(String by, CardPeople people) => by == 'me' || by == people.me ? 'You' : by;

/// "2 hr ago" for a written time, or the time as written where it cannot be read (`ago`). [now] is in ms.
String ago(String at, [int? now]) {
  final read = DateTime.tryParse(at);
  return read == null ? at : when(read.millisecondsSinceEpoch, now);
}

/// "1 reply", "3 replies".
String repliesWords(int replies) => replies == 1 ? '1 reply' : '$replies replies';
