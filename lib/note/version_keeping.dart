/// When the open note keeps a version (lib/core/versions_record.dart). A port of
/// `src/app/editor/useVersionKeeping.ts`.
///
/// After the writing rests for [versionPause], when the note is left (closed, or the app put away), and once as the
/// history begins: the note as it was when it was switched on or opened, so the first change has something to go
/// back to. A version of no change is never kept, so the pauses and the leavings of a note nobody typed in cost
/// nothing.
///
/// What differs: the hook is an object the screen makes and disposes of. `body` is asked for when a version is
/// kept; [changed] is called with each change the editor makes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/versions_record.dart';

class VersionKeeping extends ChangeNotifier {
  VersionKeeping(this.record, this.noteId, this.body, {Duration pause = versionPause, bool lifecycle = true}) : _pause = pause {
    _keeps = record.keepsVersions(noteId);
    record.keeping.addListener(_asked);
    if (lifecycle) _hides = AppLifecycleListener(onHide: keepNow, onPause: keepNow, onDetach: keepNow);
    if (_keeps) _begin();
  }

  final VersionsRecord record;
  final String noteId;

  /// The live words (lib/core/library.dart `NoteSaving.body`).
  final String Function() body;
  final Duration _pause;
  AppLifecycleListener? _hides;
  Timer? _timer;
  late bool _keeps;

  /// Whether there are words since the last version kept, so a leaving with none reads nothing.
  bool _dirty = false;

  /// Whether the note keeps a history now (`useKeepsVersions`).
  bool get keeps => _keeps;

  void _asked() {
    final now = record.keepsVersions(noteId);
    if (now == _keeps) return;
    _keeps = now;
    if (now) _begin();
    notifyListeners();
  }

  /// Begun, or opened with a history: the words as they are now are the version the first change goes back from.
  void _begin() => unawaited(record.keepVersion(noteId, body()).then<void>((_) {}, onError: (Object _) {}));

  /// Keeps a version now, if anything was written since the last.
  void keepNow() {
    _timer?.cancel();
    _timer = null;
    if (!_keeps || !_dirty) return;
    _dirty = false;
    unawaited(record.keepVersion(noteId, body()).then<void>((_) {}, onError: (Object _) {}));
  }

  /// The editor's words changed.
  void changed() {
    if (!_keeps) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(_pause, keepNow);
  }

  /// Left: the closing of the note.
  @override
  void dispose() {
    keepNow();
    record.keeping.removeListener(_asked);
    _hides?.dispose();
    super.dispose();
  }
}
