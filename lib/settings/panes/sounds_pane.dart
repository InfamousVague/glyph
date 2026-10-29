import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import '../../sounds/sound_pack.dart';
import '../../sounds/sounds.dart' as player show sounds;
import '../../sounds/sounds.dart' show Sounds, soundEventOn;
import '../kit/settings_kit.dart';
import '../settings_search.dart';

/// What Settings' search finds on Sounds: the pack, the interface switch and its volume, and every event by its name.
/// In [simple] the events are behind More, and are found all the same: the search opens the page, and More is a tap.
List<SettingsFindable> soundsFindable() => [
      const SettingsFindable('Sound pack', 'sounds pack ghostly off quiet silent audio chime'),
      const SettingsFindable('Interface sounds', 'sounds in the app tick tap chime audio mute'),
      const SettingsFindable('Volume', 'loud quiet sound level'),
      for (final event in SoundEvent.values) SettingsFindable(event.label, 'sound ${event.hint}'),
    ];

/// Sounds' row in the list: the pack, or Off.
String soundsSummary(Preferences prefs) {
  final pack = soundPackOf(prefs.soundPack);
  if (pack.silent) return 'Off';
  if (!prefs.interfaceSounds) return '${pack.name}, in the app off';
  final on = SoundEvent.values.where((event) => soundEventOn(prefs, event)).length;
  return '${pack.name} · $on of ${SoundEvent.values.length} on';
}

/// What a sound's row says under its name: where a notification's sound is heard as well as in the app.
String _hintOf(SoundEvent event) {
  if (event.place != SoundPlace.notification) return event.hint;
  // The two whose Android notifications post on the pack's own channel so far (android/…/SoundChannels.kt).
  final phone = event == SoundEvent.writeupReady || event == SoundEvent.reminderDue;
  return phone ? '${event.hint} In the app, and as its notification’s sound on Android.' : '${event.hint} In the app, while it is open.';
}

/// The volume's steps as the control says them.
String _percent(double volume) => '${(volume * 100).round()}%';

/// Settings › Sounds (Matt, 2026-10-27: "build ... the sounds settings"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md,
/// Sounds): the pack every sound comes from, whether the app makes sounds at all and how loud, and each sound's own
/// switch with a way to hear it.
///
/// A pack chosen plays a little of itself, as a font card shows its letters; each event's play button plays it in
/// the chosen pack whatever its switch says, since the person asked to hear it. Only the recorder's start and stop
/// and the to-do's tick are on until they are switched (`SoundEvent.on`).
///
/// In Simple (GHST-103) the page is the pack and the switch, and the rest behind a More row that opens in place, as
/// Recording's is.
class SoundsPane extends StatefulWidget {
  const SoundsPane({super.key, this.store, this.sounds});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;

  /// The player the previews go to; the app's own when null.
  final Sounds? sounds;

  static Widget hosted(BuildContext context) => const SoundsPane();

  @override
  State<SoundsPane> createState() => _SoundsPaneState();
}

class _SoundsPaneState extends State<SoundsPane> {
  /// Simple's More, pressed.
  bool _more = false;

  Sounds get _sounds => widget.sounds ?? player.sounds;

  @override
  Widget build(BuildContext context) {
    final store = widget.store ?? preferences;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        void set(Preferences Function(Preferences now) change) => store.update(change);
        final pack = soundPackOf(prefs.soundPack);
        // Simple's page is the pack and the switch until More is pressed, or one of the rest is looked for by name;
        // Advanced's is all of it.
        if (!_more && settingsSought(context, ['Volume', for (final event in SoundEvent.values) event.label])) _more = true;
        final full = !prefs.simple || _more;

        final packs = PaneSection(
          title: 'Sound pack',
          description: const Text('Every sound in one voice. Tap a pack to hear it.'),
          children: [
            for (final each in soundPacks)
              SettingRow(
                key: ValueKey('sound-pack-${each.id}'),
                label: each.name,
                hint: Text(each.description),
                control: Pick(
                  checked: pack.id == each.id,
                  label: 'Use ${each.name}',
                  onPress: () {
                    set((now) => now.copyWith(soundPack: each.id));
                    // A taste of it: the flourish says the most about a pack in a second.
                    _sounds.preview(SoundEvent.allTicked, pack: each.id);
                  },
                ),
              ),
          ],
        );

        final inApp = PaneSection(
          title: 'In the app',
          footer: const Text('Quiet while the phone is on silent or Do Not Disturb, during a call, and while you record.'),
          children: [
            SettingRow(
              key: const ValueKey('sound-interface'),
              label: 'Interface sounds',
              hint: const Text('The tick of a to-do, the recorder’s start and stop, and the others you switch on below.'),
              control: GlacierSwitch(ariaLabel: 'Interface sounds', checked: prefs.interfaceSounds, onCheckedChange: (on) => set((now) => now.copyWith(interfaceSounds: on))),
            ),
            if (full && prefs.interfaceSounds && !pack.silent)
              SettingRow(
                key: const ValueKey('sound-volume'),
                label: 'Volume',
                hint: const Text('For the sounds inside the app, on this device.'),
                layout: SettingRowLayout.stacked,
                control: GlacierSegmentedControl(
                  ariaLabel: 'Volume',
                  fullWidth: true,
                  size: GlacierSegmentedSize.sm,
                  options: [for (final step in soundVolumes) GlacierSegmentedOption(value: '$step', label: Text(_percent(step)))],
                  value: '${prefs.soundVolume}',
                  onValueChange: (value) {
                    set((now) => now.copyWith(soundVolume: double.parse(value)));
                    _sounds.preview(SoundEvent.todoTicked);
                  },
                ),
              ),
          ],
        );

        final events = PaneSection(
          title: 'Sounds',
          description: Text(pack.silent ? 'No pack is chosen, so nothing plays.' : 'Each sound on its own. Only the recorder and the to-do’s tick start on.'),
          children: [
            for (final event in SoundEvent.values)
              SettingRow(
                key: ValueKey('sound-${event.id}'),
                label: event.label,
                hint: Text(_hintOf(event)),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!pack.silent)
                      Semantics(
                        button: true,
                        label: 'Play ${event.label}',
                        child: ExcludeSemantics(
                          child: RowAction(
                            key: ValueKey('sound-play-${event.id}'),
                            onPress: () => _sounds.preview(event),
                            child: AppIcon(Lucide.play, size: 16),
                          ),
                        ),
                      ),
                    GlacierSwitch(
                      ariaLabel: event.label,
                      checked: soundEventOn(prefs, event),
                      onCheckedChange: (on) => set((now) => now.copyWith(soundEvents: {...now.soundEvents, event.id: on})),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (!full) {
          return PaneBody(
            children: [
              packs,
              inApp,
              PaneSection(
                children: [
                  SettingRow(
                    key: const ValueKey('sounds-more'),
                    label: 'More',
                    hint: const Text('The volume and each sound on its own.'),
                    control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
                  ),
                ],
              ),
            ],
          );
        }
        return PaneBody(children: [packs, inApp, events]);
      },
    );
  }
}
