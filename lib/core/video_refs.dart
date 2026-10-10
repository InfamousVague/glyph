/// A film written into a note's words: its poster, an ordinary picture, linked to the film, alone on its line. A
/// port of `src/app/core/videoRefs.ts`, one to one.
///
///     [![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)
///
/// The + beside the line writes one where the caret is (Matt: "add a menu to add things like geotag cards images
/// videos and more"), on the phone the film was picked on, and the editor draws the card under it. The alt text is
/// "video" and the length, as a voice memo's is (`![voice 0:08](tape:…)`), so any reader shows the still and the
/// length.
///
/// The poster is a picture like any other: the pictures' own pattern reads the inner `![video 0:12](image/…)`, so
/// sync, a share, the reader's download and a deleted note's clean-up carry it with no word about films. The film's
/// name is under `video/`, which no picture's pattern takes. It stays on its phone, so the owner's other devices and
/// a reader of a shared page see the still, each told so in words meant for them.
///
/// Only the words, and nothing that reaches a device.
///
/// What differs: the names. The web's `VIDEO_EXTENSIONS` and `VIDEO_REF` are [videoExtensions] and
/// [videoRefPattern]; `VideoLine` is a class with value equality.
library;

import 'item_syntax.dart' show jsTrim, lineWords;

/// The kinds of film a note names (`VIDEO_EXTENSIONS`). RUST TWIN: the web app's `src-tauri/src/videos.rs`
/// `EXTENSIONS`, which keeps them: a kind the phone keeps that the page does not name would be a film with no card.
const List<String> videoExtensions = ['mp4', 'm4v', 'mov', 'webm'];

final String _videoRef = '\\[!\\[([^\\]\\n]*)\\]\\(image\\/([A-Za-z0-9_.-]+)\\)\\]\\(video\\/([A-Za-z0-9_-]+\\.(?:${videoExtensions.join('|')}))\\)';

/// A film's reference in a body: the alt, the poster's name and the film's name, as groups 1 to 3 (`VIDEO_REF`).
final RegExp videoRefPattern = RegExp(_videoRef);

/// The one form a video line's words take.
final RegExp _videoWords = RegExp('^$_videoRef\$');

/// A film read from a line (`VideoLine`).
class VideoLine {
  const VideoLine({required this.poster, required this.video, required this.ms, required this.alt});

  /// The poster's name under `image/`.
  final String poster;

  /// The film's name under `video/`.
  final String video;

  /// Its length in ms, read back from the alt ("video 0:12"), or null where the alt does not say.
  final int? ms;

  /// The alt as written.
  final String alt;

  @override
  bool operator ==(Object other) => other is VideoLine && other.poster == poster && other.video == video && other.ms == ms && other.alt == alt;

  @override
  int get hashCode => Object.hash(poster, video, ms, alt);

  @override
  String toString() => 'VideoLine($poster, $video, $ms, $alt)';
}

/// The film a line is, or null: a line whose words, past its quote's markers and its list lead, are exactly one
/// reference.
VideoLine? videoOfLine(String text) {
  // A film's line has its poster's link closing on the film's, and almost no line does: asked first, since this is
  // asked of every line of a note and the patterns below are many times the cost of a search for seven letters.
  // (Nothing [lineWords] takes off a line can bring those seven together: each piece it takes ends at a space.)
  if (!text.contains('](video/')) return null;
  final found = _videoWords.firstMatch(lineWords(text));
  if (found == null) return null;
  final alt = found.group(1) ?? '';
  return VideoLine(poster: found.group(2) ?? '', video: found.group(3) ?? '', alt: alt, ms: lengthOf(alt));
}

/// "0:12", "12:04" or "1:02:03": a film's length as a person reads it. At least a second, for any film at all.
String lengthText(int ms) {
  final rounded = (ms / 1000).round();
  final least = ms > 0 ? 1 : 0;
  final total = rounded > least ? rounded : least;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

final RegExp _length = RegExp(r'(?:^|\s)(\d+):(\d{2})(?::(\d{2}))?$');

/// The length an alt says, "video 0:12" as 12000 ms, or null.
int? lengthOf(String alt) {
  final found = _length.firstMatch(jsTrim(alt));
  if (found == null) return null;
  final a = int.parse(found.group(1)!);
  final b = int.parse(found.group(2)!);
  final c = found.group(3);
  final seconds = c == null ? a * 60 + b : a * 3600 + b * 60 + int.parse(c);
  return seconds * 1000;
}

/// The line for a film: its poster linked to it, the alt its length.
String videoMarkdown(String poster, String video, int ms) => '[![video ${lengthText(ms)}](image/$poster)](video/$video)';

/// Every film a body names, in order, without repeats.
List<String> videoNames(String body) {
  final names = <String>{};
  for (final found in videoRefPattern.allMatches(body)) {
    final name = found.group(3) ?? '';
    if (name.isNotEmpty) names.add(name);
  }
  return names.toList();
}
