// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
// Copyright (c) 2020 znjameswu <znjameswu@gmail.com>
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

import 'package:collection/collection.dart';

import '../../../ast/nodes/equation_array.dart';
import '../../../ast/nodes/left_right.dart';
import '../../../ast/nodes/matrix.dart';
import '../../../ast/nodes/space.dart';
import '../../../ast/nodes/style.dart';
import '../../../ast/nodes/symbol.dart';
import '../../../ast/options.dart';
import '../../../ast/size.dart';
import '../../../ast/style.dart';
import '../../../ast/syntax_tree.dart';
import '../../../ast/types.dart';
import '../define_environment.dart';
import '../functions/katex_base.dart';
import '../macros.dart';
import '../parse_error.dart';
import '../parser.dart';
import 'array.dart';

const eqnArrayEntries = {
  [
    'cases',
    'dcases',
    'rcases',
    'drcases',
  ]: EnvSpec(
    numArgs: 0,
    handler: _casesHandler,
  ),
  // Added to 0.7.4 (README.md, 6): `align`, `gather`, `equation`, `split` and their starred forms, and
  // `gathered`, read as KaTeX reads them less the equation's number, which KaTeX sets at the right of an
  // unstarred one and this does not draw.
  ['aligned', 'align', 'align*', 'split']: EnvSpec(
    numArgs: 0,
    handler: _alignedHandler,
  ),
  ['gathered', 'gather', 'gather*']: EnvSpec(
    numArgs: 0,
    handler: _gatheredHandler,
  ),
  ['equation', 'equation*']: EnvSpec(
    numArgs: 0,
    handler: _equationHandler,
  ),
  ['alignedat', 'alignat', 'alignat*']: EnvSpec(numArgs: 1, handler: _alignedAtHandler),
};

GreenNode _casesHandler(TexParser parser, EnvContext context) {
  final body = parseEqnArray(
    parser,
    // Changed from 0.7.4 (README.md, 5): KaTeX sets `cases` with rows 1.2 apart (`arraystretch: 1.2`).
    arrayStretch: 1.2,
    concatRow: (cells) {
      final children = [
        SpaceNode.alignerOrSpacer(),
        if (cells.length >= 1) ...cells[0].children,
        if (cells.length > 1) SpaceNode.alignerOrSpacer(),
        if (cells.length > 1)
          SpaceNode(height: Measurement.zero, width: 1.0.em, mode: Mode.math),
      ];
      for (var i = 1; i < cells.length; i++) {
        children.add(SpaceNode.alignerOrSpacer());
        children.addAll(cells[i].children);
        children.add(SpaceNode.alignerOrSpacer());
      }
      if (context.envName == 'dcases' || context.envName == 'drcases') {
        return EquationRowNode(children: [
          StyleNode(
            optionsDiff: OptionsDiff(style: MathStyle.display),
            children: children,
          )
        ]);
      } else {
        return EquationRowNode(children: children);
      }
    },
  );
  if (context.envName == 'rcases' || context.envName == 'drcases') {
    return LeftRightNode(
      leftDelim: null,
      rightDelim: '}',
      body: [body.wrapWithEquationRow()],
    );
  } else {
    return LeftRightNode(
      leftDelim: '{',
      rightDelim: null,
      body: [body.wrapWithEquationRow()],
    );
  }
}

/// `validateAmsEnvironmentContext`: the environments that are a displayed formula by themselves are refused in
/// a line of text, with KaTeX's words.
///
/// Added to 0.7.4 (README.md, 19).
void _displayOnly(TexParser parser, EnvContext context) {
  if (!parser.settings.displayMode) {
    throw ParseException(
        '{${context.envName}} can be used only in display mode.');
  }
}

/// `getAutoTag`: null for an environment that is part of a formula (`aligned`, `split`), false for a starred
/// one, whose rows have only the tags they are given, true for one whose rows are numbered.
bool? _autoTag(String name) =>
    name.contains('ed') || name == 'split' ? null : !name.contains('*');

GreenNode _alignedHandler(TexParser parser, EnvContext context) {
  if (!context.envName.contains('ed')) _displayOnly(parser, context);
  return _alignedRows(parser, context);
}

GreenNode _alignedRows(TexParser parser, EnvContext context) =>
    parseEqnArray(
      parser,
      addJot: true,
      autoTag: _autoTag(context.envName),
      concatRow: (cells) {
        final expanded = cells
            .expand((cell) => [...cell.children, SpaceNode.alignerOrSpacer()])
            .toList(growable: true);
        return EquationRowNode(children: expanded);
      },
    );

/// Rows each centred, a jot between them: `gathered`.
GreenNode _gatheredHandler(TexParser parser, EnvContext context) {
  if (context.envName != 'gathered') _displayOnly(parser, context);
  return _gatheredRows(parser, context);
}

GreenNode _gatheredRows(TexParser parser, EnvContext context) =>
    parseEqnArray(
      parser,
      addJot: true,
      autoTag: _autoTag(context.envName),
      concatRow: (cells) => EquationRowNode(
          children: cells.expand((cell) => cell.children).toList()),
    );

/// One row, as it is: `equation`.
GreenNode _equationHandler(TexParser parser, EnvContext context) {
  _displayOnly(parser, context);
  return _equationRows(parser, context);
}

GreenNode _equationRows(TexParser parser, EnvContext context) =>
    parseEqnArray(
      parser,
      autoTag: _autoTag(context.envName),
      concatRow: (cells) => EquationRowNode(
          children: cells.expand((cell) => cell.children).toList()),
    );

GreenNode _alignedAtHandler(TexParser parser, EnvContext context) {
  if (!context.envName.contains('ed')) _displayOnly(parser, context);
  final arg = parser.parseArgNode(mode: null, optional: false);
  final numNode = assertNodeType<EquationRowNode>(arg);
  final string = numNode.children
      .map((e) => assertNodeType<SymbolNode>(e).symbol)
      .join('');
  final cols = int.tryParse(string);
  if (cols == null) {
    throw ParseException('Invalid argument for environment: alignedat');
  }
  return parseEqnArray(
    parser,
    addJot: true,
    autoTag: _autoTag(context.envName),
    concatRow: (cells) {
      if (cells.length > 2 * cols) {
        throw ParseException('Too many math in a row: '
            'expected ${2 * cols}, but got ${cells.length}');
      }
      final expanded = cells
          .expand((cell) => [...cell.children, SpaceNode.alignerOrSpacer()])
          .toList(growable: true);
      return EquationRowNode(children: expanded);
    },
  );
}

EquationArrayNode parseEqnArray(
  TexParser parser, {
  bool addJot = false,
  double? arrayStretch,
  bool? autoTag,
  required EquationRowNode Function(List<EquationRowNode> cells) concatRow,
}) {
  // Added to 0.7.4 (README.md, 19): what stands at the right of each row, as KaTeX's parseArray gathers it
  // (`beginRow`, `endRow`): the row's own `\tag`, or, in an environment that numbers its rows, a number unless
  // the row said `\nonumber`.
  final tags = <EquationRowNode?>[];
  void beginRow() {
    if (autoTag == true) {
      parser.macroExpander.macros
          .set('\\@eqnsw', MacroDefinition.fromString('1'), global: true);
    }
  }

  void endRow() {
    if (autoTag == null) return;
    final tagged = parser.macroExpander.expandMacro('\\df@tag');
    if (tagged != null) {
      parser.macroExpander.macros.unset('\\df@tag');
      final words = StringBuffer();
      for (final token in tagged) {
        // A control word and a letter after it are two things: kept apart as they were written.
        if (words.isNotEmpty &&
            RegExp('^[A-Za-z]').hasMatch(token.text) &&
            RegExp(r'\\[A-Za-z]+$').hasMatch(words.toString())) {
          words.write(' ');
        }
        words.write(token.text);
      }
      tags.add(TexParser(words.toString(), parser.settings).parse());
    } else {
      tags.add(autoTag &&
              parser.macroExpander.expandMacroAsText('\\@eqnsw') == '1'
          ? EquationArrayNode.numbered
          : null);
    }
  }

  final givenStretch = arrayStretch;
  // Parse body of array with \\ temporarily mapped to \cr
  parser.macroExpander.beginGroup();
  parser.macroExpander.macros.set('\\\\', MacroDefinition.fromString('\\cr'));

  // Get current arraystretch if it's not set by the environment
  arrayStretch = 1.0;
  // if (arrayStretch == null) {
  final stretch = givenStretch != null
      ? '$givenStretch'
      : parser.macroExpander.expandMacroAsText('\\arraystretch');
  if (stretch == null) {
    // Default \arraystretch from lttab.dtx
    arrayStretch = 1.0;
  } else {
    arrayStretch = double.tryParse(stretch);
    if (arrayStretch == null || arrayStretch < 0) {
      throw ParseException('Invalid \\arraystretch: $stretch');
    }
  }
  // }

  // Start group for first cell
  parser.macroExpander.beginGroup();

  var row = <EquationRowNode>[];
  final body = [row];
  beginRow();
  final rowGaps = <Measurement>[];
  final hLinesBeforeRow = <MatrixSeparatorStyle>[];

  // Test for \hline at the top of the array.
  hLinesBeforeRow
      .add(getHLines(parser).lastOrNull ?? MatrixSeparatorStyle.none);

  while (true) {
    // Parse each cell in its own group (namespace)
    final cellBody =
        parser.parseExpression(breakOnInfix: false, breakOnTokenText: '\\cr');
    parser.macroExpander.endGroup();
    parser.macroExpander.beginGroup();

    final cell = cellBody.wrapWithEquationRow();
    row.add(cell);

    final next = parser.fetch().text;
    if (next == '&') {
      parser.consume();
    } else if (next == '\\end') {
      // Arrays terminate newlines with `\crcr` which consumes a `\cr` if
      // the last line is empty.
      // NOTE: Currently, `cell` is the last item added into `row`.
      endRow();
      // Changed from 0.7.4 (README.md, 19): the test was for a kind of node a cell never is, so the empty row
      // a last `\\\\` leaves was kept, a row taller than KaTeX's and here a number more.
      if (row.length == 1 && cell.children.isEmpty && body.length > 1) {
        body.removeLast();
        if (tags.length > body.length) tags.removeLast();
      }
      if (hLinesBeforeRow.length < body.length + 1) {
        hLinesBeforeRow.add(MatrixSeparatorStyle.none);
      }
      break;
    } else if (next == '\\cr') {
      final cr = assertNodeType<CrNode>(parser.parseFunction(null, null, null));
      rowGaps.add(cr.size ?? Measurement.zero);

      // check for \hline(s) following the row separator
      hLinesBeforeRow
          .add(getHLines(parser).lastOrNull ?? MatrixSeparatorStyle.none);

      endRow();
      row = [];
      body.add(row);
      beginRow();
    } else {
      throw ParseException(
          'Expected & or \\\\ or \\cr or \\end', parser.nextToken);
    }
  }

  // End cell group
  parser.macroExpander.endGroup();
  // End array group defining \\
  parser.macroExpander.endGroup();

  final rows = body.map<EquationRowNode>(concatRow).toList();

  return EquationArrayNode(
    arrayStretch: arrayStretch,
    hlines: hLinesBeforeRow,
    rowSpacings: rowGaps,
    addJot: addJot,
    body: rows,
    tags: tags.any((tag) => tag != null) ? tags : null,
  );
}
