/// Films in notes, on the phone they were added on: a port of `src/app/core/videos.ts`.
///
/// A film is picked with the phone's Photo Picker (android/…/ghost_md/Films.kt), which copies it and makes its
/// poster, and kept by the core (`save_video`, native/src/kept/videos.rs): the film under `video/`, the poster
/// among the pictures. The note's line (video_refs.dart) names both. The card that draws it
/// (lib/editor/media/videos.dart) asks first whether the film is on this phone at all: a note synced from the
/// phone to another, or a phone reset since, has the poster and not the film.
///
/// What differs:
/// - **There is no native generation to ask.** The page arrived over the air on binaries older than the films, so
///   it asked which it ran on (`VIDEO_GENERATION`, `'update'`); this app is its binary, so a phone either has the
///   films ([Films]) or is another device, and nothing says "Update Ghost.md to play this video."
/// - **Nothing is served.** The page asked whether a film was here with a HEAD to its own `vid` scheme and played
///   it from there in a `<video>`. Here the core is asked ([FilmDevice.here], `file_exists`) and the film is played
///   by the phone's own player into a texture ([FilmPlaying], lib/core/phone_films.dart).
/// - `listenForVideos` and its answer nobody waited for (a film picked before the page reloaded) have nothing to
///   stand for: the call that asked is the one that is answered, and what a pick leaves in the cache with no one
///   to adopt it goes in the core's sweep of `picked/`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// What a person reads when they ask for a second film while the first is still being copied (`STILL_ADDING`).
const String stillAdding = 'A video is still being added.';

/// What a run with no phone half says (the page's bridge without `pickVideo`).
const String cannotAddVideos = 'Videos need the newest Ghost.md.';

/// A film picked and kept: its name, its poster's, its length and its size as it is watched (`PickedVideo`).
@immutable
class PickedVideo {
  const PickedVideo({required this.video, required this.poster, required this.ms, required this.width, required this.height});

  final String video;
  final String poster;
  final int ms;
  final double width;
  final double height;
}

/// Lets the person pick a film, keeps it, and answers it; null if they chose none, or if [keep] says it is no
/// longer wanted, when its copies are thrown away rather than kept for a note that will never name them
/// (`pickVideo`). [copying] is told once a film is chosen and its copy has started. One pick at a time: a second
/// while the first is still being copied throws [stillAdding]. Throws a [StateError] with the sentence a person
/// reads when it could not be read or kept.
typedef FilmPicker = Future<PickedVideo?> Function({bool Function()? keep, VoidCallback? copying});

/// A film open to play: what the page's `<video>` element was to its card.
abstract class FilmPlaying {
  /// The film's frames, at the film's own shape, for the card to lay over its poster.
  Widget surface();

  /// Whether it is playing now (the element's `play` and `pause`).
  ValueListenable<bool> get playing;

  /// How far it has played, in ms (`currentTime`), and its length (`duration`).
  ValueListenable<int> get position;
  int get durationMs;

  /// True once it would not play after all (the element's `error`).
  ValueListenable<bool> get failed;

  void play();
  void pause();
  void seek(int ms);

  /// Let go: paused, and the phone's player with it.
  void close();
}

/// What a device answers about films, and how it plays one.
abstract class FilmDevice {
  /// Whether films play here at all: an Android phone (`filmsPlay`'s `'phone'`).
  bool get plays;

  /// Whether the film named is on this device.
  Future<bool> here(String video);

  /// Opens the film named to play; throws where it cannot be.
  Future<FilmPlaying> open(String video);
}

/// The films of this device: the pick, and where each film stands, asked once and kept (`asked`).
class Films {
  Films({required this.device, this.pick});

  final FilmDevice device;

  /// The phone's picker; null where a film cannot be added (`canAddVideos`).
  final FilmPicker? pick;

  /// The answers kept for the app's life: whether a film is here does not change unasked.
  final Map<String, Future<bool>> _asked = <String, Future<bool>>{};

  /// Whether the film is on this phone, asked once (`filmIsHere`).
  Future<bool> isHere(String video) => _asked[video] ??= device.here(video).catchError((Object _) => false);

  /// A film just kept is here.
  void kept(String video) => _asked[video] = Future<bool>.value(true);

  /// A film that would not play after all: its card says so from now on (`filmGone`).
  void gone(String video) => _asked[video] = Future<bool>.value(false);

  /// Whether the film is on this phone now, asked afresh: a film that would not play is asked again before its
  /// card says it is gone, since a film the phone cannot decode is still here (`filmStillHere`).
  Future<bool> stillHere(String video) async {
    final here = await device.here(video).catchError((Object _) => false);
    if (!here) gone(video);
    return here;
  }
}
