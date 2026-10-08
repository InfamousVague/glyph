/// Tables through the model, kept by construction, like links (links.dart). A port of `src/app/format/tables.ts`.
///
/// A note can carry a GFM table, and a table is exactly what a small model rewriting a note will mangle: cells
/// reordered, a column dropped, the pipes lost. So before the note goes in, each table block - a header row with
/// pipes, a delimiter row of dashes, then every following row with pipes - is swapped for one line the model can
/// copy, and after the rewrite the line is swapped back for the block, verbatim. Tables go first, before links, so a
/// link in a cell is inside the block and never touched.
///
/// The line is shaped like a picture, `![table-1](table)`: measured with the 4B, a bare `[table-1]` was dropped as
/// noise even when the prompt asked for it, while a picture line - which the prompt has always asked to be copied
/// exactly, on its own line - is kept every time.
///
/// A token that does not come back is appended at the end of the note, for the modes that keep everything; a summary
/// is allowed to leave a table out.
///
/// What differs: `final` is a word Dart keeps, so [restoreTables] takes `isFinal`, and its two switches are named.
library;

import 'package:flutter/foundation.dart';

import '../core/item_syntax.dart' show jsTrim;

/// A table held aside while the model works (`ProtectedTable`).
@immutable
class ProtectedTable {
  const ProtectedTable({required this.token, required this.block});

  /// `table-2`: what stands in for the block while the model works.
  final String token;

  /// The block's lines, joined with newlines, exactly as written.
  final String block;

  @override
  bool operator ==(Object other) => other is ProtectedTable && other.token == token && other.block == block;

  @override
  int get hashCode => Object.hash(token, block);

  @override
  String toString() => 'ProtectedTable($token, $block)';
}

/// A note with its tables out, and the tables (`ProtectedTables`).
@immutable
class ProtectedTables {
  const ProtectedTables({required this.text, required this.tables});

  final String text;
  final List<ProtectedTable> tables;

  @override
  bool operator ==(Object other) => other is ProtectedTables && other.text == text && listEquals(other.tables, tables);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(tables));

  @override
  String toString() => 'ProtectedTables($text, $tables)';
}

/// A GFM delimiter row: cells of dashes, an optional colon at either end, pipes between.
final RegExp _delimiter = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// The note with every table block replaced by a token line, and the blocks to put back.
ProtectedTables protectTables(String body) {
  final lines = body.split('\n');
  final out = <String>[];
  final tables = <ProtectedTable>[];
  var i = 0;
  while (i < lines.length) {
    final header = lines[i];
    final delimiter = i + 1 < lines.length ? lines[i + 1] : null;
    if (header.contains('|') && delimiter != null && delimiter.contains('|') && _delimiter.hasMatch(delimiter)) {
      var end = i + 2;
      while (end < lines.length && lines[end].contains('|') && jsTrim(lines[end]).isNotEmpty) {
        end += 1;
      }
      final token = 'table-${tables.length + 1}';
      tables.add(ProtectedTable(token: token, block: lines.sublist(i, end).join('\n')));
      out.add('![$token](table)');
      i = end;
    } else {
      out.add(header);
      i += 1;
    }
  }
  return ProtectedTables(text: out.join('\n'), tables: tables);
}

/// The rewrite with its tables back: a line that is the token, however the model wrote it (`![table-1](table)`,
/// `[table-1]`, `table 1`), becomes the block; a token buried in a sentence gets the block on its own lines. With
/// [isFinal] and [appendMissing], a block whose token never came back is added at the end; a partial rewrite still
/// streaming is only substituted.
String restoreTables(String text, List<ProtectedTable> tables, {bool isFinal = true, bool appendMissing = true}) {
  var out = text;
  final missing = <ProtectedTable>[];
  for (final table in tables) {
    final number = table.token.substring('table-'.length);
    // Spaces and tabs only, never `\s`: that would swallow the line's newline.
    final token = '!?[\\[<(]?[ \\t]*table[ \\t-]?$number(?!\\d)[ \\t]*[\\]>)]?(?:\\([ \\t]*table[ \\t]*\\))?';
    var found = false;
    out = out.replaceAllMapped(RegExp('^[ \\t]*$token[ \\t]*\$', multiLine: true, caseSensitive: false), (_) {
      found = true;
      return table.block;
    });
    out = out.replaceAllMapped(RegExp(token, caseSensitive: false), (_) {
      found = true;
      return '\n\n${table.block}\n\n';
    });
    if (!found) missing.add(table);
  }
  if (!isFinal || !appendMissing || missing.isEmpty) return out;
  return '${out.replaceFirst(_trailingSpace, '')}\n\n${missing.map((t) => t.block).join('\n\n')}\n';
}
