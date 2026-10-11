/**
 * The cities the time solver knows (core/fillFacts.ts, docs/DESIGN.md §145): a city's name to its IANA zone, which
 * `Intl.DateTimeFormat` turns into the time there on any date, summer time included. About eighty of the places people
 * plan calls and trips around. A city not here is said to be one the app does not know, and the model can be asked
 * anyway. Pure data, in English, as the note's words are matched.
 */

export const CITY_ZONES: Readonly<Record<string, string>> = {
  London: 'Europe/London',
  Edinburgh: 'Europe/London',
  Manchester: 'Europe/London',
  Dublin: 'Europe/Dublin',
  Lisbon: 'Europe/Lisbon',
  Madrid: 'Europe/Madrid',
  Barcelona: 'Europe/Madrid',
  Paris: 'Europe/Paris',
  Brussels: 'Europe/Brussels',
  Amsterdam: 'Europe/Amsterdam',
  Berlin: 'Europe/Berlin',
  Munich: 'Europe/Berlin',
  Zurich: 'Europe/Zurich',
  Geneva: 'Europe/Zurich',
  Rome: 'Europe/Rome',
  Milan: 'Europe/Rome',
  Vienna: 'Europe/Vienna',
  Prague: 'Europe/Prague',
  Warsaw: 'Europe/Warsaw',
  Copenhagen: 'Europe/Copenhagen',
  Oslo: 'Europe/Oslo',
  Stockholm: 'Europe/Stockholm',
  Helsinki: 'Europe/Helsinki',
  Reykjavik: 'Atlantic/Reykjavik',
  Athens: 'Europe/Athens',
  Istanbul: 'Europe/Istanbul',
  Kyiv: 'Europe/Kyiv',
  Moscow: 'Europe/Moscow',
  Cairo: 'Africa/Cairo',
  Lagos: 'Africa/Lagos',
  Nairobi: 'Africa/Nairobi',
  Johannesburg: 'Africa/Johannesburg',
  'Cape Town': 'Africa/Johannesburg',
  'Tel Aviv': 'Asia/Jerusalem',
  Jerusalem: 'Asia/Jerusalem',
  Riyadh: 'Asia/Riyadh',
  Dubai: 'Asia/Dubai',
  Tehran: 'Asia/Tehran',
  Karachi: 'Asia/Karachi',
  Mumbai: 'Asia/Kolkata',
  Delhi: 'Asia/Kolkata',
  'New Delhi': 'Asia/Kolkata',
  Bangalore: 'Asia/Kolkata',
  Kolkata: 'Asia/Kolkata',
  Kathmandu: 'Asia/Kathmandu',
  Dhaka: 'Asia/Dhaka',
  Bangkok: 'Asia/Bangkok',
  Hanoi: 'Asia/Bangkok',
  Jakarta: 'Asia/Jakarta',
  Singapore: 'Asia/Singapore',
  'Kuala Lumpur': 'Asia/Kuala_Lumpur',
  Manila: 'Asia/Manila',
  'Hong Kong': 'Asia/Hong_Kong',
  Shanghai: 'Asia/Shanghai',
  Beijing: 'Asia/Shanghai',
  Taipei: 'Asia/Taipei',
  Seoul: 'Asia/Seoul',
  Tokyo: 'Asia/Tokyo',
  Osaka: 'Asia/Tokyo',
  Kyoto: 'Asia/Tokyo',
  Perth: 'Australia/Perth',
  Adelaide: 'Australia/Adelaide',
  Brisbane: 'Australia/Brisbane',
  Sydney: 'Australia/Sydney',
  Melbourne: 'Australia/Melbourne',
  Auckland: 'Pacific/Auckland',
  Wellington: 'Pacific/Auckland',
  Honolulu: 'Pacific/Honolulu',
  Anchorage: 'America/Anchorage',
  Vancouver: 'America/Vancouver',
  Seattle: 'America/Los_Angeles',
  'San Francisco': 'America/Los_Angeles',
  'Los Angeles': 'America/Los_Angeles',
  'Las Vegas': 'America/Los_Angeles',
  Phoenix: 'America/Phoenix',
  Denver: 'America/Denver',
  Dallas: 'America/Chicago',
  Houston: 'America/Chicago',
  Chicago: 'America/Chicago',
  'Mexico City': 'America/Mexico_City',
  Toronto: 'America/Toronto',
  Montreal: 'America/Toronto',
  Atlanta: 'America/New_York',
  Miami: 'America/New_York',
  Washington: 'America/New_York',
  Boston: 'America/New_York',
  'New York': 'America/New_York',
  Bogota: 'America/Bogota',
  Lima: 'America/Lima',
  Santiago: 'America/Santiago',
  'Buenos Aires': 'America/Argentina/Buenos_Aires',
  'Sao Paulo': 'America/Sao_Paulo',
  'Rio de Janeiro': 'America/Sao_Paulo',
};

/** A city's zone by its name, whatever its case or its accents ("São Paulo", "bogotá"); undefined for one not here. */
export function zoneOf(name: string): string | undefined {
  const plain = fold(name);
  const key = Object.keys(CITY_ZONES).find((city) => fold(city) === plain);
  return key ? CITY_ZONES[key] : undefined;
}

/** The city a zone is named for here, for "London" in place of "here"; undefined for a zone with no city in the table. */
export function cityOf(zone: string): string | undefined {
  const cities = Object.keys(CITY_ZONES).filter((city) => CITY_ZONES[city] === zone);
  // The city the zone is named for, where it is one: America/New_York is New York, not Atlanta.
  const named = (zone.split('/').pop() ?? '').replace(/_/g, ' ');
  return cities.find((city) => city === named) ?? cities[0];
}

/** Lower case, accents off. */
function fold(text: string): string {
  return text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim();
}

/** Every city, longest first, so "New Delhi" is found before "Delhi" and "Mexico City" before nothing. */
export const CITIES: readonly string[] = Object.keys(CITY_ZONES).sort((a, b) => b.length - a.length);
