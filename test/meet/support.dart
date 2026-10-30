import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart' show toBase64Url;
import 'package:ghost_md/meet/live_captions.dart' show liveKeyContext, liveSealContext;
import 'package:ghost_md/meet/meet_api.dart';

/// A take laid out as the service lays one out before sealing it (server/src/meet.rs `pack`, `GMT1`).
Uint8List gmt1({String? title = 'Launch sync', String meeting = 'm1', String? kind, int startedAt = 1792159200000, int endedAt = 1792161900000, String mime = 'audio/webm;codecs=opus', List<Map<String, Object?>> captions = const [], List<int> audio = const [1, 2, 3, 4], Map<String, Object?>? head}) {
  final lines = utf8.encode(captions.map(jsonEncode).join('\n'));
  final said = utf8.encode(jsonEncode(head ??
      {
        'v': 1,
        'meeting': meeting,
        'title': title,
        'kind': ?kind,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'mime': mime,
        'captionsBytes': lines.length,
        'audioBytes': audio.length,
      }));
  return (BytesBuilder()
        ..add('GMT1'.codeUnits)
        ..add((ByteData(4)..setUint32(0, said.length)).buffer.asUint8List())
        ..add(said)
        ..add(lines)
        ..add(audio))
      .takeBytes();
}

/// [payload] sealed as the service seals take [id] to the account whose encryption public key is [pub].
Future<({String wrapped, Uint8List sealed})> sealedTake(AccountCrypto crypto, String pub, String id, Uint8List payload) async {
  final raw = crypto.randomBytes(32);
  final wrapped = await crypto.wrapFor(pub, raw, takeWrapContext(id));
  final key = await crypto.importSealKey(raw);
  return (wrapped: wrapped, sealed: await crypto.sealBytes(key, payload, takeSealContext(id)));
}

/// A frame of a meeting's live captions sealed as the service seals one (server/src/meet/live.rs): a fresh key wrapped
/// to the account in `meet-live-key:<meeting>:<n>`, the words sealed in `meet-live:<meeting>:<n>`, both base64url.
Future<({String wrapped, String data})> sealedLive(AccountCrypto crypto, String pub, String meeting, String n, {List<Map<String, Object?>> lines = const [], Map<String, Object?>? partial, int startedAt = 1792159200000}) async {
  final raw = crypto.randomBytes(32);
  final wrapped = await crypto.wrapFor(pub, raw, liveKeyContext(meeting, n));
  final key = await crypto.importSealKey(raw);
  final payload = Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'meeting': meeting, 'startedAt': startedAt, 'lines': lines, 'partial': partial})));
  return (wrapped: wrapped, data: toBase64Url(await crypto.sealBytes(key, payload, liveSealContext(meeting, n))));
}

/// The service's meeting routes in memory (docs/MEET.md, "Routes"), in front of another fetcher for the rest. As a
/// service from before pages (the default) it reads no query and answers `{meetings}` alone; with [paging] it is
/// today's: `GET meet?limit=` the meetings to come and the first page of those over, with the [series] and `next`,
/// `?before=` the page after, and `DELETE meet/series/{id}`.
class FakeMeet {
  FakeMeet({int Function()? now}) : now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final List<Map<String, Object?>> meetings = [];

  /// The account's running series, as `GET meet` lists them, with [paging].
  final List<Map<String, Object?>> series = [];

  /// Today's service: pages and series. Off, one from before them.
  bool paging = false;

  /// A page after the first is refused, as a connection dropping does, while this is true.
  bool failMore = false;

  /// The list itself is refused, as a connection dropping does, while this is true.
  bool failList = false;

  /// What the service takes for now: which meetings are over.
  final int Function() now;
  final Map<String, ({String meeting, int at, String wrapped, Uint8List sealed})> takes = {};

  /// Every meeting route asked, as `METHOD path`.
  final List<String> calls = [];

  /// False: a service from before the meeting routes, which answers each "no such route".
  bool routes = true;

  /// The body a POST was sent.
  Map<String, Object?>? booked;

  /// The account's kinds (server/src/meet.rs `MeetKinds`): every kind on until a device says otherwise.
  final Map<String, bool> kinds = {'meet': true, 'zoom': true};

  /// Each body `PUT meet/kinds` was sent, in order.
  final List<Map<String, Object?>> kindsSent = [];

  /// `PUT meet/kinds` is refused, as a connection dropping does, while this is true.
  bool failKinds = false;

  /// Each meeting's live captions the service keeps, `{seq, wrapped, data}` in order; and the meetings whose feed is
  /// over.
  final Map<String, List<Map<String, Object?>>> live = {};
  final Set<String> liveOver = {};

  Fetcher over(Fetcher rest) => (request) async {
        final path = request.url.path.replaceFirst(RegExp(r'^.*/v1/'), '');
        if (!path.startsWith('meet')) return rest(request);
        calls.add('${request.method} $path');
        if (!routes) return FetchResponse.json(404, {'error': 'no such route'});
        if (path == 'meet' && request.method == 'GET') {
          if (failList) return FetchResponse.json(503, {'error': 'The service is busy.'});
          if (!paging) return FetchResponse.json(200, {'meetings': meetings});
          return _page(request.url.queryParameters);
        }
        if (path == 'meet/kinds') {
          if (request.method == 'PUT') {
            if (failKinds) return FetchResponse.json(503, {'error': 'The service is busy.'});
            final body = jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
            kindsSent.add(body);
            for (final MapEntry(:key, :value) in body.entries) {
              if (value is bool) kinds[key] = value;
            }
          }
          return FetchResponse.json(200, kinds);
        }
        if (path.startsWith('meet/series/') && request.method == 'DELETE') {
          final id = Uri.decodeComponent(path.substring('meet/series/'.length));
          final at = series.indexWhere((s) => s['id'] == id);
          if (!paging || at < 0) return FetchResponse.json(404, {'error': 'No recurring meeting by that id.'});
          series.removeAt(at);
          final changed = <Map<String, Object?>>[];
          for (final (i, m) in meetings.indexed.toList()) {
            if (m['series'] != id || (m['endsAt'] as int) <= now()) continue;
            final next = switch (m['state']) { 'booked' => 'cancelled', 'joining' || 'in_call' => 'leave', _ => null };
            if (next == null) continue;
            meetings[i] = {...m, 'state': next, 'detail': 'You asked Ghost to stop joining this meeting.'};
            changed.add({...meetings[i]}..remove('series'));
          }
          return FetchResponse.json(200, {'series': {'id': id, 'stopped': true}, 'meetings': changed});
        }
        if (path == 'meet' && request.method == 'POST') {
          final body = jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
          booked = body;
          final meeting = {'id': 'now${meetings.length}', 'title': body['title'], 'url': body['url'], 'startsAt': 1792159200000, 'endsAt': 1792166400000, 'state': 'booked', 'detail': null};
          meetings.add(meeting);
          return FetchResponse.json(200, {'meeting': meeting});
        }
        if (path == 'meet/takes' && request.method == 'GET') {
          return FetchResponse.json(200, {
            'takes': [
              for (final MapEntry(:key, :value) in takes.entries) {'id': key, 'meeting': value.meeting, 'size': value.sealed.length, 'at': value.at, 'wrapped': value.wrapped},
            ],
          });
        }
        if (path.startsWith('meet/takes/')) {
          final id = Uri.decodeComponent(path.substring('meet/takes/'.length));
          final take = takes[id];
          if (request.method == 'DELETE') {
            takes.remove(id);
            return FetchResponse(204);
          }
          if (take == null) return FetchResponse.json(404, {'error': 'No recording by that id. Another of your devices may have taken it.'});
          return FetchResponse(200, headers: {'content-type': 'application/octet-stream', 'x-glyph-wrapped': take.wrapped, 'x-glyph-meeting': take.meeting}, bytes: take.sealed);
        }
        // A meeting's live captions kept, sealed (server/src/meet/live.rs): the frames after `after`.
        if (path.startsWith('meet/') && path.endsWith('/live') && request.method == 'GET') {
          final id = Uri.decodeComponent(path.substring('meet/'.length, path.length - '/live'.length));
          final after = int.tryParse(request.url.queryParameters['after'] ?? '') ?? 0;
          final frames = live[id];
          if (frames == null) return FetchResponse.json(200, {'live': false, 'first': null, 'frames': <Object?>[]});
          return FetchResponse.json(200, {
            'live': !liveOver.contains(id),
            'first': frames.isEmpty ? 1 : frames.first['seq'],
            'frames': [for (final f in frames) if ((f['seq'] as int) > after) f],
          });
        }
        if (path.startsWith('meet/') && request.method == 'DELETE') {
          final id = Uri.decodeComponent(path.substring('meet/'.length));
          final at = meetings.indexWhere((m) => m['id'] == id);
          if (at < 0) return FetchResponse.json(404, {'error': 'No meeting by that id.'});
          final next = {...meetings[at], 'state': meetings[at]['state'] == 'booked' ? 'skipped' : 'leave'};
          meetings[at] = next;
          return FetchResponse.json(200, {'meeting': next});
        }
        return FetchResponse.json(404, {'error': 'No route ${request.method} $path'});
      };

  /// The history's order: the latest ended first, then the larger id.
  static int _latestFirst(Map<String, Object?> a, Map<String, Object?> b) {
    final ends = (b['endsAt'] as int).compareTo(a['endsAt'] as int);
    return ends != 0 ? ends : (b['id'] as String).compareTo(a['id'] as String);
  }

  FetchResponse _page(Map<String, String> query) {
    final limit = int.tryParse(query['limit'] ?? '') ?? 20;
    final at = now();
    final over = [for (final m in meetings) if ((m['endsAt'] as int) <= at) m]..sort(_latestFirst);
    final before = query['before'];
    var from = 0;
    if (before != null) {
      if (failMore) return FetchResponse.json(503, {'error': 'The service is busy.'});
      final (end, id) = (int.parse(before.split(':').first), before.split(':').last);
      from = over.indexWhere((m) => (m['endsAt'] as int) < end || ((m['endsAt'] as int) == end && (m['id'] as String).compareTo(id) < 0));
      if (from < 0) from = over.length;
    }
    final page = over.skip(from).take(limit).toList();
    final more = from + limit < over.length;
    final next = more ? '${page.last['endsAt']}:${page.last['id']}' : null;
    if (before != null) return FetchResponse.json(200, {'meetings': page, 'next': next});
    final ahead = [for (final m in meetings) if ((m['endsAt'] as int) > at) m]..sort((a, b) => (a['startsAt'] as int).compareTo(b['startsAt'] as int));
    return FetchResponse.json(200, {'meetings': [...ahead, ...page], 'series': series, 'next': next});
  }
}
