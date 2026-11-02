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

/// What Settings' search finds on Sounds & haptics: what makes a sound, its volume, every event by its name, and the
/// haptics where there is a motor. In Simple the volume and the events are behind More, and are found all the same:
/// the search opens the page, and More is a tap. Sound pack and Interface sounds, the two the Sounds row was until
/// 2026-11-01, are found by their words.
List<SettingsFindable> soundsFindable({bool haptics = false}) => [
      const SettingsFindable('Sounds', 'sound pack ghostly interface sounds in the app all notifications only off quiet silent mute audio chime tick tap'),
      const SettingsFindable('Volume', 'loud quiet sound level'),
      for (final event in SoundEvent.values) SettingsFindable(event.label, 'sound ${event.hint}'),
      if (haptics) const SettingsFindable('Haptics', 'vibrate vibration buzz touch'),
    ];

/// The Sounds row's words, in [soundsChoices]' order.
const Map<String, String> soundsWords = {'all': 'All', 'notifications': 'Notifications only', 'off': 'Off'};

/// Sounds' row in the list: Off, Notifications only, or All with how many of its sounds are on.
String soundsSummary(Preferences prefs) {
  if (prefs.sounds == 'off') return 'Off';
  if (prefs.sounds == 'notifications') return 'Notifications only';
  final on = SoundEvent.values.where((event) => soundEventOn(prefs, event)).length;
  return 'All · $on of ${SoundEvent.values.length} on';
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

/// Settings › Sounds & haptics (Matt, 2026-10-27: "build ... the sounds settings"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md,
/// Sounds): what makes a sound and how loud, each sound's own switch with a way to hear it, and the haptics.
///
/// **Sounds** is one pick, All, Notifications only or Off (Matt, 2026-11-01: "see if there are other settings that can
/// be simplified"): it was a pack, Ghostly or Off, and a switch for the sounds inside the app, Interface sounds, until
/// that day; the pick is the two read as one (`Preferences.sounds`). A pick that makes sounds plays a little of the
/// pack, as a font card shows its letters; each event's play button plays it whatever its switch says, since the
/// person asked to hear it. Only the recorder's start and stop and the to-do's tick are on until they are switched
/// (`SoundEvent.on`). **Haptics** came here from Settings › Appearance › Touch that day, where there is a motor.
///
/// In Simple (GHST-103) the page is the pick and the haptics, and the rest behind a More row that opens in place, as
/// Recording's is.
class SoundsPane extends StatefulWidget {
  const SoundsPane({super.key, this.store, this.sounds, this.haptics, this.hasMotor});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;

  /// The player the previews go to; the app's own when null.
  final Sounds? sounds;

  /// The haptics switch's flag; the app's own when null.
  final DeviceFlag? haptics;

  /// Whether this device has a motor; asked of the platform when null.
  final bool? hasMotor;

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
    final haptics = widget.haptics ?? hapticsPref;
    return ListenableBuilder(
      listenable: Listenable.merge([store, haptics]),
      builder: (context, _) {
        final prefs = store.value;
        void set(Preferences Function(Preferences now) change) => store.update(change);
        final pack = soundPackOf(prefs.soundPack);
        // Simple's page is the pack and the switch until More is pressed, or one of the rest is looked for by name;
        // Advanced's is all of it.
        if (!_more && settingsSought(context, ['Volume', for (final event in SoundEvent.values) event.label])) _more = true;
        final full = !prefs.simple || _more;

        final sounds = PaneSection(
          title: 'Sounds',
          footer: const Text('Quiet while the phone is on silent or Do Not Disturb, during a call, and while you record.'),
          children: [
            SettingRow(
              key: const ValueKey('sounds-choice'),
              label: 'Sounds',
              hint: const Text('All: the tick of a to-do, the recorder’s start and stop and the others you switch on, and the notifications’ own. Notifications only: a notification’s sound alone. Off: nothing plays.'),
              layout: SettingRowLayout.stacked,
              control: GlacierSegmentedControl(
                ariaLabel: 'Sounds',
                fullWidth: true,
                size: GlacierSegmentedSize.sm,
                options: [for (final choice in soundsChoices) GlacierSegmentedOption(value: choice, label: Text(soundsWords[choice]!))],
                value: prefs.sounds,
                onValueChange: (value) {
                  set((now) => now.copyWith(sounds: value));
                  // A taste of it: the flourish says the most about the pack in a second.
                  if (value != 'off') _sounds.preview(SoundEvent.allTicked, pack: soundPackOf('ghostly').id);
                },
              ),
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

        // Haptics, from Settings › Appearance › Touch (2026-11-01), where there is a motor.
        final touch = (widget.hasMotor ?? hapticsAvailable())
            ? PaneSection(
                title: 'Touch',
                children: [
                  SettingRow(
                    label: 'Haptics',
                    hint: const Text('A small tap when a style or a cue kicks in.'),
                    control: GlacierSwitch(ariaLabel: 'Haptics', checked: haptics.value, onCheckedChange: haptics.set),
                  ),
                ],
              )
            : null;

        final events = PaneSection(
          title: 'Each sound',
          description: Text(pack.silent ? 'Sounds are off, so nothing plays.' : 'Each sound on its own. Only the recorder and the to-do’s tick start on.'),
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
              sounds,
              ?touch,
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
        return PaneBody(children: [sounds, events, ?touch]);
      },
    );
  }
}
