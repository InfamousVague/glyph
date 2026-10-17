/// Whether this phone has asked yet for the location place reminders need. Place reminders are a plugin (Matt,
/// 2026-10-17: "Ask Claude and other integrations should be shipped as plugins"; lib/plugins/places), switched on in
/// Settings › Plugins, and that switch is whether places are watched at all. What is kept here is only whether the
/// first place reminder has been made on this phone: that is when it asks, saying why first
/// (docs/INTEGRATIONS.md §3), and only then; afterwards the plugin's page offers the way to allow it. This device's
/// own, kept in its memory under `glyph-place-reminders` (lib/core/stored.dart), never synced.
library;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';

/// What this phone has done.
@immutable
class PlaceSettings {
  const PlaceSettings({this.asked = false});

  /// Whether a place reminder has been made here, and so the location asked for.
  final bool asked;

  Map<String, Object?> toJson() => {'asked': asked};

  /// What was kept; anything else is the default's.
  static PlaceSettings? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return PlaceSettings(asked: raw['asked'] == true);
  }

  @override
  bool operator ==(Object other) => other is PlaceSettings && other.asked == asked;

  @override
  int get hashCode => asked.hashCode;

  @override
  String toString() => 'PlaceSettings(${toJson()})';
}

/// The key it is kept under; the plugin's own (lib/plugins/places/places.dart lists it).
const String placeSettingsKey = 'glyph-place-reminders';

/// What was done, read once from this device's memory and written back as it changes.
class PlaceSettingsStore extends ValueNotifier<PlaceSettings> {
  PlaceSettingsStore([Stored? kept])
      : _kept = kept ?? stored,
        super((kept ?? stored).read<PlaceSettings>(placeSettingsKey, const PlaceSettings(), PlaceSettings.fromJson));

  final Stored _kept;

  /// A place reminder was made: true the first time on this phone, when the location is to be asked for.
  bool firstMade() {
    if (value.asked) return false;
    value = const PlaceSettings(asked: true);
    _kept.write(placeSettingsKey, value.toJson());
    return true;
  }
}

PlaceSettingsStore? _settings;

/// The app's own, over the device's memory as it is when first asked: after the launch has opened it.
PlaceSettingsStore get placeSettings => _settings ??= PlaceSettingsStore();

/// For a test, or a reset: the next ask reads the memory again.
@visibleForTesting
void forgetPlaceSettings() => _settings = null;
