/// HTML: @lezer/html's grammar (html.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others): which tags close themselves, which close the one before, and the text of
/// a `<script>`, a `<style>` and a `<textarea>`. What is inside a script, a style and a `style=""` is another
/// language's: `../nesting.dart`.
library;

import '../lezer/lr.dart';
import 'html.g.dart';

typedef _T = HtmlTerms;

/* Hand-written tokenizers for HTML. */

const Set<String> _selfClosers = <String>{'area', 'base', 'br', 'col', 'command', 'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr', 'menuitem'};

const Set<String> _implicitlyClosed = <String>{'dd', 'li', 'optgroup', 'option', 'p', 'rp', 'rt', 'tbody', 'td', 'tfoot', 'th', 'tr'};

const Map<String, Set<String>> _closeOnOpen = <String, Set<String>>{
  'dd': <String>{'dd', 'dt'},
  'dt': <String>{'dd', 'dt'},
  'li': <String>{'li'},
  'option': <String>{'option', 'optgroup'},
  'optgroup': <String>{'optgroup'},
  'p': <String>{
    'address', 'article', 'aside', 'blockquote', 'dir', 'div', 'dl', 'fieldset', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'menu', 'nav', 'ol', 'p', 'pre', 'section', 'table', 'ul', //
  },
  'rp': <String>{'rp', 'rt'},
  'rt': <String>{'rp', 'rt'},
  'tbody': <String>{'tbody', 'tfoot'},
  'td': <String>{'td', 'th'},
  'tfoot': <String>{'tbody'},
  'th': <String>{'td', 'th'},
  'thead': <String>{'tbody', 'tfoot'},
  'tr': <String>{'tr'},
};

bool _nameChar(int ch) => ch == 45 || ch == 46 || ch == 58 || ch >= 65 && ch <= 90 || ch == 95 || ch >= 97 && ch <= 122 || ch >= 161;

const int _lessThan = 60, _greaterThan = 62, _slash = 47, _question = 63, _bang = 33, _dash = 45;

/// The tag name `offset` characters on, in lower case. Empty where there is none; null where what follows is `?`
/// or `!` (JavaScript's `undefined` there, and `null` for none).
String? _tagNameAfter(InputStream input, int offset) {
  var next = input.peek(offset);
  final name = StringBuffer();
  for (;;) {
    if (!_nameChar(next)) break;
    name.writeCharCode(next);
    next = input.peek(++offset);
  }
  if (name.isNotEmpty) return name.toString().toLowerCase();
  return next == _question || next == _bang ? null : '';
}

/// The elements open at a place in the document: the innermost, and the ones around it.
class _ElementContext {
  const _ElementContext(this.name, this.parent);

  final String name;
  final _ElementContext? parent;
}

const List<int> _startTagTerms = <int>[_T.StartTag, _T.StartSelfClosingTag, _T.StartScriptTag, _T.StartStyleTag, _T.StartTextareaTag];

final ContextTracker _elementContext = ContextTracker(
  start: null,
  shift: (context, term, stack, input) => _startTagTerms.contains(term) ? _ElementContext(_tagNameAfter(input, 1) ?? '', context as _ElementContext?) : context,
  reduce: (context, term, stack, input) => term == _T.Element && context != null ? (context as _ElementContext).parent : context,
  strict: false,
);

final ExternalTokenizer _tagStart = ExternalTokenizer((input, stack) {
  final context = stack.context as _ElementContext?;
  if (input.next != _lessThan) {
    // End of file, close any open tags
    if (input.next < 0 && context != null) input.acceptToken(_T.missingCloseTag);
    return;
  }
  input.advance();
  final close = input.next == _slash;
  if (close) input.advance();
  final name = _tagNameAfter(input, 0);
  if (name == null) return;
  if (name.isEmpty) return input.acceptToken(close ? _T.IncompleteCloseTag : _T.IncompleteTag);

  final parent = context?.name;
  if (close) {
    if (name == parent) return input.acceptToken(_T.StartCloseTag);
    if (parent != null && parent.isNotEmpty && _implicitlyClosed.contains(parent)) return input.acceptToken(_T.missingCloseTag, -2);
    if (stack.dialectEnabled(_T.Dialect_noMatch)) return input.acceptToken(_T.NoMatchStartCloseTag);
    for (var cx = context; cx != null; cx = cx.parent) {
      if (cx.name == name) return;
    }
    input.acceptToken(_T.MismatchedStartCloseTag);
  } else {
    if (name == 'script') return input.acceptToken(_T.StartScriptTag);
    if (name == 'style') return input.acceptToken(_T.StartStyleTag);
    if (name == 'textarea') return input.acceptToken(_T.StartTextareaTag);
    if (_selfClosers.contains(name)) return input.acceptToken(_T.StartSelfClosingTag);
    if (parent != null && (_closeOnOpen[parent]?.contains(name) ?? false)) {
      input.acceptToken(_T.missingCloseTag, -1);
    } else {
      input.acceptToken(_T.StartTag);
    }
  }
}, contextual: true);

final ExternalTokenizer _commentContent = ExternalTokenizer((input, stack) {
  for (var dashes = 0, i = 0;; i++) {
    if (input.next < 0) {
      if (i != 0) input.acceptToken(_T.commentContent$1);
      break;
    }
    if (input.next == _dash) {
      dashes++;
    } else if (input.next == _greaterThan && dashes >= 2) {
      if (i >= 3) input.acceptToken(_T.commentContent$1, -2);
      break;
    } else {
      dashes = 0;
    }
    input.advance();
  }
});

bool _inForeignElement(_ElementContext? context) {
  for (; context != null; context = context.parent) {
    if (context.name == 'svg' || context.name == 'math') return true;
  }
  return false;
}

final ExternalTokenizer _endTag = ExternalTokenizer((input, stack) {
  if (input.next == _slash && input.peek(1) == _greaterThan) {
    final selfClosing = stack.dialectEnabled(_T.Dialect_selfClosing) || _inForeignElement(stack.context as _ElementContext?);
    input.acceptToken(selfClosing ? _T.SelfClosingEndTag : _T.EndTag, 2);
  } else if (input.next == _greaterThan) {
    input.acceptToken(_T.EndTag, 1);
  }
});

ExternalTokenizer _contentTokenizer(String tag, int textToken, int endToken) {
  final lastState = 2 + tag.length;
  return ExternalTokenizer((input, stack) {
    // state means:
    // - 0 nothing matched
    // - 1 '<' matched
    // - 2 '</'
    // - 3-(1+tag.length) part of the tag matched
    // - lastState whole tag + possibly whitespace matched
    for (var state = 0, matchedLen = 0, i = 0;; i++) {
      if (input.next < 0) {
        if (i != 0) input.acceptToken(textToken);
        break;
      }
      if (state == 0 && input.next == _lessThan || state == 1 && input.next == _slash || state >= 2 && state < lastState && input.next == tag.codeUnitAt(state - 2)) {
        state++;
        matchedLen++;
      } else if (state == lastState && input.next == _greaterThan) {
        if (i > matchedLen) {
          input.acceptToken(textToken, -matchedLen);
        } else {
          input.acceptToken(endToken, -(matchedLen - 2));
        }
        break;
      } else if ((input.next == 10 /* '\n' */ || input.next == 13 /* '\r' */ ) && i != 0) {
        input.acceptToken(textToken, 1);
        break;
      } else {
        state = matchedLen = 0;
      }
      input.advance();
    }
  });
}

/// @lezer/html's `parser`.
final LRParser htmlParser = LRParser.deserialize(
  htmlSpec,
  tokenizers: <String, Tokenizer>{
    'scriptTokens': _contentTokenizer('script', _T.scriptText, _T.StartCloseScriptTag),
    'styleTokens': _contentTokenizer('style', _T.styleText, _T.StartCloseStyleTag),
    'textareaTokens': _contentTokenizer('textarea', _T.textareaText, _T.StartCloseTextareaTag),
    'endTag': _endTag,
    'tagStart': _tagStart,
    'commentContent': _commentContent,
  },
  context: _elementContext,
);

/// `html({matchClosingTags: false})`: the HTML of a tag or a block in a line of Markdown, where a closing tag is
/// not asked to match an open one (@codemirror/lang-markdown's `htmlNoMatch`).
final LRParser htmlNoMatchParser = htmlParser.configure(dialect: 'noMatch');
