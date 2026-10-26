/// Where the web build keeps what a phone keeps in files (docs/WEB.md): a few named shelves of text by key, and one
/// of bytes. In a browser it is IndexedDB (idb_shelf.dart), which outlives a reload, a restart and the tab, and is
/// the page's own: no other site reads it, and nothing of it leaves the browser but what sync seals and sends.
/// [MemoryShelf] is the same in memory, for the tests and for a browser that refuses storage (a private window
/// that will not open IndexedDB), where the page still works and keeps nothing.
library;

import 'dart:typed_data';

/// The shelves (IndexedDB's object stores) the web build keeps.
abstract final class Shelves {
  /// A note by id: the library's row, its file's words and its sidecar, as one JSON object (web_store.dart).
  static const String notes = 'notes';

  /// A note's versions file, by the note's id.
  static const String versions = 'versions';

  /// A command's write, kept for its undo (library/mutations.rs `command_mutations`), by its id.
  static const String mutations = 'mutations';

  /// A picture or a recording, by `<kind>/<name>`: bytes.
  static const String files = 'files';

  /// A team note's document, by `<account>/<note id>` (lib/team/docs.dart's files).
  static const String teamDocs = 'team';

  /// What the page has done once and must not do again: the old web app's notes carried in (web_carry.dart).
  static const String marks = 'marks';

  static const List<String> all = [notes, versions, mutations, files, teamDocs, marks];
}

/// A store of shelves. Every write is kept before its future completes; a read answers what the last write left.
abstract interface class Shelf {
  /// Every text on [shelf], by key.
  Future<Map<String, String>> texts(String shelf);

  Future<String?> text(String shelf, String key);

  /// Keeps [value] under [key]; null takes it off.
  Future<void> putText(String shelf, String key, String? value);

  Future<Uint8List?> bytes(String shelf, String key);

  /// Keeps [value] under [key]; null takes it off.
  Future<void> putBytes(String shelf, String key, Uint8List? value);

  /// Every key on [shelf].
  Future<List<String>> keys(String shelf);

  /// Everything on [shelf], gone.
  Future<void> clear(String shelf);
}

/// [Shelf] in memory.
class MemoryShelf implements Shelf {
  final Map<String, Map<String, Object>> _shelves = {};

  Map<String, Object> _on(String shelf) => _shelves.putIfAbsent(shelf, () => {});

  @override
  Future<Map<String, String>> texts(String shelf) async => {
    for (final MapEntry(:key, :value) in _on(shelf).entries)
      if (value is String) key: value,
  };

  @override
  Future<String?> text(String shelf, String key) async => _on(shelf)[key] as String?;

  @override
  Future<void> putText(String shelf, String key, String? value) async {
    if (value == null) {
      _on(shelf).remove(key);
    } else {
      _on(shelf)[key] = value;
    }
  }

  @override
  Future<Uint8List?> bytes(String shelf, String key) async => _on(shelf)[key] as Uint8List?;

  @override
  Future<void> putBytes(String shelf, String key, Uint8List? value) async {
    if (value == null) {
      _on(shelf).remove(key);
    } else {
      _on(shelf)[key] = Uint8List.fromList(value);
    }
  }

  @override
  Future<List<String>> keys(String shelf) async => _on(shelf).keys.toList();

  @override
  Future<void> clear(String shelf) async => _on(shelf).clear();
}
