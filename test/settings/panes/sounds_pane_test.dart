import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart' show SettingsSection, settingsHueOf;
import 'package:ghost_md/settings/panes/sounds_pane.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/sounds/sound_pack.dart';
import 'package:glacier/glacier.dart';

import '../../sounds/support.dart';
import 'support.dart';

/// Settings › Sounds & haptics (Matt, 2026-10-27: "build ... the sounds settings"): its row on the list, its pick and
/// switches writing the preferences, its previews reaching the player, and Simple's page with the rest behind More.
/// Since 2026-11-01 (Matt: "see if there are other settings that can be simplified removed or moved") the pack and
/// Interface sounds are one pick, Sounds: All, Notifications only or Off; and Haptics is here, from Appearance.
void main() {
  setUpAll(loadAppFonts);

  late HeardOutput output;

  setUp(() => output = HeardOutput());

  Future<void> open(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light')}) async {
    useSounds(heardSounds(output), addTearDown);
    await openPane(tester, 'sounds', prefs: prefs);
  }

  SettingsFacts facts(Preferences prefs, {bool haptics = false}) => SettingsFacts(prefs: prefs, wide: false, haptics: haptics, android: true, ios: false, developer: false);

  testWidgets('is a row under Appearance on its card, in amber, Sounds & haptics, found by the search', (tester) async {
    final spec = settingsSections.firstWhere((each) => each.id == 'sounds');
    expect(spec.label, 'Sounds & haptics');
    expect(spec.group, appearanceGroup);
    expect(settingsSections.indexOf(spec), settingsSections.indexWhere((each) => each.id == 'theme') + 1);
    expect(simpleSections, contains('sounds'));
    expect(spec.summary!(facts(Preferences.defaults)), 'All · 4 of 12 on');
    expect(spec.summary!(facts(Preferences.defaults.copyWith(sounds: 'notifications'))), 'Notifications only');
    expect(spec.summary!(facts(Preferences.defaults.copyWith(sounds: 'off'))), 'Off');
    final names = [for (final found in spec.settings!(facts(Preferences.defaults))) found.name];
    expect(names, containsAll(['Sounds', 'Volume', 'To-do ticked', 'Recording starts']));
    expect(names, isNot(anyOf(contains('Sound pack'), contains('Interface sounds'), contains('Haptics'))));
    expect([for (final found in spec.settings!(facts(Preferences.defaults, haptics: true))) found.name], contains('Haptics'));
    await open(tester);
    expect(display(tester), 'Sounds & haptics');
    expect(settingsHueOf(const SettingsSection(id: 'sounds', label: 'Sounds & haptics', icon: SizedBox(), content: _empty, group: appearanceGroup)), 'amber');
    await endSettings(tester);
  });

  testWidgets('every event has a switch that writes its own preference, and a play button that previews it', (tester) async {
    await open(tester);
    // Touch where there is a motor, as a test's phone has.
    expect(cardTitles(tester), ['Sounds', 'Each sound', 'Touch']);
    expect(rowLabels(tester, 'Each sound'), [for (final event in SoundEvent.values) event.label]);

    bool switchOf(String label) => tester.widget<GlacierSwitch>(inRow(label, find.byType(GlacierSwitch))).checked == true;
    expect(switchOf('To-do ticked'), isTrue);
    expect(switchOf('All to-dos ticked'), isFalse);

    await tapOn(tester, inRow('All to-dos ticked', find.byType(GlacierSwitch)));
    expect(preferences.value.soundEvents, {'all-ticked': true});
    await tapOn(tester, inRow('To-do ticked', find.byType(GlacierSwitch)));
    expect(preferences.value.soundEvents, {'all-ticked': true, 'todo-ticked': false});

    // Played whatever the switch says: the person asked to hear it.
    await tapOn(tester, find.byKey(const ValueKey('sound-play-todo-ticked')));
    await tapOn(tester, find.byKey(const ValueKey('sound-play-reminder-due')));
    expect(output.events, ['todo-ticked', 'reminder-due']);
    await endSettings(tester);
  });

  testWidgets('Sounds is All, Notifications only or Off, kept, a taste of the pack played; Off plays nothing and hides the play buttons', (tester) async {
    await open(tester);
    final choice = find.byKey(const ValueKey('sounds-choice'));
    await tapOn(tester, find.descendant(of: choice, matching: find.text('Off')));
    expect((preferences.value.sounds, preferences.value.soundPack, preferences.value.interfaceSounds), ('off', 'off', false));
    expect(output.played, isEmpty);
    expect(find.byKey(const ValueKey('sound-play-todo-ticked'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('sound-volume'), skipOffstage: false), findsNothing);

    await tapOn(tester, find.descendant(of: choice, matching: find.text('Notifications only')));
    expect((preferences.value.sounds, preferences.value.soundPack, preferences.value.interfaceSounds), ('notifications', 'ghostly', false));
    // With sounds in the app off there is nothing to set loud or quiet.
    expect(find.byKey(const ValueKey('sound-volume'), skipOffstage: false), findsNothing);

    await tapOn(tester, find.descendant(of: choice, matching: find.text('All')));
    expect((preferences.value.sounds, preferences.value.soundPack, preferences.value.interfaceSounds), ('all', 'ghostly', true));
    expect(output.events, ['all-ticked', 'all-ticked']);
    await endSettings(tester);
  });

  testWidgets('the volume writes its own', (tester) async {
    await open(tester);
    await tapOn(tester, find.text('25%'));
    expect(preferences.value.soundVolume, 0.25);
    expect(output.played.single.volume, 0.25);
    await endSettings(tester);
  });

  testWidgets('in Simple the pick comes first, and the rest opens in place from More', (tester) async {
    await open(tester, prefs: const Preferences(theme: 'light').choosing('simple'));
    expect(cardTitles(tester), ['Sounds', 'Touch', null]);
    expect(rowLabels(tester, 'Sounds'), ['Sounds']);
    await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('sounds-more')), matching: find.text('Show')));
    expect(cardTitles(tester), ['Sounds', 'Each sound', 'Touch']);
    expect(rowLabels(tester, 'Sounds'), ['Sounds', 'Volume']);
    await endSettings(tester);
  });

  // Matt, 2026-11-01: Haptics moves into the Sounds pane, now "Sounds & haptics". Where there is a motor, in either mode.
  testWidgets('has Haptics under Touch where there is a motor, this device’s own switch', (tester) async {
    for (final prefs in [const Preferences(theme: 'light'), const Preferences(theme: 'light').choosing('simple')]) {
      final haptics = DeviceFlag('test-haptics', fallback: () => true);
      useSounds(heardSounds(output), addTearDown);
      await pumpSettings(tester, SingleChildScrollView(child: SoundsPane(store: preferences, haptics: haptics, hasMotor: true)), prefs: prefs);
      expect(cardTitles(tester), contains('Touch'));
      await tapOn(tester, inRow('Haptics', find.byType(GlacierSwitch)));
      expect(haptics.value, isFalse);
      await endSettings(tester);
    }
    useSounds(heardSounds(output), addTearDown);
    await pumpSettings(tester, SingleChildScrollView(child: SoundsPane(store: preferences, hasMotor: false)));
    expect(cardTitles(tester), isNot(contains('Touch')));
    await endSettings(tester);
  });
}

Widget _empty(BuildContext context) => const SizedBox();
