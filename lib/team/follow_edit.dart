/// A team page's first edit makes its editor a follower (lib/team/follow.dart; Matt, 2026-10-31: "Auto-follow when
/// you create, edit or are mentioned on a team page"): the editor's extension that writes `watchers:` with the
/// change itself, so one Undo takes both back and nothing is written after it, as a ticket's auto-watch is
/// (lib/editor/tickets/tickets.dart `autoWatch`).
///
/// Only typing and deleting count, never another device's change, an undo or a redo, the page's own Follow
/// (`follow`), a ticket's writing (`ticket`) or Claude's; and only the first of them per page and per account on this
/// device ([FollowLedger]), so the front matter is read whole once and never again on the keystrokes after.
library;

import '../editor/editor.dart';
import 'follow.dart';

/// What the extension asks of whoever made the editor, each asked as it is used.
class FollowHooks {
  const FollowHooks({required this.noteId, required this.me, required this.teamPage, required this.ledger});

  final String noteId;

  /// The account's handle, or null signed out.
  final String? Function() me;

  /// Whether the note is a team's page now (filed in an organization).
  final bool Function() teamPage;
  final FollowLedger ledger;
}

/// [tr] with its editor made a follower of the page, where this is the page's first edit (see the header).
Object followOnFirstEdit(Transaction tr, FollowHooks hooks) {
  if (!tr.docChanged || tr.annotation(Transaction.remote) == true) return tr;
  if (!(tr.isUserEvent('input') || tr.isUserEvent('delete'))) return tr;
  final who = hooks.me();
  if (who == null || who.isEmpty || hooks.ledger.done(who, editReason(hooks.noteId)) || !hooks.teamPage()) return tr;
  final after = tr.newDoc.toString();
  final next = autoFollowEdit(noteId: hooks.noteId, before: tr.startState.doc.toString(), after: after, me: who, teamPage: true, ledger: hooks.ledger);
  if (next == null || next == after) return tr;
  var start = 0;
  while (start < after.length && start < next.length && after.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = after.length, nextEnd = next.length;
  while (end > start && nextEnd > start && after.codeUnitAt(end - 1) == next.codeUnitAt(nextEnd - 1)) {
    end -= 1;
    nextEnd -= 1;
  }
  final written = ChangeSet.of(ChangeSpec(from: start, to: end, insert: next.substring(start, nextEnd)), after.length);
  return TransactionSpec(changes: tr.changes.compose(written), selection: tr.newSelection.map(written), effects: tr.effects, annotations: tr.annotations, scrollIntoView: tr.scrollIntoView);
}

/// The extension: a team page's first edit follows it.
Extension followEdits(FollowHooks hooks) => EditorState.transactionFilter.of((tr) => followOnFirstEdit(tr, hooks));

/// The step that turns the editor's words [now] into [next], the least of them changed, as Follow on the More sheet
/// writes it (`follow`, which [followOnFirstEdit] leaves alone); null where nothing changes.
TransactionSpec? followChange(String now, String next) {
  if (now == next) return null;
  var start = 0;
  while (start < now.length && start < next.length && now.codeUnitAt(start) == next.codeUnitAt(start)) {
    start += 1;
  }
  var end = now.length, nextEnd = next.length;
  while (end > start && nextEnd > start && now.codeUnitAt(end - 1) == next.codeUnitAt(nextEnd - 1)) {
    end -= 1;
    nextEnd -= 1;
  }
  return TransactionSpec(changes: ChangeSpec(from: start, to: end, insert: next.substring(start, nextEnd)), userEvent: 'follow');
}
