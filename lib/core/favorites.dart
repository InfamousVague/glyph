/// Favorites: the pages a person keeps at the top of the sidebar (docs/TEAMSPACES.md; Matt, 2026-10-31, his choice
/// for the sidebar: "A space switcher at the top ... then sections: Favorites, Teamspace (the organization's pages) or
/// Private (your own), Shared with me").
///
/// **Where they are kept.** A favorite is one person's bookkeeping, not something the library says
/// (docs/MARKDOWN_FIRST.md §1, and TEAMSPACES.md: "what is one person's (favorites, folds, which space is chosen)
/// lives in their synced settings or on the device"): a team page Ana keeps at hand is not one Sam must see, so no
/// front matter is written. They follow the account to every device (lib/sync/prefs.dart `syncedPrefs`) under
/// [favoritesKey], as note ids in the order the sidebar lists them:
///
///     "favorites": ["n-k3f9x2", "n-0a1b2c"]
///
/// The typed [Preferences] has no field of its own for it: it rides in [Preferences.more] as the smart notebooks do
/// (lib/core/smart_notebooks.dart), so the shared class is untouched and a build from before this keeps the list when
/// it writes its settings back. An id whose note is gone is kept until it is unfavorited: a note trashed on one device
/// and restored comes back a favorite, and the sidebar draws only the ones it has.
library;

import 'preferences.dart';

/// The preference the favorites are kept under.
const String favoritesKey = 'favorites';

/// The note ids [prefs] keeps as favorites, in order, each once; anything but a list of words is none.
List<String> favoritesIn(Preferences prefs) {
  final raw = prefs.more[favoritesKey];
  if (raw is! List) return const [];
  final seen = <String>{};
  return List.unmodifiable([
    for (final each in raw)
      if (each is String && each.isNotEmpty && seen.add(each)) each,
  ]);
}

/// [prefs] with [noteId] a favorite ([on], last in the list) or not; the same preferences where nothing changes. The
/// key is taken off once the list is empty, so a person who never favorited anything keeps the stored shape.
Preferences withFavorite(Preferences prefs, String noteId, bool on) {
  final now = favoritesIn(prefs);
  if (now.contains(noteId) == on) return prefs;
  final next = on ? [...now, noteId] : [for (final id in now) if (id != noteId) id];
  final more = {...prefs.more};
  if (next.isEmpty) {
    more.remove(favoritesKey);
  } else {
    more[favoritesKey] = next;
  }
  return prefs.copyWith(more: more);
}
