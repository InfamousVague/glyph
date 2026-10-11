/// Places and videos through the model, kept by construction, as tables are (tables.dart). A port of
/// `src/app/format/embeds.ts`.
///
/// A place line is a link to a `geo:` address (core/place_refs.dart), and a video line a picture linked to its film.
/// A small model rewriting a note would read either as words: a place's coordinates are exactly what it might round
/// or move, links.dart masks only web addresses, and a model told nothing of them may describe one or drop it. So
/// before the note goes in, each such line, whole, lead and all, is swapped for a picture-shaped token line the
/// model copies, `![place-1](place)` or `![video-1](video)`, and after the rewrite each is swapped back, verbatim.
/// The token is a picture's shape for the reason the table's is: measured with the 4B, a picture line is kept every
/// time. The prompts are told what the tokens are (format/prompt.dart, ai/prompts.dart).
///
/// A token that does not come back is added at the end of the note, for the modes that keep everything; a summary
/// may leave a place out.
///
/// What differs: [protectEmbeds] answers a [ProtectedEmbeds] where the page answered an object literal, and
/// [restoreEmbeds] takes `isFinal` (Dart keeps the word `final`) and names its two switches.
library;

import 'package:flutter/foundation.dart';

import '../core/place_refs.dart' show placeOfLine;
import '../core/video_refs.dart' show videoOfLine;

/// A place or a video line held aside while the model works (`ProtectedEmbed`).
@immutable
class ProtectedEmbed {
  const ProtectedEmbed({required this.token, required this.line});

  /// `place-2` or `video-1`: what stands in for the line while the model works.
  final String token;

  /// The line, exactly as written.
  final String line;

  @override
  bool operator ==(Object other) => other is ProtectedEmbed && other.token == token && other.line == line;

  @override
  int get hashCode => Object.hash(token, line);

  @override
  String toString() => 'ProtectedEmbed($token, $line)';
}

/// A note with its places and videos out, and the lines to put back.
@immutable
class ProtectedEmbeds {
  const ProtectedEmbeds({required this.text, required this.embeds});

  final String text;
  final List<ProtectedEmbed> embeds;

  @override
  bool operator ==(Object other) => other is ProtectedEmbeds && other.text == text && listEquals(other.embeds, embeds);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(embeds));

  @override
  String toString() => 'ProtectedEmbeds($text, $embeds)';
}

/// A line that opens or closes fenced code.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// What holds a line's place until every token is read: a private-use character either side of its index.
const String _mark = '\uE000';
final RegExp _held = RegExp('$_mark(\\d+)$_mark');

/// The note with every place and video line replaced by a token line, and the lines to put back.
ProtectedEmbeds protectEmbeds(String body) {
  final embeds = <ProtectedEmbed>[];
  final counts = {'place': 0, 'video': 0};
  String? fence;
  final lines = body.split('\n').map((line) {
    final marker = _fence.firstMatch(line)?.group(1);
    if (marker != null) fence = fence == null ? marker : (fence == marker ? null : fence);
    if (fence != null || marker != null) return line;
    final kind = placeOfLine(line) != null ? 'place' : (videoOfLine(line) != null ? 'video' : null);
    if (kind == null) return line;
    final count = counts[kind]! + 1;
    counts[kind] = count;
    final token = '$kind-$count';
    embeds.add(ProtectedEmbed(token: token, line: line));
    return '![$token]($kind)';
  }).toList();
  return ProtectedEmbeds(text: lines.join('\n'), embeds: embeds);
}

/// The rewrite with its places and videos back: a line that is a token, however the model wrote it
/// (`![place-1](place)`, `[place-1]`, `place 1`), becomes the line; a token buried in a sentence gets its line on a
/// line of its own. With [isFinal] and [appendMissing], a line whose token never came back is added at the end; a
/// partial rewrite still streaming is only substituted.
String restoreEmbeds(String text, List<ProtectedEmbed> embeds, {bool isFinal = true, bool appendMissing = true}) {
  // Each line put back is held as a mark until every token is read, so a place named "Market place 2" is never taken
  // for the second place's token once it is back.
  String held(int index) => '$_mark$index$_mark';
  var out = text;
  final missing = <ProtectedEmbed>[];
  for (var index = 0; index < embeds.length; index += 1) {
    final embed = embeds[index];
    final parts = embed.token.split('-');
    final kind = RegExp.escape(parts.isNotEmpty ? parts[0] : '');
    final number = RegExp.escape(parts.length > 1 ? parts[1] : '');
    // Spaces and tabs only, never `\s`: that would swallow the line's newline.
    final token = '!?[\\[<(]?[ \\t]*$kind[ \\t-]?$number(?!\\d)[ \\t]*[\\]>)]?(?:\\([ \\t]*$kind[ \\t]*\\))?';
    var found = false;
    out = out.replaceAllMapped(RegExp('^[ \\t]*$token[ \\t]*\$', multiLine: true, caseSensitive: false), (_) {
      found = true;
      return held(index);
    });
    out = out.replaceAllMapped(RegExp(token, caseSensitive: false), (_) {
      found = true;
      return '\n\n${held(index)}\n\n';
    });
    if (!found) missing.add(embed);
  }
  out = out.replaceAllMapped(_held, (match) {
    final index = int.tryParse(match.group(1) ?? '');
    return index != null && index < embeds.length ? embeds[index].line : '';
  });
  if (!isFinal || !appendMissing || missing.isEmpty) return out;
  return '${out.replaceFirst(_trailingSpace, '')}\n\n${missing.map((embed) => embed.line).join('\n\n')}\n';
}
