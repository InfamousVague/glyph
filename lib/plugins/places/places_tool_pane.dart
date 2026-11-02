/// The Places plugin's page in Settings (places_tool.dart): the Location card that was Settings › Account's, whole
/// (lib/settings/panes/account_pane.dart [LocationCard]), the map on a tagged note, a place's name from
/// OpenStreetMap, and Tag new notes with my location, with its refusal and Local only's word under it. Moved here with
/// the feature (docs/PM_PLUGINS.md §10): with Places off there is nothing for it to say.
library;

import 'package:flutter/widgets.dart';

import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/account_pane.dart' show LocationCard;
import '../../settings/panes/settings_host.dart';

class PlacesToolPane extends StatelessWidget {
  const PlacesToolPane({super.key, this.store, this.features = const SettingsFeatures()});

  final PreferencesStore? store;

  /// What finds where the device is (`places`, `onLocate`, `cannotLocate`), as Settings › Account had it.
  final SettingsFeatures features;

  static Widget hosted(BuildContext context) => PlacesToolPane(features: SettingsHost.maybeOf(context)?.features ?? const SettingsFeatures());

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    final card = LocationCard(store: store, onLocate: features.onLocate, cannot: features.cannotLocate, places: features.places);
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) => PaneBody(children: card.parts(prefs)),
    );
  }
}
