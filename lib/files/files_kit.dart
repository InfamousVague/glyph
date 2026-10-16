/// Files, scans and the words read in them, made once the device has said where its files are: the one thing the
/// app's root makes (lib/main.dart, one line), and everything else reaches it here ([FilesKit.current]).
///
/// It holds the [AttachmentStore] (the files notes link), the [ReadTexts] (the words read in them and in the
/// pictures), the device's half ([DocumentDevice]) and the [ReadPass] that reads. It is what sync is handed for
/// those files ([MediaFiles], lib/sync/local.dart), what the search reads beyond a note's words
/// (lib/core/note_text.dart `searchExtra`), and what the + menu's A file and Scan a document call ([pick],
/// [scanned]). Settings › Files and scans is drawn over it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/attachment_refs.dart';
import '../core/native/core.dart';
import '../core/phone_pictures.dart' show pictureAdopted;
import '../core/note_text.dart' as note_text;
import '../core/stored.dart';
import '../sync/local.dart' as sync_local;
import '../sync/notes.dart' show FileKind;
import 'attachment_store.dart';
import 'phone_documents.dart';
import 'read_pass.dart';
import 'read_text.dart';

/// The notes whose words were read since they last went to the account, kept on this device.
const String wordsOwedKey = 'glyph-words-owed';

final RegExp _pictureName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.(?:jpg|jpeg|png|webp)$');

/// Files, scans and the words read in them, on one device.
class FilesKit implements sync_local.MediaFiles {
  FilesKit({
    required this.dataDir,
    required this.store,
    required this.texts,
    required this.device,
    required Future<List<({String id, String body})>> Function() bodies,
    Stored? kept,
    bool listenForInput = true,
  })  : _bodies = bodies,
        _kept = kept {
    pass = ReadPass(texts: texts, device: device, pathOf: pathOf, bodies: bodies, onRead: owe, kept: kept, listenForInput: listenForInput);
  }

  /// The app's own, once [start] has made it.
  static FilesKit? current;

  /// Makes the app's own over the data folder and the core, and puts it where everything finds it: the store for
  /// what brings files in (`storeAttachment`), the words for the search, the files for sync. The sidecars are read
  /// in at once, off the UI's work, and the slow reading of what the notes already show begins [after] that.
  static FilesKit start({required String dataDir, required CoreInvoke invoke, DocumentDevice? device, Duration after = const Duration(seconds: 40)}) {
    Future<List<({String id, String body})>> bodies() async {
      final listed = await invoke('list_notes');
      return <({String id, String body})>[
        if (listed is List)
          for (final note in listed)
            if (note is Map && note['id'] is String) (id: note['id'] as String, body: note['body'] is String ? note['body'] as String : ''),
      ];
    }

    final kit = FilesKit(dataDir: dataDir, store: AttachmentStore(dataDir: dataDir), texts: ReadTexts(dataDir: dataDir), device: device ?? PhoneDocuments(), bodies: bodies);
    kit.install();
    unawaited(kit.device.canScan().then((can) => kit.scans = can));
    unawaited(kit.texts.load().then<void>((_) {
      if (kit.pass.on) Timer(after, () => unawaited(kit.pass.readExisting().catchError((Object _) {})));
    }, onError: (Object failure) => debugPrint('[files] the words read before were not read in: $failure')));
    return kit;
  }

  /// Puts this kit where the app finds it.
  void install() {
    current = this;
    keptAttachments = store;
    readTexts = texts;
    sync_local.mediaFiles = this;
    note_text.searchExtra = texts;
    noteGoneForGood = (id, body) => noteDeleted(body, id: id);
    pictureAdopted = pictureAdded;
    attachmentKept = (kept) => pass.readSoon(ReadThing.file(kept.name));
  }

  /// Takes the app's kit away again, and everything that found it: for a test.
  @visibleForTesting
  static void uninstall() {
    current = null;
    keptAttachments = null;
    readTexts = null;
    sync_local.mediaFiles = null;
    note_text.searchExtra = null;
    noteGoneForGood = null;
    pictureAdopted = null;
    attachmentKept = null;
  }

  final String dataDir;

  /// Whether the document scanner opens here, once the device has said (Google Play services): false until then.
  bool scans = false;

  /// Whether a file can be chosen here.
  bool get picks => device.picks;

  final AttachmentStore store;
  final ReadTexts texts;
  final DocumentDevice device;
  late final ReadPass pass;
  final Future<List<({String id, String body})>> Function() _bodies;
  final Stored? _kept;
  Stored get _store => _kept ?? stored;

  /// Where a thing lies on this device, or null where it is not here.
  Future<String?> pathOf(ReadThing thing) async {
    if (thing.picture) {
      if (!_pictureName.hasMatch(thing.name)) return null;
      final path = '$dataDir/images/${thing.name}';
      return await File(path).exists() ? path : null;
    }
    return (await store.fileOf(thing.name))?.path;
  }

  // ---- what the + brings in -----------------------------------------------------------------------------------

  /// A file chosen on the device and kept: null when none was chosen. Its words are read soon after, where it is a
  /// PDF or a picture. Throws a [StateError] with a sentence for the note.
  Future<KeptAttachment?> pick() async {
    final picked = await device.pick();
    if (picked == null) return null;
    final kept = await store.keep(AttachmentPath(picked.path, move: true), original: picked.name);
    pass.readSoon(ReadThing.file(kept.name));
    return kept;
  }

  /// A document scanned and kept as one PDF named for the moment ("Scan 2026-10-16 14.05.pdf"): null when the
  /// person left the scanner. The words are read from the scanner's own pictures of the pages, which are sharper
  /// than the PDF's, and kept as the PDF's; then those pictures go.
  Future<KeptAttachment?> scan({required String name}) async {
    final made = await device.scan();
    if (made == null) return null;
    final kept = await store.keep(AttachmentPath(made.pdf, move: true), original: name);
    unawaited(_readScan(kept, made.pages));
    return kept;
  }

  Future<void> _readScan(KeptAttachment kept, List<String> pages) async {
    try {
      if (pass.on && pages.isNotEmpty) {
        final words = <String>[];
        for (final page in pages) {
          final read = await device.read(page, pdf: false);
          words.add(read == null || read.isEmpty ? '' : read.first);
        }
        await texts.keep(ReadThing.file(kept.name), textOfPages(words));
      } else {
        pass.readSoon(ReadThing.file(kept.name));
      }
    } catch (failure) {
      debugPrint('[files] the scan was not read: $failure');
      pass.readSoon(ReadThing.file(kept.name));
    } finally {
      for (final page in pages) {
        try {
          await File(page).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
  }

  /// A picture just put in a note (the phone's picker, a paste): its words read soon.
  void pictureAdded(String name) => pass.readSoon(ReadThing.picture(name));

  /// The files a note deleted for good linked, removed where no other note links them, with their words.
  Future<void> noteDeleted(String body, {required String id}) async {
    if (attachmentNames(body).isEmpty) return;
    final gone = await store.forgetUnlinked(body, () async => [
          for (final note in await _bodies())
            if (note.id != id) note.body,
        ]);
    for (final name in gone) {
      await texts.forget(ReadThing.file(name));
    }
  }

  // ---- sync (MediaFiles) --------------------------------------------------------------------------------------

  @override
  Future<Uint8List?> read(FileKind kind, String name) async {
    if (kind == FileKind.attachment) return store.read(name);
    if (kind == FileKind.text) {
      final thing = ReadThing.ofKey(name);
      if (thing == null) return null;
      final words = await texts.readKept(thing);
      return words == null ? null : Uint8List.fromList(utf8.encode(words));
    }
    return null;
  }

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    if (kind == FileKind.attachment) return store.write(name, bytes);
    if (kind == FileKind.text) {
      final thing = ReadThing.ofKey(name);
      if (thing == null) throw StateError('That is not a picture or a file.');
      await texts.keep(thing, utf8.decode(bytes, allowMalformed: true));
    }
  }

  @override
  Future<int?> lengthOf(FileKind kind, String name) async {
    if (kind == FileKind.attachment) return store.sizeOf(name);
    if (kind == FileKind.text) {
      final thing = ReadThing.ofKey(name);
      if (thing == null) return null;
      final words = texts.loaded ? texts.wordsOf(thing) : await texts.readKept(thing);
      return words == null ? null : utf8.encode(words).length;
    }
    return null;
  }

  List<String> _owed() => _store.read<List<String>>(wordsOwedKey, const <String>[], (raw) => raw is List ? raw.whereType<String>().toList() : null);

  /// The notes [noteIds] owe the account's other devices their words.
  void owe(Iterable<String> noteIds) {
    final owed = <String>{..._owed(), ...noteIds};
    _store.write(wordsOwedKey, owed.toList());
  }

  @override
  List<String> owed() => _owed();

  @override
  void settled(String noteId) {
    final owed = _owed();
    if (!owed.contains(noteId)) return;
    _store.write(wordsOwedKey, <String>[for (final id in owed) if (id != noteId) id]);
  }

  /// What every file kept here takes, in bytes, and how many there are.
  Future<({int files, int bytes})> used() async {
    final all = await store.all();
    return (files: all.length, bytes: all.values.fold<int>(0, (sum, each) => sum + each));
  }
}
