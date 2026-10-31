/// Which calendars the app reads, kept with the account's settings (docs/CALENDAR.md): the iCal addresses pasted in,
/// and Google's sign-in, the calendars ticked and where the to-dos go. They travel sealed with the rest of the
/// settings (lib/sync/prefs.dart, `calendars`), so a calendar added on the phone is on the Mac; they are never in a
/// note, never logged, and sent nowhere but to fetch them. What each device fetched is its own (lib/calendar/store.dart).
///
/// Kept under the preferences' `calendars` key as JSON, which the typed [Preferences] keeps among the keys it does
/// not model ([Preferences.more]) and writes back as it was read: [calendarSetupOf] reads it, [withCalendarSetup]
/// writes it.
///
/// THE SECRETS ARE NOT IN IT (2026-10-31; docs/MARKDOWN_FIRST.md §11 decision 22). An iCal address is a secret (it
/// reads the calendar), and so is Google's refresh token; both sat in the clear in the blob on the device, which the
/// export's settings.json dumped whole. Now the blob keeps an address's id and name and Google's choices, and each
/// secret is in the device's secure store (lib/sync/kept_secrets.dart) under [icalAddressName] or
/// [googleRefreshName], travelling to the account's other devices as a sealed key (lib/sync/connections.dart).
/// Read-both: a blob written by an older build still carries them, and [CalendarSetup.fromJson] takes the blob's
/// over the store's; [CalendarService] then writes them to the store and writes the blob again without them
/// ([CalendarSetup.toStored]). An older build reading a blob so written sees no address and no Google until it is
/// updated: the one-release cost, taken.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/preferences.dart';
import '../plugins/notion/sha256.dart';
import '../sync/kept_secrets.dart' show SecretPeek;

export '../sync/kept_secrets.dart' show SecretPeek;

/// The preferences' key.
const String calendarsKey = 'calendars';

/// The secure store's name for Google's refresh token: the account's, so it travels (lib/sync/connections.dart).
const String googleRefreshName = 'glyph-google-refresh';

/// The secure store's name for Google's access token, with when it runs out: this device's own, never synced (Google
/// does not turn the refresh token over, so every device makes its own access tokens from the same one).
const String googleAccessName = 'glyph-google-token';

/// The secure store's names for the iCal addresses, each by the id the blob lists it under.
const String icalAddressPrefix = 'glyph-ical-url:';
String icalAddressName(String id) => '$icalAddressPrefix$id';

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

  /// Whole, the address included: for comparing two, never for the blob.
  Map<String, Object?> toJson() => {'id': id, 'url': url, if (name != null) 'name': name};

  /// As the blob keeps it: its id and name, never the address (see the header).
  Map<String, Object?> toStored() => {'id': id, if (name != null) 'name': name};

  /// From the blob: the address from the blob where an older build wrote it there, else from [secret] by its id; null
  /// where neither has it (an address added on a newer device whose secret has not arrived yet, or not loaded yet).
  static CalendarAddress? fromJson(Object? raw, {SecretPeek? secret}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final given = raw['url'];
    final url = given is String && given.isNotEmpty ? given : (id is String && id.isNotEmpty ? secret?.call(icalAddressName(id)) : null);
    if (url == null || url.isEmpty) return null;
    final name = raw['name'];
    return CalendarAddress(id: id is String && id.isNotEmpty ? id : addressId(url), url: url, name: name is String && name.isNotEmpty ? name : null);
  }

  /// Whether the blob [raw] carries the address itself, as an older build wrote it.
  static bool storedInTheClear(Object? raw) => raw is Map && raw['url'] is String && (raw['url'] as String).isNotEmpty;

  @override
  bool operator ==(Object other) => other is CalendarAddress && other.id == id && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(id, url, name);
}

/// Google's side: the refresh token, the calendars ticked, and the to-dos' switch and calendar.
@immutable
class GoogleSetup {
  const GoogleSetup({required this.refreshToken, this.ticked = const [], this.todos = false, this.todoCalendar});

  /// Empty where Google is connected to the account but this device has no refresh token for it yet (the secret has
  /// not arrived, or not loaded): the pass says so rather than call Google with nothing.
  final String refreshToken;

  /// The ids of the calendars whose events are read.
  final List<String> ticked;

  /// To-dos on the calendar: off until turned on.
  final bool todos;

  /// The calendar the to-dos go on; the primary where none was chosen.
  final String? todoCalendar;

  GoogleSetup copyWith({List<String>? ticked, bool? todos, String? Function()? todoCalendar}) =>
      GoogleSetup(refreshToken: refreshToken, ticked: ticked ?? this.ticked, todos: todos ?? this.todos, todoCalendar: todoCalendar != null ? todoCalendar() : this.todoCalendar);

  /// Whole, the token included: for comparing two, never for the blob.
  Map<String, Object?> toJson() => {'refreshToken': refreshToken, 'ticked': ticked, 'todos': todos, if (todoCalendar != null) 'todoCalendar': todoCalendar};

  /// As the blob keeps it: the choices, never the token (see the header).
  Map<String, Object?> toStored() => {'ticked': ticked, 'todos': todos, if (todoCalendar != null) 'todoCalendar': todoCalendar};

  /// From the blob: the token from the blob where an older build wrote it there, else from [secret]; empty where
  /// neither has it. Null only where Google is not connected at all.
  static GoogleSetup? fromJson(Object? raw, {SecretPeek? secret}) {
    if (raw is! Map) return null;
    final given = raw['refreshToken'];
    final ticked = raw['ticked'];
    final calendar = raw['todoCalendar'];
    return GoogleSetup(
      refreshToken: given is String && given.isNotEmpty ? given : (secret?.call(googleRefreshName) ?? ''),
      ticked: ticked is List ? List.unmodifiable(ticked.whereType<String>()) : const [],
      todos: raw['todos'] == true,
      todoCalendar: calendar is String && calendar.isNotEmpty ? calendar : null,
    );
  }

  /// Whether the blob [raw] carries the token itself, as an older build wrote it.
  static bool storedInTheClear(Object? raw) => raw is Map && raw['refreshToken'] is String && (raw['refreshToken'] as String).isNotEmpty;
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

  /// Whole, the secrets included: for comparing two, never for the blob.
  Map<String, Object?> toJson() => {
        'addresses': [for (final address in addresses) address.toJson()],
        if (google != null) 'google': google!.toJson(),
      };

  /// As the blob keeps it: nothing that reads a calendar (see the header).
  Map<String, Object?> toStored() => {
        'addresses': [for (final address in addresses) address.toStored()],
        if (google != null) 'google': google!.toStored(),
      };

  /// From the blob, the secrets from the blob where an older build wrote them there, else from [secret]. An address
  /// whose secret is in neither is left out until it arrives.
  static CalendarSetup fromJson(Object? raw, {SecretPeek? secret}) {
    if (raw is! Map) return none;
    final list = raw['addresses'];
    return CalendarSetup(
      addresses: List.unmodifiable([
        if (list is List)
          for (final each in list) ?CalendarAddress.fromJson(each, secret: secret),
      ]),
      google: GoogleSetup.fromJson(raw['google'], secret: secret),
    );
  }

  /// The ids of the addresses the blob [raw] lists, secret here or not: what to load, and what to sync.
  static List<String> addressIdsIn(Object? raw) {
    final list = raw is Map ? raw['addresses'] : null;
    return [
      if (list is List)
        for (final each in list)
          if (each is Map && each['id'] is String && (each['id'] as String).isNotEmpty) each['id'] as String,
    ];
  }

  /// Whether the blob [raw] carries any secret in the clear, as an older build wrote it: then it is taken out.
  static bool storedInTheClear(Object? raw) {
    if (raw is! Map) return false;
    final list = raw['addresses'];
    return GoogleSetup.storedInTheClear(raw['google']) || (list is List && list.any(CalendarAddress.storedInTheClear));
  }

  @override
  bool operator ==(Object other) => other is CalendarSetup && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The calendars [prefs] keeps, their secrets from [secret] where the blob no longer carries them.
CalendarSetup calendarSetupOf(Preferences prefs, {SecretPeek? secret}) => CalendarSetup.fromJson(prefs.more[calendarsKey], secret: secret);

/// [prefs] with [setup] kept, without its secrets; with none at all, the key is taken off.
Preferences withCalendarSetup(Preferences prefs, CalendarSetup setup) {
  final more = {...prefs.more};
  if (setup.isEmpty) {
    more.remove(calendarsKey);
  } else {
    more[calendarsKey] = setup.toStored();
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
