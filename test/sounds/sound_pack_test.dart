import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/sounds/sound_pack.dart';
import 'package:ghost_md/sounds/sounds.dart';
import 'package:ghost_md/sync/prefs.dart' show syncedPrefs;

import 'support.dart';

/// Settings › Sounds (Matt, 2026-10-27: "build ... the sounds settings"): the packs, the preferences that choose
/// among them, and the rules for when a sound is heard.
void main() {
  group('the packs', () {
    test('are Ghostly then Off, the same list the preferences check a stored one against', () {
      expect(soundPackIds, soundPackChoices);
      expect(soundPackIds.first, Preferences.defaults.soundPack);
    });

    test('Ghostly has a file for every event, on disk and in the assets the app ships', () {
      final ghostly = soundPackOf('ghostly');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/sounds/ghostly/'));
      for (final event in SoundEvent.values) {
        for (final apple in [false, true]) {
          final asset = ghostly.asset(event, apple: apple)!;
          expect(asset, 'assets/sounds/ghostly/${event.id}.${apple ? 'caf' : 'ogg'}');
          expect(File(asset).existsSync(), isTrue, reason: asset);
          // A sound is a second or so, never a megabyte (the native halves refuse one that big).
          expect(File(asset).lengthSync(), lessThan(100 * 1024), reason: asset);
        }
      }
    });

    test('Off has none, and a pack this build does not have reads as Ghostly', () {
      expect(soundPackOf('off').silent, isTrue);
      expect(soundPackOf('off').asset(SoundEvent.todoTicked, apple: false), isNull);
      expect(soundPackOf('paper').id, 'ghostly');
    });

    test('only the recorder’s start and stop and the to-do’s tick are on until switched', () {
      expect({for (final event in SoundEvent.values) if (event.on) event}, {SoundEvent.todoTicked, SoundEvent.recordStart, SoundEvent.recordStop});
      for (final event in SoundEvent.values) {
        expect(soundEventOn(Preferences.defaults, event), event.on, reason: event.id);
        expect(SoundEvent.byId(event.id), event);
      }
    });
  });

  group('the preferences', () {
    test('default to Ghostly, sounds in the app on, three quarters loud, nothing switched', () {
      const d = Preferences.defaults;
      expect((d.soundPack, d.interfaceSounds, d.soundVolume), ('ghostly', true, 0.75));
      expect(d.soundEvents, isEmpty);
      expect(soundVolumes, contains(d.soundVolume));
    });

    test('go to JSON and back as they were', () {
      final chosen = Preferences.defaults.copyWith(soundPack: 'off', interfaceSounds: false, soundVolume: 0.25, soundEvents: {'all-ticked': true, 'todo-ticked': false});
      final json = chosen.toJson();
      expect((json['soundPack'], json['interfaceSounds'], json['soundVolume']), ('off', false, 0.25));
      expect(json['soundEvents'], {'all-ticked': true, 'todo-ticked': false});
      final back = Preferences.fromJson(json);
      expect(back, chosen);
      expect(soundEventOn(back, SoundEvent.allTicked), isTrue);
      expect(soundEventOn(back, SoundEvent.todoTicked), isFalse);
      // A whole volume is written as JavaScript would, 1 and not 1.0.
      expect(Preferences.defaults.copyWith(soundVolume: 1).toJson()['soundVolume'], 1);
    });

    test('read anything they cannot use as the defaults', () {
      final read = Preferences.fromJson({'soundPack': 'paper', 'interfaceSounds': 'yes', 'soundVolume': 0.3, 'soundEvents': {'saved': 'on', 'failed': true}});
      expect((read.soundPack, read.interfaceSounds, read.soundVolume), ('ghostly', true, 0.75));
      expect(read.soundEvents, {'failed': true});
      expect(Preferences.fromJson({'soundVolume': 1}).soundVolume, 1.0);
    });

    test('the pack, the switch and each event travel; the volume stays on this device', () {
      expect(syncedPrefs, containsAll(['soundPack', 'interfaceSounds', 'soundEvents']));
      expect(syncedPrefs, isNot(contains('soundVolume')));
    });
  });

  test('Android’s notifications take the pack’s sound for the notification events switched on, whatever the interface switch says', () {
    expect(notificationSounds(Preferences.defaults).pack, 'ghostly');
    expect(notificationSounds(Preferences.defaults).events, isEmpty);
    final on = Preferences.defaults.copyWith(interfaceSounds: false, soundEvents: {'writeup-ready': true, 'reminder-due': true, 'todo-ticked': true});
    expect(notificationSounds(on).events, ['writeup-ready', 'reminder-due']);
    expect(notificationSounds(on.copyWith(soundPack: 'off')).events, isEmpty);
  });

  group('a sound is heard', () {
    late PreferencesStore prefs;
    late HeardOutput output;
    late Sounds made;

    setUp(() {
      prefs = PreferencesStore()..startWithoutStorage();
      output = HeardOutput();
      made = heardSounds(output, prefs: prefs);
    });

    Future<void> turns() => Future<void>.delayed(Duration.zero);

    test('when its switch is on, at the volume, primed once', () async {
      made.play(SoundEvent.todoTicked);
      await turns();
      made.play(SoundEvent.todoTicked);
      await turns();
      expect(output.events, ['todo-ticked', 'todo-ticked']);
      expect(output.played.first.volume, 0.75);
      expect(output.primed, ['assets/sounds/ghostly/todo-ticked.ogg']);
    });

    test('not when its switch is off, nor with sounds in the app off, nor in the pack that is Off', () async {
      made.play(SoundEvent.allTicked);
      prefs.update((now) => now.copyWith(soundEvents: {'todo-ticked': false}));
      made.play(SoundEvent.todoTicked);
      prefs.update((now) => now.copyWith(soundEvents: const {}, interfaceSounds: false));
      made.play(SoundEvent.todoTicked);
      prefs.update((now) => now.copyWith(interfaceSounds: true, soundPack: 'off'));
      made.play(SoundEvent.recordStart);
      await turns();
      expect(output.played, isEmpty);
    });

    test('not during a recording, but for the recorder’s own start and stop', () async {
      made.recording = true;
      prefs.update((now) => now.copyWith(soundEvents: {'failed': true}));
      made.play(SoundEvent.todoTicked);
      made.play(SoundEvent.failed);
      made.play(SoundEvent.recordStart);
      made.play(SoundEvent.recordStop);
      made.preview(SoundEvent.todoTicked);
      await turns();
      expect(output.events, ['record-start', 'record-stop']);
      expect(output.played.every((play) => play.whileRecording), isTrue);
    });

    test('in a preview whatever its switch says, in the pack asked for', () async {
      prefs.update((now) => now.copyWith(interfaceSounds: false, soundEvents: {'saved': false}));
      made.preview(SoundEvent.saved);
      made.preview(SoundEvent.saved, pack: 'off');
      await turns();
      expect(output.events, ['saved']);
    });

    test('Apple’s files on the Mac', () async {
      final mac = Sounds(prefs: prefs, output: output, load: (_) async => throw StateError('none'), apple: true);
      mac.play(SoundEvent.todoTicked);
      await turns();
      // A file that will not load plays nothing, and says nothing.
      expect(output.played, isEmpty);
      expect(soundPackOf('ghostly').asset(SoundEvent.todoTicked, apple: true), endsWith('.caf'));
    });

    test('warm primes what is on, and nothing where there is no player', () async {
      await made.warm();
      expect(output.primed.toSet(), {for (final event in SoundEvent.values) if (event.on) 'assets/sounds/ghostly/${event.id}.ogg'});
      final silent = Sounds(prefs: prefs, useDefaultOutput: false);
      silent.play(SoundEvent.todoTicked);
      await silent.warm();
    });
  });
}
