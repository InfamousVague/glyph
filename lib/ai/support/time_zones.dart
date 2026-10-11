/// The cities the time solver knows (core/fill_facts.dart, docs/DESIGN.md §145): a city's name to its IANA zone. A
/// port of `src/app/core/timeZones.ts`. About eighty of the places people plan calls and trips around. A city not
/// here is said to be one the app does not know, and the model can be asked anyway. Pure data, in English, as the
/// note's words are matched. It belongs in lib/core once that stage lands.
///
/// What differs: on the page `Intl.DateTimeFormat` turns a zone into the time there. Dart has no time-zone database
/// without a package, so the offsets of exactly these zones are a table (`time_zone_table.dart`), read by
/// core/fill_facts.dart `offsetMinutes`. Accents come off a name through `unaccent.dart`.
library;

import '../../core/item_syntax.dart' show jsTrim;
import 'unaccent.dart';

/// Every city, with its zone (`CITY_ZONES`).
const Map<String, String> cityZones = {
  'London': 'Europe/London',
  'Edinburgh': 'Europe/London',
  'Manchester': 'Europe/London',
  'Dublin': 'Europe/Dublin',
  'Lisbon': 'Europe/Lisbon',
  'Madrid': 'Europe/Madrid',
  'Barcelona': 'Europe/Madrid',
  'Paris': 'Europe/Paris',
  'Brussels': 'Europe/Brussels',
  'Amsterdam': 'Europe/Amsterdam',
  'Berlin': 'Europe/Berlin',
  'Munich': 'Europe/Berlin',
  'Zurich': 'Europe/Zurich',
  'Geneva': 'Europe/Zurich',
  'Rome': 'Europe/Rome',
  'Milan': 'Europe/Rome',
  'Vienna': 'Europe/Vienna',
  'Prague': 'Europe/Prague',
  'Warsaw': 'Europe/Warsaw',
  'Copenhagen': 'Europe/Copenhagen',
  'Oslo': 'Europe/Oslo',
  'Stockholm': 'Europe/Stockholm',
  'Helsinki': 'Europe/Helsinki',
  'Reykjavik': 'Atlantic/Reykjavik',
  'Athens': 'Europe/Athens',
  'Istanbul': 'Europe/Istanbul',
  'Kyiv': 'Europe/Kyiv',
  'Moscow': 'Europe/Moscow',
  'Cairo': 'Africa/Cairo',
  'Lagos': 'Africa/Lagos',
  'Nairobi': 'Africa/Nairobi',
  'Johannesburg': 'Africa/Johannesburg',
  'Cape Town': 'Africa/Johannesburg',
  'Tel Aviv': 'Asia/Jerusalem',
  'Jerusalem': 'Asia/Jerusalem',
  'Riyadh': 'Asia/Riyadh',
  'Dubai': 'Asia/Dubai',
  'Tehran': 'Asia/Tehran',
  'Karachi': 'Asia/Karachi',
  'Mumbai': 'Asia/Kolkata',
  'Delhi': 'Asia/Kolkata',
  'New Delhi': 'Asia/Kolkata',
  'Bangalore': 'Asia/Kolkata',
  'Kolkata': 'Asia/Kolkata',
  'Kathmandu': 'Asia/Kathmandu',
  'Dhaka': 'Asia/Dhaka',
  'Bangkok': 'Asia/Bangkok',
  'Hanoi': 'Asia/Bangkok',
  'Jakarta': 'Asia/Jakarta',
  'Singapore': 'Asia/Singapore',
  'Kuala Lumpur': 'Asia/Kuala_Lumpur',
  'Manila': 'Asia/Manila',
  'Hong Kong': 'Asia/Hong_Kong',
  'Shanghai': 'Asia/Shanghai',
  'Beijing': 'Asia/Shanghai',
  'Taipei': 'Asia/Taipei',
  'Seoul': 'Asia/Seoul',
  'Tokyo': 'Asia/Tokyo',
  'Osaka': 'Asia/Tokyo',
  'Kyoto': 'Asia/Tokyo',
  'Perth': 'Australia/Perth',
  'Adelaide': 'Australia/Adelaide',
  'Brisbane': 'Australia/Brisbane',
  'Sydney': 'Australia/Sydney',
  'Melbourne': 'Australia/Melbourne',
  'Auckland': 'Pacific/Auckland',
  'Wellington': 'Pacific/Auckland',
  'Honolulu': 'Pacific/Honolulu',
  'Anchorage': 'America/Anchorage',
  'Vancouver': 'America/Vancouver',
  'Seattle': 'America/Los_Angeles',
  'San Francisco': 'America/Los_Angeles',
  'Los Angeles': 'America/Los_Angeles',
  'Las Vegas': 'America/Los_Angeles',
  'Phoenix': 'America/Phoenix',
  'Denver': 'America/Denver',
  'Dallas': 'America/Chicago',
  'Houston': 'America/Chicago',
  'Chicago': 'America/Chicago',
  'Mexico City': 'America/Mexico_City',
  'Toronto': 'America/Toronto',
  'Montreal': 'America/Toronto',
  'Atlanta': 'America/New_York',
  'Miami': 'America/New_York',
  'Washington': 'America/New_York',
  'Boston': 'America/New_York',
  'New York': 'America/New_York',
  'Bogota': 'America/Bogota',
  'Lima': 'America/Lima',
  'Santiago': 'America/Santiago',
  'Buenos Aires': 'America/Argentina/Buenos_Aires',
  'Sao Paulo': 'America/Sao_Paulo',
  'Rio de Janeiro': 'America/Sao_Paulo',
};

/// A city's zone by its name, whatever its case or its accents ("São Paulo", "bogotá"); null for one not here.
String? zoneOf(String name) {
  final plain = _fold(name);
  for (final city in cityZones.keys) {
    if (_fold(city) == plain) return cityZones[city];
  }
  return null;
}

/// The city a zone is named for here, for "London" in place of "here"; null for a zone with no city in the table.
String? cityOf(String zone) {
  final here = [
    for (final city in cityZones.keys)
      if (cityZones[city] == zone) city,
  ];
  // The city the zone is named for, where it is one: America/New_York is New York, not Atlanta.
  final named = zone.split('/').last.replaceAll('_', ' ');
  for (final city in here) {
    if (city == named) return city;
  }
  return here.isEmpty ? null : here.first;
}

/// Lower case, accents off.
String _fold(String text) => jsTrim(unaccented(text).toLowerCase());

/// Every city, longest first, so "New Delhi" is found before "Delhi" (`CITIES`). Cities of one length keep the
/// table's order, as JavaScript's sort keeps them.
final List<String> cities = () {
  final names = cityZones.keys.toList();
  final order = {for (var i = 0; i < names.length; i += 1) names[i]: i};
  names.sort((a, b) => b.length != a.length ? b.length - a.length : order[a]! - order[b]!);
  return List<String>.unmodifiable(names);
}();
