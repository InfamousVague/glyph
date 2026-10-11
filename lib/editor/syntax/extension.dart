// Ported from @lezer/markdown 1.7.2 (src/extension.ts), which is:
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

/// What `@codemirror/lang-markdown`'s `markdownLanguage` adds to CommonMark: `@lezer/markdown`'s `extension.ts`.
///
/// [gfm] is GitHub's four ([table], [taskList], [strikethrough], [autolink]); [superscript], [subscript] and [emoji]
/// are the three more that `markdownLanguage` turns on. Each is a [MarkdownConfig], as in Lezer, and `style` (the
/// highlighting tags) is the one property left behind.
library;

import 'markdown.dart';

const DelimiterType _strikethroughDelim = DelimiterType(resolve: 'Strikethrough', mark: 'StrikethroughMark');

final RegExp _spaceOrEdge = RegExp(r'\s|^$');

/// Lezer's `Strikethrough`. An extension that implements
/// [GFM-style](https://github.github.com/gfm/#strikethrough-extension-) Strikethrough syntax using `~~` delimiters.
final MarkdownConfig strikethrough = MarkdownConfig(
  defineNodes: const [NodeSpec('Strikethrough'), NodeSpec('StrikethroughMark')],
  parseInline: [
    InlineParser(
      name: 'Strikethrough',
      parse: (cx, next, pos) {
        if (next != 126 /* '~' */ || cx.char(pos + 1) != 126 || cx.char(pos + 2) == 126) return -1;
        final before = cx.slice(pos - 1, pos), after = cx.slice(pos + 2, pos + 3);
        final sBefore = _spaceOrEdge.hasMatch(before), sAfter = _spaceOrEdge.hasMatch(after);
        final pBefore = punctuation.hasMatch(before), pAfter = punctuation.hasMatch(after);
        return cx.addDelimiter(
          _strikethroughDelim,
          pos,
          pos + 2,
          !sAfter && (!pAfter || sBefore || pBefore),
          !sBefore && (!pBefore || sAfter || pAfter),
        );
      },
      after: 'Emphasis',
    ),
  ],
);

/// Lezer's `parseRow`. Parse a line as a table row and return the row count. When `elts` is given, push syntax
/// elements for the content onto it.
int _parseRow(BlockContext cx, String line, [int startI = 0, List<Element>? elts, int offset = 0]) {
  var count = 0, first = true, cellStart = -1, cellEnd = -1, esc = false;
  void parseCell() {
    elts!.add(
      cx.elt(
        'TableCell',
        offset + cellStart,
        offset + cellEnd,
        cx.parser.parseInline(line.substring(cellStart, cellEnd), offset + cellStart),
      ),
    );
  }

  for (var i = startI < 0 ? 0 : startI; i < line.length; i++) {
    final next = line.codeUnitAt(i);
    if (next == 124 /* '|' */ && !esc) {
      if (!first || cellStart > -1) count++;
      first = false;
      if (elts != null) {
        if (cellStart > -1) parseCell();
        elts.add(cx.elt('TableDelimiter', i + offset, i + offset + 1));
      }
      cellStart = cellEnd = -1;
    } else if (esc || next != 32 && next != 9) {
      if (cellStart < 0) cellStart = i;
      cellEnd = i + 1;
    }
    esc = !esc && next == 92;
  }
  if (cellStart > -1) {
    count++;
    if (elts != null) parseCell();
  }
  return count;
}

bool _hasPipe(String str, int start) {
  for (var i = start < 0 ? 0 : start; i < str.length; i++) {
    final next = str.codeUnitAt(i);
    if (next == 124 /* '|' */ ) return true;
    if (next == 92 /* '\\' */ ) i++;
  }
  return false;
}

final RegExp _delimiterLine = RegExp(r'^[>\s]*\|?(\s*:?-+:?\s*\|)+(\s*:?-+:?\s*)?$');

/// Whether a line is the row under a table's head, the one of dashes and bars that makes the lines round it a
/// table: no table is parsed without one.
bool isTableDelimiterLine(String text) => text.contains('|') && text.contains('-') && _delimiterLine.hasMatch(text);

/// Lezer's `TableParser`.
class _TableParser implements LeafBlockParser {
  // Null means we haven't seen the second line yet, an empty `isTable` false means this isn't a table, and a list
  // means this is a table and we've parsed the given rows so far.
  List<Element>? rows;
  bool seenSecond = false;

  @override
  bool nextLine(BlockContext cx, Line line, LeafBlock leaf) {
    if (!seenSecond) {
      // Second line
      seenSecond = true;
      if (line.next == 45 || line.next == 58 || line.next == 124 /* '-:|' */ ) {
        final lineText = line.text.substring(line.pos);
        if (_delimiterLine.hasMatch(lineText)) {
          final firstRow = <Element>[];
          final firstCount = _parseRow(cx, leaf.content, 0, firstRow, leaf.start);
          if (firstCount == _parseRow(cx, lineText, 0)) {
            rows = [
              cx.elt('TableHeader', leaf.start, leaf.start + leaf.content.length, firstRow),
              cx.elt('TableDelimiter', cx.lineStart + line.pos, cx.lineStart + line.text.length),
            ];
          }
        }
      }
    } else if (rows != null) {
      // Line after the second
      final content = <Element>[];
      _parseRow(cx, line.text, line.pos, content, cx.lineStart);
      rows!.add(cx.elt('TableRow', cx.lineStart + line.pos, cx.lineStart + line.text.length, content));
    }
    return false;
  }

  @override
  bool finish(BlockContext cx, LeafBlock leaf) {
    if (rows == null) return false;
    cx.addLeafElement(leaf, cx.elt('Table', leaf.start, leaf.start + leaf.content.length, rows!));
    return true;
  }
}

/// Lezer's `Table`. This extension provides [GFM-style](https://github.github.com/gfm/#tables-extension-) tables,
/// using syntax like this:
///
/// ```
/// | head 1 | head 2 |
/// | ---    | ---    |
/// | cell 1 | cell 2 |
/// ```
final MarkdownConfig table = MarkdownConfig(
  defineNodes: const [
    NodeSpec('Table', block: true),
    NodeSpec('TableHeader'),
    NodeSpec('TableRow'),
    NodeSpec('TableCell'),
    NodeSpec('TableDelimiter'),
  ],
  parseBlock: [
    BlockParser(
      name: 'Table',
      leaf: (cx, leaf) => _hasPipe(leaf.content, 0) ? _TableParser() : null,
      endLeaf: (cx, line, leaf) {
        if (leaf.parsers.any((p) => p is _TableParser) || !_hasPipe(line.text, line.basePos)) return false;
        final next = cx.peekLine();
        return _delimiterLine.hasMatch(next) &&
            _parseRow(cx, line.text, line.basePos) == _parseRow(cx, next, line.basePos);
      },
      before: 'SetextHeading',
    ),
  ],
);

/// Lezer's `TaskParser`.
class _TaskParser implements LeafBlockParser {
  @override
  bool nextLine(BlockContext cx, Line line, LeafBlock leaf) => false;

  @override
  bool finish(BlockContext cx, LeafBlock leaf) {
    cx.addLeafElement(
      leaf,
      cx.elt('Task', leaf.start, leaf.start + leaf.content.length, [
        cx.elt('TaskMarker', leaf.start, leaf.start + 3),
        ...cx.parser.parseInline(leaf.content.substring(3), leaf.start + 3),
      ]),
    );
    return true;
  }
}

final RegExp _taskStart = RegExp(r'^\[[ xX]\][ \t]');

/// Lezer's `TaskList`. Extension providing
/// [GFM-style](https://github.github.com/gfm/#task-list-items-extension-) task list items, where list items can be
/// prefixed with `[ ]` or `[x]` to add a checkbox.
final MarkdownConfig taskList = MarkdownConfig(
  defineNodes: const [NodeSpec('Task', block: true), NodeSpec('TaskMarker')],
  parseBlock: [
    BlockParser(
      name: 'TaskList',
      leaf: (cx, leaf) {
        return _taskStart.hasMatch(leaf.content) && cx.parentType().name == 'ListItem' ? _TaskParser() : null;
      },
      after: 'SetextHeading',
    ),
  ],
);

// Lezer runs these four sticky (`/gy`), from a `lastIndex`; here that is `matchAsPrefix` at the same index.
final RegExp _autolinkRE = RegExp(r'(www\.)|(https?://)|([\w.+-]{1,100}@)|(mailto:|xmpp:)');
final RegExp _urlRE = RegExp(r'[\w-]+(\.[\w-]+)+(:\d+)?(/[^\s<]*)?');
final RegExp _lastTwoDomainWords = RegExp(r'[\w-]+\.[\w-]+($|[/:])');
final RegExp _emailRE = RegExp(r'[\w.+-]+@[\w-]+(\.[\w.-]+)+');
final RegExp _xmppResourceRE = RegExp(r'/[a-zA-Z\d@.]+');
final RegExp _trailingPunctuation = RegExp(r'[?!.,:*_~]');
final RegExp _trailingEntity = RegExp(r'&(?:#\d+|#x[a-f\d]+|\w+);$');
final RegExp _noBracket = RegExp(r'([^\[\]]|\[[^\]]*\])*');

int _count(String str, int from, int to, int ch) {
  var result = 0;
  for (var i = from; i < to; i++) {
    if (str.codeUnitAt(i) == ch) result++;
  }
  return result;
}

int _autolinkURLEnd(String text, int from) {
  final m = _urlRE.matchAsPrefix(text, from);
  if (m == null || _lastTwoDomainWords.firstMatch(m[0]!)![0]!.contains('_')) return -1;
  var end = from + m[0]!.length;
  for (;;) {
    if (end < 1) break;
    final last = text[end - 1];
    RegExpMatch? entity;
    if (_trailingPunctuation.hasMatch(last) ||
        last == ')' && _count(text, from, end, 41) > _count(text, from, end, 40)) {
      end--;
    } else if (last == ';' && (entity = _trailingEntity.firstMatch(text.substring(from, end))) != null) {
      end = from + entity!.start;
    } else {
      break;
    }
  }
  return end;
}

int _autolinkEmailEnd(String text, int from) {
  final m = _emailRE.matchAsPrefix(text, from);
  if (m == null) return -1;
  final last = m[0]![m[0]!.length - 1];
  return last == '_' || last == '-' ? -1 : from + m[0]!.length - (last == '.' ? 1 : 0);
}

/// Whether a character can begin anything [_autolinkRE] matches: a word character, a dot, a plus or a hyphen. Asked
/// before the pattern is run, which is otherwise run at every word of a note.
bool _startsAutolink(int ch) {
  return ch >= 97 && ch <= 122 || ch >= 65 && ch <= 90 || ch >= 48 && ch <= 57 || ch == 95 || ch == 46 || ch == 43 || ch == 45;
}

bool _isWord(int ch) => ch >= 97 && ch <= 122 || ch >= 65 && ch <= 90 || ch >= 48 && ch <= 57 || ch == 95;

/// Lezer's `Autolink`. Extension that implements autolinking for `www.`/`http://`/`https://`/`mailto:`/`xmpp:` URLs
/// and email addresses.
final MarkdownConfig autolink = MarkdownConfig(
  parseInline: [
    InlineParser(
      name: 'Autolink',
      parse: (cx, next, absPos) {
        if (!_startsAutolink(next)) return -1;
        final pos = absPos - cx.offset;
        if (pos != 0 && _isWord(cx.text.codeUnitAt(pos - 1))) return -1;
        final m = _autolinkRE.matchAsPrefix(cx.text, pos);
        var end = -1;
        if (m == null) return -1;
        if (m[1] != null || m[2] != null) {
          // www., http://
          end = _autolinkURLEnd(cx.text, pos + m[0]!.length);
          if (end > -1 && cx.hasOpenLink) {
            final noBracket = _noBracket.matchAsPrefix(cx.text.substring(pos, end));
            end = pos + noBracket![0]!.length;
          }
        } else if (m[3] != null) {
          // email address
          end = _autolinkEmailEnd(cx.text, pos);
        } else {
          // mailto:/xmpp:
          end = _autolinkEmailEnd(cx.text, pos + m[0]!.length);
          if (end > -1 && m[0] == 'xmpp:') {
            final resource = _xmppResourceRE.matchAsPrefix(cx.text, end);
            if (resource != null) end = resource.end;
          }
        }
        if (end < 0) return -1;
        cx.addElement(cx.elt('URL', absPos, end + cx.offset));
        return end + cx.offset;
      },
    ),
  ],
);

/// Lezer's `GFM`. Extension bundle containing [table], [taskList], [strikethrough], and [autolink].
final List<MarkdownConfig> gfm = [table, taskList, strikethrough, autolink];

InlineParse _parseSubSuper(int ch, String node, String mark) {
  return (cx, next, pos) {
    if (next != ch || cx.char(pos + 1) == ch) return -1;
    final elts = [cx.elt(mark, pos, pos + 1)];
    for (var i = pos + 1; i < cx.end; i++) {
      final next = cx.char(i);
      if (next == ch) return cx.addElement(cx.elt(node, pos, i + 1, [...elts, cx.elt(mark, i, i + 1)]));
      if (next == 92 /* '\\' */ ) {
        elts.add(cx.elt('Escape', i, i + 2));
        i++;
      }
      if (space(next)) break;
    }
    return -1;
  };
}

/// Lezer's `Superscript`. Extension providing
/// [Pandoc-style](https://pandoc.org/MANUAL.html#superscripts-and-subscripts) superscript using `^` markers.
final MarkdownConfig superscript = MarkdownConfig(
  defineNodes: const [NodeSpec('Superscript'), NodeSpec('SuperscriptMark')],
  parseInline: [InlineParser(name: 'Superscript', parse: _parseSubSuper(94 /* '^' */, 'Superscript', 'SuperscriptMark'))],
);

/// Lezer's `Subscript`. Extension providing
/// [Pandoc-style](https://pandoc.org/MANUAL.html#superscripts-and-subscripts) subscript using `~` markers.
final MarkdownConfig subscript = MarkdownConfig(
  defineNodes: const [NodeSpec('Subscript'), NodeSpec('SubscriptMark')],
  parseInline: [InlineParser(name: 'Subscript', parse: _parseSubSuper(126 /* '~' */, 'Subscript', 'SubscriptMark'))],
);

final RegExp _emojiName = RegExp(r'^[a-zA-Z_0-9]+:');

/// Lezer's `Emoji`. Extension that parses two colons with only letters, underscores, and numbers between them as
/// `Emoji` nodes.
final MarkdownConfig emoji = MarkdownConfig(
  defineNodes: const [NodeSpec('Emoji')],
  parseInline: [
    InlineParser(
      name: 'Emoji',
      parse: (cx, next, pos) {
        if (next != 58 /* ':' */ ) return -1;
        final match = _emojiName.firstMatch(cx.slice(pos + 1, cx.end));
        if (match == null) return -1;
        return cx.addElement(cx.elt('Emoji', pos, pos + 1 + match[0]!.length));
      },
    ),
  ],
);
