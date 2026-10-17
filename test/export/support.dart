import 'dart:io';
import 'dart:typed_data';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/export/ghostex.dart';
import 'package:ghost_md/importer/ghostex.dart';

/// One device for a .ghostex to be written on or read into: a library in memory, its workspaces and trash, and its
/// pictures, files and recordings as real files under a folder of the test's, kept where the app keeps them by name.
class GhostexDevice {
  GhostexDevice({List<Note> notes = const [], WorkspaceSheet sheet = const WorkspaceSheet()})
      : library = SampleLibrary(notes),
        trash = MemoryTrash(),
        root = Directory.systemTemp.createTempSync('ghostex-') {
    workspaces = WorkspaceStore(storage: MemoryWorkspaceStorage(sheet), trash: trash);
  }

  final SampleLibrary library;
  final MemoryTrash trash;
  late final WorkspaceStore workspaces;
  final Directory root;
  var _ids = 0;

  String _in(String kind, String name) => '${root.path}/$kind/$name';

  void _put(String kind, String name, List<int> bytes) {
    final file = File(_in(kind, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  Uint8List? _read(String kind, String name) {
    final file = File(_in(kind, name));
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  void putPicture(String name, List<int> bytes) => _put('pictures', name, bytes);
  void putFile(String name, List<int> bytes) => _put('files', name, bytes);
  void putRecording(String id, List<int> bytes) => _put('recordings', id, bytes);

  Uint8List? picture(String name) => _read('pictures', name);
  Uint8List? file(String name) => _read('files', name);
  Uint8List? recording(String id) => _read('recordings', id);

  Future<String?> _where(String kind, String name) async => File(_in(kind, name)).existsSync() ? _in(kind, name) : null;

  GhostexSource source() => GhostexSource(
        library: library,
        workspaces: workspaces,
        picturePath: (name) => _where('pictures', name),
        filePath: (name) => _where('files', name),
        recordingPath: (id) => _where('recordings', id),
      );

  Future<void> _adopt(String kind, String name, String path) async {
    final to = File(_in(kind, name));
    await to.parent.create(recursive: true);
    await File(path).copy(to.path);
  }

  GhostexTarget target() => GhostexTarget(
        library: library,
        workspaces: workspaces,
        hasPicture: (name) async => File(_in('pictures', name)).existsSync(),
        keepPicture: (name, path) => _adopt('pictures', name, path),
        hasFile: (name) async => File(_in('files', name)).existsSync(),
        keepFile: (name, path) => _adopt('files', name, path),
        keepRecording: (id, path) => _adopt('recordings', id, path),
        temp: '${root.path}/temp',
        newId: () => 'copy-${++_ids}',
      );

  /// A path for a file of the test's own.
  String path(String name) => '${root.path}/$name';

  void dispose() {
    library.dispose();
    workspaces.dispose();
    root.deleteSync(recursive: true);
  }
}

/// The first bytes of each kind of file, so each is what its name says.
final List<int> jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];
final List<int> png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9];
final List<int> pdf = '%PDF-1.7 a lease'.codeUnits;
final List<int> wav = [...'RIFF'.codeUnits, 36, 0, 0, 0, ...'WAVE'.codeUnits, 7, 7, 7];

const String pictureA = '1b4e28ba-2fa1-11d2-883f-0016d3cca427.jpg';
const String pictureB = '2c5f39cb-3fb2-42e3-994f-1127e4ddb538.png';
const String fileA = '3d6a4adc-4ac3-43f4-a05a-2238f5eec649.pdf';

final int t0 = DateTime.utc(2026, 9, 1, 8, 30, 15, 123).millisecondsSinceEpoch;

/// A library with something of everything: notes in a workspace, a folder inside it, an organization's and none;
/// two of one title; a title no disk would hold; a notebook; a canvas with a picture card; an archived note, a
/// pinned one, a spoken one with its recording, and one in the trash.
GhostexDevice everything() {
  const sheet = WorkspaceSheet(
    list: [
      Workspace(id: 'w-work', name: 'Work', hue: 'sea'),
      Workspace(id: 'w-clients', name: 'Clients', parent: 'w-work'),
      Workspace(id: 'org-acme', name: 'Acme Team', hue: 'ember'),
      Workspace(id: 'w-empty', name: 'Nothing here'),
    ],
    notes: {'plan': 'w-work', 'acme': 'w-clients', 'team': 'org-acme', 'book': 'w-work', 'same2': 'w-work'},
  );
  final device = GhostexDevice(
    sheet: sheet,
    notes: [
      Note(id: 'plan', body: '---\ntags: [planning]\n---\n# Plan\n\nThe plan. #work\n\n![a photo](image/$pictureA)\n', createdAt: t0, updatedAt: t0 + 1000, starred: true),
      Note(id: 'acme', body: '# Acme\n\n[Lease.pdf](file/$fileA "16 bytes")\n', createdAt: t0 + 1, updatedAt: t0 + 2000),
      Note(id: 'team', body: '# Standup\n\nThe team’s notes.\n', createdAt: t0 + 2, updatedAt: t0 + 3000),
      Note(id: 'loose', body: '# Same\n\nOne of two.\n', createdAt: t0 + 3, updatedAt: t0 + 4000),
      Note(id: 'same2', body: '# Same\n\nThe other, in Work.\n', createdAt: t0 + 4, updatedAt: t0 + 5000),
      Note(id: 'same3', body: '# same\n\nThe same title, in lower case.\n', createdAt: t0 + 5, updatedAt: t0 + 6000),
      Note(id: 'unsafe', body: '# ../a/b:c*?"<>|\n\nA title no disk would hold.\n', createdAt: t0 + 6, updatedAt: t0 + 7000),
      Note(id: 'con', body: '# CON\n\nWindows’ own name.\n', createdAt: t0 + 7, updatedAt: t0 + 8000),
      Note(id: 'book', body: '---\nbook: true\n---\n# The Book\n\n- [[Plan]]\n- [[Acme]]\n', createdAt: t0 + 8, updatedAt: t0 + 9000),
      Note(
        id: 'canvas',
        body: '---\ntitle: "Board"\n---\n{"nodes":[{"id":"a","type":"file","x":0,"y":0,"width":10,"height":10,"file":"$pictureB"}],"edges":[]}\n',
        createdAt: t0 + 9,
        updatedAt: t0 + 10000,
      ),
      Note(id: 'old', body: '# Old\n\nPut away.\n', createdAt: t0 + 10, updatedAt: t0 + 11000, archivedAt: t0 + 12000),
      Note(
        id: 'spoken',
        body: '# Spoken\n\nHello there.\n',
        createdAt: t0 + 11,
        updatedAt: t0 + 13000,
        source: NoteSource.capture,
        recordingMs: 4200,
        segments: const [Segment(startMs: 0, endMs: 1500, text: 'Hello'), Segment(startMs: 1500, endMs: 4200, text: 'there.')],
      ),
      Note(id: 'binned', body: '# Binned\n\nIn the trash.\n', createdAt: t0 + 12, updatedAt: t0 + 14000),
    ],
  );
  device.trash.trashNote('binned');
  device.putPicture(pictureA, jpeg);
  device.putPicture(pictureB, png);
  device.putFile(fileA, pdf);
  device.putRecording('spoken', wav);
  return device;
}
