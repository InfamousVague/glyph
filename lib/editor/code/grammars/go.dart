/// Go: @lezer/go's grammar (go.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others).
library;

import '../lezer/lr.dart';
import 'go.g.dart';

typedef _T = GoTerms;

const int _newline = 10, _carriageReturn = 13, _space = 32, _tab = 9, _slash = 47, _closeParen = 41, _closeBrace = 125;

final ExternalTokenizer _semicolon = ExternalTokenizer((input, stack) {
  for (var scan = 0, next = input.next;;) {
    if (stack.context == true && (next < 0 || next == _newline || next == _carriageReturn || next == _slash && input.peek(scan + 1) == _slash) || next == _closeParen || next == _closeBrace) {
      input.acceptToken(_T.insertedSemi);
    }
    if (next != _space && next != _tab) break;
    next = input.peek(++scan);
  }
}, contextual: true);

const Set<int> _trackedTokens = <int>{
  _T.IncDecOp,
  _T.identifier,
  _T.Rune,
  _T.String_,
  _T.Number,
  _T.break_,
  _T.continue_,
  _T.return_,
  _T.fallthrough,
  _T.closeParen$1,
  _T.closeBracket,
  _T.closeBrace$1,
};

/// Whether the last token was one a line can end on, so that a line break after it ends the statement.
final ContextTracker _trackTokens = ContextTracker(start: false, shift: (context, term, stack, input) => term == _T.space$1 ? context : _trackedTokens.contains(term));

/// @lezer/go's `parser`.
final LRParser goParser = LRParser.deserialize(goSpec, tokenizers: <String, Tokenizer>{'semicolon': _semicolon}, context: _trackTokens);
