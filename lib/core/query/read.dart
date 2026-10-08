/// A query's lines, read: the grammar of a ```query fence, and the one plain sentence that says what is wrong with
/// one that cannot be read, and where (../glyph docs/QUERIES.md is the grammar written down; docs/DESIGN.md §159 why
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
///     show:     table, list, board, calendar, gantt or count
///     columns:  the fields a table shows, and a list and a board say beside each record
///     total:    the fields to add up
///     limit:    how many records at most
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

/// What the records are (`QueryKind`).
enum QueryKind { notes, tickets, tasks }

/// The ways a query is shown, in the order docs/QUERIES.md teaches them (`SHOWS`, `ShowAs`).
enum ShowAs { table, list, board, calendar, gantt, count }

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
  const Query({this.kind = QueryKind.notes, this.from, this.where, this.sort = const [], this.group, this.show, this.columns = const [], this.total = const [], this.limit});

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
};

/// The names, as a sentence lists them (`QUERY_LINES`).
const List<String> queryLines = ['from', 'where', 'sort', 'group', 'show', 'columns', 'total', 'limit'];

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
};

/// Another way of saying a way to show, read as that way.
const Map<String, ShowAs> _showAlso = {'kanban': ShowAs.board, 'timeline': ShowAs.gantt, 'number': ShowAs.count, 'cards': ShowAs.board};

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
        for (final name in queryLines) {
          if (_distance(name, lower) <= 2) return problem(lead + 1, '${_said(written)} isn’t a line a query has: did you mean ${_said(name)}?');
        }
      }
      return problem(lead + 1, 'A query’s line is a name, a colon and what it says, like “where: status != Done”.');
    }
    final name = written.toLowerCase().replaceAll(_spaces, ' ');
    final clause = _clauses[name];
    if (clause == null) {
      String? near;
      for (final each in queryLines) {
        if (name.length > 2 && _distance(each, name) <= 2) {
          near = each;
          break;
        }
      }
      return problem(
        lead + 1,
        near != null
            ? '${_said(written)} isn’t a line a query has: did you mean ${_said(near)}?'
            : '${_said(written)} isn’t a line a query has: it has from, where, sort, group, show, columns, total and limit.',
      );
    }
    if (clause != 'where' && seen.containsKey(clause)) return problem(lead + 1, '${_said('$clause:')} is written twice: a query has one, on line ${seen[clause]}.');
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
          for (final each in ShowAs.values) {
            if (each.name == way) as = each;
          }
          as ??= _showAlso[way];
          if (as == null) throw _Trouble(0, '${_said(value)} isn’t a way to show a query: table, list, board, calendar, gantt or count.');
          show = as;
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
  return Reading.read(Query(kind: kind, from: from, where: where, sort: sort, group: group, show: show, columns: columns, total: total, limit: limit));
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
