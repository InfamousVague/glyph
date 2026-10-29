/// A GFM table's source, read and grown: the pure half of `src/app/editor/tables.ts`.
///
/// A GFM table in a note is rows of pipes and dashes, which is how it is kept and how it is edited, but not how
/// anyone wants to read it on a phone. So a table the caret is not in is drawn as a real table; that drawing (the
/// widget, its field, its theme) is the view's piece (docs/STAGE4.md, G), and reads the table through what is here:
/// [parseTable], the cells' own places ([cellSpans]), a cell's words without their markup ([plainCell]) and the links
/// among them ([readCell]), and the two edits its + buttons make ([addTableColumn], [addTableRow]).
///
/// What differs: `Parsed` is [ParsedTable] and an alignment a [TableAlign]; `plainCell` and `cellSpans`, private
/// to the web's file because the widget lives in it, are public here for the widget that will live elsewhere.
library;

import 'package:flutter/foundation.dart' show immutable;

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

/// A link in a cell's words as they are drawn ([readCell]): where its words stand in [plainCell]'s text, and what
/// a tap on them opens. A web address ([url]) or, put there by the drawing, a note by its title ([title]).
@immutable
class CellLink {
  const CellLink({required this.from, required this.to, this.url, this.bare = false, this.title, this.anchor, this.waiting = false});

  /// Where its words start and end in the cell's drawn text.
  final int from;
  final int to;

  /// The address a `[words](address)` or a bare `https://…` opens.
  final String? url;

  /// Whether it is an address said bare, which a paragraph draws in the address's own look, not the link's.
  final bool bare;

  /// The note a `[[Title]]` opens, and what followed its `#`.
  final String? title;
  final String? anchor;

  /// Whether no note has that title yet: drawn as a name waiting to be written.
  final bool waiting;

  @override
  bool operator ==(Object other) => other is CellLink && other.from == from && other.to == to && other.url == url && other.bare == bare && other.title == title && other.anchor == anchor && other.waiting == waiting;

  @override
  int get hashCode => Object.hash(from, to, url, bare, title, anchor, waiting);

  @override
  String toString() => 'CellLink($from-$to, ${url ?? '[[$title]]'})';
}

/// A web address said bare, as the note's own parser finds one (GFM's autolinks): `http://` or `https://` and up
/// to the next space or `<`, without the punctuation that ends a sentence after it.
final RegExp _bareUrl = RegExp(r'https?:\/\/[^\s<]+');
final RegExp _bareTail = RegExp(r'''[.,;:!?'"*_~]+$''');

// What stands round a link's words while the cell's marks are taken off, so the words can be found after.
const String _open = '', _close = '';

/// A cell's words as [plainCell] draws them, and the links among them: a `[words](address)`'s words and an
/// address said bare (Matt, 2026-10-29: "I can't open links in ghost markdown on the deep link test spot", a table
/// of `[hello.trade/waitlist?ref=…](https://hello.trade/waitlist?ref=…)`). The text is [plainCell]'s, letter for
/// letter: the links' words are marked while the marks round them come off, and the markers taken out after.
({String text, List<CellLink> links}) readCell(String raw) {
  if (raw.contains(_open) || raw.contains(_close)) return (text: plainCell(raw), links: const <CellLink>[]);
  final targets = <({String url, bool bare})>[];
  final linked = raw.replaceAllMapped(_link, (m) {
    final target = RegExp(r'\]\(\s*<?([^)\s>]*)').firstMatch(m.group(0)!)?.group(1) ?? '';
    targets.add((url: target, bare: false));
    return '$_open${m.group(1)!}$_close';
  });
  // Addresses said bare, outside the links' words: what is between one link's close and the next one's open.
  final pieces = linked.split(RegExp('(?=$_open)|(?<=$_close)'));
  final out = StringBuffer();
  final order = <({String url, bool bare})>[];
  var link = 0;
  for (final piece in pieces) {
    if (piece.startsWith(_open)) {
      order.add(targets[link++]);
      out.write(piece);
      continue;
    }
    out.write(piece.replaceAllMapped(_bareUrl, (m) {
      var url = m.group(0)!;
      url = url.replaceFirst(_bareTail, '');
      // A closing bracket the address did not open is the sentence's.
      while (url.endsWith(')') && ')'.allMatches(url).length > '('.allMatches(url).length) {
        url = url.substring(0, url.length - 1).replaceFirst(_bareTail, '');
      }
      if (Uri.tryParse(url)?.host.isNotEmpty != true) return m.group(0)!;
      order.add((url: url, bare: true));
      return '$_open$url$_close${m.group(0)!.substring(url.length)}';
    }));
  }
  final marked = out
      .toString()
      .replaceAllMapped(_strong, (m) => m.group(2)!)
      .replaceAllMapped(_emphasis, (m) => m.group(2)!)
      .replaceAllMapped(_code, (m) => m.group(1)!);
  final text = StringBuffer();
  final links = <CellLink>[];
  var start = -1, at = 0;
  for (final unit in marked.split('')) {
    if (unit == _open) {
      start = text.length;
    } else if (unit == _close) {
      if (start >= 0 && at < order.length) {
        final target = order[at];
        if (text.length > start && target.url.isNotEmpty) links.add(CellLink(from: start, to: text.length, url: target.url, bare: target.bare));
      }
      at += 1;
      start = -1;
    } else {
      text.write(unit);
    }
  }
  return (text: text.toString(), links: links);
}

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
