/// What a share leaves out of a page before it is sealed: where it was written, and the places written in its
/// words; and the one front matter writer a saved copy needs. Ports of the pieces of `src/app/core/geotag.ts`
/// (`withGeoTag(body, null)`), `src/app/core/placeRefs.ts` (`withoutPlaces`, `hasPlaces`) and
/// `src/app/core/frontMatter.ts` (`withFrontMatterValue`, `withFrontMatterTitle`) that `share/share.ts` calls.
///
/// A share follows every save, so a location tag added to a note shared last week, or a place written into it, would
/// otherwise be published to everyone holding the link (lib/share/share.dart has the two switches). `withoutPlaces`
/// therefore takes every form a `geo:` address can be written in, not only the line the + writes: a place line goes
/// whole, a link inside other words keeps its words, an autolink and a reference definition go, in fenced and inline
/// code too; and whatever form is left - a link over two lines, a picture's source, raw HTML - loses its address
/// last of all.
///
/// What differs: these live with the share because it is the first thing in this app that needs them. The tag and
/// the place lines themselves (reading a tag, writing one, the map cards) come with the editor's stage, and when
/// `lib/core` has `geotag.dart` and `place_refs.dart` these three functions belong there.
library;

import '../core/front_matter.dart';
import '../core/item_syntax.dart' show lineWords;

// --- front matter (core/frontMatter.ts) ------------------------------------------------------------------------------

/// The body with front matter [key] set to [value] as it is written (no quoting added): replaced where the key is,
/// added last where it isn't, and front matter made where there was none (`withFrontMatterValue`). A null value
/// takes the key off, and front matter that held nothing else with it. The words are untouched.
String withFrontMatterValue(String body, String key, String? value) {
  final lines = body.split('\n');
  final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:', caseSensitive: false);
  final line = value == null ? null : '$key: ${value.replaceAll('\n', ' ').trim()}';
  final end = frontMatterEnd(lines);
  if (end == 0) return line != null ? '---\n$line\n---\n$body' : body;
  final keys = lines.sublist(1, end - 1);
  final at = keys.indexWhere(pattern.hasMatch);
  if (at >= 0) {
    if (line != null) {
      keys[at] = line;
    } else {
      keys.removeAt(at);
    }
  } else if (line != null) {
    keys.add(line);
  }
  final rest = lines.sublist(end);
  if (keys.isEmpty) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

final RegExp _titleKey = RegExp(r'^\s*title\s*:', caseSensitive: false);

/// The body with its front matter's title set (`withFrontMatterTitle`): first of its keys, in place of any it had,
/// and front matter made where there was none. An empty title takes the key off, and takes front matter that held
/// nothing else off with it.
String withFrontMatterTitle(String body, String title) {
  final clean = title.trim();
  final named = clean.isNotEmpty ? 'title: ${quotedTitle(clean, clean)}' : null;
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  if (end == 0) return named != null ? '---\n$named\n---\n$body' : body;
  final keys = [
    ?named,
    for (final key in lines.sublist(1, end - 1))
      if (!_titleKey.hasMatch(key)) key,
  ];
  final rest = lines.sublist(end);
  if (keys.isEmpty) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

// --- where a note was written (core/geotag.ts) -----------------------------------------------------------------------

String _withoutKey(String body, String key) {
  var out = body;
  while (frontMatterValue(out, key) != null) {
    final next = withFrontMatterValue(out, key, null);
    if (next == out) break;
    out = next;
  }
  return out;
}

/// The body with where it was written taken out: every `location:` and `place:` line of its front matter, and the
/// block with them when nothing else is in it (`withGeoTag(body, null)`). The words are untouched.
String withoutGeoTag(String body) => _withoutKey(_withoutKey(body, 'place'), 'location');

// --- the places written in a note's words (core/placeRefs.ts) --------------------------------------------------------

/// A link's destination when it is a `geo:` address: bare or in angle brackets, with an optional title.
const String _destination = r'''\(\s*<?geo:[^)\s>]*>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)''';

/// Any Markdown link to a `geo:` address, never a picture's: its words as group 1 (`GEO_LINK`).
final RegExp _geoLink = RegExp('(?<!!)\\[((?:[^\\[\\]\\n]|\\[[^\\]\\n]*\\])*)\\]$_destination', caseSensitive: false);

/// A `geo:` address written as an autolink, `<geo:38.7,-9.1>` (`GEO_AUTOLINK`).
final RegExp _geoAutolink = RegExp(r'<geo:[^>\s]*>', caseSensitive: false);

/// A reference definition whose address is a `geo:` one, `[c]: geo:38.7,-9.1`: its label as group 1
/// (`GEO_DEFINITION`), read a line at a time.
final RegExp _geoDefinition = RegExp(r'^ {0,3}\[([^\]\n]+)\]:\s*<?geo:\S*>?.*$', caseSensitive: false);

/// A picture whose source is a `geo:` address, `![map](geo:38.7,-9.1)`: its words as group 1 (`GEO_PICTURE`).
final RegExp _geoPicture = RegExp('!\\[((?:[^\\[\\]\\n]|\\[[^\\]\\n]*\\])*)\\]$_destination', caseSensitive: false);

/// A link or a picture to a `geo:` address written over more than one line. A picture's mark and the words as
/// groups 1 and 2 (`GEO_LINK_LINES`).
final RegExp _geoLinkLines = RegExp('(!?)\\[((?:[^\\[\\]]|\\[[^\\]]*\\])*)\\]$_destination', caseSensitive: false);

/// A `geo:` address anywhere at all, as plain words, in raw HTML or in a URL: `geo:` and coordinates after it
/// (`GEO_ADDRESS`).
final RegExp _geoAddress = RegExp(r'''\bgeo:(?=[-+.\d])[^\s<>"'()[\]`]*''', caseSensitive: false);

final RegExp _blankBetween = RegExp(r'\n[ \t]*\n');
final RegExp _reference = RegExp(r'(?<!!)\[([^\]\n]+)\]\[([^\]\n]*)\]');

/// Whether a line's words are only links (or pictures) to `geo:` addresses: the line goes whole (`onlyPlaces`).
bool _onlyPlaces(String text) {
  final words = lineWords(text);
  if (words.isEmpty) return false;
  final links = _geoPicture.allMatches(words).length + _geoLink.allMatches(words).length + _geoAutolink.allMatches(words).length;
  return links > 0 && words.replaceAll(_geoPicture, '').replaceAll(_geoLink, '').replaceAll(_geoAutolink, '').trim().isEmpty;
}

/// The body with every `geo:` address taken out, wherever it is written (`withoutPlaces`): a line of nothing but
/// places goes whole (one blank line kept where it stood between two), a link or a picture inside other words keeps
/// its words, one written over two lines keeps its words too, an autolink goes, and a reference definition goes
/// while its references keep their words. Then any address still there, in raw HTML, a URL or plain words, goes on
/// its own, and what is round it stays. `geo:` as a word with no coordinates after it is words, and the tag in the
/// front matter is the tag's own switch ([withoutGeoTag]).
String withoutPlaces(String body) {
  final joined = body.replaceAllMapped(_geoLinkLines, (m) {
    final whole = m.group(0)!;
    return whole.contains('\n') && !_blankBetween.hasMatch(whole) ? (m.group(2) ?? '') : whole;
  });
  final lines = joined.split('\n');
  final labels = <String>{};
  for (final line in lines) {
    for (final found in _geoDefinition.allMatches(line)) {
      labels.add((found.group(1) ?? '').toLowerCase());
    }
  }
  final out = <String>[];
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    if (_geoDefinition.hasMatch(line)) continue;
    if (_onlyPlaces(line)) {
      // A place between two blank lines leaves one of them, not two.
      final next = index + 1 < lines.length ? lines[index + 1] : null;
      if (out.isNotEmpty && out.last.trim().isEmpty && (next == null || next.trim().isEmpty)) out.removeLast();
      continue;
    }
    var kept = line.replaceAllMapped(_geoPicture, (m) => m.group(1) ?? '').replaceAllMapped(_geoLink, (m) => m.group(1) ?? '').replaceAll(_geoAutolink, '');
    if (labels.isNotEmpty) {
      kept = kept.replaceAllMapped(_reference, (m) {
        final words = m.group(1) ?? '', label = m.group(2) ?? '';
        return labels.contains((label.isEmpty ? words : label).toLowerCase()) ? words : m.group(0)!;
      });
    }
    out.add(kept);
  }
  return out.join('\n').replaceAll(_geoAddress, '');
}

/// Whether a body holds a `geo:` address in any form a share would take out (`hasPlaces`).
bool hasPlaces(String body) => withoutPlaces(body) != body;
