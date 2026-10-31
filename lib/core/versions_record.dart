/// A note's version history: which notes keep one, and keeping a version. A port of
/// `src/app/core/versions/record.ts`. (Matt: "add edit history timelines to notes that are in organizations by
/// default and allow versioning on personal notes by enabling it under the more menu. We should be able to revert
/// back to previous versions like git kinda".)
///
/// Which notes keep one: a note filed in an organization's workspace does, unless it is switched off; a note of the
/// person's own does once it is switched on from its More sheet. The choice is written into the note as
/// `versions: true|false` (docs/MARKDOWN_FIRST.md decision 6, 2026-10-31), so it travels with the file and a Library
/// folder restored on a fresh device keeps the histories it kept; the `versions` preference is written too, for the
/// builds before this, and read where the note says nothing. The preference never synced (lib/sync/prefs.dart lists
/// it nowhere), so until the key a personal note's history stopped on a person's second device; and a personal note
/// with a `.versions` file beside it and no word either way reads as on, since the file is the choice made.
///
/// When a version is kept: after a pause in the writing ([versionPause]), when the note is left, and by hand with a
/// name - never one of no change. Going back to a version keeps a new one with that version's words, as
/// `git revert` does, so the history only ever grows and a step back can itself be undone. Switching history on
/// keeps the note's words at once, so the file exists from that moment and another device sees the choice in the
/// folder before the key has synced.
///
/// What differs: the page's functions read the preferences, the workspaces, the account and the versions store as
/// modules; here they are a [VersionsRecord] made with those four, and with two ways to the note's words ([bodyOf] to
/// read the key, [change] to write it through the open editor where there is one, lib/root/root_commands.dart
/// `_changeNote`). Its hooks are a [Listenable] to rebuild by ([VersionsRecord.keeping]) and a stream of reads
/// ([VersionsRecord.watch]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'front_matter.dart' show frontMatterValue;
import 'preferences.dart';
import 'properties.dart' show withProperty;
import 'versions_file.dart';
import 'versions_store.dart';
import 'workspaces.dart';

/// The front matter key the choice is written under.
const String versionsKey = 'versions';

/// What a body says of its history: on, off, or nothing (`versions:` absent, or neither word).
bool? versionsSaidIn(String body) => switch (frontMatterValue(body, versionsKey)?.trim().toLowerCase()) { 'true' || 'yes' || 'on' => true, 'false' || 'no' || 'off' => false, _ => null };

/// How long the writing rests before what it wrote is kept as a version (`PAUSE_MS`).
const Duration versionPause = Duration(minutes: 2);

/// A note's versions, oldest first, and how many of the file's versions could not be read.
typedef VersionsRead = ({List<Version> versions, int damaged});

/// Which notes keep versions, and the keeping (`keepsVersions`, `setKeepsVersions`, `keepVersion`, `versionsOf`).
class VersionsRecord {
  /// [keeper] is who keeps a version here: the account's handle, or null without one, which is written `me`.
  /// [bodyOf] answers a note's words as the list holds them, for the `versions:` key; [change] writes a note's
  /// words through whatever holds them open. Without either, the record is the preferences' alone, as it was.
  VersionsRecord({required this.store, required this.preferences, required this.workspaces, String? Function()? keeper, String? Function(String id)? bodyOf, Future<void> Function(String id, String Function(String body) change)? change, void Function(String message)? log})
      : _keeper = keeper,
        _bodyOf = bodyOf,
        _change = change,
        _log = log ?? debugPrint;

  final VersionsStore store;
  final PreferencesStore preferences;
  final WorkspaceStore workspaces;
  final String? Function()? _keeper;
  final String? Function(String id)? _bodyOf;
  final Future<void> Function(String id, String Function(String body) change)? _change;
  final void Function(String message) _log;

  /// The notes known to have a versions file beside them: learnt as files are read and written here, and by
  /// [learnFiles] at open. A personal note among them with no word either way keeps versions.
  final Set<String> _filed = {};
  final _Files _files = _Files();

  /// Told when an answer of [keepsVersions] may have changed (`useKeepsVersions`).
  late final Listenable keeping = Listenable.merge([preferences, workspaces, _files]);

  /// Whether note [id] is an organization's, whose history is kept unless switched off (`versionsByDefault`).
  bool versionsByDefault(String id) {
    final space = workspaces.workspaceOf(id);
    return space != null && workspaces.orgOf(space.id) != null;
  }

  /// Whether note [id] keeps a version history (`keepsVersions`): as its words say (`versions: true|false`), else
  /// as the preferences say, else on for a personal note with a versions file beside it, else as its workspace says.
  bool keepsVersions(String id) {
    final body = _bodyOf?.call(id);
    final written = body == null ? null : versionsSaidIn(body);
    if (written != null) return written;
    final said = preferences.value.versions[id];
    if (said != null) return said;
    final byDefault = versionsByDefault(id);
    return byDefault || _filed.contains(id);
  }

  /// Switches note [id]'s history on or off (`setKeepsVersions`): written into the note, and into the preferences
  /// for the builds before the key. Its versions file stays either way: switched on again, it carries on; switched
  /// on, the words now are kept at once so the file is there.
  void setKeepsVersions(String id, bool on) {
    final versions = {...preferences.value.versions};
    // A choice that is what the note would do anyway is not kept: an organization's note on, a note of one's own off.
    // Unless a versions file sits beside the note, which would read as on: then off is a choice worth keeping.
    if (on == versionsByDefault(id) && !_filed.contains(id)) {
      versions.remove(id);
    } else {
      versions[id] = on;
    }
    preferences.update((now) => now.copyWith(versions: versions));
    // The words as they are before the key goes in: what the first version holds.
    final body = _bodyOf?.call(id);
    final change = _change;
    if (change != null) {
      unawaited(change(id, (body) => withProperty(body, versionsKey, on ? 'true' : 'false')).catchError((Object failure) => _log('[glyph] the versions key was not written: $failure')));
    }
    if (on && body != null && body.trim().isNotEmpty) {
      unawaited(keepVersion(id, body).then<void>((_) {}, onError: (Object failure) => _log('[glyph] the first version was not kept: $failure')));
    }
  }

  /// Learns which of [ids] have a versions file beside them, for [keepsVersions]: asked once as the library is
  /// opened, for the personal notes, so a restored library's histories carry on. A read that fails is no file.
  Future<void> learnFiles(Iterable<String> ids) async {
    var learnt = false;
    for (final id in ids) {
      if (_filed.contains(id)) continue;
      try {
        final file = await store.readVersionsFile(id);
        if (file != null && file.isNotEmpty) learnt = _filed.add(id) || learnt;
      } catch (_) {
        // No file, or none that can be read now.
      }
    }
    if (learnt) _files.tell();
  }

  /// Whether a versions file is known to sit beside note [id].
  bool hasFile(String id) => _filed.contains(id);

  /// One write at a time per note, so two versions kept close together do not each read the file before the other
  /// wrote it.
  final Map<String, Future<void>> _writing = {};

  Future<T> _inTurn<T>(String id, Future<T> Function() work) {
    final before = _writing[id] ?? Future<void>.value();
    final next = before.then((_) => work());
    late final Future<void> settled;
    settled = next.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_writing[id], settled)) _writing.remove(id);
    });
    _writing[id] = settled;
    return next;
  }

  /// Keeps [text] as a version of note [id], named [label] if given, answering whether one was kept: not when the
  /// last version already holds this text and no name is being given (`keepVersion`). [now] is the time, in ms.
  Future<bool> keepVersion(String id, String text, {String? label, int? now}) => _inTurn(id, () async {
        final file = await store.readVersionsFile(id);
        final by = _keeper?.call();
        final next = withVersion(file, id, text, at: now ?? DateTime.now().millisecondsSinceEpoch, by: by == null || by.isEmpty ? 'me' : by, label: label);
        if (next == null) return false;
        await store.writeVersionsFile(id, next);
        if (_filed.add(id)) _files.tell();
        return true;
      });

  /// Note [id]'s versions, oldest first, and how many of the file's versions could not be read (`versionsOf`).
  Future<VersionsRead> versionsOf(String id) async {
    final file = await store.readVersionsFile(id);
    final read = file != null && file.isNotEmpty ? readFile(file) : null;
    if (read != null && _filed.add(id)) _files.tell();
    return (versions: read?.versions ?? const <Version>[], damaged: read?.damaged ?? 0);
  }

  /// Note [id]'s versions, read now and again whenever its file changes here (`useVersions`). A read that fails is
  /// no versions.
  Stream<VersionsRead> watch(String id) {
    late final StreamController<VersionsRead> out;
    StreamSubscription<String>? changes;
    Future<void> load() async {
      VersionsRead read;
      try {
        read = await versionsOf(id);
      } catch (_) {
        read = (versions: const <Version>[], damaged: 0);
      }
      if (!out.isClosed) out.add(read);
    }

    out = StreamController<VersionsRead>(
      onListen: () {
        changes = store.changed.where((changed) => changed == id).listen((_) => unawaited(load()));
        unawaited(load());
      },
      onCancel: () async {
        await changes?.cancel();
        await out.close();
      },
    );
    return out.stream;
  }
}

/// The notifier behind [VersionsRecord.keeping] for the files learnt: a [ChangeNotifier] the record may tell.
class _Files extends ChangeNotifier {
  void tell() => notifyListeners();
}
