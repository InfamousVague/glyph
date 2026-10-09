/// Live blanks, looked up by the phone itself (docs/DESIGN.md §145). A port of `src/app/ai/fills/web.ts`. Matt, asked
/// where an answer that needs live facts comes from once the phone is online: "Phone looks it up, all local". So
/// there is no Ghost.md server and no account in it: the app asks a public source that needs no key, and the model on
/// the phone writes the answer from what came back, marked in the file as from the web with the source named.
///
/// - **Open-Meteo** for the weather: its geocoder for the place named, then its forecast for those coordinates.
/// - **Frankfurter** for exchange rates: the European Central Bank's reference rates. The sum is the app's own.
/// - **Wikipedia** for news, results, the newest of anything and events after a model's training: its search, with
///   the first sentences of the pages it finds, and **Wikidata** for the facts of the page the question names best (a
///   tournament's winner, a release's date).
///
/// No general web search lets a page call it with no key: DuckDuckGo's result pages refuse a script (403), and its
/// instant-answer API, which does allow one, answers only from Wikipedia's topics (nothing for "newest Pixel phone" or
/// "cheapest day to fly to Tokyo", checked 2026-09-28). So Wikipedia's own search is the search source. Prices, fares,
/// markets, opening hours and transport have no public source that allows it, and say so; Ask the model anyway stays.
///
/// Only what the question needs leaves the phone, and only to the one source asked: a place's name and then its
/// coordinates, two currency codes (never the amount), or the question's own words. Never the note. The parsers are
/// pure and tested on answers recorded once (test/ai/fixtures/recorded, the page's src/app/ai/fills/recorded), never
/// the network.
///
/// What differs:
/// - The shapes. A [LookupPlan] and a [Found] are one class each with the web's `kind` and `ok`/`why` and a
///   constructor a case; a Wikidata value is a [ClaimValue], words or an entity's id; a claim is a record; `URLS` is
///   [urls]; `NO_SOURCE` is the getter [noSource], since its words depend on the device, and `isMacApp`
///   (core/platform.ts) is [isMacApp] here until lib/core has it.
/// - `Fetcher` is [FillFetcher], so a file may import this beside lib/account/api.dart, whose `Fetcher` is another
///   thing; what it answers is a record.
/// - `pageFetch` was the browser's `fetch`. Here it is [pageFetcher] over `dart:io`, kept as [pageFetch]: ten seconds
///   at most, no cookies kept or sent, and it follows NO redirect, where a browser's fetch follows them: an address
///   in [urls] answers where it is, and one that has moved is a 3xx with nothing read from it, so the question's
///   words never go on to a host this file does not name. It tells the app's name ([geocodeUserAgent]), where a page
///   sent its browser's; Wikimedia refuses a client that names nothing. There is no `navigator.onLine` to ask first:
///   a request that cannot be made is `offline` all the same.
/// - No address here is the app's own service (ghostmarkdown.com), so there is no debug-build guard to keep.
/// - A figure is written as `toLocaleString('en-GB')` wrote it, by hand ([_figure]): Dart has no such formatter
///   without a package. The weekday of a weekend's forecast is English by a table, as `en-GB` gave it.
/// - JSON of another type than the source's own (a date that is a number, a list where an object goes) reads as
///   absent. On the page some of those threw a TypeError, which a lookup then called `offline`; here it is `nothing`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/blanks.dart';
import '../../core/fill_live.dart';
import '../../core/geocode.dart' show geocodeUserAgent;
import '../../core/item_syntax.dart' show jsTrim;
import '../support/stamp.dart' show weekdayName;
import '../support/unaccent.dart';
import 'message.dart';

/// Whether this is the Mac app (`isMacApp`, core/platform.ts): its sentences say "this Mac" where the phone's say
/// "the phone".
bool get isMacApp => defaultTargetPlatform == TargetPlatform.macOS;

/// The kinds of lookup; each name is the page's own word.
enum LookupKind { weather, rates, wiki, none }

/// What a lookup asks, decided from the words alone (`LookupPlan`).
@immutable
class LookupPlan {
  /// Open-Meteo, for [place] over [days], counted from today.
  const LookupPlan.weather({required String this.place, required ({int from, int to}) this.days})
      : kind = LookupKind.weather,
        amount = null,
        from = null,
        to = null,
        terms = null,
        why = null;

  /// Frankfurter, for [amount] of [from] in [to].
  const LookupPlan.rates({required double this.amount, required String this.from, required String this.to})
      : kind = LookupKind.rates,
        place = null,
        days = null,
        terms = null,
        why = null;

  /// Wikipedia, searched for [terms].
  const LookupPlan.wiki({required String this.terms})
      : kind = LookupKind.wiki,
        place = null,
        days = null,
        amount = null,
        from = null,
        to = null,
        why = null;

  /// No lookup, and [why].
  const LookupPlan.none({required String this.why})
      : kind = LookupKind.none,
        place = null,
        days = null,
        amount = null,
        from = null,
        to = null,
        terms = null;

  final LookupKind kind;
  final String? place;
  final ({int from, int to})? days;
  final double? amount;
  final String? from;
  final String? to;
  final String? terms;
  final String? why;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => switch (kind) {
        LookupKind.weather => {'kind': 'weather', 'place': place, 'days': {'from': days!.from, 'to': days!.to}},
        LookupKind.rates => {'kind': 'rates', 'amount': amount, 'from': from, 'to': to},
        LookupKind.wiki => {'kind': 'wiki', 'terms': terms},
        LookupKind.none => {'kind': 'none', 'why': why},
      };

  @override
  bool operator ==(Object other) =>
      other is LookupPlan && other.kind == kind && other.place == place && other.days == days && other.amount == amount && other.from == from && other.to == to && other.terms == terms && other.why == why;

  @override
  int get hashCode => Object.hash(kind, place, days, amount, from, to, terms, why);

  @override
  String toString() => 'LookupPlan(${toJson()})';
}

/// The sentence for a live blank no public source can answer (`NO_SOURCE`).
String get noSource => 'No public source ${isMacApp ? 'this Mac' : 'the phone'} can ask answers this.';

/// What a lookup for a live blank would ask, or why there is none.
LookupPlan lookupPlan(LiveKind kind, Asking asking, DateTime now) {
  switch (kind) {
    case LiveKind.weather:
      final place = placeAsked(asking);
      return place != null && place.isNotEmpty
          ? LookupPlan.weather(place: place, days: dayAsked(asking, now))
          : LookupPlan.none(why: 'Name the place, as in “Weather in Lisbon today”, and ${isMacApp ? 'this Mac' : 'the phone'} can look it up.');
    case LiveKind.money:
      final money = moneyAsked(asking);
      return money != null
          ? LookupPlan.rates(amount: money.amount, from: money.from, to: money.to)
          : const LookupPlan.none(why: 'Name both currencies and an amount, as in “100 dollars is {?how many yen} yen”.');
    case LiveKind.newest || LiveKind.after || LiveKind.news:
      final terms = searchWords(asking);
      return terms.isNotEmpty ? LookupPlan.wiki(terms: terms) : LookupPlan.none(why: noSource);
    case LiveKind.prices || LiveKind.markets || LiveKind.hours || LiveKind.transport:
      return LookupPlan.none(why: noSource);
  }
}

/// The source a plan asks, as the answer's bracket names it.
String? sourceName(LookupPlan plan) => switch (plan.kind) {
      LookupKind.weather => 'Open-Meteo',
      LookupKind.rates => 'Frankfurter',
      LookupKind.wiki => 'Wikipedia',
      LookupKind.none => null,
    };

// ---- the parsers ----------------------------------------------------------------------------------------------------

/// A place as Open-Meteo's geocoder names it (`Place`).
@immutable
class Place {
  const Place({required this.name, required this.country, required this.latitude, required this.longitude});

  final String name;
  final String country;
  final double latitude;
  final double longitude;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => {'name': name, 'country': country, 'latitude': latitude, 'longitude': longitude};

  @override
  bool operator ==(Object other) => other is Place && other.name == name && other.country == country && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, country, latitude, longitude);

  @override
  String toString() => 'Place($name, $country, $latitude, $longitude)';
}

/// [value] as a JSON object, or null for anything else.
Map<Object?, Object?>? _object(Object? value) => value is Map ? value : null;

/// [value] as a JSON array, or null for anything else.
List<Object?>? _array(Object? value) => value is List ? value : null;

/// The item of a JSON array at [index], or null for none, as `list?.[index]` reads one.
Object? _at(Object? list, int index) {
  final all = _array(list);
  return all != null && index >= 0 && index < all.length ? all[index] : null;
}

/// Open-Meteo's geocoder, its first place; null for none.
Place? parseGeocode(Object? json) {
  final first = _object(_at(_object(json)?['results'], 0));
  if (first == null) return null;
  final latitude = first['latitude'];
  final longitude = first['longitude'];
  if (latitude is! num || longitude is! num) return null;
  final name = first['name'];
  final country = first['country'];
  return Place(name: name is String ? name : '', country: country is String ? country : '', latitude: latitude.toDouble(), longitude: longitude.toDouble());
}

/// The WMO weather codes Open-Meteo reports, in words (`WEATHER_CODES`), by the code as JavaScript writes it.
const Map<String, String> _weatherCodes = {
  '0': 'clear sky',
  '1': 'mainly clear',
  '2': 'partly cloudy',
  '3': 'overcast',
  '45': 'fog',
  '48': 'freezing fog',
  '51': 'light drizzle',
  '53': 'drizzle',
  '55': 'heavy drizzle',
  '56': 'freezing drizzle',
  '57': 'freezing drizzle',
  '61': 'light rain',
  '63': 'rain',
  '65': 'heavy rain',
  '66': 'freezing rain',
  '67': 'freezing rain',
  '71': 'light snow',
  '73': 'snow',
  '75': 'heavy snow',
  '77': 'snow grains',
  '80': 'rain showers',
  '81': 'rain showers',
  '82': 'heavy rain showers',
  '85': 'snow showers',
  '86': 'heavy snow showers',
  '95': 'thunderstorms',
  '96': 'thunderstorms with hail',
  '99': 'thunderstorms with hail',
};

/// A number as JavaScript writes one in a string: no `.0` on a whole number, and no minus on nought.
String _number(num value) {
  final double n = value.toDouble();
  if (n == 0) return '0';
  return n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21 ? n.toStringAsFixed(0) : n.toString();
}

/// The words of a weather code, or null for one the table lacks.
String? _weatherWords(Object? code) => _weatherCodes[code == null ? '-1' : (code is num ? _number(code) : '$code')];

/// `Math.round`: the nearest whole number, a half going up.
double _jsRound(double value) {
  if (!value.isFinite) return value;
  final floor = value.floorToDouble();
  return value - floor >= 0.5 ? floor + 1 : floor;
}

String _round(num n) => _number(_jsRound(n.toDouble()));

final RegExp _numberText = RegExp(r'^[+-]?(?:\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|Infinity)$');

/// `Number(text)` for the pieces of a date: a number's own writing, nought for nothing, else not a number.
double _numberOf(String? text) {
  if (text == null) return double.nan;
  final trimmed = jsTrim(text);
  if (trimmed.isEmpty) return 0;
  return _numberText.hasMatch(trimmed) ? double.parse(trimmed) : double.nan;
}

/// A source's `2026-09-28` at midday on the device's own calendar (`new Date(y, m - 1, d, 12)`), or null for what
/// JavaScript calls an invalid date.
DateTime? _dayOf(Object? iso) {
  final parts = (iso is String ? iso : '').split('-');
  final y = _numberOf(parts[0]);
  final m = _numberOf(parts.length > 1 ? parts[1] : null);
  final d = _numberOf(parts.length > 2 ? parts[2] : null);
  if (!y.isFinite || !m.isFinite || !d.isFinite) return null;
  final year = y.truncate();
  return DateTime(year >= 0 && year <= 99 ? 1900 + year : year, m.truncate(), d.truncate(), 12);
}

/// [modelDay] of a source's date; what the page wrote for a date it could not read, where there is none.
String _modelDayOf(Object? iso) {
  final date = _dayOf(iso);
  return date == null ? 'undefined NaN undefined NaN' : modelDay(date);
}

/// Open-Meteo's forecast for the days asked, as the lines the model reads; null when it has none of them.
String? parseForecast(Object? json, Place place, ({int from, int to}) days) {
  final forecast = _object(json);
  final daily = _object(forecast?['daily']);
  final time = _array(daily?['time']);
  if (daily == null || time == null || time.isEmpty) return null;
  final lines = <String>[];
  final where = place.country.isNotEmpty ? '${place.name}, ${place.country}' : place.name;
  final now = _object(forecast?['current']);
  if (days.from == 0 && now != null && now['temperature_2m'] is num) {
    final wind = now['wind_speed_10m'];
    lines.add('$where, now: ${_weatherWords(now['weather_code']) ?? 'weather unknown'}, ${_round(now['temperature_2m']! as num)} °C, wind ${_round(wind is num ? wind : 0)} km/h.');
  }
  for (var d = days.from; d <= days.to && d < time.length; d += 1) {
    final words = _weatherWords(_at(daily['weather_code'], d)) ?? 'weather unknown';
    final low = _at(daily['temperature_2m_min'], d);
    final high = _at(daily['temperature_2m_max'], d);
    final rain = _at(daily['precipitation_probability_max'], d);
    final wind = _at(daily['wind_speed_10m_max'], d);
    final parts = [words];
    if (low is num && high is num) parts.add('${_round(low)} to ${_round(high)} °C');
    if (rain is num) parts.add('a ${_number(rain)}% chance of rain');
    if (wind is num) parts.add('wind up to ${_round(wind)} km/h');
    lines.add('$where, ${_modelDayOf(_at(time, d))}: ${parts.join(', ')}.');
  }
  return lines.isNotEmpty ? lines.join('\n') : null;
}

final RegExp _grouping = RegExp(r'\B(?=(\d{3})+$)');
final RegExp _leadingNoughts = RegExp(r'^0+(?=\d)');
final RegExp _trailingNoughts = RegExp(r'0+$');

/// A number that is nought or more, as its digits before and after the point: the shortest that read back as it,
/// which is what `toLocaleString` rounds from.
({String whole, String fraction}) _digits(double value) {
  var text = value.toString();
  var exponent = 0;
  final e = text.indexOf('e');
  if (e >= 0) {
    exponent = int.parse(text.substring(e + 1));
    text = text.substring(0, e);
  }
  final dot = text.indexOf('.');
  var whole = dot < 0 ? text : text.substring(0, dot);
  var fraction = dot < 0 ? '' : text.substring(dot + 1);
  if (exponent > 0) {
    fraction = fraction.padRight(exponent, '0');
    whole = '$whole${fraction.substring(0, exponent)}';
    fraction = fraction.substring(exponent);
  } else if (exponent < 0) {
    whole = whole.padLeft(1 - exponent, '0');
    fraction = '${whole.substring(whole.length + exponent)}$fraction';
    whole = whole.substring(0, whole.length + exponent);
  }
  return (whole: whole.replaceFirst(_leadingNoughts, ''), fraction: fraction.replaceFirst(_trailingNoughts, ''));
}

/// A run of digits with one added to it.
String _bumped(String digits) {
  final figures = digits.codeUnits.toList();
  for (var i = figures.length - 1; i >= 0; i -= 1) {
    if (figures[i] < 0x39) {
      figures[i] += 1;
      return String.fromCharCodes(figures);
    }
    figures[i] = 0x30;
  }
  return '1${String.fromCharCodes(figures)}';
}

/// A figure as a person reads it: grouped, at most two decimals, four under ten (`figure`, the page's
/// `toLocaleString('en-GB', {maximumFractionDigits})`, a half going away from nought).
String _figure(double n) {
  if (n.isNaN) return 'NaN';
  if (n.isNegative) return '-${_figureOf(-n, n < 10 ? 4 : 2)}';
  return _figureOf(n, n < 10 ? 4 : 2);
}

String _figureOf(double value, int most) {
  if (value.isInfinite) return '∞';
  var (:whole, :fraction) = _digits(value);
  if (fraction.length > most) {
    final up = fraction.codeUnitAt(most) >= 0x35;
    fraction = fraction.substring(0, most);
    if (up) {
      final all = _bumped('$whole$fraction');
      whole = all.substring(0, all.length - most);
      fraction = all.substring(all.length - most);
      if (whole.isEmpty) whole = '0';
    }
    fraction = fraction.replaceFirst(_trailingNoughts, '');
  }
  whole = whole.replaceAllMapped(_grouping, (_) => ',');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

/// The amount turned at a rate, to the cent (`Math.round(amount * rate * 100) / 100`).
double _turned(double amount, num rate) => _jsRound(amount * rate.toDouble() * 100) / 100;

/// Frankfurter's rate, and the amount turned by the app, as the lines the model reads; null for a pair it does not
/// know.
String? parseRates(Object? json, ({double amount, String from, String to}) plan) {
  final rates = _object(json);
  final rate = _object(rates?['rates'])?[plan.to];
  final date = rates?['date'];
  if (rate is! num || date is! String || date.isEmpty) return null;
  final day = _modelDayOf(date);
  return "The European Central Bank's rate for $day: 1 ${plan.from} is ${_figure(rate.toDouble())} ${plan.to}.\nSo ${_figure(plan.amount)} ${plan.from} is ${_figure(_turned(plan.amount, rate))} ${plan.to}.";
}

/// The weather's answer, written by the app from the forecast: "Rain showers, 19 to 25 °C", or one such part a day for
/// a weekend. The model never writes it, so nothing it says can be marked as Open-Meteo's without being Open-Meteo's.
String? forecastAnswer(Object? json, ({int from, int to}) days) {
  final daily = _object(_object(json)?['daily']);
  final time = _array(daily?['time']);
  if (daily == null || time == null || time.isEmpty) return null;
  final parts = <String>[];
  for (var d = days.from; d <= days.to && d < time.length; d += 1) {
    final words = _weatherWords(_at(daily['weather_code'], d));
    if (words == null || words.isEmpty) continue;
    final low = _at(daily['temperature_2m_min'], d);
    final high = _at(daily['temperature_2m_max'], d);
    final temps = low is num && high is num ? ', ${_round(low)} to ${_round(high)} °C' : '';
    final text = '$words$temps';
    if (days.to > days.from) {
      final date = _dayOf(_at(time, d));
      final weekday = date == null ? 'Invalid Date' : weekdayName(date);
      parts.add('$weekday $text');
    } else {
      parts.add(text);
    }
  }
  if (parts.isEmpty) return null;
  final joined = parts.join(', then ');
  return joined.substring(0, 1).toUpperCase() + joined.substring(1);
}

/// The exchange's answer, worked out by the app from the ECB's rate: "67.06 USD".
String? ratesAnswer(Object? json, ({double amount, String to}) plan) {
  final rate = _object(_object(json)?['rates'])?[plan.to];
  if (rate is! num) return null;
  return '${_figure(_turned(plan.amount, rate))} ${plan.to}';
}

final RegExp _digitCommaDigit = RegExp(r'(\d),(\d)');
final RegExp _numbers = RegExp(r'\d+(?:\.\d+)?');
final RegExp _letters = RegExp(r'[\p{L}]+', unicode: true);
final RegExp _trailingS = RegExp(r's$');

/// A text as [standsIn] compares it: lower case, accents folded, a number's commas out.
String _fold(String text) => unaccented(text.toLowerCase()).replaceAllMapped(_digitCommaDigit, (m) => '${m.group(1)}${m.group(2)}');

/// Whether a model's answer stands in what a source returned: every number in it, and every content word, is in the
/// facts. Measured before this: the 2B landed seven of eight answers wrong "from Wikipedia" ("newest" for the newest
/// Pixel, a 2024 winner for 2025), each marked as the web's. An answer the facts do not hold is not the web's, and
/// does not land as it.
bool standsIn(String answer, String facts) {
  final have = _fold(facts);
  final said = _fold(answer);
  final numbers = [for (final match in _numbers.allMatches(said)) match.group(0)!];
  if (numbers.any((n) => !have.contains(n))) return false;
  final words = [
    for (final match in _letters.allMatches(said))
      if (match.group(0)!.length >= 3 && !_small.contains(match.group(0))) match.group(0)!,
  ];
  if (words.isEmpty && numbers.isEmpty) return false;
  final haveWords = {for (final match in _letters.allMatches(have)) match.group(0)!.replaceFirst(_trailingS, '')};
  return words.every((w) => haveWords.contains(w.replaceFirst(_trailingS, '')));
}

final Set<String> _small = 'the and for with from that this was were are its his her their has had have been into over than then about after before'.split(' ').toSet();

/// A page Wikipedia's search found (`WikiPage`).
@immutable
class WikiPage {
  const WikiPage({required this.title, required this.extract, required this.item});

  final String title;
  final String extract;

  /// Its Wikidata item, `Q5020214`, or null.
  final String? item;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => {'title': title, 'extract': extract, 'item': item};

  @override
  bool operator ==(Object other) => other is WikiPage && other.title == title && other.extract == extract && other.item == item;

  @override
  int get hashCode => Object.hash(title, extract, item);

  @override
  String toString() => 'WikiPage($title, $item, $extract)';
}

final RegExp _spaces = RegExp(r'\s+');

/// Wikipedia's search, the pages in its order with the first sentences of each; empty for none.
List<WikiPage> parseWikiSearch(Object? json) {
  final pages = [for (final page in _array(_object(_object(json)?['query'])?['pages']) ?? const <Object?>[]) _object(page)].nonNulls.toList();
  num indexOf(Map<Object?, Object?> page) => page['index'] is num ? page['index']! as num : 0;
  // The search's own order, pages with the same place left as they came (JavaScript's sort keeps them so).
  final order = [for (var i = 0; i < pages.length; i += 1) i]
    ..sort((a, b) {
      final by = indexOf(pages[a]).compareTo(indexOf(pages[b]));
      return by != 0 ? by : a - b;
    });
  final out = <WikiPage>[];
  for (final i in order) {
    final page = pages[i];
    final title = page['title'];
    final extract = page['extract'];
    if (title is! String || title.isEmpty || extract is! String || jsTrim(extract).isEmpty) continue;
    final item = _object(page['pageprops'])?['wikibase_item'];
    out.add(WikiPage(title: title, extract: jsTrim(extract.replaceAll(_spaces, ' ')), item: item is String ? item : null));
  }
  return out;
}

/// The page the search words name best: most of them in its title, then the fewest other words in it, then the
/// search's own order. "2026 World Cup won" names "2026 FIFA World Cup" before "2026 FIFA World Cup Group B".
WikiPage? bestPage(List<WikiPage> pages, String terms) {
  final words = terms.toLowerCase().split(_spaces).where((w) => w.isNotEmpty).toList();
  WikiPage? best;
  var score = -1;
  int? extra;
  for (final page in pages) {
    final title = page.title.toLowerCase();
    final here = words.where(title.contains).length;
    final others = title.split(_spaces).length - here;
    if (here > score || (here == score && (extra == null || others < extra))) {
      best = page;
      score = here;
      extra = others;
    }
  }
  return best;
}

/// The Wikidata properties worth a live answer, in words (`PROPERTIES`), in the order they are read.
const Map<String, String> _properties = {
  'P1346': 'winner',
  'P585': 'when',
  'P580': 'from',
  'P582': 'until',
  'P577': 'published',
  'P348': 'version',
  'P1082': 'population',
  'P6': 'head of government',
  'P35': 'head of state',
  'P169': 'chief executive',
  'P156': 'followed by',
  'P155': 'follows',
};

/// One value of a Wikidata claim: words as they are ([ClaimText]), or another entity by its id ([ClaimEntity]), the
/// page's `string | { entity: string }`.
@immutable
sealed class ClaimValue {
  const ClaimValue();

  /// The value as the page holds it: the words, or `{entity: id}`.
  Object toJson();
}

/// A claim's value in words: a date, a figure, a version.
final class ClaimText extends ClaimValue {
  const ClaimText(this.text);

  final String text;

  @override
  Object toJson() => text;

  @override
  bool operator ==(Object other) => other is ClaimText && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ClaimText($text)';
}

/// A claim's value that is another entity, by its id: `Q42267`.
final class ClaimEntity extends ClaimValue {
  const ClaimEntity(this.entity);

  final String entity;

  @override
  Object toJson() => {'entity': entity};

  @override
  bool operator ==(Object other) => other is ClaimEntity && other.entity == entity;

  @override
  int get hashCode => Object.hash('entity', entity);

  @override
  String toString() => 'ClaimEntity($entity)';
}

/// An entity's claims under one property: the property's word and its values.
typedef Claim = ({String property, List<ClaimValue> values});

const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
final RegExp _wikidataTime = RegExp(r'^\+?(\d{4})-(\d{2})-(\d{2})');

/// A Wikidata date in words, as precise as it is: a year, a month, or a day.
String? _wikidataDate(Object? value) {
  final time = _object(value)?['time'];
  final found = _wikidataTime.firstMatch(time is String ? time : '');
  if (found == null) return null;
  final y = int.parse(found.group(1)!);
  final m = int.parse(found.group(2)!);
  final d = int.parse(found.group(3)!);
  final said = _object(value)?['precision'];
  final num precision = said is num ? said : 11;
  if (precision <= 9 || m == 0) return '$y';
  final month = m >= 1 && m <= 12 ? _months[m - 1] : 'undefined';
  if (precision == 10 || d == 0) return '$month $y';
  return '$d $month $y';
}

/// An entity's claims worth reading, each as its property's word and its values, the entities among them by id.
List<Claim> parseWikidataClaims(Object? json, String id) {
  final claims = _object(_object(_object(_object(json)?['entities'])?[id])?['claims']) ?? const <Object?, Object?>{};
  final out = <Claim>[];
  for (final MapEntry(:key, value: word) in _properties.entries) {
    final list = [for (final claim in _array(claims[key]) ?? const <Object?>[]) _object(claim)].nonNulls.toList();
    if (list.isEmpty) continue;
    final preferred = list.where((c) => c['rank'] == 'preferred').toList();
    final values = <ClaimValue>[];
    for (final claim in (preferred.isNotEmpty ? preferred : list.where((c) => c['rank'] != 'deprecated')).take(3)) {
      final value = _object(_object(claim['mainsnak'])?['datavalue']);
      if (value == null) continue;
      final type = value['type'];
      final held = value['value'];
      if (type == 'wikibase-entityid') {
        final entity = _object(held)?['id'];
        if (entity is String) values.add(ClaimEntity(entity));
      } else if (type == 'time') {
        final date = _wikidataDate(held);
        if (date != null && date.isNotEmpty) values.add(ClaimText(date));
      } else if (type == 'quantity') {
        final amount = _object(held)?['amount'];
        values.add(ClaimText(_figure(amount is num ? amount.toDouble() : _numberOf(amount is String ? amount : null))));
      } else if (type == 'string') {
        values.add(ClaimText('$held'));
      }
    }
    if (values.isNotEmpty) out.add((property: word, values: values));
  }
  return out;
}

/// Wikidata's labels, by id.
Map<String, String> parseWikidataLabels(Object? json) {
  final entities = _object(_object(json)?['entities']) ?? const <Object?, Object?>{};
  final out = <String, String>{};
  for (final MapEntry(key: id, value: entity) in entities.entries) {
    final label = _object(_object(_object(entity)?['labels'])?['en'])?['value'];
    if (id is String && label is String && label.isNotEmpty) out[id] = label;
  }
  return out;
}

/// What Wikidata said of one page: its title, its claims, and the labels of the entities among them.
typedef WikidataFacts = ({String title, List<Claim> claims, Map<String, String> labels});

/// What Wikipedia and Wikidata returned, as the lines the model reads.
String wikiFacts(List<WikiPage> pages, WikidataFacts? facts) {
  final lines = [for (final p in pages) '${p.title}: ${p.extract}'];
  if (facts != null && facts.claims.isNotEmpty) {
    // One fact a line, its property first: "- winner: Spain men's national football team".
    final said = <String>[];
    for (final c in facts.claims) {
      final values = [
        for (final v in c.values) jsTrim(switch (v) { ClaimText(:final text) => text, ClaimEntity(:final entity) => facts.labels[entity] ?? '' }),
      ].where((v) => v.isNotEmpty).toList();
      if (values.isNotEmpty) said.add('- ${c.property}: ${values.join(', ')}');
    }
    if (said.isNotEmpty) lines.addAll(['Wikidata on ${facts.title}:', ...said]);
  }
  return lines.join('\n');
}

// ---- asking ---------------------------------------------------------------------------------------------------------

/// Why a lookup has nothing to give; each name is the page's own word.
enum FoundWhy { offline, nothing }

/// How a lookup went (`Found`): what came back, with the source to name; offline; or nothing from a source that
/// answered.
@immutable
class Found {
  /// What came back: the [source] to name, its [facts] for the model, and the app's own [answer] where it writes one.
  const Found.ok({required String this.source, required String this.facts, this.answer})
      : ok = true,
        why = null,
        words = null;

  /// The network failed.
  const Found.offline()
      : ok = false,
        why = FoundWhy.offline,
        source = null,
        facts = null,
        answer = null,
        words = null;

  /// The source answered and had nothing: its own sentence.
  const Found.nothing({required String this.words})
      : ok = false,
        why = FoundWhy.nothing,
        source = null,
        facts = null,
        answer = null;

  final bool ok;
  final String? source;
  final String? facts;
  final String? answer;
  final FoundWhy? why;
  final String? words;

  @override
  bool operator ==(Object other) => other is Found && other.ok == ok && other.source == source && other.facts == facts && other.answer == answer && other.why == why && other.words == words;

  @override
  int get hashCode => Object.hash(ok, source, facts, answer, why, words);

  @override
  String toString() => ok ? 'Found.ok($source, $facts, $answer)' : 'Found.${why!.name}(${words ?? ''})';
}

/// Asks a URL for JSON; throws `offline` on a network failure, and answers the status with the body otherwise
/// (`Fetcher`).
typedef FillFetcher = Future<({int status, Object? json})> Function(String url);

/// The app's own fetch (`pageFetch`), ten seconds at most, no cookies, nothing but the address and the app's name,
/// and no redirect followed: a 3xx is answered as it came, with whatever JSON it carried. [client] is the one to use,
/// or one made here and kept.
FillFetcher pageFetcher({HttpClient? client, Duration timeout = const Duration(seconds: 10), String? userAgent}) {
  HttpClient? kept = client;
  return (url) async {
    HttpClientRequest? sent;
    Future<({int status, Object? json})> ask() async {
      final asked = sent = await (kept ??= HttpClient()).getUrl(Uri.parse(url));
      asked.followRedirects = false;
      asked.headers.set(HttpHeaders.acceptHeader, 'application/json');
      asked.headers.set(HttpHeaders.userAgentHeader, userAgent ?? geocodeUserAgent());
      final answer = await asked.close();
      Object? json;
      try {
        json = jsonDecode(await utf8.decodeStream(answer));
      } catch (_) {
        // Not JSON, or a body that broke off: the status stands with nothing read.
        json = null;
      }
      return (status: answer.statusCode, json: json);
    }

    try {
      return await ask().timeout(timeout, onTimeout: () {
        sent?.abort();
        throw TimeoutException('The request took too long.', timeout);
      });
    } catch (_) {
      throw StateError('offline');
    }
  };
}

/// [pageFetcher] with its own client, made at the first lookup.
final FillFetcher pageFetch = pageFetcher();

String _enc(String text) => Uri.encodeComponent(text);

/// The addresses each source is asked at: the only thing that leaves the phone (`URLS`).
class Urls {
  const Urls._();

  String geocode(String place) => 'https://geocoding-api.open-meteo.com/v1/search?name=${_enc(place)}&count=1&language=en&format=json';

  String forecast(Place p, int days) =>
      'https://api.open-meteo.com/v1/forecast?latitude=${_number(p.latitude)}&longitude=${_number(p.longitude)}&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max&current=temperature_2m,weather_code,wind_speed_10m&timezone=auto&forecast_days=$days';

  String rates(String from, String to) => 'https://api.frankfurter.dev/v1/latest?base=${_enc(from)}&symbols=${_enc(to)}';

  String wiki(String terms) =>
      'https://en.wikipedia.org/w/api.php?action=query&generator=search&gsrsearch=${_enc(terms)}&gsrlimit=3&prop=extracts%7Cpageprops&ppprop=wikibase_item&exintro=1&explaintext=1&exsentences=4&exlimit=3&format=json&formatversion=2&origin=*';

  String claims(String id) => 'https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${_enc(id)}&props=claims&format=json&origin=*';

  String labels(List<String> ids) => 'https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${ids.map(_enc).join('%7C')}&props=labels&languages=en&format=json&origin=*';
}

/// `URLS`.
const Urls urls = Urls._();

/// Looks a plan up: the source's answer as facts for the model, offline, or nothing found.
Future<Found> lookUp(LookupPlan plan, [FillFetcher? fetcher]) async {
  final fetch = fetcher ?? pageFetch;
  try {
    if (plan.kind == LookupKind.weather) {
      final days = plan.days!;
      final place = parseGeocode((await fetch(urls.geocode(plan.place!))).json);
      if (place == null) return Found.nothing(words: 'Open-Meteo doesn’t know a place called ${plan.place}.');
      final forecast = (await fetch(urls.forecast(place, days.to + 1 < 7 ? days.to + 1 : 7))).json;
      final facts = parseForecast(forecast, place, days);
      final answer = forecastAnswer(forecast, days);
      return facts != null && facts.isNotEmpty && answer != null && answer.isNotEmpty
          ? Found.ok(source: 'Open-Meteo', facts: facts, answer: answer)
          : const Found.nothing(words: 'Open-Meteo had no forecast for that day.');
    }
    if (plan.kind == LookupKind.rates) {
      final rates = (await fetch(urls.rates(plan.from!, plan.to!))).json;
      final facts = parseRates(rates, (amount: plan.amount!, from: plan.from!, to: plan.to!));
      final answer = ratesAnswer(rates, (amount: plan.amount!, to: plan.to!));
      return facts != null && answer != null
          ? Found.ok(source: 'Frankfurter', facts: facts, answer: answer)
          : Found.nothing(words: 'The European Central Bank has no rate from ${plan.from} to ${plan.to}.');
    }
    if (plan.kind == LookupKind.wiki) {
      final pages = parseWikiSearch((await fetch(urls.wiki(plan.terms!))).json);
      if (pages.isEmpty) return const Found.nothing(words: 'Wikipedia had nothing on this.');
      final best = bestPage(pages, plan.terms!);
      WikidataFacts? facts;
      final item = best?.item;
      if (best != null && item != null && item.isNotEmpty) {
        // Wikidata is a second word, not the answer: without it the pages still stand.
        try {
          final claims = parseWikidataClaims((await fetch(urls.claims(item))).json, item);
          final ids = {
            for (final c in claims)
              for (final v in c.values)
                if (v is ClaimEntity) v.entity,
          }.take(20).toList();
          final labels = ids.isNotEmpty ? parseWikidataLabels((await fetch(urls.labels(ids))).json) : <String, String>{};
          facts = (title: best.title, claims: claims, labels: labels);
        } catch (_) {
          facts = null;
        }
      }
      final used = facts != null && facts.claims.isNotEmpty ? 'Wikipedia and Wikidata' : 'Wikipedia';
      return Found.ok(source: used, facts: wikiFacts(pages, facts));
    }
    return Found.nothing(words: plan.why!);
  } catch (_) {
    return const Found.offline();
  }
}

/// The message the model reads for a looked-up blank: the note's lines as any fill's, then what the source returned.
String webMessage(String scopeMessage, String source, String facts) {
  // The builder's message ends with its answer line; the source's words go before it.
  final cut = scopeMessage.lastIndexOf('\n\n');
  final head = cut >= 0 ? scopeMessage.substring(0, cut) : scopeMessage;
  final tail = cut >= 0 ? scopeMessage.substring(cut + 2) : 'Answer blank 1.';
  return '$head\n\nWhat $source returned:\n$facts\n\n$tail';
}
