import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/settings_screen.dart' show SettingsSection, settingsHueOf;
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:ghost_md/sounds/sound_pack.dart';
import 'package:glacier/glacier.dart';

import '../../sounds/support.dart';
import 'support.dart';

/// Settings › Sounds (Matt, 2026-10-27: "build ... the sounds settings"): its row on the list, its switches writing
/// the preferences, its previews reaching the player, and Simple's page with the rest behind More.
void main() {
  setUpAll(loadAppFonts);

  late HeardOutput output;

  setUp(() => output = HeardOutput());

  Future<void> open(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light')}) async {
    useSounds(heardSounds(output), addTearDown);
    await openPane(tester, 'sounds', prefs: prefs);
  }

  testWidgets('is a row under Appearance on its card, in amber, found by the search', (tester) async {
    final spec = settingsSections.firstWhere((each) => each.id == 'sounds');
    expect(spec.group, appearanceGroup);
    expect(settingsSections.indexOf(spec), settingsSections.indexWhere((each) => each.id == 'theme') + 1);
    expect(simpleSections, contains('sounds'));
    expect(spec.summary!(SettingsFacts(prefs: Preferences.defaults, wide: false, haptics: false, android: true, ios: false, developer: false)), 'Ghostly · 4 of 12 on');
    expect(spec.summary!(SettingsFacts(prefs: Preferences.defaults.copyWith(soundPack: 'off'), wide: false, haptics: false, android: true, ios: false, developer: false)), 'Off');
    final names = [for (final found in spec.settings!(SettingsFacts(prefs: Preferences.defaults, wide: false, haptics: false, android: true, ios: false, developer: false))) found.name];
    expect(names, containsAll(['Sound pack', 'Interface sounds', 'Volume', 'To-do ticked', 'Recording starts']));
    await open(tester);
    expect(display(tester), 'Sounds');
    expect(settingsHueOf(const SettingsSection(id: 'sounds', label: 'Sounds', icon: SizedBox(), content: _empty, group: appearanceGroup)), 'amber');
    await endSettings(tester);
  });

  testWidgets('every event has a switch that writes its own preference, and a play button that previews it', (tester) async {
    await open(tester);
    expect(cardTitles(tester), ['Sound pack', 'In the app', 'Sounds']);
    expect(rowLabels(tester, 'Sounds'), [for (final event in SoundEvent.values) event.label]);

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

  testWidgets('a pack chosen is kept and plays a taste of itself; Off plays nothing and hides the play buttons', (tester) async {
    await open(tester);
    await tapOn(tester, inRow('Off', find.byType(Pick)));
    expect(preferences.value.soundPack, 'off');
    expect(output.played, isEmpty);
    expect(find.byKey(const ValueKey('sound-play-todo-ticked'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('sound-volume'), skipOffstage: false), findsNothing);

    await tapOn(tester, inRow('Ghostly', find.byType(Pick)));
    expect(preferences.value.soundPack, 'ghostly');
    expect(output.events, ['all-ticked']);
    await endSettings(tester);
  });

  testWidgets('the interface switch and the volume write theirs', (tester) async {
    await open(tester);
    await tapOn(tester, find.text('25%'));
    expect(preferences.value.soundVolume, 0.25);
    expect(output.played.single.volume, 0.25);
    await tapOn(tester, inRow('Interface sounds', find.byType(GlacierSwitch)));
    expect(preferences.value.interfaceSounds, isFalse);
    // With sounds in the app off there is nothing to set loud or quiet.
    expect(find.byKey(const ValueKey('sound-volume'), skipOffstage: false), findsNothing);
    await endSettings(tester);
  });

  testWidgets('in Simple the pack and the switch come first, and the rest opens in place from More', (tester) async {
    await open(tester, prefs: const Preferences(theme: 'light').choosing('simple'));
    expect(cardTitles(tester), ['Sound pack', 'In the app', null]);
    expect(rowLabels(tester, 'In the app'), ['Interface sounds']);
    await tapOn(tester, find.descendant(of: find.byKey(const ValueKey('sounds-more')), matching: find.text('Show')));
    expect(cardTitles(tester), ['Sound pack', 'In the app', 'Sounds']);
    expect(rowLabels(tester, 'In the app'), ['Interface sounds', 'Volume']);
    await endSettings(tester);
  });
}

Widget _empty(BuildContext context) => const SizedBox();
