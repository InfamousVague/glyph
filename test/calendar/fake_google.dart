// Google, and glyph-api's Google routes, in memory: what test/calendar/google_test.dart and calendar_test.dart talk
// to. The service's sign-in (`start`, `claim`, `refresh`) and the Calendar API's calendarList and events, each call
// kept in [FakeGoogle.calls].
import 'dart:convert';

import 'package:ghost_md/account/api.dart';

const String fakeBase = 'https://service.test/api/google';

class FakeGoogle {
  /// Whether glyph-api has Google sign-in set up; without it every route answers 503.
  bool configured = true;

  /// How many claims answer 202 before the tokens.
  int pendingClaims = 1;

  /// The access token that works; any other is a 401.
  String access = 'access-1';
  int refreshes = 0;
  bool refreshRefused = false;

  /// How many claims are turned away as glyph-api's rate limit does (429) before the next is answered.
  int limitedClaims = 0;

  final List<String> calls = [];

  final List<Map<String, Object?>> calendars = [
    {'id': 'me@example.com', 'summary': 'Me', 'primary': true, 'accessRole': 'owner'},
    {'id': 'team@group.calendar.google.com', 'summary': 'Team', 'accessRole': 'reader'},
  ];

  /// Each calendar's events by id, as Google keeps them (a deleted one stays, cancelled).
  final Map<String, Map<String, Map<String, Object?>>> events = {
    'me@example.com': {},
    'team@group.calendar.google.com': {},
  };

  FetchResponse _json(int status, Object? body) => FetchResponse.json(status, body);

  Future<FetchResponse> fetch(FetchRequest request) async {
    final url = request.url;
    calls.add('${request.method} ${url.path}${url.query.isEmpty ? '' : '?${url.query}'}');
    if (url.toString().startsWith(fakeBase)) {
      if (!configured) return _json(503, {'error': 'Google sign-in is not set up yet.'});
      final route = url.path.split('/').last;
      switch (route) {
        case 'start':
          return FetchResponse(url.queryParameters['state'] == 'probe' ? 400 : 302);
        case 'claim':
          final body = jsonDecode(request.text) as Map;
          if (body['state'] == 'gone') return _json(404, {'error': 'no sign-in with that state, or it expired'});
          if (limitedClaims > 0) {
            limitedClaims -= 1;
            return _json(429, {'error': 'rate limited'});
          }
          if (pendingClaims > 0) {
            pendingClaims -= 1;
            return FetchResponse(202);
          }
          return _json(200, {'accessToken': access, 'refreshToken': 'refresh-1', 'expiresIn': 3600, 'scope': 'calendar.events'});
        case 'refresh':
          if (refreshRefused) return _json(400, {'error': 'invalid_grant'});
          refreshes += 1;
          access = 'access-${refreshes + 1}';
          return _json(200, {'accessToken': access, 'expiresIn': 3600});
      }
      return _json(404, {'error': 'no such route'});
    }
    if (request.bearer != access) return _json(401, {'error': {'message': 'Invalid Credentials'}});
    final parts = url.pathSegments.skipWhile((each) => each != 'v3').skip(1).toList();
    if (parts.length == 3 && parts[0] == 'users' && parts[2] == 'calendarList') return _json(200, {'items': calendars});
    if (parts.length >= 3 && parts[0] == 'calendars' && parts[2] == 'events') {
      final calendar = parts[1];
      final kept = events[calendar];
      if (kept == null) return _json(404, {'error': {'message': 'Not Found'}});
      if (parts.length == 3 && request.method == 'GET') {
        final marked = url.queryParameters['privateExtendedProperty'];
        final items = [
          for (final item in kept.values)
            if (marked == null || (((item['extendedProperties'] as Map?)?['private'] as Map?)?['ghostmd'] == '1' && item['status'] != 'cancelled'))
              if (marked != null || item['status'] != 'cancelled') item,
        ];
        return _json(200, {'items': items});
      }
      if (parts.length == 3 && request.method == 'POST') {
        final body = (jsonDecode(request.text) as Map).cast<String, Object?>();
        final id = body['id'] as String;
        if (kept.containsKey(id)) return _json(409, {'error': {'message': 'The requested identifier already exists.'}});
        kept[id] = body;
        return _json(200, body);
      }
      final id = parts[3];
      final item = kept[id];
      if (item == null) return _json(404, {'error': {'message': 'Not Found'}});
      switch (request.method) {
        case 'GET':
          return _json(200, item);
        case 'PATCH':
          final body = (jsonDecode(request.text) as Map).cast<String, Object?>();
          kept[id] = {...item, ...body};
          return _json(200, kept[id]);
        case 'DELETE':
          kept[id] = {...item, 'status': 'cancelled'};
          return FetchResponse(204);
      }
    }
    return _json(404, {'error': {'message': 'Not Found'}});
  }

  /// The calls that changed an event: inserts, patches and deletes, by method and id.
  List<String> get changes => [
        for (final call in calls)
          if (call.startsWith('POST /calendar') || call.startsWith('PATCH') || call.startsWith('DELETE')) call.replaceFirst(RegExp(r'/calendar/v3/calendars/[^/]+/events'), '').trim(),
      ];
}
