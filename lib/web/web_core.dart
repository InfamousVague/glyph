/// The web build's core (docs/WEB.md): one [CoreInvoke] over two halves, so everything written against the phone's
/// core takes it unchanged.
///
/// - **The library** is the page's (web_store.dart): the notes, their versions and commands, the pictures.
/// - **Everything else** goes to the worker (web/core/ghost_core_worker.js), which is native/'s own crypto.rs,
///   crdt.rs and names.rs compiled to WebAssembly: a key, a seal, a team document, an id. A command neither half
///   has (a model, a recording, a backup, a folder of the person's) is the worker's refusal, a [CoreError] like any
///   the phone's core gives for a command its build was made without, and the screen that asked says so.
library;

import 'dart:convert';

import '../core/native/core.dart';
import '../team/docs.dart' show TeamDocRecord, TeamDocStore;
import 'shelf.dart';
import 'web_store.dart';

class WebCore {
  WebCore(this.store, this.worker);

  final WebStore store;

  /// The browser's core in its worker.
  final CoreInvoke worker;

  /// Asks the page's library or the worker, by the command.
  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) {
    if (webStoreCommands.contains(command)) return store.call(command, args);
    return worker(command, args);
  }
}

/// The team notes' documents of one account on the page's shelf: what lib/team/docs.dart's `FileDocs` keeps in
/// `<dataDir>/team/<account>`.
class ShelfTeamDocs implements TeamDocStore {
  const ShelfTeamDocs(this._shelf, this._accountId);

  final Shelf _shelf;
  final int _accountId;

  String _key(String noteId) => '$_accountId/$noteId';

  @override
  Future<TeamDocRecord?> read(String noteId) async {
    final text = await _shelf.text(Shelves.teamDocs, _key(noteId));
    if (text == null) return null;
    try {
      return TeamDocRecord.fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String noteId, TeamDocRecord record) => _shelf.putText(Shelves.teamDocs, _key(noteId), jsonEncode(record.toJson()));

  @override
  Future<void> remove(String noteId) => _shelf.putText(Shelves.teamDocs, _key(noteId), null);
}

/// The old web app's notes, carried into the page's library the first time this build opens where that app was
/// (attack.fm/glyph, the same address): its `glyph-notes` in this site's `localStorage`, each note as that app's
/// `store.ts` kept it, which is the library's own shape. Applied as sync applies a note, with its own times, so
/// nothing a person wrote in the old page is lost when the new one takes its place; and only once, so a note
/// deleted here does not come back. The old page's keys were WebCrypto's and cannot be carried: a person signed in
/// there signs in again, and sync brings the rest. Answers how many were carried.
Future<int> carryOldPage(WebStore store, Shelf shelf, String? oldNotes) async {
  const mark = 'carried-old-page';
  if (await shelf.text(Shelves.marks, mark) != null) return 0;
  var carried = 0;
  if (oldNotes != null && oldNotes.isNotEmpty) {
    try {
      final notes = jsonDecode(oldNotes);
      if (notes is List) {
        for (final note in notes) {
          if (note is! Map || note['id'] is! String || note['body'] is! String) continue;
          if (await store.call('get_note', {'id': note['id']}) != null) continue;
          await store.call('store_apply', {'note': note.cast<String, Object?>()});
          carried += 1;
        }
      }
    } catch (_) {
      // What the old page left that will not read is left where it is, in its own storage.
    }
  }
  await shelf.putText(Shelves.marks, mark, '$carried');
  return carried;
}
