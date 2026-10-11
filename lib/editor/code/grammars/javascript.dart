/// JavaScript, TypeScript, JSX and TSX: @lezer/javascript's grammar (javascript.g.dart) with the parts of it that
/// are code, ported from its `src/tokens.js` (MIT, Marijn Haverbeke and others).
///
/// One grammar reads all four: TypeScript and JSX are dialects of it, switched on as
/// `@codemirror/lang-javascript` switches them (`parser.configure({dialect: 'ts'})`, `'jsx'`, `'jsx ts'`).
library;

import '../lezer/lr.dart';
import 'javascript.g.dart';

typedef _T = JavascriptTerms;

/* Hand-written tokenizers for JavaScript tokens that can't be expressed by lezer's built-in tokenizer. */

const List<int> _space = <int>[9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288];

const int _braceR = 125, _semicolon = 59, _slash = 47, _star = 42, _plus = 43, _minus = 45, _lt = 60, _comma = 44, _question = 63, _dot = 46, _bracketL = 91;

/// Whether a line break has been passed since the last token that was not a comment or a space: the context is a
/// bool.
final ContextTracker _trackNewline = ContextTracker(
  start: false,
  shift: (context, term, stack, input) => term == _T.LineComment || term == _T.BlockComment || term == _T.spaces ? context : term == _T.newline,
  strict: false,
);

final ExternalTokenizer _insertSemicolon = ExternalTokenizer((input, stack) {
  final next = input.next;
  if (next == _braceR || next == -1 || stack.context == true) input.acceptToken(_T.insertSemi);
}, contextual: true, fallback: true);

final ExternalTokenizer _noSemicolon = ExternalTokenizer((input, stack) {
  final next = input.next;
  if (_space.contains(next)) return;
  if (next == _slash) {
    final after = input.peek(1);
    if (after == _slash || after == _star) return;
  }
  if (next != _braceR && next != _semicolon && next != -1 && stack.context != true) input.acceptToken(_T.noSemi);
}, contextual: true);

final ExternalTokenizer _noSemicolonType = ExternalTokenizer((input, stack) {
  if (input.next == _bracketL && stack.context != true) input.acceptToken(_T.noSemiType);
}, contextual: true);

final ExternalTokenizer _operatorToken = ExternalTokenizer((input, stack) {
  final next = input.next;
  if (next == _plus || next == _minus) {
    input.advance();
    if (next == input.next) {
      input.advance();
      final mayPostfix = stack.context != true && stack.canShift(_T.incdec);
      input.acceptToken(mayPostfix ? _T.incdec : _T.incdecPrefix);
    }
  } else if (next == _question && input.peek(1) == _dot) {
    input.advance();
    input.advance();
    if (input.next < 48 || input.next > 57) input.acceptToken(_T.questionDot); // No digit after
  }
}, contextual: true);

bool _identifierChar(int ch, bool start) => ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch == 95 || ch >= 192 || !start && ch >= 48 && ch <= 57;

const String _extends = 'extends';

final ExternalTokenizer _jsx = ExternalTokenizer((input, stack) {
  if (input.next != _lt || !stack.dialectEnabled(_T.Dialect_jsx)) return;
  input.advance();
  if (input.next == _slash) return;
  // Scan for an identifier followed by a comma or 'extends', don't treat this as a start tag if present.
  var back = 0;
  while (_space.contains(input.next)) {
    input.advance();
    back++;
  }
  if (_identifierChar(input.next, true)) {
    input.advance();
    back++;
    while (_identifierChar(input.next, false)) {
      input.advance();
      back++;
    }
    while (_space.contains(input.next)) {
      input.advance();
      back++;
    }
    if (input.next == _comma) return;
    for (var i = 0;; i++) {
      if (i == 7) {
        if (!_identifierChar(input.next, true)) return;
        break;
      }
      if (input.next != _extends.codeUnitAt(i)) break;
      input.advance();
      back++;
    }
  }
  input.acceptToken(_T.JSXStartTag, -back);
});

/// @lezer/javascript's `parser`: JavaScript.
final LRParser javascriptParser = LRParser.deserialize(
  javascriptSpec,
  tokenizers: <String, Tokenizer>{
    'noSemicolon': _noSemicolon,
    'noSemicolonType': _noSemicolonType,
    'operatorToken': _operatorToken,
    'jsx': _jsx,
    'insertSemicolon': _insertSemicolon,
  },
  context: _trackNewline,
);

/// `typescriptLanguage`, `jsxLanguage` and `tsxLanguage` of @codemirror/lang-javascript.
final LRParser typescriptParser = javascriptParser.configure(dialect: 'ts');
final LRParser jsxParser = javascriptParser.configure(dialect: 'jsx');
final LRParser tsxParser = javascriptParser.configure(dialect: 'jsx ts');
