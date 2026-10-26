// The Place reminders plugin (lib/plugins/places): built in and off until switched on, within its manifest, held on
// under Local only (nothing of it leaves the phone), its card in the Market, and its page: how it works,
// whether Android lets it know where the phone is all the time, and the way to allow it. Against stand-ins for the
// phone.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/places/places.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/reminders/place_host.dart';
import 'package:ghost_md/reminders/place_settings.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/market/market_items.dart' show MarketShelf;
import 'package:ghost_md/market/market_screen.dart';

import '../settings/support.dart';
import '../support/fake_places.dart';

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

void main() {
  setUpAll(loadAppFonts);

  group('the plugin', () {
    test('ships off, reaches the notes and the phone only, and keeps one key', () {
      final plugin = builtIn.singleWhere((p) => p.manifest.id == placeRemindersId);
      expect(identical(plugin, placesPlugin), isTrue);
      expect((plugin.manifest.name, plugin.manifest.standard, plugin.icon), ('Place reminders', false, 'map-pin'));
      expect([for (final p in plugin.manifest.permissions) p.kind], [Permission.notes, Permission.native]);
      expect(usesNetwork(plugin.manifest), isFalse);
      expect(plugin.manifest.storage, [placeSettingsKey]);
      expect(reachLine(plugin.manifest), 'Your notes · Built-in app commands');
    });

    test('off until switched on, and on under Local only once it is', () {
      final registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => true);
      expect(registry.isEnabled(placeRemindersId), isFalse);
      registry.setEnabled(placeRemindersId, true);
      expect(registry.isEnabled(placeRemindersId), isTrue);
      expect(registry.storageKeys(), contains(placeSettingsKey));
    });
  });

  group('the Market', () {
    late Registry before;
    setUp(() {
      before = plugins;
      useStored(MemoryStored());
    });
    tearDown(() => usePlugins(before));

    testWidgets('its card, to discover, with its line and what it uses; its page, with what it does', (tester) async {
      usePlugins(createRegistry(builtIn, store: MemorySwitches()));
      await pumpSettings(tester, MarketScreen(onBack: () {}, shelf: MarketShelf.plugins));
      final card = find.byKey(const ValueKey('market-plugin-$placeRemindersId'), skipOffstage: false);
      expect(find.descendant(of: card, matching: find.text('Place reminders', skipOffstage: false), skipOffstage: false), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Reminders when you arrive somewhere', skipOffstage: false), skipOffstage: false), findsOneWidget);
      // It watches places through Android's geofences alone.
      expect(find.descendant(of: card, matching: find.text('Android only', skipOffstage: false), skipOffstage: false), findsOneWidget);
      await endSettings(tester);

      await pumpSettings(tester, MarketScreen(onBack: () {}, plugin: placeRemindersId));
      expect(find.text('A to-do with a place reminds you when your phone arrives there.', skipOffstage: false), findsOneWidget);
      expect(find.text('Your notes', skipOffstage: false), findsOneWidget);
      await endSettings(tester);
    });
  });

  group('its page', () {
    late FakePlaces places;
    setUp(() {
      places = FakePlaces();
      useStored(MemoryStored());
      forgetReminderSettings();
      placeRemindersOn.value = true;
    });
    tearDown(() {
      forgetReminderSettings();
      placeRemindersOn.value = false;
      placeWarning.value = false;
    });

    Future<void> open(WidgetTester tester, PlaceHost? host) async {
      await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: PlacesPane(places: host))));
      await tester.pump();
    }

    testWidgets('allowed all the time: says so, offers nothing', (tester) async {
      await open(tester, places);
      expect(hintOf(tester, 'Allowed all the time'), 'Your phone tells Ghost.md when it arrives at a place on one of your to-dos.');
      expect(find.text('Allow location all the time'), findsNothing);
      expect(placeWarning.value, isFalse);
      await endSettings(tester);
    });

    testWidgets('only while in use: why, and Android’s “all the time”, after which the words go', (tester) async {
      places.now = PlaceAccess.whileUsing;
      await open(tester, places);
      expect(hintOf(tester, 'Not allowed all the time'), startsWith('Android only lets Ghost.md know where you are while it is open'));
      expect(placeWarning.value, isTrue);
      await tester.tap(find.text('Allow location all the time'));
      await tester.pump();
      await tester.pump();
      expect(places.asked, ['background']);
      expect(find.text('Allow location all the time'), findsNothing);
      expect(placeWarning.value, isFalse);
      await endSettings(tester);
    });

    testWidgets('never asked: the prompt while in use first, then all the time', (tester) async {
      places.now = PlaceAccess.ask;
      await open(tester, places);
      await tester.tap(find.text('Allow location'));
      await tester.pump();
      await tester.pump();
      expect(places.asked, ['foreground', 'background']);
      await endSettings(tester);
    });

    testWidgets('refused for good: the phone’s own settings', (tester) async {
      places.now = PlaceAccess.blocked;
      await open(tester, places);
      expect(hintOf(tester, 'Not allowed all the time'), startsWith('Location is turned off for Ghost.md.'));
      await tester.tap(find.text('Open the phone’s settings'));
      await tester.pump();
      expect(places.asked, ['settings']);
      await endSettings(tester);
    });

    testWidgets('a device with no geofences says so', (tester) async {
      await open(tester, null);
      expect(find.text('Not on this device'), findsOneWidget);
      await endSettings(tester);
    });
  });
}
