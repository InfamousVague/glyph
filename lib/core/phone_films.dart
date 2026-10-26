/// A film chosen on the phone and kept, and a kept film played: the [FilmPicker] and the [FilmDevice] over the
/// channels `ghost_md/films` and `ghost_md/film` (Kotlin's `Films` and `FilmPlayer`) and the core's files. Ports
/// `pickVideo` of `src/app/core/videos.ts`, and stands for the page's `<video>` over its `vid` scheme.
///
/// The phone's half opens the Photo Picker and answers with the film copied into its cache and its poster beside
/// it (the page's `video` event), having said `copying` first; the core then adopts both under fresh names
/// (`save_video`), which are the names the note's line carries, or throws them away for a note that was left
/// meanwhile (`discard_picked`).
///
/// A film plays in a texture of Flutter's that the phone's `MediaPlayer` draws into: [PhoneFilm] is one film open,
/// told where it has got to on the channel's events. A texture that does not turn a film filmed on its side (the
/// engine's on Vulkan) says how far the app must turn it, and [PhoneFilm.surface] does.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'films.dart';
import 'native/core.dart';

/// The channel the phone's video picker answers on, and says `copying` on.
const MethodChannel filmsChannel = MethodChannel('ghost_md/films');

/// The channel a film is played through, and where it says how far it has got.
const MethodChannel filmChannel = MethodChannel('ghost_md/film');
const EventChannel filmEvents = EventChannel('ghost_md/film/events');

/// Lets the person pick a film with the phone's picker and keeps it through the core (`pickVideo`). [kept] is told
/// the film's name once it is here.
FilmPicker phoneFilmPicker(CoreInvoke invoke, {MethodChannel channel = filmsChannel, void Function(String video)? kept}) {
  // The one pick waiting for its film (`pending`): the phone's answer does not say which pick it is for.
  var pending = false;
  VoidCallback? toldCopying;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'copying') toldCopying?.call();
  });

  // Throws away a film and its poster the phone copied, which no note will name (`discard`).
  void discard(String path, String poster) {
    for (final each in <String>[path, poster]) {
      unawaited(invoke('discard_picked', <String, Object?>{'path': each}).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  return ({bool Function()? keep, VoidCallback? copying}) async {
    if (pending) throw StateError(stillAdding);
    pending = true;
    toldCopying = copying;
    final Map<String, Object?>? answer;
    try {
      answer = await channel.invokeMapMethod<String, Object?>('pick');
    } on MissingPluginException {
      throw StateError(cannotAddVideos);
    } on PlatformException catch (failure) {
      throw StateError(failure.message ?? 'The video picker did not open.');
    } finally {
      pending = false;
      toldCopying = null;
    }
    if (answer == null || answer['cancelled'] == true) return null;
    final path = answer['path'], poster = answer['poster'];
    if (path is! String || poster is! String) throw StateError('This video can’t be read.');
    if (keep != null && !keep()) {
      discard(path, poster);
      return null;
    }
    double number(Object? value) => value is num && value.isFinite && value > 0 ? value.toDouble() : 0;
    final Map<Object?, Object?> saved;
    try {
      saved = await invoke('save_video', <String, Object?>{'path': path, 'poster': poster}) as Map<Object?, Object?>;
    } on CoreError catch (failure) {
      throw StateError(failure.message);
    }
    final video = saved['video'] as String;
    kept?.call(video);
    return PickedVideo(video: video, poster: saved['poster'] as String, ms: number(answer['ms']).round(), width: number(answer['width']), height: number(answer['height']));
  };
}

/// This phone's films: whether one is here is the core's to say, and one is played by the phone's player.
class PhoneFilmDevice implements FilmDevice {
  PhoneFilmDevice(this._invoke, {MethodChannel channel = filmChannel, EventChannel events = filmEvents, bool? plays})
      : _channel = channel,
        _events = events,
        plays = plays ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final CoreInvoke _invoke;
  final MethodChannel _channel;
  final EventChannel _events;

  @override
  final bool plays;

  /// The films open now, by their texture, each told its own events.
  final Map<int, PhoneFilm> _open = <int, PhoneFilm>{};
  StreamSubscription<Object?>? _heard;

  /// The film playing now, anywhere in the app: starting another pauses it (the page's `playing`).
  PhoneFilm? _playing;

  void _said(Object? event) {
    if (event is! Map) return;
    final film = _open[(event['id'] as num?)?.toInt()];
    if (film == null) return;
    switch (event['event']) {
      case 'position':
        film._position.value = (event['ms'] as num?)?.toInt() ?? film._position.value;
      case 'playing':
        film._playing.value = event['on'] == true;
      case 'ended':
        film._playing.value = false;
      case 'failed':
        film._playing.value = false;
        film._failed.value = true;
    }
  }

  @override
  Future<bool> here(String video) async => await _invoke('file_exists', <String, Object?>{'kind': 'video', 'name': video}) as bool;

  @override
  Future<FilmPlaying> open(String video) async {
    _heard ??= _events.receiveBroadcastStream().listen(_said, onError: (Object _) {});
    final Map<String, Object?>? said;
    try {
      said = await _channel.invokeMapMethod<String, Object?>('open', <String, Object?>{'name': video});
    } on MissingPluginException {
      throw StateError('This video can’t be played on this phone.');
    } on PlatformException catch (failure) {
      throw StateError(failure.message ?? 'This video can’t be played on this phone.');
    }
    int number(String key) => (said?[key] as num?)?.toInt() ?? 0;
    final film = PhoneFilm._(this, number('id'), width: number('width'), height: number('height'), durationMs: number('ms'), turn: number('turn'));
    _open[film.id] = film;
    return film;
  }

  Future<void> _tell(String method, PhoneFilm film, [Map<String, Object?> more = const <String, Object?>{}]) =>
      _channel.invokeMethod<void>(method, <String, Object?>{'id': film.id, ...more}).then<void>((_) {}, onError: (Object _) {});
}

/// One film open on the phone's player.
class PhoneFilm implements FilmPlaying {
  PhoneFilm._(this._device, this.id, {required this.width, required this.height, required this.durationMs, required this.turn});

  final PhoneFilmDevice _device;

  /// The texture the film is drawn into.
  final int id;

  /// The film's size as it is stored, and the degrees the app must still turn it to stand it upright.
  final int width, height, turn;

  @override
  final int durationMs;

  final ValueNotifier<bool> _playing = ValueNotifier<bool>(false);
  final ValueNotifier<int> _position = ValueNotifier<int>(0);
  final ValueNotifier<bool> _failed = ValueNotifier<bool>(false);
  bool _closed = false;

  @override
  ValueListenable<bool> get playing => _playing;

  @override
  ValueListenable<int> get position => _position;

  @override
  ValueListenable<bool> get failed => _failed;

  @override
  Widget surface() {
    final w = width > 0 ? width.toDouble() : 16.0, h = height > 0 ? height.toDouble() : 9.0;
    final frames = SizedBox(width: w, height: h, child: Texture(textureId: id));
    // 'object-fit: contain', and a film filmed on its side stood upright where the texture has not.
    return FittedBox(child: turn % 360 == 0 ? frames : RotatedBox(quarterTurns: (turn ~/ 90) % 4, child: frames));
  }

  @override
  void play() {
    if (_closed) return;
    final other = _device._playing;
    if (other != null && !identical(other, this)) other.pause();
    _device._playing = this;
    unawaited(_device._tell('play', this));
  }

  @override
  void pause() {
    if (_closed) return;
    unawaited(_device._tell('pause', this));
  }

  @override
  void seek(int ms) {
    if (_closed) return;
    _position.value = ms;
    unawaited(_device._tell('seek', this, <String, Object?>{'ms': ms}));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _playing.value = false;
    if (identical(_device._playing, this)) _device._playing = null;
    _device._open.remove(id);
    unawaited(_device._tell('close', this));
  }
}
