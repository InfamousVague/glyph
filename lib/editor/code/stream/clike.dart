// Ported from @codemirror/legacy-modes 6 (mode/clike.js), which is CodeMirror 5's clike mode:
//
// MIT License
//
// Copyright (C) 2017 by Marijn Haverbeke <marijn@haverbeke.berlin> and others
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

/// The languages that look like C, as the language pack reads the ones it has no grammar for: C#, Kotlin, Dart,
/// Scala and Objective-C. One tokenizer, configured for each with its words and with hooks for what is its own
/// (C#'s `@"…"`, Kotlin's `"""…"""`, Dart's `'$name'`).
///
/// What is left out: `indent`, which the port's editor does not ask a mode for. The contexts it reads are kept,
/// since what counts as a definition is read off them too.
library;

import 'stream_language.dart';
import 'string_stream.dart';

/// A hook's way of saying it has nothing to say (JavaScript's `false`, and `undefined` from the `token` hook).
const String _pass = '\u0000pass';

typedef ClikeTokenizer = String? Function(StringStream stream, ClikeState state);
typedef ClikeHook = String? Function(StringStream stream, ClikeState state);
typedef ClikeTokenHook = String? Function(StringStream stream, ClikeState state, String? style);

class ClikeContext {
  ClikeContext(this.indented, this.column, this.type, this.info, this.align, this.prev);

  final int indented, column;
  final String type;
  final String? info;
  bool? align;
  final ClikeContext? prev;
}

class ClikeState {
  ClikeState(this.context);

  ClikeTokenizer? tokenize;
  ClikeContext context;
  int indented = 0;
  bool startOfLine = true;
  String? prevToken;
  bool typeAtEndOfLine = false;
  List<ClikeTokenizer?>? interpolationStack;

  ClikeState copy() => ClikeState(context)
    ..tokenize = tokenize
    ..indented = indented
    ..startOfLine = startOfLine
    ..prevToken = prevToken
    ..typeAtEndOfLine = typeAtEndOfLine
    ..interpolationStack = interpolationStack == null ? null : List<ClikeTokenizer?>.of(interpolationStack!);
}

ClikeContext _pushContext(ClikeState state, int col, String type, [String? info]) {
  var indent = state.indented;
  if (state.context.type == 'statement' && type != 'statement') indent = state.context.indented;
  return state.context = ClikeContext(indent, col, type, info, null, state.context);
}

ClikeContext _popContext(ClikeState state) {
  final t = state.context.type;
  if (t == ')' || t == ']' || t == '}') state.indented = state.context.indented;
  return state.context = state.context.prev!;
}

final RegExp _typeBefore = RegExp(r'\S(?:[^- ]>|[*\]])\s*$|\*$');

bool _isTypeBefore(StringStream stream, ClikeState state, int pos) {
  if (state.prevToken == 'variable' || state.prevToken == 'type') return true;
  if (_typeBefore.hasMatch(stream.string.substring(0, pos))) return true;
  if (state.typeAtEndOfLine && stream.column() == stream.indentation()) return true;
  return false;
}

bool _isTopScope(ClikeContext? context) {
  for (;;) {
    if (context == null || context.type == 'top') return true;
    if (context.type == '}' && context.prev!.info != 'namespace') return false;
    context = context.prev;
  }
}

Set<String> _words(String str) => str.split(' ').toSet();

bool Function(String word) _in(Set<String> words) => words.contains;

bool _none(String word) => false;

final RegExp _defaultPunctuation = RegExp(r'[\[\]{}\(\),;\:\.]');
final RegExp _defaultNumberStart = RegExp(r'[\d\.]');
final RegExp _defaultNumber = RegExp(r'^(?:0x[a-f\d]+|0b[01]+|(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?)(u|ll?|l|f)?', caseSensitive: false);
final RegExp _defaultOperator = RegExp(r'[+\-*&%=<>!?|\/]');
final RegExp _defaultIdentifier = RegExp('[\\w\\\$_¡-￿]');
final RegExp _commentAhead = RegExp(r'^\/[\/*]');
final RegExp _restIsComment = RegExp(r'^\s*(?:\/\/.*)?$');
final RegExp _parenAhead = RegExp(r'^\s*\(');

/// `clike(parserConfig)`.
class Clike extends StreamMode<ClikeState> {
  Clike({
    this.keywords = _none,
    this.types = _none,
    this.builtin = _none,
    this.blockKeywords = _none,
    this.defKeywords = _none,
    this.atoms = _none,
    this.hooks = const <String, ClikeHook>{},
    this.tokenHook,
    this.multiLineStrings = false,
    this.indentStatements = true,
    this.typeFirstDefinitions = false,
    this.namespaceSeparator,
    RegExp? isPunctuationChar,
    RegExp? numberStart,
    RegExp? number,
    RegExp? isOperatorChar,
    RegExp? isIdentifierChar,
    this.isReservedIdentifier,
  }) : isPunctuationChar = isPunctuationChar ?? _defaultPunctuation,
       numberStart = numberStart ?? _defaultNumberStart,
       number = number ?? _defaultNumber,
       isOperatorChar = isOperatorChar ?? _defaultOperator,
       isIdentifierChar = isIdentifierChar ?? _defaultIdentifier;

  final bool Function(String word) keywords, types, builtin, blockKeywords, defKeywords, atoms;
  final Map<String, ClikeHook> hooks;
  final ClikeTokenHook? tokenHook;
  final bool multiLineStrings, indentStatements, typeFirstDefinitions;
  final String? namespaceSeparator;
  final RegExp isPunctuationChar, numberStart, number, isOperatorChar, isIdentifierChar;
  final bool Function(String token)? isReservedIdentifier;

  // What the token just read was, for `token` to act on: set by the tokenizers, read once.
  String? _curPunc;
  bool _isDefKeyword = false;

  String? _tokenBase(StringStream stream, ClikeState state) {
    final ch = stream.next()!;
    final hook = hooks[ch];
    if (hook != null) {
      final result = hook(stream, state);
      if (result != _pass) return result;
    }
    if (ch == '"' || ch == "'") {
      state.tokenize = _tokenString(ch);
      return state.tokenize!(stream, state);
    }
    if (numberStart.hasMatch(ch)) {
      stream.backUp(1);
      if (stream.match(number) != null) return 'number';
      stream.next();
    }
    if (isPunctuationChar.hasMatch(ch)) {
      _curPunc = ch;
      return null;
    }
    if (ch == '/') {
      if (stream.eat('*') != null) {
        state.tokenize = _tokenComment;
        return _tokenComment(stream, state);
      }
      if (stream.eat('/') != null) {
        stream.skipToEnd();
        return 'comment';
      }
    }
    if (isOperatorChar.hasMatch(ch)) {
      while (stream.match(_commentAhead, consume: false) == null && stream.eatMatch(isOperatorChar) != null) {}
      return 'operator';
    }
    stream.eatWhile(isIdentifierChar);
    if (namespaceSeparator != null) {
      while (stream.matchString(namespaceSeparator!)) {
        stream.eatWhile(isIdentifierChar);
      }
    }

    final cur = stream.current();
    if (keywords(cur)) {
      if (blockKeywords(cur)) _curPunc = 'newstatement';
      if (defKeywords(cur)) _isDefKeyword = true;
      return 'keyword';
    }
    if (types(cur)) return 'type';
    if (builtin(cur) || (isReservedIdentifier != null && isReservedIdentifier!(cur))) {
      if (blockKeywords(cur)) _curPunc = 'newstatement';
      return 'builtin';
    }
    if (atoms(cur)) return 'atom';
    return 'variable';
  }

  ClikeTokenizer _tokenString(String quote) => (stream, state) {
    var escaped = false, end = false;
    for (;;) {
      final next = stream.next();
      if (next == null) break;
      if (next == quote && !escaped) {
        end = true;
        break;
      }
      escaped = !escaped && next == '\\';
    }
    if (end || !(escaped || multiLineStrings)) state.tokenize = null;
    return 'string';
  };

  static String? _tokenComment(StringStream stream, ClikeState state) {
    var maybeEnd = false;
    for (;;) {
      final ch = stream.next();
      if (ch == null) break;
      if (ch == '/' && maybeEnd) {
        state.tokenize = null;
        break;
      }
      maybeEnd = ch == '*';
    }
    return 'comment';
  }

  void _maybeEOL(StringStream stream, ClikeState state) {
    if (typeFirstDefinitions && stream.eol() && _isTopScope(state.context)) state.typeAtEndOfLine = _isTypeBefore(stream, state, stream.pos);
  }

  @override
  ClikeState startState(int indentUnit) => ClikeState(ClikeContext(-indentUnit, 0, 'top', null, false, null));

  @override
  ClikeState copyState(ClikeState state) => state.copy();

  @override
  String? token(StringStream stream, ClikeState state) {
    var ctx = state.context;
    if (stream.sol()) {
      ctx.align ??= false;
      state.indented = stream.indentation();
      state.startOfLine = true;
    }
    if (stream.eatSpace()) {
      _maybeEOL(stream, state);
      return null;
    }
    _curPunc = null;
    _isDefKeyword = false;
    var style = (state.tokenize ?? _tokenBase)(stream, state);
    if (style == 'comment' || style == 'meta') return style;
    ctx.align ??= true;

    final curPunc = _curPunc;
    if (curPunc == ';' || curPunc == ':' || (curPunc == ',' && stream.match(_restIsComment, consume: false) != null)) {
      while (state.context.type == 'statement') {
        _popContext(state);
      }
    } else if (curPunc == '{') {
      _pushContext(state, stream.column(), '}');
    } else if (curPunc == '[') {
      _pushContext(state, stream.column(), ']');
    } else if (curPunc == '(') {
      _pushContext(state, stream.column(), ')');
    } else if (curPunc == '}') {
      while (ctx.type == 'statement') {
        ctx = _popContext(state);
      }
      if (ctx.type == '}') ctx = _popContext(state);
      while (ctx.type == 'statement') {
        ctx = _popContext(state);
      }
    } else if (curPunc == ctx.type) {
      _popContext(state);
    } else if (indentStatements && (((ctx.type == '}' || ctx.type == 'top') && curPunc != ';') || (ctx.type == 'statement' && curPunc == 'newstatement'))) {
      _pushContext(state, stream.column(), 'statement', stream.current());
    }

    if (style == 'variable' &&
        (state.prevToken == 'def' || (typeFirstDefinitions && _isTypeBefore(stream, state, stream.start) && _isTopScope(state.context) && stream.match(_parenAhead, consume: false) != null))) {
      style = 'def';
    }

    if (tokenHook != null) {
      final result = tokenHook!(stream, state, style);
      if (result != _pass) style = result;
    }

    state.startOfLine = false;
    state.prevToken = _isDefKeyword ? 'def' : (style == null || style.isEmpty ? curPunc : style);
    _maybeEOL(stream, state);
    return style;
  }
}

const String _cKeywords =
    'auto if break case register continue return default do sizeof '
    'static else struct switch extern typedef union for goto while enum const '
    'volatile inline restrict asm fortran';

const String _objCKeywords =
    'bycopy byref in inout oneway out self super atomic nonatomic retain copy '
    'readwrite readonly strong weak assign typeof nullable nonnull null_resettable _cmd '
    '@interface @implementation @end @protocol @encode @property @synthesize @dynamic @class '
    '@public @package @private @protected @required @optional @try @catch @finally @import '
    '@selector @encode @defs @synchronized @autoreleasepool @compatibility_alias @available';

const String _objCBuiltins =
    'FOUNDATION_EXPORT FOUNDATION_EXTERN NS_INLINE NS_FORMAT_FUNCTION '
    ' NS_RETURNS_RETAINEDNS_ERROR_ENUM NS_RETURNS_NOT_RETAINED NS_RETURNS_INNER_POINTER '
    'NS_DESIGNATED_INITIALIZER NS_ENUM NS_OPTIONS NS_REQUIRES_NIL_TERMINATION '
    'NS_ASSUME_NONNULL_BEGIN NS_ASSUME_NONNULL_END NS_SWIFT_NAME NS_REFINED_FOR_SWIFT';

final Set<String> _basicCTypes = _words('int long char short double float unsigned signed void bool');
final Set<String> _basicObjCTypes = _words('SEL instancetype id Class Protocol BOOL');
final RegExp _posixType = RegExp(r'.+_t$');

// Returns true if identifier is a "C" type: those reserved by the compiler, and those that end in _t (reserved
// by POSIX for types).
bool _cTypes(String identifier) => _basicCTypes.contains(identifier) || _posixType.hasMatch(identifier);

bool _objCTypes(String identifier) => _cTypes(identifier) || _basicObjCTypes.contains(identifier);

const String _cBlockKeywords = 'case do else for if switch while struct enum union';
const String _cDefKeywords = 'struct enum union';

final RegExp _anyOne = RegExp(r'^.$');

String? _cppHook(StringStream stream, ClikeState state) {
  if (!state.startOfLine) return _pass;
  ClikeTokenizer? next;
  for (;;) {
    final ch = stream.peek();
    if (ch == null) break;
    if (ch == '\\' && stream.match(_anyOne) != null) {
      next = _cppHook;
      break;
    } else if (ch == '/' && stream.match(_commentAhead, consume: false) != null) {
      break;
    }
    stream.next();
  }
  state.tokenize = next;
  return 'meta';
}

String? _pointerHook(StringStream stream, ClikeState state) => state.prevToken == 'type' ? 'type' : _pass;

// For C and C++ (and ObjC): identifiers starting with __ or _ followed by a capital letter are reserved for the
// compiler.
bool _cIsReservedIdentifier(String token) {
  if (token.length < 2) return false;
  if (token[0] != '_') return false;
  return token[1] == '_' || token[1] != token[1].toLowerCase();
}

// C#-style strings where "" escapes a quote.
String? _tokenAtString(StringStream stream, ClikeState state) {
  for (;;) {
    final next = stream.next();
    if (next == null) break;
    if (next == '"' && stream.eat('"') == null) {
      state.tokenize = null;
      break;
    }
  }
  return 'string';
}

final RegExp _wordish = RegExp(r'[\w\$_]');

/// `csharp`.
Clike csharp() => Clike(
  keywords: _in(
    _words(
      'abstract as async await base break case catch checked class const continue'
      ' default delegate do else enum event explicit extern finally fixed for'
      ' foreach goto if implicit in init interface internal is lock namespace new'
      ' operator out override params private protected public readonly record ref required return sealed'
      ' sizeof stackalloc static struct switch this throw try typeof unchecked'
      ' unsafe using virtual void volatile while add alias ascending descending dynamic from get'
      ' global group into join let orderby partial remove select set value var yield',
    ),
  ),
  types: _in(
    _words(
      'Action Boolean Byte Char DateTime DateTimeOffset Decimal Double Func'
      ' Guid Int16 Int32 Int64 Object SByte Single String Task TimeSpan UInt16 UInt32'
      ' UInt64 bool byte char decimal double short int long object'
      ' sbyte float string ushort uint ulong',
    ),
  ),
  blockKeywords: _in(_words('catch class do else finally for foreach if struct switch try while')),
  defKeywords: _in(_words('class interface namespace record struct var')),
  typeFirstDefinitions: true,
  atoms: _in(_words('true false null')),
  hooks: <String, ClikeHook>{
    '@': (stream, state) {
      if (stream.eat('"') != null) {
        state.tokenize = _tokenAtString;
        return _tokenAtString(stream, state);
      }
      stream.eatWhile(_wordish);
      return 'meta';
    },
  },
);

String? _tokenTripleString(StringStream stream, ClikeState state) {
  var escaped = false;
  while (!stream.eol()) {
    if (!escaped && stream.matchString('"""')) {
      state.tokenize = null;
      break;
    }
    escaped = stream.next() == '\\' && !escaped;
  }
  return 'string';
}

ClikeTokenizer _tokenNestedComment(int depth) => (stream, state) {
  for (;;) {
    final ch = stream.next();
    if (ch == null) break;
    if (ch == '*' && stream.eat('/') != null) {
      if (depth == 1) {
        state.tokenize = null;
        break;
      } else {
        state.tokenize = _tokenNestedComment(depth - 1);
        return state.tokenize!(stream, state);
      }
    } else if (ch == '/' && stream.eat('*') != null) {
      state.tokenize = _tokenNestedComment(depth + 1);
      return state.tokenize!(stream, state);
    }
  }
  return 'comment';
};

String? _nestedCommentHook(StringStream stream, ClikeState state) {
  if (stream.eat('*') == null) return _pass;
  state.tokenize = _tokenNestedComment(1);
  return state.tokenize!(stream, state);
}

final RegExp _scalaChar = RegExp(r"^(\\[^'\s]+|[^\\'])'");
final RegExp _scalaSymbol = RegExp('[\\w\\\$_¡-￿]');

/// `scala`.
Clike scala() => Clike(
  keywords: _in(
    _words(
      /* scala */
      'abstract case catch class def do else extends final finally for forSome if '
      'implicit import lazy match new null object override package private protected return '
      'sealed super this throw trait try type val var while with yield _ '
      /* package scala */
      'assert assume require print println printf readLine readBoolean readByte readShort '
      'readChar readInt readLong readFloat readDouble',
    ),
  ),
  types: _in(
    _words(
      'AnyVal App Application Array BufferedIterator BigDecimal BigInt Char Console Either '
      'Enumeration Equiv Error Exception Fractional Function IndexedSeq Int Integral Iterable '
      'Iterator List Map Numeric Nil NotNull Option Ordered Ordering PartialFunction PartialOrdering '
      'Product Proxy Range Responder Seq Serializable Set Specializable Stream StringBuilder '
      'StringContext Symbol Throwable Traversable TraversableOnce Tuple Unit Vector '
      /* package java.lang */
      'Boolean Byte Character CharSequence Class ClassLoader Cloneable Comparable '
      'Compiler Double Exception Float Integer Long Math Number Object Package Pair Process '
      'Runtime Runnable SecurityManager Short StackTraceElement StrictMath String '
      'StringBuffer System Thread ThreadGroup ThreadLocal Throwable Triple Void',
    ),
  ),
  multiLineStrings: true,
  blockKeywords: _in(_words('catch class enum do else finally for forSome if match switch try while')),
  defKeywords: _in(_words('class enum def object package trait type val var')),
  atoms: _in(_words('true false null')),
  indentStatements: false,
  isOperatorChar: RegExp(r'[+\-*&%=<>!?|\/#:@]'),
  hooks: <String, ClikeHook>{
    '@': (stream, state) {
      stream.eatWhile(_wordish);
      return 'meta';
    },
    '"': (stream, state) {
      if (!stream.matchString('""')) return _pass;
      state.tokenize = _tokenTripleString;
      return state.tokenize!(stream, state);
    },
    "'": (stream, state) {
      if (stream.match(_scalaChar) != null) return 'character';
      stream.eatWhile(_scalaSymbol);
      return 'atom';
    },
    '=': (stream, state) {
      final cx = state.context;
      if (cx.type == '}' && cx.align == true && stream.eat('>') != null) {
        state.context = ClikeContext(cx.indented, cx.column, cx.type, cx.info, null, cx.prev);
        return 'operator';
      } else {
        return _pass;
      }
    },
    '/': _nestedCommentHook,
  },
);

ClikeTokenizer _tokenKotlinString(bool tripleString) => (stream, state) {
  var escaped = false, end = false;
  while (!stream.eol()) {
    if (!tripleString && !escaped && stream.matchString('"')) {
      end = true;
      break;
    }
    if (tripleString && stream.matchString('"""')) {
      end = true;
      break;
    }
    final next = stream.next();
    if (!escaped && next == r'$' && stream.matchString('{')) stream.skipTo('}');
    escaped = !escaped && next == '\\' && !tripleString;
  }
  if (end || !tripleString) state.tokenize = null;
  return 'string';
};

/// `kotlin`.
Clike kotlin() => Clike(
  keywords: _in(
    _words(
      /*keywords*/
      'package as typealias class interface this super val operator '
      'var fun for is in This throw return annotation '
      'break continue object if else while do try when !in !is as? '
      /*soft keywords*/
      'file import where by get set abstract enum open inner override private public internal '
      'protected catch finally out final vararg reified dynamic companion constructor init '
      'sealed field property receiver param sparam lateinit data inline noinline tailrec '
      'external annotation crossinline const operator infix suspend actual expect setparam',
    ),
  ),
  types: _in(
    _words(
      /* package java.lang */
      'Boolean Byte Character CharSequence Class ClassLoader Cloneable Comparable '
      'Compiler Double Exception Float Integer Long Math Number Object Package Pair Process '
      'Runtime Runnable SecurityManager Short StackTraceElement StrictMath String '
      'StringBuffer System Thread ThreadGroup ThreadLocal Throwable Triple Void Annotation Any BooleanArray '
      'ByteArray Char CharArray DeprecationLevel DoubleArray Enum FloatArray Function Int IntArray Lazy '
      'LazyThreadSafetyMode LongArray Nothing ShortArray Unit',
    ),
  ),
  indentStatements: false,
  multiLineStrings: true,
  number: RegExp(r'^(?:0x[a-f\d_]+|0b[01_]+|(?:[\d_]+(\.\d+)?|\.\d+)(?:e[-+]?[\d_]+)?)(ul?|l|f)?', caseSensitive: false),
  blockKeywords: _in(_words('catch class do else finally for if where try while enum')),
  defKeywords: _in(_words('class val var object interface fun')),
  atoms: _in(_words('true false null this')),
  hooks: <String, ClikeHook>{
    '@': (stream, state) {
      stream.eatWhile(_wordish);
      return 'meta';
    },
    '*': (stream, state) => state.prevToken == '.' ? 'variable' : 'operator',
    '"': (stream, state) {
      state.tokenize = _tokenKotlinString(stream.matchString('""'));
      return state.tokenize!(stream, state);
    },
    '/': _nestedCommentHook,
  },
);

/// `objectiveC`.
Clike objectiveC() => Clike(
  keywords: _in(_words('$_cKeywords $_objCKeywords')),
  types: _objCTypes,
  builtin: _in(_words(_objCBuiltins)),
  blockKeywords: _in(_words('$_cBlockKeywords @synthesize @try @catch @finally @autoreleasepool @synchronized')),
  defKeywords: _in(_words('$_cDefKeywords @interface @implementation @protocol @class')),
  typeFirstDefinitions: true,
  atoms: _in(_words('YES NO NULL Nil nil true false nullptr')),
  isReservedIdentifier: _cIsReservedIdentifier,
  hooks: <String, ClikeHook>{'#': _cppHook, '*': _pointerHook},
);

void _pushInterpolationStack(ClikeState state) => (state.interpolationStack ??= <ClikeTokenizer?>[]).add(state.tokenize);

ClikeTokenizer? _popInterpolationStack(ClikeState state) {
  final stack = state.interpolationStack ??= <ClikeTokenizer?>[];
  return stack.isEmpty ? null : stack.removeLast();
}

int _sizeInterpolationStack(ClikeState state) => state.interpolationStack?.length ?? 0;

String? _tokenDartString(String quote, StringStream stream, ClikeState state, bool raw) {
  var tripleQuoted = false;
  if (stream.eat(quote) != null) {
    if (stream.eat(quote) != null) {
      tripleQuoted = true;
    } else {
      return 'string'; //empty string
    }
  }
  String? tokenStringHelper(StringStream stream, ClikeState state) {
    var escaped = false;
    while (!stream.eol()) {
      if (!raw && !escaped && stream.peek() == r'$') {
        _pushInterpolationStack(state);
        state.tokenize = _tokenInterpolation;
        return 'string';
      }
      final next = stream.next();
      if (next == quote && !escaped && (!tripleQuoted || stream.matchString(quote + quote))) {
        state.tokenize = null;
        break;
      }
      escaped = !raw && !escaped && next == '\\';
    }
    return 'string';
  }

  state.tokenize = tokenStringHelper;
  return tokenStringHelper(stream, state);
}

String? _tokenInterpolation(StringStream stream, ClikeState state) {
  stream.eat(r'$');
  if (stream.eat('{') != null) {
    // let clike handle the content of ${...}, we take over again when "}" appears (see hooks).
    state.tokenize = null;
  } else {
    state.tokenize = _tokenInterpolationIdentifier;
  }
  return null;
}

final RegExp _wordChar = RegExp(r'[\w_]');

String? _tokenInterpolationIdentifier(StringStream stream, ClikeState state) {
  stream.eatWhile(_wordChar);
  state.tokenize = _popInterpolationStack(state);
  return 'variable';
}

final RegExp _dartAnnotation = RegExp(r'[\w\$_\.]');
final RegExp _dartIsUpper = RegExp(r'^[_$]*[A-Z][a-zA-Z0-9_$]*$');

/// `dart`.
Clike dart() => Clike(
  keywords: _in(
    _words(
      'this super static final const abstract class extends external factory '
      'implements mixin get native set typedef with enum throw rethrow assert break case '
      'continue default in return new deferred async await covariant try catch finally '
      'do else for if switch while import library export part of show hide is as extension '
      'on yield late required sealed base interface when inline',
    ),
  ),
  blockKeywords: _in(_words('try catch finally do else for if switch while')),
  builtin: _in(_words('void bool num int double dynamic var String Null Never')),
  atoms: _in(_words('true false null')),
  // clike numbers without the suffixes, and with '_' separators.
  number: RegExp(r'^(?:0x[a-f\d_]+|(?:[\d_]+\.?[\d_]*|\.[\d_]+)(?:e[-+]?[\d_]+)?)', caseSensitive: false),
  hooks: <String, ClikeHook>{
    '@': (stream, state) {
      stream.eatWhile(_dartAnnotation);
      return 'meta';
    },
    // custom string handling to deal with triple-quoted strings and string interpolation
    "'": (stream, state) => _tokenDartString("'", stream, state, false),
    '"': (stream, state) => _tokenDartString('"', stream, state, false),
    'r': (stream, state) {
      final peek = stream.peek();
      if (peek == "'" || peek == '"') return _tokenDartString(stream.next()!, stream, state, true);
      return _pass;
    },
    '}': (stream, state) {
      // "}" is end of interpolation, if interpolation stack is non-empty
      if (_sizeInterpolationStack(state) > 0) {
        state.tokenize = _popInterpolationStack(state);
        return null;
      }
      return _pass;
    },
    '/': _nestedCommentHook,
  },
  // Assume uppercase symbols are classes
  tokenHook: (stream, state, style) => style == 'variable' && _dartIsUpper.hasMatch(stream.current()) ? 'type' : _pass,
);
