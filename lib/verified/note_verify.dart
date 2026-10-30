/// One note's verification, as its desk holds it (lib/root/note_desk.dart): the badge at the top of its page and
/// Verify… on its More sheet, with the front matter written through the editor as one step, the caret kept with
/// the words, as the sheet's Look is written (lib/note/note_screen.dart `_writeFrontMatter`).
library;

import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../art/lucide.g.dart';
import '../comments/ui/note_colours.dart' show memberColoursOf, orgOfNote;
import '../core/front_matter.dart' show frontMatterOffset;
import '../editor/editor.dart';
import '../note/note_settings.dart' show NoteSheetItem;
import 'verified.dart';
import 'verified_badge.dart';

/// [change] made to the front matter of [view]'s note, as one step: a caret in the block, or at its end, goes to the
/// start of the words; one in the words moves by what the block grew. False where nothing changed.
bool writeFrontMatterIn(EditorViewLike view, String Function(String doc) change, String userEvent) {
  final doc = view.state.doc.toString();
  final after = change(doc);
  if (after == doc) return false;
  final was = frontMatterOffset(doc), now = frontMatterOffset(after);
  int place(int pos) => pos <= was ? now : pos + now - was;
  final selection = EditorSelection.create([for (final range in view.state.selection.ranges) EditorSelection.range(place(range.anchor), place(range.head))], view.state.selection.mainIndex);
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: was, insert: after.substring(0, now)), selection: selection, userEvent: userEvent));
  return true;
}

class NoteVerify {
  NoteVerify({required this.services, required this.noteId, required this.view, DateTime Function()? today}) : _today = today ?? DateTime.now;

  final AccountServices? services;
  final String noteId;
  final EditorViewLike? Function() view;
  final DateTime Function() _today;

  String? get _me => services?.session?.handle;

  /// Who can vouch for it: the members of its organization, in a team's note.
  List<String> get _owners {
    final services = this.services, org = orgOfNote(services, noteId);
    if (services == null || org == null) return const [];
    return (memberColoursOf(services).of(org) ?? const <String, String?>{}).keys.toList();
  }

  /// The badge, where the note says it is verified: pressed, [openVerify].
  Widget? badge({required String body, double? start, VoidCallback? openVerify}) {
    final verified = verifiedOf(body);
    if (verified == null) return null;
    return VerifiedBadge(verified: verified, edited: editedSinceVerified(verified, body), today: _today(), start: start, onPress: openVerify);
  }

  /// The badge for the note in [editor], or as last saved while it has none: its words read whole only where its
  /// first line opens front matter, so a letter typed in any other note costs nothing here.
  Widget? badgeOf(EditorViewLike? editor, {required String? Function() saved, VoidCallback? openVerify}) {
    if (editor == null) return badge(body: saved() ?? '', openVerify: openVerify);
    final doc = editor.state.doc;
    final first = doc.line(1).text.trim();
    if (first != '---' && first != '+++') return null;
    return badge(body: doc.toString(), openVerify: openVerify);
  }

  /// Verify…'s row and page; null where there is no editor to write through. Signed out, the owner is written `@me`.
  NoteSheetItem? item() {
    final editor = view();
    if (editor == null) return null;
    final me = _me ?? 'me';
    final body = editor.state.doc.toString();
    final verified = verifiedOf(body);
    final edited = verified != null && editedSinceVerified(verified, body);
    final today = _today();
    return NoteSheetItem(
      id: 'verify',
      icon: Lucide.shieldCheck,
      label: 'Verify…',
      hint: verifyHint(verified, edited, today),
      page: (context, close) => [
        VerifyPage(
          owners: _owners,
          me: me,
          verified: verified,
          edited: edited,
          today: today,
          close: close,
          onVerify: (by, days) => writeFrontMatterIn(editor, (doc) => withVerified(doc, by: by, days: days, today: today), 'input.verify'),
          onRemove: () => writeFrontMatterIn(editor, (doc) => withVerified(doc, by: null), 'input.verify'),
        ),
      ],
    );
  }
}
