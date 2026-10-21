/// The phone's own halves of [WatchNotes] (docs/WATCH.md, "On the phone"): the library a take becomes a note in, and
/// the core's Whisper that hears it. Made by voice (lib/root/voice_wiring.dart).
library;

import '../capture/native_backend.dart';
import '../core/library.dart';
import '../core/native/files.dart';
import '../core/note.dart';
import 'watch_notes.dart';

/// [WatchNoteStore] over the app's library and the core's files.
class LibraryWatchNotes implements WatchNoteStore {
  LibraryWatchNotes(this.library, this.files, {this.removeRecordings});

  final NoteLibrary library;
  final CoreFiles files;

  /// The core's `recording_delete` (lib/ai/native_backend.dart `recordingDelete`); none, and a recording stays.
  final Future<void> Function(List<String> ids)? removeRecordings;

  @override
  Future<void> dropRecording(String id) async => removeRecordings?.call([id]);

  @override
  Future<Note?> getNote(String id) => library.get(id);

  @override
  Future<bool> hasRecording(String id) => files.exists(CoreFileKind.recording, id);

  @override
  Future<void> keepRecording(String id, String path) => files.adopt(CoreFileKind.recording, id, path);

  @override
  Future<Note> makeNote({required String id, required String body, required int createdAt, required int recordingMs, required List<Segment> segments}) async {
    final made = await library.createNote(body, source: NoteSource.capture, id: id);
    final note = await library.get(made.id) ?? made;
    // Dated when the watch recorded it, with its tape, written as a recording's length and phrases are
    // (lib/capture/recorder.dart `setNoteRecording`): the note read whole, then applied.
    return library.apply(Note(
      id: note.id,
      body: note.body,
      createdAt: createdAt > 0 && createdAt < note.createdAt ? createdAt : note.createdAt,
      updatedAt: note.updatedAt,
      source: note.source,
      sourceName: note.sourceName,
      starred: note.starred,
      archivedAt: note.archivedAt,
      recordingMs: recordingMs,
      segments: List<Segment>.unmodifiable(segments),
      formatted: note.formatted,
      formattedFor: note.formattedFor,
      formattedModel: note.formattedModel,
      path: note.path,
      revision: note.revision,
    ));
  }
}

/// Whether a refusal from the engine means "not now" rather than "not ever".
bool _busy(Object failure) {
  final said = failure.toString().toLowerCase();
  return said.contains('busy') || said.contains('capturing') || said.contains('cancelled');
}

/// Hears note [noteId]'s recording with the phone's Whisper (see watch_notes.dart's header): the larger model's timed
/// phrases where it is here (`capture_refine` over the whole tape), else the live model's words in one pass
/// (`transcribe_wav`), fetched first where it is not here and Local only is off.
Future<Heard> listenWithCore(NativeCaptureBackend capture, CoreFiles files, String noteId, {required bool Function() localOnly}) async {
  try {
    final larger = await capture.refineModelStatus();
    if (larger.present) {
      return HeardWords(await capture.refine(id: noteId, fromMs: 0, promptTail: ''));
    }
    var live = await capture.modelStatus();
    if (!live.present) {
      if (localOnly()) return const HeardLater('no voice model on this phone, and Local only is on');
      live = await capture.fetchModel();
      if (!live.present) return const HeardLater('the voice model did not download');
    }
    final where = await files.where(CoreFileKind.recording, noteId);
    if (where == null) return const HeardLater('the recording is not on this phone');
    final said = await capture.transcribeWav(where.path);
    final text = said.text.trim();
    return HeardWords(text.isEmpty ? const [] : [Segment(startMs: 0, endMs: said.audioMs, text: text)]);
  } catch (failure) {
    if (_busy(failure)) return HeardLater('the voice engine is busy ($failure)');
    rethrow;
  }
}
