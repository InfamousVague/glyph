/// A note's properties - its front matter read as named values, the way Notion shows a page's - and a ticket's
/// vocabulary (Matt asked what Notion- and Jira-like features custom Markdown could give the app, "like tickets and
/// such", and picked tickets as notes: tauri/docs/DESIGN.md §156). A port of `src/app/core/properties.ts`, whole.
///
///     ---
///     type: ticket
///     id: GHO-12
///     status: In progress
///     assignee: Sam
///     priority: high
///     due: 2026-10-03
///     estimate: 3
///     blocked-by: "[[GHO-9]]"
///     ---
///
/// A ticket is a note with `type: ticket`, and its fields are front matter, which Obsidian shows as properties,
/// Jekyll and Hugo read, and GitHub draws as a table over the file: nothing about it needs the app. A notebook
/// (book.dart) gives its tickets a key, `key: GHO`, and each new one the next number, `GHO-13`, as Jira does;
/// `[[GHO-12]]` then links to it by that key. The notebook may name its own workflow, `statuses: [Ideas, Building,
/// Live]`.
///
/// Where the front matter ends is front_matter.dart's `frontMatterEnd`, and nothing here has a second rule for it; a
/// value's quotes come off by its `unquoted`. A list is written across, `["[[GHO-9]]", "[[GHO-10]]"]`, and read
/// either that way or with commas. A priority's names are task_fields.dart's, so a ticket and a to-do sort as one.
/// Pure, and every front matter edge is a test (test/book_core/properties_test.dart).
///
/// What differs:
/// - `withFrontMatterValue` (`core/frontMatter.ts`) is here, moved from lib/notes/note_templates.dart where the
///   first port that needed it put it; that file re-exports it. front_matter.dart is still the reading half, since
///   lib/share/carried.dart keeps a copy of its own under the same name and the two would meet there.
/// - [parseFloat] is JavaScript's `Number.parseFloat`, which an estimate and a query's number are read with.
/// - The constants are lowerCamel: `TICKET_PROPERTIES` is [ticketProperties], `PROJECT_KEY` [projectKey], `ISSUE_KEY`
///   [issueKey]. A property's kind is a [PropertyKind], a priority its name as task_fields.dart keeps it (a string).
/// - [withProperty] takes a `String`, a `List<String>` or null, as the web's union does.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'days.dart' show isIsoDay;
import 'front_matter.dart';
import 'item_syntax.dart' show isDoneName, jsTrim;
import 'task_fields.dart' show Priority, priorityOf, priorities;

export 'item_syntax.dart' show isDoneName;

// ---- reading ------------------------------------------------------------------------------------------------------

/// One property: its key as written, its value with its quotes off, and the line of the body it is on (from 0).
@immutable
class Property {
  const Property({required this.key, required this.value, required this.line});
  final String key;
  final String value;
  final int line;

  @override
  bool operator ==(Object other) => other is Property && other.key == key && other.value == value && other.line == line;

  @override
  int get hashCode => Object.hash(key, value, line);

  @override
  String toString() => 'Property($key: $value, line $line)';
}

/// A property's line: a key at the start of the line, its colon, and its value. An indented `key:` belongs to the
/// one above it in YAML, and is not a property of the note's own.
final RegExp _propertyLine = RegExp(r'^([\w.-]+)[ \t]*:(.*)$');

/// Every property in the note's front matter, in order; none where it has no front matter.
List<Property> propertiesOf(String body) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  final found = <Property>[];
  for (var line = 1; line < end - 1; line += 1) {
    final said = _propertyLine.firstMatch(lines[line]);
    if (said != null) found.add(Property(key: said.group(1) ?? '', value: unquoted(jsTrim(said.group(2) ?? '')), line: line));
  }
  return found;
}

/// A value that is note links and nothing else, `[[GHO-9]], [[GHO-10]]`: a list with commas, never a flow list.
final RegExp _linksOnly = RegExp(r'^\[\[[^\]\n]*\]\](?:\s*,\s*\[\[[^\]\n]*\]\])*$');

/// [text] cut at its commas, but not at one inside quotes that open an item, or inside brackets.
List<String> _cutAtCommas(String text) {
  final parts = <String>[];
  var start = 0;
  var depth = 0;
  String? quote;
  for (var at = 0; at < text.length; at += 1) {
    final char = text[at];
    if (quote != null) {
      if (char == r'\' && quote == '"') {
        at += 1;
      } else if (char == quote && quote == "'" && at + 1 < text.length && text[at + 1] == "'") {
        at += 1;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if ((char == '"' || char == "'") && text.substring(start, at).trim().isEmpty) {
      quote = char;
    } else if (char == '[') {
      depth += 1;
    } else if (char == ']') {
      depth = depth > 0 ? depth - 1 : 0;
    } else if (char == ',' && depth == 0) {
      parts.add(text.substring(start, at));
      start = at + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

/// A value as a list: a flow list, `[bug, ui]`, or names with commas, `Matt, Claude`. Each item with its quotes off
/// and trimmed, empty ones dropped. A value of note links alone, `[[GHO-9]]`, is that link, not a list inside a list.
List<String> propertyList(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return const [];
  final flow = text.startsWith('[') && text.endsWith(']') && !_linksOnly.hasMatch(text);
  return _cutAtCommas(flow ? text.substring(1, text.length - 1) : text).map((item) => unquoted(item.trim()).trim()).where((item) => item.isNotEmpty).toList();
}

/// A note link as a whole item: `[[GHO-9]]`, a `#heading` or `|words` after the title not part of it.
final RegExp _linkItem = RegExp(r'^\[\[([^\]\n|#]*)(?:[#|][^\]\n]*)?\]\]$');

/// What a `blocked-by:` or `parent:` points at: the title in each note link of the list (`GHO-9` from `[[GHO-9]]`
/// and from `[[GHO-9|the login loop]]`), and an item written without brackets as it is, so a hand-written
/// `blocked-by: GHO-9` still points.
List<String> linkTargets(String? value) =>
    propertyList(value).map((item) => jsTrim(_linkItem.firstMatch(item)?.group(1) ?? item)).where((item) => item.isNotEmpty).toList();

// ---- writing ------------------------------------------------------------------------------------------------------

/// The body with front matter [key] set to [value] as it is written (no quoting added): replaced where the key is,
/// added last where it isn't, and front matter made where there was none. A null value takes the key off, and front
/// matter that held nothing else with it. The words are untouched (`core/frontMatter.ts` `withFrontMatterValue`).
String withFrontMatterValue(String body, String key, String? value) {
  final lines = body.split('\n');
  final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:', caseSensitive: false);
  final line = value == null ? null : '$key: ${jsTrim(value.replaceAll('\n', ' '))}';
  final end = frontMatterEnd(lines);
  if (end == 0) return line != null ? '---\n$line\n---\n$body' : body;
  final keys = lines.sublist(1, end - 1);
  final at = keys.indexWhere(pattern.hasMatch);
  if (at >= 0) {
    if (line != null) {
      keys[at] = line;
    } else {
      keys.removeAt(at);
    }
  } else if (line != null) {
    keys.add(line);
  }
  final rest = lines.sublist(end);
  if (keys.isEmpty) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

final RegExp _propertyKey = RegExp(r'^[\w.-]+$');

/// A key front matter can hold, as front_matter.dart reads a key's line: letters, digits, `_`, `.` and `-`.
bool isPropertyKey(String key) => _propertyKey.hasMatch(key);

/// What YAML would take for something other than the words: spaces at either end; a sign that opens something else
/// (`[` a list or a note link, `{` a map, `#` a comment, `@` and a backtick reserved, a quote, `&`, `*`, `!`, `|`,
/// `>`, `%`, `,`), or a `-`, `?` or `:` with a space after it; a colon that would end a key, `a: b`; a ` #` that
/// would start a comment.
final RegExp _misread = RegExp(r'''^\s|\s$|^[\[\]{}#&*!|>'"%@`,]|^[-?:](?:\s|$)|:(?:\s|$)|\s#''');
final RegExp _needsSingle = RegExp(r'["\\]');
final RegExp _lineBreak = RegExp(r'\s*\n\s*');
final RegExp _listSign = RegExp(r'[,\[\]{}]');

/// Quoted: in double quotes, or in single ones where the words have a double quote or a backslash, which YAML
/// escapes.
String _quoted(String value) => _needsSingle.hasMatch(value) ? "'${value.replaceAll("'", "''")}'" : '"$value"';

/// A value as front matter writes it: as it is, or quoted where YAML would misread it. One line.
String yamlValue(String value) {
  final line = value.replaceAll(_lineBreak, ' ');
  return line.isEmpty || _misread.hasMatch(line) ? _quoted(line) : line;
}

/// A list as front matter writes it, across: `[bug, ui]`, `["[[GHO-9]]", "[[GHO-10]]"]`, an item quoted where
/// needed.
String yamlList(List<String> items) {
  final written = items.map((item) {
    final line = jsTrim(item.replaceAll(_lineBreak, ' '));
    return line.isEmpty || _misread.hasMatch(line) || _listSign.hasMatch(line) ? _quoted(line) : line;
  });
  return '[${written.join(', ')}]';
}

/// The body with one property set ([withFrontMatterValue]): replaced where it is, added last where it is not, front
/// matter made where there is none. A string is written as [yamlValue] writes it, a list across as [yamlList] does,
/// and null - or a list with nothing in it - takes the property off. A key front matter cannot hold leaves the body
/// as it was. [value] is a `String`, a `List<String>` or null.
String withProperty(String body, String key, Object? value) {
  if (!isPropertyKey(key)) return body;
  if (value == null) return withFrontMatterValue(body, key, null);
  if (value is String) return withFrontMatterValue(body, key, yamlValue(value));
  final items = (value as List).cast<String>().map(jsTrim).where((item) => item.isNotEmpty).toList();
  return withFrontMatterValue(body, key, items.isNotEmpty ? yamlList(items) : null);
}

// ---- tickets ------------------------------------------------------------------------------------------------------

/// What a property holds, for a panel to pick it with and a query to compare it by (`PropertyKind`).
enum PropertyKind { text, id, status, person, priority, date, number, link, links, list }

/// One of a ticket's properties (`TicketProperty`).
@immutable
class TicketProperty {
  const TicketProperty({required this.key, required this.kind, required this.label});
  final String key;
  final PropertyKind kind;

  /// How a panel names it.
  final String label;
}

/// A ticket's properties, in the order a new ticket writes them and a panel shows them (`TICKET_PROPERTIES`).
const List<TicketProperty> ticketProperties = [
  TicketProperty(key: 'type', kind: PropertyKind.text, label: 'Type'),
  TicketProperty(key: 'id', kind: PropertyKind.id, label: 'ID'),
  TicketProperty(key: 'status', kind: PropertyKind.status, label: 'Status'),
  TicketProperty(key: 'assignee', kind: PropertyKind.person, label: 'Assignee'),
  TicketProperty(key: 'priority', kind: PropertyKind.priority, label: 'Priority'),
  TicketProperty(key: 'due', kind: PropertyKind.date, label: 'Due'),
  TicketProperty(key: 'start', kind: PropertyKind.date, label: 'Start'),
  TicketProperty(key: 'estimate', kind: PropertyKind.number, label: 'Estimate'),
  TicketProperty(key: 'blocked-by', kind: PropertyKind.links, label: 'Blocked by'),
  TicketProperty(key: 'parent', kind: PropertyKind.link, label: 'Parent'),
  TicketProperty(key: 'labels', kind: PropertyKind.list, label: 'Labels'),
  // The port's own (Matt, 2026-10-31: "`labels: [bug, ui]` and `component: Waitlist` in front matter"): words, as any
  // other key's, with a row of their own in the panel and a name a query's column says.
  TicketProperty(key: 'component', kind: PropertyKind.text, label: 'Component'),
  // The port's own (Matt, 2026-10-31; lib/core/planning): the cycle a ticket is planned in, a name or a cycle note,
  // and the milestone it is for.
  TicketProperty(key: 'cycle', kind: PropertyKind.link, label: 'Cycle'),
  TicketProperty(key: 'milestone', kind: PropertyKind.link, label: 'Milestone'),
];

/// What a property holds by its key, any case: a ticket's own kind, and `text` for any other.
PropertyKind propertyKind(String key) {
  final clean = jsTrim(key).toLowerCase();
  for (final property in ticketProperties) {
    if (property.key == clean) return property.kind;
  }
  return PropertyKind.text;
}

/// The `type:` that makes a note a ticket (`TICKET_TYPE`).
const String ticketType = 'ticket';

/// The `type:`s a ticket may have: a ticket's, and an epic's, which is a ticket that others are under (Matt,
/// 2026-10-31; lib/core/planning/planning.dart). The port's own.
const Set<String> ticketTypes = {ticketType, 'epic'};

/// Whether a `type:` makes a note a ticket, in any case.
bool isTicketType(String? type) => ticketTypes.contains(type?.trim().toLowerCase());

/// Whether a note is a ticket: its front matter says `type: ticket` (or `type: epic`), in any case.
bool isTicket(String body) => isTicketType(frontMatterValue(body, 'type'));

// ---- statuses -----------------------------------------------------------------------------------------------------

/// The workflow a ticket moves through when its notebook names none: Jira's, with a backlog before it
/// (`DEFAULT_STATUSES`).
const List<String> defaultStatuses = ['Backlog', 'To do', 'In progress', 'In review', 'Done'];

/// A notebook's own workflow, its `statuses:` list, each once; the default where it names none or there is no notebook.
List<String> statusesOf(String? notebook) {
  final seen = <String>{};
  final own = propertyList(notebook == null || notebook.isEmpty ? null : frontMatterValue(notebook, 'statuses')).where((status) => seen.add(status.toLowerCase())).toList();
  return own.isNotEmpty ? own : [...defaultStatuses];
}

/// Where a status stands, as Jira groups them: not started, under way, or finished with (`StatusCategory`).
enum StatusCategory { todo, doing, done }

/// A status as its words are compared: lower case, no apostrophes, a space between words. "Won't do" is "wont do".
String _statusWords(String status) => status.toLowerCase().replaceAll(_apostrophes, '').replaceAll(_notWords, ' ').trim();

final RegExp _apostrophes = RegExp("['’]");
final RegExp _notWords = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

const Set<String> _done = {
  'done', 'closed', 'resolved', 'complete', 'completed', 'finished', 'shipped', 'released', 'merged', 'fixed', 'cancelled', 'canceled', 'duplicate', 'rejected',
  'declined', 'abandoned', 'obsolete', 'archived', 'wont do', 'wont fix', //
};
const Set<String> _todo = {'backlog', 'to do', 'todo', 'open', 'new', 'ready', 'planned', 'triage', 'icebox', 'inbox', 'next', 'later', 'not started'};
const Set<String> _doing = {'doing', 'review', 'reviewing', 'testing', 'qa', 'started', 'active', 'blocked', 'wip', 'ongoing', 'working', 'building'};

/// Where a status stands, by its words and in any case. A name none of the lists know is placed by the workflow it is
/// in, where one is given: its first status not started, its last done, any between under way.
StatusCategory statusCategory(String? status, [List<String>? workflow]) {
  final words = _statusWords(status ?? '');
  if (words.isEmpty) return StatusCategory.todo;
  if (_done.contains(words) || isDoneName(words)) return StatusCategory.done;
  if (_todo.contains(words)) return StatusCategory.todo;
  if (_doing.contains(words) || words.startsWith('in ')) return StatusCategory.doing;
  final at = workflow?.indexWhere((each) => _statusWords(each) == words) ?? -1;
  if (workflow == null || at < 0) return StatusCategory.todo;
  if (at == workflow.length - 1 && at > 0) return StatusCategory.done;
  return at == 0 ? StatusCategory.todo : StatusCategory.doing;
}

// ---- issue keys ---------------------------------------------------------------------------------------------------

/// A notebook's key: a capital letter, then two to ten capitals and digits in all, as Jira's project keys are
/// (`PROJECT_KEY`).
final RegExp projectKey = RegExp(r'^[A-Z][A-Z0-9]{1,9}$');

/// A ticket's id: its notebook's key, a dash, and a number from 1, up to six figures. `GHO-12` (`ISSUE_KEY`).
final RegExp issueKey = RegExp(r'^[A-Z][A-Z0-9]{1,9}-[1-9]\d{0,5}$');

/// [text] as an issue key, trimmed and upper-cased (`gho-12` is `GHO-12`, as a link matches in any case), or null.
String? issueKeyOf(String? text) {
  final key = jsTrim(text ?? '').toUpperCase();
  return issueKey.hasMatch(key) ? key : null;
}

/// Whether [text] is an issue key, in any case.
bool isIssueKey(String text) => issueKeyOf(text) != null;

/// An issue key's number: 12 for `GHO-12`, for sorting `GHO-9` before `GHO-10`; null for what is not a key.
int? issueNumber(String text) {
  final key = issueKeyOf(text);
  return key == null ? null : int.parse(key.substring(key.lastIndexOf('-') + 1));
}

/// A notebook's key, its `key:` upper-cased, `GHO`; null where it has none or one that is not a key (`G`, `12`).
String? notebookKey(String notebook) {
  final key = jsTrim(frontMatterValue(notebook, 'key') ?? '').toUpperCase();
  return projectKey.hasMatch(key) ? key : null;
}

/// A ticket's id, its `id:` as an issue key ([issueKeyOf]); null where it has none or it is not one.
String? ticketIdOf(String body) => issueKeyOf(frontMatterValue(body, 'id'));

/// The id the next ticket under [key] gets: one more than the highest number any of [bodies] gives that key, in an
/// `id:` or anywhere in their words (`[[GHO-12]]`, "see GHO-12"), in any case. Never the lowest free number: a
/// number a ticket had is never given to another while anything still names it, so a link to a deleted ticket never
/// finds a new one. `GHO-1` where nothing names the key yet; null for a key that is not one, or past `KEY-999999`.
/// Give it every note it must not collide with: the notebook's, the Trash's too.
String? nextIssueId(String key, Iterable<String> bodies) {
  final prefix = jsTrim(key).toUpperCase();
  if (!projectKey.hasMatch(prefix)) return null;
  final named = RegExp('(?<![A-Za-z0-9_])$prefix-([1-9]\\d{0,5})(?!\\d)', caseSensitive: false);
  var highest = 0;
  for (final body in bodies) {
    for (final found in named.allMatches(body)) {
      highest = math.max(highest, int.parse(found.group(1)!));
    }
  }
  return highest >= 999999 ? null : '$prefix-${highest + 1}';
}

// ---- a ticket, read -----------------------------------------------------------------------------------------------

final RegExp _float = RegExp(r'^[\s\uFEFF\xA0]*([+-]?(?:Infinity|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))');

/// The number [text] starts with, as JavaScript's `Number.parseFloat` reads it: 2.5 for `2.5 days`; null where it
/// starts with none (the web's `NaN`).
double? parseFloat(String text) {
  final found = _float.firstMatch(text)?.group(1);
  if (found == null) return null;
  if (found.endsWith('Infinity')) return found.startsWith('-') ? double.negativeInfinity : double.infinity;
  return double.tryParse(found.endsWith('.') ? '${found}0' : found);
}

/// A ticket's properties, read: what a panel shows, a board lays out and a query sorts (`Ticket`).
@immutable
class Ticket {
  const Ticket({
    required this.id,
    required this.status,
    required this.category,
    required this.assignee,
    this.priority,
    this.due,
    this.start,
    this.estimate,
    this.blockedBy = const [],
    this.parent,
    this.labels = const [],
    this.epic = false,
  });
  final String? id;

  /// As written; null where it has none.
  final String? status;

  /// Where the status stands ([statusCategory]), in the workflow given.
  final StatusCategory category;

  /// As written, without an at sign.
  final String? assignee;

  /// A priority's name (task_fields.dart `priorities`), or null.
  final String? priority;

  /// A day (days.dart), or null where it is none or not one.
  final String? due;
  final String? start;

  /// The number it starts with: 3 for `3`, 2.5 for `2.5 days`.
  final double? estimate;

  /// What it waits on ([linkTargets]): `GHO-9`.
  final List<String> blockedBy;
  final String? parent;

  /// Its labels, a `#` before one taken off.
  final List<String> labels;

  /// Whether it is an epic, `type: epic`: the port's own, which its JSON leaves out.
  final bool epic;

  /// The object the web has for it, key for key.
  Map<String, Object?> toJson() => {
        'id': id,
        'status': status,
        'category': category.name,
        'assignee': assignee,
        'priority': priority,
        'due': due,
        'start': start,
        'estimate': estimate == null ? null : (estimate == estimate!.truncateToDouble() ? estimate!.toInt() : estimate),
        'blockedBy': blockedBy,
        'parent': parent,
        'labels': labels,
      };

  @override
  bool operator ==(Object other) =>
      other is Ticket &&
      other.id == id &&
      other.status == status &&
      other.category == category &&
      other.assignee == assignee &&
      other.priority == priority &&
      other.due == due &&
      other.start == start &&
      other.estimate == estimate &&
      listEquals(other.blockedBy, blockedBy) &&
      other.parent == parent &&
      listEquals(other.labels, labels) &&
      other.epic == epic;

  @override
  int get hashCode => Object.hash(id, status, category, assignee, priority, due, start, estimate, Object.hashAll(blockedBy), parent, Object.hashAll(labels), epic);

  @override
  String toString() => 'Ticket(${toJson()})';
}

final RegExp _ats = RegExp(r'^@+');
final RegExp _hashes = RegExp(r'^#+');

/// A ticket's priority as written, which may say `urgent` (Matt, 2026-10-31: `priority: urgent|high|medium|low`):
/// Tasks' highest, one rank read either way. Anything else as task_fields.dart reads it. A note that is no ticket
/// keeps `urgent` as its words, as the web reads it.
Priority? ticketPriorityOf(String? said) => said?.trim().toLowerCase() == 'urgent' ? priorities.first : priorityOf(said);

/// A ticket's properties, or null where the note is not one. [statuses] is its notebook's workflow ([statusesOf]).
Ticket? ticketOf(String body, [List<String>? statuses]) {
  // The front matter is found once, and each property read from where it lies.
  final front = frontMatterSpan(body);
  final type = frontMatterValueIn(body, front, 'type');
  if (front.isEmpty || !isTicketType(type)) return null;
  String? said(String key) {
    final value = frontMatterValueIn(body, front, key);
    if (value == null) return null;
    final clean = jsTrim(value);
    return clean.isEmpty ? null : clean;
  }

  String? day(String key) {
    final value = said(key);
    return value != null && isIsoDay(value) ? value : null;
  }

  final status = said('status');
  final estimate = parseFloat(said('estimate') ?? '');
  final assignee = said('assignee');
  final person = assignee == null ? '' : jsTrim(assignee.replaceFirst(_ats, ''));
  // `epic: "[[Epic]]"` is read as its parent where it names none (lib/core/planning/planning.dart says why an epic's
  // tickets are its sub-tickets): one link, written `parent:`, read either way.
  final parents = linkTargets(said('parent') ?? said('epic'));
  return Ticket(
    id: issueKeyOf(frontMatterValueIn(body, front, 'id')),
    status: status,
    category: statusCategory(status, statuses),
    assignee: person.isEmpty ? null : person,
    priority: ticketPriorityOf(said('priority'))?.name,
    due: day('due'),
    start: day('start'),
    estimate: estimate != null && estimate.isFinite ? estimate : null,
    blockedBy: linkTargets(said('blocked-by')),
    parent: parents.isEmpty ? null : parents.first,
    labels: propertyList(said('labels')).map((label) => jsTrim(label.replaceFirst(_hashes, ''))).where((label) => label.isNotEmpty).toList(),
    epic: type?.trim().toLowerCase() == 'epic',
  );
}
