/// A place written into a note's words: a plain Markdown link to a `geo:` address (RFC 5870), alone on its line.
/// Ports `src/app/core/placeRefs.ts`, and with it the half of `src/app/core/geotag.ts` a place is read into (the
/// tag itself, and how its coordinates are said), since nothing else here has ported that module yet.
///
///     [Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
///
/// The + beside the line writes one where the caret is, the editor draws the map card under it
/// (lib/editor/media/place_cards.dart), and any other reader shows a link. A note may hold as many as it likes.
///
/// The coordinates are the tag's: four decimals, or two for a rough fix, and the roughness is read back from the
/// decimals, as the tag's is. The words are the place's name, or the coordinates as a person reads them when no
/// name came.
///
/// What differs:
/// - `GeoTag`, `coordsText`, `tagLabel` and `sameTag` are core/geotag.ts's. The front matter half of that module
///   (`geoTagOf`, `withGeoTag`) is not here: `withGeoTag(body, null)` is in lib/share/carried.dart, for the share.
/// - `withoutPlaces` and `hasPlaces` (and the patterns they alone use: `GEO_LINK`, `GEO_AUTOLINK`,
///   `GEO_DEFINITION`) were ported with the share, which is what calls them, as lib/share/carried.dart. They are
///   not written a second time here.
/// - A number is said as JavaScript says one ([jsNumber]): `1`, not `1.0`.
library;

import 'package:flutter/foundation.dart';

import 'front_matter.dart';
import 'item_syntax.dart' show jsTrim, lineWords;

/// Where something is, as a note says it (core/geotag.ts `GeoTag`).
@immutable
class GeoTag {
  const GeoTag({required this.lat, required this.lon, this.place, this.rough = false});

  final double lat;
  final double lon;

  /// The place's name, once asked and kept in the note; null until then.
  final String? place;

  /// Written or read at two decimals: an area, not a point.
  final bool rough;

  GeoTag named(String? place) => GeoTag(lat: lat, lon: lon, place: place, rough: rough);

  /// Whether two tags say the same thing (`sameTag`).
  @override
  bool operator ==(Object other) => other is GeoTag && other.lat == lat && other.lon == lon && other.place == place && other.rough == rough;

  @override
  int get hashCode => Object.hash(lat, lon, place, rough);

  @override
  String toString() => 'GeoTag($lat, $lon, $place, ${rough ? 'rough' : 'fine'})';
}

/// Whether two tags say the same thing, for a card that redraws only when its tag changes.
bool sameTag(GeoTag? a, GeoTag? b) => a == b;

/// A number as JavaScript writes one in a string: no `.0` on a whole number.
String jsNumber(double value) => value == value.truncateToDouble() && value.abs() < 1e21 ? value.toStringAsFixed(0) : value.toString();

/// The coordinates as a person reads them: "51.5074, -0.1278", or "Roughly 51.51, -0.13".
String coordsText(GeoTag tag) {
  final digits = tag.rough ? 2 : 4;
  return '${tag.rough ? 'Roughly ' : ''}${tag.lat.toStringAsFixed(digits)}, ${tag.lon.toStringAsFixed(digits)}';
}

/// The place's name, or the coordinates where none is known.
String tagLabel(GeoTag tag) => tag.place ?? coordsText(tag);

/// The one form a place line takes: the words, then the latitude and the longitude as groups 2 and 3.
final RegExp _place = RegExp(r'^\[([^\[\]\n]*)\]\(geo:(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)\)$', caseSensitive: false);

/// A line that opens or closes fenced code, as lib/editor/syntax/lines.dart reads one.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// The most a place's name may run to, as the tag's `place:` may.
const int _nameChars = 80;

/// A place read from a line: where it is, and the words it is written with.
@immutable
class PlaceLine {
  const PlaceLine(this.tag, this.words, [this.line = 0]);

  /// The place as a tag: `place` is its name, or null where its words are only the coordinates.
  final GeoTag tag;
  final String words;

  /// Its line in the body, counting from 1, where [placeLines] read it; 0 otherwise.
  final int line;

  @override
  bool operator ==(Object other) => other is PlaceLine && other.tag == tag && other.words == words && other.line == line;

  @override
  int get hashCode => Object.hash(tag, words, line);

  @override
  String toString() => 'PlaceLine($tag, $words, $line)';
}

/// How many decimals a number was written with.
int _decimalsOf(String text) {
  final dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

/// Whether [text] has `](geo:` in it, in either case, as [_place] reads the scheme.
bool _hasGeoLink(String text) {
  for (var at = text.indexOf(']('); at >= 0; at = text.indexOf('](', at + 2)) {
    if (at + 6 > text.length) return false;
    // `geo:` in either case: 0x20 is the bit between an ASCII letter's two cases.
    if ((text.codeUnitAt(at + 2) | 0x20) == 0x67 && (text.codeUnitAt(at + 3) | 0x20) == 0x65 && (text.codeUnitAt(at + 4) | 0x20) == 0x6f && text.codeUnitAt(at + 5) == 0x3a) return true;
  }
  return false;
}

/// The place a line is, or null: a line whose words, past its quote's markers and its list lead, are exactly one
/// link to `geo:lat,lon` with the latitude in -90..90 and the longitude in -180..180. That line draws a map card.
PlaceLine? placeOfLine(String text) {
  // A place's line has a link to a `geo:` address, and almost no line does: asked first, since this is asked of
  // every line of a note and the patterns below are many times the cost of looking for the link's turn.
  if (!_hasGeoLink(text)) return null;
  final found = _place.firstMatch(lineWords(text));
  if (found == null) return null;
  final words = found.group(1) ?? '', a = found.group(2) ?? '', b = found.group(3) ?? '';
  final lat = double.tryParse(a), lon = double.tryParse(b);
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) return null;
  final rough = (_decimalsOf(a) > _decimalsOf(b) ? _decimalsOf(a) : _decimalsOf(b)) <= 2;
  final tag = GeoTag(lat: lat, lon: lon, rough: rough);
  final named = jsTrim(words);
  return PlaceLine(tag.named(named.isNotEmpty && named != coordsText(tag) ? named : null), named);
}

final RegExp _breaking = RegExp(r'[\[\]\\]');
final RegExp _spaces = RegExp(r'\s+');

/// A name made safe for a link's words: no brackets, backslashes or line breaks, one space between words, a
/// title's length.
String cleanPlaceName(String name) {
  final clean = jsTrim(name.replaceAll(_breaking, ' ').replaceAll(_spaces, ' '));
  return jsTrim(clean.length > _nameChars ? clean.substring(0, _nameChars) : clean);
}

/// The line for a place: its name as the words, or the coordinates where there is none. The tag's own precision.
String placeMarkdown(GeoTag tag, [String? name]) {
  final digits = tag.rough ? 2 : 4;
  final clean = cleanPlaceName(name ?? '');
  final words = clean.isNotEmpty ? clean : coordsText(tag);
  return '[$words](geo:${tag.lat.toStringAsFixed(digits)},${tag.lon.toStringAsFixed(digits)})';
}

/// Every place line in a body, outside fenced code, with its line number counting from 1.
List<PlaceLine> placeLines(String body) {
  final found = <PlaceLine>[];
  String? fence;
  final lines = body.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    final marker = _fence.firstMatch(text)?.group(1);
    if (marker != null) {
      fence = fence == null ? marker : (fence == marker ? null : fence);
      continue;
    }
    if (fence != null) continue;
    final place = placeOfLine(text);
    if (place != null) found.add(PlaceLine(place.tag, place.words, index + 1));
  }
  return found;
}

/// The place line at the very top of a note, counting from 1, which is drawn as the note's header rather than the
/// slim card (GLY-3, Matt: "Map location when placed at the very top of a note should produce a full screen header
/// of the map instead of the slim card"). The very top is the note's first line with words, after its front
/// matter, or the line with words straight after that one, since a note's first line is its title and a place put
/// at the top goes under it. Null where neither is a place.
int? topPlaceLine(List<String> lines) {
  var seen = 0;
  for (var index = frontMatterEnd(lines); index < lines.length && seen < 2; index += 1) {
    final text = lines[index];
    if (jsTrim(text).isEmpty) continue;
    if (_fence.hasMatch(text)) return null;
    if (placeOfLine(text) != null) return index + 1;
    seen += 1;
  }
  return null;
}
