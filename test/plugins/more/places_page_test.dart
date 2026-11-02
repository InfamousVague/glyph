// The Places plugin's page (lib/plugins/places/places_tool_pane.dart; docs/PM_PLUGINS.md §10): Settings › Account's
// Location card, moved whole with the feature: the map, a place's name, Tag new notes with my location asking for a fix
// once as it is switched on, and Local only holding the three off and saying so.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/places/places_tool.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/settings_host.dart' show SettingsFeatures;
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:glacier/glacier.dart';

import '../../settings/panes/support.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> openPlaces(WidgetTester tester, {SettingsFeatures features = const SettingsFeatures(), Preferences prefs = const Preferences(theme: 'light')}) => pumpSettings(
        tester,
        SettingsScreen(
          open: true,
          onClose: () {},
          sections: [SettingsSection(id: 'plugin:places', label: 'Places', icon: const SizedBox.shrink(), group: 0, content: (context) => PlacesToolPane(features: features))],
          goTo: const SettingsTarget('plugin:places', nonce: 1),
        ),
        size: const Size(390, 1600),
        prefs: prefs,
      );

  testWidgets('is the Location card, and its switches are the preferences they were', (tester) async {
    var located = 0;
    await openPlaces(tester, features: SettingsFeatures(onLocate: () => located++));
    expect(cardTitles(tester), ['Location']);
    // Map on a tagged note and Place names are one switch since 2026-11-01, Use OpenStreetMap.
    expect(rowLabels(tester, 'Location'), ['Use OpenStreetMap', 'Tag new notes with my location']);
    for (final (row, read) in <(String, bool Function(Preferences))>[
      ('Use OpenStreetMap', (p) => p.openStreetMap && p.mapTiles && p.placeNames),
    ]) {
      final was = read(preferences.value);
      await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
      expect(read(preferences.value), !was, reason: row);
      await tapOn(tester, inRow(row, find.byType(GlacierSwitch)));
      expect(read(preferences.value), was, reason: row);
    }
    // Tagging asks for a fix once, here, as it is switched on.
    preferences.update((now) => now.copyWith(tagNewNotes: false));
    await tester.pump();
    await tapOn(tester, inRow('Tag new notes with my location', find.byType(GlacierSwitch)));
    expect((preferences.value.tagNewNotes, located), (true, 1));
    await tapOn(tester, inRow('Tag new notes with my location', find.byType(GlacierSwitch)));
    expect((preferences.value.tagNewNotes, located), (false, 1));
    await endSettings(tester);
  });

  testWidgets('under Local only, holds both off and says what a tagged note still shows', (tester) async {
    await openPlaces(tester, prefs: const Preferences(theme: 'light', localOnly: true));
    expect([for (final row in rowLabels(tester, 'Location')) tester.widget<SettingRow>(rowCalled(row)).disabledReason], everyElement('Local only is on.'));
    expect(find.textContaining('A tagged note shows where it was written and a pin while Local only is on'), findsOneWidget);
    await endSettings(tester);
  });

  test('is found by what the card was found by, and kept in Simple', () {
    final page = placesToolPlugin.settings!;
    expect([for (final each in page.settings) each.name], ['Location', 'Use OpenStreetMap', 'Tag new notes with my location']);
    expect(page.simple, isTrue);
  });
}
