import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';

export 'package:ghost_md/account/api.dart' show FetchRequest, FetchResponse;

/// The phone a Notion test stands on: its memory, its secure store, a network that answers what the test recorded
/// and writes down every request, and a browser that writes down what it was asked to open. Nothing here reaches a
/// real service: a request no test answered throws.
class Phone {
  Phone({this.generation = 12, String? account}) {
    if (account != null) secrets.held[accountSecret] = account;
  }

  /// The binary's native generation, as the page's `ota_status` said it.
  int generation;
  final MemoryStored kept = MemoryStored();
  final CountingSecrets secrets = CountingSecrets();
  final List<FetchRequest> requests = [];
  final List<String> opened = [];

  /// What the network answers, by the request. Replaced per test where it matters.
  Future<FetchResponse> Function(FetchRequest request) answer = (request) => throw StateError('no answer recorded for ${request.method} ${request.url}');

  /// Whether the browser opens anything; false throws, as an opener with nothing to open in does.
  String? cannotOpen;

  PluginGround get ground => PluginGround(
        stored: () => kept,
        secrets: secrets,
        fetch: (request) {
          requests.add(request);
          return answer(request);
        },
        open: (url) async {
          if (cannotOpen != null) throw Exception(cannotOpen);
          opened.add(url);
        },
        hasNativeGeneration: (wanted) async => generation >= wanted,
      );

  /// Stands every plugin's host on this phone, with the page's modules as newly loaded.
  void use() {
    usePluginGround(ground);
    resetNotionClient();
    resetNotionDetails();
    forgetSent();
  }

  /// What is kept under a storage key, as JSON read; null when nothing is.
  Object? storedJson(String key) {
    final text = kept.getItem(key);
    return text == null ? null : jsonDecode(text);
  }

  /// The requests made of Notion itself, as the page's tests saw `notion_request`'s arguments: the method, the path
  /// below /v1/, and the body as JSON read (null for none).
  List<Map<String, Object?>> get asked => [
        for (final request in requests)
          if (request.url.host == 'api.notion.com') {'method': request.method, 'path': request.url.path.replaceFirst('/v1/', ''), 'body': request.body == null ? null : jsonDecode(request.text)},
      ];
}

/// A secure store in memory that counts what is read of it.
class CountingSecrets extends MemorySecureStore {
  int reads = 0;

  /// While set, a read waits for it: a store that has not answered yet.
  Future<void>? hold;

  @override
  Future<String?> read(String name) async {
    reads += 1;
    if (hold != null) await hold;
    return super.read(name);
  }
}

/// An account as glyph-api's claim spells one, kept.
String accountJson({String token = 'secret_x', String? refresh, String? workspace = 'Studio'}) => jsonEncode({'accessToken': token, 'refreshToken': refresh, 'botId': 'b', 'workspaceId': 'w', 'workspaceName': workspace, 'workspaceIcon': null});

/// A JSON answer, as a service writes one; with no body, an empty one.
FetchResponse json(int status, [Object? body]) => body == null ? FetchResponse(status) : FetchResponse.json(status, body);

/// A database as Notion's search lists one.
Map<String, Object?> database(String id, String title, {Map<String, Object?> properties = const {'Name': {'type': 'title'}}}) => {
      'object': 'database',
      'id': id,
      'url': 'https://notion.so/$id',
      'title': [
        {'plain_text': title},
      ],
      'properties': properties,
    };

/// What the web page measured for [name] (tool notes in reference_test.dart): each named thing's rectangles.
class Measured {
  Measured(String plugin, String name) : _things = (jsonDecode(File('test/plugins/$plugin/fixtures/$name.json').readAsStringSync()) as Map).cast<String, Object?>();
  final Map<String, Object?> _things;

  List<Map<String, Object?>> all(String thing) => [for (final e in _things[thing]! as List) (e as Map).cast<String, Object?>()];

  /// The [index]th [thing]'s rectangle on the page.
  Rect rect(String thing, [int index = 0]) {
    final e = all(thing)[index];
    return Rect.fromLTWH((e['x']! as num).toDouble(), (e['y']! as num).toDouble(), (e['w']! as num).toDouble(), (e['h']! as num).toDouble());
  }

  String text(String thing, [int index = 0]) => all(thing)[index]['text']! as String;
  int count(String thing) => all(thing).length;
}

/// Collects what is off the page's measure by more than half a pixel, so a run says all of it at once.
class Held {
  final List<String> off = [];

  /// The whole rectangle.
  void rect(String what, Rect got, Rect want, {double by = 0.5}) {
    if ((got.left - want.left).abs() > by || (got.top - want.top).abs() > by || (got.width - want.width).abs() > by || (got.height - want.height).abs() > by) {
      off.add('$what: ${_r(got)} against the page\'s ${_r(want)}');
    }
  }

  /// Its sides, its top and its foot, each by itself: for a row under a hairline, which the settings kit draws
  /// beside the row where the page has it inside the row's own height.
  void span(String what, Rect got, Rect want, {double by = 0.5}) {
    if ((got.left - want.left).abs() > 0.5 || (got.right - want.right).abs() > 0.5 || (got.top - want.top).abs() > by || (got.bottom - want.bottom).abs() > by) {
      off.add('$what: ${_r(got)} against the page\'s ${_r(want)}');
    }
  }

  /// Where it starts and how tall it is: for text, whose box on the page is as wide as its column.
  void block(String what, Rect got, Rect want, {double by = 0.5, double indent = 0}) {
    if ((got.left - want.left - indent).abs() > by || (got.top - want.top).abs() > by || (got.height - want.height).abs() > by) {
      off.add('$what: ${_r(got)} against the page\'s ${_r(want)}${indent == 0 ? '' : ' (indented $indent)'}');
    }
  }

  static String _r(Rect r) => 'x${r.left.toStringAsFixed(2)} y${r.top.toStringAsFixed(2)} w${r.width.toStringAsFixed(2)} h${r.height.toStringAsFixed(2)}';
}
