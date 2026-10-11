part of katex_base;

// Added to 0.7.4 (README.md, 16): `\smash`, the laps, `\vcenter`, `\hbox`, `\mathchoice`, `\pmb`, and the
// commands KaTeX draws only for a page it trusts.

const _boxEntries = {
  ['\\smash']: FunctionSpec(
      numArgs: 1,
      numOptionalArgs: 1,
      allowedInText: true,
      handler: _smashHandler),
  ['\\mathllap', '\\mathrlap', '\\mathclap']:
      FunctionSpec(numArgs: 1, allowedInText: true, handler: _lapHandler),
  ['\\vcenter']: FunctionSpec(numArgs: 1, handler: _vcenterHandler),
  ['\\hbox']: FunctionSpec(numArgs: 1, allowedInText: true, handler: _hboxHandler),
  ['\\mathchoice']: FunctionSpec(numArgs: 4, handler: _mathchoiceHandler),
  ['\\pmb']: FunctionSpec(numArgs: 1, allowedInText: true, handler: _pmbHandler),
  ['\\href', '\\htmlClass', '\\htmlId', '\\htmlStyle', '\\htmlData']:
      FunctionSpec(numArgs: 1, allowedInText: true, handler: _untrustedHandler),
  ['\\url', '\\includegraphics']:
      FunctionSpec(numArgs: 0, allowedInText: true, handler: _untrustedHandler),
};

/// `\smash[t]{…}` has no height, `\smash[b]{…}` no depth, `\smash{…}` neither.
GreenNode _smashHandler(TexParser parser, FunctionContext context) {
  final which = parser.parseArgNode(mode: null, optional: true);
  final body = parser.parseArgNode(mode: null, optional: false)!;
  var height = true, depth = true;
  if (which != null) {
    // KaTeX reads the letters one at a time and stops at the first that is neither.
    height = depth = false;
    for (final letter in which.expandEquationRow()) {
      final text = letter is SymbolNode ? letter.symbol : '';
      if (text == 't') {
        height = true;
      } else if (text == 'b') {
        depth = true;
      } else {
        height = depth = false;
        break;
      }
    }
  }
  return BoxNode(
    body: body.wrapWithEquationRow(),
    zeroHeight: height,
    zeroDepth: depth,
    type: AtomType.ord,
  );
}

GreenNode _lapHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return BoxNode(
    body: body.wrapWithEquationRow(),
    zeroWidth: true,
    align: context.funcName == '\\mathllap'
        ? CrossAxisAlignment.end
        : context.funcName == '\\mathrlap'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
    type: AtomType.ord,
  );
}

GreenNode _vcenterHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return BoxNode(
      body: body.wrapWithEquationRow(), onAxis: true, type: AtomType.ord);
}

/// `\hbox{…}`: what is in it read as text is read, and set as it stands.
GreenNode _hboxHandler(TexParser parser, FunctionContext context) =>
    parser.parseArgNode(mode: Mode.text, optional: false)!.wrapWithEquationRow();

GreenNode _mathchoiceHandler(TexParser parser, FunctionContext context) =>
    StyleChoiceNode(choices: [
      for (var i = 0; i < 4; i++)
        parser.parseArgNode(mode: null, optional: false)!.wrapWithEquationRow(),
    ]);

GreenNode _pmbHandler(TexParser parser, FunctionContext context) {
  final body = parser.parseArgNode(mode: null, optional: false)!;
  return BoxNode(body: body.wrapWithEquationRow(), doubled: true);
}

/// Steps over `{…}` without reading what is in it: a link, a class's name.
void _skipGroup(TexParser parser) {
  parser.consumeSpaces();
  parser.expect('{');
  var depth = 1;
  while (depth > 0) {
    final text = parser.fetch().text;
    if (text == 'EOF') throw ParseException('Expected \'}\', got \'EOF\'');
    if (text == '{') depth++;
    if (text == '}') depth--;
    parser.consume();
  }
}

/// A link, a picture, a class: KaTeX draws these only where its caller says the formula may be trusted, and
/// otherwise writes the command's own name in its error colour (`formatUnsupportedCmd`). A note is not trusted
/// (src/app/editor/mathsDrawn.ts sets no `trust`), so that is what is drawn: `\href` in red, and nothing of
/// what it was given.
GreenNode _untrustedHandler(TexParser parser, FunctionContext context) {
  final name = context.funcName;
  if (name == '\\includegraphics') {
    parser.consumeSpaces();
    if (parser.fetch().text == '[') {
      while (parser.fetch().text != ']') {
        if (parser.fetch().text == 'EOF') {
          throw ParseException('Expected \']\', got \'EOF\'');
        }
        parser.consume();
      }
      parser.consume();
    }
  }
  _skipGroup(parser);
  if (name != '\\url' && name != '\\includegraphics') {
    parser.parseArgNode(mode: null, optional: false);
  }
  final said = TexParser(
    '\\textcolor{#cc0000}{\\text{\\textbackslash ${name.substring(1)}}}',
    parser.settings,
  ).parse();
  return said.children.length == 1 ? said.children[0] : said;
}
