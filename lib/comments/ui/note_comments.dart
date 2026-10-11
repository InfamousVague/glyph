/// The note's comments on its screen (tauri/docs/SHARED.md, S8): what the editor's drawing opens
/// (lib/editor/comments/comments.dart), what every way in starts (Comment on the press-and-hold band, in More and in
/// the bar, "Add a comment" on a note's menu in a list; Matt: "add them to the context menu for a note and the
/// popover toolbar so we can quickly click to add comments") and the sheet the card is drawn in. A port of
/// `src/app/editor/useNoteComments.tsx`.
///
/// Every change is a few edits from lib/comments/format.dart put through the editor as one dispatch, as the More
/// sheet's Look is: one undo step, saved the way typing is, and in a team note a change the document merges with
/// everyone else's rather than the note written again (lib/live/editor_binding.dart hears it as it hears typing).
///
/// What differs:
/// - The page's hook is [ScreenComments] (what it answered was called `NoteComments` there, a name the format's
///   reading has here, lib/comments/format.dart), a [ChangeNotifier] the note's desk holds for the screen's life
///   (lib/root/note_desk.dart): it tells its listeners when the sheet opens, turns its page or closes, and when the
///   note changes under an open card. The editor is asked for through [view], as the hook read it through a ref.
/// - The colours are handed in ([colours]) by whoever knows where the note is filed; [recolour] is the hook's
///   effect on `colours.key`, called when they may have changed.
/// - The ask from a note's menu ([takeAsk]) is taken when the desk says the editor has arrived, where the hook
///   followed the ask's store and the view together.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../account/session.dart';
import '../../core/front_matter.dart';
import '../../editor/comments/comments.dart';
import '../../editor/editor.dart';
import '../../editor/view/editor_view.dart';
import '../ask.dart';
import '../author.dart';
import '../colours.dart';
import '../format.dart';
import 'card.dart';
import 'sheet.dart';

/// What a note that cannot be written in says to Comment.
const String commentRefused = 'This note can’t take a comment while it is being written by something else.';

/// What a place a thread cannot go says.
const String commentMisplaced = 'Comments go on the note’s words. Put the caret on a line, or select some words, and try again.';

/// What a deleted thread says.
const String commentDeleted = 'Thread deleted. Undo puts it back.';

/// The line a note is called by, counting from 1: its first line of words after its front matter (`titleLine`).
int titleLine(String doc) {
  final lines = doc.split('\n');
  final from = frontMatterEnd(lines);
  for (var i = from; i < lines.length; i += 1) {
    if (lines[i].trim().isNotEmpty) return i + 1;
  }
  return from + 1 < lines.length ? from + 1 : lines.length;
}

class ScreenComments extends ChangeNotifier {
  ScreenComments({required this.noteId, required this.view, required this.say, required this.colours, this.account, CommentAsks? asks, this.now}) : _asks = asks ?? commentAsks;

  final String noteId;

  /// The note's editor, once it is there.
  final EditorView? Function() view;

  /// A toast.
  final void Function(String message) say;

  /// Who wears what in this note, as it stands now (lib/comments/colours.dart [commentColours]).
  final CommentColours Function() colours;

  /// The account, for the handle a comment is by; null in a build with none, where every comment is `me`'s.
  final AccountSource? account;
  final CommentAsks _asks;

  /// This moment, for a stamp; the clock's unless given.
  final DateTime Function()? now;

  CommentPage? _page;

  /// Where the comment being written goes: held from the press, so the caret moving under the sheet does not
  /// move it.
  Target? _target;
  String? _drawnIn;

  /// What the sheet is showing; null while it is closed.
  CommentPage? get page => _page;

  void _show(CommentPage? page) {
    _page = page;
    notifyListeners();
  }

  Stamp _stamp() => stampHere(account, now?.call());

  /// What the editor is handed: one object for the screen's life, its answers read live.
  late final CommentHooks hooks = CommentHooks(
    open: (id) {
      fireMotor(HapticKind.selection);
      _show(ThreadPage(id));
    },
    colour: (handle) => colours().of(handle),
    me: () => commentHandle(account),
    // Drawn again when the note changes under an open card: a reply from another member arriving live.
    changed: () {
      if (_page != null) notifyListeners();
    },
  );

  /// A colour read or changed: the rounds and the washes drawn again in it.
  void recolour() {
    final editor = view();
    final key = colours().key;
    if (editor == null || key == _drawnIn) return;
    _drawnIn = key;
    editor.dispatch(TransactionSpec(effects: refreshComments.of(null)));
    if (_page != null) notifyListeners();
  }

  static bool _editable(EditorView? editor) => editor != null && editor.state.facet(EditorViewLike.editable) && !editor.state.readOnly;

  /// The edits into the editor as one change; false where there was nothing to write.
  bool _write(List<Edit>? edits) {
    final editor = view();
    if (edits == null || editor == null || !_editable(editor)) return false;
    editor.dispatch(
      TransactionSpec(
        changes: ChangeSet.of(<ChangeSpec>[for (final edit in edits) ChangeSpec(from: edit.from, to: edit.to, insert: edit.insert)], editor.state.doc.length),
        userEvent: 'input.comment',
      ),
    );
    return true;
  }

  void _begin(Target wanted) {
    final editor = view();
    if (editor == null || !_editable(editor)) {
      say(commentRefused);
      return;
    }
    // Tried with words first, so a place a thread cannot go (inside the comments themselves) is said now, not after
    // the words are written.
    if (addThread(editor.state.doc.toString(), wanted, _stamp(), 'x', 'cx') == null) {
      say(commentMisplaced);
      return;
    }
    _target = wanted;
    String? quote;
    if (wanted case SpanTarget(:final from, :final to)) {
      final picked = editor.state.sliceDoc(from, to).trim();
      if (picked.isNotEmpty) quote = picked.contains('\n') ? '${picked.split('\n').first}…' : picked;
    }
    fireMotor(HapticKind.selection);
    _show(NewPage(quote));
  }

  /// Starts a comment on the selection, or on the caret's line; [range] is a selection the caller holds.
  void start([({int from, int to})? range]) {
    final editor = view();
    if (editor == null) return;
    final main = editor.state.selection.main;
    final (from, to, head) = range == null ? (main.from, main.to, main.head) : (range.from, range.to, range.to);
    _begin(from != to ? SpanTarget(from < to ? from : to, from < to ? to : from) : LineTarget(editor.state.doc.lineAt(head).number));
  }

  /// "Add a comment" from a note's menu in a list: once the editor is here, a comment on the note's first line.
  void takeAsk() {
    final editor = view();
    if (editor == null || !_asks.take(noteId)) return;
    _begin(LineTarget(titleLine(editor.state.doc.toString())));
  }

  /// Opens the list of threads.
  void openList() => _show(const ListPage());

  void close() => _show(null);

  String _doc() => view()?.state.doc.toString() ?? '';

  /// "3 comments, 1 open", read now; null for none.
  String? summary() => countWords(readComments(_doc()).threads);

  /// The comment being written, added where the press that started it was (`onAdd`).
  void add(String words) {
    final wanted = _target;
    if (wanted == null || !_write(addThread(_doc(), wanted, _stamp(), words))) return;
    _target = null;
    fireMotor(HapticKind.success);
    close();
  }

  /// A reply under a thread (`onReply`).
  void reply(String id, String words) {
    if (_write(addReply(_doc(), id, _stamp(), words))) fireMotor(HapticKind.success);
  }

  /// A thread closed, by this person, now (`onResolve`).
  void resolve(String id) {
    if (_write(resolveThread(_doc(), id, _stamp()))) fireMotor(HapticKind.success);
  }

  /// A closed thread open again (`onReopen`).
  void reopen(String id) {
    if (_write(reopenThread(_doc(), id))) fireMotor(HapticKind.selection);
  }

  /// A thread taken out, its comments and its mark in the note (`onDelete`).
  void delete(String id) {
    if (!_write(deleteThread(_doc(), id))) return;
    fireMotor(HapticKind.warning);
    close();
    say(commentDeleted);
  }

  /// The sheet, while one is open.
  Widget? sheet(BuildContext context) {
    final page = _page;
    final editor = view();
    if (page == null || editor == null) return null;
    final comments = readComments(editor.state.doc.toString());
    final wears = colours();
    return CommentSheet(
      page: page,
      threads: [for (final thread in comments.threads) cardThread(thread)],
      people: CardPeople(colour: wears.of, me: commentHandle(account)),
      quoteOf: (id) => quoteOf(editor.state, comments, id),
      onClose: close,
      onOpen: (id) => _show(ThreadPage(id)),
      onList: openList,
      onAdd: add,
      onReply: reply,
      onResolve: resolve,
      onReopen: reopen,
      onDelete: delete,
      now: now?.call().millisecondsSinceEpoch,
    );
  }
}
