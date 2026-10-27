import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/sounds/sounds.dart';

/// A player that keeps what it was asked: the keys primed and the plays, in order.
class HeardOutput implements SoundOutput {
  final List<String> primed = [];
  final List<({String key, double volume, bool whileRecording})> played = [];

  /// The events played, by their file's name: `record-start` for `assets/sounds/ghostly/record-start.ogg`.
  List<String> get events => [for (final play in played) play.key.split('/').last.split('.').first];

  @override
  Future<void> prime(String key, Uint8List bytes) async => primed.add(key);

  @override
  Future<bool> play(String key, double volume, {bool whileRecording = false}) async {
    played.add((key: key, volume: volume, whileRecording: whileRecording));
    return true;
  }
}

/// Sounds over [output], reading [prefs] (the app's own when null), whose files are a few bytes of nothing.
Sounds heardSounds(HeardOutput output, {PreferencesStore? prefs}) =>
    Sounds(prefs: prefs, output: output, load: (_) async => ByteData.sublistView(Uint8List.fromList(const [1, 2, 3])), apple: false);

/// Puts [made] in the app's place for the test, and the one it replaced back after ([tearDown] is the test's
/// `addTearDown`).
void useSounds(Sounds made, void Function(void Function() body) tearDown) {
  final was = sounds;
  sounds = made;
  tearDown(() => sounds = was);
}
