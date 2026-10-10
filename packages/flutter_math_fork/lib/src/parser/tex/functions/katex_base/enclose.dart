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

part of katex_base;

const _encloseEntries = {
  ['\\colorbox']: FunctionSpec(
      numArgs: 2,
      allowedInText: true,
      greediness: 3,
      handler: _colorboxHandler),
  ['\\fcolorbox']: FunctionSpec(
      numArgs: 3,
      allowedInText: true,
      greediness: 3,
      handler: _fcolorboxHandler),
  ['\\fbox']:
      FunctionSpec(numArgs: 1, allowedInText: true, handler: _fboxHandler),
  ['\\cancel', '\\bcancel', '\\xcancel', '\\sout']:
      FunctionSpec(numArgs: 1, handler: _cancelHandler),
};

GreenNode _colorboxHandler(TexParser parser, FunctionContext context) {
  final color = parser.parseArgColor(optional: false);
  final body = parser.parseArgNode(mode: Mode.text, optional: false)!;
  return EnclosureNode(
    backgroundcolor: color,
    base: body.wrapWithEquationRow(),
    hasBorder: false,
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _fcolorboxHandler(TexParser parser, FunctionContext context) {
  final borderColor = parser.parseArgColor(optional: false)!;
  final color = parser.parseArgColor(optional: false)!;
  final body = parser.parseArgNode(mode: Mode.text, optional: false)!;
  return EnclosureNode(
    hasBorder: true,
    bordercolor: borderColor,
    backgroundcolor: color,
    base: body.wrapWithEquationRow(),
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _fboxHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgHbox(optional: false);
  return EnclosureNode(
    hasBorder: true,
    base: body.wrapWithEquationRow(),
    // FontMetrics.fboxsep
    verticalPadding: 0.3.cssEm,
    // katex.less/.boxpad
    horizontalPadding: 0.3.cssEm,
  );
}

GreenNode _cancelHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  // Changed from 0.7.4 (README.md, 11), to KaTeX's functions/enclose.js: a stroke through one character
  // reaches a fifth of an em over and under it and no wider; through more it is as tall as they are and a
  // fifth of an em wider each side; either way it adds nothing to the height (EnclosureNode). And the names:
  // `\bcancel`'s and `\xcancel`'s were not the ones the node looks for, so neither was drawn at all.
  final row = body.wrapWithEquationRow();
  final single = row.children.length == 1 && row.children.first is SymbolNode;
  return EnclosureNode(
    notation: const {
      '\\cancel': ['updiagonalstrike'],
      '\\bcancel': ['downdiagnoalstrike'],
      '\\xcancel': ['updiagonalstrike', 'downdiagnoalstrike'],
      '\\sout': ['horizontalstrike'],
    }[context.funcName]!,
    hasBorder: false,
    base: row,
    verticalPadding: single ? 0.2.cssEm : Measurement.zero,
    // katex.less/.cancel-pad
    horizontalPadding: single ? Measurement.zero : 0.2.cssEm,
  );
}
