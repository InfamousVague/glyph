/// Place reminders kept in step with the notes, as reminder_scheduler.dart keeps the times: a pass reads the library
/// as it is (each note's places kept by the note object: place_plan.dart [PlacedItems]), and hands the phone the
/// whole set only when it is another than the last one handed over. The passes are lib/root/phone_extras.dart's, a
/// moment after the notes, the Trash, the settings or the plugins' switches last changed, a sync's notes included.
///
/// Nothing is watched with the Place reminders plugin off (lib/plugins/places) or Remind me off: the phone is told to
/// clear them, so switching the plugin off lets every geofence go.
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import 'place_host.dart';
import 'place_plan.dart';
import 'reminder_settings.dart';

class PlaceScheduler {
  PlaceScheduler({required this.host, required this.on, required this.reminders});

  final PlaceHost host;

  /// Whether the plugin is switched on, asked at each pass.
  final bool Function() on;
  final ValueListenable<ReminderSettings> reminders;

  /// The set last handed over, as it was handed; null before the first, and after one the phone did not take.
  String? _sent;

  /// The set the last pass made.
  List<PlaceReminder> plan = const [];

  /// Whether places are watched at all now.
  bool get watching => reminders.value.on && on();

  /// One pass over [notes], [skip] leaving out what the Trash holds. True where the phone was handed a new set.
  Future<bool> pass(List<Note> notes, {bool Function(Note note)? skip}) async {
    final all = watching ? placesIn(notes, skip: skip) : const <PlaceReminder>[];
    // Where the phone was is asked only when there are more than it can hold.
    final near = all.length > mostPlaces ? await host.lastKnown() : null;
    final made = nearestPlaces(all, near: near);
    plan = made;
    final json = placesJson(made);
    if (json == _sent) return false;
    _sent = json;
    final taken = made.isEmpty ? await host.clear() : await host.set(made);
    if (!taken && _sent == json) _sent = null;
    return taken;
  }

  /// The next pass hands the set over whatever it is: after the phone was restarted under the app, say.
  void forget() => _sent = null;
}
