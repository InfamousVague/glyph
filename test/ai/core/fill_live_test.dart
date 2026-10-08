// What the model can't know offline, and what a lookup would ask. A port of src/app/core/fillLive.test.ts, case for
// case, and after it the web's own answers for a corpus of notes (tool/ai_fixtures.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/fill_live.dart';

/// The screen over the last blank of [text], for a model taken to know up to 2024.
LiveKind? live(String text, [int learntUntil = 2024]) => cannotKnow(blanksIn(text).last, text, learntUntil)?.kind;
Asking asking(String text) => askingWords(blanksIn(text).last, text);

void main() {
  group('what the model can’t know offline', () {
    test('refuses the scenarios that need something live or newer', () {
      expect(live('Weather in Lisbon today: {?weather}'), LiveKind.weather);
      // A place named is enough for the weather, with no word for now: "weather in Tokyo" means now, and went to the
      // model before (Matt: it never fills on mobile).
      expect(live('Weather in Lisbon: {?}'), LiveKind.weather);
      expect(live('The weather in Tokyo is {?}'), LiveKind.weather);
      expect(live('The forecast for New York: {?}'), LiveKind.weather);
      expect(live('A return flight London to Tokyo costs {?price today}'), LiveKind.prices);
      // Found by the shots: a fare asked with "cheapest" went to the model, which could only say it did not know.
      expect(live('Cheapest flight to Lisbon today: {?}'), LiveKind.prices);
      expect(live('The cheapest hotel in Porto tomorrow night is {?}'), LiveKind.prices);
      expect(live('The 2026 World Cup was won by {?}'), LiveKind.after);
      expect(live('100 dollars is {?how many yen} yen.'), LiveKind.money);
      expect(live('Kinkaku-ji opens at {?opening time}'), LiveKind.hours);
      expect(live('The newest Pixel is the {?}'), LiveKind.newest);
      expect(live('Q: Who won the 2026 World Cup?\nA: {?}'), LiveKind.after);
      expect(live('Bitcoin is worth {?} now.'), LiveKind.markets);
      expect(live('Next train to Brighton: {?}'), LiveKind.transport);
      expect(live('Who won last night? {?}'), LiveKind.news);
    });

    test('lets through what stays true from month to month', () {
      for (final text in [
        'Flights are cheapest to Tokyo on {?what day / time?}',
        'The capital of Australia is {?}.',
        'Priya: export bug fixed, lands today.\n\nIn one line: {?summary}',
        '| Book | Author |\n| --- | --- |\n| The Remains of the Day | {?} |',
        'Petrichor: {?what it means}',
        '1 cup of plain flour is about {?grams} grams.',
        'The 2022 World Cup was won by {?}',
        'Opening line, friendlier: {?a friendlier way to say: fix the boiler now}',
        '{?how long to boil an egg}',
        'What’s the average lifespan of a cat? {?}',
        'If it rains tomorrow what do we do? {?}',
        'The latest check-out time is {?}',
        'Our 2026 trip: flights are cheapest on {?}',
        // Past weather is a thing the model may know; only "now" needs the live look-up.
        'The weather in Tokyo back in 1990 was {?}',
        'What was the weather in Lisbon on our wedding day? {?}',
      ]) {
        expect(live(text), isNull, reason: text);
      }
    });

    test('keeps the horizon a fixed year per model, never the clock', () {
      expect(live('The 2022 World Cup was won by {?}', 2024), isNull);
      expect(live('The 2025 World Cup was won by {?}', 2024), LiveKind.after);
      expect(live('The 2026 World Cup was won by {?}', 2024), LiveKind.after);
      expect(live('The 2026 World Cup was won by {?}', 2026), isNull);
    });

    test('never reads “who won” as a currency', () {
      expect(live('Who won the 2022 World Cup? {?}'), isNull);
    });
  });

  group('what a lookup would ask', () {
    test('reads the amount and the two currencies', () {
      expect(moneyAsked(asking('100 dollars is {?how many yen} yen.')), (amount: 100, from: 'USD', to: 'JPY'));
      expect(moneyAsked(asking('€250 in pounds: {?}')), (amount: 250, from: 'EUR', to: 'GBP'));
      expect(moneyAsked(asking('1,000 USD is {?} EUR')), (amount: 1000, from: 'USD', to: 'EUR'));
    });

    test('reads the place and the day for the weather', () {
      expect(placeAsked(asking('Weather in Lisbon today: {?weather}')), 'Lisbon');
      expect(placeAsked(asking('The forecast for New York tomorrow: {?}')), 'New York');
      expect(placeAsked(asking('Will it rain today? {?}')), isNull);
      final monday = DateTime(2026, 9, 28);
      expect(dayAsked(asking('Weather in Lisbon tomorrow: {?}'), monday), (from: 1, to: 1));
      expect(dayAsked(asking('Weather in Lisbon this weekend: {?}'), monday), (from: 5, to: 6));
    });

    test('searches for the question’s own words, the small ones left out', () {
      expect(searchWords(asking('The 2026 World Cup was won by {?}')), '2026 World Cup won');
      expect(searchWords(asking('Q: Who won the 2026 World Cup?\nA: {?}')), 'won 2026 World Cup');
      // "newest" is kept: a search for plain "Pixel" found the picture element (the review of §145).
      expect(searchWords(asking('The newest Pixel is the {?}')), 'newest Pixel');
    });

    test('sends the braces’ own question alone, and never the rest of the sentence or the one before', () {
      expect(searchWords(asking('Sarah Jones owes me £450 for rent. {?who won the 2026 World Cup}')), 'won 2026 World Cup');
      expect(searchWords(asking('My HIV test results came back and Dr Patel said to ask who won the 2026 World Cup {?}')), 'won 2026 World Cup');
      expect(searchWords(asking('Told Dr Patel about my knee, and he asked who won the 2026 World Cup {?}')), 'won 2026 World Cup');
    });

    test('takes a place only from the question or its own clause, never a person or a language', () {
      expect(placeAsked(asking('Weather for Sarah’s wedding in Lisbon tomorrow: {?}')), 'Lisbon');
      expect(placeAsked(asking('Q: Will it rain at Dr Patel’s clinic tomorrow? A: {?}')), isNull);
      expect(placeAsked(asking('- Will it rain tomorrow? {?in Italian}')), isNull);
    });
  });

  // ---- beyond the page's own cases ----------------------------------------------------------------------------------

  group('the web’s own answers (tool/ai_fixtures.mjs)', () {
    test('every note of the corpus: the screen at two horizons, the money, the place, the days, the search, the clause', () {
      final cases = (jsonDecode(File('test/ai/fixtures/fill_live_web.json').readAsStringSync()) as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThan(70));
      for (final one in cases) {
        final text = one['text']! as String;
        final blank = blanksIn(text).last;
        final words = askingWords(blank, text);
        final lives = one['live']! as Map<String, Object?>;
        expect(cannotKnow(blank, text, 2024)?.toJson(), lives['2024'], reason: text);
        expect(cannotKnow(blank, text, 2026)?.toJson(), lives['2026'], reason: text);
        final money = moneyAsked(words);
        expect(money == null ? null : {'amount': money.amount, 'from': money.from, 'to': money.to}, one['money'], reason: text);
        expect(placeAsked(words), one['place'], reason: text);
        final days = [
          for (var i = 0; i < 7; i += 1) dayAsked(words, DateTime(2026, 9, 28 + i, 12)),
        ];
        expect([for (final day in days) {'from': day.from, 'to': day.to}], one['days'], reason: text);
        expect(searchWords(words), one['search'], reason: text);
        expect(askingClause(words), one['clause'], reason: text);
      }
    });

    test('the panel’s sentence for each kind', () {
      expect(liveWords(LiveKind.after, 2026), '2026 is after what the model learnt. It would only be guessing.');
      expect(liveWords(LiveKind.after), 'That year is after what the model learnt. It would only be guessing.');
      expect(LiveKind.values.map((kind) => kind.name), ['weather', 'prices', 'money', 'markets', 'hours', 'newest', 'after', 'news', 'transport']);
    });
  });
}
