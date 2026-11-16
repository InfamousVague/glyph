import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';

/// The app's interface sounds (Matt, 2026-11-16: "Give me some elevenlabs prompts to generate sounds for the entire app
/// such as new friend requests, message inbount and outboud. connection and disconnection noises as well as mute and
/// unmute sounds they should all be cohesive"), made with ElevenLabs by tool/ui_sounds.py and picked by him: take 2 of
/// each, but Call ended 2, Code copied 3, Connected 2, Deafen 2 and Disconnected 1, and a choice of three for the
/// message sound and three for ringing ("give me the options to pick from for the calling and notification sounds").
///
/// Everything but ringing and a new message plays at a third of its loudness unless changed ("for most UI sounds
/// (outside of calling and new messages) play them at 33% volume by default"): Settings › Sounds.
///
/// The files are WAV in assets/sounds/, scaled here to the loudness wanted and handed to the device's own player on
/// "ghost/sound" (android Sounds.kt, macos Sounds.swift, windows sounds.cpp), so the phone, the Mac and Windows play
/// them alike. On Android a notification's sound is its channel's (Notifier.kt, notify_message_<n>.ogg): the choice
/// made here is the one it uses.
enum UiSound {
  messageIn('message-in'),
  messageOut('message-out'),
  messageFailed('message-failed'),
  reaction('reaction'),
  codeCopied('code-copied'),
  friendRequest('friend-request'),
  friendAccepted('friend-accepted'),
  groupAdded('group-added'),
  hangoutJoin('hangout-join'),
  hangoutLeave('hangout-leave'),
  someoneJoined('someone-joined'),
  someoneLeft('someone-left'),
  ringIn('ring-in'),
  ringOut('ring-out'),
  callEnded('call-ended'),
  mute('mute'),
  unmute('unmute'),
  deafen('deafen'),
  undeafen('undeafen'),
  connected('connected'),
  disconnected('disconnected'),
  reconnecting('reconnecting');

  const UiSound(this.file);
  final String file;

  /// Ringing and a new message: at their full loudness, and chosen from three.
  bool get loud => this == messageIn || this == ringIn;
}

/// One of the three choices for the message sound or for ringing.
class SoundChoice {
  const SoundChoice(this.id, this.label);
  final String id;
  final String label;
}

class Sounds {
  Sounds._();
  static final Sounds instance = Sounds._();

  static const _channel = MethodChannel('ghost/sound');

  /// The three message sounds and the three rings, by the take they are.
  static const messageChoices = [SoundChoice('1', 'Ripple'), SoundChoice('2', 'Glass'), SoundChoice('3', 'Breeze')];
  static const ringChoices = [SoundChoice('1', 'Chime'), SoundChoice('2', 'Lantern'), SoundChoice('3', 'Halo')];

  /// The loudness of every sound but ringing and a new message, unless changed: a third.
  static const quietDefault = 33;

  AppState? _app;
  final Map<String, Uint8List> _files = {};
  UiSound? _looping;

  void start(AppState app) => _app = app;

  bool get on => _app?.flag('sounds', fallback: true) ?? true;
  void setOn(bool v) => _app?.setFlag('sounds', v);

  String get message => _app?.choice('sound_message', '2') ?? '2';
  String get ring => _app?.choice('sound_ring', '2') ?? '2';

  /// The loudness of the quieter sounds, 0 to 100.
  int get quiet => int.tryParse(_app?.choice('sound_quiet', '$quietDefault') ?? '') ?? quietDefault;

  void setMessage(String id) {
    _app?.set('sound_message', id);
    unawaited(_play('message-in-$id', 1, loop: false));
  }

  void setRing(String id) {
    _app?.set('sound_ring', id);
    unawaited(_play('ring-in-$id', 1, loop: false));
  }

  void setQuiet(int v) => _app?.set('sound_quiet', '${v.clamp(0, 100)}');

  /// Played once, at its loudness.
  void play(UiSound s) {
    if (!on) return;
    unawaited(_play(_name(s), s.loud ? 1 : quiet / 100, loop: false));
  }

  /// Played over and over until [stopLoop] (ringing, in and out).
  void loop(UiSound s) {
    if (!on || _looping == s) return;
    _looping = s;
    unawaited(_play(_name(s), s.loud ? 1 : quiet / 100, loop: true));
  }

  void stopLoop([UiSound? only]) {
    if (_looping == null || (only != null && _looping != only)) return;
    _looping = null;
    unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
  }

  String _name(UiSound s) => switch (s) {
        UiSound.messageIn => 'message-in-$message',
        UiSound.ringIn => 'ring-in-$ring',
        _ => s.file,
      };

  Future<void> _play(String name, double volume, {required bool loop}) async {
    if (volume <= 0) return;
    try {
      final wav = _files[name] ??= (await rootBundle.load('assets/sounds/$name.wav')).buffer.asUint8List();
      await _channel.invokeMethod<void>('play', {'name': name, 'bytes': scaled(wav, volume), 'loop': loop});
    } catch (_) {
      // No player on this device, or no file: the app goes on quietly.
    }
  }

  /// [wav] (16-bit PCM) at [volume] of its loudness: the samples multiplied, so every device plays it alike.
  @visibleForTesting
  static Uint8List scaled(Uint8List wav, double volume) {
    if (volume >= 0.999) return wav;
    final out = Uint8List.fromList(wav);
    final data = ByteData.sublistView(out);
    // The chunks after the header: scale only what is in "data".
    var at = 12;
    while (at + 8 <= out.length) {
      final id = String.fromCharCodes(out.sublist(at, at + 4));
      final size = data.getUint32(at + 4, Endian.little);
      if (id == 'data') {
        final end = (at + 8 + size).clamp(0, out.length);
        for (var i = at + 8; i + 1 < end; i += 2) {
          data.setInt16(i, (data.getInt16(i, Endian.little) * volume).round().clamp(-32768, 32767), Endian.little);
        }
        break;
      }
      at += 8 + size + (size & 1);
    }
    return out;
  }
}
