/// A live document's words as an editor is bound to them (lib/live/editor_binding.dart): what `Y.Text` is to
/// y-codemirror, said for a document that is a call away.
///
/// A team note's document is one ([TeamDoc], lib/team/doc.dart), and so is an account's own note while it is live
/// ([LiveSession], session.dart). Both number the changes that reach the words from elsewhere
/// (lib/team/text_log.dart), and take an editor's own change with the number its words were at.
library;

import '../team/crdt.dart';
import '../team/text_log.dart';

export '../team/crdt.dart' show CrdtEdit;
export '../team/text_log.dart' show TextSplice;

/// The words, and the two ways they change.
abstract interface class LiveText {
  /// The document's words now, as far as this device has heard.
  String get words;

  /// How many changes from elsewhere they have taken.
  int get rev;

  /// An editor's own changes, in order, as one; [base] is the [rev] its words were at when it made them.
  Future<Object?> edit(List<CrdtEdit> edits, {int? base});

  /// Told each change from elsewhere, in order. Answers the way to stop hearing.
  void Function() onSplice(void Function(TextSplice splice) listener);

  /// Settles once everything asked of the document so far is done.
  Future<void> settled();
}
