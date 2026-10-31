import 'package:flutter/foundation.dart';

import '../core/note.dart';

/// The library as every screen sees it, which is not the library as the store has it (`VisibleNotes`,
/// shell/useVisibleNotes.ts).
@immutable
class VisibleNotes {
  const VisibleNotes({required this.visible, required this.trashed, required this.live});

  /// Every note a screen may show: not hidden by a pending delete, not in the trash.
  final List<Note> visible;

  /// The notes in the trash, the most recently thrown away first, for its folder in the tree.
  final List<Note> trashed;

  /// [visible]'s ids: what a tab, a place on the trail or a link can still land on.
  final Set<String> live;
}

/// The notes a screen may show (`useVisibleNotes`, with `outOfTrash` and `inTrash` of core/trash.ts): [notes] as the
/// store has them, less the ids a pending delete is holding back ([hidden]), less the ones in the trash ([trash],
/// each id with when it was thrown away).
///
/// Differs from the web: the trash was read from the preferences by a hook; here it is handed in, the preferences
/// being another module's.
VisibleNotes visibleNotes(List<Note> notes, {Set<String> hidden = const {}, Map<String, int> trash = const {}}) {
  final kept = hidden.isEmpty ? notes : [for (final n in notes) if (!hidden.contains(n.id)) n];
  // In the trash by the map, or by its file being under `.trash/` (lib/core/trash.dart `trashedNote`): a note whose
  // file is there is never shown live while the map catches up with it.
  final visible = [for (final n in kept) if (!trash.containsKey(n.id) && !n.inTrash) n];
  final trashed = [for (final n in kept) if (trash.containsKey(n.id) || n.inTrash) n]..sort((a, b) => (trash[b.id] ?? 0).compareTo(trash[a.id] ?? 0));
  return VisibleNotes(visible: List.unmodifiable(visible), trashed: List.unmodifiable(trashed), live: Set.unmodifiable({for (final n in visible) n.id}));
}
