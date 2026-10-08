// Ported from @lezer/markdown 1.7.2 (src/markdown.ts), which is:
//
// MIT License
//
// Copyright (C) 2020 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// The Markdown parser the web editor reads a note with: `@lezer/markdown`'s `markdown.ts`, class for class.
///
/// The names are Lezer's so the source can be read beside this: [BlockContext] walks the note a line at a time
/// keeping a stack of open [CompositeBlock]s (quotes, lists, list items); a line that no block parser takes starts a
/// [LeafBlock], which [LeafBlockParser]s watch (a link reference, a Setext heading, a table) and which is a paragraph
/// if none claims it; a leaf's words go through [MarkdownParser.parseInline], an [InlineContext] that collects
/// [Element]s and [InlineDelimiter]s and pairs the delimiters up in `resolveMarkers`. [MarkdownParser.configure]
/// takes the same [MarkdownConfig] objects, which is how GFM (extension.dart) and the app's marks (language.dart)
/// are added.
///
/// What differs:
/// - Lezer writes a leaf block's nodes into a flat buffer and has `Tree.build` make the tree; here an [Element]
///   becomes a [Tree] directly. The nodes and their positions are the same.
/// - One input range, the whole string: no gaps (`ranges`), so no `injectGaps`, and no `stopAt`.
/// - No `wrap` (nested parsers: a fence's own language, HTML) and no `props` or `style` (highlighting tags).
/// - JavaScript reads `NaN` past the end of a string and an empty string from a slice that starts there; the reads
///   that lean on it go through [_charAt] and [_slice].
library;

import 'tree.dart';

/// Lezer's `Type`: the ids of the built-in nodes, in its order.
abstract final class Type {
  static const int document = 1;
  static const int codeBlock = 2;
  static const int fencedCode = 3;
  static const int blockquote = 4;
  static const int horizontalRule = 5;
  static const int bulletList = 6;
  static const int orderedList = 7;
  static const int listItem = 8;
  static const int atxHeading1 = 9;
  static const int atxHeading2 = 10;
  static const int atxHeading3 = 11;
  static const int atxHeading4 = 12;
  static const int atxHeading5 = 13;
  static const int atxHeading6 = 14;
  static const int setextHeading1 = 15;
  static const int setextHeading2 = 16;
  static const int htmlBlock = 17;
  static const int linkReference = 18;
  static const int paragraph = 19;
  static const int commentBlock = 20;
  static const int processingInstructionBlock = 21;

  // Inline
  static const int escape = 22;
  static const int entity = 23;
  static const int hardBreak = 24;
  static const int emphasis = 25;
  static const int strongEmphasis = 26;
  static const int link = 27;
  static const int image = 28;
  static const int inlineCode = 29;
  static const int htmlTag = 30;
  static const int comment = 31;
  static const int processingInstruction = 32;
  static const int autolink = 33;

  // Smaller tokens
  static const int headerMark = 34;
  static const int quoteMark = 35;
  static const int listMark = 36;
  static const int linkMark = 37;
  static const int emphasisMark = 38;
  static const int codeMark = 39;
  static const int codeText = 40;
  static const int codeInfo = 41;
  static const int linkTitle = 42;
  static const int linkLabel = 43;
  static const int url = 44;

  /// The names, by id. The first is Lezer's `NodeType.none`.
  static const List<String> names = [
    '',
    'Document',
    'CodeBlock',
    'FencedCode',
    'Blockquote',
    'HorizontalRule',
    'BulletList',
    'OrderedList',
    'ListItem',
    'ATXHeading1',
    'ATXHeading2',
    'ATXHeading3',
    'ATXHeading4',
    'ATXHeading5',
    'ATXHeading6',
    'SetextHeading1',
    'SetextHeading2',
    'HTMLBlock',
    'LinkReference',
    'Paragraph',
    'CommentBlock',
    'ProcessingInstructionBlock',
    'Escape',
    'Entity',
    'HardBreak',
    'Emphasis',
    'StrongEmphasis',
    'Link',
    'Image',
    'InlineCode',
    'HTMLTag',
    'Comment',
    'ProcessingInstruction',
    'Autolink',
    'HeaderMark',
    'QuoteMark',
    'ListMark',
    'LinkMark',
    'EmphasisMark',
    'CodeMark',
    'CodeText',
    'CodeInfo',
    'LinkTitle',
    'LinkLabel',
    'URL',
  ];
}

/// `String.prototype.charCodeAt` where the port needs its answer past either end: -1 where JavaScript says `NaN`,
/// which equals no character either.
int _charAt(String text, int index) => index >= 0 && index < text.length ? text.codeUnitAt(index) : -1;

/// `String.prototype.slice`: a negative index counts from the end, and both are clamped to the string.
String _slice(String text, int from, [int? to]) {
  final length = text.length;
  var start = from < 0 ? from + length : from;
  var end = to == null ? length : (to < 0 ? to + length : to);
  if (start < 0) start = 0;
  if (end > length) end = length;
  return start >= end ? '' : text.substring(start, end);
}

/// Lezer's `CompositeBlock`: a block that holds other blocks (the document, a quote, a list, a list item), open on
/// the [BlockContext]'s stack while its lines come in.
class CompositeBlock {
  CompositeBlock._(this.type, this.value, this.from, this.hash, this.end);

  factory CompositeBlock.create(int type, int value, int from, int parentHash, int end) {
    final hash = (parentHash + (parentHash << 8) + type + (value << 4)).toSigned(32);
    return CompositeBlock._(type, value, from, hash, end);
  }

  final int type;

  /// Used for indentation in list items, markup character in lists.
  final int value;
  final int from;

  /// The context hash: this block's type and value folded into its parent's hash.
  final int hash;
  int end;
  final List<Tree> children = [];
  final List<int> positions = [];

  void addChild(Tree child, int pos) {
    if (child.contextHash != hash) child = Tree(child.type, child.children, child.positions, child.length, hash);
    children.add(child);
    positions.add(pos);
  }

  Tree toTree(List<NodeType> types, [int? end]) {
    var to = end ?? this.end;
    final last = children.length - 1;
    if (last >= 0) {
      final childEnd = positions[last] + children[last].length + from;
      if (childEnd > to) to = childEnd;
    }
    return Tree(types[type], children, positions, to - from);
  }
}

/// Lezer's `LeafBlock`: what a leaf block's content is gathered in while its lines come in.
class LeafBlock {
  LeafBlock(this.start, this.content);

  /// The composite blocks' markers (a quote's `>`) on the block's later lines.
  final List<Element> marks = [];

  /// The block parsers active for this block.
  final List<LeafBlockParser> parsers = [];

  /// The start position of the block.
  final int start;

  /// The block's text content.
  String content;
}

/// Lezer's `Line`: the line the block parsers are looking at.
class Line {
  /// The line's full text.
  String text = '';

  /// The base indent provided by the composite contexts (that have been handled so far).
  int baseIndent = 0;

  /// The string position corresponding to the base indent.
  int basePos = 0;

  /// The number of contexts handled.
  int depth = 0;

  /// Any markers (i.e. block quote markers) parsed for the contexts. A block parser that moves across lines,
  /// covering such marks, may need to include these in its node structure.
  List<Element> markers = [];

  /// The position of the next non-whitespace character beyond any list, blockquote, or other composite block
  /// markers.
  int pos = 0;

  /// The column of the next non-whitespace character.
  int indent = 0;

  /// The character code of the character after `pos`.
  int next = -1;

  void forward() {
    if (basePos > pos) forwardInner();
  }

  void forwardInner() {
    final newPos = skipSpace(basePos);
    indent = countIndent(newPos, pos, indent);
    pos = newPos;
    next = newPos == text.length ? -1 : text.codeUnitAt(newPos);
  }

  /// Skip whitespace after the given position, return the position of the next non-space character or the end of
  /// the line if there's only space after `from`.
  int skipSpace(int from) => _skipSpace(text, from);

  void reset(String text) {
    this.text = text;
    baseIndent = basePos = pos = indent = 0;
    forwardInner();
    depth = 1;
    markers.clear();
  }

  /// Move the line's base position forward to the given position. This should only be called by composite block
  /// parsers or markup skipping functions.
  void moveBase(int to) {
    basePos = to;
    baseIndent = countIndent(to, pos, indent);
  }

  /// Move the line's base position forward to the given _column_.
  void moveBaseColumn(int indent) {
    baseIndent = indent;
    basePos = findColumn(indent);
  }

  /// Store a composite-block-level marker. Should be called from markup skipping functions when they consume any
  /// non-whitespace characters.
  void addMarker(Element elt) {
    markers.add(elt);
  }

  /// Find the column position at `to`, optionally starting at a given position and column.
  int countIndent(int to, [int from = 0, int indent = 0]) {
    for (var i = from; i < to; i++) {
      indent += _charAt(text, i) == 9 ? 4 - indent % 4 : 1;
    }
    return indent;
  }

  /// Find the position corresponding to the given column.
  int findColumn(int goal) {
    var i = 0;
    for (var indent = 0; i < text.length && indent < goal; i++) {
      indent += text.codeUnitAt(i) == 9 ? 4 - indent % 4 : 1;
    }
    return i;
  }

  /// The line with what the composite blocks took from its start blanked out.
  String scrub() {
    if (baseIndent == 0) return text;
    return ' ' * basePos + _slice(text, basePos);
  }
}

bool _skipForList(CompositeBlock bl, BlockContext cx, Line line) {
  if (line.pos == line.text.length || (bl != cx.block && line.indent >= cx.stack[line.depth + 1].value + line.baseIndent)) {
    return true;
  }
  if (line.indent >= line.baseIndent + 4) return false;
  final size = (bl.type == Type.orderedList ? _isOrderedList : _isBulletList)(line, cx, false);
  return size > 0 &&
      (bl.type != Type.bulletList || _isHorizontalRule(line, cx, false) < 0) &&
      _charAt(line.text, line.pos + size - 1) == bl.value;
}

/// A composite block's say on whether a new line is still inside it: Lezer's `skipContextMarkup` entry.
typedef SkipMarkup = bool Function(CompositeBlock bl, BlockContext cx, Line line);

final Map<int, SkipMarkup> _defaultSkipMarkup = {
  Type.blockquote: (bl, cx, line) {
    if (line.next != 62 /* '>' */ ) return false;
    line.markers.add(_elt(Type.quoteMark, cx.lineStart + line.pos, cx.lineStart + line.pos + 1));
    line.moveBase(line.pos + (space(_charAt(line.text, line.pos + 1)) ? 2 : 1));
    bl.end = cx.lineStart + line.text.length;
    return true;
  },
  Type.listItem: (bl, cx, line) {
    if (line.indent < line.baseIndent + bl.value && line.next > -1) return false;
    line.moveBaseColumn(line.baseIndent + bl.value);
    return true;
  },
  Type.orderedList: _skipForList,
  Type.bulletList: _skipForList,
  Type.document: (bl, cx, line) => true,
};

/// Lezer's `space`: a space, a tab, a line feed or a carriage return.
bool space(int ch) => ch == 32 || ch == 9 || ch == 10 || ch == 13;

int _skipSpace(String line, [int i = 0]) {
  while (i < line.length && space(line.codeUnitAt(i))) {
    i++;
  }
  return i;
}

int _skipSpaceBack(String line, int i, int to) {
  while (i > to && space(line.codeUnitAt(i - 1))) {
    i--;
  }
  return i;
}

int _isFencedCode(Line line) {
  if (line.next != 96 && line.next != 126 /* '`~' */ ) return -1;
  var pos = line.pos + 1;
  while (pos < line.text.length && line.text.codeUnitAt(pos) == line.next) {
    pos++;
  }
  if (pos < line.pos + 3) return -1;
  if (line.next == 96) {
    for (var i = pos; i < line.text.length; i++) {
      if (line.text.codeUnitAt(i) == 96) return -1;
    }
  }
  return pos;
}

int _isBlockquote(Line line) {
  return line.next != 62 /* '>' */ ? -1 : (_charAt(line.text, line.pos + 1) == 32 ? 2 : 1);
}

int _isHorizontalRule(Line line, BlockContext cx, bool breaking) {
  if (line.next != 42 && line.next != 45 && line.next != 95 /* '_-*' */ ) return -1;
  var count = 1;
  for (var pos = line.pos + 1; pos < line.text.length; pos++) {
    final ch = line.text.codeUnitAt(pos);
    if (ch == line.next) {
      count++;
    } else if (!space(ch)) {
      return -1;
    }
  }
  // Setext headers take precedence
  if (breaking &&
      line.next == 45 &&
      _isSetextUnderline(line) > -1 &&
      line.depth == cx.stack.length &&
      cx.parser.leafBlockParsers.contains(_setextHeadingLeaf)) {
    return -1;
  }
  return count < 3 ? -1 : 1;
}

bool _inList(BlockContext cx, int type) {
  for (var i = cx.stack.length - 1; i >= 0; i--) {
    if (cx.stack[i].type == type) return true;
  }
  return false;
}

int _isBulletList(Line line, BlockContext cx, bool breaking) {
  return (line.next == 45 || line.next == 43 || line.next == 42 /* '-+*' */ ) &&
          (line.pos == line.text.length - 1 || space(_charAt(line.text, line.pos + 1))) &&
          (!breaking || _inList(cx, Type.bulletList) || line.skipSpace(line.pos + 2) < line.text.length)
      ? 1
      : -1;
}

int _isOrderedList(Line line, BlockContext cx, bool breaking) {
  var pos = line.pos, next = line.next;
  for (;;) {
    if (next >= 48 && next <= 57 /* '0-9' */ ) {
      pos++;
    } else {
      break;
    }
    if (pos == line.text.length) return -1;
    next = line.text.codeUnitAt(pos);
  }
  if (pos == line.pos ||
      pos > line.pos + 9 ||
      (next != 46 && next != 41 /* '.)' */ ) ||
      (pos < line.text.length - 1 && !space(_charAt(line.text, pos + 1))) ||
      breaking &&
          !_inList(cx, Type.orderedList) &&
          (line.skipSpace(pos + 1) == line.text.length || pos > line.pos + 1 || line.next != 49 /* '1' */ )) {
    return -1;
  }
  return pos + 1 - line.pos;
}

int _isAtxHeading(Line line) {
  if (line.next != 35 /* '#' */ ) return -1;
  var pos = line.pos + 1;
  while (pos < line.text.length && line.text.codeUnitAt(pos) == 35) {
    pos++;
  }
  if (pos < line.text.length && line.text.codeUnitAt(pos) != 32) return -1;
  final size = pos - line.pos;
  return size > 6 ? -1 : size;
}

int _isSetextUnderline(Line line) {
  if (line.next != 45 && line.next != 61 /* '-=' */ || line.indent >= line.baseIndent + 4) return -1;
  var pos = line.pos + 1;
  while (pos < line.text.length && line.text.codeUnitAt(pos) == line.next) {
    pos++;
  }
  final end = pos;
  while (pos < line.text.length && space(line.text.codeUnitAt(pos))) {
    pos++;
  }
  return pos == line.text.length ? end : -1;
}

final RegExp _emptyLine = RegExp(r'^[ \t]*$');
final RegExp _commentEnd = RegExp(r'-->');
final RegExp _processingEnd = RegExp(r'\?>');

/// Lezer's `HTMLBlockStyle`: for each of CommonMark's seven kinds of HTML block, what opens it and what ends it.
final List<List<RegExp>> _htmlBlockStyle = [
  [RegExp(r'^<(?:script|pre|style)(?:\s|>|$)', caseSensitive: false), RegExp(r'</(?:script|pre|style)>', caseSensitive: false)],
  [RegExp(r'^\s*<!--'), _commentEnd],
  [RegExp(r'^\s*<\?'), _processingEnd],
  [RegExp(r'^\s*<![A-Z]'), RegExp(r'>')],
  [RegExp(r'^\s*<!\[CDATA\['), RegExp(r'\]\]>')],
  [
    RegExp(
      r'^\s*</?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\s|/?>|$)',
      caseSensitive: false,
    ),
    _emptyLine,
  ],
  [
    RegExp(
      r'''^\s*(?:</[a-z][\w-]*\s*>|<[a-z][\w-]*(\s+[a-z:_][\w\-.]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*>)\s*$''',
      caseSensitive: false,
    ),
    _emptyLine,
  ],
];

int _isHTMLBlock(Line line, BlockContext cx, bool breaking) {
  if (line.next != 60 /* '<' */ ) return -1;
  final rest = _slice(line.text, line.pos);
  for (var i = 0, e = _htmlBlockStyle.length - (breaking ? 1 : 0); i < e; i++) {
    if (_htmlBlockStyle[i][0].hasMatch(rest)) return i;
  }
  return -1;
}

int _getListIndent(Line line, int pos) {
  final indentAfter = line.countIndent(pos, line.pos, line.indent);
  final skipped = line.skipSpace(pos);
  final indented = line.countIndent(skipped, pos, indentAfter);
  return indented >= indentAfter + 5 || skipped == line.text.length ? indentAfter + 1 : indented;
}

/// A block parser's `parse`. Lezer's `BlockResult` is its answer:
///
/// - `false` to indicate that nothing was matched and lower-precedence parsers should run.
/// - `true` to indicate that a leaf block was parsed and the stream was advanced past its content.
/// - `null` to indicate that a context was opened and block parsing should continue on this line.
typedef BlockParse = bool? Function(BlockContext cx, Line line);

/// A block parser's `leaf`: a watcher for the leaf block that has just begun, or null to leave it be.
typedef LeafParse = LeafBlockParser? Function(BlockContext cx, LeafBlock leaf);

/// A block parser's `endLeaf`: whether this line ends the leaf block before it without a blank line between.
typedef EndLeaf = bool Function(BlockContext cx, Line line, LeafBlock leaf);

/// An inline parser's `parse`: -1 when the character is not its own, else the position after what it took.
typedef InlineParse = int Function(InlineContext cx, int next, int pos);

void _addCodeText(List<Element> marks, int from, int to) {
  final last = marks.length - 1;
  if (last >= 0 && marks[last].to == from && marks[last].type == Type.codeText) {
    marks[last].to = to;
  } else {
    marks.add(_elt(Type.codeText, from, to));
  }
}

bool? _indentedCode(BlockContext cx, Line line) {
  final base = line.baseIndent + 4;
  if (line.indent < base) return false;
  final start = line.findColumn(base);
  final from = cx.lineStart + start;
  var to = cx.lineStart + line.text.length;
  final marks = <Element>[];
  var pendingMarks = <Element>[];
  _addCodeText(marks, from, to);
  while (cx.nextLine() && line.depth >= cx.stack.length) {
    if (line.pos == line.text.length) {
      // Empty
      _addCodeText(pendingMarks, cx.lineStart - 1, cx.lineStart);
      for (final m in line.markers) {
        pendingMarks.add(m);
      }
    } else if (line.indent < base) {
      break;
    } else {
      if (pendingMarks.isNotEmpty) {
        for (final m in pendingMarks) {
          if (m.type == Type.codeText) {
            _addCodeText(marks, m.from, m.to);
          } else {
            marks.add(m);
          }
        }
        pendingMarks = [];
      }
      _addCodeText(marks, cx.lineStart - 1, cx.lineStart);
      for (final m in line.markers) {
        marks.add(m);
      }
      to = cx.lineStart + line.text.length;
      final codeStart = cx.lineStart + line.findColumn(line.baseIndent + 4);
      if (codeStart < to) _addCodeText(marks, codeStart, to);
    }
  }
  if (pendingMarks.isNotEmpty) {
    pendingMarks = pendingMarks.where((m) => m.type != Type.codeText).toList();
    if (pendingMarks.isNotEmpty) line.markers = [...pendingMarks, ...line.markers];
  }

  cx.addNode(_treeOf(cx.parser.nodeTypes, Type.codeBlock, marks, from, to), from);
  return true;
}

bool? _fencedCode(BlockContext cx, Line line) {
  final fenceEnd = _isFencedCode(line);
  if (fenceEnd < 0) return false;
  final from = cx.lineStart + line.pos, ch = line.next, len = fenceEnd - line.pos;
  final infoFrom = line.skipSpace(fenceEnd), infoTo = _skipSpaceBack(line.text, line.text.length, infoFrom);
  final marks = <Element>[_elt(Type.codeMark, from, from + len)];
  if (infoFrom < infoTo) marks.add(_elt(Type.codeInfo, cx.lineStart + infoFrom, cx.lineStart + infoTo));

  for (var first = true, empty = true, hasLine = false; cx.nextLine() && line.depth >= cx.stack.length; first = false) {
    var i = line.pos;
    if (line.indent - line.baseIndent < 4) {
      while (i < line.text.length && line.text.codeUnitAt(i) == ch) {
        i++;
      }
    }
    if (i - line.pos >= len && line.skipSpace(i) == line.text.length) {
      for (final m in line.markers) {
        marks.add(m);
      }
      if (empty && hasLine) _addCodeText(marks, cx.lineStart - 1, cx.lineStart);
      marks.add(_elt(Type.codeMark, cx.lineStart + line.pos, cx.lineStart + i));
      cx.nextLine();
      break;
    } else {
      hasLine = true;
      if (!first) {
        _addCodeText(marks, cx.lineStart - 1, cx.lineStart);
        empty = false;
      }
      for (final m in line.markers) {
        marks.add(m);
      }
      final textStart = cx.lineStart + line.basePos, textEnd = cx.lineStart + line.text.length;
      if (textStart < textEnd) {
        _addCodeText(marks, textStart, textEnd);
        empty = false;
      }
    }
  }
  cx.addNode(_treeOf(cx.parser.nodeTypes, Type.fencedCode, marks, from, cx.prevLineEnd()), from);
  return true;
}

bool? _blockquote(BlockContext cx, Line line) {
  final size = _isBlockquote(line);
  if (size < 0) return false;
  cx.startContext(Type.blockquote, line.pos);
  cx.addNode(Type.quoteMark, cx.lineStart + line.pos, cx.lineStart + line.pos + 1);
  line.moveBase(line.pos + size);
  return null;
}

bool? _horizontalRule(BlockContext cx, Line line) {
  if (_isHorizontalRule(line, cx, false) < 0) return false;
  final from = cx.lineStart + line.pos;
  cx.nextLine();
  cx.addNode(Type.horizontalRule, from);
  return true;
}

bool? _bulletList(BlockContext cx, Line line) {
  final size = _isBulletList(line, cx, false);
  if (size < 0) return false;
  if (cx.block.type != Type.bulletList) cx.startContext(Type.bulletList, line.basePos, line.next);
  final newBase = _getListIndent(line, line.pos + 1);
  cx.startContext(Type.listItem, line.basePos, newBase - line.baseIndent);
  cx.addNode(Type.listMark, cx.lineStart + line.pos, cx.lineStart + line.pos + size);
  line.moveBaseColumn(newBase);
  return null;
}

bool? _orderedList(BlockContext cx, Line line) {
  final size = _isOrderedList(line, cx, false);
  if (size < 0) return false;
  if (cx.block.type != Type.orderedList) {
    cx.startContext(Type.orderedList, line.basePos, _charAt(line.text, line.pos + size - 1));
  }
  final newBase = _getListIndent(line, line.pos + size);
  cx.startContext(Type.listItem, line.basePos, newBase - line.baseIndent);
  cx.addNode(Type.listMark, cx.lineStart + line.pos, cx.lineStart + line.pos + size);
  line.moveBaseColumn(newBase);
  return null;
}

bool? _atxHeading(BlockContext cx, Line line) {
  final size = _isAtxHeading(line);
  if (size < 0) return false;
  final off = line.pos, from = cx.lineStart + off;
  final endOfSpace = _skipSpaceBack(line.text, line.text.length, off);
  var after = endOfSpace;
  while (after > off && line.text.codeUnitAt(after - 1) == line.next) {
    after--;
  }
  if (after == endOfSpace || after == off || !space(_charAt(line.text, after - 1))) after = line.text.length;
  final elts = <Element>[
    _elt(Type.headerMark, from, from + size),
    ...cx.parser.parseInline(_slice(line.text, off + size + 1, after), from + size + 1),
    if (after < line.text.length) _elt(Type.headerMark, from + after - off, from + endOfSpace - off),
  ];
  final node = _treeOf(cx.parser.nodeTypes, Type.atxHeading1 - 1 + size, elts, from, from + line.text.length - off);
  cx.nextLine();
  cx.addNode(node, from);
  return true;
}

bool? _htmlBlock(BlockContext cx, Line line) {
  final type = _isHTMLBlock(line, cx, false);
  if (type < 0) return false;
  final from = cx.lineStart + line.pos, end = _htmlBlockStyle[type][1];
  final marks = <Element>[];
  var trailing = !identical(end, _emptyLine);
  while (!end.hasMatch(line.text) && cx.nextLine()) {
    if (line.depth < cx.stack.length) {
      trailing = false;
      break;
    }
    for (final m in line.markers) {
      marks.add(m);
    }
  }
  if (trailing) cx.nextLine();
  final nodeType = identical(end, _commentEnd)
      ? Type.commentBlock
      : identical(end, _processingEnd)
      ? Type.processingInstructionBlock
      : Type.htmlBlock;
  final to = cx.prevLineEnd();
  cx.addNode(_treeOf(cx.parser.nodeTypes, nodeType, marks, from, to), from);
  return true;
}

/// Lezer's `DefaultBlockParsers`, in its order; the two with no `parse` only hold a place for their leaf parser.
const List<String> _defaultBlockNames = [
  'LinkReference',
  'IndentedCode',
  'FencedCode',
  'Blockquote',
  'HorizontalRule',
  'BulletList',
  'OrderedList',
  'ATXHeading',
  'HTMLBlock',
  'SetextHeading',
];

const List<BlockParse?> _defaultBlockParsers = [
  null,
  _indentedCode,
  _fencedCode,
  _blockquote,
  _horizontalRule,
  _bulletList,
  _orderedList,
  _atxHeading,
  _htmlBlock,
  null, // SetextHeading: specifies relative precedence for block-continue function
];

// Lezer's `RefStage`.
const int _refFailed = -1, _refStart = 0, _refLabel = 1, _refLink = 2, _refTitle = 3;

/// Lezer's `LinkReferenceParser`.
///
/// This implements a state machine that incrementally parses link references. At each next line, it looks ahead to
/// see if the line continues the reference or not. If it doesn't and a valid link is available ending before that
/// line, it finishes that. Similarly, on `finish` (when the leaf is terminated by external circumstances), it
/// creates a link reference if there's a valid reference up to the current point.
class _LinkReferenceParser implements LeafBlockParser {
  _LinkReferenceParser(LeafBlock leaf) : start = leaf.start {
    advance(leaf.content);
  }

  int stage = _refStart;
  final List<Element> elts = [];
  int pos = 0;
  final int start;

  @override
  bool nextLine(BlockContext cx, Line line, LeafBlock leaf) {
    if (stage == _refFailed) return false;
    final content = '${leaf.content}\n${line.scrub()}';
    final finish = advance(content);
    if (finish > -1 && finish < content.length) return complete(cx, leaf, finish);
    return false;
  }

  @override
  bool finish(BlockContext cx, LeafBlock leaf) {
    if ((stage == _refLink || stage == _refTitle) && _skipSpace(leaf.content, pos) == leaf.content.length) {
      return complete(cx, leaf, leaf.content.length);
    }
    return false;
  }

  bool complete(BlockContext cx, LeafBlock leaf, int len) {
    cx.addLeafElement(leaf, _elt(Type.linkReference, start, start + len, elts));
    return true;
  }

  /// Takes an element, null (ran off the end) or false (cannot be).
  bool nextStage(Object? elt) {
    if (elt is Element) {
      pos = elt.to - start;
      elts.add(elt);
      stage++;
      return true;
    }
    if (elt == false) stage = _refFailed;
    return false;
  }

  int advance(String content) {
    for (;;) {
      if (stage == _refFailed) {
        return -1;
      } else if (stage == _refStart) {
        if (!nextStage(_parseLinkLabel(content, pos, start, true))) return -1;
        if (_charAt(content, pos) != 58 /* ':' */ ) return stage = _refFailed;
        elts.add(_elt(Type.linkMark, pos + start, pos + start + 1));
        pos++;
      } else if (stage == _refLabel) {
        if (!nextStage(_parseURL(content, _skipSpace(content, pos), start))) return -1;
      } else if (stage == _refLink) {
        final skip = _skipSpace(content, pos);
        var end = 0;
        if (skip > pos) {
          final title = _parseLinkTitle(content, skip, start);
          if (title is Element) {
            final titleEnd = _lineEnd(content, title.to - start);
            if (titleEnd > 0) {
              nextStage(title);
              end = titleEnd;
            }
          }
        }
        if (end == 0) end = _lineEnd(content, pos);
        return end > 0 && end < content.length ? end : -1;
      } else {
        // RefStage.Title
        return _lineEnd(content, pos);
      }
    }
  }
}

int _lineEnd(String text, int pos) {
  for (; pos < text.length; pos++) {
    final next = text.codeUnitAt(pos);
    if (next == 10) break;
    if (!space(next)) return -1;
  }
  return pos;
}

/// Lezer's `SetextHeadingParser`. The app takes it out (language.dart): there, `#` is the only way to a heading.
class _SetextHeadingParser implements LeafBlockParser {
  @override
  bool nextLine(BlockContext cx, Line line, LeafBlock leaf) {
    final underline = line.depth < cx.stack.length ? -1 : _isSetextUnderline(line);
    final next = line.next;
    if (underline < 0) return false;
    final underlineMark = _elt(Type.headerMark, cx.lineStart + line.pos, cx.lineStart + underline);
    cx.nextLine();
    cx.addLeafElement(
      leaf,
      _elt(next == 61 ? Type.setextHeading1 : Type.setextHeading2, leaf.start, cx.prevLineEnd(), [
        ...cx.parser.parseInline(leaf.content, leaf.start),
        underlineMark,
      ]),
    );
    return true;
  }

  @override
  bool finish(BlockContext cx, LeafBlock leaf) => false;
}

LeafBlockParser? _linkReferenceLeaf(BlockContext cx, LeafBlock leaf) {
  return _charAt(leaf.content, 0) == 91 /* '[' */ ? _LinkReferenceParser(leaf) : null;
}

LeafBlockParser? _setextHeadingLeaf(BlockContext cx, LeafBlock leaf) => _SetextHeadingParser();

/// Lezer's `DefaultLeafBlocks`, placed by the same names as [_defaultBlockParsers].
const List<LeafParse?> _defaultLeafBlocks = [
  _linkReferenceLeaf,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  _setextHeadingLeaf,
];

/// Lezer's `DefaultEndLeaf`: the lines that end a paragraph without a blank line before them.
final List<EndLeaf> _defaultEndLeaf = [
  (cx, line, leaf) => _isAtxHeading(line) >= 0,
  (cx, line, leaf) => _isFencedCode(line) >= 0,
  (cx, line, leaf) => _isBlockquote(line) >= 0,
  (cx, line, leaf) => _isBulletList(line, cx, true) >= 0,
  (cx, line, leaf) => _isOrderedList(line, cx, true) >= 0,
  (cx, line, leaf) => _isHorizontalRule(line, cx, true) >= 0,
  (cx, line, leaf) => _isHTMLBlock(line, cx, true) >= 0,
];

/// Lezer's `BlockContext`: one parse of one text, a block at a time. Block-level parsing functions get access to
/// this context object.
class BlockContext {
  BlockContext._(this.parser, this.input, List<TreeFragment> fragments)
    : _to = input.length,
      block = CompositeBlock.create(Type.document, 0, 0, 0, 0),
      _fragments = fragments.isNotEmpty ? _FragmentCursor(fragments, input) : null {
    stack.add(block);
    _readLine();
  }

  /// The parser configuration used.
  final MarkdownParser parser;

  /// The whole text being parsed.
  final String input;

  /// The innermost open composite block.
  CompositeBlock block;

  /// The open composite blocks, the document first.
  final List<CompositeBlock> stack = [];
  final Line _line = Line();
  bool _atEnd = false;
  final _FragmentCursor? _fragments;
  final int _to;

  /// The start of the current line.
  int lineStart = 0;
  int _lineEnd = 0;

  /// How many nodes of an earlier tree this parse lifted whole, for a test to hold the reuse to.
  int reused = 0;

  /// Runs the parse to its end.
  Tree parseToEnd() {
    for (;;) {
      final done = advance();
      if (done != null) return done;
    }
  }

  /// Parses one more block. The finished tree once the text has run out, null until then.
  Tree? advance() {
    final line = _line;
    for (;;) {
      for (var markI = 0; ;) {
        final next = line.depth < stack.length ? stack[stack.length - 1] : null;
        while (markI < line.markers.length && (next == null || line.markers[markI].from < next.end)) {
          final mark = line.markers[markI++];
          addNode(mark.type, mark.from, mark.to);
        }
        if (next == null) break;
        finishContext();
      }
      if (line.pos < line.text.length) break;
      // Empty line
      if (!nextLine()) return _finish();
    }

    if (_fragments != null && _reuseFragment(line.basePos)) return null;

    start:
    for (;;) {
      for (final type in parser.blockParsers) {
        if (type != null) {
          final result = type(this, line);
          if (result != false) {
            if (result == true) return null;
            line.forward();
            continue start;
          }
        }
      }
      break;
    }
    if (line.pos == line.text.length) return nextLine() ? null : _finish();

    final leaf = LeafBlock(lineStart + line.pos, _slice(line.text, line.pos));
    for (final parse in parser.leafBlockParsers) {
      if (parse != null) {
        final leafParser = parse(this, leaf);
        if (leafParser != null) leaf.parsers.add(leafParser);
      }
    }
    lines:
    while (nextLine()) {
      if (line.pos == line.text.length) break;
      if (line.indent < line.baseIndent + 4) {
        for (final stop in parser.endLeafBlock) {
          if (stop(this, line, leaf)) break lines;
        }
      }
      for (final leafParser in leaf.parsers) {
        if (leafParser.nextLine(this, line, leaf)) return null;
      }
      leaf.content += '\n${line.scrub()}';
      for (final m in line.markers) {
        leaf.marks.add(m);
      }
    }
    finishLeaf(leaf);
    return null;
  }

  bool _reuseFragment(int start) {
    final fragments = _fragments!;
    if (!fragments.moveTo(lineStart + start, lineStart) || !fragments.matches(block.hash)) return false;
    final taken = fragments.takeNodes(this);
    if (taken == 0) return false;
    lineStart += taken;
    if (lineStart < _to) {
      lineStart++;
      _readLine();
    } else {
      _atEnd = true;
      _readLine();
    }
    return true;
  }

  /// The number of parent blocks surrounding the current block.
  int get depth => stack.length;

  /// Get the type of the parent block at the given depth. When no depth is passed, return the type of the innermost
  /// parent.
  NodeType parentType([int? depth]) => parser.nodeTypes[stack[depth ?? this.depth - 1].type];

  /// Move to the next input line. This should only be called by (non-composite) block parsers that consume the line
  /// directly, or leaf block parser `nextLine` methods when they consume the current line (and return true).
  bool nextLine() {
    lineStart += _line.text.length;
    if (_lineEnd >= _to) {
      _atEnd = true;
      _readLine();
      return false;
    } else {
      lineStart++;
      _readLine();
      return true;
    }
  }

  /// Retrieve the text of the line after the current one, without actually moving the context's current line
  /// forward.
  String peekLine() => _lineAt(_lineEnd + 1);

  /// The text of the line that starts at [start]: up to its line feed, or nothing past the end.
  String _lineAt(int start) {
    if (start >= _to) return '';
    final eol = input.indexOf('\n', start);
    return input.substring(start, eol < 0 ? _to : eol);
  }

  /// Populate this.line with the content of the next line. Skip leading characters covered by composite blocks.
  void _readLine() {
    final line = _line, text = _lineAt(lineStart);
    _lineEnd = lineStart + text.length;
    line.reset(text);
    for (; line.depth < stack.length; line.depth++) {
      final cx = stack[line.depth], handler = parser.skipContextMarkup[cx.type];
      if (handler == null) throw StateError('Unhandled block context ${parser.nodeTypes[cx.type].name}');
      final marks = line.markers.length;
      if (!handler(cx, this, line)) {
        if (line.markers.length > marks) cx.end = line.markers[line.markers.length - 1].to;
        line.forward();
        break;
      }
      line.forward();
    }
  }

  /// The end position of the previous line.
  int prevLineEnd() => _atEnd ? lineStart : lineStart - 1;

  /// Opens a composite block of a built-in type.
  void startContext(int type, int start, [int value = 0]) {
    block = CompositeBlock.create(type, value, lineStart + start, block.hash, lineStart + _line.text.length);
    stack.add(block);
  }

  /// Start a composite block. Should only be called from block parser functions that return null.
  void startComposite(String type, int start, [int value = 0]) {
    startContext(parser.getNodeType(type), start, value);
  }

  /// Adds a node to the open block: a finished [Tree], or a type id for an empty node from [from] to [to] (the end
  /// of the line before, when [to] is left out).
  void addNode(Object block, int from, [int? to]) {
    final tree = block is Tree ? block : Tree.leaf(parser.nodeTypes[block as int], (to ?? prevLineEnd()) - from);
    this.block.addChild(tree, from - this.block.from);
  }

  /// Add a block element. Can be called by block parsers.
  void addElement(Element elt) {
    block.addChild(elt.toTree(parser.nodeTypes), elt.from - block.from);
  }

  /// Add a block element from a leaf parser. This makes sure any extra composite block markup (such as blockquote
  /// markers) inside the block are also added to the syntax tree.
  void addLeafElement(LeafBlock leaf, Element elt) {
    addNode(_treeOf(parser.nodeTypes, elt.type, _injectMarks(elt.children, leaf.marks), elt.from, elt.to), elt.from);
  }

  /// Closes the innermost composite block and puts it in the one around it.
  void finishContext() {
    final cx = stack.removeLast();
    final top = stack[stack.length - 1];
    top.addChild(cx.toTree(parser.nodeTypes), cx.from - top.from);
    block = top;
  }

  Tree _finish() {
    while (stack.length > 1) {
      finishContext();
    }
    return block.toTree(parser.nodeTypes, lineStart);
  }

  /// Ends a leaf block: the watching parser that claims it makes its node, else it is a paragraph.
  void finishLeaf(LeafBlock leaf) {
    for (final leafParser in leaf.parsers) {
      if (leafParser.finish(this, leaf)) return;
    }
    final inline = _injectMarks(parser.parseInline(leaf.content, leaf.start), leaf.marks);
    addNode(_treeOf(parser.nodeTypes, Type.paragraph, inline, leaf.start, leaf.start + leaf.content.length), leaf.start);
  }

  /// Create an [Element] object to represent some syntax node.
  Element elt(String type, int from, int to, [List<Element> children = const []]) {
    return _elt(parser.getNodeType(type), from, to, children);
  }

  /// An [Element] that is an already finished [tree], at [at].
  Element eltOfTree(Tree tree, int at) => Element.ofTree(tree, at);
}

/// Lezer's `NodeSpec`. Used in the configuration ([MarkdownConfig.defineNodes]) to define new syntax node types.
class NodeSpec {
  const NodeSpec(this.name, {this.block = false, this.composite});

  /// The node's name.
  final String name;

  /// Should be set to true if this type represents a block node.
  final bool block;

  /// If this is a composite block, this should hold a function that, at the start of a new line where that block is
  /// active, checks whether the composite block should continue (return value) and optionally adjusts
  /// ([Line.moveBase]) the line's base position and registers ([Line.addMarker]) nodes for any markers involved in
  /// the block's syntax.
  final bool Function(BlockContext cx, Line line, int value)? composite;
}

/// Lezer's `InlineParser`. Inline parsers are called for every character of parts of the document that are parsed as
/// inline content.
class InlineParser {
  const InlineParser({required this.name, required this.parse, this.before, this.after});

  /// This parser's name, which can be used by other parsers to indicate a relative precedence.
  final String name;

  /// The parse function. Gets the next character and its position as arguments. Should return -1 if it doesn't
  /// handle the character, or add some element ([InlineContext.addElement]) or delimiter
  /// ([InlineContext.addDelimiter]) and return the end position of the content it parsed if it can.
  final InlineParse parse;

  /// When given, this parser will be installed directly before the parser with the given name. The default
  /// configuration defines inline parsers with names Escape, Entity, InlineCode, HTMLTag, Emphasis, HardBreak, Link,
  /// and Image. When no `before` or `after` property is given, the parser is added to the end of the list.
  final String? before;

  /// When given, the parser will be installed directly _after_ the parser with the given name.
  final String? after;
}

/// Lezer's `BlockParser`. Block parsers handle block-level structure. There are three general types of block
/// parsers:
///
/// - Composite block parsers, which handle things like lists and blockquotes. These define a [parse] method that
///   starts a composite block ([BlockContext.startComposite]) and returns null when it recognizes its syntax. The
///   node type used by such a block must define a [NodeSpec.composite] function as well.
/// - Eager leaf block parsers, used for things like code or HTML blocks. These can unambiguously recognize their
///   content from its first line. They define a [parse] method that, if it recognizes the construct, moves
///   ([BlockContext.nextLine]) the current line forward to the line beyond the end of the block, adds
///   ([BlockContext.addElement]) a syntax node for the block, and returns true.
/// - Leaf block parsers that observe a paragraph-like construct as it comes in, and optionally decide to handle it
///   at some point. This is used for "setext" (underlined) headings and link references. These define a [leaf]
///   method that checks the first line of the block and returns a [LeafBlockParser] object if it wants to observe
///   that block.
class BlockParser {
  const BlockParser({required this.name, this.parse, this.leaf, this.endLeaf, this.before, this.after});

  /// The name of the parser. Can be used by other block parsers to specify precedence.
  final String name;

  /// The eager parse function.
  final BlockParse? parse;

  /// A leaf parse function. If no regular parse functions match for a given line, its content will be accumulated
  /// for a paragraph-style block. This method can return an object that overrides that style of parsing in some
  /// situations.
  final LeafParse? leaf;

  /// Some constructs, such as code blocks or newly started blockquotes, can interrupt paragraphs even without a
  /// blank line. If your construct can do this, provide a predicate here that recognizes lines that should end a
  /// paragraph (or other non-eager leaf block).
  final EndLeaf? endLeaf;

  /// When given, this parser will be installed directly before the block parser with the given name. The default
  /// configuration defines block parsers with names LinkReference, IndentedCode, FencedCode, Blockquote,
  /// HorizontalRule, BulletList, OrderedList, ATXHeading, HTMLBlock, and SetextHeading.
  final String? before;

  /// When given, the parser will be installed directly _after_ the parser with the given name.
  final String? after;
}

/// Lezer's `LeafBlockParser`. Objects that are used to override paragraph-style blocks should conform to this
/// interface.
abstract interface class LeafBlockParser {
  /// Update the parser's state for the next line, and optionally finish the block. This is not called for the first
  /// line (the object is constructed at that line), but for any further lines. When it returns `true`, the block is
  /// finished. It is okay for the function to consume the current line or any subsequent lines when returning true.
  bool nextLine(BlockContext cx, Line line, LeafBlock leaf);

  /// Called when the block is finished by external circumstances (such as a blank line or the start of another
  /// construct). If this parser can handle the block up to its current position, it should finish the block
  /// ([BlockContext.addLeafElement]) and return true.
  bool finish(BlockContext cx, LeafBlock leaf);
}

/// Lezer's `MarkdownConfig`. Objects of this type are used to configure the Markdown parser
/// ([MarkdownParser.configure]). Where Lezer nests arrays of these (`MarkdownExtension`), here a group is a list
/// (`gfm` in extension.dart) spread into the list `configure` takes.
class MarkdownConfig {
  const MarkdownConfig({
    this.defineNodes = const [],
    this.parseBlock = const [],
    this.parseInline = const [],
    this.remove = const [],
  });

  /// Define new node types for use in parser extensions.
  final List<NodeSpec> defineNodes;

  /// Define additional block parsing logic.
  final List<BlockParser> parseBlock;

  /// Define new inline parsing logic.
  final List<InlineParser> parseInline;

  /// Remove the named parsers from the configuration.
  final List<String> remove;
}

/// Lezer's `MarkdownParser`. A Markdown parser configuration.
class MarkdownParser {
  MarkdownParser._(
    this.nodeTypes,
    this.blockParsers,
    this.leafBlockParsers,
    this.blockNames,
    this.endLeafBlock,
    this.skipContextMarkup,
    this.inlineParsers,
    this.inlineNames,
  ) {
    for (final type in nodeTypes) {
      _nodeTypeIds[type.name] = type.id;
    }
  }

  /// The parser's syntax node types, by id (Lezer's `nodeSet.types`).
  final List<NodeType> nodeTypes;
  final Map<String, int> _nodeTypeIds = {};
  final List<BlockParse?> blockParsers;
  final List<LeafParse?> leafBlockParsers;
  final List<String> blockNames;
  final List<EndLeaf> endLeafBlock;
  final Map<int, SkipMarkup> skipContextMarkup;
  final List<InlineParse?> inlineParsers;
  final List<String> inlineNames;

  /// Parses [text] whole, or, given [fragments] of earlier trees, only where they do not reach.
  Tree parse(String text, {List<TreeFragment> fragments = const []}) => startParse(text, fragments: fragments).parseToEnd();

  /// A parse to step through a block at a time ([BlockContext.advance]).
  BlockContext startParse(String text, {List<TreeFragment> fragments = const []}) {
    return BlockContext._(this, text, fragments);
  }

  /// Parses [text], the note after an edit, lifting from [previous] (the tree of the note before it) every block
  /// the [changes] left alone. [changes] are in order, as CodeMirror's `ChangeSet.iterChangedRanges` gives them.
  ///
  /// What CodeMirror's language state does on a transaction: `TreeFragment.applyChanges` over the old tree's
  /// fragment, then a parse with what is left. The tree is the one a parse from nothing would give.
  Tree reparse(Tree previous, String text, List<ChangedRange> changes) {
    return parse(text, fragments: TreeFragment.applyChanges(TreeFragment.addTree(previous), changes));
  }

  /// Reconfigure the parser. The configs are taken together, as Lezer takes a nested array of them: every
  /// `defineNodes` first, then every `remove`, then the block parsers and the inline parsers, each in the order
  /// given.
  MarkdownParser configure(List<MarkdownConfig> spec) {
    if (spec.isEmpty) return this;
    final defineNodes = [for (final config in spec) ...config.defineNodes];
    final parseBlock = [for (final config in spec) ...config.parseBlock];
    final parseInline = [for (final config in spec) ...config.parseInline];
    final remove = [for (final config in spec) ...config.remove];

    var nodeTypes = this.nodeTypes;
    var skipContextMarkup = this.skipContextMarkup;
    final blockParsers = [...this.blockParsers], leafBlockParsers = [...this.leafBlockParsers];
    final blockNames = [...this.blockNames], inlineParsers = [...this.inlineParsers];
    final inlineNames = [...this.inlineNames], endLeafBlock = [...this.endLeafBlock];

    if (defineNodes.isNotEmpty) {
      skipContextMarkup = {...skipContextMarkup};
      nodeTypes = [...nodeTypes];
      for (final s in defineNodes) {
        if (nodeTypes.any((t) => t.name == s.name)) continue;
        final composite = s.composite;
        final id = nodeTypes.length;
        if (composite != null) skipContextMarkup[id] = (bl, cx, line) => composite(cx, line, bl.value);
        final groups = composite != null
            ? const ['Block', 'BlockContext']
            : !s.block
            ? const <String>[]
            : const ['Block', 'LeafBlock'];
        nodeTypes.add(NodeType(id, s.name, groups: groups));
      }
    }

    if (remove.isNotEmpty) {
      for (final rm in remove) {
        final block = this.blockNames.indexOf(rm), inline = this.inlineNames.indexOf(rm);
        if (block > -1) blockParsers[block] = leafBlockParsers[block] = null;
        if (inline > -1) inlineParsers[inline] = null;
      }
    }

    if (parseBlock.isNotEmpty) {
      for (final spec in parseBlock) {
        final found = blockNames.indexOf(spec.name);
        if (found > -1) {
          blockParsers[found] = spec.parse;
          leafBlockParsers[found] = spec.leaf;
        } else {
          final pos = spec.before != null
              ? _findName(blockNames, spec.before!)
              : spec.after != null
              ? _findName(blockNames, spec.after!) + 1
              : blockNames.length - 1;
          blockParsers.insert(pos, spec.parse);
          leafBlockParsers.insert(pos, spec.leaf);
          blockNames.insert(pos, spec.name);
        }
        if (spec.endLeaf != null) endLeafBlock.add(spec.endLeaf!);
      }
    }

    if (parseInline.isNotEmpty) {
      for (final spec in parseInline) {
        final found = inlineNames.indexOf(spec.name);
        if (found > -1) {
          inlineParsers[found] = spec.parse;
        } else {
          final pos = spec.before != null
              ? _findName(inlineNames, spec.before!)
              : spec.after != null
              ? _findName(inlineNames, spec.after!) + 1
              : inlineNames.length - 1;
          inlineParsers.insert(pos, spec.parse);
          inlineNames.insert(pos, spec.name);
        }
      }
    }

    return MarkdownParser._(
      nodeTypes,
      blockParsers,
      leafBlockParsers,
      blockNames,
      endLeafBlock,
      skipContextMarkup,
      inlineParsers,
      inlineNames,
    );
  }

  /// The id of the node type called [name].
  int getNodeType(String name) {
    final found = _nodeTypeIds[name];
    if (found == null) throw RangeError("Unknown node type '$name'");
    return found;
  }

  /// Parse the given piece of inline text at the given offset, returning an array of [Element] objects representing
  /// the inline content.
  List<Element> parseInline(String text, int offset) {
    final cx = InlineContext._(this, text, offset);
    final end = cx.end, parsers = inlineParsers;
    outer:
    for (var pos = offset; pos < end;) {
      final next = cx.char(pos);
      for (final token in parsers) {
        if (token != null) {
          final result = token(cx, next, pos);
          if (result >= 0) {
            pos = result;
            continue outer;
          }
        }
      }
      pos++;
    }
    return cx.resolveMarkers(0);
  }
}

int _findName(List<String> names, String name) {
  final found = names.indexOf(name);
  if (found < 0) throw RangeError('Position specified relative to unknown parser $name');
  return found;
}

List<NodeType> _defaultNodeTypes() {
  return [
    for (var i = 0; i < Type.names.length; i++)
      NodeType(
        i,
        Type.names[i],
        groups: i == 0 || i >= Type.escape
            ? const []
            : _defaultSkipMarkup.containsKey(i)
            ? const ['Block', 'BlockContext']
            : const ['Block', 'LeafBlock'],
        isTop: i == Type.document,
      ),
  ];
}

/// Lezer's `Element`. Elements are used to compose syntax nodes during parsing.
///
/// Lezer has a second class, `TreeElement`, for a node that is already a [Tree]; here that is an element made with
/// [Element.ofTree].
class Element {
  Element._(this.type, this.from, this.to, this.children) : tree = null;

  /// Lezer's `TreeElement`: a finished [tree] placed at [from].
  Element.ofTree(Tree this.tree, this.from) : type = tree.type.id, to = from + tree.length, children = const [];

  /// The node's type id.
  final int type;

  /// The start of the node, as an offset from the start of the document.
  final int from;

  /// The end of the node.
  int to;

  /// The node's child nodes.
  final List<Element> children;

  /// The tree this element stands for, when it was made from one.
  final Tree? tree;

  Tree toTree(List<NodeType> types) => tree ?? _treeOf(types, type, children, from, to);
}

Element _elt(int type, int from, int to, [List<Element> children = const []]) => Element._(type, from, to, children);

/// What Lezer's `Buffer.writeElements(elts, -from).finish(type, to - from)` builds: a node of [type] from [from] to
/// [to] holding [elts].
Tree _treeOf(List<NodeType> types, int type, List<Element> elts, int from, int to) {
  if (elts.isEmpty) return Tree.leaf(types[type], to - from);
  return Tree(
    types[type],
    List<Tree>.generate(elts.length, (i) => elts[i].toTree(types), growable: false),
    List<int>.generate(elts.length, (i) => elts[i].from - from, growable: false),
    to - from,
  );
}

// Lezer's `Mark`.
const int _markNone = 0, _markOpen = 1, _markClose = 2;

/// Lezer's `DelimiterType`. Delimiters are used during inline parsing to store the positions of things that _might_
/// be delimiters, if another matching delimiter is found. They are identified by objects with these properties.
class DelimiterType {
  const DelimiterType({this.resolve, this.mark});

  /// If this is given, the delimiter should be matched automatically when a piece of inline content is finished.
  /// Such delimiters will be matched with delimiters of the same type according to their open and close
  /// ([InlineContext.addDelimiter]) properties. When a match is found, the content between the delimiters is wrapped
  /// in a node whose name is given by the value of this property.
  ///
  /// When this isn't given, you need to match the delimiter eagerly using the
  /// [InlineContext.findOpeningDelimiter] and [InlineContext.takeContent] methods.
  final String? resolve;

  /// If the delimiter itself should, when matched, create a syntax node, set this to the name of the syntax node.
  final String? mark;
}

// Not const: two delimiter types are the same type only when they are the same object, and these two are spelled
// alike.
final DelimiterType _emphasisUnderscore = DelimiterType(resolve: 'Emphasis', mark: 'EmphasisMark');
final DelimiterType _emphasisAsterisk = DelimiterType(resolve: 'Emphasis', mark: 'EmphasisMark');
final DelimiterType _linkStart = DelimiterType(), _imageStart = DelimiterType();

/// Lezer's `InlineDelimiter`: a run that may yet open or close something.
class InlineDelimiter {
  InlineDelimiter(this.type, this.from, this.to, this.side);

  final DelimiterType type;
  final int from, to;

  /// Whether it may open (1), close (2), both (3) or neither (0).
  int side;
}

const String _escapable = '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';

/// Lezer's `Punctuation`: what CommonMark counts as punctuation beside a delimiter run, in its Unicode form (every
/// symbol and punctuation character), which is the one any engine that knows `\p{…}` runs.
final RegExp punctuation = RegExp(r'[\p{S}|\p{P}]', unicode: true);

/// `/\s|^$/`: a space, or nothing at all (the edge of the text).
final RegExp _spaceOrEdge = RegExp(r'\s|^$');

final RegExp _entity = RegExp(r'^(?:#\d+|#x[a-f\d]+|\w+);', caseSensitive: false);
final RegExp _autolinkTag = RegExp(
  r"^(?:[a-z][-\w+.]+:[^\s>]+|[a-z\d.!#$%&'*+/=?^_`{|}~-]+@[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?(?:\.[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?)*)>",
  caseSensitive: false,
);
final RegExp _commentTag = RegExp(r'^!--[^>](?:-[^-]|[^-])*?-->', caseSensitive: false);
final RegExp _procInstTag = RegExp(r'^\?[\s\S]*?\?>');
final RegExp _htmlTag = RegExp(
  r'''^(?:![A-Z][\s\S]*?>|!\[CDATA\[[\s\S]*?\]\]>|/\s*[a-zA-Z][\w-]*\s*>|\s*[a-zA-Z][\w-]*(\s+[a-zA-Z:_][\w\-.:]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*(/\s*)?>)''',
);
final RegExp _linkOpener = RegExp(r'[(\[]');

int _escape(InlineContext cx, int next, int start) {
  if (next != 92 /* '\\' */ || start == cx.end - 1) return -1;
  final escaped = cx.char(start + 1);
  for (var i = 0; i < _escapable.length; i++) {
    if (_escapable.codeUnitAt(i) == escaped) return cx.append(_elt(Type.escape, start, start + 2));
  }
  return -1;
}

int _entityInline(InlineContext cx, int next, int start) {
  if (next != 38 /* '&' */ ) return -1;
  final m = _entity.firstMatch(cx.slice(start + 1, start + 31));
  return m != null ? cx.append(_elt(Type.entity, start, start + 1 + m[0]!.length)) : -1;
}

int _inlineCode(InlineContext cx, int next, int start) {
  if (next != 96 /* '`' */ || start != 0 && cx.char(start - 1) == 96) return -1;
  var pos = start + 1;
  while (pos < cx.end && cx.char(pos) == 96) {
    pos++;
  }
  final size = pos - start;
  var curSize = 0;
  for (; pos < cx.end; pos++) {
    if (cx.char(pos) == 96) {
      curSize++;
      if (curSize == size && cx.char(pos + 1) != 96) {
        return cx.append(
          _elt(Type.inlineCode, start, pos + 1, [
            _elt(Type.codeMark, start, start + size),
            _elt(Type.codeMark, pos + 1 - size, pos + 1),
          ]),
        );
      }
    } else {
      curSize = 0;
    }
  }
  return -1;
}

int _htmlTagInline(InlineContext cx, int next, int start) {
  // or URL
  if (next != 60 /* '<' */ || start == cx.end - 1) return -1;
  final after = cx.slice(start + 1, cx.end);
  final url = _autolinkTag.firstMatch(after);
  if (url != null) {
    final length = url[0]!.length;
    return cx.append(
      _elt(Type.autolink, start, start + 1 + length, [
        _elt(Type.linkMark, start, start + 1),
        // url[0] includes the closing bracket, so exclude it from this slice
        _elt(Type.url, start + 1, start + length),
        _elt(Type.linkMark, start + length, start + 1 + length),
      ]),
    );
  }
  final comment = _commentTag.firstMatch(after);
  if (comment != null) return cx.append(_elt(Type.comment, start, start + 1 + comment[0]!.length));
  final procInst = _procInstTag.firstMatch(after);
  if (procInst != null) return cx.append(_elt(Type.processingInstruction, start, start + 1 + procInst[0]!.length));
  final m = _htmlTag.firstMatch(after);
  if (m == null) return -1;
  return cx.append(_elt(Type.htmlTag, start, start + 1 + m[0]!.length));
}

int _emphasis(InlineContext cx, int next, int start) {
  if (next != 95 && next != 42) return -1;
  var pos = start + 1;
  while (cx.char(pos) == next) {
    pos++;
  }
  final before = cx.slice(start - 1, start), after = cx.slice(pos, pos + 1);
  final pBefore = punctuation.hasMatch(before), pAfter = punctuation.hasMatch(after);
  final sBefore = _spaceOrEdge.hasMatch(before), sAfter = _spaceOrEdge.hasMatch(after);
  final leftFlanking = !sAfter && (!pAfter || sBefore || pBefore);
  final rightFlanking = !sBefore && (!pBefore || sAfter || pAfter);
  final canOpen = leftFlanking && (next == 42 || !rightFlanking || pBefore);
  final canClose = rightFlanking && (next == 42 || !leftFlanking || pAfter);
  return cx.append(
    InlineDelimiter(
      next == 95 ? _emphasisUnderscore : _emphasisAsterisk,
      start,
      pos,
      (canOpen ? _markOpen : _markNone) | (canClose ? _markClose : _markNone),
    ),
  );
}

int _hardBreak(InlineContext cx, int next, int start) {
  if (next == 92 /* '\\' */ && cx.char(start + 1) == 10 /* '\n' */ ) {
    return cx.append(_elt(Type.hardBreak, start, start + 2));
  }
  if (next == 32) {
    var pos = start + 1;
    while (cx.char(pos) == 32) {
      pos++;
    }
    if (cx.char(pos) == 10 && pos >= start + 2) return cx.append(_elt(Type.hardBreak, start, pos + 1));
  }
  return -1;
}

int _link(InlineContext cx, int next, int start) {
  return next == 91 /* '[' */ ? cx.append(InlineDelimiter(_linkStart, start, start + 1, _markOpen)) : -1;
}

int _image(InlineContext cx, int next, int start) {
  return next == 33 /* '!' */ && cx.char(start + 1) == 91 /* '[' */
      ? cx.append(InlineDelimiter(_imageStart, start, start + 2, _markOpen))
      : -1;
}

int _linkEnd(InlineContext cx, int next, int start) {
  if (next != 93 /* ']' */ ) return -1;
  // Scanning back to the next link/image start marker
  for (var i = cx.parts.length - 1; i >= 0; i--) {
    final part = cx.parts[i];
    if (part is InlineDelimiter && (identical(part.type, _linkStart) || identical(part.type, _imageStart))) {
      // If this one has been set invalid (because it would produce a nested link) or there's no valid link here
      // ignore both.
      if (part.side == 0 ||
          cx.skipSpace(part.to) == start && !_linkOpener.hasMatch(cx.slice(start + 1, start + 2))) {
        cx.parts[i] = null;
        return -1;
      }
      // Finish the content and replace the entire range in this.parts with the link/image node.
      final content = cx.takeContent(i);
      final link = _finishLink(cx, content, identical(part.type, _linkStart) ? Type.link : Type.image, part.from, start + 1);
      cx.parts.add(link);
      // Set any open-link markers before this link to invalid.
      if (identical(part.type, _linkStart)) {
        for (var j = 0; j < i; j++) {
          final p = cx.parts[j];
          if (p is InlineDelimiter && identical(p.type, _linkStart)) p.side = _markNone;
        }
      }
      return link.to;
    }
  }
  return -1;
}

/// Lezer's `DefaultInline`, in its order.
const List<String> _defaultInlineNames = [
  'Escape',
  'Entity',
  'InlineCode',
  'HTMLTag',
  'Emphasis',
  'HardBreak',
  'Link',
  'Image',
  'LinkEnd',
];

const List<InlineParse?> _defaultInline = [
  _escape,
  _entityInline,
  _inlineCode,
  _htmlTagInline,
  _emphasis,
  _hardBreak,
  _link,
  _image,
  _linkEnd,
];

Element _finishLink(InlineContext cx, List<Element> content, int type, int start, int startPos) {
  final text = cx.text, next = cx.char(startPos);
  var endPos = startPos;
  content.insert(0, _elt(Type.linkMark, start, start + (type == Type.image ? 2 : 1)));
  content.add(_elt(Type.linkMark, startPos - 1, startPos));
  if (next == 40 /* '(' */ ) {
    var pos = cx.skipSpace(startPos + 1);
    final dest = _parseURL(text, pos - cx.offset, cx.offset);
    Object? title;
    if (dest is Element) {
      pos = cx.skipSpace(dest.to);
      // The destination and title must be separated by whitespace
      if (pos != dest.to) {
        title = _parseLinkTitle(text, pos - cx.offset, cx.offset);
        if (title is Element) pos = cx.skipSpace(title.to);
      }
    }
    if (cx.char(pos) == 41 /* ')' */ ) {
      content.add(_elt(Type.linkMark, startPos, startPos + 1));
      endPos = pos + 1;
      if (dest is Element) content.add(dest);
      if (title is Element) content.add(title);
      content.add(_elt(Type.linkMark, pos, endPos));
    }
  } else if (next == 91 /* '[' */ ) {
    final label = _parseLinkLabel(text, startPos - cx.offset, cx.offset, false);
    if (label is Element) {
      content.add(label);
      endPos = label.to;
    }
  }
  return _elt(type, start, endPos, content);
}

// These return `null` when falling off the end of the input, `false` when parsing fails otherwise (for use in the
// incremental link reference parser), and the element when there is one.

Object? _parseURL(String text, int start, int offset) {
  final next = _charAt(text, start);
  if (next == 60 /* '<' */ ) {
    for (var pos = start + 1; pos < text.length; pos++) {
      final ch = text.codeUnitAt(pos);
      if (ch == 62 /* '>' */ ) return _elt(Type.url, start + offset, pos + 1 + offset);
      if (ch == 60 || ch == 10 /* '<\n' */ ) return false;
    }
    return null;
  } else {
    var depth = 0, pos = start;
    for (var escaped = false; pos < text.length; pos++) {
      final ch = text.codeUnitAt(pos);
      if (space(ch)) {
        break;
      } else if (escaped) {
        escaped = false;
      } else if (ch == 40 /* '(' */ ) {
        depth++;
      } else if (ch == 41 /* ')' */ ) {
        if (depth == 0) break;
        depth--;
      } else if (ch == 92 /* '\\' */ ) {
        escaped = true;
      }
    }
    return pos > start
        ? _elt(Type.url, start + offset, pos + offset)
        : pos == text.length
        ? null
        : false;
  }
}

Object? _parseLinkTitle(String text, int start, int offset) {
  final next = _charAt(text, start);
  if (next != 39 && next != 34 && next != 40 /* '"\'(' */ ) return false;
  final end = next == 40 ? 41 : next;
  for (var pos = start + 1, escaped = false; pos < text.length; pos++) {
    final ch = text.codeUnitAt(pos);
    if (escaped) {
      escaped = false;
    } else if (ch == end) {
      return _elt(Type.linkTitle, start + offset, pos + 1 + offset);
    } else if (ch == 92 /* '\\' */ ) {
      escaped = true;
    }
  }
  return null;
}

Object? _parseLinkLabel(String text, int start, int offset, bool requireNonWS) {
  final limit = start + 1 + 999;
  for (var escaped = false, pos = start + 1, end = text.length < limit ? text.length : limit; pos < end; pos++) {
    final ch = text.codeUnitAt(pos);
    if (escaped) {
      escaped = false;
    } else if (ch == 93 /* ']' */ ) {
      return requireNonWS ? false : _elt(Type.linkLabel, start + offset, pos + 1 + offset);
    } else {
      if (requireNonWS && !space(ch)) requireNonWS = false;
      if (ch == 91 /* '[' */ ) {
        return false;
      } else if (ch == 92 /* '\\' */ ) {
        escaped = true;
      }
    }
  }
  return null;
}

/// Lezer's `InlineContext`. Inline parsing functions get access to this context, and use it to read the content and
/// emit syntax nodes.
class InlineContext {
  InlineContext._(this.parser, this.text, this.offset) : end = offset + text.length;

  /// What has been found so far, in order: an [Element], an [InlineDelimiter] still unmatched, or null where one
  /// was taken away.
  final List<Object?> parts = [];

  /// The parser that is being used.
  final MarkdownParser parser;

  /// The text of this inline section.
  final String text;

  /// The starting offset of the section in the document.
  final int offset;

  /// The position of the end of this inline section.
  final int end;

  /// Get the character code at the given (document-relative) position.
  int char(int pos) => pos >= end ? -1 : _charAt(text, pos - offset);

  /// Get a substring of this inline section. Again uses document-relative positions.
  String slice(int from, int to) => _slice(text, from - offset, to - offset);

  /// Adds an element or a delimiter to [parts] and answers where it ends.
  int append(Object elt) {
    parts.add(elt);
    return elt is Element ? elt.to : (elt as InlineDelimiter).to;
  }

  /// Add a delimiter ([DelimiterType]) at this given position. `open` and `close` indicate whether this delimiter is
  /// opening, closing, or both. Returns the end of the delimiter, for convenient returning from parse functions.
  int addDelimiter(DelimiterType type, int from, int to, bool open, bool close) {
    return append(InlineDelimiter(type, from, to, (open ? _markOpen : _markNone) | (close ? _markClose : _markNone)));
  }

  /// Returns true when there is an unmatched link or image opening token before the current position.
  bool get hasOpenLink {
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part is InlineDelimiter && (identical(part.type, _linkStart) || identical(part.type, _imageStart))) {
        return true;
      }
    }
    return false;
  }

  /// Add an inline element. Returns the end of the element.
  int addElement(Element elt) => append(elt);

  /// Resolve markers between this.parts.length and from, wrapping matched markers in the appropriate node and
  /// updating the content of this.parts.
  List<Element> resolveMarkers(int from) {
    // Scan forward, looking for closing tokens
    for (var i = from; i < parts.length; i++) {
      final close = parts[i];
      if (!(close is InlineDelimiter && close.type.resolve != null && (close.side & _markClose) != 0)) continue;

      final emp = identical(close.type, _emphasisUnderscore) || identical(close.type, _emphasisAsterisk);
      final closeSize = close.to - close.from;
      InlineDelimiter? open;
      var j = i - 1;
      // Continue scanning for a matching opening token
      for (; j >= from; j--) {
        final part = parts[j];
        if (part is InlineDelimiter &&
            (part.side & _markOpen) != 0 &&
            identical(part.type, close.type) &&
            // Ignore emphasis delimiters where the character count doesn't match
            !(emp &&
                ((close.side & _markOpen) != 0 || (part.side & _markClose) != 0) &&
                (part.to - part.from + closeSize) % 3 == 0 &&
                ((part.to - part.from) % 3 != 0 || closeSize % 3 != 0))) {
          open = part;
          break;
        }
      }
      if (open == null) continue;

      var type = close.type.resolve!;
      final content = <Element>[];
      var start = open.from, end = close.to;
      // Emphasis marker effect depends on the character count. Size consumed is minimum of the two markers.
      if (emp) {
        var size = open.to - open.from;
        if (closeSize < size) size = closeSize;
        if (size > 2) size = 2;
        start = open.to - size;
        end = close.from + size;
        type = size == 1 ? 'Emphasis' : 'StrongEmphasis';
      }
      // Move the covered region into content, optionally adding marker nodes
      if (open.type.mark != null) content.add(elt(open.type.mark!, start, open.to));
      for (var k = j + 1; k < i; k++) {
        final part = parts[k];
        if (part is Element) content.add(part);
        parts[k] = null;
      }
      if (close.type.mark != null) content.add(elt(close.type.mark!, close.from, end));
      final element = elt(type, start, end, content);
      // If there are leftover emphasis marker characters, shrink the close/open markers. Otherwise, clear them.
      parts[j] = emp && open.from != start ? InlineDelimiter(open.type, open.from, start, open.side) : null;
      final keep = parts[i] = emp && close.to != end ? InlineDelimiter(close.type, end, close.to, close.side) : null;
      // Insert the new element in this.parts
      if (keep != null) {
        parts.insert(i, element);
      } else {
        parts[i] = element;
      }
    }

    // Collect the elements remaining in this.parts into an array.
    final result = <Element>[];
    for (var i = from; i < parts.length; i++) {
      final part = parts[i];
      if (part is Element) result.add(part);
    }
    return result;
  }

  /// Find an opening delimiter of the given type. Returns `null` if no delimiter is found, or an index that can be
  /// passed to [takeContent] otherwise.
  int? findOpeningDelimiter(DelimiterType type) {
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i];
      if (part is InlineDelimiter && identical(part.type, type) && (part.side & _markOpen) != 0) return i;
    }
    return null;
  }

  /// Remove all inline elements and delimiters starting from the given index (which you should get from
  /// [findOpeningDelimiter]), resolve delimiters inside of them, and return them as an array of elements.
  List<Element> takeContent(int startIndex) {
    final content = resolveMarkers(startIndex);
    parts.length = startIndex;
    return content;
  }

  /// Return the delimiter at the given index. Mostly useful to get additional info out of a delimiter index returned
  /// by [findOpeningDelimiter]. Returns null if there is no delimiter at this index.
  InlineDelimiter? getDelimiterAt(int index) {
    final part = index >= 0 && index < parts.length ? parts[index] : null;
    return part is InlineDelimiter ? part : null;
  }

  /// Skip space after the given (document) position, returning either the position of the next non-space character
  /// or the end of the section.
  int skipSpace(int from) => _skipSpace(text, from - offset) + offset;

  /// Create an [Element] for a syntax node.
  Element elt(String type, int from, int to, [List<Element> children = const []]) {
    return _elt(parser.getNodeType(type), from, to, children);
  }

  /// An [Element] that is an already finished [tree], at [at].
  Element eltOfTree(Tree tree, int at) => Element.ofTree(tree, at);

  /// The opening delimiter type used by the standard link parser.
  static DelimiterType get linkStart => _linkStart;

  /// Opening delimiter type used for standard images.
  static DelimiterType get imageStart => _imageStart;
}

List<Element> _injectMarks(List<Element> elements, List<Element> marks) {
  if (marks.isEmpty) return elements;
  if (elements.isEmpty) return marks;
  final elts = [...elements];
  var eI = 0;
  for (final mark in marks) {
    while (eI < elts.length && elts[eI].to < mark.to) {
      eI++;
    }
    if (eI < elts.length && elts[eI].from < mark.from) {
      final e = elts[eI];
      if (e.tree == null) elts[eI] = Element._(e.type, e.from, e.to, _injectMarks(e.children, [mark]));
    } else {
      elts.insert(eI++, mark);
    }
  }
  return elts;
}

// These are blocks that can span blank lines, and should thus only be reused if their next sibling is also being
// reused.
const List<int> _notLast = [Type.codeBlock, Type.listItem, Type.orderedList, Type.bulletList];

/// Lezer's `FragmentCursor`: where the parse is in the earlier trees, for lifting blocks out of them.
class _FragmentCursor {
  _FragmentCursor(this.fragments, this.input) {
    if (fragments.isNotEmpty) fragment = fragments[i++];
  }

  final List<TreeFragment> fragments;
  final String input;

  // Index into fragment array
  int i = 0;
  // Active fragment
  TreeFragment? fragment;
  int fragmentEnd = -1;
  // Cursor into the current fragment, if any. When `moveTo` returns true, this points at the first block after
  // `pos`.
  TreeCursor? cursor;

  void nextFragment() {
    fragment = i < fragments.length ? fragments[i++] : null;
    cursor = null;
    fragmentEnd = -1;
  }

  bool moveTo(int pos, int lineStart) {
    while (this.fragment != null && this.fragment!.to <= pos) {
      nextFragment();
    }
    final fragment = this.fragment;
    if (fragment == null || fragment.from > (pos != 0 ? pos - 1 : 0)) return false;
    if (fragmentEnd < 0) {
      var end = fragment.to;
      while (end > 0 && input.codeUnitAt(end - 1) != 10) {
        end--;
      }
      fragmentEnd = end != 0 ? end - 1 : 0;
    }

    var c = cursor;
    if (c == null) {
      c = cursor = fragment.tree.cursor();
      c.firstChild();
    }

    final rPos = pos + fragment.offset;
    while (c.to <= rPos) {
      if (!c.parent()) return false;
    }
    for (;;) {
      if (c.from >= rPos) return fragment.from <= lineStart;
      if (!c.childAfter(rPos)) return false;
    }
  }

  bool matches(int hash) => cursor!.tree.contextHash == hash;

  int takeNodes(BlockContext cx) {
    final cur = cursor!, off = fragment!.offset, fragEnd = fragmentEnd - (fragment!.openEnd ? 1 : 0);
    final start = cx.lineStart;
    final firstI = cx.block.children.length;
    var end = start, blockI = firstI;
    var prevEnd = end, prevI = blockI;
    for (;;) {
      if (cur.to - off > fragEnd) break;
      cx.addNode(cur.tree, cur.from - off);
      // Taken content must always end in a block, because incremental parsing happens on block boundaries. Never
      // stop directly after an indented code block, since those can continue after any number of blank lines.
      if (cur.type.isA('Block')) {
        if (!_notLast.contains(cur.type.id)) {
          end = cur.to - off;
          blockI = cx.block.children.length;
        } else {
          end = prevEnd;
          blockI = prevI;
        }
        prevEnd = cur.to - off;
        prevI = cx.block.children.length;
      }
      if (!cur.nextSibling()) break;
    }
    while (cx.block.children.length > blockI) {
      cx.block.children.removeLast();
      cx.block.positions.removeLast();
    }
    if (blockI > firstI) cx.reused += blockI - firstI;
    return end - start;
  }
}

/// The default CommonMark parser: Lezer's `parser`.
final MarkdownParser parser = MarkdownParser._(
  _defaultNodeTypes(),
  _defaultBlockParsers,
  _defaultLeafBlocks,
  _defaultBlockNames,
  _defaultEndLeaf,
  _defaultSkipMarkup,
  _defaultInline,
  _defaultInlineNames,
);
