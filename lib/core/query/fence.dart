/// Where each ```query fence in a note is, and what it says (../glyph docs/QUERIES.md, docs/DESIGN.md §159): the
/// editor draws each as its result, and nothing else in a note is a query. A port of `src/app/core/query/fence.ts`.
/// A fence is ```query or ~~~query and nothing more on its line but its settings (`height=18`, as a board's), closed
/// by a fence of the same character at least as long; one never closed is not drawn, since everything after it is
/// still being typed. Found as a diagram's fence is, so the two never disagree about where a fence ends. Pure.
///
/// What differs: a height is a `double`, written into a fence as the page writes a number (`20`, `31.5`), as
/// boards/fence.dart does a board's.
library;

import '../boards/fence.dart' show clampHeight;
import '../item_syntax.dart' show jsTrim;
import 'read.dart' show QueryData, ShowAs, jsonNumber;

class QueryFence extends QueryData {
  const QueryFence({required this.from, required this.to, required this.body, required this.height});

  /// The line the opening fence is on, counting from 1.
  final int from;

  /// The line the closing fence is on.
  final int to;

  /// The lines between: the query itself.
  final String body;

  /// How tall a board's lanes are set, in their own ems; null for the board's own height.
  final double? height;

  @override
  Object? toJson() => {'from': from, 'to': to, 'body': body, 'height': height == null ? null : jsonNumber(height!)};
}

/// The fence that opens a query, and its settings: `name=value` words after the word, which any other renderer takes
/// as part of the block's info string. Other words after it are another kind of block.
final RegExp _open = RegExp(r'^\s*(`{3,}|~{3,})\s*query((?:\s+[a-z]+=\S+)*)\s*$', caseSensitive: false);

/// `height=18`: how tall a query drawn as a board is, in its lanes' ems, set by the line under it as a ```board's is
/// (Matt: "The swimlanes are maximum height on the query instead of acting like board view with the split view
/// handle").
final RegExp _height = RegExp(r'(?:^|\s)height=(\d+(?:\.\d+)?)(?:em)?(?=\s|$)', caseSensitive: false);
final RegExp _openStart = RegExp(r'^\s*(?:`{3,}|~{3,})\s*query', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

/// Every closed query fence in [doc], in order.
List<QueryFence> queryFencesIn(String doc) {
  final lines = doc.split('\n');
  final found = <QueryFence>[];
  for (var i = 0; i < lines.length; i += 1) {
    final open = _open.firstMatch(lines[i]);
    if (open == null) continue;
    final fence = open.group(1) ?? '```';
    final close = RegExp('^\\s*${fence[0] == '~' ? '~' : '`'}{${fence.length},}\\s*\$');
    var end = -1;
    for (var j = i + 1; j < lines.length; j += 1) {
      if (close.hasMatch(lines[j])) {
        end = j;
        break;
      }
    }
    if (end < 0) break;
    final written = _height.firstMatch(open.group(2) ?? '')?.group(1);
    final height = written == null ? double.nan : (double.tryParse(written) ?? double.nan);
    found.add(QueryFence(from: i + 1, to: end + 1, body: lines.sublist(i + 1, end).join('\n'), height: height.isFinite ? clampHeight(height) : null));
    i = end;
  }
  return found;
}

/// A number as the page writes one: a whole one without its `.0`.
String _number(double value) => value.isFinite && value == value.truncateToDouble() ? value.toStringAsFixed(0) : value.toString();

/// A query's opening fence with its board's height set, or taken off with null: the fence, the word and any other
/// settings as they were. A line that does not open a query comes back as it is.
String withQueryHeight(String openLine, num? height) {
  final open = _open.firstMatch(openLine);
  if (open == null) return openLine;
  final start = _openStart.firstMatch(openLine)?.group(0) ?? '${open.group(1)}query';
  final rest = jsTrim((open.group(2) ?? '').replaceFirst(_height, ' ').replaceAll(_spaces, ' '));
  final settings = [height == null ? '' : 'height=${_number(clampHeight(height))}', rest].where((part) => part.isNotEmpty).join(' ');
  return '$start${settings.isNotEmpty ? ' $settings' : ''}';
}

/// A query line for a clause, however it is spaced: `(indent)(name)(space):(space)(value)`.
RegExp _clauseLine(String clause) => RegExp('^(\\s*)($clause)(\\s*):(\\s*)(.*)\$', caseSensitive: false);

/// A clause's value in the body (`from`, `where`, `group`, `show`…), trimmed; null where the clause has no line.
String? clauseValue(String body, String clause) {
  final re = _clauseLine(clause);
  for (final line in body.split('\n')) {
    final found = re.firstMatch(line);
    if (found != null) return jsTrim(found.group(5) ?? '');
  }
  return null;
}

/// A query's body with one clause set, removed (null), or added: the first line for the clause has its value
/// replaced with its spacing left as it was, null takes the line out, and a clause with no line gets one at the end.
/// The keyword is written lower case, as docs/QUERIES.md teaches. Pure; this is how the view switcher and the
/// builder change a drawn query without the person learning the grammar.
String withClause(String body, String clause, String? value) {
  final re = _clauseLine(clause);
  final next = <String>[];
  var set = false;
  for (final line in body.split('\n')) {
    final found = set ? null : re.firstMatch(line);
    if (found == null) {
      next.add(line);
      continue;
    }
    set = true;
    if (value != null) next.add('${found.group(1)}$clause${found.group(3)}:${found.group(4)}$value');
  }
  if (!set && value != null) next.add('$clause: $value');
  return next.join('\n');
}

/// A query's body with `show:` set, for the view switcher: a list becomes a board or a table with from: and where:
/// kept.
String withShow(String body, ShowAs show) => withClause(body, 'show', show.name);

final RegExp _trailing = RegExp(r'\s+$');

/// A query fence with [body] in it, as the + writes one: three backticks, the word, the lines, three backticks.
String queryFence(String body) => ['```query', body.replaceFirst(_trailing, ''), '```'].join('\n');
