/// Where a note was written: two flat keys in its front matter, `location: 38.7223,-9.1393` and `place: "Alfama,
/// Lisbon"`. A port of `src/app/core/geotag.ts`: reading the tag, writing it, the words a row says for it, and the
/// short name made of a geocoder's answer.
///
/// A fix worse than a kilometre is a rough one, kept to two decimals (about a kilometre) and said as "Roughly";
/// a good one to four (about ten metres). A tag read from a note is rough when neither number carries more than two
/// decimals, so what was written rough is read rough.
///
/// What differs: `GeoTag` and `Fix` are classes with value equality, so the web's `sameTag(a, b)` is also `a == b`;
/// a geocoder's answer is the decoded JSON map rather than an interface over it.
library;

import 'package:flutter/foundation.dart';

import '../notes/note_templates.dart' show withFrontMatterValue;
import 'front_matter.dart';

/// A note's place (`GeoTag`).
@immutable
class GeoTag {
  const GeoTag({required this.lat, required this.lon, this.place, this.rough = false});

  final double lat;
  final double lon;

  /// Its name, once one has been asked for and answered.
  final String? place;

  /// Known only to about a kilometre.
  final bool rough;

  GeoTag named(String? place) => GeoTag(lat: lat, lon: lon, place: place, rough: rough);

  @override
  bool operator ==(Object other) => other is GeoTag && other.lat == lat && other.lon == lon && other.place == place && other.rough == rough;

  @override
  int get hashCode => Object.hash(lat, lon, place, rough);

  @override
  String toString() => 'GeoTag($lat, $lon, $place${rough ? ', rough' : ''})';
}

/// What the device's location answered (`Fix`): where, to how many metres, and when.
@immutable
class Fix {
  const Fix({required this.lat, required this.lon, required this.accuracy, required this.at});
  final double lat;
  final double lon;
  final double accuracy;
  final int at;
}

/// A fix worse than this many metres is a rough one (`ROUGH_M`).
const double roughMetres = 1000;
const int _placeChars = 80;
const String _location = 'location';
const String _place = 'place';

int _decimalsOf(String text) {
  final dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

final RegExp _quoted = RegExp(r'''^(["'])(.*)\1$''');
final RegExp _bracketed = RegExp(r'^\[(.*)\]$');
final RegExp _pair = RegExp(r'^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$');
final RegExp _spaces = RegExp(r'\s+');

({double lat, double lon, bool rough})? _readPair(String raw) {
  var text = raw.trim();
  text = text.replaceFirstMapped(_quoted, (m) => m.group(2)!);
  text = text.replaceFirstMapped(_bracketed, (m) => m.group(1)!).trim();
  final found = _pair.firstMatch(text);
  if (found == null) return null;
  final a = found.group(1)!, b = found.group(2)!;
  final lat = double.tryParse(a), lon = double.tryParse(b);
  if (lat == null || lon == null || !lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) return null;
  final most = _decimalsOf(a) > _decimalsOf(b) ? _decimalsOf(a) : _decimalsOf(b);
  return (lat: lat, lon: lon, rough: most <= 2);
}

/// The tag a note's front matter carries, or null where it says none, or says something that is not a place
/// (`geoTagOf`).
GeoTag? geoTagOf(String body) {
  final raw = frontMatterValue(body, _location);
  if (raw == null) return null;
  final pair = _readPair(raw);
  if (pair == null) return null;
  final place = frontMatterValue(body, _place)?.trim();
  return GeoTag(lat: pair.lat, lon: pair.lon, rough: pair.rough, place: place == null || place.isEmpty ? null : place);
}

/// The tag a fix makes: rounded to what it is good for, not yet named (`tagOf`).
GeoTag tagOf(Fix fix) {
  final rough = fix.accuracy > roughMetres;
  final digits = rough ? 2 : 4;
  return GeoTag(lat: double.parse(fix.lat.toStringAsFixed(digits)), lon: double.parse(fix.lon.toStringAsFixed(digits)), rough: rough);
}

String _locationValue(GeoTag tag) {
  final digits = tag.rough ? 2 : 4;
  return '${tag.lat.toStringAsFixed(digits)},${tag.lon.toStringAsFixed(digits)}';
}

String _withoutKey(String body, String key) {
  var out = body;
  while (frontMatterValue(out, key) != null) {
    final next = withFrontMatterValue(out, key, null);
    if (next == out) break;
    out = next;
  }
  return out;
}

/// The body with [tag] written into its front matter, or (null) with both keys taken out, and a block that held
/// nothing else with them. The words are untouched (`withGeoTag`).
String withGeoTag(String body, GeoTag? tag) {
  if (tag == null) return _withoutKey(_withoutKey(body, _place), _location);
  final located = withFrontMatterValue(body, _location, _locationValue(tag));
  var name = tag.place?.replaceAll(_spaces, ' ').trim() ?? '';
  if (name.length > _placeChars) name = name.substring(0, _placeChars);
  return withFrontMatterValue(located, _place, name.isEmpty ? null : quotedTitle(name, name));
}

/// "38.7223, -9.1393", or "Roughly 38.72, -9.14" (`coordsText`).
String coordsText(GeoTag tag) {
  final digits = tag.rough ? 2 : 4;
  return '${tag.rough ? 'Roughly ' : ''}${tag.lat.toStringAsFixed(digits)}, ${tag.lon.toStringAsFixed(digits)}';
}

/// What a row says for a tag: its name, or its numbers (`tagLabel`).
String tagLabel(GeoTag tag) => tag.place ?? coordsText(tag);

/// Whether two tags, or two absences of one, are the same (`sameTag`).
bool sameTag(GeoTag? a, GeoTag? b) => a == b;

const List<String> _settlement = ['city', 'town', 'village', 'hamlet', 'municipality'];
const List<String> _region = ['state', 'country'];
final RegExp _houseNumber = RegExp(r'^\d+[a-z]?\s*', caseSensitive: false);

String? _first(Map<String, Object?> address, List<String> keys) {
  for (final key in keys) {
    final value = address[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// A geocoder's answer (Nominatim's `jsonv2`, decoded) as the few words a note keeps: a road or a named place and
/// its town; for a rough tag only the town and its region. Null where the answer names nothing (`shortPlace`).
String? shortPlace(Map<String, Object?> answer, {required bool rough}) {
  final raw = answer['address'];
  final address = raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
  final settlement = _first(address, _settlement);
  final region = _first(address, _region);
  final parts = <String>[];
  if (rough) {
    if (settlement != null) parts.add(settlement);
    if (region != null && region != settlement) parts.add(region);
  } else {
    final number = address['house_number'];
    final house = answer['addresstype'] == 'building' || answer['addresstype'] == 'house' || (number is String && number.trim().isNotEmpty);
    final said = answer['name'];
    final named = !house && said is String && said.trim().isNotEmpty ? said.trim() : null;
    final local = named ?? _first(address, const ['road', 'neighbourhood', 'suburb']);
    if (local != null) parts.add(local);
    if (settlement != null && settlement != local) {
      parts.add(settlement);
    } else if (settlement == null && region != null && region != local) {
      parts.add(region);
    }
  }
  final display = answer['display_name'];
  if (parts.isEmpty && display is String && display.isNotEmpty) {
    parts.addAll(display.split(',').map((part) => part.trim().replaceFirst(_houseNumber, '')).where((part) => part.isNotEmpty).take(2));
  }
  var name = parts.join(', ').replaceAll(_spaces, ' ').trim();
  if (name.length > _placeChars) name = name.substring(0, _placeChars);
  return name.isEmpty ? null : name;
}
