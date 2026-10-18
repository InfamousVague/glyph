/// The Place reminders plugin, built in and off until switched on: a to-do with a `📍` place reminds when the phone
/// arrives there (docs/INTEGRATIONS.md §3). Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as
/// plugins".
///
/// The `📍 [Target](geo:…)` is Markdown (lib/reminders/place_syntax.dart): it is read, drawn as a chip and left out of
/// an item's words whether the plugin is on or not, on every device. What the plugin switches is the phone's part:
///
/// - **Press and hold › Remind me at a place**, and a place chip's **Change place**: offered only while it is on, on a
///   phone that watches places (lib/reminders/place_host.dart [placeRemindersOn], [phonePlaces]).
/// - **The geofences**: set for each open to-do with a place while it is on (lib/reminders/place_scheduler.dart, from
///   lib/root/phone_extras.dart's pass); switched off, the phone is told to clear every one.
/// - **Its page** (places_pane.dart): what it does, whether Android lets it know where the phone is all the time,
///   and the way to allow that.
///
/// What it reaches is the notes (to read the to-dos with a place, and write the place picked) and the phone's
/// location, kept inside the app and handed to Google Play services' geofences (`native`). A place searched for by
/// name is asked of OpenStreetMap through the app's own place lookup (lib/core/geocode.dart), the one that names a
/// place the + adds, which Local only turns off by itself; so the plugin does not declare the network, and Local only
/// leaves the reminders themselves working, since they never leave the phone.
library;

import '../../reminders/place_settings.dart' show placeSettingsKey;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'places_pane.dart';

export 'places_pane.dart' show PlacesPane;

/// The plugin's id: its switch, as lib/root asks it.
const String placeRemindersId = 'place-reminders';

const PluginManifest placesManifest = PluginManifest(
  id: placeRemindersId,
  name: 'Place reminders',
  description: 'A to-do with a place reminds you when your phone arrives there.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.calendar,
  tagline: 'Reminders when you arrive somewhere',
  adds: [
    'Remind me at a place, when you press and hold a to-do',
    'A reminder as your phone arrives, while the app is closed',
  ],
  // Off until switched on: it asks Android for the location all the time.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the to-dos that have a place, to know which places to watch, and writes the place you pick on a to-do.'),
    PluginPermission(
      Permission.native,
      'Knows where your phone is while the app is closed, through Google Play services’ geofences, to notice when you arrive at one of those places. Where you are never leaves the phone through Ghost.md.',
    ),
  ],
  storage: [placeSettingsKey],
);

/// See the header.
final GlyphPlugin placesPlugin = GlyphPlugin(
  manifest: placesManifest,
  icon: 'map-pin',
  settings: PluginSettings(
    pane: (context) => const PlacesPane(),
    summary: () => 'Reminders when you arrive',
    hue: 'green',
    settings: const [
      SettingsFindable('How it works', 'place location arrive geofence pin map reminder'),
      SettingsFindable('Location', 'allow all the time background permission precise'),
    ],
  ),
);
