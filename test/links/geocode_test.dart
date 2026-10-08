// A place's name, asked of Nominatim: src-tauri/src/geocode.rs's three tests, case for case, then the ask itself
// through a fake fetcher that answers in Nominatim's jsonv2 shape, the one case of core/location.test.ts that is
// about what is asked ("is asked of the app once, at three decimals and zoom 15"; the rest of that file's cases are
// in test/editor/media/core_test.dart, against lib/core/location.dart), and the fetcher that follows no redirect
// against a server on 127.0.0.1. Nothing here asks OpenStreetMap.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/geocode.dart';
import 'package:ghost_md/core/location.dart';

/// Trafalgar Square, as Nominatim's reverse lookup answers at zoom 15 with `format=jsonv2&addressdetails=1`: the
/// shape of its answer, written out here (nothing was asked of the service to make it).
const String trafalgar = '''
{"place_id":258718304,"licence":"Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright","osm_type":"way","osm_id":4372002,
 "lat":"51.5080","lon":"-0.1281","category":"place","type":"square","place_rank":25,"importance":0.53,"addresstype":"square",
 "name":"Trafalgar Square","display_name":"Trafalgar Square, St. James's, Covent Garden, City of Westminster, Greater London, England, WC2N 5DN, United Kingdom",
 "address":{"square":"Trafalgar Square","neighbourhood":"St. James's","suburb":"Covent Garden","city":"London","borough":"City of Westminster",
  "ISO3166-2-lvl8":"GB-WSM","state_district":"Greater London","state":"England","ISO3166-2-lvl4":"GB-ENG","postcode":"WC2N 5DN","country":"United Kingdom","country_code":"gb"},
 "boundingbox":["51.5076","51.5084","-0.1290","-0.1272"]}''';

/// A house on a road: an address, which the short name never says.
const String house = '''
{"addresstype":"building","name":"","display_name":"221B, Baker Street, Marylebone, London, Greater London, England, NW1 6XE, United Kingdom",
 "address":{"house_number":"221B","road":"Baker Street","suburb":"Marylebone","city":"London","state":"England","country":"United Kingdom","country_code":"gb"}}''';

Matcher refusedWith(String message) => throwsA(isA<GeocodeError>().having((error) => error.message, 'message', message));

FetchResponse body(int status, String text) => FetchResponse(status, headers: const <String, String>{'content-type': 'application/json'}, bytes: Uint8List.fromList(utf8.encode(text)));

void main() {
  group('geocode.rs', () {
    test('builds_the_lookup_from_a_place_and_a_zoom', () {
      expect(reverseUrl(51.507, -0.128, 15).toString(), 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1');
      expect(reverseUrl(51.51, -0.13, 12).toString(), 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.51&lon=-0.13&zoom=12&addressdetails=1');
      // A whole number is written as Rust and the page write one: no `.0`.
      expect(reverseUrl(51, -1, 12).toString(), 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51&lon=-1&zoom=12&addressdetails=1');
    });

    test('refuses_what_is_not_a_place_or_a_zoom_the_card_draws', () {
      expect(() => reverseUrl(double.nan, 0, 15), refusedWith("That isn't a place on Earth."));
      expect(() => reverseUrl(0, double.infinity, 15), refusedWith("That isn't a place on Earth."));
      expect(() => reverseUrl(91, 0, 15), refusedWith("That isn't a place on Earth."));
      expect(() => reverseUrl(0, -181, 15), refusedWith("That isn't a place on Earth."));
      expect(() => reverseUrl(0, 0, 14), refusedWith('The map has no such zoom.'));
      expect(() => reverseUrl(0, 0, 0), refusedWith('The map has no such zoom.'));
      expect(reverseUrl(90, -180, 15), isNotNull);
    });

    test('keeps_the_language_to_what_a_header_may_hold', () {
      expect(acceptLanguage('en-GB,en;q=0.9'), 'en-GB,en;q=0.9');
      expect(acceptLanguage(''), 'en');
      expect(acceptLanguage('\r\nX-Injected: yes'), 'X-Injected yes');
      expect(acceptLanguage('   '), 'en');
      expect(acceptLanguage('é' * 10), 'en');
      expect(acceptLanguage('a' * 100).length, 64);
    });
  });

  group('a place’s name', () {
    test('is asked of Nominatim as the app, in the device’s language, and read into an answer', () async {
      final asked = <FetchRequest>[];
      var lang = 'en-GB';
      final lookup = geocodePlace((request) async {
        asked.add(request);
        return body(200, trafalgar);
      }, lang: () => lang, version: '1.15.0');
      final answer = await lookup(lat: 51.507, lon: -0.128, zoom: 15);
      final request = asked.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1');
      expect(request.headers, <String, String>{'User-Agent': 'GhostMd/1.15.0 (https://ghostmarkdown.com)', 'Accept': 'application/json', 'Accept-Language': 'en-GB'});
      expect(request.body, isNull);
      expect(request.timeout, const Duration(seconds: 8));
      expect(answer.name, 'Trafalgar Square');
      expect(answer.addresstype, 'square');
      expect(answer.displayName, startsWith('Trafalgar Square, St. James'));
      expect(answer.address['city'], 'London');
      expect(answer.address['country'], 'United Kingdom');
      expect(shortPlace(answer, false), 'Trafalgar Square, London');
      expect(shortPlace(answer, true), 'London, England');
      // The language is read at each ask, and kept to what a header may hold.
      lang = 'pt-PT\r\nX-Injected: yes';
      await lookup(lat: 38.71, lon: -9.14, zoom: 12);
      expect(asked.last.headers['Accept-Language'], 'pt-PTX-Injected yes');
      expect(asked.last.url.query, 'format=jsonv2&lat=38.71&lon=-9.14&zoom=12&addressdetails=1');
    });

    test('asks in English, as version 0.1.0, where it is told neither', () async {
      FetchRequest? asked;
      await geocodePlace((request) async {
        asked = request;
        return body(200, house);
      })(lat: 51.524, lon: -0.158, zoom: 15);
      expect(asked!.headers['Accept-Language'], 'en');
      expect(asked!.headers['User-Agent'], 'GhostMd/0.1.0 (https://ghostmarkdown.com)');
    });

    test('never says a house’s number', () async {
      final answer = await geocodePlace((request) async => body(200, house))(lat: 51.524, lon: -0.158, zoom: 15);
      expect(shortPlace(answer, false), 'Baker Street, London');
    });

    test('asks nothing for what is not a place or a zoom the card draws', () async {
      var asked = 0;
      final lookup = geocodePlace((request) async {
        asked++;
        return body(200, trafalgar);
      });
      await expectLater(lookup(lat: 91, lon: 0, zoom: 15), refusedWith("That isn't a place on Earth."));
      await expectLater(lookup(lat: 0, lon: 0, zoom: 18), refusedWith('The map has no such zoom.'));
      expect(asked, 0);
    });

    test('is a refusal when Nominatim says no, cannot be reached, is too slow, or answers what is not JSON', () async {
      Future<PlaceAnswer> ask(Fetcher fetch, {Duration timeout = geocodeTimeout}) => geocodePlace(fetch, timeout: timeout)(lat: 51.507, lon: -0.128, zoom: 15);
      await expectLater(ask((request) async => body(429, '{"error":"Too many requests"}')), refusedWith('OpenStreetMap answered 429.'));
      await expectLater(ask((request) async => body(503, '<html>down</html>')), refusedWith('OpenStreetMap answered 503.'));
      await expectLater(ask((request) async => FetchResponse(302, headers: const <String, String>{'location': 'https://elsewhere.test/'})), refusedWith('OpenStreetMap answered 302.'));
      await expectLater(ask((request) async => throw const SocketException('offline')), refusedWith("OpenStreetMap couldn't be reached."));
      await expectLater(ask((request) => Completer<FetchResponse>().future, timeout: const Duration(milliseconds: 20)), refusedWith("OpenStreetMap couldn't be reached."));
      await expectLater(ask((request) async => body(200, '<html>a captive portal</html>')), refusedWith("OpenStreetMap's answer wasn't JSON."));
      await expectLater(ask((request) async => body(200, '[]')), refusedWith("OpenStreetMap's answer wasn't JSON."));
      // Nominatim's "nothing there" is a 200 with an error and no address: an answer, with no name in it.
      final nothing = await ask((request) async => body(200, '{"error":"Unable to geocode"}'));
      expect(shortPlace(nothing, false), isNull);
    });

    // core/location.test.ts, as far as it is about the ask.
    test('is asked of the app once, at three decimals and zoom 15, and told to the note watching', () async {
      final asked = <Uri>[];
      final locations = Locations(
        lookup: geocodePlace((request) async {
          asked.add(request.url);
          return body(200, trafalgar);
        }),
        localOnly: () => false,
      );
      const london = GeoTag(lat: 51.5074, lon: -0.1278);
      final names = await Future.wait(<Future<String?>>[locations.placeName(london), locations.placeName(london)]);
      expect(names, <String?>['Trafalgar Square, London', 'Trafalgar Square, London']);
      expect(asked.map((url) => url.query), <String>['format=jsonv2&lat=51.507&lon=-0.128&zoom=15&addressdetails=1']);
      // Known now: nothing is asked again.
      expect(await locations.placeName(london), 'Trafalgar Square, London');
      expect(asked.length, 1);
    });

    test('is not asked under Local only, and a failed ask is a coordinate', () async {
      var asked = 0;
      var local = true;
      final locations = Locations(
        lookup: geocodePlace((request) async {
          asked++;
          return body(500, '');
        }),
        localOnly: () => local,
      );
      expect(await locations.placeName(const GeoTag(lat: 51.5074, lon: -0.1278)), isNull);
      expect(asked, 0);
      local = false;
      expect(await locations.placeName(const GeoTag(lat: 48.8566, lon: 2.3522)), isNull);
      expect(asked, 1);
    });
  });

  group('the fetcher that follows no redirect', () {
    test('sends the app’s name in place of dart:io’s, and answers a redirect as it came', () async {
      final asked = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        asked.add(request);
        if (request.uri.path == '/moved') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/reverse');
        } else {
          request.response.headers.set('content-type', 'application/json');
          request.response.write(trafalgar);
        }
        await request.response.close();
      });
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final fetch = geocodeFetcher(client: client);
      const headers = <String, String>{'User-Agent': 'GhostMd/1.15.0 (https://ghostmarkdown.com)', 'Accept': 'application/json', 'Accept-Language': 'en-GB'};
      final answer = await fetch(FetchRequest(method: 'GET', url: Uri.parse('http://127.0.0.1:${server.port}/reverse?lat=1'), headers: headers));
      expect(answer.status, 200);
      expect(PlaceAnswer.fromJson((jsonDecode(answer.text) as Map).cast<String, Object?>()).name, 'Trafalgar Square');
      expect(asked.single.headers['user-agent'], <String>['GhostMd/1.15.0 (https://ghostmarkdown.com)']);
      expect(asked.single.headers.value('accept-language'), 'en-GB');
      expect(asked.single.headers.value('accept'), 'application/json');
      final moved = await fetch(FetchRequest(method: 'GET', url: Uri.parse('http://127.0.0.1:${server.port}/moved'), headers: headers));
      expect(moved.status, 302);
      expect(asked.map((request) => request.uri.path), <String>['/reverse', '/moved'], reason: 'the redirect was not followed');
    });

    test('gives up when the wait is over', () async {
      final never = Completer<void>();
      addTearDown(never.complete);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => never.future);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final lookup = geocodePlace(geocodeFetcher(client: client), timeout: const Duration(milliseconds: 100));
      // (The lookup builds Nominatim's address itself, so the fetcher is asked directly here.)
      await expectLater(geocodeFetcher(client: client)(FetchRequest(method: 'GET', url: Uri.parse('http://127.0.0.1:${server.port}/'), timeout: const Duration(milliseconds: 100))), throwsA(isA<TimeoutException>()));
      expect(lookup, isNotNull);
    });
  });
}
