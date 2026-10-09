/// A spoken command's write to one note, and its undo, as the store is asked for them and as it answers. A port of
/// `CommandMutationRequest`, `CommandMutationResult` and `CommandUndoResult` in `src/app/core/store.ts`, with the
/// JSON the Rust core reads and answers (`ApplyCommandRequest` in native/src/dispatch.rs; `CommandMutationResult`
/// and `CommandUndoResult` in `src-tauri/src/note.rs`).
///
/// A command applies only while the note is exactly what its preview was made from, and an undo only while the note
/// is exactly what the command left (`src-tauri/src/library/mutations.rs`): a later edit, typed or synced, is never
/// overwritten by either, and is answered as a conflict with the note as it now stands. The change is kept in the
/// library's index, so its undo still finds it after the app was closed.
///
/// What differs: each answer is a class of a sealed one, with the web's `status` as a getter, where the web has a
/// union of object literals told apart by their `status`. The request and `applyCommandMutation`'s answer were
/// declared in lib/capture/take_writer.dart while the library had no command mutations; that file hands them on.
library;

import 'native/core.dart';
import 'note.dart';
import 'note_json.dart';

/// A change a command asks the store to make to one note, if the note is still as it was read (`apply_command`).
class CommandMutationRequest {
  const CommandMutationRequest({
    required this.mutationId,
    required this.noteId,
    required this.kind,
    required this.beforeRevision,
    required this.beforeBody,
    required this.afterBody,
    required this.source,
  });

  final String mutationId;
  final String noteId;

  /// `append` or `create`.
  final String kind;
  final int? beforeRevision;
  final String? beforeBody;
  final String afterBody;
  final NoteSource source;
}

/// What the store answers: the change made, or the note as it now stands.
sealed class CommandMutationResult {
  const CommandMutationResult();

  /// The web's `status`.
  String get status;
}

final class CommandMutationResultApplied extends CommandMutationResult {
  const CommandMutationResultApplied({required this.mutationId, required this.note});

  final String mutationId;
  final Note note;

  @override
  String get status => 'applied';
}

final class CommandMutationResultConflict extends CommandMutationResult {
  const CommandMutationResultConflict({required this.current});

  final Note? current;

  @override
  String get status => 'conflict';
}

/// What the store answers an undo (`undo_command`): the change taken back, the note as it now stands where it has
/// changed since, or that there is nothing to take back.
sealed class CommandUndoResult {
  const CommandUndoResult();

  /// The web's `status`.
  String get status;
}

final class CommandUndoResultUndone extends CommandUndoResult {
  const CommandUndoResultUndone({required this.mutationId, required this.note});

  final String mutationId;

  /// The note with the words it had before the command, or null where the command had made the note, which is gone
  /// again.
  final Note? note;

  @override
  String get status => 'undone';
}

final class CommandUndoResultConflict extends CommandUndoResult {
  const CommandUndoResultConflict({required this.current});

  /// The note as it is now, which the undo left alone; null where it was deleted since.
  final Note? current;

  @override
  String get status => 'conflict';
}

final class CommandUndoResultAlreadyUndone extends CommandUndoResult {
  const CommandUndoResultAlreadyUndone();

  @override
  String get status => 'already-undone';
}

final class CommandUndoResultNotFound extends CommandUndoResult {
  const CommandUndoResultNotFound();

  @override
  String get status => 'not-found';
}

/// The request as the core reads it (`apply_command_mutation`'s `request`): every field said, and none it does not
/// name, which the core refuses.
Map<String, Object?> commandMutationRequestToJson(CommandMutationRequest request) => {
      'mutationId': request.mutationId,
      'noteId': request.noteId,
      'kind': request.kind,
      'beforeRevision': request.beforeRevision,
      'beforeBody': request.beforeBody,
      'afterBody': request.afterBody,
      'source': request.source.name,
    };

/// What `apply_command_mutation` answered. An answer that is neither of the two is an error, as a refusal is: the
/// caller cannot say whether anything was written.
CommandMutationResult commandMutationResultFromJson(Object? raw) {
  if (raw is Map) {
    final status = raw['status'];
    if (status == 'conflict') return CommandMutationResultConflict(current: noteFromJson(raw['current']));
    final mutationId = raw['mutationId'];
    final note = noteFromJson(raw['note']);
    if (status == 'applied' && mutationId is String && note != null) return CommandMutationResultApplied(mutationId: mutationId, note: note);
  }
  throw const CoreError('the command was asked for, and the library did not say what became of it');
}

/// What `undo_command_mutation` answered. An answer that is none of the four is an error, as a refusal is.
CommandUndoResult commandUndoResultFromJson(Object? raw) {
  if (raw is Map) {
    final mutationId = raw['mutationId'];
    switch (raw['status']) {
      case 'undone' when mutationId is String:
        return CommandUndoResultUndone(mutationId: mutationId, note: noteFromJson(raw['note']));
      case 'conflict':
        return CommandUndoResultConflict(current: noteFromJson(raw['current']));
      case 'already-undone':
        return const CommandUndoResultAlreadyUndone();
      case 'not-found':
        return const CommandUndoResultNotFound();
    }
  }
  throw const CoreError('the undo was asked for, and the library did not say what became of it');
}
