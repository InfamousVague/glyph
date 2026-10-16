/// This device's stores, as the sync pass is handed them. A port of `deviceNotes` and `deviceFiles` in
/// `src/app/core/sync/engine.ts`: the library's notes behind [LocalNotes], and the recordings, pictures and versions
/// files behind [LocalFiles].
///
/// [LibraryNotes] speaks to the Rust core by the web's own commands (docs/STAGE3.md): `list_notes`, `get_note {id}`,
/// `store_apply {note}`, `delete_note {id}`. `store_apply` overwrites what the library keeps beside a note, so it is
/// only ever handed a whole note: the pass (notes.dart) applies a note out of another device's payload, or one of
/// this device's own that it has just read with `get`. **Always get before apply; never apply a note from the
/// list.**
///
/// [KeptFiles] is the versions files where they already live (lib/core/versions_store.dart) and everything else
/// through [DeviceBytes], which is the ask this file makes of whoever holds the device's recordings and pictures
/// (the core's file commands, lib/core/native/files.dart, when they are there).
///
/// What differs:
/// - The page reads a recording through a `rec:` URL and a picture through `imageBytes`, and files a recording with
///   `sync_put_file`; here all four are [DeviceBytes], with no command named in this file.
/// - The page asks whether the binary is new enough for `recording_digest` (native generation 20) and whether it is
///   iOS, which hashes nothing; here that is [DeviceBytes.recordingSha256] answering null. A call that FAILS is
///   "cannot say" as well, never "no tape": remembered as no tape, the note would travel without its tape's
///   fingerprint for good.
/// - The list is asked of the core, not of [NoteLibrary]: the library's own list hides what the shell took out for
///   an Undo and shows drafts that have no file, and neither is what the account should hear.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/native/core.dart';
import '../core/note.dart';
import '../core/note_json.dart';
import '../core/versions_store.dart';
import 'notes.dart';

/// [LocalNotes] over the Rust core.
class LibraryNotes implements LocalNotes {
  const LibraryNotes(this._invoke);

  final CoreInvoke _invoke;

  @override
  Future<List<Note>> list() async => notesFromJson(await _invoke('list_notes'));

  @override
  Future<Note?> get(String id) async => noteFromJson(await _invoke('get_note', {'id': id}));

  /// `applyNote`: the note written exactly as given. Only ever a whole note (see the header).
  @override
  Future<Note> apply(Note note) async {
    final stored = noteFromJson(await _invoke('store_apply', {'note': noteToJson(note)}));
    if (stored == null) throw const CoreError('the note was written, and the library did not say how');
    return stored;
  }

  /// `deleteNote`: for good. One already gone is not an error.
  @override
  Future<void> remove(String id) async {
    await _invoke('delete_note', {'id': id});
  }
}

/// This device's recordings (by note id) and pictures (by name), as bytes: what [KeptFiles] asks of whoever holds
/// them.
abstract interface class DeviceBytes {
  /// The file, or null where this device has none. [kind] is a recording or a picture, never a versions file.
  Future<Uint8List?> read(FileKind kind, String name);

  /// Keeps the file as another device sent it. A picture is drawn at once wherever a page was waiting for it.
  Future<void> write(FileKind kind, String name, Uint8List bytes);

  /// A recording's SHA-256 made without reading it into the app, as 64 hex characters; empty for no tape by that
  /// name; null where this device cannot say. May throw, which is "cannot say" too.
  Future<String?> recordingSha256(String name);
}

/// The files notes link and the words read in their pictures and files (lib/files/): kept by Dart beside the
/// pictures, not by the core, which keeps only what it can check (a picture is what its name says, a recording is
/// a RIFF file). [owed] is the notes whose words were read here since they were last sent.
abstract interface class MediaFiles {
  Future<Uint8List?> read(FileKind kind, String name);
  Future<void> write(FileKind kind, String name, Uint8List bytes);
  Future<int?> lengthOf(FileKind kind, String name);
  List<String> owed();
  void settled(String noteId);
}

/// This device's [MediaFiles], once lib/files/files_kit.dart has made them; none before, and none in a run with no
/// data folder, where a note's files are nothing this device has.
MediaFiles? mediaFiles;

bool _media(FileKind kind) => kind == FileKind.attachment || kind == FileKind.text;

/// [LocalFiles] on this device: the versions files in the [VersionsStore], a note's files and the words read in its
/// things in [MediaFiles], the rest in [DeviceBytes].
class KeptFiles implements LocalFiles {
  const KeptFiles({required this.versions, required this.bytes, this.media});

  final VersionsStore versions;
  final DeviceBytes bytes;

  /// The files notes link, and the words read; the app's own ([mediaFiles]) unless given.
  final MediaFiles? media;

  MediaFiles? get _files => media ?? mediaFiles;

  @override
  Future<Uint8List?> read(FileKind kind, String name) async {
    if (_media(kind)) return _files?.read(kind, name);
    if (kind != FileKind.versions) return bytes.read(kind, name);
    final text = await versions.readVersionsFile(name);
    return text == null ? null : utf8.encode(text);
  }

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    if (_media(kind)) {
      final files = _files;
      if (files == null) throw StateError('This device keeps no files.');
      return files.write(kind, name, bytes);
    }
    // A versions file from the account is not owed back to it; what this device adds to it is, when it adds it.
    if (kind == FileKind.versions) return versions.writeVersionsFile(name, utf8.decode(bytes, allowMalformed: true), owed: false);
    return this.bytes.write(kind, name, bytes);
  }

  @override
  Future<int?> lengthOf(FileKind kind, String name) async {
    if (_media(kind)) return _files?.lengthOf(kind, name);
    return (await read(kind, name))?.length;
  }

  @override
  List<String> owed() {
    final words = _files?.owed() ?? const <String>[];
    final kept = versions.unsentVersions();
    return words.isEmpty ? kept : <String>{...kept, ...words}.toList();
  }

  @override
  void settled(String name) {
    versions.sentVersions(name);
    _files?.settled(name);
  }

  /// The same first sixteen bytes of the SHA-256 the pass would take itself.
  @override
  FileDigest get digest => (name) async {
        final String? answer;
        try {
          answer = await bytes.recordingSha256(name);
        } catch (_) {
          return null;
        }
        if (answer == null) return null;
        if (answer.isEmpty) return const RecordingDigest.none();
        return answer.length >= 32 ? RecordingDigest(answer.substring(0, 32)) : null;
      };
}
