// Ported from @codemirror/legacy-modes 6 (mode/swift.js, shell.js, toml.js, diff.js, properties.js, lua.js,
// ruby.js), which are CodeMirror 5's modes of those names:
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

/// Swift, the shell, TOML, diffs, properties files, Lua and Ruby, as the language pack reads them: each a
/// `token` function over a line and a state, kept as close to the JavaScript as Dart lets it be, quirks and all,
/// since a quirk is a colour on the page.
///
/// What is left out of each: `indent` and the contexts only it reads. Where JavaScript kept a count inside a
/// closure the state holds (Swift's parentheses in a string, Ruby's braces), the count is in an object here that
/// a copy of the state copies, so that a line read again from a kept state reads as it did the first time.
library;

import 'stream_language.dart';
import 'string_stream.dart';

/// JavaScript's `/\w/.test(ch)` and friends, where `ch` may be `undefined`: the word "undefined" is tested.
bool _test(RegExp pattern, String? ch) => pattern.hasMatch(ch ?? 'undefined');

final RegExp _w = RegExp(r'\w');
final RegExp _d = RegExp(r'\d');

// ---- Swift ----------------------------------------------------------------------------------------------------------

const Set<String> _swiftKeywords = <String>{
  '_', 'var', 'let', 'actor', 'class', 'enum', 'extension', 'import', 'protocol', 'struct', 'func', 'typealias', 'associatedtype', //
  'open', 'public', 'internal', 'fileprivate', 'private', 'deinit', 'init', 'new', 'override', 'self', 'subscript', 'super',
  'convenience', 'dynamic', 'final', 'indirect', 'lazy', 'required', 'static', 'unowned', 'unowned(safe)', 'unowned(unsafe)', 'weak', 'as', 'is',
  'break', 'case', 'continue', 'default', 'else', 'fallthrough', 'for', 'guard', 'if', 'in', 'repeat', 'switch', 'where', 'while',
  'defer', 'return', 'inout', 'mutating', 'nonmutating', 'isolated', 'nonisolated', 'catch', 'do', 'rethrows', 'throw', 'throws', 'async', 'await', 'try', 'didSet', 'get', 'set', 'willSet',
  'assignment', 'associativity', 'infix', 'left', 'none', 'operator', 'postfix', 'precedence', 'precedencegroup', 'prefix', 'right',
  'Any', 'AnyObject', 'Type', 'dynamicType', 'Self', 'Protocol', '__COLUMN__', '__FILE__', '__FUNCTION__', '__LINE__',
};
const Set<String> _swiftDefining = <String>{'var', 'let', 'actor', 'class', 'enum', 'extension', 'import', 'protocol', 'struct', 'func', 'typealias', 'associatedtype', 'for'};
const Set<String> _swiftAtoms = <String>{'true', 'false', 'nil', 'self', 'super', '_'};
const Set<String> _swiftTypes = <String>{'Array', 'Bool', 'Character', 'Dictionary', 'Double', 'Float', 'Int', 'Int8', 'Int16', 'Int32', 'Int64', 'Never', 'Optional', 'Set', 'String', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'Void'};
const String _swiftOperators = '+-/*%=|&<>~^?!';
const String _swiftPunc = ':;,.(){}[]';
final RegExp _swiftBinary = RegExp(r'^\-?0b[01][01_]*');
final RegExp _swiftOctal = RegExp(r'^\-?0o[0-7][0-7_]*');
final RegExp _swiftHex = RegExp(r'^\-?0x[\dA-Fa-f][\dA-Fa-f_]*(?:(?:\.[\dA-Fa-f][\dA-Fa-f_]*)?[Pp]\-?\d[\d_]*)?');
final RegExp _swiftDecimal = RegExp(r'^\-?\d[\d_]*(?:\.\d[\d_]*)?(?:[Ee]\-?\d[\d_]*)?');
final RegExp _swiftIdentifier = RegExp(r'^\$\d+|(`?)[_A-Za-z][_A-Za-z$0-9]*\1');
final RegExp _swiftProperty = RegExp(r'^\.(?:\$\d+|(`?)[_A-Za-z][_A-Za-z$0-9]*\1)');
final RegExp _swiftInstruction = RegExp(r'^\#[A-Za-z]+');
final RegExp _swiftAttribute = RegExp(r'^@(?:\$\d+|(`?)[_A-Za-z][_A-Za-z$0-9]*\1)');
final RegExp _swiftQuote = RegExp('("""|"|\')');

/// What reads the next token: the base reader, a string, a comment, or code inside a string's `\( … )`.
abstract class SwiftTokenizer {
  const SwiftTokenizer();

  String? read(StringStream stream, SwiftState state, String? prev);

  /// A copy, for a copy of the state: the same object where it holds nothing that changes.
  SwiftTokenizer copy() => this;
}

class SwiftState {
  String? prev;
  List<SwiftTokenizer> tokenize = <SwiftTokenizer>[];
}

String? _swiftBase(StringStream stream, SwiftState state, String? prev) {
  if (stream.eatSpace()) return null;

  final ch = stream.peek();
  if (ch == '/') {
    if (stream.matchString('//')) {
      stream.skipToEnd();
      return 'comment';
    }
    if (stream.matchString('/*')) {
      state.tokenize.add(const _SwiftComment());
      return const _SwiftComment().read(stream, state, prev);
    }
  }
  if (stream.match(_swiftInstruction) != null) return 'builtin';
  if (stream.match(_swiftAttribute) != null) return 'attribute';
  if (stream.match(_swiftBinary) != null) return 'number';
  if (stream.match(_swiftOctal) != null) return 'number';
  if (stream.match(_swiftHex) != null) return 'number';
  if (stream.match(_swiftDecimal) != null) return 'number';
  if (stream.match(_swiftProperty) != null) return 'property';
  if (ch != null && _swiftOperators.contains(ch)) {
    stream.next();
    return 'operator';
  }
  if (ch != null && _swiftPunc.contains(ch)) {
    stream.next();
    stream.matchString('..');
    return 'punctuation';
  }
  final stringMatch = stream.match(_swiftQuote);
  if (stringMatch != null) {
    final tokenize = _SwiftString(stringMatch.group(0)!);
    state.tokenize.add(tokenize);
    return tokenize.read(stream, state, prev);
  }

  if (stream.match(_swiftIdentifier) != null) {
    final ident = stream.current();
    if (_swiftTypes.contains(ident)) return 'type';
    if (_swiftAtoms.contains(ident)) return 'atom';
    if (_swiftKeywords.contains(ident)) {
      if (_swiftDefining.contains(ident)) state.prev = 'define';
      return 'keyword';
    }
    if (prev == 'define') return 'def';
    return 'variable';
  }

  stream.next();
  return null;
}

class _SwiftBase extends SwiftTokenizer {
  const _SwiftBase();

  @override
  String? read(StringStream stream, SwiftState state, String? prev) => _swiftBase(stream, state, prev);
}

class _SwiftUntilClosingParen extends SwiftTokenizer {
  _SwiftUntilClosingParen([this.depth = 0]);

  int depth;

  @override
  SwiftTokenizer copy() => _SwiftUntilClosingParen(depth);

  @override
  String? read(StringStream stream, SwiftState state, String? prev) {
    final inner = _swiftBase(stream, state, prev);
    if (inner == 'punctuation') {
      if (stream.current() == '(') {
        ++depth;
      } else if (stream.current() == ')') {
        if (depth == 0) {
          stream.backUp(1);
          state.tokenize.removeLast();
          // `state.tokenize[state.tokenize.length - 1](stream, state)`: no `prev` is handed on.
          return state.tokenize.last.read(stream, state, null);
        } else {
          --depth;
        }
      }
    }
    return inner;
  }
}

class _SwiftString extends SwiftTokenizer {
  const _SwiftString(this.openQuote);

  final String openQuote;

  @override
  String? read(StringStream stream, SwiftState state, String? prev) {
    final singleLine = openQuote.length == 1;
    var escaped = false;
    for (;;) {
      final ch = stream.peek();
      if (ch == null) break;
      if (escaped) {
        stream.next();
        if (ch == '(') {
          state.tokenize.add(_SwiftUntilClosingParen());
          return 'string';
        }
        escaped = false;
      } else if (stream.matchString(openQuote)) {
        state.tokenize.removeLast();
        return 'string';
      } else {
        stream.next();
        escaped = ch == '\\';
      }
    }
    if (singleLine) state.tokenize.removeLast();
    return 'string';
  }
}

class _SwiftComment extends SwiftTokenizer {
  const _SwiftComment();

  @override
  String? read(StringStream stream, SwiftState state, String? prev) {
    for (;;) {
      final ch = stream.next();
      if (ch == null) break;
      if (ch == '/' && stream.eat('*') != null) {
        state.tokenize.add(const _SwiftComment());
      } else if (ch == '*' && stream.eat('/') != null) {
        state.tokenize.removeLast();
        break;
      }
    }
    return 'comment';
  }
}

/// `swift`.
class Swift extends StreamMode<SwiftState> {
  const Swift();

  @override
  SwiftState startState(int indentUnit) => SwiftState();

  @override
  SwiftState copyState(SwiftState state) => SwiftState()
    ..prev = state.prev
    ..tokenize = <SwiftTokenizer>[for (final tokenize in state.tokenize) tokenize.copy()];

  @override
  String? token(StringStream stream, SwiftState state) {
    final prev = state.prev;
    state.prev = null;
    final tokenize = state.tokenize.isEmpty ? const _SwiftBase() : state.tokenize.last;
    final style = tokenize.read(stream, state, prev);
    if (style == null || style == 'comment') {
      state.prev = prev;
    } else {
      state.prev ??= style;
    }
    return style;
  }
}

// ---- Shell ----------------------------------------------------------------------------------------------------------

final Map<String, String> _shellWords = <String, String>{
  for (final word in const <String>['true', 'false']) word: 'atom',
  for (final word in const <String>['if', 'then', 'do', 'else', 'elif', 'while', 'until', 'for', 'in', 'esac', 'fi', 'fin', 'fil', 'done', 'exit', 'set', 'unset', 'export', 'function']) word: 'keyword',
  for (final word in const <String>[
    'ab', 'awk', 'bash', 'beep', 'cat', 'cc', 'cd', 'chown', 'chmod', 'chroot', 'clear', //
    'cp', 'curl', 'cut', 'diff', 'echo', 'find', 'gawk', 'gcc', 'get', 'git', 'grep', 'hg', 'kill', 'killall',
    'ln', 'ls', 'make', 'mkdir', 'openssl', 'mv', 'nc', 'nl', 'node', 'npm', 'ping', 'ps', 'restart', 'rm',
    'rmdir', 'sed', 'service', 'sh', 'shopt', 'shred', 'source', 'sort', 'sleep', 'ssh', 'start', 'stop',
    'su', 'sudo', 'svn', 'tee', 'telnet', 'top', 'touch', 'vi', 'vim', 'wall', 'wc', 'wget', 'who', 'write',
    'yes', 'zsh',
  ])
    word: 'builtin',
};

typedef ShellTokenizer = String? Function(StringStream stream, ShellState state);

class ShellState {
  ShellState([List<ShellTokenizer>? tokens]) : tokens = tokens ?? <ShellTokenizer>[];

  /// The readers in force, the innermost first.
  final List<ShellTokenizer> tokens;
}

final RegExp _shellHeredoc = RegExp(r'''^<-?\s*(?:['"]([^'"]*)['"]|([^'"\s]*))''');
final RegExp _shellWord = RegExp(r'[\w-]');
final RegExp _hasWord = RegExp(r'\w+');
final RegExp _quoteChar = RegExp(r'''['"]''');
final RegExp _dollarOpen = RegExp(r'''['"({]''');

String? _shellTokenize(StringStream stream, ShellState state) => (state.tokens.isEmpty ? _shellBase : state.tokens.first)(stream, state);

String? _shellBase(StringStream stream, ShellState state) {
  if (stream.eatSpace()) return null;

  final sol = stream.sol();
  final ch = stream.next();

  if (ch == '\\') {
    stream.next();
    return null;
  }
  if (ch == "'" || ch == '"' || ch == '`') {
    state.tokens.insert(0, _shellString(ch!, ch == '`' ? 'quote' : 'string'));
    return _shellTokenize(stream, state);
  }
  if (ch == '#') {
    if (sol && stream.eat('!') != null) {
      stream.skipToEnd();
      return 'meta'; // 'comment'?
    }
    stream.skipToEnd();
    return 'comment';
  }
  if (ch == r'$') {
    state.tokens.insert(0, _shellDollar);
    return _shellTokenize(stream, state);
  }
  if (ch == '+' || ch == '=') return 'operator';
  if (ch == '-') {
    stream.eat('-');
    stream.eatWhile(_w);
    return 'attribute';
  }
  if (ch == '<') {
    if (stream.matchString('<<')) return 'operator';
    final heredoc = stream.match(_shellHeredoc);
    if (heredoc != null) {
      final quoted = heredoc.group(1);
      state.tokens.insert(0, _shellHeredocReader(quoted != null && quoted.isNotEmpty ? quoted : heredoc.group(2)));
      return 'string.special';
    }
  }
  if (_test(_d, ch)) {
    stream.eatWhile(_d);
    if (stream.eol() || !_test(_w, stream.peek())) return 'number';
  }
  stream.eatWhile(_shellWord);
  final cur = stream.current();
  if (stream.peek() == '=' && _hasWord.hasMatch(cur)) return 'def';
  return _shellWords[cur];
}

ShellTokenizer _shellString(String quote, String style) {
  final close = quote == '('
      ? ')'
      : quote == '{'
      ? '}'
      : quote;
  return (stream, state) {
    var escaped = false;
    for (;;) {
      final next = stream.next();
      if (next == null) break;
      if (next == close && !escaped) {
        state.tokens.removeAt(0);
        break;
      } else if (next == r'$' && !escaped && quote != "'" && stream.peek() != close) {
        escaped = true;
        stream.backUp(1);
        state.tokens.insert(0, _shellDollar);
        break;
      } else if (!escaped && quote != close && next == quote) {
        state.tokens.insert(0, _shellString(quote, style));
        return _shellTokenize(stream, state);
      } else if (!escaped && _quoteChar.hasMatch(next) && !_quoteChar.hasMatch(quote)) {
        state.tokens.insert(0, _shellStringStart(next, 'string'));
        stream.backUp(1);
        break;
      }
      escaped = !escaped && next == '\\';
    }
    return style;
  };
}

ShellTokenizer _shellStringStart(String quote, String style) => (stream, state) {
  state.tokens[0] = _shellString(quote, style);
  stream.next();
  return _shellTokenize(stream, state);
};

String? _shellDollar(StringStream stream, ShellState state) {
  if (state.tokens.length > 1) stream.eat(r'$');
  final ch = stream.next();
  if (ch != null && _dollarOpen.hasMatch(ch)) {
    state.tokens[0] = _shellString(
      ch,
      ch == '('
          ? 'quote'
          : ch == '{'
          ? 'def'
          : 'string',
    );
    return _shellTokenize(stream, state);
  }
  if (!_test(_d, ch)) stream.eatWhile(_w);
  state.tokens.removeAt(0);
  return 'def';
}

ShellTokenizer _shellHeredocReader(String? delim) => (stream, state) {
  if (stream.sol() && stream.string == delim) state.tokens.removeAt(0);
  stream.skipToEnd();
  return 'string.special';
};

/// `shell`.
class Shell extends StreamMode<ShellState> {
  const Shell();

  @override
  ShellState startState(int indentUnit) => ShellState();

  @override
  ShellState copyState(ShellState state) => ShellState(List<ShellTokenizer>.of(state.tokens));

  @override
  String? token(StringStream stream, ShellState state) => _shellTokenize(stream, state);
}

// ---- TOML -----------------------------------------------------------------------------------------------------------

class TomlState {
  bool inString = false;
  String stringType = '';
  bool lhs = true;
  int inArray = 0;
}

final RegExp _tomlQuote = RegExp('^(\'\'\'|"""|\'|")');
final RegExp _tomlStringRun = RegExp(r'''^.[^\\\"\']*''');
final RegExp _tomlDate = RegExp(r'^\d\d\d\d[\d\-\:\.T]*Z');
final RegExp _tomlNumber = RegExp(r'^\-?\d+(?:\.\d+)?');

/// `toml`.
class Toml extends StreamMode<TomlState> {
  const Toml();

  @override
  TomlState startState(int indentUnit) => TomlState();

  @override
  TomlState copyState(TomlState state) => TomlState()
    ..inString = state.inString
    ..stringType = state.stringType
    ..lhs = state.lhs
    ..inArray = state.inArray;

  @override
  String? token(StringStream stream, TomlState state) {
    //check for state changes
    if (!state.inString) {
      final quote = stream.match(_tomlQuote);
      if (quote != null) {
        state.stringType = quote.group(0)!;
        state.inString = true; // Update state
      }
    }
    if (stream.sol() && !state.inString && state.inArray == 0) state.lhs = true;
    //return state
    if (state.inString) {
      while (state.inString) {
        if (stream.matchString(state.stringType)) {
          state.inString = false; // Clear flag
        } else if (stream.peek() == '\\') {
          stream.next();
          stream.next();
        } else if (stream.eol()) {
          break;
        } else {
          stream.match(_tomlStringRun);
        }
      }
      return state.lhs ? 'property' : 'string'; // Token style
    } else if (state.inArray != 0 && stream.peek() == ']') {
      stream.next();
      state.inArray--;
      return 'bracket';
    } else if (state.lhs && stream.peek() == '[' && stream.skipTo(']')) {
      stream.next(); //skip closing ]
      // array of objects has an extra open & close []
      if (stream.peek() == ']') stream.next();
      return 'atom';
    } else if (stream.peek() == '#') {
      stream.skipToEnd();
      return 'comment';
    } else if (stream.eatSpace()) {
      return null;
    } else if (state.lhs && stream.eatWhileIf((c) => c != '=' && c != ' ')) {
      return 'property';
    } else if (state.lhs && stream.peek() == '=') {
      stream.next();
      state.lhs = false;
      return null;
    } else if (!state.lhs && stream.match(_tomlDate) != null) {
      return 'atom'; //date
    } else if (!state.lhs && (stream.matchString('true') || stream.matchString('false'))) {
      return 'atom';
    } else if (!state.lhs && stream.peek() == '[') {
      state.inArray++;
      stream.next();
      return 'bracket';
    } else if (!state.lhs && stream.match(_tomlNumber) != null) {
      return 'number';
    } else if (!stream.eatSpace()) {
      stream.next();
    }
    return null;
  }
}

// ---- diff -----------------------------------------------------------------------------------------------------------

const Map<String, String> _diffNames = <String, String>{'+': 'inserted', '-': 'deleted', '@': 'meta'};
final RegExp _trailingSpace = RegExp(r'[\t ]+?$');

/// `diff`. It keeps no state: JavaScript's `true`.
class Diff extends StreamMode<bool> {
  const Diff();

  @override
  bool startState(int indentUnit) => true;

  @override
  bool copyState(bool state) => state;

  @override
  String? token(StringStream stream, bool state) {
    final twPos = stream.string.indexOf(_trailingSpace);

    if (!stream.sol() || twPos == 0) {
      stream.skipToEnd();
      final name = stream.string.isEmpty ? null : _diffNames[stream.string[0]];
      return name == null ? 'error' : 'error $name';
    }

    final tokenName = _diffNames[stream.peek()];
    if (tokenName == null) stream.skipToEnd();

    if (twPos == -1) {
      stream.skipToEnd();
    } else {
      stream.pos = twPos;
    }

    return tokenName;
  }
}

// ---- properties -----------------------------------------------------------------------------------------------------

class PropertiesState {
  String position = 'def'; // Current position, "def", "quote" or "comment"
  bool nextMultiline = false; // Is the next line multiline value
  bool inMultiline = false; // Is the current line a multiline value
  bool afterSection = false; // Did we just open a section
}

/// `properties`: what the pack reads `ini` and `properties` with.
class Properties extends StreamMode<PropertiesState> {
  const Properties();

  @override
  PropertiesState startState(int indentUnit) => PropertiesState();

  @override
  PropertiesState copyState(PropertiesState state) => PropertiesState()
    ..position = state.position
    ..nextMultiline = state.nextMultiline
    ..inMultiline = state.inMultiline
    ..afterSection = state.afterSection;

  @override
  String? token(StringStream stream, PropertiesState state) {
    final sol = stream.sol() || state.afterSection;
    final eol = stream.eol();

    state.afterSection = false;

    if (sol) {
      if (state.nextMultiline) {
        state.inMultiline = true;
        state.nextMultiline = false;
      } else {
        state.position = 'def';
      }
    }

    if (eol && !state.nextMultiline) {
      state.inMultiline = false;
      state.position = 'def';
    }

    if (sol) {
      while (stream.eatSpace()) {}
    }

    final ch = stream.next();

    if (sol && (ch == '#' || ch == '!' || ch == ';')) {
      state.position = 'comment';
      stream.skipToEnd();
      return 'comment';
    } else if (sol && ch == '[') {
      state.afterSection = true;
      stream.skipTo(']');
      stream.eat(']');
      return 'header';
    } else if (ch == '=' || ch == ':') {
      state.position = 'quote';
      return null;
    } else if (ch == '\\' && state.position == 'quote') {
      if (stream.eol()) {
        // Multiline value
        state.nextMultiline = true;
      }
    }

    return state.position;
  }
}

// ---- Lua ------------------------------------------------------------------------------------------------------------

RegExp _wordRE(List<String> words) => RegExp('^(?:${words.join('|')})\$', caseSensitive: false);

// long list of standard functions from lua manual
final RegExp _luaBuiltins = _wordRE(const <String>[
  '_G', '_VERSION', 'assert', 'collectgarbage', 'dofile', 'error', 'getfenv', 'getmetatable', 'ipairs', 'load', //
  'loadfile', 'loadstring', 'module', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget', 'rawset', 'require',
  'select', 'setfenv', 'setmetatable', 'tonumber', 'tostring', 'type', 'unpack', 'xpcall',
  'coroutine.create', 'coroutine.resume', 'coroutine.running', 'coroutine.status', 'coroutine.wrap', 'coroutine.yield',
  'debug.debug', 'debug.getfenv', 'debug.gethook', 'debug.getinfo', 'debug.getlocal', 'debug.getmetatable',
  'debug.getregistry', 'debug.getupvalue', 'debug.setfenv', 'debug.sethook', 'debug.setlocal', 'debug.setmetatable',
  'debug.setupvalue', 'debug.traceback',
  'close', 'flush', 'lines', 'read', 'seek', 'setvbuf', 'write',
  'io.close', 'io.flush', 'io.input', 'io.lines', 'io.open', 'io.output', 'io.popen', 'io.read', 'io.stderr', 'io.stdin',
  'io.stdout', 'io.tmpfile', 'io.type', 'io.write',
  'math.abs', 'math.acos', 'math.asin', 'math.atan', 'math.atan2', 'math.ceil', 'math.cos', 'math.cosh', 'math.deg',
  'math.exp', 'math.floor', 'math.fmod', 'math.frexp', 'math.huge', 'math.ldexp', 'math.log', 'math.log10', 'math.max',
  'math.min', 'math.modf', 'math.pi', 'math.pow', 'math.rad', 'math.random', 'math.randomseed', 'math.sin', 'math.sinh',
  'math.sqrt', 'math.tan', 'math.tanh',
  'os.clock', 'os.date', 'os.difftime', 'os.execute', 'os.exit', 'os.getenv', 'os.remove', 'os.rename', 'os.setlocale',
  'os.time', 'os.tmpname',
  'package.cpath', 'package.loaded', 'package.loaders', 'package.loadlib', 'package.path', 'package.preload',
  'package.seeall',
  'string.byte', 'string.char', 'string.dump', 'string.find', 'string.format', 'string.gmatch', 'string.gsub',
  'string.len', 'string.lower', 'string.match', 'string.rep', 'string.reverse', 'string.sub', 'string.upper',
  'table.concat', 'table.insert', 'table.maxn', 'table.remove', 'table.sort',
]);
final RegExp _luaKeywords = _wordRE(const <String>['and', 'break', 'elseif', 'false', 'nil', 'not', 'or', 'return', 'true', 'function', 'end', 'if', 'then', 'else', 'do', 'while', 'repeat', 'until', 'for', 'in', 'local']);

typedef LuaTokenizer = String? Function(StringStream stream, LuaState state);

class LuaState {
  LuaState(this.cur);

  LuaTokenizer cur;
}

final RegExp _bracketOrEquals = RegExp(r'[\[=]');
final RegExp _luaNumberRest = RegExp(r'[\w.%]');
final RegExp _luaWordStart = RegExp(r'[\w_]');
final RegExp _luaWordRest = RegExp(r'[\w\\\-_.]');

int _luaReadBracket(StringStream stream) {
  var level = 0;
  while (stream.eat('=') != null) {
    ++level;
  }
  stream.eat('[');
  return level;
}

String? _luaNormal(StringStream stream, LuaState state) {
  final ch = stream.next()!;
  if (ch == '-' && stream.eat('-') != null) {
    if (stream.eat('[') != null && _test(_bracketOrEquals, stream.peek())) return (state.cur = _luaBracketed(_luaReadBracket(stream), 'comment'))(stream, state);
    stream.skipToEnd();
    return 'comment';
  }
  if (ch == '"' || ch == "'") return (state.cur = _luaString(ch))(stream, state);
  if (ch == '[' && _test(_bracketOrEquals, stream.peek())) return (state.cur = _luaBracketed(_luaReadBracket(stream), 'string'))(stream, state);
  if (_d.hasMatch(ch)) {
    stream.eatWhile(_luaNumberRest);
    return 'number';
  }
  if (_luaWordStart.hasMatch(ch)) {
    stream.eatWhile(_luaWordRest);
    return 'variable';
  }
  return null;
}

LuaTokenizer _luaBracketed(int level, String style) => (stream, state) {
  int? curlev;
  for (;;) {
    final ch = stream.next();
    if (ch == null) break;
    if (curlev == null) {
      if (ch == ']') curlev = 0;
    } else if (ch == '=') {
      ++curlev;
    } else if (ch == ']' && curlev == level) {
      state.cur = _luaNormal;
      break;
    } else {
      curlev = null;
    }
  }
  return style;
};

LuaTokenizer _luaString(String quote) => (stream, state) {
  var escaped = false;
  for (;;) {
    final ch = stream.next();
    if (ch == null) break;
    if (ch == quote && !escaped) break;
    escaped = !escaped && ch == '\\';
  }
  if (!escaped) state.cur = _luaNormal;
  return 'string';
};

/// `lua`.
class Lua extends StreamMode<LuaState> {
  const Lua();

  @override
  LuaState startState(int indentUnit) => LuaState(_luaNormal);

  @override
  LuaState copyState(LuaState state) => LuaState(state.cur);

  @override
  String? token(StringStream stream, LuaState state) {
    if (stream.eatSpace()) return null;
    var style = state.cur(stream, state);
    final word = stream.current();
    if (style == 'variable') {
      if (_luaKeywords.hasMatch(word)) {
        style = 'keyword';
      } else if (_luaBuiltins.hasMatch(word)) {
        style = 'builtin';
      }
    }
    return style;
  }
}

// ---- Ruby -----------------------------------------------------------------------------------------------------------

const Set<String> _rubyKeywords = <String>{
  'alias', 'and', 'BEGIN', 'begin', 'break', 'case', 'class', 'def', 'defined?', 'do', 'else', //
  'elsif', 'END', 'end', 'ensure', 'false', 'for', 'if', 'in', 'module', 'next', 'not', 'or',
  'redo', 'rescue', 'retry', 'return', 'self', 'super', 'then', 'true', 'undef', 'unless',
  'until', 'when', 'while', 'yield', 'nil', 'raise', 'throw', 'catch', 'fail', 'loop', 'callcc',
  'caller', 'lambda', 'proc', 'public', 'protected', 'private', 'require', 'load',
  'require_relative', 'extend', 'autoload', '__END__', '__FILE__', '__LINE__', '__dir__',
};

const Set<String> _rubyIndentWords = <String>{'def', 'class', 'case', 'for', 'while', 'until', 'module', 'catch', 'loop', 'proc', 'begin'};
const Set<String> _rubyDedentWords = <String>{'end', 'until'};
const Map<String, String> _rubyOpening = <String, String>{'[': ']', '{': '}', '(': ')'};

class RubyContext {
  const RubyContext(this.prev, this.type, this.indented);

  final RubyContext? prev;
  final String? type;
  final int indented;
}

abstract class RubyTokenizer {
  const RubyTokenizer();

  String? read(StringStream stream, RubyState state);

  RubyTokenizer copy() => this;
}

class RubyState {
  RubyState(this.context);

  List<RubyTokenizer> tokenize = <RubyTokenizer>[const _RubyBase()];
  int indented = 0;
  RubyContext context;
  String? lastTok;
  bool varList = false;

  /// What the token just read was, for `token` to act on (the mode's `curPunc`).
  String? curPunc;
}

String? _rubyChain(RubyTokenizer newtok, StringStream stream, RubyState state) {
  state.tokenize.add(newtok);
  return newtok.read(stream, state);
}

final RegExp _rubyHeredoc = RegExp(r'''^<([-~])[\`\"\']?([a-zA-Z_?]\w*)[\`\"\']?(?:;|$)''');
final RegExp _rubyNumberRest = RegExp(r'^[\d_]*(?:\.[\d_]+)?(?:[eE][+\-]?[\d_]+)?');
final RegExp _rubyCharMeta = RegExp(r'^\\[CM]-');
final RegExp _rubyIvar = RegExp('^@?[a-zA-Z_¡-￿]');
final RegExp _rubyIdentStart = RegExp('[a-zA-Z_¡-￿]');
final RegExp _rubyIdentRest = RegExp('[\\w¡-￿]');
final RegExp _rubySymbolStart = RegExp('[a-zA-Z\$@_¡-￿]');
final RegExp _rubySymbolRest = RegExp('[\\w\$¡-￿]');
final RegExp _rubyBrackets = RegExp(r'[\(\)\[\]{}\\;]');
final RegExp _rubyOperator = RegExp(r'[=+\-\/*:\.^%<>~|]');
final RegExp _rubyDelim = RegExp(r'[^\w\s=]');

String? _rubyBase(StringStream stream, RubyState state) {
  if (stream.sol() && stream.matchString('=begin') && stream.eol()) {
    state.tokenize.add(const _RubyBlockComment());
    return 'comment';
  }
  if (stream.eatSpace()) return null;
  final ch = stream.next()!;
  if (ch == '`' || ch == "'" || ch == '"') {
    return _rubyChain(_RubyQuoted(ch, 'string', ch == '"' || ch == '`'), stream, state);
  } else if (ch == '/') {
    if (_rubyRegexpAhead(stream)) {
      return _rubyChain(_RubyQuoted(ch, 'string.special', true), stream, state);
    } else {
      return 'operator';
    }
  } else if (ch == '%') {
    var style = 'string', embed = true;
    if (stream.eat('s') != null) {
      style = 'atom';
    } else if (stream.eatMatch(RegExp('[WQ]')) != null) {
      style = 'string';
    } else if (stream.eatMatch(RegExp('[r]')) != null) {
      style = 'string.special';
    } else if (stream.eatMatch(RegExp('[wxq]')) != null) {
      style = 'string';
      embed = false;
    }
    var delim = stream.eatMatch(_rubyDelim);
    if (delim == null) return 'operator';
    delim = _rubyOpening[delim] ?? delim;
    return _rubyChain(_RubyQuoted(delim, style, embed, true), stream, state);
  } else if (ch == '#') {
    stream.skipToEnd();
    return 'comment';
  }
  if (ch == '<') {
    final m = stream.match(_rubyHeredoc);
    if (m != null) return _rubyChain(_RubyHereDoc(m.group(2)!, true), stream, state);
  }
  if (ch == '0') {
    if (stream.eat('x') != null) {
      stream.eatWhile(RegExp(r'[\da-fA-F]'));
    } else if (stream.eat('b') != null) {
      stream.eatWhile(RegExp('[01]'));
    } else if (stream.eat('.') != null) {
      // `stream.eat(/[\d_]*(?:[eE][+\-]?[\d_]+)?/)`: a pattern that matches nothing at all matches any one
      // character, so one character is eaten whatever it is.
      stream.next();
    } else {
      stream.eatWhile(RegExp('[0-7]'));
    }
    return 'number';
  } else if (_d.hasMatch(ch)) {
    stream.match(_rubyNumberRest);
    return 'number';
  } else if (ch == '?') {
    while (stream.match(_rubyCharMeta) != null) {}
    if (stream.eat('\\') != null) {
      stream.eatWhile(_w);
    } else {
      stream.next();
    }
    return 'string';
  } else if (ch == ':') {
    if (stream.eat("'") != null) return _rubyChain(const _RubyQuoted("'", 'atom', false), stream, state);
    if (stream.eat('"') != null) return _rubyChain(const _RubyQuoted('"', 'atom', true), stream, state);

    // :> :>> :< :<< are valid symbols
    if (stream.eatMatch(RegExp(r'[\<\>]')) != null) {
      stream.eatMatch(RegExp(r'[\<\>]'));
      return 'atom';
    }

    // :+ :- :/ :* :| :& :! are valid symbols
    if (stream.eatMatch(RegExp(r'[\+\-\*\/\&\|\:\!]')) != null) return 'atom';

    // Symbols can't start by a digit
    if (stream.eatMatch(_rubySymbolStart) != null) {
      stream.eatWhile(_rubySymbolRest);
      // Only one ? ! = is allowed and only as the last character
      stream.eatMatch(RegExp(r'[\?\!\=]'));
      return 'atom';
    }
    return 'operator';
  } else if (ch == '@' && stream.match(_rubyIvar) != null) {
    stream.eat('@');
    stream.eatWhile(_rubyIdentRest);
    return 'propertyName';
  } else if (ch == r'$') {
    if (stream.eatMatch(RegExp('[a-zA-Z_]')) != null) {
      stream.eatWhile(_w);
    } else if (stream.eatMatch(_d) != null) {
      stream.eatMatch(_d);
    } else {
      stream.next(); // Must be a special global like $: or $!
    }
    return 'variableName.special';
  } else if (_rubyIdentStart.hasMatch(ch)) {
    stream.eatWhile(_rubyIdentRest);
    stream.eatMatch(RegExp(r'[\?\!]'));
    if (stream.eat(':') != null) return 'atom';
    return 'variable';
  } else if (ch == '|' && (state.varList || state.lastTok == '{' || state.lastTok == 'do')) {
    state.curPunc = '|';
    return null;
  } else if (_rubyBrackets.hasMatch(ch)) {
    state.curPunc = ch;
    return null;
  } else if (ch == '-' && stream.eat('>') != null) {
    return 'operator';
  } else if (_rubyOperator.hasMatch(ch)) {
    final more = stream.eatWhile(_rubyOperator);
    if (ch == '.' && !more) state.curPunc = '.';
    return 'operator';
  } else {
    return null;
  }
}

bool _rubyRegexpAhead(StringStream stream) {
  final start = stream.pos;
  var depth = 0, found = false, escaped = false;
  for (;;) {
    final next = stream.next();
    if (next == null) break;
    if (!escaped) {
      if ('[{('.contains(next)) {
        depth++;
      } else if (']})'.contains(next)) {
        depth--;
        if (depth < 0) break;
      } else if (next == '/' && depth == 0) {
        found = true;
        break;
      }
      escaped = next == '\\';
    } else {
      escaped = false;
    }
  }
  stream.backUp(stream.pos - start);
  return found;
}

class _RubyBase extends RubyTokenizer {
  const _RubyBase();

  @override
  String? read(StringStream stream, RubyState state) => _rubyBase(stream, state);
}

class _RubyBaseUntilBrace extends RubyTokenizer {
  const _RubyBaseUntilBrace([this.depth = 1]);

  final int depth;

  @override
  String? read(StringStream stream, RubyState state) {
    if (stream.peek() == '}') {
      if (depth == 1) {
        state.tokenize.removeLast();
        return state.tokenize.last.read(stream, state);
      } else {
        state.tokenize[state.tokenize.length - 1] = _RubyBaseUntilBrace(depth - 1);
      }
    } else if (stream.peek() == '{') {
      state.tokenize[state.tokenize.length - 1] = _RubyBaseUntilBrace(depth + 1);
    }
    return _rubyBase(stream, state);
  }
}

class _RubyBaseOnce extends RubyTokenizer {
  _RubyBaseOnce([this.alreadyCalled = false]);

  bool alreadyCalled;

  @override
  RubyTokenizer copy() => _RubyBaseOnce(alreadyCalled);

  @override
  String? read(StringStream stream, RubyState state) {
    if (alreadyCalled) {
      state.tokenize.removeLast();
      return state.tokenize.last.read(stream, state);
    }
    alreadyCalled = true;
    return _rubyBase(stream, state);
  }
}

final RegExp _atOrDollar = RegExp(r'[@\$]');

class _RubyQuoted extends RubyTokenizer {
  const _RubyQuoted(this.quote, this.style, this.embed, [this.unescaped = false]);

  final String quote, style;
  final bool embed, unescaped;

  @override
  String? read(StringStream stream, RubyState state) {
    var escaped = false;

    if (state.context.type == 'read-quoted-paused') {
      state.context = state.context.prev!;
      stream.eat('}');
    }

    for (;;) {
      final ch = stream.next();
      if (ch == null) break;
      if (ch == quote && (unescaped || !escaped)) {
        state.tokenize.removeLast();
        break;
      }
      if (embed && ch == '#' && !escaped) {
        if (stream.eat('{') != null) {
          // The paused context has no `indented`: JavaScript's `undefined`, which nothing is less than.
          if (quote == '}') state.context = RubyContext(state.context, 'read-quoted-paused', 0x3fffffff);
          state.tokenize.add(const _RubyBaseUntilBrace());
          break;
        } else if (_test(_atOrDollar, stream.peek())) {
          state.tokenize.add(_RubyBaseOnce());
          break;
        }
      }
      escaped = !escaped && ch == '\\';
    }
    return style;
  }
}

class _RubyHereDoc extends RubyTokenizer {
  const _RubyHereDoc(this.phrase, this.mayIndent);

  final String phrase;
  final bool mayIndent;

  @override
  String? read(StringStream stream, RubyState state) {
    if (mayIndent) stream.eatSpace();
    if (stream.matchString(phrase)) {
      state.tokenize.removeLast();
    } else {
      stream.skipToEnd();
    }
    return 'string';
  }
}

class _RubyBlockComment extends RubyTokenizer {
  const _RubyBlockComment();

  @override
  String? read(StringStream stream, RubyState state) {
    if (stream.sol() && stream.matchString('=end') && stream.eol()) state.tokenize.removeLast();
    stream.skipToEnd();
    return 'comment';
  }
}

final RegExp _upperStart = RegExp('^[A-Z]');
final RegExp _openBracket = RegExp(r'[\(\[\{]');
final RegExp _closeBracket = RegExp(r'[\)\]\}]');

/// `ruby`.
class Ruby extends StreamMode<RubyState> {
  const Ruby();

  @override
  RubyState startState(int indentUnit) => RubyState(RubyContext(null, 'top', -indentUnit));

  @override
  RubyState copyState(RubyState state) => RubyState(state.context)
    ..tokenize = <RubyTokenizer>[for (final tokenize in state.tokenize) tokenize.copy()]
    ..indented = state.indented
    ..lastTok = state.lastTok
    ..varList = state.varList;

  @override
  String? token(StringStream stream, RubyState state) {
    state.curPunc = null;
    if (stream.sol()) state.indented = stream.indentation();
    var style = state.tokenize.last.read(stream, state);
    String? kwtype;
    final curPunc = state.curPunc;
    var thisTok = curPunc;
    if (style == 'variable') {
      final word = stream.current();
      style = state.lastTok == '.'
          ? 'property'
          : _rubyKeywords.contains(word)
          ? 'keyword'
          : _upperStart.hasMatch(word)
          ? 'tag'
          : (state.lastTok == 'def' || state.lastTok == 'class' || state.varList)
          ? 'def'
          : 'variable';
      if (style == 'keyword') {
        thisTok = word;
        if (_rubyIndentWords.contains(word)) {
          kwtype = 'indent';
        } else if (_rubyDedentWords.contains(word)) {
          kwtype = 'dedent';
        } else if ((word == 'if' || word == 'unless') && stream.column() == stream.indentation()) {
          kwtype = 'indent';
        } else if (word == 'do' && state.context.indented < state.indented) {
          kwtype = 'indent';
        }
      }
    }
    if (curPunc != null || (style != null && style != 'comment')) state.lastTok = thisTok;
    if (curPunc == '|') state.varList = !state.varList;

    if (kwtype == 'indent' || (curPunc != null && _openBracket.hasMatch(curPunc))) {
      state.context = RubyContext(state.context, curPunc ?? style, state.indented);
    } else if ((kwtype == 'dedent' || (curPunc != null && _closeBracket.hasMatch(curPunc))) && state.context.prev != null) {
      state.context = state.context.prev!;
    }
    return style;
  }
}
