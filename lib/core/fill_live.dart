/// Blanks that need live facts, found before any model is asked (docs/DESIGN.md §145, 2.4). A port of
/// `src/app/core/fillLive.ts`.
///
/// The model has no internet: it runs on the phone with none, even when the phone has one. Measured on the 4B, it
/// named a 2026 World Cup winner twice, and said a temple opens at 9:00 with nothing to say that may change. So a
/// blank whose words make its answer live (weather today, a fare now, an exchange rate, a market, opening hours, the
/// newest of anything, results, events after the model's training) is not handed to the model. It looks for words
/// that make an answer live, not for topics: "Flights are cheapest to Tokyo on" is general advice and goes to the
/// model, "A return flight costs {?price today}" does not.
///
/// Matt then chose "Pause till online" and "Phone looks it up, all local": a live blank pressed with Fill waits for a
/// connection, then the phone itself asks a keyless public source and the model on the phone writes the answer from
/// what came back (ai/fills/web.dart). So this screen also says what a lookup would ask: the place and the day for
/// the weather, the two currencies for a rate, the words to search for the rest. Where no public source can answer (a
/// fare, a market, opening hours) the app says so, and Ask the model anyway stays.
///
/// The horizon is a fixed year per model (ai/backend.dart `learntUntil`), never the clock, so a 2026 event is after
/// what the model learnt in 2028 as well. Pure: every rule is a test.
///
/// What differs: only the shapes. `LiveKind` is an enum whose names are the page's words, `Live` a class with value
/// equality, and what [moneyAsked] and [dayAsked] answer are records.
library;

import 'blanks.dart';
import 'item_syntax.dart' show jsTrim;

/// Why a blank is live (`LiveKind`); each name is the page's own word.
enum LiveKind { weather, prices, money, markets, hours, newest, after, news, transport }

/// A blank the model cannot know the answer to (`Live`).
class Live {
  const Live({required this.kind, required this.words});

  final LiveKind kind;

  /// Why the model can't know it, in the app's words.
  final String words;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => {'kind': kind.name, 'words': words};

  @override
  bool operator ==(Object other) => other is Live && other.kind == kind && other.words == words;

  @override
  int get hashCode => Object.hash(kind, words);

  @override
  String toString() => 'Live(${kind.name}, $words)';
}

/// The panel's sentence for each kind.
String liveWords(LiveKind kind, [int? year]) => switch (kind) {
  LiveKind.weather => 'Weather changes by the hour, and the model has no internet.',
  LiveKind.prices => 'Prices change, and the model has no internet.',
  LiveKind.money => 'Exchange rates change every day, and the model has no internet.',
  LiveKind.markets => 'Prices change by the minute, and the model has no internet.',
  LiveKind.hours => 'Opening hours change, and the model could be out of date.',
  LiveKind.newest => 'Something newer may exist than the model knows of.',
  LiveKind.after => '${year ?? 'That year'} is after what the model learnt. It would only be guessing.',
  LiveKind.news => 'This happened after what the model learnt, or may have.',
  LiveKind.transport => 'This changes by the minute, and the model has no internet.',
};

RegExp _words(String source) => RegExp(source, caseSensitive: false);

final RegExp _whenNow = _words(r'\b(today|tonight|tomorrow|now|this week|this weekend|right now|at the moment)\b');
final RegExp _weather = _words(r'\b(weather|forecast|rain|raining|rainy|snow|snowing|temperature|sunny|windy|warm|cold|hot|degrees)\b');

/// Weather asked of the past, which the model keeps as history rather than a forecast: "what was the weather", "back
/// in 1990".
final RegExp _weatherWas = _words(r'\b(was|were|used to|back in|years? ago)\b');
// "Cheapest" is a price too: "Cheapest flight to Lisbon today" is a fare now. "Flights are cheapest to Tokyo on" has
// no word for now, and stays general advice for the model.
final RegExp _price = _words(r'\b(price|prices|cost|costs|fare|fares|how much|cheapest|cheaper|cheap|dearest)\b');
final RegExp _priceNow = _words(r'\b(today|tonight|tomorrow|now|current|currently|this week|this weekend|right now|at the moment)\b');
final RegExp _market = _words(r'\b(stocks?|share price|shares|bitcoin|ethereum|crypto|the market|nasdaq|ftse|dow jones|s&p)\b');
final RegExp _marketWhat = _words(r'\b(price|value|worth|trading|at)\b');
final RegExp _hours = _words(r'\b(opens|opening hours|opening times|closes|closing time|open on|is it open|open until|open (?:today|tonight|now|tomorrow))\b');
final RegExp _newest = _words(r'\b(newest|latest|most recent|current|reigning)\b');
final RegExp _product = _words(r'\b(version|model|phone|release|update|edition|album|single|song|film|movie|book|iphone|pixel|galaxy)\b');
final RegExp _office = _words(r'\b(prime minister|president|chancellor|pope|king|queen|monarch|mayor|ceo|base rate|interest rate)\b');
final RegExp _holder = _words(r'\b(leader|champion|winner|record|holder|prime minister|president|ceo)\b');
final RegExp _event = _words(r'\b(won|win|winner|winners|result|results|score|released|launched|elected|announced|happened|died|champion|went to|awarded|prize|came out)\b');
final RegExp _news = _words(r'\b(who won|the score|results?)\b');
final RegExp _newsWhen = _words(r'\b(last night|yesterday|this season|last season|this year|last year|last week|at the weekend)\b');
final RegExp _transport = _words(r'\b(delays?|departures?|next train|next bus|next tram|traffic|is it running|running late)\b');
final RegExp _condition = _words(r'\b(if|unless|in case)\b');
final RegExp _exchangeRate = _words(r'\bexchange rates?\b|\brate of exchange\b');
final RegExp _isOrAre = _words(r'\b(is|are)\b');
final RegExp _year = RegExp(r'\b(1\d{3}|2\d{3})\b');

/// The pieces a blank asks with, each on its own: a rule that needs two words needs them in one sentence.
List<String> _pieces(Asking asking) => [asking.question, asking.sentence, asking.prior].where((each) => each.isNotEmpty).toList();

/// Whether [word] stands in an `if` clause of [piece]: "If it rains tomorrow, what do we do?" asks for a plan.
bool _inIf(String piece, RegExp word) {
  final at = piece.indexOf(word);
  final cond = piece.indexOf(_condition);
  return at >= 0 && cond >= 0 && cond < at;
}

/// Whether the blank needs something live or newer than the model ([learntUntil], the last year it is taken to
/// know).
Live? cannotKnow(Blank blank, String text, int learntUntil) => screen(askingWords(blank, text), learntUntil);

/// The screen over the asking words, for a caller that has them already.
Live? screen(Asking asking, int learntUntil) {
  final all = _pieces(asking);
  Live live(LiveKind kind, [int? year]) => Live(kind: kind, words: liveWords(kind, year));
  // Weather is the weather now unless an "if" makes it a plan or the past tense makes it history: a time word, or
  // just a place named ("weather in Tokyo"), routes it to a live look-up. Before, with no time word it went to the
  // model, which has no internet, so it never filled (Matt: "weather in Tokyo never fills on mobile"). The place a
  // forecast needs is read the same way the look-up reads it (`placeAsked`); with none and no time word it stays the
  // model's.
  final weatherPieces = all.where((p) => _weather.hasMatch(p) && !_inIf(p, _weather) && !_weatherWas.hasMatch(p));
  if (weatherPieces.isNotEmpty && (_whenNow.hasMatch(weatherPieces.first) || placeAsked(asking) != null)) return live(LiveKind.weather);
  if (moneyAsked(asking) != null || all.any(_exchangeRate.hasMatch)) return live(LiveKind.money);
  if (all.any((p) => _market.hasMatch(p) && _marketWhat.hasMatch(p))) return live(LiveKind.markets);
  if (all.any((p) => _price.hasMatch(p) && _priceNow.hasMatch(p))) return live(LiveKind.prices);
  if (all.any(_hours.hasMatch)) return live(LiveKind.hours);
  if (all.any(_transport.hasMatch)) return live(LiveKind.transport);
  final year = _laterYear(asking, learntUntil);
  if (year != null) return live(LiveKind.after, year);
  if (all.any((p) => _newest.hasMatch(p) && (_holder.hasMatch(p) || _product.hasMatch(p) || _namedAfter(p)))) return live(LiveKind.newest);
  if (all.any((p) => _news.hasMatch(p) && _newsWhen.hasMatch(p))) return live(LiveKind.news);
  // Who holds an office now: "The President of the United States is {?}", with no year to date it.
  if (all.any((p) => _office.hasMatch(p) && _isOrAre.hasMatch(p) && !_year.hasMatch(p) && !_inIf(p, _office))) return live(LiveKind.newest);
  return null;
}

final RegExp _nameAfterNewest = RegExp(r'\b(?:newest|latest|most recent|current|reigning)\s+(?:version of\s+(?:the\s+)?)?(?:[A-Z][\w-]*|[a-z]+[A-Z][\w-]*)');

/// A capitalised name straight after newest or latest: "The newest Pixel", "the latest version of Android".
bool _namedAfter(String piece) => _nameAfterNewest.hasMatch(piece);

/// A year after the model's horizon, beside a word for something that happened: a year alone is a plan, not news.
int? _laterYear(Asking asking, int learntUntil) {
  for (final piece in _pieces(asking)) {
    if (!_event.hasMatch(piece)) continue;
    for (final match in _year.allMatches(piece)) {
      final year = int.parse(match.group(1)!);
      if (year > learntUntil) return year;
    }
  }
  return null;
}

// ---- what a lookup would ask ----------------------------------------------------------------------------------------

/// Currencies by what people call them, as ISO codes Frankfurter's ECB rates know. Words that are also everyday
/// words ("won", "real", "try") count only with their country, and a code only in capitals, so "who won" is not
/// money.
final List<(RegExp, String)> _currencyNames = [
  (_words(r'\baustralian dollars?\b'), 'AUD'),
  (_words(r'\bcanadian dollars?\b'), 'CAD'),
  (_words(r'\bnew zealand dollars?\b'), 'NZD'),
  (_words(r'\bhong kong dollars?\b'), 'HKD'),
  (_words(r'\bsingapore dollars?\b'), 'SGD'),
  (_words(r'\b(?:us )?dollars?\b|\bbucks\b|\$'), 'USD'),
  (_words(r'\beuros?\b|€'), 'EUR'),
  (_words(r'\bpounds? sterling\b|\bpounds?\b|\bquid\b|\bsterling\b|£'), 'GBP'),
  (_words(r'\byen\b|¥'), 'JPY'),
  (_words(r'\byuan\b|\brenminbi\b'), 'CNY'),
  (_words(r'\brupees?\b|₹'), 'INR'),
  (_words(r'\bswiss francs?\b|\bfrancs?\b'), 'CHF'),
  (_words(r'\bswedish kron(?:a|or)\b|\bkronor\b'), 'SEK'),
  (_words(r'\bnorwegian kron(?:e|er)\b'), 'NOK'),
  (_words(r'\bdanish kron(?:e|er)\b'), 'DKK'),
  (_words(r'\bkorean won\b'), 'KRW'),
  (_words(r'\bmexican pesos?\b|\bpesos?\b'), 'MXN'),
  (_words(r'\bbrazilian real\b|\breais\b'), 'BRL'),
  (_words(r'\bsouth african rand\b'), 'ZAR'),
  (_words(r'\bzloty\b|\bzłoty\b'), 'PLN'),
  (_words(r'\bbaht\b'), 'THB'),
  (_words(r'\bturkish lira\b'), 'TRY'),
  (_words(r'\bforint\b'), 'HUF'),
  (_words(r'\bczech koruna\b|\bkoruna\b'), 'CZK'),
];

/// The ECB's currencies by their codes, in capitals only.
final RegExp _codes = RegExp(r'\b(AUD|BGN|BRL|CAD|CHF|CNY|CZK|DKK|EUR|GBP|HKD|HUF|IDR|ILS|INR|ISK|JPY|KRW|MXN|MYR|NOK|NZD|PHP|PLN|RON|SEK|SGD|THB|TRY|USD|ZAR)\b');
final RegExp _amountBefore = RegExp(r'(\d[\d,]*(?:\.\d+)?)\s*$');
final RegExp _amountAfter = RegExp(r'^\s*(\d[\d,]*(?:\.\d+)?)');

/// The currencies a piece of words names, where each is named, in order.
List<({String code, int at, double? amount})> _currenciesIn(String piece) {
  final found = <({String code, int at, double? amount})>[];
  var rest = piece;
  final codes = [for (final m in _codes.allMatches(piece)) (RegExp('\\b${m.group(1)}\\b'), m.group(1)!)];
  for (final (pattern, code) in [...codes, ..._currencyNames]) {
    final match = pattern.firstMatch(rest);
    if (match == null || found.any((f) => f.code == code)) continue;
    final before = _amountBefore.firstMatch(rest.substring(0, match.start));
    final after = _amountAfter.firstMatch(rest.substring(match.end));
    final amount = before != null
        ? double.parse(before.group(1)!.replaceAll(',', ''))
        : (match.end - match.start == 1 && after != null ? double.parse(after.group(1)!.replaceAll(',', '')) : null);
    found.add((code: code, at: match.start, amount: amount));
    rest = '${rest.substring(0, match.start)}${' ' * (match.end - match.start)}${rest.substring(match.end)}';
  }
  found.sort((a, b) => a.at - b.at);
  return found;
}

/// An amount in one currency with another asked for: `100 dollars is {?how many yen} yen`. The source is the
/// currency with an amount, the target the one the question or the words after the blank name, else the other one
/// named.
({double amount, String from, String to})? moneyAsked(Asking asking) {
  final named = _currenciesIn([asking.question, asking.sentence, asking.prior].join(' '));
  if (named.length < 2) return null;
  final sources = named.where((c) => c.amount != null);
  if (sources.isEmpty) return null;
  final source = sources.first;
  final askedFor = _currenciesIn('${asking.question} ${asking.after}');
  final asked = askedFor.isEmpty ? null : askedFor.first;
  final others = named.where((c) => c.code != source.code);
  final target = asked != null && asked.code != source.code ? asked : (others.isEmpty ? null : others.first);
  if (target == null) return null;
  return (amount: source.amount!, from: source.code, to: target.code);
}

/// Languages, which follow "in" as often as places do: `{?in Italian}` asks for a translation, not the weather in
/// Italy.
final Set<String> _languages =
    'english french german spanish italian portuguese japanese chinese mandarin cantonese korean russian arabic dutch swedish norwegian danish finnish polish greek turkish hindi hebrew welsh irish latin czech hungarian vietnamese thai indonesian ukrainian romanian catalan'
        .split(' ')
        .toSet();

final RegExp _colonsAndSpacesAtEnd = RegExp(r'[:\s]+$');
final RegExp _oneOrTwoLetters = RegExp(r'^[\p{L}]{1,2}$', unicode: true);
final RegExp _clauseEnd = RegExp(r'[,;]|\s(?:and|but|so)\s', caseSensitive: false);
final RegExp _questionWord = _words(r'\b(who|what|when|where|which|how|whose|whom)\b');

/// The part of the blank's own sentence that asks: its last clause before the blank (a comma or a semicolon ends a
/// clause), from its first question word on when it has one. `Sarah Jones owes me £450, and who won the 2026 World
/// Cup {?}` asks "who won the 2026 World Cup". The sentence before is read only when the blank's own is a label or
/// nothing. This is what a lookup may send when the braces hold no words of their own (docs/DESIGN.md §145): never
/// the rest of the note, a whole sentence, or the one before.
String askingClause(Asking asking) {
  final own = jsTrim(asking.before.replaceFirst(_colonsAndSpacesAtEnd, ''));
  final from = own.isNotEmpty && !_oneOrTwoLetters.hasMatch(own) ? own : asking.prior;
  final clause = jsTrim(from.split(_clauseEnd).last);
  final wh = _questionWord.firstMatch(clause);
  return jsTrim(clause.substring(wh?.start ?? 0));
}

final RegExp _twoLettersOrDigits = RegExp(r'[\p{L}\p{N}]{2,}', unicode: true);

/// What a lookup reads its words from: the braces' own question when it has any words, else the asking clause.
List<String> _lookupPieces(Asking asking) {
  final question = jsTrim(asking.question);
  if (question.isNotEmpty && _twoLettersOrDigits.hasMatch(question)) return [question];
  final clause = askingClause(asking);
  return clause.isEmpty ? [] : [clause];
}

final RegExp _placeAfter = RegExp(r"\b(?:in|at|for|over)\s+((?:[A-Z][\p{L}'’-]+)(?:\s+(?:de|del|da|do|di|la|le|am|upon|on)?\s*[A-Z][\p{L}'’-]+){0,2})", unicode: true);
final RegExp _possessiveEnd = RegExp(r"['’]s?$");
final RegExp _possessive = RegExp(r"['’]s\b");
final RegExp _spaces = RegExp(r'\s+');

/// The place a weather question names: `Weather in Lisbon today`, `the forecast for New York`. Read from the
/// question and the blank's own clause only, never a word from elsewhere in the note; a possessive ("Sarah's
/// wedding") names a person and a language names no place, so both are passed over.
String? placeAsked(Asking asking) {
  final read = [asking.question, askingClause(asking), asking.before.replaceFirst(_colonsAndSpacesAtEnd, '')].where((each) => each.isNotEmpty);
  for (final piece in read) {
    for (final found in _placeAfter.allMatches(piece)) {
      final place = jsTrim(found.group(1)!.replaceAll(_spaces, ' '));
      if (_possessiveEnd.hasMatch(place) || _possessive.hasMatch(place)) continue;
      if (_languages.contains(place.toLowerCase())) continue;
      return place;
    }
  }
  return null;
}

final RegExp _tomorrow = _words(r'\btomorrow\b');
final RegExp _thisWeekend = _words(r'\bthis weekend\b');
final RegExp _thisWeek = _words(r'\bthis week\b');

/// Which day a weather question is about, as days from today: today 0, tomorrow 1, this weekend the coming Saturday.
/// [now]'s weekday is read on the device's own calendar.
({int from, int to}) dayAsked(Asking asking, DateTime now) {
  final words = _pieces(asking).join(' ');
  if (_tomorrow.hasMatch(words)) return (from: 1, to: 1);
  if (_thisWeekend.hasMatch(words)) {
    final saturday = (6 - now.toLocal().weekday % 7 + 7) % 7;
    return (from: saturday, to: saturday + 1 < 6 ? saturday + 1 : 6);
  }
  if (_thisWeek.hasMatch(words)) return (from: 0, to: 6);
  return (from: 0, to: 0);
}

/// Words that carry nothing for a search: the question's small words.
final Set<String> _stop =
    'a an the of to in on at and or is are was were be been it for with by from as that this what which who whom whose when where why how do does did will would can could should i we you he she they me my our your his her their there here about into over than then so not no yes please tell me find out'
        .split(' ')
        .toSet();

final RegExp _notSearchable = RegExp(r"[^\p{L}\p{N}'’ -]+", unicode: true);
final RegExp _digit = RegExp(r'\d');

/// The words a lookup searches for: the braces' own question, or with `{?}` the clause that asks ([askingClause]),
/// the small ones left out, at most eight. Only these leave the phone, to the one source asked (docs/DESIGN.md
/// §145): never the rest of the note.
String searchWords(Asking asking) {
  final words = _lookupPieces(asking)
      .join(' ')
      .replaceAll(_notSearchable, ' ')
      .split(_spaces)
      // A label's lone letter (the Q of "Q: …") says nothing either.
      .where((w) => w.isNotEmpty && !_stop.contains(w.toLowerCase()) && (w.length > 1 || _digit.hasMatch(w)));
  final seen = <String>{};
  return words.where((w) => seen.add(w.toLowerCase())).take(8).join(' ');
}
