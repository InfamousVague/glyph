/// The phone's inbox and the library, as the watch's tests hold them (lib/watch).
library;

import 'dart:async';
import 'dart:io';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/watch/watch_link.dart';
import 'package:ghost_md/watch/watch_notes.dart';

/// The phone's inbox, as a test holds it.
class FakeHost implements WatchHost {
  final List<WatchTake> takes = [];
  final List<String> doneIds = [];
  final StreamController<String> _arrivals = StreamController<String>.broadcast();
  WatchStatus said = const WatchStatus();

  void arrive(WatchTake take) {
    takes.add(take);
    _arrivals.add(take.id);
  }

  @override
  Future<List<WatchTake>> waiting() async => [...takes]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

  @override
  Future<void> done(String id) async {
    doneIds.add(id);
    takes.removeWhere((t) => t.id == id);
  }

  @override
  Stream<String> get arrivals => _arrivals.stream;

  @override
  Future<WatchStatus> status() async => said;
}

/// The library and the core's files, as a test holds them.
class FakeStore implements WatchNoteStore {
  final Map<String, Note> notes = {};

  /// Note id -> the path its recording was moved from.
  final Map<String, String> recordings = {};
  Object? failMaking;

  @override
  Future<Note?> getNote(String id) async => notes[id];

  @override
  Future<bool> hasRecording(String id) async => recordings.containsKey(id);

  @override
  Future<void> keepRecording(String id, String path) async {
    final file = File(path);
    if (!file.existsSync()) throw StateError('no file at $path');
    file.deleteSync();
    recordings[id] = path;
  }

  /// The recordings removed, by note id.
  final List<String> dropped = [];

  @override
  Future<void> dropRecording(String id) async {
    recordings.remove(id);
    dropped.add(id);
  }

  @override
  Future<Note> makeNote({required String id, required String body, required int createdAt, required int recordingMs, required List<Segment> segments}) async {
    if (failMaking != null) throw failMaking!;
    if (notes.containsKey(id)) throw StateError('the note id already exists');
    return notes[id] = Note(id: id, body: body, createdAt: createdAt, updatedAt: createdAt, source: NoteSource.capture, recordingMs: recordingMs, segments: segments);
  }
}
