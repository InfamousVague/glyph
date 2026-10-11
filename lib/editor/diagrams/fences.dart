/// Where a note's diagrams are: its ```mermaid fences. Ports `diagramsIn` of `src/app/editor/mermaid.ts`, and keeps
/// what it found with the editor's state.
///
/// A ```mermaid fence is markdown like any other: the text is what is kept, what is edited, and what another app
/// sees. The fence is read by hand and not from the syntax tree, as boards are, and the word has to be the whole
/// info string, so a note about mermaids is not a diagram.
///
/// What differs: the page reads the whole note again on every change and every move of the caret
/// (`diagramsIn(state.doc.toString())` in its `build`). Here the fences are found once, as a note opens, and then
/// KEPT ([diagramBlocks]): a change is looked at by the lines it touched, in the note as it was and as it is, and
/// - a change that touched no line with a fence's run of backticks or tildes in it cannot have made, ended or
///   opened a diagram, so the ones there are moved to where the change left them, and the one whose lines it
///   changed has its words read again, and no other line of the note is read;
/// - any other change (a fence typed, closed, broken or pasted) finds the note's fences again, once, from the lines
///   with a fence's mark in them, which the document's tree keeps (`LineFact`, lib/editor/state/text.dart): the
///   lines of the leaf the change made are read, and no others.
///
/// So a letter typed outside a diagram looks at the line it is on, and a letter typed inside one reads that
/// diagram. [DiagramWork] counts both, for the test that holds a keystroke to it.
library;

import '../state/state.dart';
import '../state/text.dart';

/// The fence that opens a diagram: ```mermaid, or ~~~mermaid, and nothing else on the line (`OPEN`).
final RegExp _open = RegExp(r'^\s*(`{3,}|~{3,})\s*mermaid\s*$', caseSensitive: false);

/// A fence of a diagram in a note's text, by its lines.
class Diagram {
  const Diagram({required this.from, required this.to, required this.code});

  /// The line the opening fence is on, counting from 1.
  final int from;

  /// The line the closing fence is on.
  final int to;

  /// What is between the fences: the diagram itself.
  final String code;

  @override
  bool operator ==(Object other) => other is Diagram && other.from == from && other.to == to && other.code == code;

  @override
  int get hashCode => Object.hash(from, to, code);

  @override
  String toString() => 'Diagram($from-$to, ${code.replaceAll('\n', r'\n')})';
}

/// Whether a line can be a fence at all: it has a run of three backticks or three tildes in it.
bool _fenced(String line) => line.contains('```') || line.contains('~~~');

/// The fence a line opens a diagram with, or null.
String? _opens(String line) => _fenced(line) ? _open.firstMatch(line)?.group(1) : null;

/// Whether a line closes a fence opened with `fence`: the same mark, at least as many, and nothing else.
bool _closes(String line, String fence) {
  final mark = fence.codeUnitAt(0);
  var at = 0;
  while (at < line.length && _space(line.codeUnitAt(at))) {
    at += 1;
  }
  final run = at;
  while (at < line.length && line.codeUnitAt(at) == mark) {
    at += 1;
  }
  if (at - run < fence.length) return false;
  while (at < line.length && _space(line.codeUnitAt(at))) {
    at += 1;
  }
  return at == line.length;
}

/// What a regular expression's `\s` takes on one line.
bool _space(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0b || unit == 0x0c || unit == 0x0d || unit == 0xa0 || unit == 0x1680 || (unit >= 0x2000 && unit <= 0x200a) || unit == 0x2028 || unit == 0x2029 || unit == 0x202f || unit == 0x205f || unit == 0x3000 || unit == 0xfeff;

/// Every mermaid fence in the note, in the order they appear (`diagramsIn`). A fence that never closes is not one.
List<Diagram> diagramsIn(String doc) {
  if (!_fenced(doc)) return const <Diagram>[];
  final lines = doc.split('\n');
  final found = <Diagram>[];
  for (var i = 0; i < lines.length; i += 1) {
    final fence = _opens(lines[i]);
    if (fence == null) continue;
    var end = i;
    for (var j = i + 1; j < lines.length; j += 1) {
      if (_closes(lines[j], fence)) {
        end = j;
        break;
      }
    }
    if (end > i) found.add(Diagram(from: i + 1, to: end + 1, code: lines.sublist(i + 1, end).join('\n')));
    i = end;
  }
  return found;
}

/// A diagram's fence in a document, by where it is: from the opening fence's first backtick to the end of the
/// closing fence's line.
class DiagramBlock {
  const DiagramBlock({required this.from, required this.to, required this.code});

  final int from;
  final int to;

  /// What is between the fences. The same string, and not only an equal one, for as long as the lines are not
  /// changed.
  final String code;

  @override
  String toString() => 'DiagramBlock($from-$to, ${code.replaceAll('\n', r'\n')})';
}

/// How much of a note was read to keep its diagrams, counted in a debug build only (each count is inside an
/// `assert`). A test puts them to zero, does one thing, and holds what was read to a number.
abstract final class DiagramWork {
  /// Times a note's fences were found again, whole.
  static int scans = 0;

  /// Lines a change touched that were looked at for a fence's mark.
  static int lines = 0;

  /// Diagrams whose words were read again.
  static int reads = 0;

  static void reset() => scans = lines = reads = 0;

  static bool _scan() {
    scans += 1;
    return true;
  }

  static bool _line() {
    lines += 1;
    return true;
  }

  static bool _read() {
    reads += 1;
    return true;
  }
}

const List<DiagramBlock> _none = <DiagramBlock>[];

/// The lines of a note with a fence's mark in them, kept for every line of a document by the document's own tree
/// (`LineFact`, lib/editor/state/text.dart): few in any note, and a document made by a change reads only the lines
/// of the leaf the change made.
final LineFact<bool> _marked = LineFact<bool>((text) => _fenced(text) ? true : null);

/// Every diagram of a document, read whole: `diagramsIn` of its words, from the lines that have a fence's mark in
/// them, since an opening fence and what closes it are both among those. The note is never made into one string,
/// and a note read again after a change reads the changed leaf's lines and no others.
List<DiagramBlock> _scan(Doc doc) {
  assert(DiagramWork._scan());
  if (_marked.nowhere(doc)) return _none;
  final marked = _marked.of(doc);
  final blocks = <DiagramBlock>[];
  for (var i = 0; i < marked.length; i += 1) {
    final fence = _open.firstMatch(marked[i].text)?.group(1);
    if (fence == null) continue;
    for (var j = i + 1; j < marked.length; j += 1) {
      if (!_closes(marked[j].text, fence)) continue;
      final open = marked[i], close = marked[j];
      blocks.add(DiagramBlock(from: open.from, to: close.to, code: close.number > open.number + 1 ? doc.sliceString(open.to + 1, close.from - 1) : ''));
      i = j;
      break;
    }
  }
  return blocks.isEmpty ? _none : blocks;
}

/// Whether any line from the one `from` is on to the one `to` is on has a fence's mark in it.
bool _fencedBetween(Doc doc, int from, int to) {
  var line = doc.lineAt(from);
  for (;;) {
    assert(DiagramWork._line());
    if (_fenced(line.text)) return true;
    if (line.to >= to || line.number >= doc.lines) return false;
    line = doc.line(line.number + 1);
  }
}

/// The diagrams after a change, from the ones before it.
List<DiagramBlock> _after(List<DiagramBlock> before, Transaction tr) {
  final was = tr.startState.doc, now = tr.state.doc;
  var again = false;
  final touched = <(int, int)>[];
  tr.changes.iterChangedRanges((fromA, toA, fromB, toB) {
    if (again) return;
    if (_fencedBetween(was, fromA, toA) || _fencedBetween(now, fromB, toB)) {
      again = true;
    } else {
      touched.add((fromA, toA));
    }
  });
  if (again) return _scan(now);
  if (before.isEmpty) return before;
  List<DiagramBlock>? moved;
  for (var index = 0; index < before.length; index += 1) {
    final block = before[index];
    // No touched line has a fence's mark, so both of this block's fences stand as they were: only where they are
    // can have moved, and what is between them changed.
    final from = tr.changes.mapPos(block.from, 1), to = tr.changes.mapPos(block.to, -1);
    final changed = touched.any((range) => range.$1 <= block.to && range.$2 >= block.from);
    if (!changed && from == block.from && to == block.to) continue;
    moved ??= List<DiagramBlock>.of(before);
    moved[index] = DiagramBlock(from: from, to: to, code: changed ? _codeOf(now, from, to) : block.code);
  }
  return moved ?? before;
}

/// What is between the fences of the block at `from`-`to`.
String _codeOf(Doc doc, int from, int to) {
  assert(DiagramWork._read());
  final open = doc.lineAt(from), close = doc.lineAt(to);
  return close.number > open.number + 1 ? doc.sliceString(open.to + 1, close.from - 1) : '';
}

/// A note's diagrams, kept with its state: read once, then moved and read again only where a change touched them.
/// The same list, and not only an equal one, across a transaction that left every diagram where and as it was.
final StateField<List<DiagramBlock>> diagramBlocks = StateField.define<List<DiagramBlock>>(
  create: (state) => _scan(state.doc),
  update: (blocks, tr) => tr.docChanged ? _after(blocks, tr) : blocks,
);

/// The diagrams of `state`, where its editor keeps them ([diagramBlocks]); read from the note where it does not.
List<DiagramBlock> diagramsOf(EditorState state) => state.fieldOrNull(diagramBlocks) ?? _scan(state.doc);
