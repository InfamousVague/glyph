/// Where the notes' attachments are on this device, as the core says (`attachment_places`, native/src/dispatch.rs;
/// the rule is tauri/src-tauri/src/library/attachments.rs): for each kind, the folders it is read from, the first
/// the one written to. Every kind lives under the library now (`Library/image/`, `Library/file/`, `Library/video/`,
/// `Library/recordings/`, the paths the notes link; 2026-10-31) and is still read from the old folder beside it
/// (`images/`, `images/files/`, `video/`, `recordings/`), where an older build or the phone's meeting service left
/// a file. Dart reads by a path of its own in four places, and each asks here rather than keep the rule twice: the
/// words read in a picture or a file (lib/files/read_text.dart), the files notes link (lib/files/attachment_store.dart),
/// whether a picture is here (lib/files/files_kit.dart), and the phone's and the Mac's players, which are handed the
/// folders with each load (lib/tapes/phone_player.dart, lib/core/phone_films.dart; TapePlayer.kt, FilmPlayer.kt,
/// TapeChannel.swift).
library;

import 'package:flutter/foundation.dart';

import '../core/native/core.dart';

/// The folders each kind of attachment is read from, the first the one written to.
@immutable
class AttachmentPlaces {
  const AttachmentPlaces({required this.image, required this.file, required this.video, required this.recording});

  /// The folders every build before 2.3.94 used, beside the library under the app's data: what is read until the
  /// core has answered, and all there is on a device whose core has no `attachment_places` yet.
  AttachmentPlaces.legacy(String dataDir)
      : image = ['$dataDir/images'],
        file = ['$dataDir/images/files'],
        video = ['$dataDir/video'],
        recording = ['$dataDir/recordings'];

  factory AttachmentPlaces.fromJson(Map<Object?, Object?> json) {
    List<String> dirs(String key) => json[key] is List ? (json[key] as List).whereType<String>().toList() : const <String>[];
    return AttachmentPlaces(image: dirs('image'), file: dirs('file'), video: dirs('video'), recording: dirs('recording'));
  }

  final List<String> image;
  final List<String> file;
  final List<String> video;
  final List<String> recording;

  /// Whether every kind has somewhere to be written: an answer with a kind missing is no answer.
  bool get whole => image.isNotEmpty && file.isNotEmpty && video.isNotEmpty && recording.isNotEmpty;

  /// The last answer [ask] gave on this device (the core's, or the old folders), for whatever needs the folders
  /// without a core in hand; null before anything has asked, and in a test that set none.
  static AttachmentPlaces? current;

  /// How to ask the core again, remembered by [ask]: a library moved to another folder since the launch has other
  /// folders, so a player asks at each load ([now]) rather than keep the launch's answer.
  static Future<AttachmentPlaces> Function()? _again;

  /// The core's answer, or the old folders where the core has none to give (a core before the command, a web build).
  static Future<AttachmentPlaces> ask(CoreInvoke invoke, {required String dataDir}) async {
    _again = () => ask(invoke, dataDir: dataDir);
    var places = AttachmentPlaces.legacy(dataDir);
    try {
      final said = await invoke('attachment_places');
      if (said is Map) {
        final answered = AttachmentPlaces.fromJson(said);
        if (answered.whole) places = answered;
      }
    } catch (failure) {
      debugPrint('[files] where the attachments are was not answered, so the old folders are read: $failure');
    }
    return current = places;
  }

  /// The folders as the core has them now: asked again where [ask] has been called once (so a library moved since is
  /// followed), else whatever [current] is (a test's, or null where nothing has asked).
  static Future<AttachmentPlaces?> now() async => _again == null ? current : await _again!();

  /// Forgets what [ask] remembered: for a test.
  @visibleForTesting
  static void forget() {
    current = null;
    _again = null;
  }

  @override
  bool operator ==(Object other) =>
      other is AttachmentPlaces && listEquals(other.image, image) && listEquals(other.file, file) && listEquals(other.video, video) && listEquals(other.recording, recording);

  @override
  int get hashCode => Object.hash(Object.hashAll(image), Object.hashAll(file), Object.hashAll(video), Object.hashAll(recording));

  @override
  String toString() => 'AttachmentPlaces(image: $image, file: $file, video: $video, recording: $recording)';
}
