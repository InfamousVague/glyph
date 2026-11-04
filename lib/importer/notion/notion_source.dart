/// Notion's API as the import reads it (Matt, 2026-11-04: "Add functionality in the notion plugin to import a whole
/// notion into ghost since we should have 1 to 1 functionality"; docs/NOTION_IMPORT.md): every page and database the
/// sign-in can see, each database's rows, each block's children, and the files they name.
///
/// - **Paged.** Every list Notion answers is a page of at most 100 with `has_more` and `next_cursor`, asked again
///   with `start_cursor` until it says no more: `POST search`, `POST databases/<id>/query`, and
///   `GET blocks/<id>/children`.
/// - **Paced.** Notion allows about three requests a second for an integration. [NotionReader] leaves [gap] between
///   the start of one request and the next, and answers a 429 by waiting what its `Retry-After` says (a second where
///   it says nothing, doubling) before asking again; a 500, 502, 503 or 504 and a network blip wait 1, 2, 4, 8 s. A
///   call that still fails after [tries] says why ([NotionImportFailure]).
/// - **Over a call it is handed** ([NotionCall]): in the app the Notion plugin's own (lib/plugins/notion/client.dart
///   `notionAnswer`, with the device's sign-in and its refresh), in a test a fake Notion. Files are fetched by
///   [NotionDownload], since a file's address is a signed link to Notion's storage that expires in about an hour:
///   the import fetches each one as it writes the page that names it.
library;

import 'dart:async';
import 'dart:typed_data';

/// What Notion answered: its status, its body as JSON read, and its headers by lower-cased name.
typedef NotionReply = ({int status, Object? body, Map<String, String> headers});

/// One call to Notion's API: [method] (GET or POST), [path] below `https://api.notion.com/v1/` with its query, and
/// the JSON [body] for a POST. Throws only where nothing answered (no network).
typedef NotionCall = Future<NotionReply> Function(String method, String path, [Object? body]);

/// A file's bytes, or null where they could not be fetched (gone, refused, a site the app does not reach).
typedef NotionDownload = Future<Uint8List?> Function(Uri url);

/// A call to Notion that did not work, said as the sentence a person reads.
class NotionImportFailure implements Exception {
  const NotionImportFailure(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// The most a page of Notion's lists holds.
const int notionPageSize = 100;

/// The most pages one list is followed for: 100,000 of anything.
const int notionMostPages = 1000;

/// How long apart requests start: a little over a third of a second, under Notion's three a second.
const Duration notionGap = Duration(milliseconds: 340);

/// The pages and databases the sign-in can see, each database's rows, and the blocks of each, paced and paged.
class NotionReader {
  NotionReader(this._call, {NotionDownload? download, this.gap = notionGap, this.tries = 6, Future<void> Function(Duration wait)? sleep, DateTime Function()? clock})
      : _download = download,
        _sleep = sleep ?? ((wait) => Future<void>.delayed(wait)),
        _clock = clock ?? DateTime.now;

  final NotionCall _call;
  final NotionDownload? _download;
  final Duration gap;

  /// How many times a call is asked before its failure is said.
  final int tries;
  final Future<void> Function(Duration wait) _sleep;
  final DateTime Function() _clock;
  DateTime? _last;

  /// How many requests were made, and how many were waited out after a 429: for the tests, and the report.
  int requests = 0;
  int limited = 0;

  /// Waits until [gap] has passed since the last request began.
  Future<void> _pace() async {
    final last = _last;
    if (last != null) {
      final since = _clock().difference(last);
      if (since < gap) await _sleep(gap - since);
    }
    _last = _clock();
  }

  /// [method] [path], paced, asked again after a 429, a server's passing failure or a network blip.
  Future<Object?> ask(String method, String path, [Object? body]) async {
    var backoff = const Duration(seconds: 1);
    for (var attempt = 1;; attempt += 1) {
      await _pace();
      requests += 1;
      final NotionReply reply;
      try {
        reply = await _call(method, path, body);
      } on NotionImportFailure {
        rethrow;
      } catch (failure) {
        // Nothing answered: the network, or the plugin's own sentence for it. A blip is tried again.
        if (attempt >= tries || !_passing(failure)) rethrow;
        await _sleep(backoff);
        backoff *= 2;
        continue;
      }
      final status = reply.status;
      if (status >= 200 && status < 300) return reply.body;
      if (status == 429 && attempt < tries) {
        limited += 1;
        final said = int.tryParse(reply.headers['retry-after']?.trim() ?? '');
        await _sleep(said != null && said >= 0 ? Duration(seconds: said) : backoff);
        backoff *= 2;
        continue;
      }
      if ((status == 500 || status == 502 || status == 503 || status == 504) && attempt < tries) {
        await _sleep(backoff);
        backoff *= 2;
        continue;
      }
      throw NotionImportFailure(_said(status, reply.body), status: status);
    }
  }

  static bool _passing(Object failure) {
    if (failure is TimeoutException) return true;
    final words = '$failure'.toLowerCase();
    final name = failure.runtimeType.toString();
    return name.contains('Socket') || name.contains('ClientException') || name.contains('Handshake') || name.contains('HttpException') || words.contains("couldn't be reached") || words.contains('could not be reached');
  }

  static String _said(int status, Object? body) {
    final message = body is Map && body['message'] is String ? body['message'] as String : null;
    if (status == 401) return 'Notion signed Ghost.md out. Sign in again in Settings › Notion.';
    if (status == 429) return 'Notion kept asking Ghost.md to slow down. Try again in a few minutes; what came in stays.';
    return message == null ? 'Notion answered $status.' : 'Notion said: $message';
  }

  /// Every row of a list, page after page: [path] asked with [method], a POST's cursor in its body and a GET's in
  /// its query.
  Future<List<Map<String, Object?>>> _all(String method, String path, [Map<String, Object?>? body]) async {
    final rows = <Map<String, Object?>>[];
    String? cursor;
    for (var page = 0; page < notionMostPages; page += 1) {
      final Object? answer;
      if (method == 'GET') {
        final join = path.contains('?') ? '&' : '?';
        answer = await ask('GET', '$path${join}page_size=$notionPageSize${cursor == null ? '' : '&start_cursor=${Uri.encodeQueryComponent(cursor)}'}');
      } else {
        answer = await ask(method, path, {...?body, 'page_size': notionPageSize, 'start_cursor': ?cursor});
      }
      if (answer is! Map) break;
      final results = answer['results'];
      if (results is List) {
        for (final row in results) {
          if (row is Map) rows.add(row.cast<String, Object?>());
        }
      }
      final next = answer['next_cursor'];
      if (answer['has_more'] != true || next is! String || next.isEmpty) break;
      cursor = next;
    }
    return rows;
  }

  /// Every page and database the sign-in can see, as Notion's search lists them (oldest edited first, so a page
  /// edited during the import is not missed between two pages of the list).
  Future<List<Map<String, Object?>>> search() => _all('POST', 'search', {
        'sort': {'direction': 'ascending', 'timestamp': 'last_edited_time'},
      });

  /// A database's rows, in the order Notion lists them.
  Future<List<Map<String, Object?>>> rows(String databaseId) => _all('POST', 'databases/$databaseId/query');

  /// A block's (or a page's) children, one level.
  Future<List<Map<String, Object?>>> children(String blockId) => _all('GET', 'blocks/$blockId/children');

  /// A block's children and theirs, as deep as they go, each child's own under `children`. A sub-page and a database
  /// inside the page are not gone into: they are pages of their own.
  Future<List<Map<String, Object?>>> tree(String blockId, {int depth = 0}) async {
    final found = await children(blockId);
    for (final block in found) {
      final type = block['type'];
      if (block['has_children'] == true && type != 'child_page' && type != 'child_database' && depth < 30) {
        block['children'] = await tree('${block['id']}', depth: depth + 1);
      }
    }
    return found;
  }

  /// A file's bytes, fetched now, before its link expires; null where it could not be.
  Future<Uint8List?> download(Uri url) async {
    final fetch = _download;
    if (fetch == null) return null;
    try {
      return await fetch(url);
    } catch (_) {
      return null;
    }
  }
}

/// A Notion id as one is compared: its 32 hex digits, lower case, without the dashes. Null for anything else.
String? notionIdOf(String? said) {
  if (said == null) return null;
  final hex = said.replaceAll('-', '').toLowerCase();
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(hex) ? hex : null;
}

final RegExp _idInLink = RegExp(r'([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?![0-9a-f])', caseSensitive: false);

/// The page a link points at, where it is a link into Notion (`/2f3c…`, `https://www.notion.so/Plan-2f3c…`,
/// `notion.so/team/2f3c…?pvs=4`): its id as [notionIdOf] gives it. Null for a link anywhere else. A link to a block
/// inside a page (`#` and the block's id) is the page's.
String? notionLinkId(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final inside = host.isEmpty ? url.startsWith('/') : (host == 'notion.so' || host.endsWith('.notion.so') || host == 'notion.site' || host.endsWith('.notion.site'));
  if (!inside) return null;
  final match = _idInLink.firstMatch(uri.path);
  return match == null ? null : notionIdOf(match.group(1));
}
