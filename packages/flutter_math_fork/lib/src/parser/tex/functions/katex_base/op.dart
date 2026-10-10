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

const _opEntries = {
  [
    '\\coprod',
    '\\bigvee',
    '\\bigwedge',
    '\\biguplus',
    '\\bigcap',
    '\\bigcup',
    '\\intop',
    '\\prod',
    '\\sum',
    '\\bigotimes',
    '\\bigoplus',
    '\\bigodot',
    '\\bigsqcup',
    '\\smallint',
    '\u220F',
    '\u2210',
    '\u2211',
    '\u22c0',
    '\u22c1',
    '\u22c2',
    '\u22c3',
    '\u2a00',
    '\u2a01',
    '\u2a02',
    '\u2a04',
    '\u2a06',
  ]: FunctionSpec(
    numArgs: 0,
    handler: _bigOpHandler,
  ),
  // ['\\mathop']: FunctionSpec(
  //   numArgs: 1,
  //   handler: _mathopHandler,
  // ),
  mathFunctions: FunctionSpec(
    numArgs: 0,
    handler: _mathFunctionHandler,
  ),
  mathLimits: FunctionSpec(
    numArgs: 0,
    handler: _mathLimitsHandler,
  ),
  [
    '\\int',
    '\\iint',
    '\\iiint',
    '\\oint',
    '\\oiint',
    '\\oiiint',
    '\u222b',
    '\u222c',
    '\u222d',
    '\u222e',
    '\u222f',
    '\u2230',
  ]: FunctionSpec(
    numArgs: 0,
    handler: _integralHandler,
  ),
};

NaryOperatorNode _parseNaryOperator(
  String command,
  TexParser parser,
  FunctionContext context,
) {
  final scriptsResult = parser.parseScripts(allowLimits: true);
  final arg = parser.parseAtom(context.breakOnTokenText)?.wrapWithEquationRow();

  return NaryOperatorNode(
    operator: texSymbolCommandConfigs[Mode.math]![command]!.symbol,
    lowerLimit: scriptsResult.subscript,
    upperLimit: scriptsResult.superscript,
    naryand: arg ?? EquationRowNode.empty(),
    limits: scriptsResult.limits,
    allowLargeOp: command == '\\smallint' ? false : true,
  );
}

/// A named function with its scripts and what it is applied to.
///
/// Changed from 0.7.4 (README.md, 13): whether its scripts are limits now follows the style it is built in, as in
/// KaTeX; it was fixed here as the formula was read ("in accordance with UnicodeMath, and … different from
/// KaTeX", the package said).
FunctionNode _parseMathFunction(
    GreenNode funcNameBase, TexParser parser, FunctionContext context,
    {bool defaultLimits = false}) {
  final scriptsResult = parser.parseScripts(allowLimits: true);
  EquationRowNode arg;
  arg = parser
          .parseAtom(context.breakOnTokenText)
          // .parseArgNode(mode: Mode.math, optional: false)
          ?.wrapWithEquationRow() ??
      EquationRowNode.empty();
  final base = funcNameBase.wrapWithEquationRow();
  if (scriptsResult.subscript == null && scriptsResult.superscript == null) {
    return FunctionNode(
      functionName: base,
      argument: arg,
    );
  }
  return FunctionNode(
    functionName: _nameWithScripts(base, scriptsResult,
            limitsInDisplay: defaultLimits)
        .wrapWithEquationRow(),
    argument: arg,
  );
}

/// An operator's name with what was written under and over it.
///
/// Changed from 0.7.4 (README.md, 13): a name that takes limits (`\lim`, `\max`, `\operatorname*{…}`) takes them
/// in display style only and scripts beside it otherwise, as KaTeX builds it (functions/op.js:
/// `limits && style.size === DISPLAY`); `\limits` asks for them in any style and `\nolimits` in none. It was
/// decided here, as the formula was read, always for limits.
GreenNode _nameWithScripts(
    EquationRowNode base, ScriptsParsingResults scripts,
    {required bool limitsInDisplay}) {
  GreenNode limits() {
    var name = base;
    if (scripts.subscript != null) {
      name = UnderNode(base: name, below: scripts.subscript!)
          .wrapWithEquationRow();
    }
    if (scripts.superscript != null) {
      name = OverNode(base: name, above: scripts.superscript!)
          .wrapWithEquationRow();
    }
    return name;
  }

  GreenNode beside() => MultiscriptsNode(
        base: base,
        sub: scripts.subscript,
        sup: scripts.superscript,
      );

  if (scripts.limits == true) return limits();
  if (scripts.limits == false || !limitsInDisplay) return beside();
  return StyleLimitsNode(
    limits: limits().wrapWithEquationRow(),
    scripts: beside().wrapWithEquationRow(),
  );
}

const singleCharBigOps = {
  '\u220F': '\\prod',
  '\u2210': '\\coprod',
  '\u2211': '\\sum',
  '\u22c0': '\\bigwedge',
  '\u22c1': '\\bigvee',
  '\u22c2': '\\bigcap',
  '\u22c3': '\\bigcup',
  '\u2a00': '\\bigodot',
  '\u2a01': '\\bigoplus',
  '\u2a02': '\\bigotimes',
  '\u2a04': '\\biguplus',
  '\u2a06': '\\bigsqcup',
};

GreenNode _bigOpHandler(TexParser parser, FunctionContext context) {
  final fName = context.funcName.length == 1
      ? singleCharBigOps[context.funcName]!
      : context.funcName;
  return _parseNaryOperator(fName, parser, context);
}

// GreenNode _mathopHandler(TexParser parser, FunctionContext context) {
//   final fName = parser.parseArgNode(mode: Mode.math, optional: false);
//   return _parseMathFunction(fName, parser, context);
// }

const mathFunctions = [
  '\\arcsin',
  '\\arccos',
  '\\arctan',
  '\\arctg',
  '\\arcctg',
  '\\arg',
  '\\ch',
  '\\cos',
  '\\cosec',
  '\\cosh',
  '\\cot',
  '\\cotg',
  '\\coth',
  '\\csc',
  '\\ctg',
  '\\cth',
  '\\deg',
  '\\dim',
  '\\exp',
  '\\hom',
  '\\ker',
  '\\lg',
  '\\ln',
  '\\log',
  '\\sec',
  '\\sin',
  '\\sinh',
  '\\sh',
  '\\tan',
  '\\tanh',
  '\\tg',
  '\\th',
];

GreenNode _mathFunctionHandler(TexParser parser, FunctionContext context) =>
    _parseMathFunction(
      stringToNode(context.funcName.substring(1), Mode.text),
      parser,
      context,
      defaultLimits: false,
    );

const mathLimits = [
  '\\det',
  '\\gcd',
  '\\inf',
  '\\lim',
  '\\max',
  '\\min',
  '\\Pr',
  '\\sup',
];

GreenNode _mathLimitsHandler(TexParser parser, FunctionContext context) =>
    _parseMathFunction(
      stringToNode(context.funcName.substring(1), Mode.text),
      parser,
      context,
      defaultLimits: true,
    );

const singleCharIntegrals = {
  '\u222b': '\\int',
  '\u222c': '\\iint',
  '\u222d': '\\iiint',
  '\u222e': '\\oint',
  '\u222f': '\\oiint',
  '\u2230': '\\oiiint',
};
GreenNode _integralHandler(TexParser parser, FunctionContext context) {
  final fName = context.funcName.length == 1
      ? singleCharIntegrals[context.funcName]!
      : context.funcName;
  return _parseNaryOperator(fName, parser, context);
}
