/// A GFM table's source, read and grown: the pure half of `src/app/editor/tables.ts`.
///
/// A GFM table in a note is rows of pipes and dashes, which is how it is kept and how it is edited, but not how
/// anyone wants to read it on a phone. So a table the caret is not in is drawn as a real table; that drawing (the
/// widget, its field, its theme) is the view's piece (docs/STAGE4.md, G), and reads the table through what is here:
/// [parseTable], the cells' own places ([cellSpans]), a cell's words without their markup ([plainCell]), and the two
/// edits its + buttons make ([addTableColumn], [addTableRow]).
///
/// What differs: `Parsed` is [ParsedTable] and an alignment a [TableAlign]; `plainCell` and `cellSpans`, private
/// to the web's file because the widget lives in it, are public here for the widget that will live elsewhere.
library;

import '../../core/item_syntax.dart' show jsTrim;

/// How a column is aligned by its divider cell: `:--`, `:-:`, `--:`.
enum TableAlign { left, center, right }

/// A table as its drawing needs it (`Parsed`).
class ParsedTable {
  const ParsedTable({required this.header, required this.align, required this.rows});

  final List<String> header;

  /// One per divider cell; null where the divider says nothing.
  final List<TableAlign?> align;

  /// Every row as wide as the header: short rows filled with empty cells, long ones cut.
  final List<List<String>> rows;
}

/// The cells of one table line: split on unescaped pipes, the outer ones dropped.
List<String> _cellsOfLine(String line) {
  final cells = <String>[];
  var current = StringBuffer();
  for (var i = 0; i < line.length; i += 1) {
    final ch = line[i];
    if (ch == r'\' && i + 1 < line.length && line[i + 1] == '|') {
      current.write('|');
      i += 1;
    } else if (ch == '|') {
      cells.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(ch);
    }
  }
  cells.add(current.toString());
  final trimmed = jsTrim(line);
  if (trimmed.startsWith('|')) cells.removeAt(0);
  if (trimmed.endsWith('|') && !trimmed.endsWith(r'\|')) cells.removeLast();
  return <String>[for (final cell in cells) jsTrim(cell)];
}

final RegExp _dividerCell = RegExp(r'^:?-+:?$');

/// A table's text as its header, alignment and rows; null when it has no divider line under its header.
ParsedTable? parseTable(String text) {
  final lines = <String>[
    for (final line in text.split('\n'))
      if (jsTrim(line).isNotEmpty) line,
  ];
  if (lines.length < 2) return null;
  final header = _cellsOfLine(lines[0]);
  final divider = _cellsOfLine(lines[1]);
  if (!divider.every(_dividerCell.hasMatch)) return null;
  final align = <TableAlign?>[
    for (final cell in divider)
      cell.startsWith(':') && cell.endsWith(':')
          ? TableAlign.center
          : cell.endsWith(':')
          ? TableAlign.right
          : cell.startsWith(':')
          ? TableAlign.left
          : null,
  ];
  final rows = <List<String>>[
    for (final line in lines.skip(2))
      () {
        final cells = _cellsOfLine(line);
        return <String>[for (var i = 0; i < header.length; i += 1) i < cells.length ? cells[i] : ''];
      }(),
  ];
  return ParsedTable(header: header, align: align, rows: rows);
}

final RegExp _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final RegExp _strong = RegExp(r'(\*\*|__)(.+?)\1');
final RegExp _emphasis = RegExp(r'(\*|_)(.+?)\1');
final RegExp _code = RegExp(r'`([^`]+)`');

/// A cell's words without the markup that would show as symbols: bold, italics, code ticks, link targets.
String plainCell(String text) => text
    .replaceAllMapped(_link, (m) => m.group(1)!)
    .replaceAllMapped(_strong, (m) => m.group(2)!)
    .replaceAllMapped(_emphasis, (m) => m.group(2)!)
    .replaceAllMapped(_code, (m) => m.group(1)!);

final RegExp _pipe = RegExp(r'(?<!\\)\|');
final RegExp _leadingSpace = RegExp(r'^\s+');

/// Where each cell of a table's text starts in it, by line and column: the raw words a blank or a fill is drawn
/// from. Blank lines have no row.
List<List<({String raw, int at})>> cellSpans(String text) {
  final out = <List<({String raw, int at})>>[];
  var lineAt = 0;
  for (final line in text.split('\n')) {
    final row = <({String raw, int at})>[];
    final trimmed = jsTrim(line);
    if (trimmed.isNotEmpty) {
      final pipes = <int>[for (final m in _pipe.allMatches(line)) m.start];
      final edges = trimmed.startsWith('|') ? pipes : <int>[-1, ...pipes];
      if (!trimmed.endsWith('|') || trimmed.endsWith(r'\|')) edges.add(line.length);
      for (var i = 0; i + 1 < edges.length; i += 1) {
        final start = edges[i] + 1;
        final cell = line.substring(start, edges[i + 1]);
        final lead = cell.length - cell.replaceFirst(_leadingSpace, '').length;
        row.add((raw: jsTrim(cell), at: lineAt + start + lead));
      }
      out.add(row);
    }
    lineAt += line.length + 1;
  }
  return out;
}

final RegExp _trailingSpace = RegExp(r'\s+$');
final RegExp _closingPipe = RegExp(r'(?<!\\)\|\s*$');

/// A cell appended to a table line, before its trailing pipe where it has one, so `| a | b |` grows by one cell.
String _appendCell(String line, String cell) {
  final end = line.replaceFirst(_trailingSpace, '');
  return _closingPipe.hasMatch(end) ? '$end $cell |' : '$end | $cell';
}

/// A table's source with one more column: a heading on the header row, dashes on the divider, and an empty cell on
/// every body row (the + column button on a drawn table). Blank lines are left as they are.
String addTableColumn(String text) {
  var body = 0;
  return text
      .split('\n')
      .map((line) {
        if (jsTrim(line).isEmpty) return line;
        body += 1;
        return _appendCell(
          line,
          body == 1
              ? 'Column'
              : body == 2
              ? '---'
              : '',
        );
      })
      .join('\n');
}

/// A table's source with one more row: an empty row, as wide as its header, after its last row (the + row button on
/// a drawn table). Its cells are left empty for the words to be typed in.
String addTableRow(String text) {
  final lines = text.split('\n');
  final cells = _cellsOfLine(lines[0]).length;
  final columns = cells < 1 ? 1 : cells;
  final row = '| ${List<String>.filled(columns, '').join(' | ')} |';
  var last = lines.length - 1;
  while (last > 0 && jsTrim(lines[last]).isEmpty) {
    last -= 1;
  }
  lines.insert(last + 1, row);
  return lines.join('\n');
}
