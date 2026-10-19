import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/meet/meet_api.dart';

/// A take laid out as the service lays one out before sealing it (server/src/meet.rs `pack`, `GMT1`).
Uint8List gmt1({String? title = 'Launch sync', String meeting = 'm1', int startedAt = 1792159200000, int endedAt = 1792161900000, String mime = 'audio/webm;codecs=opus', List<Map<String, Object?>> captions = const [], List<int> audio = const [1, 2, 3, 4], Map<String, Object?>? head}) {
  final lines = utf8.encode(captions.map(jsonEncode).join('\n'));
  final said = utf8.encode(jsonEncode(head ??
      {
        'v': 1,
        'meeting': meeting,
        'title': title,
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

/// The service's meeting routes in memory (docs/MEET.md, "Routes"), in front of another fetcher for the rest.
class FakeMeet {
  final List<Map<String, Object?>> meetings = [];
  final Map<String, ({String meeting, int at, String wrapped, Uint8List sealed})> takes = {};

  /// Every meeting route asked, as `METHOD path`.
  final List<String> calls = [];

  /// False: a service from before the meeting routes, which answers each "no such route".
  bool routes = true;

  /// The body a POST was sent.
  Map<String, Object?>? booked;

  Fetcher over(Fetcher rest) => (request) async {
        final path = request.url.path.replaceFirst(RegExp(r'^.*/v1/'), '');
        if (!path.startsWith('meet')) return rest(request);
        calls.add('${request.method} $path');
        if (!routes) return FetchResponse.json(404, {'error': 'no such route'});
        if (path == 'meet' && request.method == 'GET') return FetchResponse.json(200, {'meetings': meetings});
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
}
