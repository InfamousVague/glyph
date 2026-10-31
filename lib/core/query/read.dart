/// A query's lines, read: the grammar of a ```query fence, and the one plain sentence that says what is wrong with
/// one that cannot be read, and where (tauri/docs/QUERIES.md is the grammar written down; docs/DESIGN.md §159 why
/// it is this one). A port of `src/app/core/query/read.ts`. Matt asked for "notion and jira like features"; a query
/// is the database view, written as words.
///
///     ```query
///     from: tickets #bug
///     where: status != Done and (priority >= high or due < today+7)
///     sort: priority, due
///     show: table
///     ```
///
/// One clause to a line, each a name, a colon and what it says, and each left out for its default, so `from: #bug`
/// alone is a query. The names are Dataview's and Obsidian Tasks' where they have one (`from`, `where`, `sort`,
/// `group`, `limit`), so a person who has written those reads this, and `sort by:` and `group by:` are read too.
///
///     from:     notes, tickets or tasks, then what to read them from: `#tag`, `[[A notebook]]` (its pages, or the
///               notes that link to any other note), `@person`, `"words"`; side by side all of them, `or` for
///               either, `not` or `-` to leave one out, brackets to say which goes with which
///     where:    tests on fields: `= != < <= > >=`, `contains`, `is empty`, joined by `and`, `or`, `not` and
///               brackets; a field alone is a test that it says something
///     sort:     fields, each `asc` or `desc`
///     group:    one field
///     show:     table, list, board, calendar, gantt, count, timeline or chart (`view:` is read as it too)
///     columns:  the fields a table shows, and a list and a board say beside each record
///     total:    the fields to add up
///     limit:    how many records at most
///     rollup:   a column worked out over the notes a record links to or is linked from (rollup.dart):
///               `open = count(links where status != done)`, `hours = sum(hours of backlinks)`; one a line
///
/// And a view's own, each one field or word, which any other view leaves alone (the port's, 2026-10-30):
///
///     date:     the field a calendar puts a record on (`due`, `date`, `created`); its first day field where unsaid
///     start:    the field a timeline's bar starts on; `start` where unsaid
///     end:      the field it ends on; `due` where unsaid
///     zoom:     how much a timeline shows at once: week, month or quarter
///     chart:    bar, line or pie
///     x:        the field a chart's bars or slices are of; `group:`, else the status
///     y:        what each measures: count, or sum, average, min, max or percent of a field (`sum(hours)`)
///     series:   a field a chart's bars are split by, each a colour
///     cycle:    the cycle a burndown is of: current where unsaid, previous, next, `2026-C45` or `[[Sprint 12]]`
///
/// And the planning views of tickets (Matt, 2026-10-31; lib/core/query/planning.dart): `show: burndown` and `show:
/// velocity` (charts, or `chart: burndown` under `show: chart`), and `show: roadmap`, a timeline of epics and
/// milestones. Their fields - `cycle`, `stale`, `age`, `epic`, `milestone`, `progress` - are fields like any other,
/// and `where: cycle = current` and `where: stale` read as a person would mean them.
///
/// A field is written as Dataview keys one: lower case, a space a dash (task_fields.dart `fieldKey`), so `Due Date`
/// and `due-date` are one field. A value on the right of a test is words unless it is something else: a number, a
/// day (`2026-10-03`, `today`, `today+7`, `today-2w`), `empty`, or anything in quotes, which is words whatever it
/// says. What a word means against a field is the run's to say (values.dart); this only reads.
///
/// A query that cannot be read is never half run: it answers the first problem, its line and column, in a sentence a
/// person can act on. Pure, so every shape of query is a test (test/query/read_test.dart).
///
/// What differs: the web's unions of plain objects are sealed classes here, each with [QueryData.toJson] giving the
/// object the web has, key for key, which is what a test and the fixtures (tool/query_fixtures.mjs) compare. `SHOWS`
/// is [ShowAs.values], `QUERY_LINES` is [queryLines]. An operator is an [Op] whose [Op.sign] is the web's string.
/// The drawn timeline and the chart, `rollup:` and the view's own lines are the port's (Matt, 2026-10-30, "add all
/// 12" of the plain-Markdown features): `show: timeline` is its own timeline here, where the web reads it as `gantt`,
/// and a [Query]'s JSON has their keys only where they are written, so every query the web reads reads the same.
library;

import 'dart:convert';

import '../days.dart' show isIsoDay;
import '../item_syntax.dart' show jsTrim;
import '../task_fields.dart' show fieldKey;

/// Plain data a query is made of and answers with: compared, hashed and printed by what it says ([toJson]), as the
/// web compares its objects with `toEqual`.
abstract class QueryData {
  const QueryData();

  /// The object the web has for this, key for key.
  Object? toJson();

  @override
  bool operator ==(Object other) => other is QueryData && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => jsonEncode(toJson());
}

/// A number as JSON writes one the web wrote: a whole number without its `.0`.
Object jsonNumber(num value) => value is double && value.isFinite && value == value.truncateToDouble() ? value.toInt() : value;

/// What the records are (`QueryKind`): `events` is the port's own, the calendars' (docs/CALENDAR.md).
enum QueryKind { notes, tickets, tasks, events }

/// The ways a query is shown, in the order docs/QUERIES.md teaches them (`SHOWS`, `ShowAs`).
enum ShowAs { table, list, board, calendar, gantt, count, timeline, chart }

/// How a measure works its records out: a chart's `y:`, a rollup's (rollup.dart).
enum Aggregate { count, sum, average, min, max, percent }

/// A chart's `y:` and a rollup's sum: what is worked out, and of which field; a count's field may be null.
class Measure extends QueryData {
  const Measure(this.fn, [this.field]);
  final Aggregate fn;
  final String? field;

  /// As the fence writes it: `count`, `sum(hours)`.
  String get written => field == null ? fn.name : '${fn.name}($field)';

  @override
  Object? toJson() => {'fn': fn.name, 'field': field};
}

/// A chart's shape (`chart:`).
enum ChartKind { bar, line, pie }

/// A planning view of tickets (Matt, 2026-10-31; lib/core/planning): a cycle's burndown and the cycles' velocity, each
/// a chart, and the roadmap of epics and milestones, a timeline. Written `show: burndown`, `show: velocity` and
/// `show: roadmap`, or `chart: burndown` under `show: chart`.
enum PlanView { burndown, velocity, roadmap }

/// How many days a timeline shows across its card (`zoom:`).
enum TimelineZoom { week, month, quarter }

/// Which notes a rollup works over, from the record it is a column of (rollup.dart).
enum RollupWay {
  /// The notes its `[[links]]` name, anywhere in it.
  links,

  /// The notes whose `[[links]]` name it.
  backlinks,

  /// The to-dos in its note.
  tasks,

  /// The notes one of its fields names, `project: [[Kiln]]`: a relation.
  relation,

  /// The notes whose field names it: the relation from the other side, `backlinks.project`.
  backRelation,
}

/// `rollup: open = count(links where status != done)`: a column called [name], [measure] over the notes [way]
/// reaches (through [through], a relation's field), those [where] passes.
class Rollup extends QueryData {
  const Rollup({required this.name, required this.measure, required this.way, this.through, this.where});
  final String name;
  final Measure measure;
  final RollupWay way;
  final String? through;
  final Condition? where;

  @override
  Object? toJson() => {'name': name, 'measure': measure.toJson(), 'way': way.name, 'through': through, 'where': where?.toJson()};
}

/// What `from:` reads a record from, after its kind (`Source`).
sealed class Source extends QueryData {
  const Source();
}

class TagSource extends Source {
  const TagSource(this.tag);
  final String tag;
  @override
  Object? toJson() => {'kind': 'tag', 'tag': tag};
}

class LinkSource extends Source {
  const LinkSource(this.title);
  final String title;
  @override
  Object? toJson() => {'kind': 'link', 'title': title};
}

class PersonSource extends Source {
  const PersonSource(this.name);
  final String name;
  @override
  Object? toJson() => {'kind': 'person', 'name': name};
}

class WordsSource extends Source {
  const WordsSource(this.words);
  final String words;
  @override
  Object? toJson() => {'kind': 'words', 'words': words};
}

class NotSource extends Source {
  const NotSource(this.of);
  final Source of;
  @override
  Object? toJson() => {'kind': 'not', 'of': of.toJson()};
}

class AndSource extends Source {
  const AndSource(this.all);
  final List<Source> all;
  @override
  Object? toJson() => {'kind': 'and', 'all': [for (final each in all) each.toJson()]};
}

class OrSource extends Source {
  const OrSource(this.any);
  final List<Source> any;
  @override
  Object? toJson() => {'kind': 'or', 'any': [for (final each in any) each.toJson()]};
}

/// How a test compares (`Op`); [sign] is the web's word for it.
enum Op {
  eq('='),
  ne('!='),
  lt('<'),
  le('<='),
  gt('>'),
  ge('>='),
  contains('contains'),
  notContains('!contains');

  const Op(this.sign);
  final String sign;

  static Op of(String sign) => values.firstWhere((op) => op.sign == sign);
}

/// What a test compares a field with (`Literal`).
sealed class Literal extends QueryData {
  const Literal();
}

class NumberLiteral extends Literal {
  const NumberLiteral(this.value, this.text);
  final double value;
  final String text;
  @override
  Object? toJson() => {'kind': 'number', 'value': jsonNumber(value), 'text': text};
}

class WordsLiteral extends Literal {
  const WordsLiteral(this.text, {required this.quoted});
  final String text;
  final bool quoted;
  @override
  Object? toJson() => {'kind': 'words', 'text': text, 'quoted': quoted};
}

/// A day counted from today: 0 for `today`, 7 for `today+7`.
class TodayLiteral extends Literal {
  const TodayLiteral(this.offset, this.text);
  final int offset;
  final String text;
  @override
  Object? toJson() => {'kind': 'today', 'offset': offset, 'text': text};
}

class DateLiteral extends Literal {
  const DateLiteral(this.day);
  final String day;
  @override
  Object? toJson() => {'kind': 'date', 'day': day};
}

class EmptyLiteral extends Literal {
  const EmptyLiteral();
  @override
  Object? toJson() => {'kind': 'empty'};
}

/// A test, or tests joined (`Condition`).
sealed class Condition extends QueryData {
  const Condition();
}

class Compare extends Condition {
  const Compare(this.field, this.op, this.value);
  final String field;
  final Op op;
  final Literal value;
  @override
  Object? toJson() => {'kind': 'compare', 'field': field, 'op': op.sign, 'value': value.toJson()};
}

/// `is empty` ([empty] true) and `is not empty`.
class EmptyTest extends Condition {
  const EmptyTest(this.field, {required this.empty});
  final String field;
  final bool empty;
  @override
  Object? toJson() => {'kind': 'empty', 'field': field, 'empty': empty};
}

/// A field on its own: it says something, and not "no".
class Has extends Condition {
  const Has(this.field);
  final String field;
  @override
  Object? toJson() => {'kind': 'has', 'field': field};
}

class NotCondition extends Condition {
  const NotCondition(this.of);
  final Condition of;
  @override
  Object? toJson() => {'kind': 'not', 'of': of.toJson()};
}

class AndCondition extends Condition {
  const AndCondition(this.all);
  final List<Condition> all;
  @override
  Object? toJson() => {'kind': 'and', 'all': [for (final each in all) each.toJson()]};
}

class OrCondition extends Condition {
  const OrCondition(this.any);
  final List<Condition> any;
  @override
  Object? toJson() => {'kind': 'or', 'any': [for (final each in any) each.toJson()]};
}

class SortKey extends QueryData {
  const SortKey(this.field, {this.desc = false});
  final String field;
  final bool desc;
  @override
  Object? toJson() => {'field': field, 'desc': desc};
}

class Query extends QueryData {
  const Query({
    this.kind = QueryKind.notes,
    this.from,
    this.where,
    this.sort = const [],
    this.group,
    this.show,
    this.columns = const [],
    this.total = const [],
    this.limit,
    this.date,
    this.start,
    this.end,
    this.zoom,
    this.chart,
    this.x,
    this.y,
    this.series,
    this.rollups = const [],
    this.plan,
    this.cycle,
  });

  /// What the records are: notes (tickets among them), tickets alone, or to-dos. Notes, where `from:` does not say.
  final QueryKind kind;
  final Source? from;
  final Condition? where;

  /// As written; empty for the kind's own order.
  final List<SortKey> sort;
  final String? group;

  /// As written; null for the kind's own way.
  final ShowAs? show;

  /// As written; empty for the kind's own columns.
  final List<String> columns;
  final List<String> total;
  final int? limit;

  /// A calendar's day field (`date:`), a timeline's start and end fields (`start:`, `end:`) and its zoom; null where
  /// unsaid, for the view's own.
  final String? date;
  final String? start;
  final String? end;
  final TimelineZoom? zoom;

  /// A chart's shape, the field its bars are of, what each measures and the field it is split by.
  final ChartKind? chart;
  final String? x;
  final Measure? y;
  final String? series;

  /// The columns worked out over linked notes, in the order written.
  final List<Rollup> rollups;

  /// A planning view (lib/core/query/planning.dart): a burndown, velocity, or the roadmap; null for none.
  final PlanView? plan;

  /// The cycle a burndown is of, as written (`current`, `previous`, `2026-C45`, `[[Sprint 12]]`); null for the current.
  final String? cycle;

  /// Whether anything of a view's own is written: what the web's JSON has no keys for.
  bool get hasViewLines => date != null || start != null || end != null || zoom != null || chart != null || x != null || y != null || series != null || rollups.isNotEmpty || plan != null || cycle != null;

  @override
  Object? toJson() => {
        'kind': kind.name,
        'from': from?.toJson(),
        'where': where?.toJson(),
        'sort': [for (final key in sort) key.toJson()],
        'group': group,
        'show': show?.name,
        'columns': columns,
        'total': total,
        'limit': limit,
        if (date != null) 'date': date,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (zoom != null) 'zoom': zoom!.name,
        if (chart != null) 'chart': chart!.name,
        if (x != null) 'x': x,
        if (y != null) 'y': y!.toJson(),
        if (series != null) 'series': series,
        if (rollups.isNotEmpty) 'rollups': [for (final rollup in rollups) rollup.toJson()],
        if (plan != null) 'plan': plan!.name,
        if (cycle != null) 'cycle': cycle,
      };
}

/// Why a query cannot be read: the line and column, counting from 1 within the fence, and the sentence.
class QueryProblem extends QueryData {
  const QueryProblem({required this.line, required this.column, required this.message});
  final int line;
  final int column;
  final String message;
  @override
  Object? toJson() => {'line': line, 'column': column, 'message': message};
}

/// A query read, or the first problem with it: one of the two is null (`Reading`).
class Reading extends QueryData {
  const Reading.read(Query this.query) : problem = null;
  const Reading.unread(QueryProblem this.problem) : query = null;
  final Query? query;
  final QueryProblem? problem;
  @override
  Object? toJson() => {'query': query?.toJson(), 'problem': problem?.toJson()};
}

/// A query's lines, by name, and what each is called where it is written.
const Map<String, String> _clauses = {
  'from': 'from',
  'where': 'where',
  'sort': 'sort',
  'sort by': 'sort',
  'group': 'group',
  'group by': 'group',
  'show': 'show',
  'columns': 'columns',
  'column': 'columns',
  'total': 'total',
  'totals': 'total',
  'limit': 'limit',
  // The port's own (2026-10-30): `view:` as `show:`, and each view's lines.
  'view': 'show',
  'date': 'date',
  'day': 'date',
  'start': 'start',
  'end': 'end',
  'zoom': 'zoom',
  'chart': 'chart',
  'x': 'x',
  'y': 'y',
  'series': 'series',
  'rollup': 'rollup',
  // A burndown's cycle (lib/core/query/planning.dart).
  'cycle': 'cycle',
  'sprint': 'cycle',
};

/// The names, as a sentence lists them (`QUERY_LINES`), the web's first, so a "did you mean" finds the one it did.
const List<String> queryLines = ['from', 'where', 'sort', 'group', 'show', 'columns', 'total', 'limit', 'rollup', 'date', 'start', 'end', 'zoom', 'chart', 'x', 'y', 'series', 'cycle'];

/// The names a "did you mean" offers: a letter's name is too near every short word to be one.
final List<String> _nearLines = [for (final name in queryLines) if (name.length > 1) name];

/// A kind as `from:` may write it.
const Map<String, QueryKind> _kinds = {
  'notes': QueryKind.notes,
  'note': QueryKind.notes,
  'pages': QueryKind.notes,
  'tickets': QueryKind.tickets,
  'ticket': QueryKind.tickets,
  'issues': QueryKind.tickets,
  'tasks': QueryKind.tasks,
  'task': QueryKind.tasks,
  'todos': QueryKind.tasks,
  'to-dos': QueryKind.tasks,
  'events': QueryKind.events,
  'event': QueryKind.events,
};

/// Another way of saying a way to show, read as that way.
const Map<String, ShowAs> _showAlso = {'kanban': ShowAs.board, 'number': ShowAs.count, 'cards': ShowAs.board, 'graph': ShowAs.chart, 'roadmap': ShowAs.timeline};

/// A chart's shape as `chart:` may write it.
const Map<String, ChartKind> _chartWords = {
  'bar': ChartKind.bar,
  'bars': ChartKind.bar,
  'column': ChartKind.bar,
  'columns': ChartKind.bar,
  'line': ChartKind.line,
  'lines': ChartKind.line,
  'pie': ChartKind.pie,
  'donut': ChartKind.pie,
  'doughnut': ChartKind.pie,
};

/// A measure's word as `y:` and `rollup:` may write it.
const Map<String, Aggregate> _aggregates = {
  'count': Aggregate.count,
  'sum': Aggregate.sum,
  'total': Aggregate.sum,
  'average': Aggregate.average,
  'avg': Aggregate.average,
  'mean': Aggregate.average,
  'min': Aggregate.min,
  'max': Aggregate.max,
  'percent': Aggregate.percent,
  'done': Aggregate.percent,
};

/// The names a field is also called, by Dataview, Tasks or a person, read as the one the app keeps: `completed` is
/// Dataview's word for a ticked to-do, `completion` its done date.
const Map<String, String> _aliases = {
  'assignees': 'assignee',
  'people': 'assignee',
  'person': 'assignee',
  'tag': 'tags',
  'label': 'labels',
  'ticked': 'checked',
  'completed': 'checked',
  'completion': 'done',
  'modified': 'updated',
  'edited': 'updated',
  'file': 'note',
  'page': 'note',
  'dependson': 'depends-on',
};

/// A field's name as a query keeps it: Dataview's form (`fieldKey`), and the name the app keeps for an alias.
String fieldName(String written) {
  final key = fieldKey(written);
  return _aliases[key] ?? key;
}

/// What a field's name may be: a letter, digit or `_`, then those, `.`, `/` and `-`.
final RegExp _field = RegExp(r'^[\p{L}\p{N}_][\p{L}\p{N}_./-]*$', unicode: true);
const Set<String> _keywords = {'and', 'or', 'not'};

// ---- the words of a clause ------------------------------------------------------------------------------------

enum _T { word, quoted, tag, link, person, op, open, close, comma, minus }

class _Token {
  const _Token(this.kind, this.raw, this.text, this.at);
  final _T kind;

  /// As written, quotes and all.
  final String raw;

  /// What it says: a quoted value's words, a tag's or a person's name, a link's title, an operator.
  final String text;
  final int at;
}

/// A problem at [at] in a clause's value, before it has a line.
class _Trouble implements Exception {
  const _Trouble(this.at, this.message);
  final int at;
  final String message;
}

/// The quotes a phone or a keyboard may type, and what closes each.
const Map<String, String> _quotes = {'"': '"”', '“': '”"', "'": "'’", '‘': '’\''};
const List<String> _ops = ['!=', '==', '<=', '>=', '≠', '≤', '≥', '=', '<', '>'];
const Map<String, String> _opRead = {'==': '=', '≠': '!=', '≤': '<=', '≥': '>='};

final RegExp _space = RegExp(r'\s');
final RegExp _tagStart = RegExp(r'^#\p{L}', unicode: true);
final RegExp _tagRun = RegExp(r'^#\p{L}[\p{L}\p{N}_/-]*', unicode: true);
final RegExp _tagTail = RegExp(r'[-/]+$');
final RegExp _personStart = RegExp(r'^@\p{L}', unicode: true);
final RegExp _personRun = RegExp(r'^@\p{L}[\p{L}\p{N}_.-]*', unicode: true);
final RegExp _personTail = RegExp(r'[.-]+$');
final RegExp _minusBefore = RegExp(r'''^-[#@\["“'‘(]''');
final RegExp _fromWord = RegExp(r'^[^\s(),=<>≠≤≥]+');
final RegExp _whereWord = RegExp(r'^[^\s()=<>≠≤≥]+');
final RegExp _linkCut = RegExp('[#|]');

/// A clause's value as tokens. In `from:` a comma parts two filters and a dash leaves one out; in `where:` both are
/// words.
List<_Token> _scan(String value, bool from) {
  final tokens = <_Token>[];
  var at = 0;
  void push(_T kind, String raw, [String? text]) {
    tokens.add(_Token(kind, raw, text ?? raw, at));
    at += raw.length;
  }

  while (at < value.length) {
    final rest = value.substring(at);
    final char = rest[0];
    if (_space.hasMatch(char)) {
      at += 1;
      continue;
    }
    if (char == '(') {
      push(_T.open, char);
    } else if (char == ')') {
      push(_T.close, char);
    } else if (char == ',' && from) {
      push(_T.comma, char);
    } else if (_quotes.containsKey(char)) {
      // Counted as the page counts it: the closing quote's place among the characters, then cut by code units.
      final closers = _quotes[char]!;
      var close = -1;
      var n = 0;
      for (final rune in rest.substring(1).runes) {
        if (closers.contains(String.fromCharCode(rune))) {
          close = n;
          break;
        }
        n += 1;
      }
      if (close < 0) throw _Trouble(at, 'A quote opened here is never closed.');
      final raw = rest.substring(0, close + 2 > rest.length ? rest.length : close + 2);
      push(_T.quoted, raw, raw.length >= 2 ? raw.substring(1, raw.length - 1) : '');
    } else if (rest.startsWith('[[')) {
      final close = rest.indexOf(']]');
      if (close < 0) throw _Trouble(at, 'A [[ opened here is never closed with ]].');
      final raw = rest.substring(0, close + 2);
      push(_T.link, raw, jsTrim(raw.substring(2, raw.length - 2).split(_linkCut)[0]));
    } else if (_tagStart.hasMatch(rest)) {
      final raw = _tagRun.firstMatch(rest)!.group(0)!.replaceFirst(_tagTail, '');
      push(_T.tag, raw, raw.substring(1).toLowerCase());
    } else if (_personStart.hasMatch(rest)) {
      final raw = _personRun.firstMatch(rest)!.group(0)!.replaceFirst(_personTail, '');
      push(_T.person, raw, raw.substring(1));
    } else if (from && char == '-' && _minusBefore.hasMatch(rest)) {
      push(_T.minus, char);
    } else {
      String? op;
      for (final each in _ops) {
        if (rest.startsWith(each)) {
          op = each;
          break;
        }
      }
      if (op != null) {
        push(_T.op, op, _opRead[op] ?? op);
      } else {
        // A word runs to a space, a bracket, an operator, or (in from:) a comma.
        final raw = (from ? _fromWord : _whereWord).firstMatch(rest)?.group(0) ?? char;
        final word = raw.endsWith('!') && raw.length < rest.length && rest[raw.length] == '=' ? raw.substring(0, raw.length - 1) : raw;
        push(_T.word, word.isNotEmpty ? word : char);
      }
    }
  }
  return tokens;
}

/// Whether a token is one of the keywords [words], in any case.
bool _isWord(_Token? token, [String a = '', String b = '', String c = '']) {
  if (token == null || token.kind != _T.word) return false;
  final said = token.text.toLowerCase();
  return said == a || (b.isNotEmpty && said == b) || (c.isNotEmpty && said == c);
}

/// `“text”`, for a sentence.
String _said(String text) => '“$text”';

/// Reads tokens in order, with what each grammar asks of the next one.
class _Reader {
  _Reader(this.tokens, this.end);
  final List<_Token> tokens;

  /// Where the value ends, for a problem with nothing after it.
  final int end;
  int at = 0;

  _Token? peek([int by = 0]) => at + by < tokens.length ? tokens[at + by] : null;

  _Token take() => tokens[at++];

  /// Where the next token is, or the end.
  int here() => peek()?.at ?? end;

  bool done() => at >= tokens.length;
}

// ---- from: ----------------------------------------------------------------------------------------------------

const String _fromHelp = 'write notes, tickets or tasks first, then #tags, [[notebooks]], @people or "words"';

({QueryKind? kind, Source? source}) _readFrom(String value) {
  final reader = _Reader(_scan(value, true), value.length);
  QueryKind? kind;
  final first = reader.peek();
  if (first != null && first.kind == _T.word && _kinds.containsKey(first.text.toLowerCase())) {
    kind = _kinds[first.text.toLowerCase()];
    reader.take();
  }
  if (reader.done()) return (kind: kind, source: null);
  final source = _fromOr(reader);
  if (!reader.done()) {
    final left = reader.peek()!;
    throw _Trouble(left.at, left.kind == _T.close ? 'A bracket closes here that was never opened.' : '${_said(left.raw)} is left over: $_fromHelp.');
  }
  return (kind: kind, source: source);
}

Source _fromOr(_Reader reader) {
  final any = [_fromAnd(reader)];
  while (_isWord(reader.peek(), 'or')) {
    final or = reader.take();
    if (reader.done() || reader.peek()?.kind == _T.close) throw _Trouble(or.at, 'Something to read from is missing after ${_said(or.raw)}.');
    any.add(_fromAnd(reader));
  }
  return any.length == 1 ? any[0] : OrSource(any);
}

Source _fromAnd(_Reader reader) {
  final all = [_fromUnary(reader)];
  for (;;) {
    while (reader.peek()?.kind == _T.comma || _isWord(reader.peek(), 'and')) {
      reader.take();
    }
    final next = reader.peek();
    if (next == null || next.kind == _T.close || _isWord(next, 'or')) break;
    all.add(_fromUnary(reader));
  }
  return all.length == 1 ? all[0] : AndSource(all);
}

Source _fromUnary(_Reader reader) {
  final next = reader.peek();
  if (next == null) throw _Trouble(reader.end, 'Something to read from is missing here: $_fromHelp.');
  if (next.kind == _T.minus || _isWord(next, 'not')) {
    reader.take();
    return NotSource(_fromUnary(reader));
  }
  if (next.kind == _T.open) {
    reader.take();
    final inner = _fromOr(reader);
    if (reader.peek()?.kind != _T.close) throw _Trouble(next.at, 'A bracket opened here is never closed.');
    reader.take();
    return inner;
  }
  reader.take();
  if (next.kind == _T.tag) return TagSource(next.text);
  if (next.kind == _T.link) {
    if (next.text.isEmpty) throw _Trouble(next.at, 'A [[link]] here names no note.');
    return LinkSource(next.text);
  }
  if (next.kind == _T.person) return PersonSource(next.text);
  if (next.kind == _T.quoted) return WordsSource(next.text);
  if (next.kind == _T.word && _kinds.containsKey(next.text.toLowerCase())) {
    throw _Trouble(next.at, '${_said(next.raw)} goes first in from:, before the #tags, [[notebooks]], @people and "words".');
  }
  if (next.kind == _T.close) throw _Trouble(next.at, 'A bracket closes here that was never opened.');
  throw _Trouble(next.at, '${_said(next.raw)} isn’t something a query reads from: $_fromHelp.');
}

// ---- where: ---------------------------------------------------------------------------------------------------

Condition _readWhere(String value) {
  final reader = _Reader(_scan(value, false), value.length);
  final condition = _whereOr(reader);
  if (!reader.done()) {
    final left = reader.peek()!;
    throw _Trouble(left.at, left.kind == _T.close ? 'A bracket closes here that was never opened.' : '${_said(left.raw)} is left over: join two tests with and or or.');
  }
  return condition;
}

Condition _whereOr(_Reader reader) {
  final any = [_whereAnd(reader)];
  while (_isWord(reader.peek(), 'or')) {
    reader.take();
    any.add(_whereAnd(reader));
  }
  return any.length == 1 ? any[0] : OrCondition(any);
}

Condition _whereAnd(_Reader reader) {
  final all = [_whereUnary(reader)];
  while (_isWord(reader.peek(), 'and')) {
    reader.take();
    all.add(_whereUnary(reader));
  }
  return all.length == 1 ? all[0] : AndCondition(all);
}

Condition _whereUnary(_Reader reader) {
  final next = reader.peek();
  if (_isWord(next, 'not')) {
    reader.take();
    return NotCondition(_whereUnary(reader));
  }
  if (next?.kind == _T.open) {
    reader.take();
    final inner = _whereOr(reader);
    if (reader.peek()?.kind != _T.close) throw _Trouble(next!.at, 'A bracket opened here is never closed.');
    reader.take();
    return inner;
  }
  return _test(reader);
}

/// One test: a field, and what is asked of it.
Condition _test(_Reader reader) {
  final token = reader.peek();
  if (token == null || token.kind != _T.word || _keywords.contains(token.text.toLowerCase())) {
    throw _Trouble(reader.here(), 'A field is missing here, like status or due${token != null ? ', before ${_said(token.raw)}' : ''}.');
  }
  if (!_field.hasMatch(token.text)) throw _Trouble(token.at, '${_said(token.raw)} isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.');
  reader.take();
  final field = fieldName(token.text);
  final next = reader.peek();
  if (next == null || next.kind == _T.close || _isWord(next, 'and', 'or')) return Has(field);
  if (next.kind == _T.op) {
    reader.take();
    return Compare(field, Op.of(next.text), _literal(reader, '${token.raw} ${next.raw}'));
  }
  if (_isWord(next, 'is')) {
    reader.take();
    final negated = _isWord(reader.peek(), 'not');
    if (negated) reader.take();
    if (_isWord(reader.peek(), 'empty')) {
      reader.take();
      return EmptyTest(field, empty: !negated);
    }
    return Compare(field, negated ? Op.ne : Op.eq, _literal(reader, '${token.raw} is${negated ? ' not' : ''}'));
  }
  if (_isWord(next, 'contains', 'has', 'includes')) {
    reader.take();
    return Compare(field, Op.contains, _literal(reader, '${token.raw} ${next.raw}'));
  }
  if (_isWord(next, 'not') && _isWord(reader.peek(1), 'contains', 'has', 'includes')) {
    reader.take();
    final verb = reader.take();
    return Compare(field, Op.notContains, _literal(reader, '${token.raw} not ${verb.raw}'));
  }
  throw _Trouble(next.at, 'After ${_said(token.raw)}, a comparison: =, !=, <, >, contains, or is empty.');
}

final RegExp _today = RegExp(r'^today\s*(?:([+-])\s*(\d{1,5})\s*(d|days?|w|weeks?)?)?$', caseSensitive: false);
final RegExp _number = RegExp(r'^-?\d+(?:\.\d+)?$');
final RegExp _emptyWord = RegExp(r'^empty$', caseSensitive: false);
final RegExp _tomorrow = RegExp(r'^tomorrow$', caseSensitive: false);
final RegExp _yesterday = RegExp(r'^yesterday$', caseSensitive: false);
final RegExp _dayShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _weeks = RegExp(r'^w', caseSensitive: false);

bool _endsWords(_Token token) =>
    token.kind == _T.close || token.kind == _T.open || token.kind == _T.op || _isWord(token, 'and', 'or');

/// What a test compares with: quoted words, or the words up to the next `and`, `or` or bracket, read for what they
/// are.
Literal _literal(_Reader reader, String after) {
  final first = reader.peek();
  if (first == null || _endsWords(first)) {
    throw _Trouble(reader.here(), 'After ${_said(after)}, something to compare it with: a word, a number, a date or empty.');
  }
  if (first.kind == _T.quoted) {
    reader.take();
    return WordsLiteral(first.text, quoted: true);
  }
  final words = <_Token>[];
  for (var next = reader.peek(); next != null && !_endsWords(next) && next.kind != _T.quoted; next = reader.peek()) {
    words.add(reader.take());
  }
  final text = words.map((word) => word.raw).join(' ');
  if (_emptyWord.hasMatch(text)) return const EmptyLiteral();
  final today = _today.firstMatch(text);
  if (today != null) {
    final count = int.parse(today.group(2) ?? '0') * (_weeks.hasMatch(today.group(3) ?? '') ? 7 : 1);
    return TodayLiteral(today.group(1) == '-' ? -count : count, text);
  }
  if (_tomorrow.hasMatch(text)) return TodayLiteral(1, text);
  if (_yesterday.hasMatch(text)) return TodayLiteral(-1, text);
  if (_dayShape.hasMatch(text)) {
    if (!isIsoDay(text)) throw _Trouble(first.at, '${_said(text)} isn’t a day on the calendar.');
    return DateLiteral(text);
  }
  if (_number.hasMatch(text)) return NumberLiteral(double.parse(text), text);
  return WordsLiteral(text, quoted: false);
}

// ---- the lines ------------------------------------------------------------------------------------------------

const String _notAField = 'isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.';

/// A list of fields, `id, title, status`: each a name, in Dataview's form.
List<String> _fieldList(String value, int at) {
  final fields = <String>[];
  var offset = 0;
  for (final part in value.split(',')) {
    final name = jsTrim(part);
    if (name.isNotEmpty) {
      final key = fieldName(name);
      if (!_field.hasMatch(key)) throw _Trouble(at + offset + part.indexOf(name), '${_said(name)} $_notAField');
      fields.add(key);
    }
    offset += part.length + 1;
  }
  return fields;
}

const Set<String> _ascending = {'asc', 'ascending', 'up'};
const Set<String> _descending = {'desc', 'descending', 'down', 'reverse', 'reversed'};
final RegExp _by = RegExp(r'^by\s+', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

List<SortKey> _sortList(String value) {
  final keys = <SortKey>[];
  var offset = 0;
  for (final part in value.split(',')) {
    final words = jsTrim(part).replaceFirst(_by, '').split(_spaces).where((word) => word.isNotEmpty).toList();
    if (words.isNotEmpty) {
      final last = words.last.toLowerCase();
      final way = words.length > 1 && (_ascending.contains(last) || _descending.contains(last)) ? words.removeLast().toLowerCase() : null;
      final name = words.join(' ');
      final key = fieldName(name);
      if (!_field.hasMatch(key)) {
        final where = offset + part.indexOf(words.last);
        throw _Trouble(where, words.length > 1 ? '${_said(words.last)} isn’t a way to sort: write asc or desc after the field.' : '${_said(name)} $_notAField');
      }
      keys.add(SortKey(key, desc: way != null && _descending.contains(way)));
    }
    offset += part.length + 1;
  }
  return keys;
}

/// The distance from one word to another, in letters changed, added or taken away: for "did you mean".
int _distance(String one, String two) {
  final row = List<int>.generate(two.length + 1, (i) => i);
  for (var i = 1; i <= one.length; i += 1) {
    var previous = row[0];
    row[0] = i;
    for (var j = 1; j <= two.length; j += 1) {
      final kept = row[j];
      final change = previous + (one.codeUnitAt(i - 1) == two.codeUnitAt(j - 1) ? 0 : 1);
      var least = row[j] + 1;
      if (row[j - 1] + 1 < least) least = row[j - 1] + 1;
      if (change < least) least = change;
      row[j] = least;
      previous = kept;
    }
  }
  return row[two.length];
}

// ---- a view's own lines -------------------------------------------------------------------------------------------

/// One field, as `group:` takes it: `by` before it is read and left out.
String? _oneField(String value, String clause) {
  final words = value.replaceFirst(_by, '');
  final fields = _fieldList(words, value.length - words.length);
  if (fields.length > 1 || _hasSpace.hasMatch(jsTrim(words))) throw _Trouble(0, '$clause: is one field, like ${clause == 'date' ? 'due' : (clause == 'x' || clause == 'series' ? 'status' : 'start')}.');
  return fields.isEmpty ? null : fields[0];
}

final RegExp _measure = RegExp(r'^([A-Za-z]+)\s*(?:\((.*)\))?$');

/// `count`, `sum(hours)`, or a field alone, which is its sum: a chart's `y:`.
Measure _readMeasure(String value) {
  final found = _measure.firstMatch(jsTrim(value));
  final word = found?.group(1)?.toLowerCase();
  final fn = word == null ? null : _aggregates[word];
  if (found != null && fn != null) {
    final inner = jsTrim(found.group(2) ?? '');
    if (inner.isEmpty) {
      if (fn == Aggregate.count || fn == Aggregate.percent) return Measure(fn);
      throw _Trouble(0, '${_said(word!)} needs a field to work out, like $word(hours).');
    }
    final key = fieldName(inner);
    if (!_field.hasMatch(key)) throw _Trouble(value.indexOf(inner), '${_said(inner)} $_notAField');
    return Measure(fn, key);
  }
  final key = fieldName(jsTrim(value));
  if (_field.hasMatch(key) && !_hasSpace.hasMatch(jsTrim(value)) && !value.contains('(')) return Measure(Aggregate.sum, key);
  throw const _Trouble(0, 'y: is count, or sum, average, min, max or percent of a field, like sum(hours).');
}

final RegExp _rollupLine = RegExp(r'^([\p{L}\p{N}_][\p{L}\p{N}_./-]*)\s*=\s*([A-Za-z]+)\s*\((.*)\)\s*$', unicode: true);
final RegExp _rollupWhere = RegExp(r'\s+where\s+', caseSensitive: false);
final RegExp _rollupOf = RegExp(r'^(\S+)\s+of\s+(.+)$', caseSensitive: false);
const String _rollupHelp = 'a rollup is a name, =, and what it works out over linked notes, like open = count(links where status != done)';

/// `open = count(links where status != done)`, `hours = sum(hours of backlinks)`, `done = percent(tasks)`,
/// `spent = sum(hours of backlinks.project)`: a name, a measure, `field of` the notes it is worked out over, and a
/// `where:` of their own.
Rollup _readRollup(String value) {
  final found = _rollupLine.firstMatch(value);
  if (found == null) throw const _Trouble(0, 'This isn’t a rollup: $_rollupHelp.');
  final name = fieldName(found.group(1)!);
  final word = found.group(2)!.toLowerCase();
  final fn = _aggregates[word];
  final innerAt = value.indexOf('(', found.group(1)!.length) + 1;
  if (fn == null) throw _Trouble(value.indexOf(found.group(2)!, found.group(1)!.length), '${_said(found.group(2)!)} isn’t something a rollup works out: count, sum, average, min, max or percent.');
  final inner = found.group(3)!;
  final cut = _rollupWhere.firstMatch(inner);
  final head = jsTrim(cut == null ? inner : inner.substring(0, cut.start));
  Condition? where;
  if (cut != null) {
    final condition = inner.substring(cut.end);
    try {
      where = _readWhere(condition);
    } on _Trouble catch (trouble) {
      throw _Trouble(innerAt + cut.end + trouble.at, trouble.message);
    }
  }
  final of = _rollupOf.firstMatch(head);
  final field = of == null ? null : fieldName(of.group(1)!);
  if (field != null && !_field.hasMatch(field)) throw _Trouble(innerAt, '${_said(of!.group(1)!)} $_notAField');
  final path = jsTrim(of == null ? head : of.group(2)!).toLowerCase();
  if (fn != Aggregate.count && fn != Aggregate.percent && field == null) throw _Trouble(innerAt, '$word( ) needs a field of the notes, like $word(hours of links).');
  final RollupWay way;
  String? through;
  if (path == 'links' || path == 'link' || path == 'linked') {
    way = RollupWay.links;
  } else if (path == 'backlinks' || path == 'backlink' || path == 'linked from') {
    way = RollupWay.backlinks;
  } else if (path == 'tasks' || path == 'todos' || path == 'to-dos') {
    way = RollupWay.tasks;
  } else if (path.startsWith('backlinks.')) {
    way = RollupWay.backRelation;
    through = fieldName(path.substring('backlinks.'.length));
  } else {
    way = RollupWay.relation;
    through = fieldName(path);
  }
  if (path.isEmpty || (through != null && !_field.hasMatch(through))) throw _Trouble(innerAt, 'Which notes to work it out over is missing: links, backlinks, tasks, or a field that links, like project.');
  return Rollup(name: name, measure: Measure(fn, field), way: way, through: through, where: where);
}

/// A line a query has: its name, a colon, and what it says.
final RegExp _line = RegExp(r'^(\s*)([^:]*?)\s*:(\s*)(.*?)\s*$');
final RegExp _lead = RegExp(r'^\s*');
final RegExp _lineName = RegExp(r'^[A-Za-z][A-Za-z ]*$');
final RegExp _limit = RegExp(r'^\d{1,6}$');
final RegExp _hasSpace = RegExp(r'\s');

/// A fence's body read as a query, or the first problem with it.
Reading readQuery(String body) {
  var kind = QueryKind.notes;
  Source? from;
  var sort = const <SortKey>[];
  String? group;
  ShowAs? show;
  var columns = const <String>[];
  var total = const <String>[];
  int? limit;
  String? date, start, end, x, series;
  TimelineZoom? zoom;
  ChartKind? chart;
  Measure? y;
  PlanView? plan;
  String? cycle;
  final rollups = <Rollup>[];
  final seen = <String, int>{};
  final wheres = <Condition>[];
  final lines = body.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final text = lines[index];
    if (jsTrim(text).isEmpty) continue;
    final line = index + 1;
    Reading problem(int column, String message) => Reading.unread(QueryProblem(line: line, column: column, message: message));
    final found = _line.firstMatch(text);
    final lead = _lead.firstMatch(text)!.group(0)!.length;
    final written = found?.group(2) ?? '';
    if (found == null || !_lineName.hasMatch(written)) {
      if (found != null && written.isNotEmpty) {
        final lower = written.toLowerCase();
        for (final name in _nearLines) {
          if (_distance(name, lower) <= 2) return problem(lead + 1, '${_said(written)} isn’t a line a query has: did you mean ${_said(name)}?');
        }
      }
      return problem(lead + 1, 'A query’s line is a name, a colon and what it says, like “where: status != Done”.');
    }
    final name = written.toLowerCase().replaceAll(_spaces, ' ');
    final clause = _clauses[name];
    if (clause == null) {
      String? near;
      for (final each in _nearLines) {
        if (name.length > 2 && _distance(each, name) <= 2) {
          near = each;
          break;
        }
      }
      return problem(
        lead + 1,
        near != null
            ? '${_said(written)} isn’t a line a query has: did you mean ${_said(near)}?'
            : '${_said(written)} isn’t a line a query has: it has from, where, sort, group, show, columns, total, limit and rollup, and a view’s date, start, end, zoom, chart, x, y and series.',
      );
    }
    if (clause != 'where' && clause != 'rollup' && seen.containsKey(clause)) return problem(lead + 1, '${_said('$clause:')} is written twice: a query has one, on line ${seen[clause]}.');
    seen[clause] = line;
    final value = found.group(4) ?? '';
    // Where the value starts in the line, counting from 0, for a problem's column.
    final before = (found.group(1) ?? '').length + written.length;
    final valueAt = before + (text.substring(before).indexOf(':') + 1) + (found.group(3) ?? '').length;
    if (value.isEmpty) continue;
    try {
      switch (clause) {
        case 'from':
          final read = _readFrom(value);
          if (read.kind != null) kind = read.kind!;
          from = read.source;
        case 'where':
          wheres.add(_readWhere(value));
        case 'sort':
          sort = _sortList(value);
        case 'group':
          final words = value.replaceFirst(_by, '');
          final fields = _fieldList(words, value.length - words.length);
          if (fields.length > 1 || _hasSpace.hasMatch(jsTrim(words))) throw const _Trouble(0, 'A query groups by one field, like status.');
          group = fields.isEmpty ? null : fields[0];
        case 'show':
          final way = value.toLowerCase();
          ShowAs? as;
          // A planning view is a chart or a timeline of its own (lib/core/query/planning.dart).
          final planned = PlanView.values.where((each) => each.name == way).firstOrNull;
          if (planned != null) {
            plan = planned;
            as = planned == PlanView.roadmap ? ShowAs.timeline : ShowAs.chart;
          }
          for (final each in ShowAs.values) {
            if (each.name == way) as = each;
          }
          as ??= _showAlso[way];
          if (as == null) throw _Trouble(0, '${_said(value)} isn’t a way to show a query: table, list, board, calendar, timeline, chart, gantt or count.');
          show = as;
        case 'date':
          date = _oneField(value, 'date');
        case 'start':
          start = _oneField(value, 'start');
        case 'end':
          end = _oneField(value, 'end');
        case 'x':
          x = _oneField(value, 'x');
        case 'series':
          series = _oneField(value, 'series');
        case 'zoom':
          final way = value.toLowerCase();
          zoom = TimelineZoom.values.where((each) => each.name == way || '${each.name}s' == way).firstOrNull;
          if (zoom == null) throw _Trouble(0, '${_said(value)} isn’t a zoom: week, month or quarter.');
        case 'chart':
          final planned = const {'burndown': PlanView.burndown, 'velocity': PlanView.velocity}[value.toLowerCase()];
          if (planned != null) {
            plan = planned;
          } else {
            chart = _chartWords[value.toLowerCase()];
            if (chart == null) throw _Trouble(0, '${_said(value)} isn’t a chart: bar, line, pie, burndown or velocity.');
          }
        case 'cycle':
          cycle = jsTrim(value);
        case 'y':
          y = _readMeasure(value);
        case 'rollup':
          final rollup = _readRollup(value);
          if (rollups.any((each) => each.name == rollup.name)) throw _Trouble(0, 'A rollup called ${_said(rollup.name)} is written twice.');
          rollups.add(rollup);
        case 'columns':
          columns = _fieldList(value, 0);
        case 'total':
          total = _fieldList(value, 0);
        case 'limit':
          if (!_limit.hasMatch(value) || int.parse(value) < 1) throw const _Trouble(0, 'A limit is a whole number, like 20.');
          limit = int.parse(value);
      }
    } on _Trouble catch (trouble) {
      return problem(valueAt + trouble.at + 1, trouble.message);
    }
  }
  final where = wheres.isEmpty ? null : (wheres.length == 1 ? wheres[0] : AndCondition(wheres));
  return Reading.read(Query(
    kind: kind,
    from: from,
    where: where,
    sort: sort,
    group: group,
    show: show,
    columns: columns,
    total: total,
    limit: limit,
    date: date,
    start: start,
    end: end,
    zoom: zoom,
    chart: chart,
    x: x,
    y: y,
    series: series,
    rollups: rollups,
    plan: plan,
    cycle: cycle,
  ));
}

/// Every field a condition names, for what a query's defaults hang on: a tasks query reads the open ones unless its
/// `where:` says something about whether they are done.
Set<String> fieldsNamed(Condition? condition) {
  final names = <String>{};
  void walk(Condition each) {
    switch (each) {
      case AndCondition(:final all):
        all.forEach(walk);
      case OrCondition(:final any):
        any.forEach(walk);
      case NotCondition(:final of):
        walk(of);
      case Compare(:final field) || EmptyTest(:final field) || Has(:final field):
        names.add(field);
    }
  }

  if (condition != null) walk(condition);
  return names;
}
