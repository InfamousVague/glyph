import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';
import 'package:ghost_md/sync/notes.dart';

import '../support/fake_service.dart';
import '../support/sync_device.dart';

export '../feed/signed.dart' show apiOf, down, testAccount, testSession;
export '../support/fake_service.dart';
export '../support/sync_device.dart';

/// A device of the notes' pass.
typedef Device = SyncDevice<SyncState>;

/// A device of the seeded account, with nothing remembered (`syncDevice(api, …)`).
Device deviceOf(FakeService service, {int clock = 0, Map<String, List<int>> pictures = const {}, Fetcher? fetcher, FileDigest? digest}) => SyncDevice<SyncState>(
      service,
      state: emptyState(),
      clock: clock,
      pictures: {for (final entry in pictures.entries) entry.key: Uint8List.fromList(entry.value)},
      fetcher: fetcher,
      digest: digest,
    );

/// One pass of the notes on a device: the one line the web's `syncDevice` has as its `sync`.
extension NotesPassOnDevice on Device {
  Future<Outcome> run({Map<String, num> meetings = const {}, bool syncMeetingRecordings = false, bool Function(String id)? teamNote, bool Function(String id)? sharedLive}) =>
      sync((d) => syncNotes(SyncContext(
            token: d.token,
            key: d.key,
            notes: d.local,
            files: d.files,
            state: d.state,
            save: d.save,
            api: d.api,
            crypto: d.crypto,
            now: d.now,
            meetings: () => meetings,
            syncMeetingRecordings: () => syncMeetingRecordings,
            teamNote: teamNote,
            sharedLive: sharedLive,
          )));
}

/// A note for a test, as the web's `makeNote(id, body, extra)`.
Note note(String id, String body, {int createdAt = 0, int updatedAt = 0, bool starred = false, int? archivedAt, int? recordingMs, List<Segment>? segments, String? path}) =>
    Note(id: id, body: body, createdAt: createdAt, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt, recordingMs: recordingMs, segments: segments, path: path);

/// A note as a device edits it: new words, a later time.
Note edited(Note note, String body, int at) => note.copyWith(body: body, updatedAt: at);

/// A note, as text two of them can be compared by.
String said(Note? note) => note == null ? 'null' : jsonEncode(noteToJson(note));

/// The bodies of a device's notes, sorted.
List<String> bodies(Device device) => [for (final n in device.notes.values) n.body]..sort();
