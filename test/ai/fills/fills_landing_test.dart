// The web's own answers for the fills' lookups, lanes, landings and sources (tool/ai_fixtures.mjs, section `landing`),
// held against lib/ai/fills/{web,lane,edits,source}.dart. Nothing here asks the network: every lookup is served the
// JSON recorded once from its source, by address.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/edits.dart';
import 'package:ghost_md/ai/fills/lane.dart';
import 'package:ghost_md/ai/fills/shape.dart';
import 'package:ghost_md/ai/fills/source.dart';
import 'package:ghost_md/ai/fills/web.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/fill_facts.dart';

final Map<String, Object?> fixture = (jsonDecode(File('test/ai/fixtures/fills_landing_web.json').readAsStringSync()) as Map).cast<String, Object?>();

Map<String, Object?> map(Object? value) => (value! as Map).cast<String, Object?>();
List<Object?> list(Object? value) => value! as List;

({int from, int to}) span(Object? value) => (from: map(value)['from']! as int, to: map(value)['to']! as int);

Place place(Object? value) {
  final p = map(value);
  return Place(name: p['name']! as String, country: p['country']! as String, latitude: (p['latitude']! as num).toDouble(), longitude: (p['longitude']! as num).toDouble());
}

LookupPlan plan(Object? value) {
  final p = map(value);
  return switch (p['kind']) {
    'weather' => LookupPlan.weather(place: p['place']! as String, days: span(p['days'])),
    'rates' => LookupPlan.rates(amount: (p['amount']! as num).toDouble(), from: p['from']! as String, to: p['to']! as String),
    'wiki' => LookupPlan.wiki(terms: p['terms']! as String),
    _ => LookupPlan.none(why: p['why']! as String),
  };
}

/// A plan as the page's JSON holds it, a whole amount written whole.
Object? planJson(LookupPlan plan) => jsonDecode(jsonEncode(plan.toJson()));

Object? foundJson(Found found) => found.ok
    ? {'ok': true, 'source': found.source, 'facts': found.facts, if (found.answer != null) 'answer': found.answer}
    : {'ok': false, 'why': found.why!.name, if (found.words != null) 'words': found.words};

List<Object?> claimsJson(List<Claim> claims) => [
      for (final claim in claims) {'property': claim.property, 'values': [for (final value in claim.values) value.toJson()]},
    ];

List<Claim> claimsOf(Object? json) => [
      for (final claim in list(json))
        (property: map(claim)['property']! as String, values: <ClaimValue>[for (final value in list(map(claim)['values'])) value is String ? ClaimText(value) : ClaimEntity(map(value)['entity']! as String)]),
    ];

FillSource sourceOf(Object? value) {
  final s = map(value);
  return switch (s['kind']) {
    'memory' => const FillSource.memory(),
    'note' => const FillSource.note(),
    _ => FillSource.web(s['name']! as String),
  };
}

/// Numbers as JSON holds them, so `1` and `1.0` are the same number.
Object? plain(Object? value) => jsonDecode(jsonEncode(value));

void main() {
  final web = map(fixture['web']);

  group('the lookups, against the web’s answers', () {
    test('the forecast’s lines and the app’s own answer', () {
      final jsons = list(web['forecastJsons']);
      final places = [for (final p in list(web['places'])) place(p)];
      for (final row in list(web['forecasts'])) {
        final r = map(row);
        final json = jsons[r['json']! as int];
        final days = span(r['days']);
        final why = 'forecast ${r['json']}, place ${r['place']}, days $days';
        expect(parseForecast(json, places[r['place']! as int], days), r['lines'], reason: why);
        expect(forecastAnswer(json, days), r['answer'], reason: why);
      }
    });

    test('the rate’s lines and the app’s own sum, every figure as the page writes it', () {
      final jsons = list(web['rateJsons']);
      for (final row in list(web['rates'])) {
        final r = map(row);
        final p = map(r['plan']);
        final json = jsons[r['json']! as int];
        final amount = (p['amount']! as num).toDouble();
        final why = 'rates ${r['json']}: ${jsonEncode(json)} × $amount';
        expect(parseRates(json, (amount: amount, from: p['from']! as String, to: p['to']! as String)), r['lines'], reason: why);
        expect(ratesAnswer(json, (amount: amount, to: p['to']! as String)), r['answer'], reason: why);
      }
    });

    test('a Wikidata quantity as a figure', () {
      for (final row in list(web['quantities'])) {
        final r = map(row);
        final json = {
          'entities': {
            'Q1': {
              'claims': {
                'P1082': [
                  {'rank': 'normal', 'mainsnak': {'datavalue': {'type': 'quantity', 'value': {'amount': r['amount']}}}},
                ],
              },
            },
          },
        };
        expect(claimsJson(parseWikidataClaims(json, 'Q1')), r['claims'], reason: '${r['amount']}');
      }
    });

    test('whether an answer stands in what came back', () {
      for (final row in list(web['stands'])) {
        final r = map(row);
        expect(standsIn(r['answer']! as String, r['facts']! as String), r['stands'], reason: '${r['answer']} in ${r['facts']}');
      }
    });

    test('Wikipedia’s pages, and the one the words name best', () {
      final jsons = list(web['wikiJsons']);
      final parsed = [for (final json in jsons) parseWikiSearch(json)];
      expect([for (final pages in parsed) [for (final page in pages) page.toJson()]], web['wiki']);
      final sets = [parsed[0], parsed[2], <WikiPage>[]];
      for (final row in list(web['best'])) {
        final r = map(row);
        expect(bestPage(sets[r['pages']! as int], r['terms']! as String)?.title, r['title'], reason: '${r['terms']} in ${r['pages']}');
      }
    });

    test('Wikidata’s claims and labels, and the lines made of them', () {
      final cases = list(web['claimJsons']);
      final claims = [for (final each in cases) parseWikidataClaims(map(each)['json'], map(each)['id']! as String)];
      expect([for (final each in claims) claimsJson(each)], web['claims']);
      final labelJsons = list(web['labelJsons']);
      expect([for (final json in labelJsons) parseWikidataLabels(json)], web['labels']);
      final cupPages = parseWikiSearch(list(web['wikiJsons'])[0]);
      final cupClaims = claimsOf(list(web['claims'])[0]);
      expect([
        wikiFacts(cupPages, null),
        wikiFacts(cupPages, (title: '2026 FIFA World Cup', claims: cupClaims, labels: parseWikidataLabels(labelJsons[0]))),
        wikiFacts(cupPages, (title: '2026 FIFA World Cup', claims: cupClaims, labels: const {})),
        wikiFacts(cupPages, (title: 'Made', claims: claims[2], labels: const {'Q42267': '  Spain  '})),
        wikiFacts(const [], (title: 'Made', claims: const [], labels: const {})),
        wikiFacts(const [], null),
      ], web['facts']);
    });

    test('the message, the addresses and the sentence for no source', () {
      for (final row in list(web['messages'])) {
        final r = map(row);
        expect(webMessage(r['message']! as String, r['source']! as String, r['facts']! as String), r['out']);
      }
      final all = map(web['urls']);
      final places = [for (final p in list(web['places'])) place(p)];
      for (final row in list(all['geocode'])) {
        expect(urls.geocode(list(row)[0]! as String), list(row)[1]);
      }
      for (final row in list(all['forecast'])) {
        expect(urls.forecast(places[list(row)[0]! as int], list(row)[1]! as int), list(row)[2]);
      }
      for (final row in list(all['rates'])) {
        expect(urls.rates(list(row)[0]! as String, list(row)[1]! as String), list(row)[2]);
      }
      for (final row in list(all['wiki'])) {
        expect(urls.wiki(list(row)[0]! as String), list(row)[1]);
      }
      for (final row in list(all['claims'])) {
        expect(urls.claims(list(row)[0]! as String), list(row)[1]);
      }
      for (final row in list(all['labels'])) {
        expect(urls.labels(list(list(row)[0]).cast<String>()), list(row)[1]);
      }
      expect(noSource, web['noSource']);
    });

    test('a lookup, start to end, over the recorded answers', () async {
      final sets = map(web['sets']);
      for (final row in list(web['lookups'])) {
        final r = map(row);
        final asked = <String>[];
        final answers = r['set'] == 'offline' ? null : map(sets[r['set']]);
        final found = await lookUp(plan(r['plan']), (url) async {
          if (answers == null) throw StateError('offline');
          asked.add(url);
          for (final MapEntry(key: part, value: json) in answers.entries) {
            if (url.contains(part)) return (status: 200, json: json);
          }
          return (status: 404, json: <String, Object?>{'message': 'not found'});
        });
        final why = '${jsonEncode(r['plan'])} over ${r['set']}';
        expect(asked, r['asked'], reason: why);
        expect(foundJson(found), r['found'], reason: why);
      }
    });
  });

  group('the lanes, against the web’s answers', () {
    test('every blank’s lane, with lookups on, held by Local only, and off', () {
      final clock = FactClock(now: DateTime(2026, 9, 28, 14, 5), zone: 'Europe/London');
      for (final row in list(fixture['lanes'])) {
        final r = map(row);
        final text = r['text']! as String;
        for (final lookups in Lookups.values) {
          final wanted = list(map(r['lanes'])[lookups.id]);
          final blanks = blanksIn(text);
          expect(blanks.length, wanted.length, reason: text);
          for (var i = 0; i < blanks.length; i += 1) {
            final lane = laneOf(blanks[i], text, LaneOptions(clock: clock, learntUntil: 2024, lookups: lookups));
            final got = {
              'lane': lane.lane,
              'can': lane is LiveLane ? lane.can.id : null,
              'plan': lane is LiveLane ? planJson(lane.plan) : null,
              'live': lane is LiveLane ? lane.live.toJson() : null,
              'worked': lane is WorkedLane ? lane.worked.toJson() : null,
              'cannot': lane is CannotLane ? lane.cannot.toJson() : null,
              'shape': switch (lane) { LiveLane(:final info) || ModelLane(:final info) => info.shape.name, _ => null },
              'fillable': fillable(lane),
            };
            expect(plain(got), plain(wanted[i]), reason: '$text, blank $i, lookups ${lookups.id}');
          }
        }
      }
    });
  });

  group('the landings, against the web’s answers', () {
    final edits = map(fixture['edits']);

    Landing landing(String text, Blank blank, List<String> words, FillSource source) =>
        Landing(from: blank.from, to: blank.to, question: blank.question, info: shapeOf(blank, text), words: words, source: source, model: 'Qwen3.5 4B', date: '2026-09-28');

    List<TextChange> changesOf(Object? json) => [
          for (final change in list(json)) TextChange(from: map(change)['from']! as int, to: map(change)['to']! as int, insert: map(change)['insert']! as String),
        ];

    test('one answer’s changes, for every blank, every shape of answer and every source', () {
      var held = 0;
      for (final row in list(edits['landings'])) {
        final r = map(row);
        final text = r['text']! as String;
        final blanks = blanksIn(text);
        for (final each in list(r['cases'])) {
          final c = map(each);
          final words = list(c['words']).cast<String>();
          final changes = landingChanges(text, landing(text, blanks[c['blank']! as int], words, sourceOf(c['source'])));
          final why = '$text, blank ${c['blank']}, $words';
          expect([for (final change in changes) change.toJson()], c['changes'], reason: why);
          expect(applyChanges(text, changes), c['applied'], reason: why);
          held += 1;
        }
      }
      expect(held, greaterThan(100));
    });

    test('every answer’s changes in one set, in the text’s order, with the signature', () {
      const sources = [FillSource.memory(), FillSource.note(), FillSource.web('Open-Meteo'), FillSource.web('Wikipedia and Wikidata')];
      for (final row in list(edits['all'])) {
        final r = map(row);
        final text = r['text']! as String;
        final blanks = blanksIn(text);
        final answers = [
          for (var b = 0; b < blanks.length; b += 1)
            landing(text, blanks[b], shapeOf(blanks[b], text).shape == Shape.items ? ['Item ${b}a', 'Item ${b}b'] : ['Answer $b'], sources[b % sources.length]),
        ];
        final changes = allChanges(text, answers.reversed.toList());
        expect([for (final change in changes) change.toJson()], r['changes'], reason: text);
        expect(applyChanges(text, changes), r['applied'], reason: text);
        final sign = signatureChange(text);
        expect(applyChanges(text, [...changes, ?sign]), r['signed'], reason: text);
      }
    });

    test('changes applied, the ones at one place in the order they came', () {
      for (final row in list(edits['applied'])) {
        final r = map(row);
        expect(applyChanges(r['text']! as String, changesOf(r['changes'])), r['out'], reason: '${r['text']} ${jsonEncode(r['changes'])}');
      }
    });

    test('the signature as a change of its own', () {
      for (final row in list(edits['signatures'])) {
        final r = map(row);
        final text = r['text']! as String;
        final change = signatureChange(text, r['owner'] as String?);
        expect(change?.toJson(), r['change'], reason: jsonEncode(text));
        expect(change == null ? text : applyChanges(text, [change]), r['out'], reason: jsonEncode(text));
      }
    });
  });

  group('the source, against the web’s answers', () {
    final source = map(fixture['source']);

    test('a text’s content words', () {
      for (final row in list(source['words'])) {
        expect(contentWords(map(row)['text']! as String), map(row)['words'], reason: '${map(row)['text']}');
      }
    });

    test('the note as a source reads it', () {
      for (final row in list(source['notes'])) {
        expect(noteForSource(map(row)['text']! as String), map(row)['out']);
      }
    });

    test('whether an answer is from this note', () {
      for (final row in list(source['from'])) {
        final r = map(row);
        final text = r['text']! as String;
        final blank = blanksIn(text).last;
        expect(fromThisNote(r['answer']! as String, blank, shapeOf(blank, text).shape, text, text), r['from'], reason: '${r['answer']} for $text');
      }
    });
  });
}
