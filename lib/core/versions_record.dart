/// A note's version history: which notes keep one, and keeping a version. A port of
/// `src/app/core/versions/record.ts`. (Matt: "add edit history timelines to notes that are in organizations by
/// default and allow versioning on personal notes by enabling it under the more menu. We should be able to revert
/// back to previous versions like git kinda".)
///
/// Which notes keep one: a note filed in an organization's workspace does, unless it is switched off; a note of the
/// person's own does once it is switched on from its More sheet. Both are the `versions` preference, so the choice
/// travels with the person.
///
/// When a version is kept: after a pause in the writing ([versionPause]), when the note is left, and by hand with a
/// name - never one of no change. Going back to a version keeps a new one with that version's words, as
/// `git revert` does, so the history only ever grows and a step back can itself be undone.
///
/// What differs: the page's functions read the preferences, the workspaces, the account and the versions store as
/// modules; here they are a [VersionsRecord] made with those four. Its hooks are a [Listenable] to rebuild by
/// ([VersionsRecord.keeping]) and a stream of reads ([VersionsRecord.watch]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'preferences.dart';
import 'versions_file.dart';
import 'versions_store.dart';
import 'workspaces.dart';

/// How long the writing rests before what it wrote is kept as a version (`PAUSE_MS`).
const Duration versionPause = Duration(minutes: 2);

/// A note's versions, oldest first, and how many of the file's versions could not be read.
typedef VersionsRead = ({List<Version> versions, int damaged});

/// Which notes keep versions, and the keeping (`keepsVersions`, `setKeepsVersions`, `keepVersion`, `versionsOf`).
class VersionsRecord {
  /// [keeper] is who keeps a version here: the account's handle, or null without one, which is written `me`.
  VersionsRecord({required this.store, required this.preferences, required this.workspaces, String? Function()? keeper}) : _keeper = keeper;

  final VersionsStore store;
  final PreferencesStore preferences;
  final WorkspaceStore workspaces;
  final String? Function()? _keeper;

  /// Told when an answer of [keepsVersions] may have changed (`useKeepsVersions`).
  late final Listenable keeping = Listenable.merge([preferences, workspaces]);

  /// Whether note [id] is an organization's, whose history is kept unless switched off (`versionsByDefault`).
  bool versionsByDefault(String id) {
    final space = workspaces.workspaceOf(id);
    return space != null && isOrgWorkspace(space.id);
  }

  /// Whether note [id] keeps a version history, as the preferences and its workspace say now (`keepsVersions`).
  bool keepsVersions(String id) {
    final said = preferences.value.versions[id];
    return versionsByDefault(id) ? said != false : said == true;
  }

  /// Switches note [id]'s history on or off (`setKeepsVersions`). Its versions file stays either way: switched on
  /// again, it carries on.
  void setKeepsVersions(String id, bool on) {
    final versions = {...preferences.value.versions};
    // A choice that is what the note would do anyway is not kept: an organization's note on, a note of one's own off.
    if (on == versionsByDefault(id)) {
      versions.remove(id);
    } else {
      versions[id] = on;
    }
    preferences.update((now) => now.copyWith(versions: versions));
  }

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
        return true;
      });

  /// Note [id]'s versions, oldest first, and how many of the file's versions could not be read (`versionsOf`).
  Future<VersionsRead> versionsOf(String id) async {
    final file = await store.readVersionsFile(id);
    final read = file != null && file.isNotEmpty ? readFile(file) : null;
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
