/// The trash as the preference it is on the web: [Trash] over the preferences' `trash` field. A port of the kept half
/// of `src/app/core/trash.ts` (`trash`, `isTrashed`, `trashNote`, `restoreNote`, `forget`, `useTrash`), which reads
/// and writes `preferences().trash`, `{note id: when it went in}`.
///
/// Kept as a preference the way the workspaces are (lib/core/kept_workspaces.dart), and for the web's reason: the
/// notes are the Rust core's, a preference syncs, so a note put in the trash on the phone is in the trash on the Mac
/// too. The note itself is untouched until the trash is emptied; only then is it deleted from the library
/// ([NoteLibrary.destroy], lib/core/library.dart).
///
/// What differs: the web's `useTrash` hears every change to the preferences and hands React the same map while the
/// trash has not changed; here a listener is told only when the trash itself did. The times are whole milliseconds
/// ([TrashHeld]); a time another build kept with a fraction is read without it.
library;

import 'package:flutter/foundation.dart';

import 'preferences.dart';
import 'trash.dart';

/// [Trash] kept in the preferences ([prefs], the app's own unless a test hands in another).
class KeptTrash extends ChangeNotifier implements Trash {
  KeptTrash({PreferencesStore? prefs, int Function()? clock})
      : _prefs = prefs ?? preferences,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _from = _prefs.value.trash;
    _held = _read(_from);
    _prefs.addListener(_heard);
  }

  final PreferencesStore _prefs;
  final int Function() _clock;

  /// The preference the held map was read from, to tell a change to the trash from a change to anything else.
  late Map<String, num> _from;
  late TrashHeld _held;

  static TrashHeld _read(Map<String, num> kept) => Map.unmodifiable({for (final entry in kept.entries) entry.key: entry.value.toInt()});

  void _heard() {
    final now = _prefs.value.trash;
    if (identical(now, _from) || mapEquals(now, _from)) return;
    _from = now;
    _held = _read(now);
    notifyListeners();
  }

  /// `trash()`.
  @override
  TrashHeld get value => _held;

  @override
  bool isTrashed(String id) => _prefs.value.trash.containsKey(id);

  @override
  void trashNote(String id, [int? now]) => _prefs.update((prefs) => prefs.copyWith(trash: {...prefs.trash, id: now ?? _clock()}));

  @override
  void restoreNote(String id) => forget([id]);

  @override
  void forget(Iterable<String> ids) {
    final held = _prefs.value.trash;
    if (!ids.any(held.containsKey)) return;
    final next = {...held};
    ids.forEach(next.remove);
    _prefs.update((prefs) => prefs.copyWith(trash: next));
  }

  @override
  void dispose() {
    _prefs.removeListener(_heard);
    super.dispose();
  }
}
