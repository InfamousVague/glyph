import 'package:flutter/foundation.dart';

// Where a person has been, so the arrows in the app's tab bar can go back and forward through it: the web app's
// notes/visited.ts, whose rules these are. shell/trail.dart holds a trail and does the walking.
//
// A trail of places, and where along it we are now. It behaves the way a browser's arrows do: going somewhere new
// after going back forgets what was ahead. Notes get deleted, so a step skips any place that is no longer there
// rather than landing on nothing.

/// A place: `'list'` (the home page), `'notes'` (the All notes grid), or a note by id (`'note:<id>'`).
typedef Place = String;

/// The home page.
const Place homePlace = 'list';

/// The All notes page (`ALL_NOTES`): a place like the list, since the tab row is on it and the arrows should reach it.
const Place allNotesPlace = 'notes';

/// As many places as anyone will step through by hand (`MOST_PLACES`); older ones fall off the start.
const int mostPlaces = 30;

Place notePlace(String id) => 'note:$id';

/// The note a place is, or null for the home page and the grid.
String? noteIdOf(Place place) => place.startsWith('note:') ? place.substring(5) : null;

/// A trail of places, and where along it we are now (`Trail`, notes/visited.ts).
///
/// Differs from the web: `placeAt(trail)` is [place], `went(trail, place)` is [went], and `backFrom`, `onFrom`,
/// `canGoBack` and `canGoOn` are methods, so none of them stands beside notes/tabDrag.ts's `placeAt` as a second
/// function of that name.
@immutable
class Trail {
  const Trail(this.places, this.at);

  /// `FIRST`: on the home page, with nowhere to go.
  static const Trail first = Trail([homePlace], 0);

  final List<Place> places;

  /// Where along [places] we are now.
  final int at;

  /// Where the trail stands, or null for an empty one.
  Place? get place => at >= 0 && at < places.length ? places[at] : null;

  /// Somewhere new: it goes after where we are, and anything that was ahead is forgotten. Arriving where you already
  /// are changes nothing, and answers this same trail.
  Trail went(Place to) {
    if (place == to) return this;
    final next = [...places.take(at + 1), to];
    final kept = next.length > mostPlaces ? next.sublist(next.length - mostPlaces) : next;
    return Trail(List.unmodifiable(kept), kept.length - 1);
  }

  /// The nearest place before this one that is still there, or null when there is none.
  Trail? backFrom(bool Function(Place place) there) {
    for (var i = at - 1; i >= 0; i--) {
      if (i < places.length && there(places[i])) return Trail(places, i);
    }
    return null;
  }

  /// The nearest place after this one that is still there, or null when there is none.
  Trail? onFrom(bool Function(Place place) there) {
    for (var i = at + 1; i < places.length; i++) {
      if (there(places[i])) return Trail(places, i);
    }
    return null;
  }

  /// Whether the arrows can do anything, for drawing them live or dead.
  bool canGoBack(bool Function(Place place) there) => backFrom(there) != null;
  bool canGoOn(bool Function(Place place) there) => onFrom(there) != null;

  @override
  bool operator ==(Object other) => other is Trail && other.at == at && listEquals(other.places, places);

  @override
  int get hashCode => Object.hash(at, Object.hashAll(places));

  @override
  String toString() => 'Trail($places, at $at)';
}
