import 'dart:typed_data';

import 'package:ghost_md/importer/notion/notion_source.dart';

/// Notion's objects as its API spells them (version 2022-06-28), made small for the tests, and a Notion that answers
/// them: search, a database's query, a block's children, each a page at a time, and the files they name. Nothing
/// here reaches the network.

const String idA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String idB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// A 32-digit id as Notion writes one, with its dashes.
String dashed(String id) => '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';

/// An id for the [n]th thing a test makes.
String idOf(int n) => n.toRadixString(16).padLeft(32, '0');

const Map<String, Object?> plainNotes = {'bold': false, 'italic': false, 'strikethrough': false, 'underline': false, 'code': false, 'color': 'default'};

Map<String, Object?> text(String words, {bool bold = false, bool italic = false, bool strike = false, bool underline = false, bool code = false, String color = 'default', String? link}) => {
      'type': 'text',
      'text': {'content': words, 'link': link == null ? null : {'url': link}},
      'annotations': {'bold': bold, 'italic': italic, 'strikethrough': strike, 'underline': underline, 'code': code, 'color': color},
      'plain_text': words,
      'href': link,
    };

Map<String, Object?> mentionUser(String plain) => {'type': 'mention', 'mention': {'type': 'user', 'user': {'object': 'user', 'id': 'u1'}}, 'annotations': plainNotes, 'plain_text': plain, 'href': null};

Map<String, Object?> mentionPage(String id, String plain) => {'type': 'mention', 'mention': {'type': 'page', 'page': {'id': dashed(id)}}, 'annotations': plainNotes, 'plain_text': plain, 'href': 'https://www.notion.so/$id'};

Map<String, Object?> mentionDate(String start, {String? end}) => {'type': 'mention', 'mention': {'type': 'date', 'date': {'start': start, 'end': end}}, 'annotations': plainNotes, 'plain_text': start, 'href': null};

var _blocks = 0;

/// A block of [type], its words [rich], its own fields [extra], its [children] read already.
Map<String, Object?> block(String type, {String? rich, Map<String, Object?> extra = const {}, List<Map<String, Object?>>? children, String? id}) => {
      'object': 'block',
      'id': id ?? dashed('c${(++_blocks).toRadixString(16).padLeft(31, '0')}'),
      'type': type,
      'has_children': children != null && children.isNotEmpty,
      type: {if (rich != null) 'rich_text': rich.isEmpty ? [] : [text(rich)], ...extra},
      'children': ?children,
    };

Map<String, Object?> fileBlock(String type, String url, {bool external = false, String? caption}) => {
      'object': 'block',
      'id': dashed('f${(++_blocks).toRadixString(16).padLeft(31, '0')}'),
      'type': type,
      'has_children': false,
      type: {
        'type': external ? 'external' : 'file',
        if (external) 'external': {'url': url} else 'file': {'url': url, 'expiry_time': '2026-11-04T12:00:00.000Z'},
        'caption': caption == null ? [] : [text(caption)],
      },
    };

Map<String, Object?> table(List<List<String>> rows, {required bool header}) => block('table', extra: {'table_width': rows.first.length, 'has_column_header': header, 'has_row_header': false}, children: [
      for (final row in rows) block('table_row', extra: {'cells': [for (final cell in row) [text(cell)]]}),
    ]);

/// A page: its id, title, parent (`workspace`, or a page's or a database's id with [parentKind]), dates and the rest.
Map<String, Object?> page(String id, String title, {String? parent, String parentKind = 'page_id', String edited = '2026-11-01T10:00:00.000Z', String created = '2026-10-01T10:00:00.000Z', Map<String, Object?>? properties, String? titleProperty, Object? icon, Object? cover}) => {
      'object': 'page',
      'id': dashed(id),
      'created_time': created,
      'last_edited_time': edited,
      'archived': false,
      'in_trash': false,
      'icon': icon,
      'cover': cover,
      'parent': parent == null ? {'type': 'workspace', 'workspace': true} : {'type': parentKind, parentKind: dashed(parent)},
      'url': 'https://www.notion.so/${title.replaceAll(' ', '-')}-$id',
      'properties': {
        titleProperty ?? 'title': {'id': 'title', 'type': 'title', 'title': [text(title)]},
        ...?properties,
      },
    };

Map<String, Object?> database(String id, String title, {String? parent, String parentKind = 'page_id', Map<String, Object?> schema = const {}, String edited = '2026-11-01T10:00:00.000Z'}) => {
      'object': 'database',
      'id': dashed(id),
      'created_time': '2026-10-01T09:00:00.000Z',
      'last_edited_time': edited,
      'archived': false,
      'in_trash': false,
      'title': [text(title)],
      'description': [],
      'icon': {'type': 'emoji', 'emoji': '✅'},
      'cover': null,
      'parent': parent == null ? {'type': 'workspace', 'workspace': true} : {'type': parentKind, parentKind: dashed(parent)},
      'url': 'https://www.notion.so/$id',
      'is_inline': false,
      'properties': {
        'Name': {'id': 'title', 'name': 'Name', 'type': 'title', 'title': {}},
        ...schema,
      },
    };

/// A Notion in memory: what it holds, every request asked of it, a page of [pageSize] at most per answer whatever
/// was asked for, and answers to play first ([script]: a 429 with its wait, a 503).
class FakeNotion {
  FakeNotion({this.pageSize = 2});

  final int pageSize;
  final List<Map<String, Object?>> found = [];
  final Map<String, List<Map<String, Object?>>> blocks = {};
  final Map<String, List<Map<String, Object?>>> rows = {};
  final Map<String, Uint8List> files = {};
  final List<String> asked = [];
  final List<Uri> fetched = [];
  final List<NotionReply> script = [];

  void add(Map<String, Object?> json, {List<Map<String, Object?>> children = const []}) {
    found.removeWhere((each) => each['id'] == json['id']);
    found.add(json);
    blocks[notionIdOf('${json['id']}')!] = children;
  }

  void addRow(String database, Map<String, Object?> json, {List<Map<String, Object?>> children = const []}) {
    found.removeWhere((each) => each['id'] == json['id']);
    found.add(json);
    blocks[notionIdOf('${json['id']}')!] = children;
    final list = rows.putIfAbsent(database, () => []);
    list.removeWhere((each) => each['id'] == json['id']);
    list.add(json);
  }

  NotionReply _page(List<Map<String, Object?>> all, String? cursor) {
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = (from + pageSize).clamp(0, all.length);
    final more = to < all.length;
    return (status: 200, body: {'object': 'list', 'results': all.sublist(from, to), 'has_more': more, 'next_cursor': more ? '$to' : null}, headers: const <String, String>{});
  }

  Future<NotionReply> call(String method, String path, [Object? body]) async {
    asked.add('$method $path');
    if (script.isNotEmpty) return script.removeAt(0);
    final cursor = body is Map ? body['start_cursor'] as String? : Uri.parse('https://x/$path').queryParameters['start_cursor'];
    if (method == 'POST' && path == 'search') return _page(found, cursor);
    final query = RegExp(r'^databases/([^/]+)/query$').firstMatch(path);
    if (method == 'POST' && query != null) return _page(rows[notionIdOf(query.group(1))] ?? const [], cursor);
    final children = RegExp(r'^blocks/([^/?]+)/children').firstMatch(path);
    if (method == 'GET' && children != null) {
      final id = notionIdOf(children.group(1)) ?? children.group(1)!;
      final list = blocks[id] ?? _nested[id];
      if (list == null) return (status: 404, body: {'message': 'Could not find block'}, headers: const <String, String>{});
      // Each block's own children are asked for, as Notion has them: only what this level holds is answered.
      for (final each in list) {
        final under = each['children'];
        if (under is List) _nested[notionIdOf('${each['id']}')!] = [for (final b in under) (b as Map).cast<String, Object?>()];
      }
      return _page([for (final each in list) {...each}..remove('children')], cursor);
    }
    return (status: 400, body: {'message': 'no route $method $path'}, headers: const <String, String>{});
  }

  final Map<String, List<Map<String, Object?>>> _nested = {};

  Future<Uint8List?> download(Uri url) async {
    fetched.add(url);
    return files[url.toString()];
  }

  /// A reader over this Notion that never waits for real, and writes down what it would have waited.
  NotionReader reader({List<Duration>? waits}) => NotionReader(call, download: download, sleep: (wait) async => waits?.add(wait));
}

/// A PNG's first bytes, which is all the import reads of one to know it is a picture.
final Uint8List pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);
