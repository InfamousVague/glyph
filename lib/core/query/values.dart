/// What a field says on a record, and how a query compares it, sorts it and groups by it (../glyph docs/QUERIES.md).
/// A port of `src/app/core/query/values.ts`. A query's words are read in read.dart; what they mean against a note, a
/// ticket or a to-do is here.
///
/// A field is found the way the record keeps it. Every record has the built-ins: `title` (its note's), `note` (the
/// same, read better for a to-do), `notebook`, `tags`, `created`, `updated`, `kind`, `status` and `category`, where
/// its status stands (properties.dart `statusCategory`). A note has its front matter, by key, and a ticket its
/// ticket's properties read as properties.dart reads them; a to-do has `text`, `checked`, `line` and its fields as
/// task_fields.dart reads them, a `[key:: value]` by its key. Nothing is inherited: a to-do in a ticket is not the
/// ticket, so a to-do's `status` is its own, Done where it is ticked.
///
/// A value has a kind, and the kind says how it compares, so the words of a query mean what a person meant by them:
///
/// - **A priority** compares by its rank, the most urgent the greatest: `priority >= high` is high and highest. A
///   record with none sits between medium and low, as Obsidian Tasks puts it, so `priority < high` includes it.
/// - **A status** compares by its place in the workflow, so `status < Done` is every status before it.
/// - **A day** compares as its ten characters (days.dart), against `today`, `today+7` or a date.
/// - **A number** compares as a number, read as a sum reads one (sums.dart), so `$1,200 > 1000`.
/// - **A person** is the same person however they are written (task_fields.dart `samePerson`).
/// - **A list** - tags, labels, what blocks a ticket, the people on a to-do - is equal to anything it holds, so
///   `labels = ui` and `tags contains work` read alike, and a tag holds the tags inside it (`#work/clients`).
/// - **Words** are equal whatever their case and punctuation; `contains` looks inside them.
///
/// Anything compared with a field that says nothing is false but `!=`, as Dataview has it, so `due < today` never
/// lists what has no due date. A field written wrong is not an error: one no record has is empty on every record.
///
/// What differs:
/// - `isEmpty` is [isEmptyValue] and `matches` is [valueMatches]: the web's names are a matcher's in every Dart test
///   and `matches` is note_text.dart's too. `EMPTY` is [emptyValue], `CATEGORY_WORDS` [categoryWords].
/// - Words are ordered by collate.dart's [localeCompare], which stands in for the browser's collation (see there).
library;

import '../days.dart' show isIsoDay, isoDayAfter;
import '../item_syntax.dart' show jsTrim;
import '../properties.dart';
import '../sums.dart' show writtenNumber;
import '../task_fields.dart' show TaskFields, dateKeys, priorities, priorityOf, priorityRank, samePerson;
import 'collate.dart';
import 'read.dart';
import 'records.dart';

/// What a field says (`Value`).
sealed class Value extends QueryData {
  const Value();

  /// The web's name for the kind: `text`, `day`, `people`…
  String get kind;
}

class EmptyValue extends Value {
  const EmptyValue();
  @override
  String get kind => 'empty';
  @override
  Object? toJson() => {'kind': kind};
}

class TextValue extends Value {
  const TextValue(this.text);
  final String text;
  @override
  String get kind => 'text';
  @override
  Object? toJson() => {'kind': kind, 'text': text};
}

class NumberValue extends Value {
  const NumberValue(this.value, this.text);
  final double value;
  final String text;
  @override
  String get kind => 'number';
  @override
  Object? toJson() => {'kind': kind, 'value': jsonNumber(value), 'text': text};
}

class DayValue extends Value {
  const DayValue(this.day);
  final String day;
  @override
  String get kind => 'day';
  @override
  Object? toJson() => {'kind': kind, 'day': day};
}

/// A priority, or none ([name] null), which still sorts and compares, between medium and low.
class PriorityValue extends Value {
  const PriorityValue(this.name);
  final String? name;
  @override
  String get kind => 'priority';
  @override
  Object? toJson() => {'kind': kind, 'name': name};
}

/// A status, its place in the workflow it is in ([rank]), and where it stands.
class StatusValue extends Value {
  const StatusValue({required this.text, required this.rank, required this.category, required this.workflow});
  final String text;
  final double rank;
  final StatusCategory category;
  final List<String> workflow;
  @override
  String get kind => 'status';
  @override
  Object? toJson() => {'kind': kind, 'text': text, 'rank': jsonNumber(rank), 'category': category.name, 'workflow': workflow};
}

class PeopleValue extends Value {
  const PeopleValue(this.names);
  final List<String> names;
  @override
  String get kind => 'people';
  @override
  Object? toJson() => {'kind': kind, 'names': names};
}

/// Tags, labels, links: [tags] for a list of tags, which hold the tags inside them.
class ListValue extends Value {
  const ListValue(this.items, {required this.tags});
  final List<String> items;
  final bool tags;
  @override
  String get kind => 'list';
  @override
  Object? toJson() => {'kind': kind, 'items': items, 'tags': tags};
}

class BoolValue extends Value {
  const BoolValue({required this.on});
  final bool on;
  @override
  String get kind => 'bool';
  @override
  Object? toJson() => {'kind': kind, 'on': on};
}

/// A field that says nothing (`EMPTY`).
const Value emptyValue = EmptyValue();

final RegExp _ats = RegExp(r'^@+');
final RegExp _hashes = RegExp(r'^#+');

Value _text(String? said) {
  final clean = said == null ? '' : jsTrim(said);
  return clean.isNotEmpty ? TextValue(clean) : emptyValue;
}

Value _day(String? said) => said != null && said.isNotEmpty && isIsoDay(said) ? DayValue(said) : _text(said);

Value _people(Iterable<String> names) {
  final kept = [
    for (final name in names)
      if (jsTrim(name.replaceFirst(_ats, '')) case final clean when clean.isNotEmpty) clean,
  ];
  return kept.isNotEmpty ? PeopleValue(kept) : emptyValue;
}

Value _list(List<String> items, [bool tags = false]) => items.isNotEmpty ? ListValue([...items], tags: tags) : emptyValue;

/// Whether a value says nothing: no value, no priority, a list with nothing in it (`isEmpty`).
bool isEmptyValue(Value value) => switch (value) {
      EmptyValue() => true,
      PriorityValue(:final name) => name == null,
      PeopleValue(:final names) => names.isEmpty,
      ListValue(:final items) => items.isEmpty,
      _ => false,
    };

final RegExp _apostrophes = RegExp("['’]");
final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Words as two of them are compared: lower case, no apostrophes, nothing but letters and numbers.
String _norm(String words) => words.toLowerCase().replaceAll(_apostrophes, '').replaceAll(_notWord, '');

/// A status's place in its workflow, the most finished last; a status the workflow has not got, by where it stands.
({double rank, StatusCategory category}) _statusRank(String status, List<String> workflow) {
  final category = statusCategory(status, workflow);
  final at = workflow.indexWhere((each) => _norm(each) == _norm(status));
  if (at >= 0) return (rank: at.toDouble(), category: category);
  final rank = switch (category) {
    StatusCategory.todo => -0.5,
    StatusCategory.doing => (workflow.length - 1) / 2,
    StatusCategory.done => workflow.length - 0.5,
  };
  return (rank: rank, category: category);
}

Value _status(String? said, List<String> workflow) {
  final clean = said == null ? '' : jsTrim(said);
  if (clean.isEmpty) return emptyValue;
  final placed = _statusRank(clean, workflow);
  return StatusValue(text: clean, rank: placed.rank, category: placed.category, workflow: workflow);
}

/// A value written as words, read for what it is: a day, a number, links, a list, or words.
Value _inferred(String? said) {
  final clean = said == null ? '' : jsTrim(said);
  if (clean.isEmpty) return emptyValue;
  if (isIsoDay(clean)) return DayValue(clean);
  final number = writtenNumber(clean);
  if (number != null) return NumberValue(number, clean);
  if (clean.contains('[[')) return _list(linkTargets(clean));
  if (clean.startsWith('[') && clean.endsWith(']')) return _list(propertyList(clean));
  return TextValue(clean);
}

/// A property's value, read as what its key holds (properties.dart `propertyKind`).
Value _typed(String key, String? said, List<String> workflow) {
  final clean = said == null ? '' : jsTrim(said);
  if (clean.isEmpty) return emptyValue;
  switch (propertyKind(key)) {
    case PropertyKind.date:
      return _day(clean);
    case PropertyKind.priority:
      final priority = priorityOf(clean);
      return priority != null ? PriorityValue(priority.name) : _text(clean);
    case PropertyKind.number:
      final number = writtenNumber(clean) ?? parseFloat(clean);
      return number != null && number.isFinite ? NumberValue(number, clean) : _text(clean);
    case PropertyKind.person:
      return _people(propertyList(clean));
    case PropertyKind.links:
      return _list(linkTargets(clean));
    case PropertyKind.link:
      final targets = linkTargets(clean);
      return _text(targets.isEmpty ? null : targets.first);
    case PropertyKind.list:
      return _list([for (final item in propertyList(clean)) item.replaceFirst(_hashes, '')]);
    case PropertyKind.status:
      return _status(clean, workflow);
    case PropertyKind.id:
      return _text(clean);
    case PropertyKind.text:
      return _inferred(clean);
  }
}

/// Where a record stands: a ticket's or a note's status's, and for a to-do, ticked or not.
StatusCategory categoryOf(QueryRecord record) {
  final said = valueOf(record, 'status');
  return said is StatusValue ? said.category : StatusCategory.todo;
}

/// A to-do's status: its own `[status:: …]`, or Done where it is ticked, Cancelled where it has ❌, else To do.
Value _taskStatus(QueryRecord record) {
  final named = record.fields?.fields['status'];
  if (named != null && jsTrim(named).isNotEmpty) return _status(named, record.workflow);
  if (record.done == true) return _status('Done', record.workflow);
  final cancelled = record.fields?.cancelled;
  if (cancelled != null && cancelled.isNotEmpty) return _status('Cancelled', record.workflow);
  return _status('To do', record.workflow);
}

Value _taskValue(QueryRecord record, String field) {
  final TaskFields fields = record.fields!;
  final named = fields.fields[field];
  if (field == 'status') return _taskStatus(record);
  if (field == 'checked') return BoolValue(on: record.done == true);
  if (field == 'line') return NumberValue((record.line + 1).toDouble(), '${record.line + 1}');
  if (field == 'created') return _day(fields.created ?? record.created);
  if (dateKeys.contains(field)) return _day(fields.date(field));
  if (field == 'priority') return PriorityValue(fields.priority);
  if (field == 'assignee') return _people([...fields.assignees, ...propertyList(named)]);
  if (field == 'recurs') return _text(fields.recurs);
  if (field == 'id') return _text(fields.id ?? named);
  if (field == 'depends-on') return _list(fields.dependsOn);
  return _typed(field, named, record.workflow);
}

Value _noteValue(QueryRecord record, String field) {
  final said = record.props[field];
  final ticket = record.ticket;
  if (field == 'created') return said != null && isIsoDay(jsTrim(said)) ? _day(jsTrim(said)) : _day(record.created);
  if (field == 'checked') return ticket != null ? BoolValue(on: ticket.category == StatusCategory.done) : emptyValue;
  if (field == 'status') return _status(ticket != null ? ticket.status : said, record.workflow);
  if (ticket != null) {
    if (field == 'id') return _text(ticket.id ?? said);
    if (field == 'priority') return ticket.priority != null ? PriorityValue(ticket.priority) : _typed(field, said, record.workflow);
    if (field == 'assignee') return _people(propertyList(said));
    if (field == 'estimate' && ticket.estimate != null) {
      final written = said == null ? '' : jsTrim(said);
      return NumberValue(ticket.estimate!, written.isNotEmpty ? written : _jsNumber(ticket.estimate!));
    }
    if (field == 'blocked-by') return _list(ticket.blockedBy);
    if (field == 'parent') return _text(ticket.parent);
    if (field == 'labels') return _list(ticket.labels);
  }
  if (field == 'priority') return said != null && jsTrim(said).isNotEmpty ? _typed(field, said, record.workflow) : const PriorityValue(null);
  return _typed(field, said, record.workflow);
}

/// A number as JavaScript's `String(n)` writes it: a whole one without its `.0`.
String _jsNumber(double value) => value.isFinite && value == value.truncateToDouble() && value.abs() < 1e21 ? value.toStringAsFixed(0) : value.toString();

/// What [field] (as read.dart `fieldName` keeps it) says on [record].
Value valueOf(QueryRecord record, String field) {
  switch (field) {
    case 'title':
    case 'note':
      return _text(record.title);
    case 'text':
      return _text(record.text);
    case 'notebook':
      return _text(record.notebook);
    case 'tags':
      return _list(record.tags, true);
    case 'updated':
      return _day(record.updated);
    case 'kind':
      return _text(record.kind.name);
    case 'category':
      final said = record.kind == RecordKind.task ? _taskStatus(record) : _noteValue(record, 'status');
      if (said is StatusValue) return _text(categoryWords[said.category]);
      return record.kind == RecordKind.note ? emptyValue : _text(categoryWords[StatusCategory.todo]);
    default:
      return record.kind == RecordKind.task ? _taskValue(record, field) : _noteValue(record, field);
  }
}

/// Where a status stands, in words: what `category` says, and a group of it is called (`CATEGORY_WORDS`).
const Map<StatusCategory, String> categoryWords = {StatusCategory.todo: 'To do', StatusCategory.doing: 'In progress', StatusCategory.done: 'Done'};

// ---- comparing ------------------------------------------------------------------------------------------------

/// What a literal says as words.
String _literalText(Literal literal, String today) => switch (literal) {
      NumberLiteral(:final text) || WordsLiteral(:final text) => text,
      TodayLiteral(:final offset) => isoDayAfter(today, offset) ?? today,
      DateLiteral(:final day) => day,
      EmptyLiteral() => '',
    };

/// A literal as a day, where it is one.
String? _literalDay(Literal literal, String today) => switch (literal) {
      TodayLiteral(:final offset) => isoDayAfter(today, offset),
      DateLiteral(:final day) => day,
      WordsLiteral(:final text) when isIsoDay(jsTrim(text)) => jsTrim(text),
      _ => null,
    };

/// A literal as a number, where it is one.
double? _literalNumber(Literal literal) => switch (literal) {
      NumberLiteral(:final value) => value,
      WordsLiteral(:final text) => writtenNumber(text),
      _ => null,
    };

/// An order, as [op] asks of it: how the value stands to what it is compared with.
bool _ordered(int order, Op op) => switch (op) {
      Op.eq || Op.contains => order == 0,
      Op.ne || Op.notContains => order != 0,
      Op.lt => order < 0,
      Op.le => order <= 0,
      Op.gt => order > 0,
      Op.ge => order >= 0,
    };

int _sign(num n) => n < 0 ? -1 : (n > 0 ? 1 : 0);

/// Two words in the order a person sorts them, whatever their case: `GHO-9` before `GHO-10` (`textOrder`).
int textOrder(String a, String b) => localeCompare(a, b, numeric: true, base: true);

/// Words that say yes to a ticked to-do, and no.
const Set<String> _yes = {'yes', 'true', 'done', 'ticked', 'checked', 'x', '1', 'y'};
const Set<String> _no = {'no', 'false', 'open', 'unticked', 'unchecked', 'not done', '0', 'n'};

final RegExp _itemSign = RegExp(r'^[#@]+');
final RegExp _itemLink = RegExp(r'^\[\[(.*)\]\]$');

/// An item of a list as it is compared: its `#`, its `@` and its link's brackets off.
String _itemWords(String item) => _norm(item.replaceFirst(_itemSign, '').replaceFirstMapped(_itemLink, (m) => m.group(1)!));

/// Whether [value] passes [op] against [literal], [today] being the day `today` names (`matches`).
bool valueMatches(Value value, Op op, Literal literal, String today) {
  final contains = op == Op.contains || op == Op.notContains;
  final equals = op == Op.eq || op == Op.ne;
  if (literal is EmptyLiteral) {
    if (op == Op.eq || op == Op.contains) return isEmptyValue(value);
    if (op == Op.ne || op == Op.notContains) return !isEmptyValue(value);
    return false;
  }
  final words = _literalText(literal, today);
  final negative = op == Op.ne || op == Op.notContains;
  if (value is PriorityValue) {
    final other = priorityOf(words);
    if (other == null) return negative;
    // The most urgent the greatest: highest is 0 in rank, so the order is turned round.
    return _ordered(_sign(other.rank - priorityRank(value.name)), op);
  }
  if (isEmptyValue(value)) return negative;
  switch (value) {
    case DayValue(:final day):
      final other = _literalDay(literal, today);
      if (contains) return day.contains(words) != negative;
      if (other == null) return negative;
      return _ordered(_sign(day.compareTo(other)), op);
    case NumberValue(:final text, value: final number):
      final other = _literalNumber(literal);
      if (contains) return text.toLowerCase().contains(words.toLowerCase()) != negative;
      if (other == null) return op == Op.eq ? _norm(text) == _norm(words) : negative;
      return _ordered(_sign(number - other), op);
    case BoolValue(:final on):
      final said = jsTrim(words).toLowerCase();
      final bool? other = _yes.contains(said) ? true : (_no.contains(said) ? false : null);
      if (other == null || !equals) return negative;
      return (on == other) != negative;
    case StatusValue(:final text, :final rank, :final workflow):
      if (contains) return text.toLowerCase().contains(words.toLowerCase()) != negative;
      if (equals) return (_norm(text) == _norm(words)) != negative;
      // Before or after in the workflow: the other status's place in the value's, or where it stands if it has none.
      return _ordered(_sign(rank - _statusRank(words, workflow).rank), op);
    case PeopleValue(:final names):
      final has = names.any((name) => samePerson(name, words));
      if (op == Op.eq || op == Op.contains) return has;
      if (negative) return !has;
      return _ordered(textOrder(names[0], words), op);
    case ListValue(:final items, :final tags):
      final want = _itemWords(words);
      final inside = '${words.toLowerCase().replaceFirst(_hashes, '')}/';
      final has = items.any((item) {
        if (_itemWords(item) == want) return true;
        // A tag holds the tags inside it: #work has #work/clients.
        return tags && item.toLowerCase().replaceFirst(_hashes, '').startsWith(inside);
      });
      if (op == Op.eq || op == Op.contains) return has;
      if (negative) return !has;
      return _ordered(textOrder(items[0], words), op);
    case TextValue(:final text):
      if (equals) return (_norm(text) == _norm(words)) != negative;
      if (contains) return text.toLowerCase().contains(words.toLowerCase()) != negative;
      final mine = writtenNumber(text);
      final other = _literalNumber(literal);
      if (mine != null && other != null) return _ordered(_sign(mine - other), op);
      return _ordered(textOrder(text, words), op);
    case EmptyValue() || PriorityValue():
      return negative;
  }
}

/// Whether a field says something, and not "no": a field alone in `where:`.
bool says(Value value) {
  if (isEmptyValue(value)) return false;
  if (value is BoolValue) return value.on;
  if (value is NumberValue) return value.value != 0;
  return true;
}

// ---- sorting and grouping -------------------------------------------------------------------------------------

/// Each kind's place among the others, for a field that is one kind on some records and another on others.
const List<String> _kindOrder = ['priority', 'status', 'day', 'number', 'bool', 'people', 'list', 'text', 'empty'];

/// Two values in order: priorities the most urgent first, statuses in the workflow's order, days and numbers from
/// the least, words as a person sorts them (`GHO-9` before `GHO-10`). A record with no value is the caller's to put
/// last. Negative, zero or positive, as the web's is.
num compareValues(Value a, Value b) {
  if (a is PriorityValue && b is PriorityValue) return priorityRank(a.name) - priorityRank(b.name);
  if (a is StatusValue && b is StatusValue) return a.rank != b.rank ? a.rank - b.rank : textOrder(a.text, b.text);
  if (a is DayValue && b is DayValue) return _sign(a.day.compareTo(b.day));
  if (a is NumberValue && b is NumberValue) return a.value - b.value;
  if (a is BoolValue && b is BoolValue) return (a.on ? 1 : 0) - (b.on ? 1 : 0);
  if (a.kind != b.kind && a is! TextValue && b is! TextValue) return _kindOrder.indexOf(a.kind) - _kindOrder.indexOf(b.kind);
  return textOrder(valueText(a), valueText(b));
}

/// A value as words: what a group is called and a cell says where it has nothing better.
String valueText(Value value) => switch (value) {
      EmptyValue() => '',
      TextValue(:final text) || NumberValue(:final text) || StatusValue(:final text) => text,
      DayValue(:final day) => day,
      PriorityValue(:final name) => () {
          for (final priority in priorities) {
            if (priority.name == name) return priority.label;
          }
          return '';
        }(),
      PeopleValue(:final names) => names.join(', '),
      ListValue(:final items) => items.join(', '),
      BoolValue(:final on) => on ? 'Yes' : 'No',
    };

/// The groups a value puts its record in: one for most, one for each thing a list holds, none-group for nothing.
List<Value> groupValues(Value value) => switch (value) {
      PeopleValue(:final names) => [for (final name in names) PeopleValue([name])],
      ListValue(:final items, :final tags) => [for (final item in items) ListValue([item], tags: tags)],
      _ => [value],
    };

final RegExp _handleGaps = RegExp(r'[\s_-]+');

/// A group's key: two values in one group have one key.
String groupKey(Value value) {
  if (isEmptyValue(value)) return '';
  if (value is PeopleValue) return '@${value.names[0].toLowerCase().replaceAll(_handleGaps, '-')}';
  if (value is PriorityValue) return '!${value.name}';
  final words = valueText(value);
  final normed = _norm(words);
  return '${value.kind}:${normed.isNotEmpty ? normed : words}';
}

// ---- names ----------------------------------------------------------------------------------------------------

/// What a field is called at the head of a column, a group or a total.
const Map<String, String> _labels = {
  'title': 'Title',
  'note': 'Note',
  'text': 'To-do',
  'notebook': 'Notebook',
  'tags': 'Tags',
  'created': 'Created',
  'updated': 'Updated',
  'kind': 'Kind',
  'category': 'Category',
  'checked': 'Ticked',
  'line': 'Line',
  'done': 'Done',
  'due': 'Due',
  'start': 'Start',
  'scheduled': 'Scheduled',
  'cancelled': 'Cancelled',
  'recurs': 'Repeats',
  'depends-on': 'Depends on',
};

final RegExp _dashes = RegExp(r'[-_]+');

String fieldLabel(String field) {
  var own = _labels[field];
  if (own == null) {
    for (final property in ticketProperties) {
      if (property.key == field) own = property.label;
    }
  }
  if (own != null && own.isNotEmpty) return own;
  final words = jsTrim(field.replaceAll(_dashes, ' '));
  return words.isNotEmpty ? '${words[0].toUpperCase()}${words.substring(1)}' : field;
}
