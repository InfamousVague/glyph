import 'package:flutter/foundation.dart';

import 'visited.dart';

/// Where he has been, and the arrows that walk it: the web app's shell/useTrail.ts, drawn in the tab bar.
///
/// The trail records arriving somewhere rather than every way of getting there, so it does not matter which of the
/// many paths into a note was taken. The arrows only say where to go ([back], [on]); the shell does the going, as it
/// does for every other way of moving. A step is not itself recorded as somewhere new: it moves the trail to where
/// it lands before the screen gets there, and arriving where the trail already stands changes nothing.
///
/// Differs from the web: a hook took the screen's place and the live ids on every render; here the shell says them
/// as they change ([arrive], [live]), and this tells its listeners when the arrows' answers may have.
class TrailController extends ChangeNotifier {
  TrailController({Set<String> live = const {}}) : _live = live;

  Trail _trail = Trail.first;
  Set<String> _live;

  /// The trail itself, for whatever must follow it changing.
  Trail get trail => _trail;

  /// The ids of the notes that can still be seen: a place whose note is not among them is stepped over.
  Set<String> get live => _live;
  set live(Set<String> ids) {
    if (setEquals(ids, _live)) return;
    _live = ids;
    notifyListeners();
  }

  /// Where the screen is now (shell/screen.dart `Screen.place`), or null for a screen that is no place: a capture
  /// and the Academy leave the trail where it was.
  void arrive(Place? place) {
    if (place == null) return;
    final next = _trail.went(place);
    if (identical(next, _trail)) return;
    _trail = next;
    notifyListeners();
  }

  /// A place worth landing on: the list and the grid always, a note only while it can still be seen.
  bool stillThere(Place spot) {
    final id = noteIdOf(spot);
    return id == null || _live.contains(id);
  }

  bool get canBack => _trail.canGoBack(stillThere);
  bool get canOn => _trail.canGoOn(stillThere);

  Place? _step(Trail? next) {
    final spot = next?.place;
    if (next == null || spot == null) return null;
    _trail = next;
    notifyListeners();
    return spot;
  }

  /// One step back: answers the place to go to, or null when there is nowhere.
  Place? back() => _step(_trail.backFrom(stillThere));

  /// One step forward again: answers the place to go to, or null when there is nowhere.
  Place? on() => _step(_trail.onFrom(stillThere));
}
