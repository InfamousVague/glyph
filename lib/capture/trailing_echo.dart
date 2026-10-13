/// Whisper's echo at the end of a recording: "…add eggs to Go. Go. Go." A port of `src/app/capture/trailingEcho.ts`
/// (the Tauri app's, from the voice work that followed 1.6; the Flutter app takes it up here).
///
/// When the audio after the last word is quiet, the model often says its last word or two again as sentences of
/// their own. "go. go" turned up on the end of notes, and the command reader took it for part of the last item.
///
/// A short sentence (three words or fewer) at the very end is dropped when it only repeats the words the sentence
/// before it ended with; when the sentence before is that same short sentence ("…Ohio. Go. Go."), both go. Repeated
/// as long as the end still echoes. Anything that says something new stays.
///
/// What differs: nothing but the shapes. [segmentsWithoutTrailingEcho] takes and answers `Segment`s
/// (lib/core/note.dart).
library;

import '../core/note.dart' show Segment;

const int _maxEchoWords = 3;

final RegExp _sentence = RegExp(r'[^.!?]+[.!?]*');
final RegExp _word = RegExp(r"[\p{L}\p{N}']+", unicode: true);

List<String> _wordsOf(String sentence) => [for (final match in _word.allMatches(sentence.toLowerCase())) match.group(0)!];

/// How many characters at the end of [text] are echo.
int trailingEchoLength(String text) {
  final sentences = [for (final match in _sentence.allMatches(text)) (at: match.start, text: match.group(0)!)];
  var end = text.length;
  while (sentences.length >= 2) {
    final last = sentences[sentences.length - 1];
    final before = sentences[sentences.length - 2];
    final echo = _wordsOf(last.text);
    final said = _wordsOf(before.text);
    if (echo.isEmpty || echo.length > _maxEchoWords || said.length < echo.length) break;
    var repeatsTheEnd = true;
    for (var i = 0; i < echo.length; i += 1) {
      if (echo[i] != said[said.length - echo.length + i]) repeatsTheEnd = false;
    }
    // "…Ohio. Go. Go.": the same short sentence twice at the very end is the echo itself, both of them.
    final repeated = said.length == echo.length && repeatsTheEnd;
    if (!repeatsTheEnd) break;
    end = repeated ? before.at : last.at;
    sentences.removeLast();
    if (repeated) sentences.removeLast();
  }
  return text.length - text.substring(0, end).trimRight().length;
}

/// [text] with its trailing echo taken off.
String withoutTrailingEcho(String text) {
  final cut = trailingEchoLength(text);
  return cut > 0 ? text.substring(0, text.length - cut) : text;
}

/// The phrases of a take with the echo taken off the last of them.
List<Segment> segmentsWithoutTrailingEcho(List<Segment> segments) {
  final joined = [for (final segment in segments) segment.text].join(' ');
  var cut = trailingEchoLength(joined);
  if (cut == 0) return [...segments];
  final kept = [...segments];
  while (cut > 0 && kept.isNotEmpty) {
    final last = kept.last;
    if (last.text.length <= cut) {
      kept.removeLast();
      // The space that joined it to the phrase before.
      cut -= last.text.length + 1;
    } else {
      kept[kept.length - 1] = Segment(startMs: last.startMs, endMs: last.endMs, text: last.text.substring(0, last.text.length - cut).trimRight());
      cut = 0;
    }
  }
  return kept;
}
