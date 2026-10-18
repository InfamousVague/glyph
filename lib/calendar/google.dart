/// Google Calendar, two-way, through glyph-api's sign-in (docs/CALENDAR.md, "Two-way, with Google sign-in"): the
/// account's calendars, their events, and the to-dos with a due date put on one of them as all-day events.
///
/// Signing in is Notion's shape (lib/plugins/notion/client.dart, server/src/notion.rs): a random state and verifier,
/// the browser opened at `start` with the verifier's SHA-256 ([googleChallenge]), and the tokens collected from
/// `claim` when the person comes back ([GoogleCalendarApi.claim]). A refresh token is turned into a fresh access
/// token by `refresh`; nothing comes back by a link.
///
/// Every call to Google is [GoogleSession.call]: the access token, refreshed through glyph-api when it has run out
/// and once more on a 401. Only the routes Ghost.md uses are called: calendarList, and a calendar's events.
///
/// **To-dos on the calendar** ([exportTodos]): each open to-do with a due date is an all-day event whose id is made
/// from its note's id and its anchor or words ([todoEventId]), so the same to-do is always the same event. Every
/// event the app makes carries a private extended property, `ghostmd=1`; the app changes and deletes only the
/// events Google lists with it, and an event of the same id without it is left alone.
///
/// Pure over a [Fetcher], so the whole of it runs against a fake (test/calendar/google_test.dart).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../account/api.dart' show FetchRequest, FetchResponse, Fetcher;
import '../core/bytes.dart' show toBase64Url;
import '../core/days.dart' show isoDay, isoDayAfter;
import '../core/query/records.dart' show QueryLibrary, RecordKind;
import '../plugins/notion/sha256.dart';
import 'event.dart';

/// Google's Calendar API.
const String googleCalendarApi = 'https://www.googleapis.com/calendar/v3/';

/// The private extended property every event the app makes carries, and the only events it changes.
const String todoMarkKey = 'ghostmd';
const String todoMarkValue = '1';

/// How long a call to Google may take.
const Duration _patience = Duration(seconds: 30);

/// Something Google, the service or this app said about a call that did not work, as the sentence a person reads.
class GoogleFailure implements Exception {
  const GoogleFailure(this.message, [this.status = 0]);
  final String message;
  final int status;

  @override
  String toString() => message;
}

/// The challenge the server recomputes from the verifier: its SHA-256, base64url without padding (as Notion's).
String googleChallenge(String verifier) => toBase64Url(sha256(utf8.encode(verifier)));

final Random _random = Random.secure();

/// A fresh state or verifier: 32 random bytes, base64url.
String googleToken() => toBase64Url(Uint8List.fromList([for (var i = 0; i < 32; i++) _random.nextInt(256)]));

/// What a sign-in or a refresh gave: the access token, a refresh token where one came, and when the access token
/// stops working, in milliseconds.
class GoogleTokens {
  const GoogleTokens({required this.accessToken, this.refreshToken, required this.expiresAt});

  final String accessToken;
  final String? refreshToken;
  final int expiresAt;

  /// glyph-api's answer (`{ accessToken, refreshToken?, expiresIn, scope }`) read at [now]; null for one with no
  /// access token.
  static GoogleTokens? fromAnswer(Object? raw, int now) {
    if (raw is! Map) return null;
    final access = raw['accessToken'];
    if (access is! String || access.isEmpty) return null;
    final refresh = raw['refreshToken'];
    final expires = raw['expiresIn'];
    // A minute early, so a call is never sent with a token about to run out.
    final seconds = expires is num ? expires.toInt() : 3600;
    return GoogleTokens(accessToken: access, refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null, expiresAt: now + (seconds - 60) * 1000);
  }

  /// As this device keeps it. The refresh token is kept with the account's settings, not here.
  Map<String, Object?> toJson() => {'accessToken': accessToken, 'expiresAt': expiresAt};

  static GoogleTokens? fromJson(Object? raw) {
    if (raw is! Map || raw['accessToken'] is! String || raw['expiresAt'] is! num) return null;
    return GoogleTokens(accessToken: raw['accessToken'] as String, expiresAt: (raw['expiresAt'] as num).toInt());
  }
}

/// What collecting a sign-in found.
sealed class GoogleClaim {
  const GoogleClaim();
}

/// The person is still on Google's page.
class GooglePending extends GoogleClaim {
  const GooglePending();
}

class GoogleSignedIn extends GoogleClaim {
  const GoogleSignedIn(this.tokens);
  final GoogleTokens tokens;
}

/// One of the account's calendars (calendarList).
class GoogleCalendarInfo {
  const GoogleCalendarInfo({required this.id, required this.name, this.primary = false, this.writable = false});
  final String id;
  final String name;
  final bool primary;

  /// Whether the app may put to-dos on it: the account owns it or may write to it.
  final bool writable;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'primary': primary, 'writable': writable};

  static GoogleCalendarInfo? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final name = raw['name'];
    return GoogleCalendarInfo(id: raw['id'] as String, name: name is String ? name : raw['id'] as String, primary: raw['primary'] == true, writable: raw['writable'] == true);
  }
}

Object? _json(FetchResponse response) {
  try {
    return response.bytes.isEmpty ? null : jsonDecode(response.text);
  } catch (_) {
    return null;
  }
}

String? _said(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  if (error is String) return error;
  if (error is Map && error['message'] is String) return error['message'] as String;
  return null;
}

/// glyph-api's Google routes at [base] (`…/api/google`), and Google's own, through one [Fetcher].
class GoogleCalendarApi {
  GoogleCalendarApi({required this.base, required this.fetch, int Function()? clock}) : now = clock ?? _clock;

  /// Where glyph-api's Google routes are: `start`, `claim`, `refresh`.
  final String base;
  final Fetcher fetch;
  final int Function() now;

  static int _clock() => DateTime.now().millisecondsSinceEpoch;

  /// Whether the service has Google sign-in set up: `start` turns the probe away as a broken link (400; its state is
  /// too short to be kept, so it starts no sign-in) or as busy (429). A service with sign-in not set up answers 503,
  /// and one from before it had Google at all answers 404 "no such route": neither offers Connect (Matt, 2026-10-17,
  /// pressed it on such a service and was sent to that 404).
  Future<bool> offered() async {
    try {
      final response = await fetch(FetchRequest(method: 'GET', url: Uri.parse('$base/start?state=probe&challenge=probe'), timeout: const Duration(seconds: 10)));
      return response.status == 400 || response.status == 429;
    } catch (_) {
      return false;
    }
  }

  /// Where the browser goes to sign in.
  Uri startUrl(String state, String challenge) => Uri.parse('$base/start?state=${Uri.encodeComponent(state)}&challenge=${Uri.encodeComponent(challenge)}');

  /// Collects a sign-in: [GooglePending] while the person is still on Google's page, the tokens once they finished.
  /// One that was refused, expired or never started says why.
  Future<GoogleClaim> claim(String state, String verifier) async {
    final FetchResponse response;
    try {
      response = await fetch(FetchRequest(
        method: 'POST',
        url: Uri.parse('$base/claim'),
        headers: const {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'state': state, 'verifier': verifier})),
        timeout: _patience,
      ));
    } catch (_) {
      throw const GoogleFailure("Google sign-in couldn't be reached. Check the connection.");
    }
    if (response.status == 202) return const GooglePending();
    final body = _json(response);
    if (response.status == 404) throw const GoogleFailure('That sign-in ran out of time. Connect Google Calendar again.', 404);
    if (!response.ok) throw GoogleFailure(_said(body) ?? 'Google sign-in did not finish.', response.status);
    final tokens = GoogleTokens.fromAnswer(body, now());
    if (tokens == null) throw const GoogleFailure("Google didn't give Ghost.md an access token.", 422);
    return GoogleSignedIn(tokens);
  }

  /// A fresh access token for [refreshToken]; null where glyph-api would not give one (the sign-in was taken back).
  Future<GoogleTokens?> refresh(String refreshToken) async {
    final FetchResponse response;
    try {
      response = await fetch(FetchRequest(
        method: 'POST',
        url: Uri.parse('$base/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: utf8.encode(jsonEncode({'refreshToken': refreshToken})),
        timeout: _patience,
      ));
    } catch (_) {
      throw const GoogleFailure("Google couldn't be reached. Check the connection.");
    }
    if (response.status == 400 || response.status == 401 || response.status == 403) return null;
    if (!response.ok) throw GoogleFailure(_said(_json(response)) ?? 'Google answered ${response.status}.', response.status);
    return GoogleTokens.fromAnswer(_json(response), now());
  }
}

/// A signed-in Google account's calls: the access token kept fresh with the refresh token, and every fresh one told
/// to [onTokens] to be kept.
class GoogleSession {
  GoogleSession({required this.api, required this.refreshToken, GoogleTokens? tokens, this.onTokens}) : _tokens = tokens;

  final GoogleCalendarApi api;
  final String refreshToken;
  GoogleTokens? _tokens;
  final void Function(GoogleTokens tokens)? onTokens;

  Future<String> _token({bool fresh = false}) async {
    final held = _tokens;
    if (!fresh && held != null && held.expiresAt > api.now()) return held.accessToken;
    final next = await api.refresh(refreshToken);
    if (next == null) throw const GoogleFailure('Google signed Ghost.md out. Connect Google Calendar again in Settings › Plugins › Calendar.', 401);
    _tokens = next;
    onTokens?.call(next);
    return next.accessToken;
  }

  /// A call to Google's Calendar API: [path] below `calendar/v3/`, [query] its parameters. Answers the status and
  /// the body read as JSON. A 401 is answered by a fresh token, once.
  Future<({int status, Object? body})> call(String method, String path, {Map<String, Object?>? query, Object? body}) async {
    final url = Uri.parse('$googleCalendarApi$path').replace(queryParameters: query == null ? null : {for (final MapEntry(:key, :value) in query.entries) if (value != null) key: '$value'});
    Future<FetchResponse> send(String token) async {
      try {
        return await api.fetch(FetchRequest(
          method: method,
          url: url,
          headers: {'Authorization': 'Bearer $token', if (body != null) 'Content-Type': 'application/json'},
          body: body == null ? null : utf8.encode(jsonEncode(body)),
          timeout: _patience,
        ));
      } catch (_) {
        throw const GoogleFailure("Google couldn't be reached. Check the connection.");
      }
    }

    var response = await send(await _token());
    if (response.status == 401) response = await send(await _token(fresh: true));
    return (status: response.status, body: _json(response));
  }

  /// [call], with a refusal as a [GoogleFailure].
  Future<Object?> ask(String method, String path, {Map<String, Object?>? query, Object? body}) async {
    final answer = await call(method, path, query: query, body: body);
    if (answer.status >= 400) {
      if (answer.status == 401) throw const GoogleFailure('Google signed Ghost.md out. Connect Google Calendar again in Settings › Plugins › Calendar.', 401);
      throw GoogleFailure(_said(answer.body) ?? 'Google answered ${answer.status}.', answer.status);
    }
    return answer.body;
  }

  /// Every page of a list, its `items` together.
  Future<List<Map<Object?, Object?>>> _pages(String path, Map<String, Object?> query) async {
    final items = <Map<Object?, Object?>>[];
    String? next;
    for (var page = 0; page < 40; page += 1) {
      final body = await ask('GET', path, query: {...query, 'pageToken': ?next});
      if (body is! Map) break;
      final found = body['items'];
      if (found is List) items.addAll(found.whereType<Map<Object?, Object?>>());
      final token = body['nextPageToken'];
      if (token is! String || token.isEmpty) break;
      next = token;
    }
    return items;
  }

  /// The account's calendars, the primary first.
  Future<List<GoogleCalendarInfo>> calendars() async {
    final items = await _pages('users/me/calendarList', {'maxResults': 250});
    final list = [
      for (final item in items)
        if (item['id'] is String && item['deleted'] != true)
          GoogleCalendarInfo(
            id: item['id'] as String,
            name: (item['summaryOverride'] ?? item['summary'] ?? item['id']) as String,
            primary: item['primary'] == true,
            writable: item['accessRole'] == 'owner' || item['accessRole'] == 'writer',
          ),
    ];
    list.sort((a, b) => a.primary == b.primary ? 0 : (a.primary ? -1 : 1));
    return list;
  }

  /// The events of [calendar] that overlap [from] to [to], each repeating one as its instances. The to-dos the app
  /// put there are left out: they are to-dos already.
  Future<List<CalendarEvent>> events(GoogleCalendarInfo calendar, {required DateTime from, required DateTime to}) async {
    final items = await _pages('calendars/${Uri.encodeComponent(calendar.id)}/events', {
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': 2500,
      'timeMin': from.toUtc().toIso8601String(),
      'timeMax': to.toUtc().toIso8601String(),
    });
    return [
      for (final item in items)
        if (!isOurs(item)) ?googleEvent(item, calendar),
    ];
  }

  // ---- to-dos on the calendar --------------------------------------------------------------------------------

  /// The events on [calendarId] the app made: listed by their mark, so nothing else is ever in it.
  Future<Map<String, Map<Object?, Object?>>> ours(String calendarId) async {
    final items = await _pages('calendars/${Uri.encodeComponent(calendarId)}/events', {
      'privateExtendedProperty': '$todoMarkKey=$todoMarkValue',
      'maxResults': 2500,
      'showDeleted': 'false',
    });
    return {
      for (final item in items)
        if (item['id'] is String && isOurs(item) && item['status'] != 'cancelled') item['id'] as String: item,
    };
  }
}

/// Whether Google's event carries the app's mark.
bool isOurs(Map<Object?, Object?> item) {
  final extended = item['extendedProperties'];
  final private = extended is Map ? extended['private'] : null;
  return private is Map && private[todoMarkKey] == todoMarkValue;
}

/// Google's event as the app keeps it; null for a cancelled one, or one with no start.
CalendarEvent? googleEvent(Map<Object?, Object?> item, GoogleCalendarInfo calendar) {
  if (item['status'] == 'cancelled') return null;
  final id = item['id'];
  final start = item['start'], end = item['end'];
  if (id is! String || start is! Map) return null;
  DateTime? read(Object? when, {required bool date}) {
    if (when is! Map) return null;
    if (date) {
      final day = when['date'];
      final at = day is String ? DateTime.tryParse(day) : null;
      return at == null ? null : DateTime(at.year, at.month, at.day);
    }
    final moment = when['dateTime'];
    return moment is String ? DateTime.tryParse(moment)?.toUtc() : null;
  }

  final allDay = start['date'] is String;
  final begins = read(start, date: allDay);
  if (begins == null) return null;
  final ends = read(end, date: allDay) ?? (allDay ? DateTime(begins.year, begins.month, begins.day + 1) : begins);
  final title = item['summary'];
  final location = item['location'];
  return CalendarEvent(
    id: id,
    source: 'google:${calendar.id}',
    calendar: calendar.name,
    title: title is String && title.trim().isNotEmpty ? title.trim() : 'Untitled event',
    start: begins,
    end: ends,
    allDay: allDay,
    location: location is String && location.trim().isNotEmpty ? location.trim() : null,
  );
}

/// Base32hex's letters, lower case: what Google takes in an event's id (`a-v`, `0-9`).
const String _base32hex = '0123456789abcdefghijklmnopqrstuv';

String _toBase32hex(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32hex[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_base32hex[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// The event id of a to-do: `gm` and the base32hex of the SHA-256 of its note's id and its anchor, or its words
/// where it has none (54 characters, all Google takes). The same to-do is always the same event, whatever its date.
String todoEventId(String noteId, {String? anchor, required String words}) {
  final which = anchor != null && anchor.isNotEmpty ? '^$anchor' : words.trim().toLowerCase();
  return 'gm${_toBase32hex(sha256(utf8.encode('$noteId\n$which')))}';
}

/// A to-do as the calendar has it: an all-day event on its due day.
class TodoEvent {
  const TodoEvent({required this.id, required this.title, required this.day, required this.noteId});
  final String id;
  final String title;

  /// Its due day, `YYYY-MM-DD`.
  final String day;
  final String noteId;

  /// A link back to its note, the event's description.
  String get description => 'ghostmd://note/$noteId';

  /// The event as Google is sent it.
  Map<String, Object?> body({bool withId = true}) => {
        if (withId) 'id': id,
        'summary': title,
        'description': description,
        'start': {'date': day},
        'end': {'date': isoDayAfter(day, 1)},
        'transparency': 'transparent',
        'status': 'confirmed',
        'extendedProperties': {
          'private': {todoMarkKey: todoMarkValue},
        },
      };
}

/// Every open to-do with a due date in [library], as its event: one per id, the first written where two are the
/// same to-do.
List<TodoEvent> todoEvents(QueryLibrary library) {
  final out = <String, TodoEvent>{};
  for (final record in library.records) {
    if (record.kind != RecordKind.task || record.done != false) continue;
    final due = record.fields?.date('due');
    if (due == null || due.isEmpty || record.text.trim().isEmpty) continue;
    final id = todoEventId(record.noteId, anchor: record.anchor, words: record.text);
    out.putIfAbsent(id, () => TodoEvent(id: id, title: record.text.trim(), day: due, noteId: record.noteId));
  }
  return out.values.toList();
}

/// What a pass of the to-dos did.
typedef TodoExport = ({int added, int moved, int removed});

/// Puts [wanted] on [calendarId] (`events.insert`, `patch`, `delete`): a to-do not there yet is added, one whose day
/// or words changed is moved, and an event the app made that is no to-do any more (ticked, removed, its date taken
/// off) is deleted. Only events listed with the app's mark are changed; an id taken by one without it is left as it
/// is.
Future<TodoExport> exportTodos(GoogleSession session, String calendarId, List<TodoEvent> wanted) async {
  final path = 'calendars/${Uri.encodeComponent(calendarId)}/events';
  final made = await session.ours(calendarId);
  var added = 0, moved = 0, removed = 0;
  for (final todo in wanted) {
    final there = made.remove(todo.id);
    if (there != null) {
      final start = there['start'];
      final same = start is Map && start['date'] == todo.day && there['summary'] == todo.title && there['description'] == todo.description;
      if (!same) {
        await session.ask('PATCH', '$path/${todo.id}', body: todo.body(withId: false));
        moved += 1;
      }
      continue;
    }
    final answer = await session.call('POST', path, body: todo.body());
    if (answer.status == 409) {
      // The id is taken: by one of the app's own that was deleted (Google keeps it, cancelled), which is put back;
      // or by an event the app did not make, which is never touched.
      final existing = await session.call('GET', '$path/${todo.id}');
      final item = existing.body;
      if (existing.status < 400 && item is Map<Object?, Object?> && isOurs(item)) {
        await session.ask('PATCH', '$path/${todo.id}', body: todo.body(withId: false));
        added += 1;
      }
      continue;
    }
    if (answer.status >= 400) throw GoogleFailure(_said(answer.body) ?? 'Google answered ${answer.status}.', answer.status);
    added += 1;
  }
  for (final id in made.keys) {
    final answer = await session.call('DELETE', '$path/$id');
    // Gone already is gone.
    if (answer.status >= 400 && answer.status != 404 && answer.status != 410) throw GoogleFailure(_said(answer.body) ?? 'Google answered ${answer.status}.', answer.status);
    removed += 1;
  }
  return (added: added, moved: moved, removed: removed);
}

/// The calendar a Google iCal address is the secret address of (`…/calendar/ical/<id>/private-…/basic.ics`), or
/// null for any other address: an address for a calendar that is ticked under Google is not read twice.
String? googleCalendarOfAddress(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.host.endsWith('google.com')) return null;
  final parts = uri.pathSegments;
  final at = parts.indexOf('ical');
  if (at < 0 || at + 1 >= parts.length) return null;
  return Uri.decodeComponent(parts[at + 1]);
}

/// Today on this device's clock, as a day.
String todayDay([DateTime? now]) => isoDay(now ?? DateTime.now());
