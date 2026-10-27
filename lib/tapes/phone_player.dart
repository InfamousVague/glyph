/// The phone's player of a note's recording: the [TapePlayer] lib/tapes/player.dart is written against, over the
/// Kotlin `MediaPlayer` in android/…/ghost_md/TapePlayer.kt. What the page's `<audio>` element over the `rec`
/// scheme was to `src/app/tapes/useTape.ts`.
///
/// Made by whoever wires the app and let go with it; a [Tape] loads its note's recording into it by the note's id,
/// at the first Play, so a tape nobody plays asks the phone for nothing. The app makes two: the tape's, and with
/// [PhoneTapePlayer.clips] the voice memos' own on a channel of its own (`ghost_md/clip`), as the page made an
/// `<audio>` for a memo beside the tape's (`src/app/editor/clips.ts`). The Mac has a few more, with
/// [PhoneTapePlayer.preview], for the cassettes on the home page's shelf (lib/tapes/previews.dart).
///
/// A memo's player also plays a whole sound that is not a note's recording ([loadArguments]): a sound file in a note,
/// `file:<name>` (a voice-over among them, lib/plugins/elevenlabs/voice_over.dart), from the files' folder, and a
/// sound kept in the app's cache, `cached:<name>` (an ElevenLabs voice's preview). The phone's half takes only a
/// name that is a file's name there, never a path.
///
/// What differs: the element's five events are the channel's four (`position`, `playing`, `ended`, `failed`); a
/// file that is not on this device is the channel's `onDevice`, where the scheme answered a HEAD with 404. Off
/// Android there is no phone half: loading throws, and whether a recording is here is not known.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/attachment_refs.dart' show attachmentName;
import 'player.dart';

/// What `load` asks the phone's half for [src]: a note's recording by its id, a note's sound file (`file:<name>`), or
/// a sound in the app's cache (`cached:<name>`). A name that is not a kept file's name is asked as nothing the half
/// will open.
Map<String, String> loadArguments(String src) {
  for (final (lead, argument) in const [('file:', 'file'), ('cached:', 'cached')]) {
    if (!src.startsWith(lead)) continue;
    final name = src.substring(lead.length);
    return {argument: attachmentName.hasMatch(name) ? name : ''};
  }
  return {'noteId': src};
}

class PhoneTapePlayer implements TapePlayer {
  PhoneTapePlayer({MethodChannel channel = const MethodChannel('ghost_md/tape'), EventChannel events = const EventChannel('ghost_md/tape/events')}) : _channel = channel {
    // A browser has no phone half to hear from (lib/web, docs/WEB.md): nothing is listened for, and a load throws.
    if (!kIsWeb) _heard = events.receiveBroadcastStream().listen(_said, onError: (Object _) {});
  }

  /// The player a voice memo is played on: the phone's second, which the tape's knows nothing of.
  PhoneTapePlayer.clips() : this(channel: const MethodChannel('ghost_md/clip'), events: const EventChannel('ghost_md/clip/events'));

  /// One of the Mac's players kept for the home page's shelf ([slot] 0 to `tapePreviewsMost` - 1;
  /// lib/tapes/previews.dart): a cassette's tape loaded ahead, so a resting mouse only has to press Play.
  PhoneTapePlayer.preview(int slot) : this(channel: MethodChannel('ghost_md/preview/$slot'), events: EventChannel('ghost_md/preview/$slot/events'));

  final MethodChannel _channel;
  StreamSubscription<Object?>? _heard;

  final ValueNotifier<int> _position = ValueNotifier<int>(0);
  final ValueNotifier<int?> _duration = ValueNotifier<int?>(null);
  final ValueNotifier<bool> _playing = ValueNotifier<bool>(false);
  final StreamController<TapeEvent> _events = StreamController<TapeEvent>.broadcast(sync: true);

  void _said(Object? event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'position':
        _position.value = (event['ms'] as num?)?.toInt() ?? _position.value;
      case 'playing':
        _playing.value = event['on'] == true;
      case 'ended':
        _playing.value = false;
        if (!_events.isClosed) _events.add(TapeEvent.ended);
      case 'failed':
        _playing.value = false;
        if (!_events.isClosed) _events.add(TapeEvent.failed);
    }
  }

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
    _playing.value = false;
    _position.value = 0;
    _duration.value = null;
    _duration.value = await _channel.invokeMethod<int>('load', loadArguments(noteId));
  }

  @override
  Future<void> play() => _channel.invokeMethod<void>('play');

  @override
  Future<void> pause() => _channel.invokeMethod<void>('pause');

  @override
  Future<void> seek(int ms) async {
    await _channel.invokeMethod<void>('seek', {'ms': ms});
    _position.value = ms;
  }

  @override
  Future<bool?> onDevice(String noteId) async {
    try {
      return await _channel.invokeMethod<bool>('onDevice', {'noteId': noteId});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> release() async {
    _playing.value = false;
    _position.value = 0;
    _duration.value = null;
    await _channel.invokeMethod<void>('release');
  }

  @override
  void dispose() {
    unawaited(_heard?.cancel());
    unawaited(_channel.invokeMethod<void>('release').then<void>((_) {}, onError: (Object _) {}));
    unawaited(_events.close());
  }
}
