/// "A list with Parkersburg West Virginia Marietta Ohio Baltimore Maryland and Detroit Michigan": the items of a
/// spoken list, one string each. A port of `src/app/capture/spokenList.ts`.
///
/// Kevin's list was places, and places are the case that splitting on commas gets wrong in both directions: Whisper
/// writes "Parkersburg, West Virginia, Marietta, Ohio", so a comma split makes eight items of four, and it often
/// writes no commas at all, so there is nothing to split on. A US state name ends a place, so when every item of the
/// list ends in one, the state is the separator and each item reads "City, State". Anything else falls back to the
/// ordinary spoken split (semicolons, then commas and "and", then short runs of bare words).
///
/// What differs: nothing.
library;

import 'dart:math' as math;

import '../core/text.dart';

const List<String> _states = [
  'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado', 'Connecticut', 'Delaware', 'Florida', 'Georgia', //
  'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana', 'Maine', 'Maryland',
  'Massachusetts', 'Michigan', 'Minnesota', 'Mississippi', 'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire',
  'New Jersey', 'New Mexico', 'New York', 'North Carolina', 'North Dakota', 'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania',
  'Rhode Island', 'South Carolina', 'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont', 'Virginia', 'Washington',
  'West Virginia', 'Wisconsin', 'Wyoming', 'District of Columbia',
];

const Map<String, String> _abbreviations = {
  'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California', 'CO': 'Colorado', //
  'CT': 'Connecticut', 'DE': 'Delaware', 'FL': 'Florida', 'GA': 'Georgia', 'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois',
  'IN': 'Indiana', 'IA': 'Iowa', 'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
  'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri', 'MT': 'Montana',
  'NE': 'Nebraska', 'NV': 'Nevada', 'NH': 'New Hampshire', 'NJ': 'New Jersey', 'NM': 'New Mexico', 'NY': 'New York',
  'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio', 'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania',
  'RI': 'Rhode Island', 'SC': 'South Carolina', 'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah',
  'VT': 'Vermont', 'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming',
  'DC': 'District of Columbia',
};

final Map<String, String> _byWords = {for (final state in _states) state.toLowerCase(): state};
final int _longest = _states.map((state) => state.split(' ').length).reduce(math.max);

String _capitalised(List<String> words) => words.map(capitalise).join(' ');

final RegExp _twoCapitals = RegExp(r'^[A-Z]{2}$');

/// The state spelled by [words] from [at], longest first, and how many words it took.
({String state, int length})? _stateAt(List<String> words, int at) {
  for (var length = math.min(_longest, words.length - at); length >= 1; length -= 1) {
    final state = _byWords[words.sublist(at, at + length).join(' ').toLowerCase()];
    if (state != null) return (state: state, length: length);
  }
  final word = at < words.length ? words[at] : '';
  final abbreviation = _twoCapitals.hasMatch(word) ? _abbreviations[word] : null;
  return abbreviation != null ? (state: abbreviation, length: 1) : null;
}

final RegExp _stops = RegExp('[.,;:!?"“”]+');
final RegExp _space = RegExp(r'\s+');
final RegExp _between = RegExp(r'^(?:and|&|then|also)$', caseSensitive: false);

/// "Parkersburg West Virginia Marietta Ohio" as places, or null when it is not a list made only of them.
List<String>? _placesIn(String text) {
  final words = text.replaceAll(_stops, ' ').split(_space).where((word) => word.isNotEmpty).toList();
  final places = <String>[];
  var city = <String>[];
  for (var at = 0; at < words.length;) {
    final word = words[at];
    // "…Maryland and Detroit Michigan": the "and" between two places.
    if (city.isEmpty && places.isNotEmpty && _between.hasMatch(word)) {
      at += 1;
      continue;
    }
    final state = _stateAt(words, at);
    if (state != null && city.isNotEmpty) {
      places.add('${_capitalised(city)}, ${state.state}');
      city = [];
      at += state.length;
      continue;
    }
    // A state with no city before it is the city's own name: "New York New York", "Kansas City Missouri".
    final taken = state?.length ?? 1;
    city.addAll(words.sublist(at, at + taken));
    at += taken;
  }
  return places.length >= 2 && city.isEmpty ? places : null;
}

final RegExp _stopsAtEnd = RegExp(r'[.!?]+$');
final RegExp _semicolon = RegExp(r'\s*;\s*');
final RegExp _commaOrAnd = RegExp(r'\s*(?:,|\band\b)\s*', caseSensitive: false);
final RegExp _bareWord = RegExp(r"^[\p{L}\p{N}'-]+$", unicode: true);

/// What Whisper writes between the items of a list said slowly: "Also." "And." "Can you also add?" "Go."
final RegExp _filler = RegExp(
  r'^(?:(?:can|could|would)\s+you\s+(?:also\s+|please\s+)?(?:add|put)(?:\s+(?:these|them|those))?|(?:and|also|then|next|okay|ok|um|uh|please|go|end|stop|done|add|put)(?:\s+(?:and|also|then|next|add|put))*)$',
  caseSensitive: false,
);
final RegExp _sentenceBreak = RegExp(r'[.!?]\s+\S');
final RegExp _sentenceSplit = RegExp(r'\s*[.!?]+\s+');
final RegExp _pieceEdges = RegExp(r'^[\s.,]+|[\s.,!?]+$');
final RegExp _leadingJoiners = RegExp(r'^(?:(?:and|also|then|next)\s+)+', caseSensitive: false);

/// Items said with a pause between them come back as sentences: "Zelda. Spiderman PS4. And Lego Star Wars. Also.
/// Stardew Valley." Two or more of those are the items, with the filler between them and a leading "and" left out.
List<String>? _sentenceItems(String text) {
  if (text.contains(';') || !_sentenceBreak.hasMatch(text)) return null;
  final items = [
    for (final piece in text.split(_sentenceSplit).map((piece) => piece.replaceAll(_pieceEdges, '')))
      if (piece.isNotEmpty && !_filler.hasMatch(piece)) piece.replaceFirst(_leadingJoiners, '').trim(),
  ].where((item) => item.isNotEmpty).toList();
  return items.length >= 2 ? items : null;
}

/// The items of a spoken list, one string each, in the order said.
List<String> spokenListItems(String text) {
  final cleaned = text.trim().replaceFirst(_stopsAtEnd, '').trim();
  if (cleaned.isEmpty) return [];
  final places = _placesIn(cleaned);
  if (places != null) return places;
  final sentences = _sentenceItems(cleaned);
  if (sentences != null) return sentences;
  // A model is asked to separate its items with semicolons, which keeps a comma inside one item.
  if (cleaned.contains(';')) return cleaned.split(_semicolon).map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  final said = cleaned.split(_commaOrAnd).map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  if (said.length > 1) return said;
  // "Milk eggs bread": short bare words said one after another are items too.
  final words = cleaned.split(_space);
  return words.length >= 2 && words.length <= 8 && words.every(_bareWord.hasMatch) ? words : [cleaned];
}
