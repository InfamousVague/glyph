/// The phone's half of place reminders, over the channel `ghost_md/places` (android/…/ghost_md/reminders/Places.kt):
/// the geofences it holds, the location permission they need, and where the phone last was.
///
/// - `set [{id, lat, lon, radius, title, text, place, noteId, line, words}]`: the whole set (place_plan.dart), which
///   the phone keeps, registers with Google Play services' GeofencingClient, and registers again after a restart or
///   an update; whatever it held that the set no longer has is let go. Arriving at one shows a notification on the
///   reminders' channel, whose tap opens the note at the to-do and whose Done ticks it, as a reminder's does
///   (reminder_host.dart, Reminders.kt).
/// - `clear`: none at all.
/// - `access` -> `always`, `whileUsing`, `approximate`, `ask` or `blocked` ([PlaceAccess]).
/// - `askForeground` -> the same, once Android's prompt for location while the app is in use is answered.
/// - `askBackground` -> the same, once Android's "Allow all the time" is answered (from Android 11 a page of its
///   settings, not a dialog).
/// - `lastKnown` -> `{lat, lon}` or null: where the phone last was, for the nearest hundred.
/// - `openSettings`: the app's own page in the phone's settings.
///
/// Where there is no phone half (a Mac, an iPhone, a test without one) every ask answers null or false, and place
/// reminders are offered nowhere. The iPhone's region monitoring is to come (docs/INTEGRATIONS.md §3).
library;

import 'package:flutter/foundation.dart' show ValueNotifier, defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

import 'place_plan.dart';

/// What the phone lets the app know of where it is, as a geofence needs it.
enum PlaceAccess {
  /// Precise, and while the app is closed too: the geofences work.
  always,

  /// Precise, but only while the app is in use: Android keeps the geofences from ringing.
  whileUsing,

  /// Approximate only: a geofence needs the precise location.
  approximate,

  /// Never answered, or may be asked again.
  ask,

  /// Refused for good: only the phone's settings can allow it now.
  blocked,
}

/// The access a word of the channel names; [PlaceAccess.ask] for anything else.
PlaceAccess placeAccessOf(Object? said) => switch (said) {
  'always' => PlaceAccess.always,
  'whileUsing' => PlaceAccess.whileUsing,
  'approximate' => PlaceAccess.approximate,
  'blocked' => PlaceAccess.blocked,
  _ => PlaceAccess.ask,
};

/// The phone's place reminders, where this run has them: a line's menu offers Remind me at a place, and Settings ›
/// Notifications › Reminders its switch, only while this is set (lib/root/phone_extras.dart, on Android).
final ValueNotifier<PlaceHost?> phonePlaces = ValueNotifier<PlaceHost?>(null);

/// Whether the Place reminders plugin is switched on (lib/plugins/places, Settings › Plugins): Remind me at a place
/// is offered, and a place's chip offers Change place, only while it is. The `📍` is Markdown, read and drawn either
/// way. Kept by lib/root/phone_extras.dart, which hears the plugins' switches.
final ValueNotifier<bool> placeRemindersOn = ValueNotifier<bool>(false);

/// Whether a place's chip says, quietly, that the phone will not remind there: place reminders are on, and the
/// location they need is not allowed all the time (lib/editor/items/task_fields.dart reads it as it draws).
final ValueNotifier<bool> placeWarning = ValueNotifier<bool>(false);

/// The phone, asked about places.
abstract interface class PlaceHost {
  /// Hands the phone the whole set. False where it could not be handed.
  Future<bool> set(List<PlaceReminder> places);

  /// Lets every geofence go.
  Future<bool> clear();

  /// The permission as it stands; null where there is no phone half.
  Future<PlaceAccess?> access();

  /// Android's prompt for the location while the app is in use; the access once it is answered.
  Future<PlaceAccess> askForeground();

  /// Android's "Allow all the time"; the access once it is answered.
  Future<PlaceAccess> askBackground();

  /// Where the phone last was, or null where it has not said.
  Future<LatLon?> lastKnown();

  /// The app's page in the phone's settings.
  Future<bool> openSettings();
}

/// The channel the phone answers on.
const MethodChannel placesChannel = MethodChannel('ghost_md/places');

/// The phone's own half, on Android; nothing anywhere else.
class PhonePlaceHost implements PlaceHost {
  PhonePlaceHost({MethodChannel channel = placesChannel, bool? android}) : _channel = channel, _android = android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _android;

  Future<Object?> _ask(String method, [Object? arguments]) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> set(List<PlaceReminder> places) async => await _ask('set', [for (final place in places) place.toJson()]) == true;

  @override
  Future<bool> clear() async => await _ask('clear') == true;

  @override
  Future<PlaceAccess?> access() async {
    final said = await _ask('access');
    return said is String ? placeAccessOf(said) : null;
  }

  @override
  Future<PlaceAccess> askForeground() async => placeAccessOf(await _ask('askForeground'));

  @override
  Future<PlaceAccess> askBackground() async => placeAccessOf(await _ask('askBackground'));

  @override
  Future<LatLon?> lastKnown() async {
    final said = await _ask('lastKnown');
    if (said is! Map) return null;
    final lat = said['lat'], lon = said['lon'];
    if (lat is! num || lon is! num) return null;
    return (lat: lat.toDouble(), lon: lon.toDouble());
  }

  @override
  Future<bool> openSettings() async => await _ask('openSettings') == true;
}
