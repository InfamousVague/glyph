/// Where the notes' attachments are on this device, as the core says (`attachment_places`, native/src/dispatch.rs;
/// the rule is tauri/src-tauri/src/library/attachments.rs): for each kind, the folders it is read from, the first
/// the one written to. The pictures live under the library now (`Library/image/`, the path the notes link) and are
/// still read from the old folder beside it (`images/`); the files, films and recordings are still beside it, their
/// folder under the library only read. Dart reads two things by a path of its own, the words read in a picture or
/// a file (lib/files/read_text.dart) and whether a picture is here (lib/files/files_kit.dart), so it asks the core
/// where to look rather than keep the rule twice.
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

  /// The core's answer, or the old folders where the core has none to give (a core before the command, a web build).
  static Future<AttachmentPlaces> ask(CoreInvoke invoke, {required String dataDir}) async {
    try {
      final said = await invoke('attachment_places');
      if (said is Map) {
        final places = AttachmentPlaces.fromJson(said);
        if (places.whole) return places;
      }
    } catch (failure) {
      debugPrint('[files] where the attachments are was not answered, so the old folders are read: $failure');
    }
    return AttachmentPlaces.legacy(dataDir);
  }

  @override
  bool operator ==(Object other) =>
      other is AttachmentPlaces && listEquals(other.image, image) && listEquals(other.file, file) && listEquals(other.video, video) && listEquals(other.recording, recording);

  @override
  int get hashCode => Object.hash(Object.hashAll(image), Object.hashAll(file), Object.hashAll(video), Object.hashAll(recording));

  @override
  String toString() => 'AttachmentPlaces(image: $image, file: $file, video: $video, recording: $recording)';
}
