// Live blanks, looked up by the phone (lib/ai/fills/web.dart). A port of src/app/ai/fills/web.test.ts, case for case.
// The web's own answers for a corpus are held in fills_landing_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/web.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/fill_live.dart';

/// An answer recorded from a source once (2026-09-28): src/app/ai/fills/recorded, copied to test/ai/fixtures/recorded.
Object? recordedJson(String name) => jsonDecode(File('test/ai/fixtures/recorded/$name.json').readAsStringSync());

final Object? forecast = recordedJson('forecast-lisbon');
final Object? geocodeLisbon = recordedJson('geocode-lisbon');
final Object? geocodeNowhere = recordedJson('geocode-nowhere');
final Object? ratesUnknown = recordedJson('rates-unknown');
final Object? rates = recordedJson('rates-usd-jpy');
final Object? wikiNothing = recordedJson('wiki-nothing');
final Object? wikiCup = recordedJson('wiki-world-cup');
final Object? wikidataLabels = recordedJson('wikidata-labels');
final Object? wikidataCup = recordedJson('wikidata-world-cup');

/// Answers recorded from each source once, served by address: the tests never touch the network.
FillFetcher recorded(Map<String, Object?> answers, [List<String>? asked]) => (url) async {
      asked?.add(url);
      for (final MapEntry(key: part, value: json) in answers.entries) {
        if (url.contains(part)) return (status: 200, json: json);
      }
      return (status: 404, json: <String, Object?>{'message': 'not found'});
    };

Future<({int status, Object? json})> offline(String url) async => throw StateError('offline');

final DateTime monday = DateTime(2026, 9, 28, 14, 5);

LookupPlan planFor(String text) {
  final blank = blanksIn(text).last;
  final live = cannotKnow(blank, text, 2024)!;
  return lookupPlan(live.kind, askingWords(blank, text), monday);
}

void main() {
  group('what a lookup asks', () {
    test('asks Open-Meteo for a named place, Frankfurter for two currencies, Wikipedia for the rest', () {
      expect(planFor('Weather in Lisbon tomorrow: {?weather}'), const LookupPlan.weather(place: 'Lisbon', days: (from: 1, to: 1)));
      expect(planFor('100 dollars is {?how many yen} yen.'), const LookupPlan.rates(amount: 100, from: 'USD', to: 'JPY'));
      expect(planFor('The 2026 World Cup was won by {?}'), const LookupPlan.wiki(terms: '2026 World Cup won'));
    });

    test('says so where no public source answers, or where the place is not named', () {
      expect(planFor('A return flight London to Tokyo costs {?price today}'), LookupPlan.none(why: noSource));
      expect(planFor('Kinkaku-ji opens at {?opening time}'), LookupPlan.none(why: noSource));
      final rain = planFor('Will it rain today? {?}');
      expect(rain.kind, LookupKind.none);
      expect(rain.why, contains('Name the place'));
    });
  });

  group('the parsers, on answers recorded from each source', () {
    test('reads Open-Meteo’s place and forecast', () {
      final place = parseGeocode(geocodeLisbon)!;
      expect(place.name, 'Lisbon');
      expect(place.country, 'Portugal');
      expect(parseGeocode(geocodeNowhere), isNull);
      final lines = parseForecast(forecast, place, (from: 1, to: 1))!;
      expect(lines, matches(RegExp(r'^Lisbon, Portugal, \w+day \d+ \w+ 2026: [a-z ]+, \d+ to \d+ °C, a \d+% chance of rain, wind up to \d+ km\/h\.$')));
      expect(parseForecast(forecast, place, (from: 0, to: 0))!.split('\n')[0], matches(RegExp(r'^Lisbon, Portugal, now: ')));
      expect(parseForecast(<String, Object?>{}, place, (from: 0, to: 0)), isNull);
    });

    test('reads Frankfurter’s rate, and the app turns the amount', () {
      expect(parseRates(rates, (amount: 100, from: 'USD', to: 'JPY')), "The European Central Bank's rate for Monday 28 September 2026: 1 USD is 156.88 JPY.\nSo 100 USD is 15,688 JPY.");
      expect(parseRates((ratesUnknown! as Map)['body'], (amount: 1, from: 'XXX', to: 'JPY')), isNull);
    });

    test('reads Wikipedia’s pages in its order, and picks the one the words name best', () {
      final pages = parseWikiSearch(wikiCup);
      expect([for (final p in pages) p.title], ['2026 FIFA World Cup Group B', '2026 FIFA World Cup knockout stage', '2026 FIFA World Cup']);
      expect(bestPage(pages, '2026 World Cup won')?.item, 'Q5020214');
      expect(parseWikiSearch(wikiNothing), isEmpty);
    });

    test('reads Wikidata’s winner and dates, and its labels', () {
      final claims = parseWikidataClaims(wikidataCup, 'Q5020214');
      expect(claims.where((c) => c.property == 'winner').firstOrNull?.values, const [ClaimEntity('Q42267')]);
      expect(claims.where((c) => c.property == 'until').firstOrNull?.values, const [ClaimText('19 July 2026')]);
      expect(parseWikidataLabels(wikidataLabels)['Q42267'], "Spain men's national football team");
    });
  });

  group('a lookup', () {
    test('asks only for the place, then its coordinates, and gives the forecast as facts', () async {
      final asked = <String>[];
      final found = await lookUp(
        const LookupPlan.weather(place: 'Lisbon', days: (from: 1, to: 1)),
        recorded({'geocoding-api.open-meteo.com': geocodeLisbon, 'api.open-meteo.com/v1/forecast': forecast}, asked),
      );
      expect(found.ok, isTrue);
      expect(found.source, 'Open-Meteo');
      expect(asked, [urls.geocode('Lisbon'), urls.forecast(parseGeocode(geocodeLisbon)!, 2)]);
    });

    test('asks Frankfurter for the two codes and never the amount', () async {
      final asked = <String>[];
      final found = await lookUp(const LookupPlan.rates(amount: 100, from: 'USD', to: 'JPY'), recorded({'api.frankfurter.dev': rates}, asked));
      expect(found.ok, isTrue);
      expect(found.source, 'Frankfurter');
      expect(asked, ['https://api.frankfurter.dev/v1/latest?base=USD&symbols=JPY']);
      expect(asked.join(' '), isNot(contains('100')));
    });

    test('asks Wikipedia for the question’s words, then Wikidata for the page they name best', () async {
      final asked = <String>[];
      final found = await lookUp(const LookupPlan.wiki(terms: '2026 World Cup won'), recorded({'en.wikipedia.org': wikiCup, 'props=claims': wikidataCup, 'props=labels': wikidataLabels}, asked));
      expect(found.ok, isTrue);
      expect(found.source, 'Wikipedia and Wikidata');
      expect(found.facts, contains('concluded on July 19 with Spain winning the championship'));
      expect(found.facts, contains("Wikidata on 2026 FIFA World Cup:\n- winner: Spain men's national football team\n- when: 2026"));
      expect(asked[0], urls.wiki('2026 World Cup won'));
    });

    test('keeps Wikipedia’s pages when Wikidata does not answer', () async {
      final found = await lookUp(const LookupPlan.wiki(terms: '2026 World Cup won'), recorded({'en.wikipedia.org': wikiCup}));
      expect(found.ok, isTrue);
      expect(found.source, 'Wikipedia');
    });

    test('says offline when the network fails, and nothing when a source had nothing', () async {
      expect(await lookUp(const LookupPlan.rates(amount: 1, from: 'USD', to: 'JPY'), offline), const Found.offline());
      expect(await lookUp(const LookupPlan.wiki(terms: 'qqq'), recorded({'en.wikipedia.org': wikiNothing})), const Found.nothing(words: 'Wikipedia had nothing on this.'));
      final nowhere = await lookUp(const LookupPlan.weather(place: 'Qqqzzxxy', days: (from: 0, to: 0)), recorded({'geocoding-api.open-meteo.com': geocodeNowhere}));
      expect(nowhere.ok, isFalse);
      expect(nowhere.why, FoundWhy.nothing);
    });
  });

  group('the message for a looked-up blank', () {
    test('puts what the source returned before the answer line', () {
      const message = 'Today is Monday 28 September 2026.\n\nThe note:\n# Lisbon\nWeather in Lisbon tomorrow: {?1 weather}\n\nAnswer blank 1.';
      expect(
        webMessage(message, 'Open-Meteo', 'Lisbon, Portugal, Tuesday 29 September 2026: rain.'),
        'Today is Monday 28 September 2026.\n\nThe note:\n# Lisbon\nWeather in Lisbon tomorrow: {?1 weather}\n\nWhat Open-Meteo returned:\nLisbon, Portugal, Tuesday 29 September 2026: rain.\n\nAnswer blank 1.',
      );
    });
  });
}
