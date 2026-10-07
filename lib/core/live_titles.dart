import 'package:flutter/foundation.dart';

/// One open note's title as its editor has it, and when it was said (`LiveTitle`, core/liveTitles.ts).
@immutable
class LiveTitle {
  const LiveTitle(this.title, this.at);
  final String title;

  /// Milliseconds since the epoch.
  final int at;
}

/// The title each open note has now, as its editor has it: what its tab says (core/liveTitles.ts; docs/DESIGN.md
/// §144). A tab is drawn from the shell's list of notes, which is read again when the store says the notes changed
/// and not on the editor's own saves, so the note screen says its title here as line 1 changes and the tab row
/// listens.
///
/// Differs from the web: that was a module's own store read through `useSyncExternalStore`; this is a
/// [ChangeNotifier] with one instance for the app ([liveTitles]), and a test may make its own.
class LiveTitles extends ChangeNotifier {
  Map<String, LiveTitle> _titles = const {};

  /// Every open note's title as its editor has it, for the tab row.
  Map<String, LiveTitle> get titles => _titles;

  /// The note's title as its editor has it now (`setLiveTitle`).
  void set(String id, String title, {int? at}) {
    if (_titles[id]?.title == title) return;
    _titles = Map.unmodifiable({..._titles, id: LiveTitle(title, at ?? DateTime.now().millisecondsSinceEpoch)});
    notifyListeners();
  }

  /// Forgets the notes whose tabs closed (`dropLiveTitles`).
  void drop(Iterable<String> ids) {
    if (!ids.any(_titles.containsKey)) return;
    _titles = Map.unmodifiable({..._titles}..removeWhere((id, _) => ids.contains(id)));
    notifyListeners();
  }

  /// The title a tab shows for a note (`titleNow`): its editor's, while that is newer than the note as the shell has
  /// it, else the note's own, so a rename that arrives by sync afterwards wins.
  String titleNow(String id, int updatedAt, String stored) {
    final said = _titles[id];
    return said != null && said.at >= updatedAt ? said.title : stored;
  }
}

/// The app's one store of live titles.
final LiveTitles liveTitles = LiveTitles();
