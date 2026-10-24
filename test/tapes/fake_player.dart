/// The player the tapes' tests play through: a clock in place of the audio, as a browser had on the web
/// (`useTape.ts`, "The browser's stand-in for the audio: a clock"), so the words can follow a playhead with no phone
/// and no file. It ticks every 100 ms on the test's own clock, and says the recording ended when it reaches the
/// length it was told.
///
/// What differs: on the web the clock was inside the hook; here it is an implementation of the seam
/// (`lib/tapes/player.dart` [TapePlayer]) that lives with the tests, and it can be told to fail the ways a phone
/// does: a file that will not load, a Play that is refused, a recording that is not on this device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ghost_md/tapes/player.dart';

class FakeTapePlayer implements TapePlayer {
  FakeTapePlayer({this.lengths = const {}, this.loadFails = false, this.playFails, this.here = true});

  /// How long each note's recording is, by the note's id. A note not named has no recording to load.
  final Map<String, int> lengths;

  /// Loading throws, as for a file that is missing or cannot be read.
  bool loadFails;

  /// What Play throws, where it is refused.
  Object? playFails;

  /// What [onDevice] answers.
  bool? here;

  /// Every call made, in order: `load t`, `play`, `pause`, `seek 2000`, `release`, `dispose`.
  final List<String> calls = [];

  /// The note whose recording is loaded.
  String? loaded;

  final ValueNotifier<int> _position = ValueNotifier(0);
  final ValueNotifier<int?> _duration = ValueNotifier(null);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final StreamController<TapeEvent> _events = StreamController.broadcast(sync: true);
  Timer? _clock;

  @override
  ValueListenable<int> get position => _position;
  @override
  ValueListenable<int?> get duration => _duration;
  @override
  ValueListenable<bool> get playing => _playing;
  @override
  Stream<TapeEvent> get events => _events.stream;

  @override
  Future<void> load(String noteId) async {
    calls.add('load $noteId');
    _stop();
    if (loadFails || !lengths.containsKey(noteId)) throw StateError('no recording');
    loaded = noteId;
    _duration.value = lengths[noteId];
    _position.value = 0;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (playFails != null) throw playFails!;
    if (_playing.value) return;
    _playing.value = true;
    _clock = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = _position.value + 100;
      if (now >= (_duration.value ?? 0)) {
        _stop();
        _events.add(TapeEvent.ended);
      } else {
        _position.value = now;
      }
    });
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _stop();
  }

  @override
  Future<void> seek(int ms) async {
    calls.add('seek $ms');
    _position.value = ms;
  }

  @override
  Future<bool?> onDevice(String noteId) async => here;

  @override
  Future<void> release() async {
    calls.add('release');
    _stop();
    loaded = null;
    _duration.value = null;
    _position.value = 0;
  }

  /// The recording breaks while it plays (the element's `error`).
  void fail() {
    _stop();
    _events.add(TapeEvent.failed);
  }

  void _stop() {
    _clock?.cancel();
    _clock = null;
    _playing.value = false;
  }

  @override
  void dispose() {
    calls.add('dispose');
    _stop();
    unawaited(_events.close());
  }
}
