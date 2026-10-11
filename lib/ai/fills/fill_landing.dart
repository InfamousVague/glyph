/// A fill's answers into the open note (docs/DESIGN.md §145, 6.3): the note screen's editor is the one writer of an
/// open note, so the fills' queue hands it each generation's answers and it lands them in one transaction, with the
/// AI's signature in the same change on a press's first landing, told from the person's own edits (`aiEdit`),
/// arriving out of smoke as rewritten words do when the wisp is on, and a light tick under the thumb. A port of
/// `src/app/ai/fills/useFillLanding.ts`.
///
/// The queue finds a blank by the range this editor has tracked since the press (editor/ai/blanks.dart
/// `blanksField`), and by its question and order where the note was closed in between. The run itself is never
/// landed by the lines-as-they-finish lander (ai/note_landing.dart skips a fill), since a fill's answers go where
/// its blanks are, not over the note.
///
/// What differs: the hook is a [FillLanding], made for a note's editor once it has one and disposed of as the note
/// is left or its editor is replaced (the hook's `[noteId, view]`): made, it is the note's host for the queue
/// (`openForFills(noteId, host)`); disposed of, the note has none (`openForFills(noteId, null)`). The options are
/// asked as they are needed, as the hook's ref gave them. "The view is still in the page" (`view.dom.isConnected`)
/// is the landing not yet disposed of.
library;

import '../../editor/ai/blanks.dart' show blanksField, trackBlanks;
import '../../editor/input/felt.dart' show fireFelt;
import '../../editor/marks/wisp_motion.dart' show WispKind, wisp;
import '../../editor/state/change.dart';
import '../../editor/state/state.dart';
import '../ai_changes.dart';
import 'edits.dart';
import 'queue.dart';

/// See the header (`useFillLanding`).
class FillLanding {
  FillLanding(this.noteId, this._view, {required bool Function() wisp, required String? Function() owner})
      : _wisp = wisp,
        _owner = owner {
    openForFills(noteId, host);
  }

  final String noteId;
  final StateCommandTarget _view;

  /// Whether the answers arrive from smoke: asked as each lands.
  final bool Function() _wisp;

  /// The handle the note is the person's under, for the signature; null signed out.
  final String? Function() _owner;
  bool _disposed = false;

  /// What the queue is given: this editor as the note's one writer.
  late final FillHost host = _Host(this);

  /// Leaving the note: it has no host, and a fill still running lands in it closed (ai/fills/queue.dart).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    openForFills(noteId, null);
  }
}

class _Host implements FillHost {
  _Host(this._landing);

  final FillLanding _landing;

  StateCommandTarget get _view => _landing._view;

  @override
  String text() => _view.state.doc.toString();

  @override
  ({int from, int to})? rangeOf(String key) => _view.state.fieldOrNull(blanksField)?[key];

  @override
  void track(List<({String key, int from, int to})> targets) => _view.dispatch(TransactionSpec(effects: trackBlanks.of(targets)));

  @override
  String? land(List<TextChange> changes, TextChange? sign) {
    if (_landing._disposed) return null;
    // The signature is worked out afresh on the note as it reads now, with the owner the screen knows.
    final signature = sign != null ? signatureChange(_view.state.doc.toString(), _landing._owner()) : null;
    final all = <TextChange>[...changes, ?signature]..sort((a, b) => a.from - b.from);
    _view.dispatch(
      TransactionSpec(
        changes: <ChangeSpec>[for (final change in all) ChangeSpec(from: change.from, to: change.to, insert: change.insert)],
        annotations: <Annotation<Object?>>[aiEdit.of(AiEdit.land), if (_landing._wisp()) wisp.of(WispKind.rewrite)],
        userEvent: 'ai.land',
      ),
    );
    fireFelt('light');
    return _view.state.doc.toString();
  }
}
