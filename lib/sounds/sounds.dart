/// The app's sounds, played (Matt, 2026-10-27: "build ... the sounds settings"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md,
/// Sounds): one object the app's hooks call with an event, which decides whether it is heard and hands the pack's file
/// to the device's player.
///
/// Whether a sound is heard, in order:
/// - the pack has a file for it (Off has none);
/// - the event's own switch is on (`Preferences.soundEvents`, or the event's default);
/// - sounds inside the app are on (`Preferences.interfaceSounds`);
/// - nothing is recording, unless it is the recorder's own start or stop ([recording]): a chime in the middle of a take
///   would be in its tape and in its words;
/// - and the device itself allows it, which the native half decides as it plays: on Android the ringer is on, Do Not
///   Disturb is off, there is no call, and no other recording is open (a meeting's service, another app's); on the
///   Mac nothing more is readable, and it plays.
///
/// The player is a small native channel of the app's own, `ghost_md/sounds` (android/…/ghost_md/Sounds.kt, a
/// `SoundPool`; macos/Runner/SoundsChannel.swift, `AVAudioPlayer`), not a package: the app already plays its tapes
/// over channels of its own (lib/tapes/phone_player.dart). A sound's file is read from the app's assets here and
/// handed over once (`prime`), and kept by the native half under its key, so every later play is the pool's or the
/// player's alone, with no lag. Where there is no native half (the web, the iPhone for now, a test) a play is
/// nothing, quietly.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:glacier/glacier.dart' show GlacierToastProvider, GlacierToastTone;

import '../core/preferences.dart' as core show preferences;
import '../core/preferences.dart' show Preferences, PreferencesStore;
import 'sound_pack.dart';

/// Whether [event]'s switch is on in [prefs]: as it was switched, or its default.
bool soundEventOn(Preferences prefs, SoundEvent event) => prefs.soundEvents[event.id] ?? event.on;

/// The events that may sound while a recording runs: the recorder's own, which are what tell a person it began and
/// ended.
const Set<SoundEvent> soundsWhileRecording = {SoundEvent.recordStart, SoundEvent.recordStop};

/// The device's player, as [Sounds] asks it.
abstract class SoundOutput {
  /// Keeps [bytes] under [key], ready to play at once. Asked once per key.
  Future<void> prime(String key, Uint8List bytes);

  /// Plays what [key] holds at [volume] (0 to 1). [whileRecording] lets the recorder's own sounds past the device's
  /// check for an open recording. Answers whether it was played.
  Future<bool> play(String key, double volume, {bool whileRecording = false});
}

/// [SoundOutput] over the app's `ghost_md/sounds` channel.
class ChannelSoundOutput implements SoundOutput {
  const ChannelSoundOutput([this.channel = const MethodChannel('ghost_md/sounds')]);

  final MethodChannel channel;

  @override
  Future<void> prime(String key, Uint8List bytes) => channel.invokeMethod<void>('prime', {'key': key, 'bytes': bytes});

  @override
  Future<bool> play(String key, double volume, {bool whileRecording = false}) async =>
      await channel.invokeMethod<bool>('play', {'key': key, 'volume': volume, 'whileRecording': whileRecording}) ?? false;
}

/// The device's player where this build has one: Android and the Mac. Null elsewhere, and a play is nothing.
SoundOutput? defaultSoundOutput() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.macOS => const ChannelSoundOutput(),
    _ => null,
  };
}

/// Whether the device's player reads Apple's files (`.caf`) rather than Android's (`.ogg`).
bool get _apple => !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS);

class Sounds {
  Sounds({PreferencesStore? prefs, SoundOutput? output, bool useDefaultOutput = true, Future<ByteData> Function(String asset)? load, bool? apple})
      : _prefs = prefs,
        output = output ?? (useDefaultOutput ? defaultSoundOutput() : null),
        _load = load ?? rootBundle.load,
        apple = apple ?? _apple;

  final PreferencesStore? _prefs;

  /// The player; null where there is none.
  final SoundOutput? output;
  final Future<ByteData> Function(String asset) _load;

  /// Which files are played: `.caf` or `.ogg`.
  final bool apple;

  /// Set by the recorder while it has the microphone (lib/capture/ui/capture_screen.dart): nothing sounds but its own
  /// start and stop.
  bool recording = false;

  /// The keys handed to the player, each primed once; a prime that failed is tried again on the next play.
  final Map<String, Future<bool>> _primed = {};

  Preferences get _now => (_prefs ?? core.preferences).value;

  /// Whether [event] would be heard now, by the app's own rules (the device's are the native half's).
  bool wants(SoundEvent event) {
    final prefs = _now;
    if (soundPackOf(prefs.soundPack).asset(event, apple: apple) == null) return false;
    if (!prefs.interfaceSounds || !soundEventOn(prefs, event)) return false;
    return !recording || soundsWhileRecording.contains(event);
  }

  /// Plays [event] if it [wants] to be heard. Never throws, never waits on anyone: a hook calls it and goes on.
  void play(SoundEvent event) {
    if (!wants(event)) return;
    final prefs = _now;
    unawaited(_play(soundPackOf(prefs.soundPack), event, prefs.soundVolume));
  }

  /// Settings' preview: [event] in [pack], whatever its switch and the interface switch say, since the person asked to
  /// hear it. Not over a recording, all the same.
  void preview(SoundEvent event, {String? pack}) {
    if (recording) return;
    unawaited(_play(soundPackOf(pack ?? _now.soundPack), event, _now.soundVolume));
  }

  /// Has the player ready for every event that is on, so even the first tick plays at once. Asked as the app opens
  /// and when the pack changes; cheap to ask again.
  Future<void> warm() async {
    final prefs = _now;
    final pack = soundPackOf(prefs.soundPack);
    for (final event in SoundEvent.values) {
      if (!soundEventOn(prefs, event)) continue;
      final asset = pack.asset(event, apple: apple);
      if (asset != null) await _prime(asset);
    }
  }

  Future<void> _play(SoundPack pack, SoundEvent event, double volume) async {
    final output = this.output;
    final asset = pack.asset(event, apple: apple);
    if (output == null || asset == null) return;
    try {
      if (!await _prime(asset)) return;
      await output.play(asset, volume.clamp(0, 1).toDouble(), whileRecording: soundsWhileRecording.contains(event));
    } catch (_) {
      // A sound that cannot be played is not worth a word: the app goes on in silence.
    }
  }

  Future<bool> _prime(String asset) {
    final output = this.output;
    if (output == null) return Future.value(false);
    return _primed[asset] ??= () async {
      try {
        // A turn first, so a load that throws at once still finds this future in the map to take out.
        await Future<void>.value();
        final data = await _load(asset);
        await output.prime(asset, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        return true;
      } catch (_) {
        // Tried again on the next play.
        _primed.remove(asset);
        return false;
      }
    }();
  }
}

/// The app's sounds. A test puts its own in place and back.
Sounds sounds = Sounds();

/// What Android's notifications sound like (android/…/ghost_md/SoundChannels.kt): the pack, and the notification
/// events whose switch is on, which post on that pack's channel; the rest keep the phone's own sound. The interface
/// switch has no say here: it is the sounds inside the app.
({String pack, List<String> events}) notificationSounds(Preferences prefs) {
  final pack = soundPackOf(prefs.soundPack);
  return (
    pack: pack.id,
    events: [
      for (final event in SoundEvent.values)
        if (event.place == SoundPlace.notification && pack.asset(event, apple: false) != null && soundEventOn(prefs, event)) event.id,
    ],
  );
}

/// Tells the phone [notificationSounds], kept there for a reminder or a write-up that arrives with no Dart running.
Future<void> _tellNotifications(Preferences prefs) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final chosen = notificationSounds(prefs);
  try {
    await const MethodChannel('ghost_md/sounds').invokeMethod<void>('notifications', {'pack': chosen.pack, 'events': chosen.events});
  } catch (_) {
    // A binary from before the channel: the notifications keep the phone's sound.
  }
}

/// As the app opens, once the preferences are read: the player made ready for what is on, and the phone told which
/// notifications have the pack's sound, and both again whenever the pack or a switch changes; and a failure's sound
/// under every toast that says something failed, the one place the app's failures are all said (the kit's toast,
/// [GlacierToastProvider.onShown]).
void startSounds() {
  unawaited(sounds.warm());
  unawaited(_tellNotifications(core.preferences.value));
  var heard = (core.preferences.value.soundPack, core.preferences.value.soundEvents);
  core.preferences.addListener(() {
    final now = (core.preferences.value.soundPack, core.preferences.value.soundEvents);
    if (now == heard) return;
    heard = now;
    unawaited(sounds.warm());
    unawaited(_tellNotifications(core.preferences.value));
  });
  GlacierToastProvider.onShown = (tone) {
    if (tone == GlacierToastTone.danger) sounds.play(SoundEvent.failed);
  };
}
