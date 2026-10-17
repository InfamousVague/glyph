import 'package:ghost_md/reminders/place_host.dart';
import 'package:ghost_md/reminders/place_plan.dart';

/// The phone, as place reminders ask it (lib/reminders/place_host.dart): keeps every set it is handed, answers the
/// permission as the test sets it, and moves it along as the test says each prompt is answered.
class FakePlaces implements PlaceHost {
  final List<List<PlaceReminder>> sets = [];
  int clears = 0;
  bool takes = true;
  PlaceAccess? now = PlaceAccess.always;

  /// What Android's prompts leave the access at, once answered.
  PlaceAccess afterForeground = PlaceAccess.whileUsing;
  PlaceAccess afterBackground = PlaceAccess.always;
  LatLon? where;

  /// What was asked, in order: `foreground`, `background`, `lastKnown`, `settings`.
  final List<String> asked = [];

  /// What the last set handed over says, as `words @ place`; empty after a clear.
  List<String> get last => [for (final place in (lastWasClear ? const <PlaceReminder>[] : sets.last)) '${place.words} @ ${place.place}'];
  bool lastWasClear = false;

  @override
  Future<bool> set(List<PlaceReminder> places) async {
    sets.add(places);
    lastWasClear = false;
    return takes;
  }

  @override
  Future<bool> clear() async {
    clears += 1;
    lastWasClear = true;
    return takes;
  }

  @override
  Future<PlaceAccess?> access() async => now;

  @override
  Future<PlaceAccess> askForeground() async {
    asked.add('foreground');
    return now = afterForeground;
  }

  @override
  Future<PlaceAccess> askBackground() async {
    asked.add('background');
    return now = afterBackground;
  }

  @override
  Future<LatLon?> lastKnown() async {
    asked.add('lastKnown');
    return where;
  }

  @override
  Future<bool> openSettings() async {
    asked.add('settings');
    return true;
  }
}
