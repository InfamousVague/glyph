/// A query written back as its fence's lines: what read.dart reads, the other way (the port's own, 2026-10-30). Every
/// clause a [Query] has is one line, in the order docs/QUERIES.md teaches them, each left out where it says the
/// default, so `readQuery(queryText(query))` reads the query it was written from (test/query/write_test.dart holds
/// that for every query the web's fixtures read). The builder and the view switcher still change one line at a time
/// (fence.dart `withClause`), which keeps a person's own spacing and order; this is for a fence made whole, and what
/// a round trip is held to.
///
/// What is written is the plain grammar: a `from:` its kind and its sources (`#tag`, `[[note]]`, `@person`,
/// `"words"`, `not`, `or` and brackets where an `or` sits inside an `and`), a `where:` its tests, a value in quotes
/// where it was quoted, and each view's own line (`date:`, `start:`, `end:`, `zoom:`, `chart:`, `x:`, `y:`,
/// `series:`) and each `rollup:` as read.dart reads them. Pure.
library;

import 'read.dart';

const Map<QueryKind, String> _kindWord = {QueryKind.notes: 'notes', QueryKind.tickets: 'tickets', QueryKind.tasks: 'tasks', QueryKind.events: 'events'};

/// Words in quotes, with a pair that can hold them: a double quote closes on either double quote, a single one on
/// either single one (read.dart's `_quotes`).
String _quoted(String words) {
  if (!words.contains('"') && !words.contains('”')) return '"$words"';
  return '‘$words’';
}

/// A source as `from:` writes it; [inside] is an `and`'s, where an `or` takes brackets.
String _source(Source source, {bool inside = false}) => switch (source) {
      TagSource(:final tag) => '#$tag',
      LinkSource(:final title) => '[[$title]]',
      PersonSource(:final name) => '@$name',
      WordsSource(:final words) => _quoted(words),
      NotSource(:final of) => 'not ${_source(of, inside: true)}',
      AndSource(:final all) => () {
          final words = all.map((each) => _source(each, inside: true)).join(' ');
          return inside ? '($words)' : words;
        }(),
      OrSource(:final any) => () {
          final words = any.map((each) => _source(each, inside: true)).join(' or ');
          return inside ? '($words)' : words;
        }(),
    };

/// A literal as a test writes it.
String _literal(Literal literal) => switch (literal) {
      NumberLiteral(:final text) => text,
      WordsLiteral(:final text, :final quoted) => quoted ? _quoted(text) : text,
      TodayLiteral(:final text) => text,
      DateLiteral(:final day) => day,
      EmptyLiteral() => 'empty',
    };

/// A test, or tests joined, as `where:` writes them; [inside] says whether an `or` or an `and` takes brackets.
String conditionText(Condition condition, {int inside = 0}) {
  switch (condition) {
    case Compare(:final field, :final op, :final value):
      final sign = switch (op) {
        Op.contains => 'contains',
        Op.notContains => 'not contains',
        _ => op.sign,
      };
      return '$field $sign ${_literal(value)}';
    case EmptyTest(:final field, :final empty):
      return '$field is ${empty ? '' : 'not '}empty';
    case Has(:final field):
      return field;
    case NotCondition(:final of):
      return 'not ${conditionText(of, inside: 2)}';
    case AndCondition(:final all):
      // An `and` inside an `and` was bracketed to be one: it is written so again.
      final words = all.map((each) => conditionText(each, inside: each is AndCondition ? 2 : 1)).join(' and ');
      return inside >= 2 ? '($words)' : words;
    case OrCondition(:final any):
      final words = any.map((each) => conditionText(each, inside: each is OrCondition ? 1 : 0)).join(' or ');
      return inside >= 1 ? '($words)' : words;
  }
}

/// A rollup as its line says it: `open = count(links where status != Done)`.
String rollupText(Rollup rollup) {
  final path = switch (rollup.way) {
    RollupWay.links => 'links',
    RollupWay.backlinks => 'backlinks',
    RollupWay.tasks => 'tasks',
    RollupWay.relation => rollup.through ?? '',
    RollupWay.backRelation => 'backlinks.${rollup.through ?? ''}',
  };
  final field = rollup.measure.field;
  final where = rollup.where;
  return '${rollup.name} = ${rollup.measure.fn.name}(${field == null ? '' : '$field of '}$path${where == null ? '' : ' where ${conditionText(where)}'})';
}

/// [query] as the lines of its fence, one clause to a line.
String queryText(Query query) {
  final lines = <String>[];
  final from = query.from;
  if (from != null || query.kind != QueryKind.notes) {
    lines.add('from: ${[if (query.kind != QueryKind.notes || from == null) _kindWord[query.kind]!, if (from != null) _source(from)].join(' ')}');
  }
  final where = query.where;
  if (where != null) lines.add('where: ${conditionText(where)}');
  if (query.sort.isNotEmpty) lines.add('sort: ${[for (final key in query.sort) key.desc ? '${key.field} desc' : key.field].join(', ')}');
  if (query.group != null) lines.add('group: ${query.group}');
  if (query.show != null) lines.add('show: ${query.show!.name}');
  if (query.date != null) lines.add('date: ${query.date}');
  if (query.start != null) lines.add('start: ${query.start}');
  if (query.end != null) lines.add('end: ${query.end}');
  if (query.zoom != null) lines.add('zoom: ${query.zoom!.name}');
  if (query.chart != null) lines.add('chart: ${query.chart!.name}');
  if (query.x != null) lines.add('x: ${query.x}');
  if (query.y != null) lines.add('y: ${query.y!.written}');
  if (query.series != null) lines.add('series: ${query.series}');
  if (query.columns.isNotEmpty) lines.add('columns: ${query.columns.join(', ')}');
  if (query.total.isNotEmpty) lines.add('total: ${query.total.join(', ')}');
  for (final rollup in query.rollups) {
    lines.add('rollup: ${rollupText(rollup)}');
  }
  if (query.limit != null) lines.add('limit: ${query.limit}');
  return lines.join('\n');
}
