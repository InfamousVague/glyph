/// A linked item's task, read back from Notion: its status, its priority, when it's due, for the pill on the item
/// and the card a tap opens (lib/plugins/mark_details.dart). A port of `src/app/plugins/notion/details.ts`.
///
/// - **What a task is made of** is read from the page, not assumed: any board Ghost.md was shared works. The status
///   is the page's status property (or a "Done" checkbox), and its stage comes from the board's own status groups
///   (To-do, In progress, Complete), read once per board, so "Shipped" or "Blocked" land where the board put them.
///   The pill's facts are a priority-like select and a due-like date. The card lists every property with a value.
/// - **Reads are paced**, because Notion allows about three requests a second, and an answer stays fresh long
///   enough that scrolling a long list doesn't re-read it. The note coming back to the front reads what it shows
///   again, which is how a change made in Notion shows up.
/// - **The last answers are kept** (`glyph-notion-tasks`), so a note opened offline or before the read finishes
///   shows the status it last had, with when it was read on the card.
///
/// The pacing, the freshness and the keeping are the plugins' shared cache (lib/plugins/details_cache.dart, which
/// has the numbers), keyed by the page's id; what is Notion's is how a page is read and what can be written back.
///
/// What differs:
/// - A page and a board's schema are the JSON as read (`Map`s), where the page had interfaces over the same JSON.
/// - Days and times are written out here as `en-US` writes them ("Sep 20", "Sep 20, 2025", "3:05 PM" with the
///   narrow space Chromium puts before PM), where the page asked the browser's `toLocaleDateString`.
/// - Nothing is asked of Notion until the app is known to reach it: the page learned that as its module loaded,
///   this the first time something is wanted, or from [warmNotionDetails] (which notion.dart asks at launch).
library;

import 'dart:async';

import '../../core/short_url.dart';
import '../details_cache.dart';
import '../types.dart';
import 'client.dart';
import 'manifest.dart';

// ---- reading a page (pure) -------------------------------------------------------------------------------------

final RegExp _pageId = RegExp(r'([0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12})/?$', caseSensitive: false);

/// An address as the page's `new URL` would take it: with a scheme, or not an address.
Uri? _address(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri == null || !uri.hasScheme ? null : uri;
}

/// The page id in a Notion address: the 32 hex digits at the end of its path, dashed or not.
String? pageIdOf(String url) {
  final uri = _address(url);
  if (uri == null) return null;
  final match = _pageId.firstMatch(uri.path);
  return match?.group(1)!.replaceAll('-', '').toLowerCase();
}

/// A page as Notion answers one (`NotionPage`).
typedef NotionPage = Map<Object?, Object?>;

/// A board's status groups: which stage each status option is in, by option id and by name (`StageMap`).
typedef StageMap = Map<String, Stage>;

/// A board's status options by stage, in the board's order: what "Mark done" and "Reopen" set (`StageOptions`).
typedef StageOptions = Map<Stage, List<String>>;

/// A page's or a schema's properties, in the board's order: each name with its value.
List<(String, Map<Object?, Object?>)> _properties(Map<Object?, Object?> of) {
  final properties = of['properties'];
  return [
    if (properties is Map)
      for (final MapEntry(:key, :value) in properties.entries)
        if (key is String && value is Map) (key, value),
  ];
}

Map<Object?, Object?>? _map(Object? raw) => raw is Map ? raw : null;
String? _text(Object? raw) => raw is String ? raw : null;

/// Every status option of a board's schema with its stage, group by group in the board's order.
Iterable<({String id, String? name, Stage stage})> _statusOptions(Map<Object?, Object?> schema) sync* {
  for (final (_, property) in _properties(schema)) {
    final status = _map(property['status']);
    if (property['type'] != 'status' || status == null) continue;
    final options = status['options'];
    final names = {
      if (options is List)
        for (final option in options)
          if (option is Map && option['id'] is String && option['name'] is String) option['id'] as String: option['name'] as String,
    };
    final groups = status['groups'];
    if (groups is! List) continue;
    for (final group in groups) {
      if (group is! Map) continue;
      final stage = _stageOfGroup(_text(group['name']) ?? '');
      final ids = group['option_ids'];
      if (ids is! List) continue;
      for (final id in ids) {
        if (id is String) yield (id: id, name: names[id], stage: stage);
      }
    }
  }
}

/// Each stage's status options, in the board's order.
StageOptions _stageOptionsOf(Map<Object?, Object?> schema) {
  final options = <Stage, List<String>>{Stage.todo: [], Stage.doing: [], Stage.done: []};
  for (final option in _statusOptions(schema)) {
    final name = option.name;
    if (name != null && name.isNotEmpty) options[option.stage]!.add(name);
  }
  return options;
}

final RegExp _doneBox = RegExp(r'^(done|complete|completed)$', caseSensitive: false);

typedef _Writables = ({String? title, DoneProperty? done, String? board});

/// What a page's properties are called, for changing them: its title, and what says it's done (a status or a Done
/// checkbox).
({String? title, DoneProperty? done}) _writablesOf(NotionPage page) {
  final entries = _properties(page);
  String? first(bool Function(String name, Map<Object?, Object?> value) test) {
    for (final (name, value) in entries) {
      if (test(name, value)) return name;
    }
    return null;
  }

  final status = first((_, value) => value['type'] == 'status');
  final checkbox = first((name, value) => value['type'] == 'checkbox' && _doneBox.hasMatch(name.trim()));
  return (
    title: first((_, value) => value['type'] == 'title'),
    done: status != null ? DoneProperty(status, 'status') : (checkbox != null ? DoneProperty(checkbox, 'checkbox') : null),
  );
}

/// Where a Notion address points, for links that aren't marks: notion.so, notion.site or app.notion.com, with a
/// page id.
bool _isNotionPageUrl(String url) {
  final uri = _address(url);
  if (uri == null) return false;
  final name = uri.host.toLowerCase();
  final notion = name == 'notion.so' || name.endsWith('.notion.so') || name.endsWith('.notion.site') || name == 'app.notion.com';
  return notion && pageIdOf(url) != null;
}

/// The stages of a board's status options, from its groups.
StageMap stagesOf(Map<Object?, Object?> schema) {
  final stages = <String, Stage>{};
  for (final option in _statusOptions(schema)) {
    stages[option.id] = option.stage;
    final name = option.name;
    if (name != null && name.isNotEmpty) stages[name.toLowerCase()] = option.stage;
  }
  return stages;
}

Stage _stageOfGroup(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('complete') || lower.contains('done')) return Stage.done;
  if (lower.contains('progress')) return Stage.doing;
  return Stage.todo;
}

final RegExp _todoName = RegExp(r'^(not started|to ?do|backlog|new|open|todo|up next|planned|triage)');
final RegExp _doneName = RegExp(r'(done|complete|shipped|closed|resolved|finished|released|merged)');

/// A stage from a status's name alone, for a board whose groups couldn't be read.
Stage guessStage(String name) {
  final lower = name.toLowerCase().trim();
  if (_todoName.hasMatch(lower)) return Stage.todo;
  if (_doneName.hasMatch(lower)) return Stage.done;
  return Stage.doing;
}

String _rich(Object? rich) => (rich is List ? [for (final r in rich) r is Map && r['plain_text'] is String ? r['plain_text'] as String : ''].join() : '').trim();

final RegExp _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');
const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// [iso] as a moment on this device: a day alone is its noon (or [dayAt]), anything else what it says.
DateTime? _moment(String iso, {String dayAt = '12:00:00'}) => _dateOnly.hasMatch(iso) ? DateTime.tryParse('${iso}T$dayAt') : DateTime.tryParse(iso)?.toLocal();

String _dayText(String iso, int now) {
  final when = _moment(iso);
  if (when == null) return iso;
  final sameYear = when.year == DateTime.fromMillisecondsSinceEpoch(now).year;
  final day = '${_months[when.month - 1]} ${when.day}${sameYear ? '' : ', ${when.year}'}';
  if (_dateOnly.hasMatch(iso)) return day;
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  return '$day, $hour:${when.minute.toString().padLeft(2, '0')} ${when.hour < 12 ? 'AM' : 'PM'}';
}

/// The names in a list of options or people, those that have one.
List<String> _names(Object? list) => [
      if (list is List)
        for (final item in list)
          if (item is Map && item['name'] is String && (item['name'] as String).isNotEmpty) item['name'] as String,
    ];

/// A number as the page prints one: a whole number without its `.0`.
String _number(num n) => n is double && n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21 ? n.toStringAsFixed(0) : '$n';

/// A property's value as a line of words, or null when it has none worth showing.
String? _valueText(Map<Object?, Object?> value, int now) {
  switch (value['type']) {
    case 'rich_text':
      final words = _rich(value['rich_text']);
      return words.isEmpty ? null : (words.length > 140 ? '${words.substring(0, 139)}…' : words);
    case 'status':
      return _text(_map(value['status'])?['name']);
    case 'select':
      return _text(_map(value['select'])?['name']);
    case 'multi_select':
      final names = _names(value['multi_select']);
      return names.isEmpty ? null : names.join(', ');
    case 'date':
      final date = _map(value['date']);
      final start = _text(date?['start']);
      if (start == null || start.isEmpty) return null;
      final end = _text(date?['end']);
      return end != null && end.isNotEmpty ? '${_dayText(start, now)} – ${_dayText(end, now)}' : _dayText(start, now);
    case 'people':
      final names = _names(value['people']);
      return names.isEmpty ? null : names.join(', ');
    case 'checkbox':
      return value['checkbox'] == true ? 'Yes' : null;
    case 'number':
      final number = value['number'];
      return number is num ? _number(number) : null;
    case 'url':
      final url = _text(value['url']);
      return url != null && url.isNotEmpty ? shortUrl(url) : null;
    case 'email':
      return _text(value['email']);
    case 'phone_number':
      return _text(value['phone_number']);
    default:
      // Formulas, rollups, relations, files, and the times Notion sets itself: noise on a small card.
      return null;
  }
}

final RegExp _prio = RegExp('prio', caseSensitive: false);
final RegExp _dueName = RegExp('due|deadline|date', caseSensitive: false);
final RegExp _afterDay = RegExp(r', .*$');

/// A page as details: its title, its status and stage, the pill's facts and the card's fields.
MarkDetails detailsOf(NotionPage page, StageMap? stages, [int? now]) {
  final at = now ?? notionNow();
  final entries = _properties(page);
  var title = '';
  for (final (_, value) in entries) {
    if (value['type'] == 'title') {
      title = _rich(value['title']);
      break;
    }
  }

  MarkStatus? status;
  Map<Object?, Object?>? chosen;
  for (final (_, value) in entries) {
    final name = _text(_map(value['status'])?['name']);
    if (value['type'] == 'status' && name != null && name.isNotEmpty) {
      chosen = _map(value['status']);
      break;
    }
  }
  if (chosen != null) {
    final label = chosen['name'] as String;
    final id = _text(chosen['id']);
    final known = stages ?? const <String, Stage>{};
    final stage = known[id ?? ''] ?? known[label.toLowerCase()] ?? guessStage(label);
    status = MarkStatus(label, stage);
  } else {
    for (final (name, value) in entries) {
      if (value['type'] == 'checkbox' && _doneBox.hasMatch(name.trim())) {
        status = value['checkbox'] == true ? const MarkStatus('Done', Stage.done) : const MarkStatus('Not done', Stage.todo);
        break;
      }
    }
  }

  final brief = <String>[];
  for (final (name, value) in entries) {
    if (_prio.hasMatch(name) && (value['type'] == 'select' || value['type'] == 'status')) {
      final priority = _valueText(value, at);
      if (priority != null && priority.isNotEmpty) brief.add(priority);
      break;
    }
  }
  for (final (name, value) in entries) {
    final start = _text(_map(value['date'])?['start']);
    if (value['type'] == 'date' && _dueName.hasMatch(name) && start != null && start.isNotEmpty) {
      final ends = _moment(start, dayAt: '23:59:59');
      final late = status?.stage != Stage.done && ends != null && ends.millisecondsSinceEpoch < at;
      brief.add('${late ? 'Overdue' : 'Due'} ${_dayText(start, at).replaceFirst(_afterDay, '')}');
      break;
    }
  }

  final fields = <MarkField>[];
  for (final (label, value) in entries) {
    if (value['type'] == 'title') continue;
    final said = _valueText(value, at);
    if (said != null) fields.add(MarkField(label, said));
  }

  final edited = _text(page['last_edited_time']);
  return MarkDetails(
    url: _text(page['url']) ?? '',
    title: title.isNotEmpty ? title : 'Untitled',
    status: status,
    brief: brief.take(2).toList(),
    fields: fields,
    editedAt: edited == null ? null : DateTime.tryParse(edited)?.millisecondsSinceEpoch,
    readAt: at,
    gone: page['archived'] == true || page['in_trash'] == true,
  );
}

// ---- the provider ----------------------------------------------------------------------------------------------

typedef _BoardStatuses = ({StageMap stages, StageOptions options});

/// Each board's statuses, by the database's id: read once, and null for a board whose schema would not read.
final Map<String, _BoardStatuses?> _boards = {};

/// Per page: its property names for writing back, and its board. Kept in memory; a read fills it.
final Map<String, _Writables> _writables = {};

/// A board's statuses by stage and by option, read once per database. Not client.dart's `boardFor`, which answers
/// the board a note sends its list to.
Future<_BoardStatuses?> _boardStatusesOf(String? databaseId) async {
  if (databaseId == null || databaseId.isEmpty) return null;
  if (_boards.containsKey(databaseId)) return _boards[databaseId];
  Object? schema;
  try {
    schema = await notionRequest('GET', 'databases/$databaseId');
  } catch (_) {
    schema = null;
  }
  final board = schema is Map ? (stages: stagesOf(schema), options: _stageOptionsOf(schema)) : null;
  _boards[databaseId] = board;
  return board;
}

/// Reads a task's page, and its board's statuses the first time the board is met; keeps what can be written back.
Future<MarkDetails> _read(String id, String url) async {
  final answer = await notionRequest('GET', 'pages/$id');
  final NotionPage page = answer is Map ? answer : const {};
  final parent = _map(page['parent']);
  final databaseId = parent?['type'] == 'database_id' ? _text(parent?['database_id']) : null;
  final board = await _boardStatusesOf(databaseId);
  final write = _writablesOf(page);
  _writables[id] = (title: write.title, done: write.done, board: databaseId);
  final details = detailsOf(page, board?.stages);
  final own = _text(page['url']);
  return own != null ? details : _at(details, url);
}

/// [details] under another address.
MarkDetails _at(MarkDetails details, String url) =>
    MarkDetails(url: url, title: details.title, status: details.status, brief: details.brief, fields: details.fields, editedAt: details.editedAt, readAt: details.readAt, gone: details.gone);

// Nothing is asked of Notion until the app is known to reach it: the answer lands a moment after the first asking.
bool _usable = false;
Future<void>? _asking;

/// Learns whether Notion can be reached, once, and tells the pills when it can. Asked at launch by notion.dart, and
/// by the first thing wanted otherwise.
Future<void> warmNotionDetails() => _asking ??= notionAvailable().then((yes) {
      _usable = yes;
      if (yes) markDetailsChanged();
    });

bool _ready() {
  if (_asking == null) unawaited(warmNotionDetails());
  return _usable;
}

final DetailsCache _tasks = DetailsCache(host: host, storageKey: 'glyph-notion-tasks', read: _read, ready: _ready, now: () => notionNow());

class _NotionDetails extends MarkDetailsProvider {
  const _NotionDetails();

  @override
  MarkEntry? peek(String url) {
    final id = pageIdOf(url);
    return id == null ? null : _tasks.peek(id);
  }

  @override
  void want(String url, {bool fresh = false}) {
    final id = pageIdOf(url);
    if (id != null) _tasks.want(id, url, fresh: fresh);
  }

  @override
  Future<void> open(String url) => host.openUrl(url);

  @override
  bool reads(String url) => _isNotionPageUrl(url);

  @override
  List<MarkAction> actions(String url, String words) {
    final id = pageIdOf(url);
    final details = id == null ? null : _tasks.details(id);
    final write = id == null ? null : _writables[id];
    if (id == null || details == null || write == null || details.gone) return const [];
    final actions = <MarkAction>[];
    if (write.done != null) {
      final done = details.status?.stage == Stage.done;
      actions.add(MarkAction(
        id: done ? 'reopen' : 'done',
        label: done ? 'Reopen in Notion' : 'Mark done in Notion',
        busyLabel: done ? 'Reopening…' : 'Marking done…',
        icon: done ? MarkActionIcon.reopen : MarkActionIcon.done,
        run: () => _setDone(id, url, !done),
      ));
    }
    final said = words.trim();
    final title = write.title;
    if (title != null && said.isNotEmpty && said != details.title.trim()) {
      actions.add(MarkAction(
        id: 'rename',
        label: 'Use these words as its title',
        busyLabel: 'Renaming…',
        icon: MarkActionIcon.rename,
        run: () async {
          await notionRequest('PATCH', 'pages/$id', {
            'properties': {title: titleValue(said)},
          });
          await _tasks.reread(id, url);
          return 'Renamed in Notion.';
        },
      ));
    }
    return actions;
  }
}

/// What Notion's item marks link to, read back (`notionDetails`).
const MarkDetailsProvider notionDetails = _NotionDetails();

/// Moves a task to the board's first done status, or back to its first to-do one (or ticks its Done box).
Future<String> _setDone(String id, String url, bool done) async {
  final write = _writables[id];
  final property = write?.done;
  if (write == null || property == null) throw const NotionFailure('This task has nothing that says it’s done.');
  final Object value;
  if (property.kind == 'checkbox') {
    value = {'checkbox': done};
  } else {
    final board = await _boardStatusesOf(write.board);
    final options = board?.options ?? const <Stage, List<String>>{};
    final todo = options[Stage.todo] ?? const <String>[];
    final names = (done ? options[Stage.done] : (todo.isNotEmpty ? todo : options[Stage.doing])) ?? const <String>[];
    if (names.isEmpty) throw const NotionFailure('Ghost.md couldn’t read this board’s statuses.');
    value = {
      'status': {'name': names.first},
    };
  }
  await notionRequest('PATCH', 'pages/$id', {
    'properties': {property.name: value},
  });
  await _tasks.reread(id, url);
  return done ? 'Marked done in Notion.' : 'Reopened in Notion.';
}

/// Forgets what was read, for signing out: another workspace's tasks aren't this one's.
void forgetTaskDetails() {
  _boards.clear();
  _writables.clear();
  _tasks.forget();
}

/// For the tests: as the page's module newly loaded, with nothing known of whether Notion can be reached.
void resetNotionDetails() {
  forgetTaskDetails();
  _usable = false;
  _asking = null;
}
