/// The name of the place a tagged note was written, asked of OpenStreetMap's Nominatim (Matt: "Add the ability to
/// geotag notes and show a map card embedded on the note"). Ports `src-tauri/src/geocode.rs`; the asker's half is
/// lib/core/location.dart ([Locations], `core/location.ts`).
///
/// Nominatim's usage policy asks for a User-Agent that names the application, and says a library's stock one will
/// not do, so the app asks as itself. [Locations] sends coordinates already rounded (three decimals, or two for a
/// rough tag), asks once per tag and a second apart, and reads the short name out of the answer (`shortPlace`), so
/// this stays a passthrough: it builds the address itself and takes nothing else from its caller. Eight seconds,
/// no redirects, a non-2xx is a refusal. Nothing is kept and nothing is paced here: both are [Locations]'.
///
/// What differs:
/// - `geocode_place` is [geocodePlace], a [PlaceLookup] over a [Fetcher]. The language is not an argument of a
///   [PlaceLookup], so it is asked for at each lookup (`lang`, the page's `navigator.language || 'en'`).
/// - The answer is read into a [PlaceAnswer] here, where the Rust handed the page Nominatim's JSON as it came. An
///   answer that is JSON and not an object is a refusal too.
/// - The app's version is told ([geocodeUserAgent]), where the Rust read the crate's at build time.
/// - "No redirects" is the fetcher's to keep: a [Fetcher] has no such switch, and lib/account/api.dart's
///   `ioFetcher` follows them. [geocodeFetcher] is the one over `dart:io` that does not; through it a redirect is
///   a 3xx, and so a refusal.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../account/api.dart' show FetchRequest, FetchResponse, Fetcher;
import 'location.dart' show PlaceAnswer, PlaceLookup;
import 'place_refs.dart' show jsNumber;

/// How long Nominatim is waited for.
const Duration geocodeTimeout = Duration(seconds: 8);

/// The app's version, where none is told: pubspec.yaml's.
const String geocodeAppVersion = '0.1.0';

/// Why a place's name did not come, in the Rust's words.
class GeocodeError implements Exception {
  const GeocodeError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The reverse lookup, at the two zooms the card draws: a street (15) or a district (12) (`reverse_url`). Throws a
/// [GeocodeError] for what is not a place or not such a zoom.
Uri reverseUrl(double lat, double lon, int zoom) {
  if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) throw const GeocodeError("That isn't a place on Earth.");
  if (zoom != 12 && zoom != 15) throw const GeocodeError('The map has no such zoom.');
  return Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${jsNumber(lat)}&lon=${jsNumber(lon)}&zoom=$zoom&addressdetails=1');
}

final RegExp _headerSafe = RegExp(r'[A-Za-z0-9\-,;=. ]');

/// The language the name is asked in: the caller's, kept to what an Accept-Language header may hold, else English
/// (`accept_language`).
String acceptLanguage(String lang) {
  final clean = lang.runes.map(String.fromCharCode).where(_headerSafe.hasMatch).take(64).join().trim();
  return clean.isEmpty ? 'en' : clean;
}

/// The app, named, as Nominatim asks: the version and where to find out about it.
String geocodeUserAgent([String version = geocodeAppVersion]) => 'GhostMd/$version (https://ghostmarkdown.com)';

/// `geocode_place`: a [PlaceLookup] that asks Nominatim through [fetch]. [lang] is read at each lookup (the
/// device's language, as `en-GB`); [version] is the app's. Throws a [GeocodeError].
PlaceLookup geocodePlace(Fetcher fetch, {String Function()? lang, String version = geocodeAppVersion, Duration timeout = geocodeTimeout}) {
  return ({required double lat, required double lon, required int zoom}) async {
    final url = reverseUrl(lat, lon, zoom);
    final FetchResponse response;
    try {
      response = await fetch(
        FetchRequest(
          method: 'GET',
          url: url,
          headers: <String, String>{'User-Agent': geocodeUserAgent(version), 'Accept': 'application/json', 'Accept-Language': acceptLanguage(lang?.call() ?? 'en')},
          timeout: timeout,
        ),
      ).timeout(timeout);
    } catch (_) {
      throw const GeocodeError("OpenStreetMap couldn't be reached.");
    }
    if (!response.ok) throw GeocodeError('OpenStreetMap answered ${response.status}.');
    final Object? json;
    try {
      json = jsonDecode(response.text);
    } catch (_) {
      throw const GeocodeError("OpenStreetMap's answer wasn't JSON.");
    }
    if (json is! Map) throw const GeocodeError("OpenStreetMap's answer wasn't JSON.");
    return PlaceAnswer.fromJson(json.cast<String, Object?>());
  };
}

/// A [Fetcher] over `dart:io` that follows no redirect, for [geocodePlace]: a 3xx is answered as it came. [client]
/// is the one to use, or one made here and kept.
Fetcher geocodeFetcher({HttpClient? client}) {
  final http = client ?? HttpClient();
  return (request) async {
    HttpClientRequest? sent;
    Future<FetchResponse> ask() async {
      final asked = sent = await http.openUrl(request.method, request.url);
      asked.followRedirects = false;
      request.headers.forEach(asked.headers.set);
      final answer = await asked.close();
      final bytes = BytesBuilder(copy: false);
      await answer.forEach(bytes.add);
      final headers = <String, String>{};
      answer.headers.forEach((name, values) => headers[name] = values.join(', '));
      return FetchResponse(answer.statusCode, headers: headers, bytes: bytes.takeBytes());
    }

    return ask().timeout(request.timeout, onTimeout: () {
      sent?.abort();
      throw TimeoutException('The request took too long.', request.timeout);
    });
  };
}
