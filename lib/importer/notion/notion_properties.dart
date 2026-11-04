/// A Notion database row's properties as its note's front matter, and a database as its notebook's index
/// (docs/NOTION_IMPORT.md). Every key in the form the queries read (tauri/docs/QUERIES.md, "Fields": lower case, a
/// space a dash, so `Due Date` is `due-date`), every value plain YAML another app reads.
///
/// | Notion | Front matter |
/// | --- | --- |
/// | title | the note's `title:` and its heading, not repeated |
/// | text | the words, Markdown marks and all |
/// | number, checkbox | `3.5`, `true` |
/// | select, status | the option's name |
/// | multi-select | a list written across; the first one (or one called Tags) is the note's `tags:` |
/// | date | its day; `-end` its last day, `-at` the moment where it has a time |
/// | person, created by, edited by | the names, a list |
/// | relation | the rows' `[[links]]`, quoted |
/// | url, email, phone | as written |
/// | files | the files kept, a list of their links |
/// | formula, rollup | their value as Notion worked it out at the import, plainly |
/// | unique id | `TASK-12` |
/// | created, last edited time | the note's own dates |
/// | button | left out |
library;

import '../import_paths.dart' show cleanStem;
import 'notion_markdown.dart';

/// The keys the library or the page keeps for itself, which a property never writes over: a property of that name
/// is written as `notion-<name>`.
const Set<String> notionReservedKeys = {
  'id', 'created', 'updated', 'source', 'pinned', 'archived', 'trashed', 'recording-ms', 'title', 'book', 'journal', 'banner', 'icon', 'type', 'order', 'statuses',
  'notion-id', 'notion-url', 'notion-edited', 'tags', //
};

/// A property's name as a key: lower case, every run of anything but a letter, a digit or a dash one dash.
String propertyKey(String name, {Set<String> taken = const {}}) {
  var key = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]+'), '-').replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (key.isEmpty) key = 'property';
  if (notionReservedKeys.contains(key)) key = 'notion-$key';
  if (!taken.contains(key)) return key;
  for (var n = 2;; n += 1) {
    if (!taken.contains('$key-$n')) return '$key-$n';
  }
}

final RegExp _plainValue = RegExp(r'''^[^,\[\]{}#&*!|>'"%@`:\n]+$''');
final RegExp _numberish = RegExp(r'^(-?\d+(\.\d+)?|true|false|yes|no|null|~)$', caseSensitive: false);

/// [text] as a YAML scalar: as written where nothing in it would be misread, else in double quotes.
String yamlScalar(String text) {
  final clean = text.replaceAll('\r', '').replaceAll('\n', ' ');
  if (clean.isNotEmpty && clean.trim() == clean && _plainValue.hasMatch(clean) && !_numberish.hasMatch(clean) && !clean.startsWith('-') && !clean.startsWith('?')) return clean;
  return '"${clean.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// A list written across, each item a [yamlScalar]: `[Design, "Q&A"]`.
String yamlList(Iterable<String> items) => '[${items.map(yamlScalar).join(', ')}]';

/// A tag as a note's tags hold one: no spaces (a dash for each), no `#`.
String notionTag(String name) => name.trim().replaceAll('#', '').replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[,\[\]{}]'), '');

/// What a property is, as its value is written.
typedef NotionProperty = ({String name, String key, String type});

/// The properties of a database's schema, in Notion's order, each with its key; the title property first and
/// keyless.
List<NotionProperty> schemaOf(Map<String, Object?> database) {
  final properties = database['properties'];
  if (properties is! Map) return const [];
  final taken = <String>{};
  final out = <NotionProperty>[];
  String? tags;
  // The first multi-select (or one called Tags) is the note's tags.
  for (final MapEntry(:key, :value) in properties.entries) {
    if (value is Map && value['type'] == 'multi_select' && (tags == null || '$key'.toLowerCase() == 'tags')) tags = '$key';
  }
  for (final MapEntry(:key, :value) in properties.entries) {
    if (value is! Map) continue;
    final type = '${value['type']}';
    if (type == 'title') {
      out.insert(0, (name: '$key', key: 'title', type: type));
      continue;
    }
    if ('$key' == tags) {
      out.add((name: '$key', key: 'tags', type: type));
      taken.add('tags');
      continue;
    }
    final made = propertyKey('$key', taken: taken);
    taken.add(made);
    out.add((name: '$key', key: made, type: type));
  }
  return out;
}

/// The schema a row's own properties give, where its database is not among what was shared (a row found alone).
List<NotionProperty> schemaOfRow(Map<String, Object?> page) => schemaOf({'properties': page['properties']});

/// The day an ISO date or moment starts with.
String _day(String said) => said.length >= 10 ? said.substring(0, 10) : said;

/// What a value written for one property says, or null for nothing.
typedef _Written = ({String? value, List<String> extra});

/// A row's properties as front matter lines, in the schema's order: each `key: value`, nothing for a property that
/// says nothing. [files] keeps a file a `files` property names and answers its link.
Future<List<String>> propertyLines(Map<String, Object?> page, List<NotionProperty> schema, NotionWriting writing, {Future<String?> Function(String url, String name)? files}) async {
  final values = page['properties'] is Map ? (page['properties'] as Map).cast<Object?, Object?>() : const <Object?, Object?>{};
  final lines = <String>[];
  for (final property in schema) {
    if (property.type == 'title' || property.type == 'created_time' || property.type == 'last_edited_time' || property.type == 'button') continue;
    final raw = values[property.name];
    if (raw is! Map) continue;
    final written = await _value(raw.cast<Object?, Object?>(), property, writing, files);
    if (written.value != null) lines.add('${property.key}: ${written.value}');
    lines.addAll(written.extra);
  }
  return lines;
}

String _names(Object? people) => yamlList([
      if (people is List)
        for (final person in people)
          if (person is Map && (person['name'] is String || person['id'] is String)) person['name'] is String && (person['name'] as String).isNotEmpty ? person['name'] as String : 'Someone',
    ]);

Future<_Written> _value(Map<Object?, Object?> raw, NotionProperty property, NotionWriting writing, Future<String?> Function(String url, String name)? files) async {
  final type = '${raw['type'] ?? property.type}';
  final said = raw[type];
  _Written one(String? value) => (value: value, extra: const []);
  switch (type) {
    case 'rich_text':
      final words = richMarkdown(said, writing, lineBreaks: false).trim();
      return one(words.isEmpty ? null : yamlScalar(words));
    case 'number':
      return one(said is num ? '$said' : null);
    case 'checkbox':
      return one(said == true ? 'true' : 'false');
    case 'select':
    case 'status':
      return one(said is Map && said['name'] is String ? yamlScalar(said['name'] as String) : null);
    case 'multi_select':
      final names = [if (said is List) for (final option in said) if (option is Map && option['name'] is String) option['name'] as String];
      if (names.isEmpty) return one(null);
      return one(property.key == 'tags' ? yamlList([for (final name in names) notionTag(name)].where((tag) => tag.isNotEmpty)) : yamlList(names));
    case 'date':
      if (said is! Map || said['start'] is! String) return one(null);
      final start = said['start'] as String, end = said['end'];
      return (
        value: _day(start),
        extra: [
          if (end is String && end.isNotEmpty) '${property.key}-end: ${_day(end)}',
          if (start.length > 10) '${property.key}-at: ${yamlScalar(start)}',
        ],
      );
    case 'people':
      return one(said is List && said.isNotEmpty ? _names(said) : null);
    case 'created_by':
    case 'last_edited_by':
      return one(said is Map ? _names([said]) : null);
    case 'relation':
      final links = <String>[];
      if (said is List) {
        for (final ref in said) {
          final id = ref is Map && ref['id'] is String ? (ref['id'] as String).replaceAll('-', '').toLowerCase() : null;
          final title = id == null ? null : writing.titleOf(id);
          if (title != null) {
            links.add('[[$title]]');
          } else {
            writing.unresolved('a related row Ghost.md wasn’t shown');
          }
        }
      }
      return one(links.isEmpty ? null : yamlList(links));
    case 'url':
    case 'email':
    case 'phone_number':
      return one(said is String && said.isNotEmpty ? yamlScalar(said) : null);
    case 'files':
      final links = <String>[];
      if (said is List) {
        for (final file in said) {
          if (file is! Map) continue;
          final kind = file['type'];
          final url = file[kind] is Map ? (file[kind] as Map)['url'] : null;
          if (url is! String) continue;
          final name = file['name'] is String ? file['name'] as String : 'file';
          final kept = kind == 'external' || files == null ? url : await files(url, name);
          if (kept != null) links.add(kept);
        }
      }
      return one(links.isEmpty ? null : yamlList(links));
    case 'formula':
      return one(said is Map ? _plainOf(said) : null);
    case 'rollup':
      if (said is! Map) return one(null);
      if (said['type'] == 'array') {
        final items = [
          if (said['array'] is List)
            for (final item in said['array'] as List)
              if (item is Map) ?_unquotedOf(item, writing),
        ];
        return one(items.isEmpty ? null : yamlList(items));
      }
      return one(_plainOf(said));
    case 'unique_id':
      if (said is! Map || said['number'] == null) return one(null);
      final prefix = said['prefix'];
      return one(yamlScalar(prefix is String && prefix.isNotEmpty ? '$prefix-${said['number']}' : '${said['number']}'));
    case 'verification':
      return one(said is Map && said['state'] is String ? yamlScalar(said['state'] as String) : null);
    default:
      return one(null);
  }
}

/// A formula's or a rollup's value as a scalar: its string, number, boolean or date.
String? _plainOf(Map<Object?, Object?> said) {
  final kind = said['type'];
  final value = said[kind];
  return switch (kind) {
    'string' => value is String && value.isNotEmpty ? yamlScalar(value) : null,
    'number' => value is num ? '$value' : null,
    'boolean' => value == true ? 'true' : 'false',
    'date' => value is Map && value['start'] is String ? _day(value['start'] as String) : null,
    _ => null,
  };
}

/// One item of a rollup's array as words.
String? _unquotedOf(Map<Object?, Object?> item, NotionWriting writing) {
  final kind = '${item['type']}';
  final value = item[kind];
  switch (kind) {
    case 'title':
    case 'rich_text':
      final words = notionPlain(value).trim();
      return words.isEmpty ? null : words;
    case 'number':
      return value is num ? '$value' : null;
    case 'select':
    case 'status':
      return value is Map && value['name'] is String ? value['name'] as String : null;
    case 'date':
      return value is Map && value['start'] is String ? _day(value['start'] as String) : null;
    case 'people':
      return value is List ? [for (final p in value) if (p is Map && p['name'] is String) p['name'] as String].join(', ') : null;
    case 'formula':
      if (value is! Map) return null;
      final plain = _plainOf(value);
      return plain?.replaceAll(RegExp(r'^"|"$'), '');
    default:
      return null;
  }
}

/// How a database's rows are shown on its index: a table always, and a board where it has a status (or, failing
/// that, a select) to group the lanes by. Notion's API does not say which views a database has, so its own view is
/// guessed from its properties.
List<String> databaseQueries(String title, List<NotionProperty> schema) {
  final shown = [
    'title',
    for (final property in schema)
      if (property.type != 'title' && property.type != 'rich_text' && property.type != 'button' && property.type != 'files' && property.type != 'created_time' && property.type != 'last_edited_time') property.key,
  ].take(7).toList();
  final lane = schema.where((p) => p.type == 'status').firstOrNull ?? schema.where((p) => p.type == 'select').firstOrNull;
  return [
    '```query\nfrom: [[$title]]\nshow: table\ncolumns: ${shown.join(', ')}\nsort: title\n```',
    if (lane != null) '```query\nfrom: [[$title]]\nshow: board\ngroup: ${lane.key}\n```',
  ];
}

/// A cleaned name for a folder made of a title, as the library cleans a file's.
String folderOfTitle(String title) => cleanStem(title);
