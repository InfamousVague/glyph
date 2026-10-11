// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
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
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Added to 0.7.4 (README.md, 20): the `CD` environment of amscd, a diagram of arrows, read as KaTeX's
// environments/cd.js reads it and laid out as its array is (environments/array.js, `colSeparationType: "CD"`).
//
//   \begin{CD} A @>a>> B \\ @VbVV @AAcA \\ C @= D \end{CD}
//
// A row is cells and arrows in turn. An arrow starts at `@`: `@>>>` and `@<<<` across, with what is written
// before the second mark over the arrow and what is after it under; `@VVV` and `@AAA` down and up, with what is
// before the second mark to the left and what is after it to the right; `@=` a long equals; `@|` two bars; `@.`
// nothing. Every other row is the arrows between the rows of cells.

import '../../../ast/nodes/box.dart';
import '../../../ast/nodes/matrix.dart';
import '../../../ast/nodes/space.dart';
import '../../../ast/nodes/stretchy_op.dart';
import '../../../ast/nodes/style.dart';
import '../../../ast/nodes/symbol.dart';
import '../../../ast/options.dart';
import '../../../ast/size.dart';
import '../../../ast/style.dart';
import '../../../ast/syntax_tree.dart';
import '../../../ast/types.dart';
import '../define_environment.dart';
import '../macros.dart';
import '../parse_error.dart';
import '../parser.dart';

const cdEntries = {
  ['CD']: EnvSpec(numArgs: 0, handler: _cdHandler),
};

GreenNode _cdHandler(TexParser parser, EnvContext context) {
  // `validateAmsEnvironmentContext`.
  if (!parser.settings.displayMode) {
    throw ParseException(
        '{${context.envName}} can be used only in display mode.');
  }
  return parseCD(parser);
}

bool _isStartOfArrow(GreenNode node) =>
    node is SymbolNode && node.symbol == '@';

bool _isLabelEnd(GreenNode node, String endChar) =>
    node is SymbolNode && node.symbol == endChar;

/// `\Big` of a delimiter that is always built of pieces (an arrow up or down, two bars), with what stands at
/// its sides.
GreenNode _big(String delim, [List<List<GreenNode>>? labels]) =>
    StackedDelimNode(
      delim: delim,
      height: 1.8.cssEm,
      left: labels?[0].wrapWithEquationRow(),
      right: labels?[1].wrapWithEquationRow(),
    );

/// An arrow and its labels (`cdArrow`).
GreenNode _cdArrow(String arrowChar, List<List<GreenNode>> labels) {
  switch (arrowChar) {
    case '>':
    case '<':
      return StretchyOpNode(
        above: labels[0].wrapWithEquationRow(),
        below: labels[1].wrapWithEquationRow(),
        symbol: arrowChar == '>' ? 'cdrightarrow' : 'cdleftarrow',
      );
    case 'A':
    case 'V':
      return _big(arrowChar == 'A' ? '↑' : '↓', labels);
    case '=':
      return StretchyOpNode(
        above: EquationRowNode.empty(),
        below: null,
        symbol: 'cdlongequal',
      );
    case '|':
      return _big('∥');
    default:
      // No arrow: a space as wide as a word's.
      return SpaceNode(
          height: Measurement.zero, width: 0.25.cssEm, mode: Mode.math);
  }
}

/// A cell: always in display style.
EquationRowNode _cell(List<GreenNode> body) => StyleNode(
      children: body,
      optionsDiff: const OptionsDiff(style: MathStyle.display),
    ).wrapWithEquationRow();

GreenNode parseCD(TexParser parser) {
  // Get the rows' nodes with \\ temporarily mapped to \cr.
  final parsedRows = <List<GreenNode>>[];
  parser.macroExpander.beginGroup();
  parser.macroExpander.macros.set('\\\\', MacroDefinition.fromString('\\cr'));
  parser.macroExpander.beginGroup();
  while (true) {
    parsedRows.add(
        parser.parseExpression(breakOnInfix: false, breakOnTokenText: '\\cr'));
    parser.macroExpander.endGroup();
    parser.macroExpander.beginGroup();
    final next = parser.fetch().text;
    if (next == '&' || next == '\\cr') {
      parser.consume();
    } else if (next == '\\end') {
      if (parsedRows.last.isEmpty) {
        parsedRows.removeLast(); // final row ended in \\
      }
      break;
    } else {
      throw ParseException('Expected \\\\ or \\cr or \\end', parser.nextToken);
    }
  }

  var row = <EquationRowNode?>[];
  final body = <List<EquationRowNode?>>[row];

  // Loop through the nodes. Collect them into cells and arrows.
  for (var i = 0; i < parsedRows.length; i++) {
    final rowNodes = parsedRows[i];
    var cell = <GreenNode>[];
    for (var j = 0; j < rowNodes.length; j++) {
      if (!_isStartOfArrow(rowNodes[j])) {
        // What is not an arrow goes into a cell.
        cell.add(rowNodes[j]);
        continue;
      }
      // An "@", the start of an arrow: the cell before it is done.
      row.add(_cell(cell));
      // The character after "@" says which arrow.
      j += 1;
      final mark = j < rowNodes.length ? rowNodes[j] : null;
      if (mark is! SymbolNode) {
        throw ParseException('Expected one of "<>AV=|." after @');
      }
      final arrowChar = mark.symbol;
      final labels = <List<GreenNode>>[<GreenNode>[], <GreenNode>[]];
      if (arrowChar == '=' || arrowChar == '|' || arrowChar == '.') {
        // Three "arrows", `@=`, `@|` and `@.`, take no labels.
      } else if (arrowChar == '<' ||
          arrowChar == '>' ||
          arrowChar == 'A' ||
          arrowChar == 'V') {
        // Four arrows take two labels each, which may be empty: `@>{label}>{label}>`.
        for (var labelNum = 0; labelNum < 2; labelNum++) {
          var inLabel = true;
          for (var k = j + 1; k < rowNodes.length; k++) {
            if (_isLabelEnd(rowNodes[k], arrowChar)) {
              inLabel = false;
              j = k;
              break;
            }
            if (_isStartOfArrow(rowNodes[k])) {
              throw ParseException(
                  'Missing a $arrowChar character to complete a CD arrow.');
            }
            labels[labelNum].add(rowNodes[k]);
          }
          if (inLabel) {
            throw ParseException(
                'Missing a $arrowChar character to complete a CD arrow.');
          }
        }
      } else {
        throw ParseException('Expected one of "<>AV=|." after @');
      }
      row.add(_cell(<GreenNode>[_cdArrow(arrowChar, labels)]));
      // Cells are implicit: everything that is not an arrow is in one, and one begins here.
      cell = <GreenNode>[];
    }
    if (i % 2 == 0) {
      // A row of cells: cell, arrow, cell, arrow, … cell. The last is not in the row yet.
      row.add(_cell(cell));
    } else if (row.isNotEmpty) {
      // A row of arrows: arrow, cell, arrow, … arrow. The empty cell put before the first is taken off.
      row.removeAt(0);
    }
    row = <EquationRowNode?>[];
    body.add(row);
  }

  // End row group
  parser.macroExpander.endGroup();
  // End array group defining \\
  parser.macroExpander.endGroup();

  // As KaTeX leaves it, `body` ends with a row nothing is in. Its array still counts that row where it sets the
  // whole about the axis, and no column reaches down into it: the diagram stands that much higher than a matrix
  // of its rows would, and is that much less deep (`lessDepth`).
  return BoxNode(
    body: MatrixNode(
      body: body,
      // A row is three x-heights from the next where an array's is twelve points (`baselineskip`).
      arrayStretch: 3 * 0.431 / 1.2,
      // `addJot`: three points more under every row but the last.
      rowSpacings: List.filled(body.length, 3.0.pt),
      // "CD package sets \enskip between columns": a quarter of an em each side.
      colSep: 0.25.cssEm,
    ).wrapWithEquationRow(),
    lessDepth: 3.0.ex,
  );
}
