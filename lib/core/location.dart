/// Where the device is, and what becomes of that. Ports the parts of `src/app/core/location.ts` a place in the
/// words needs (Matt: "Add the ability to geotag notes and show a map card embedded on the note"), with
/// `src/app/core/placeLink.ts` (where a tapped map goes) and the two pieces of `src/app/core/geotag.ts` that turn
/// what a device and OpenStreetMap answer into a tag: `tagOf` and `shortPlace`.
///
/// Gated the way lib/core/link_preview.dart is: nothing leaves the device unless the person chose it. The rules of
/// the page's module stand, and the ones kept here are:
///
/// 1. THE FIX IS A NETWORK CALL, so Local only turns it off too ([Locations.canLocate]).
/// 2. THE NAME IS ASKED ONCE, at three decimals (about 100 m, enough for a street) or two for a rough tag, one ask
///    per place at a time, a second apart across the app (Nominatim's usage policy), and the switches read again
///    after the wait, since Local only may have been turned on during it ([Locations.placeName]).
///
/// What differs:
/// - The module's state (names known this run, asks in flight, when Nominatim may next be asked) is a [Locations]
///   object. What it cannot do itself is given to it: the device's position ([Locator]: the page's
///   `navigator.geolocation` and Android bridge), the reverse lookup ([PlaceLookup]: `geocode_place` in Rust, or a
///   fetch), the two switches, the clock and the wait. This stage has no location plugin and no network.
/// - What is the note store's, the recorder's and the shell's is lib/core/place_tags.dart ([PlaceTags], on top of
///   [Locations]): the tag that waits for a recording's better words, tagging new notes, a new note's held box, the
///   watchers and the kept refusal. The phone's half of a [Locator] is lib/core/phone_position.dart.
/// - `placeUrl` asked the platform itself; here it is told ([MapsApp]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'item_syntax.dart' show jsTrim;
import 'link_preview.dart' show LinkOpener;
import 'place_refs.dart';

export 'place_refs.dart' show GeoTag, coordsText, sameTag, tagLabel;

/// Why a fix did not come (`LocateFailure`). `localOnly` is the page's `'local-only'`.
enum LocateFailure { refused, blocked, unavailable, timeout, none, mac, ios, localOnly }

/// Why a fix did not come: [Locations.locate] throws one.
class LocateError implements Exception {
  const LocateError(this.why);

  final LocateFailure why;

  @override
  String toString() => 'LocateError(${why.name})';
}

/// The failure a failed `locate` carries, and `unavailable` for anything else.
LocateFailure whyLocateFailed(Object? failure) => failure is LocateError ? failure.why : LocateFailure.unavailable;

/// A position as the device answered it: degrees, metres, and when (core/geotag.ts `Fix`).
class Fix {
  const Fix({required this.lat, required this.lon, required this.accuracy, required this.at});

  final double lat;
  final double lon;
  final double accuracy;
  final int at;
}

/// A fix less exact than this many metres is Android's "Approximate": written rough.
const double roughMetres = 1000;

/// The most a place name may run to, as a title may.
const int _placeChars = 80;

/// Nominatim's usage policy: at most one request a second, across the app.
const int nominatimGapMs = 1100;

/// A fix as a tag: four decimals, or two where the fix was rough; no name yet.
GeoTag tagOf(Fix fix) {
  final rough = fix.accuracy > roughMetres;
  final digits = rough ? 2 : 4;
  return GeoTag(lat: double.parse(fix.lat.toStringAsFixed(digits)), lon: double.parse(fix.lon.toStringAsFixed(digits)), rough: rough);
}

/// What Nominatim's reverse lookup answers with, as much of it as the short name reads (`jsonv2`,
/// `addressdetails=1`).
class PlaceAnswer {
  const PlaceAnswer({this.name, this.displayName, this.addresstype, this.address = const <String, String?>{}});

  factory PlaceAnswer.fromJson(Map<String, Object?> json) => PlaceAnswer(
    name: json['name'] is String ? json['name'] as String : null,
    displayName: json['display_name'] is String ? json['display_name'] as String : null,
    addresstype: json['addresstype'] is String ? json['addresstype'] as String : null,
    address: <String, String?>{
      if (json['address'] is Map)
        for (final entry in (json['address'] as Map).entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    },
  );

  final String? name;
  final String? displayName;
  final String? addresstype;
  final Map<String, String?> address;
}

const List<String> _settlement = <String>['city', 'town', 'village', 'hamlet', 'municipality'];
const List<String> _region = <String>['state', 'country'];
final RegExp _spaces = RegExp(r'\s+');
final RegExp _houseNumber = RegExp(r'^\d+[a-z]?\s*', caseSensitive: false);

String? _first(Map<String, String?> address, List<String> keys) {
  for (final key in keys) {
    final value = jsTrim(address[key] ?? '');
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// A place's short name out of Nominatim's answer: "Trafalgar Square, London", "Rue de Rivoli, Paris",
/// "Hardangervidda, Vestland". A named place (a square, a park) or the road, then the settlement; never a house's
/// name or number, which is an address rather than a place. A rough tag takes the settlement and its region only.
/// Nothing usable reads as null, which the asker counts as a failed ask.
String? shortPlace(PlaceAnswer answer, bool rough) {
  final address = answer.address;
  final settlement = _first(address, _settlement);
  final region = _first(address, _region);
  final parts = <String>[];
  if (rough) {
    if (settlement != null) parts.add(settlement);
    if (region != null && region != settlement) parts.add(region);
  } else {
    final house = answer.addresstype == 'building' || answer.addresstype == 'house' || jsTrim(address['house_number'] ?? '').isNotEmpty;
    final own = jsTrim(answer.name ?? '');
    final named = !house && own.isNotEmpty ? own : null;
    final local = named ?? _first(address, const <String>['road', 'neighbourhood', 'suburb']);
    if (local != null) parts.add(local);
    if (settlement != null && settlement != local) {
      parts.add(settlement);
    } else if (settlement == null && region != null && region != local) {
      parts.add(region);
    }
  }
  final display = answer.displayName;
  if (parts.isEmpty && display != null && display.isNotEmpty) {
    parts.addAll(display.split(',').map((part) => jsTrim(part).replaceFirst(_houseNumber, '')).where((part) => part.isNotEmpty).take(2));
  }
  final joined = jsTrim(parts.join(', ').replaceAll(_spaces, ' '));
  final name = joined.length > _placeChars ? joined.substring(0, _placeChars) : joined;
  return name.isEmpty ? null : name;
}

// ---- where a tapped map goes (core/placeLink.ts) -------------------------------------------------------------------

/// Which maps a tap opens: the phone's chooser on an Android build whose opener allows `geo:`, Apple Maps on the
/// Mac, and openstreetmap.org everywhere else, which carries no label.
enum MapsApp { androidGeo, appleMaps, openStreetMap }

/// The address a tap on a map card opens, carrying the place name or the coordinates and never the note's title.
String placeUrl(GeoTag tag, [MapsApp app = MapsApp.openStreetMap]) {
  final lat = jsNumber(tag.lat), lon = jsNumber(tag.lon);
  switch (app) {
    case MapsApp.androidGeo:
      return 'geo:$lat,$lon?q=$lat,$lon${tag.place != null ? '(${Uri.encodeComponent(tag.place!)})' : ''}';
    case MapsApp.appleMaps:
      return 'https://maps.apple.com/?ll=$lat,$lon&q=${Uri.encodeComponent(tag.place ?? coordsText(tag))}';
    case MapsApp.openStreetMap:
      final zoom = tag.rough ? 12 : 15;
      return 'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=$zoom/$lat/$lon';
  }
}

/// Opens the place in the device's maps app, or the browser.
Future<void> openPlace(GeoTag tag, LinkOpener open, [MapsApp app = MapsApp.openStreetMap]) => open(placeUrl(tag, app));

// ---- the device, the lookup and the gates --------------------------------------------------------------------------

/// What the phone says of its permission (`Access`): a precise fix allowed, a rough one, never answered (or may be
/// asked again), or refused for good.
enum LocationAccess { granted, approximate, ask, blocked }

/// The device's own position: what the page asked of `navigator.geolocation` and the Android bridge.
abstract class Locator {
  /// Whether this device and this build can find where they are at all, whatever the switches say: null when they
  /// can, or why not (`locateHere`).
  LocateFailure? get cannot;

  /// Where the device is now. `quiet` never raises a prompt. Throws a [LocateError].
  Future<Fix> fix({bool quiet = false});

  /// The permission as it stands (`readAccess`); null where the device cannot say.
  Future<LocationAccess?> access();

  /// Whether this is the phone's app, which asks again after a first refusal and has a settings page of its own to
  /// open (`hasLocationBridge`).
  bool get onPhone;

  /// The app's page in the phone's settings, where a blocked location is allowed again; false if nothing took it.
  Future<bool> openSettings();
}

/// The reverse lookup: Nominatim asked for the coordinates at a zoom, in a language (`askNominatim`).
typedef PlaceLookup = Future<PlaceAnswer> Function({required double lat, required double lon, required int zoom});

/// The fix, the gates and a place's name.
class Locations {
  Locations({
    Locator? locator,
    PlaceLookup? lookup,
    required bool Function() localOnly,
    bool Function()? mapTiles,
    bool Function()? placeNames,
    int Function()? now,
    Future<void> Function(Duration wait)? wait,
  }) : _locator = locator,
       _lookup = lookup,
       _localOnly = localOnly,
       _mapTiles = mapTiles ?? (() => true),
       _placeNames = placeNames ?? (() => true),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _wait = wait ?? ((duration) => Future<void>.delayed(duration));

  final Locator? _locator;
  final PlaceLookup? _lookup;
  final bool Function() _localOnly;
  final bool Function() _mapTiles;
  final bool Function() _placeNames;
  final int Function() _now;
  final Future<void> Function(Duration wait) _wait;

  /// Whether this device can find where it is at all, whatever the switches say: null, or why not (`locateHere`).
  LocateFailure? get cannotLocateHere => _locator == null ? LocateFailure.none : _locator.cannot;

  /// Whether a fix can be asked for here at all: null, or why not, read before anything is asked (`canLocate`).
  LocateFailure? get cannotLocate => _localOnly() ? LocateFailure.localOnly : cannotLocateHere;

  /// Where the device is now (`locate`).
  Future<Fix> locate({bool quiet = false}) {
    final why = cannotLocate;
    if (why != null) return Future<Fix>.error(LocateError(why));
    return _locator!.fix(quiet: quiet);
  }

  /// The permission as the device says it stands; null where it cannot say, or there is nothing to ask.
  Future<LocationAccess?> access() => _locator?.access() ?? Future<LocationAccess?>.value();

  /// Whether this is the phone's app (`hasLocationBridge`).
  bool get onPhone => _locator?.onPhone ?? false;

  /// The app's page in the phone's settings.
  Future<bool> openSettings() => _locator?.openSettings() ?? Future<bool>.value(false);

  /// Whether a tagged note draws OpenStreetMap's tiles: the switch, and never under Local only.
  bool get canShowTiles => !_localOnly() && _mapTiles();

  /// Whether a place's name may be asked for: the switch, never under Local only, and something to ask with.
  bool get canAskPlace => _placeNames() && !_localOnly() && _lookup != null;

  // ---- the place's name ----

  /// Names that came this run, by the coordinates asked.
  final Map<String, String> _known = <String, String>{};

  /// Asks that failed this run: not asked again until the tag is made again.
  final Set<String> _failed = <String>{};

  /// Asks in flight, by the coordinates asked: a second note at the same place waits for the same answer.
  final Map<String, Future<String?>> _inflight = <String, Future<String?>>{};
  int _nextAllowedAt = 0;

  /// The coordinates a name is asked for, and kept under: three decimals, or two for a rough tag.
  static ({double lat, double lon, int zoom}) askedAs(GeoTag tag) {
    final digits = tag.rough ? 2 : 3;
    return (lat: double.parse(tag.lat.toStringAsFixed(digits)), lon: double.parse(tag.lon.toStringAsFixed(digits)), zoom: tag.rough ? 12 : 15);
  }

  static String _keyOf(GeoTag tag) {
    final asked = askedAs(tag);
    return '${jsNumber(asked.lat)},${jsNumber(asked.lon)}@${asked.zoom}';
  }

  /// A name that came for these coordinates while nothing was open to take it, or null.
  String? placeFor(GeoTag tag) => _known[_keyOf(tag)];

  Future<String?> _nameFor(GeoTag tag) {
    final key = _keyOf(tag);
    final already = _inflight[key];
    if (already != null) return already;
    Future<String?> ask() async {
      if (!canAskPlace) return null;
      final wait = math.max(0, _nextAllowedAt - _now());
      _nextAllowedAt = _now() + wait + nominatimGapMs;
      if (wait > 0) await _wait(Duration(milliseconds: wait));
      if (!canAskPlace) return null;
      String? place;
      try {
        final asked = askedAs(tag);
        place = shortPlace(await _lookup!(lat: asked.lat, lon: asked.lon, zoom: asked.zoom), tag.rough);
      } catch (_) {
        // Offline, refused, or an answer that was not JSON: a coordinate until the location is added again.
        place = null;
      }
      if (place != null) {
        _known[key] = place;
      } else {
        _failed.add(key);
      }
      return place;
    }

    // (A block, not an arrow: an arrow would answer the removed future, which is this one, and wait on itself.)
    final asked = ask().whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = asked;
    return asked;
  }

  /// The name for a place the + beside the line is adding: what is already known first, with no ask; nothing for a
  /// place whose ask failed this run; otherwise asked once, on Nominatim's terms. Null when none may be asked or
  /// none came.
  Future<String?> placeName(GeoTag tag) {
    final key = _keyOf(tag);
    final had = _known[key];
    if (had != null) return Future<String?>.value(had);
    if (_failed.contains(key)) return Future<String?>.value();
    return _nameFor(tag);
  }
}
