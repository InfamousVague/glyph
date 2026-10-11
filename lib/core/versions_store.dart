/// Where a note's versions file is kept. A port of `src/app/core/versions/store.ts`.
///
/// The file (core/versions/file.ts, which comes with the versions themselves) is `<Title>.versions` beside the note
/// in its library folder, read and written by the core's `versions_read {id}` and `versions_write {id, text}`
/// (src-tauri/src/library/versions.rs). Where there is no core, the app keeps the file itself under
/// `glyph-versions-<id>`, and moves it beside its note the first time it is read with one, so a history begun
/// without a library is not lost when there is one.
///
/// A file written here is owed to the account until sync has sent it ([VersionsStore.unsentVersions], kept under
/// `glyph-versions-unsent`), so a version kept by hand, with no change to the note's words, still travels.
///
/// What differs: the web asks whether the binary is new enough for the two commands (`VERSIONS_GENERATION`, native
/// generation 24) before it calls them; this app's core always has them, so the only question is whether there is a
/// core at all (a null `invoke` is the browser's case). `VERSIONS_CHANGED`, an event on the window with the note's
/// id, is [VersionsStore.changed].
library;

import 'dart:async';

import 'native/core.dart';
import 'stored.dart';

/// Native generation with `versions_read` and `versions_write` (`VERSIONS_GENERATION`): said for the record, since
/// nothing here has to ask.
const int versionsGeneration = 24;

const String _unsentKey = 'glyph-versions-unsent';

/// The key the app keeps note [id]'s versions file under where the library cannot.
String versionsKey(String id) => 'glyph-versions-$id';

/// Notes' versions files, beside the notes or on the device (`readVersionsFile`, `writeVersionsFile`,
/// `unsentVersions`, `sentVersions`).
class VersionsStore {
  /// [invoke] is the core, or null where there is none; [kept] this device's memory, the app's own unless given.
  VersionsStore(this._invoke, {Stored? kept}) : _kept = kept;

  final CoreInvoke? _invoke;
  final Stored? _kept;
  Stored get _device => _kept ?? stored;

  final StreamController<String> _changed = StreamController<String>.broadcast(sync: true);

  /// Heard when a note's versions file changes here, by sync or by a version kept: the note's id
  /// (`VERSIONS_CHANGED`).
  Stream<String> get changed => _changed.stream;

  /// Note [id]'s versions file, or null where it has none.
  Future<String?> readVersionsFile(String id) async {
    final local = _device.readText(versionsKey(id));
    final invoke = _invoke;
    if (invoke == null) return local;
    final answer = await invoke('versions_read', {'id': id});
    final beside = answer is String ? answer : null;
    if (beside == null && local != null && local.isNotEmpty) {
      // Kept by the app before there was a library to keep it beside the note: moved there now, and forgotten here.
      if (await invoke('versions_write', {'id': id, 'text': local}) == true) _device.writeText(versionsKey(id), null);
      return local;
    }
    return beside;
  }

  /// Keeps [text] as note [id]'s versions file. [owed] (the default) marks it for the next sync to send.
  Future<void> writeVersionsFile(String id, String text, {bool owed = true}) async {
    final invoke = _invoke;
    final beside = invoke != null && await invoke('versions_write', {'id': id, 'text': text}) == true;
    // No note to keep it beside, or no library that can: the app keeps it.
    if (!beside) _device.writeText(versionsKey(id), text);
    if (owed) _owe(id);
    if (!_changed.isClosed) _changed.add(id);
  }

  // ---- what sync owes the account ---------------------------------------------------------------------------------

  List<String> _unsent() => _device.read<List<String>>(_unsentKey, const [], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : const []);

  void _owe(String id) {
    final now = _unsent();
    if (!now.contains(id)) _device.write(_unsentKey, [...now, id]);
  }

  /// The notes whose versions file changed here since sync last sent it.
  List<String> unsentVersions() => _unsent();

  /// Note [id]'s versions file is with the account now.
  void sentVersions(String id) {
    final now = _unsent();
    if (now.contains(id)) _device.write(_unsentKey, [for (final each in now) if (each != id) each]);
  }

  /// Nobody is listening any more.
  void dispose() => unawaited(_changed.close());
}
