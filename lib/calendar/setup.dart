/// Which calendars the app reads, kept with the account's settings (docs/CALENDAR.md): the iCal addresses pasted in,
/// and Google's sign-in, the calendars ticked and where the to-dos go. They travel sealed with the rest of the
/// settings (lib/sync/prefs.dart, `calendars`), so a calendar added on the phone is on the Mac; they are never in a
/// note, never logged, and sent nowhere but to fetch them. What each device fetched is its own (lib/calendar/store.dart).
///
/// Kept under the preferences' `calendars` key as JSON, which the typed [Preferences] keeps among the keys it does
/// not model ([Preferences.more]) and writes back as it was read: [calendarSetupOf] reads it, [withCalendarSetup]
/// writes it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/preferences.dart';
import '../plugins/notion/sha256.dart';

/// The preferences' key.
const String calendarsKey = 'calendars';

/// An iCal address pasted in: a secret, so it is shown by its calendar's name and never in full.
@immutable
class CalendarAddress {
  const CalendarAddress({required this.id, required this.url, this.name});

  /// Made from the address itself ([addressId]), so the same address added on two devices is one.
  final String id;
  final String url;

  /// The calendar's own name, once a fetch has said it.
  final String? name;

  /// What a row says of it: its name, or the address's host.
  String get label => name ?? Uri.tryParse(url)?.host ?? 'Calendar';

  CalendarAddress named(String? next) => CalendarAddress(id: id, url: url, name: next);

  Map<String, Object?> toJson() => {'id': id, 'url': url, if (name != null) 'name': name};

  static CalendarAddress? fromJson(Object? raw) {
    if (raw is! Map || raw['url'] is! String) return null;
    final url = raw['url'] as String;
    final id = raw['id'];
    final name = raw['name'];
    return CalendarAddress(id: id is String && id.isNotEmpty ? id : addressId(url), url: url, name: name is String && name.isNotEmpty ? name : null);
  }

  @override
  bool operator ==(Object other) => other is CalendarAddress && other.id == id && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(id, url, name);
}

/// Google's side: the refresh token, the calendars ticked, and the to-dos' switch and calendar.
@immutable
class GoogleSetup {
  const GoogleSetup({required this.refreshToken, this.ticked = const [], this.todos = false, this.todoCalendar});

  final String refreshToken;

  /// The ids of the calendars whose events are read.
  final List<String> ticked;

  /// To-dos on the calendar: off until turned on.
  final bool todos;

  /// The calendar the to-dos go on; the primary where none was chosen.
  final String? todoCalendar;

  GoogleSetup copyWith({List<String>? ticked, bool? todos, String? Function()? todoCalendar}) =>
      GoogleSetup(refreshToken: refreshToken, ticked: ticked ?? this.ticked, todos: todos ?? this.todos, todoCalendar: todoCalendar != null ? todoCalendar() : this.todoCalendar);

  Map<String, Object?> toJson() => {'refreshToken': refreshToken, 'ticked': ticked, 'todos': todos, if (todoCalendar != null) 'todoCalendar': todoCalendar};

  static GoogleSetup? fromJson(Object? raw) {
    if (raw is! Map || raw['refreshToken'] is! String || (raw['refreshToken'] as String).isEmpty) return null;
    final ticked = raw['ticked'];
    final calendar = raw['todoCalendar'];
    return GoogleSetup(
      refreshToken: raw['refreshToken'] as String,
      ticked: ticked is List ? List.unmodifiable(ticked.whereType<String>()) : const [],
      todos: raw['todos'] == true,
      todoCalendar: calendar is String && calendar.isNotEmpty ? calendar : null,
    );
  }
}

/// Every calendar the app reads.
@immutable
class CalendarSetup {
  const CalendarSetup({this.addresses = const [], this.google});

  static const CalendarSetup none = CalendarSetup();

  final List<CalendarAddress> addresses;

  /// Null until Google is connected.
  final GoogleSetup? google;

  bool get isEmpty => addresses.isEmpty && google == null;

  CalendarSetup copyWith({List<CalendarAddress>? addresses, GoogleSetup? Function()? google}) => CalendarSetup(addresses: addresses ?? this.addresses, google: google != null ? google() : this.google);

  Map<String, Object?> toJson() => {
        'addresses': [for (final address in addresses) address.toJson()],
        if (google != null) 'google': google!.toJson(),
      };

  static CalendarSetup fromJson(Object? raw) {
    if (raw is! Map) return none;
    final list = raw['addresses'];
    return CalendarSetup(
      addresses: List.unmodifiable([
        if (list is List)
          for (final each in list) ?CalendarAddress.fromJson(each),
      ]),
      google: GoogleSetup.fromJson(raw['google']),
    );
  }

  @override
  bool operator ==(Object other) => other is CalendarSetup && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The calendars [prefs] keeps.
CalendarSetup calendarSetupOf(Preferences prefs) => CalendarSetup.fromJson(prefs.more[calendarsKey]);

/// [prefs] with [setup] kept; with none at all, the key is taken off.
Preferences withCalendarSetup(Preferences prefs, CalendarSetup setup) {
  final more = {...prefs.more};
  if (setup.isEmpty) {
    more.remove(calendarsKey);
  } else {
    more[calendarsKey] = setup.toJson();
  }
  return prefs.copyWith(more: Map.unmodifiable(more));
}

/// An address's id: the first twelve bytes of its SHA-256, in hex.
String addressId(String url) => [for (final byte in sha256(utf8.encode(url.trim())).take(12)) byte.toRadixString(16).padLeft(2, '0')].join();

/// What a person pasted, as the address to fetch, or why it is not one: `webcal://` is read as `https://`, and only
/// a secure web address with a host is taken.
({String? url, String? problem}) calendarAddress(String typed) {
  final text = typed.trim();
  if (text.isEmpty) return (url: null, problem: 'Paste the calendar’s iCal address.');
  if (RegExp(r'\s').hasMatch(text)) return (url: null, problem: 'An iCal address has no spaces in it.');
  final secure = text.replaceFirst(RegExp(r'^webcals?://', caseSensitive: false), 'https://');
  final uri = Uri.tryParse(secure);
  if (uri == null || uri.host.isEmpty || !uri.hasScheme) return (url: null, problem: 'That isn’t a web address. An iCal address starts with https:// or webcal://.');
  if (uri.scheme.toLowerCase() == 'http') return (url: null, problem: 'Only a secure address (https:// or webcal://) is read: the address is a secret.');
  if (uri.scheme.toLowerCase() != 'https') return (url: null, problem: 'An iCal address starts with https:// or webcal://.');
  return (url: uri.toString(), problem: null);
}
