/// `{image: a prompt}`: an image asked for where it is written (Matt, 2026-10-26: "create images automatically based on
/// notes and with some custom inline syntax"). Pure: the note action (lovart.dart) finds the cues, asks Lovart, and
/// puts each picture where its cue was.
///
/// - **The cue.** `{image:` then the prompt, up to 500 characters on one line, then `}`; `Image` or `IMAGE` too. Not
///   after a `{`, a `$` or a backslash, and not closed by `}}`, as the blanks are not (lib/core/blanks_syntax.dart), so
///   `{{image: …}}` in a template stays a template's. It cannot be read as a blank, which begins `{?`. Not inside a
///   code fence or between backticks: code about the cue is not a cue.
/// - **The picture.** `![the prompt](image/<name>)`, the app's picture line (lib/core/images.dart). A cue on a line of
///   its own becomes the picture; a cue among words leaves the words, without it, and the picture goes on its own line
///   just after.
library;

import 'package:flutter/foundation.dart';

import '../../core/images.dart' show imageMarkdown;

/// The cue's pattern: [ImageCue.prompt] is its first group.
final RegExp imageCuePattern = RegExp(r'(?<![{\\$])\{image:[ \t]*([^{}\n]{1,500}?)[ \t]*\}(?!\})', caseSensitive: false);

final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// One `{image: …}` in a note.
@immutable
class ImageCue {
  const ImageCue({required this.prompt, required this.text, required this.from, required this.to, required this.line});

  /// What to make: the words between `{image:` and `}`, trimmed.
  final String prompt;

  /// The cue as written, braces and all.
  final String text;

  /// Where it is in the body: [from] to [to].
  final int from;
  final int to;

  /// Its line, 1-based.
  final int line;

  @override
  bool operator ==(Object other) => other is ImageCue && other.prompt == prompt && other.text == text && other.from == from && other.to == to && other.line == line;

  @override
  int get hashCode => Object.hash(prompt, text, from, to, line);

  @override
  String toString() => 'ImageCue($prompt, line $line, $from–$to)';
}

/// Whether [at] in [line] is between backticks: an odd number of them before it.
bool _inCode(String line, int at) => '`'.allMatches(line.substring(0, at)).length.isOdd;

/// Every cue in [body], in order.
List<ImageCue> imageCues(String body) {
  final out = <ImageCue>[];
  var offset = 0;
  var fenced = false;
  final lines = body.split('\n');
  for (final (index, line) in lines.indexed) {
    if (_fence.hasMatch(line)) {
      fenced = !fenced;
    } else if (!fenced) {
      for (final match in imageCuePattern.allMatches(line)) {
        final prompt = match[1]!.trim();
        if (prompt.isEmpty || _inCode(line, match.start)) continue;
        out.add(ImageCue(prompt: prompt, text: match[0]!, from: offset + match.start, to: offset + match.end, line: index + 1));
      }
    }
    offset += line.length + 1;
  }
  return out;
}

/// A prompt as a picture's caption: one line, no brackets that would end it, at most 120 characters.
String pictureCaption(String prompt) {
  final flat = prompt.replaceAll(RegExp(r'[\[\]\n\r]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 120 ? flat : '${flat.substring(0, 119).trimRight()}…';
}

final RegExp _pictureLine = RegExp(r'^\s*!\[[^\]]*\]\(image/[A-Za-z0-9_.-]+\)\s*$');

/// The edits that make the cue [cue] of [body] into the pictures [names], each a whole line's new text by its 1-based
/// number, the last line first so the numbers hold as they are made. A cue that is all its line holds (behind a
/// list's or a quote's marker, kept) becomes the pictures; a cue among words leaves the words without it, and the
/// pictures go on lines of their own after it, after any pictures already there (an earlier cue's on that line), so
/// several cues on a line keep their order. Empty where the cue is no longer on its line.
List<({int line, String text})> cueEdits(String body, ImageCue cue, List<String> names) {
  final lines = body.split('\n');
  var n = cue.line;
  if (n < 1 || n > lines.length || !lines[n - 1].contains(cue.text)) {
    n = lines.indexWhere((l) => l.contains(cue.text)) + 1;
    if (n == 0) return const [];
  }
  final line = lines[n - 1];
  final at = line.indexOf(cue.text);
  final pictures = [for (final name in names) imageMarkdown(name, pictureCaption(cue.prompt))];
  final before = line.substring(0, at), after = line.substring(at + cue.text.length);
  final marker = RegExp(r'^(\s*(?:[-*+]\s+|\d+[.)]\s+|>\s*)?)$').firstMatch(before);
  if (after.trim().isEmpty && marker != null) {
    return [(line: n, text: [for (final (i, p) in pictures.indexed) i == 0 ? '${marker[1]}$p' : p].join('\n'))];
  }
  final rest = (before + after).replaceAll(RegExp(r'[ \t]{2,}'), ' ').trimRight();
  var last = n;
  while (last < lines.length && _pictureLine.hasMatch(lines[last])) {
    last += 1;
  }
  if (last == n) return [(line: n, text: [rest, ...pictures].join('\n'))];
  return [(line: last, text: [lines[last - 1], ...pictures].join('\n')), (line: n, text: rest)];
}

/// [body] with [cue] made into the pictures [names] (several where Lovart made several).
String withImages(String body, ImageCue cue, List<String> names) {
  final lines = body.split('\n');
  for (final edit in cueEdits(body, cue, names)) {
    lines[edit.line - 1] = edit.text;
  }
  return lines.join('\n');
}

/// [body] with [cue] made into the picture [name].
String withImage(String body, ImageCue cue, String name) => withImages(body, cue, [name]);

/// What a cue's prompt is sent to Lovart as: the words, and that one image is wanted, since Lovart takes no count but
/// in words.
String cuePrompt(String prompt) => '$prompt\n\nMake one image.';
