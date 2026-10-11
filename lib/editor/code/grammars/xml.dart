/// XML: @lezer/xml's grammar (xml.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others).
library;

import '../lezer/lr.dart';
import 'xml.g.dart';

typedef _T = XmlTerms;

/* Hand-written tokenizer for XML tag matching. */

bool _nameChar(int ch) => ch == 45 || ch == 46 || ch == 58 || ch >= 65 && ch <= 90 || ch == 95 || ch >= 97 && ch <= 122 || ch >= 161;

bool _isSpace(int ch) => ch == 9 || ch == 10 || ch == 13 || ch == 32;

/// The tag name `offset` characters on, past any space; null where there is none. (Lezer remembers the last
/// answer; reading it again costs a name's length.)
String? _tagNameAfter(InputStream input, int offset) {
  while (_isSpace(input.peek(offset))) {
    offset++;
  }
  final name = StringBuffer();
  for (;;) {
    final next = input.peek(offset);
    if (!_nameChar(next)) break;
    name.writeCharCode(next);
    offset++;
  }
  return name.isEmpty ? null : name.toString();
}

/// The elements open at a place in the document: the innermost, and the ones around it.
class _ElementContext {
  const _ElementContext(this.name, this.parent);

  final String name;
  final _ElementContext? parent;
}

final ContextTracker _elementContext = ContextTracker(
  start: null,
  shift: (context, term, stack, input) => term == _T.StartTag ? _ElementContext(_tagNameAfter(input, 1) ?? '', context as _ElementContext?) : context,
  reduce: (context, term, stack, input) => term == _T.Element && context != null ? (context as _ElementContext).parent : context,
  strict: false,
);

final ExternalTokenizer _startTag = ExternalTokenizer((input, stack) {
  if (input.next != 60 /* '<' */ ) return;
  input.advance();
  if (input.next == 47 /* '/' */ ) {
    input.advance();
    final name = _tagNameAfter(input, 0);
    if (name == null) return input.acceptToken(_T.incompleteStartCloseTag);
    final context = stack.context as _ElementContext?;
    if (context != null && name == context.name) return input.acceptToken(_T.StartCloseTag);
    for (var cx = context; cx != null; cx = cx.parent) {
      if (cx.name == name) return input.acceptToken(_T.MissingCloseTag, -2);
    }
    input.acceptToken(_T.mismatchedStartCloseTag);
  } else if (input.next != 33 /* '!' */ && input.next != 63 /* '?' */ ) {
    return input.acceptToken(_T.StartTag);
  }
}, contextual: true);

ExternalTokenizer _scanTo(int type, String end) => ExternalTokenizer((input, stack) {
  var len = 0;
  final first = end.codeUnitAt(0);
  scan:
  for (;; input.advance(), len++) {
    if (input.next < 0) break;
    if (input.next == first) {
      for (var i = 1; i < end.length; i++) {
        if (input.peek(i) != end.codeUnitAt(i)) continue scan;
      }
      break;
    }
  }
  if (len != 0) input.acceptToken(type);
});

/// @lezer/xml's `parser`.
final LRParser xmlParser = LRParser.deserialize(
  xmlSpec,
  tokenizers: <String, Tokenizer>{
    'startTag': _startTag,
    'commentContent': _scanTo(_T.commentContent$1, '-->'),
    'piContent': _scanTo(_T.piContent$1, '?>'),
    'cdataContent': _scanTo(_T.cdataContent$1, ']]>'),
  },
  context: _elementContext,
);
