/// One of CodeMirror's older modes run as it is written: its JavaScript, by `js/js.dart`.
///
/// The pack reads a hundred and ten languages with @codemirror/legacy-modes. The commonest are ported to Dart by
/// hand (`clike.dart`, `modes.dart`) and read at Dart's speed; every other one is read by its own `token`
/// function, from the syntax tree tool/code_modes.mjs wrote (`modes.g.dart`), so what it colours is what
/// CodeMirror colours and a language costs a line to add.
///
/// A mode's file is unpacked, compiled and run the first time a block asks for one of its languages, once:
/// a few milliseconds, off the first frame that shows such a block and no other.
library;

import 'dart:convert';
import 'dart:io';

import 'js/js.dart';
import 'modes.g.dart';
import 'stream_language.dart';
import 'string_stream.dart';

final Map<String, Exports> _modules = <String, Exports>{};

/// What the mode file `file` exports, the file run if it has not been.
Exports _load(String file) {
  final known = _modules[file];
  if (known != null) return known;
  final packed = modeFiles[file];
  if (packed == null) throw StateError('No mode file $file');
  JsMode.filesRun++;
  // A file builds its tables as it is run: as many turns as it needs.
  refuel(0x3fffffff);
  final tree = jsonDecode(utf8.decode(gzip.decode(base64.decode(packed)))) as Map<String, dynamic>;
  return _modules[file] = runModule(tree, _load);
}

/// The mode `name` of the file `file`, for the language `language`; with `call`, `name` is a function that makes
/// the mode of `{}`. A file that could not be run (none is known: test/editor/code/js_mode_test.dart loads every
/// one) gives a mode that colours nothing, and the language is listed in [JsMode.unloaded].
StreamMode<Object?> loadJsMode(String language, String file, String name, {bool call = false}) {
  try {
    return JsMode(file, name, call: call, resumable: !_keepMoreThanTheirState.contains(language));
    // Whatever went wrong, in the mode's JavaScript or in the reading of it, a block is still drawn.
    // ignore: avoid_catches_without_on_clauses
  } catch (error) {
    JsMode.unloaded[language] = error;
    return const _NoMode();
  }
}

/// The modes that keep something of what they have read where a state does not hold it, so that a line's kept
/// state is not enough to read on from: a block of one of these that changed is read again from its first line.
/// (CodeMirror reads on from a kept state all the same, and colours such a block wrongly until it is read whole
/// again.) Elm's keeps how deep a nested comment is in a variable of the function that is its state, and
/// counts it down as the comment's end is read, in every copy of the state at once. The message-chart modes
/// keep "in an attribute list" on the mode itself, for every block there is: read again from the top they are
/// still what they were on the web, a reading that depends on what was read before.
///
/// test/editor/code/resume_test.dart found them: each of the others, changed eighty times by chance, is the
/// same taken up from the changed line as read whole.
const Set<String> _keepMoreThanTheirState = <String>{'Elm', 'MscGen', 'Xù', 'MsGenny'};

/// The mode of a language whose own could not be run: nothing is coloured.
class _NoMode extends StreamMode<Object?> {
  const _NoMode();

  @override
  Object? startState(int indentUnit) => null;

  @override
  Object? copyState(Object? state) => state;

  @override
  String? token(StringStream stream, Object? state) {
    stream.skipToEnd();
    return null;
  }
}

final RegExp _spaceChar = RegExp('[\\s ]');

/// The line as a mode sees it: CodeMirror's `StringStream`, its methods as JavaScript has them (`next` at the
/// end of the line is `undefined`, `match` answers the groups).
class _StreamHost extends JsObject {
  /// The line being read. One is given before a mode's `token` is first called.
  StringStream? _line;

  StringStream get stream => _line!;

  @override
  Object? get(String key) {
    final method = _methods[key];
    if (method != null) return method;
    switch (key) {
      case 'pos':
        return stream.pos;
      case 'start':
        return stream.start;
      case 'string':
        return stream.string;
      case 'indentUnit':
        return stream.indentUnit;
      case 'tabSize':
        return stream.tabSize;
    }
    return super.get(key);
  }

  @override
  void set(String key, Object? value) {
    switch (key) {
      case 'pos':
        stream.pos = toNum(value).toInt();
      case 'start':
        stream.start = toNum(value).toInt();
      default:
        super.set(key, value);
    }
  }

  static StringStream _of(Object? self) => (self! as _StreamHost).stream;

  /// `eat(match)`: the next character if it is the string, matches the pattern, or the function says so.
  static bool _eat(StringStream s, Object? match) {
    if (s.pos >= s.string.length) {
      // `charAt` past the end is the empty string, which only the empty string equals.
      return match is String && match.isEmpty;
    }
    final ch = s.string[s.pos];
    final bool ok;
    if (match is String) {
      ok = ch == match;
    } else if (match is JsRegExp) {
      ok = match.test(ch);
    } else if (match is JsCallable) {
      ok = truthy(match.call(undefined, <Object?>[ch]));
    } else {
      throw JsThrow('match is not a function');
    }
    if (ok) s.pos++;
    return ok;
  }

  static final Map<String, Native> _methods = <String, Native>{
    'eol': Native((self, args) => _of(self).eol()),
    'sol': Native((self, args) => _of(self).sol()),
    'peek': Native((self, args) => _of(self).peek() ?? undefined),
    'next': Native((self, args) => _of(self).next() ?? undefined),
    'eat': Native((self, args) {
      final s = _of(self);
      final at = s.pos;
      if (!_eat(s, args.isEmpty ? undefined : args[0])) return undefined;
      return at < s.string.length ? s.string[at] : '';
    }),
    'eatWhile': Native((self, args) {
      final s = _of(self), match = args.isEmpty ? undefined : args[0];
      final start = s.pos;
      // `while (this.eat(match)) {}`: an empty string eaten at the end of the line is falsy, and ends it.
      while (s.pos < s.string.length && _eat(s, match)) {}
      return s.pos > start;
    }),
    'eatSpace': Native((self, args) {
      final s = _of(self);
      final start = s.pos;
      while (s.pos < s.string.length && _spaceChar.hasMatch(s.string[s.pos])) {
        s.pos++;
      }
      return s.pos > start;
    }),
    'skipToEnd': Native((self, args) {
      _of(self).skipToEnd();
      return undefined;
    }),
    'skipTo': Native((self, args) {
      final s = _of(self);
      final found = s.pos > s.string.length ? -1 : s.string.indexOf(toStr(args.isEmpty ? undefined : args[0]), s.pos);
      if (found < 0) return undefined;
      s.pos = found;
      return true;
    }),
    'backUp': Native((self, args) {
      _of(self).pos -= toNum(args.isEmpty ? undefined : args[0]).toInt();
      return undefined;
    }),
    'column': Native((self, args) => _of(self).column()),
    'indentation': Native((self, args) => _of(self).indentation()),
    'current': Native((self, args) {
      final s = _of(self);
      final end = s.pos > s.string.length ? s.string.length : s.pos;
      return s.start < end ? s.string.substring(s.start < 0 ? 0 : s.start, end) : '';
    }),
    'match': Native((self, args) {
      final s = _of(self);
      final pattern = args.isEmpty ? undefined : args[0];
      final consume = args.length < 2 || !identical(args[1], false);
      if (pattern is String) {
        final insensitive = args.length > 2 && truthy(args[2]);
        final end = s.pos + pattern.length > s.string.length ? s.string.length : s.pos + pattern.length;
        final there = s.pos > s.string.length ? '' : s.string.substring(s.pos, end);
        if (insensitive ? there.toLowerCase() != pattern.toLowerCase() : there != pattern) return null;
        if (consume) s.pos += pattern.length;
        return true;
      }
      final rest = s.pos == 0 ? s.string : (s.pos >= s.string.length ? '' : s.string.substring(s.pos));
      if (pattern is JsRegExp && !pattern.global && !pattern.sticky) {
        final m = pattern.re.firstMatch(rest);
        if (m == null || m.start > 0) return null;
        if (consume) s.pos += m.end;
        return JsRegExp.matchArray(m, rest);
      }
      // `this.string.slice(this.pos).match(pattern)`, then a match with an `index` above nothing is no match.
      // With the `g` flag a match has no `index`, and the first match anywhere in the rest of the line counts,
      // as it does there; and what is no pattern (Dylan's mode hands over a list of them) is made one of.
      final found = stringMatch(rest, pattern);
      if (found == null) return null;
      final index = found.get('index');
      if (index is num && index > 0) return null;
      if (consume) s.pos += toStr(found.list[0]).length;
      return found;
    }),
  };
}

/// What `StreamLanguage` copies a state with when the mode has no way of its own: a new object with the old
/// one's properties, each array a copy.
Object? _defaultCopy(Object? state) {
  if (state != null && state is! JsObject) return state;
  if (state is JsCallable) return state;
  final copy = JsObject();
  if (state is JsObject) {
    final inherits = state.proto != null;
    for (final key in inherits ? forInKeys(state) : state.ownKeys()) {
      final value = state.get(key);
      copy.props[key] = value is JsArray ? JsArray(List<Object?>.of(value.list)) : value;
    }
  }
  return copy;
}

/// A mode of the pack, run from its JavaScript.
class JsMode extends StreamMode<Object?> {
  /// The mode `name` of the file `file` exports: an object, or with `call` a function that makes one of `{}`.
  factory JsMode(String file, String name, {bool call = false, bool resumable = true}) {
    var spec = _load(file)[name];
    if (call) spec = (spec! as JsCallable).call(undefined, <Object?>[JsObject()]);
    return JsMode._(spec! as JsObject, resumable);
  }

  JsMode._(JsObject spec, this.resumable)
    : _token = spec.get('token')! as JsCallable,
      _blankLine = spec.get('blankLine'),
      _startState = spec.get('startState'),
      _copyState = spec.get('copyState') {
    // `fullParser`: what the mode's functions are called on.
    for (final key in const <String>['name', 'token', 'blankLine', 'startState', 'copyState', 'indent', 'languageData', 'tokenTable', 'mergeTokens']) {
      if (spec.has(key)) _self.props[key] = spec.get(key);
    }
  }

  @override
  final bool resumable;

  final JsObject _self = JsObject();
  final JsCallable _token;
  final Object? _blankLine, _startState, _copyState;
  final _StreamHost _host = _StreamHost();

  /// The lines a mode's own JavaScript failed on, where CodeMirror would have stopped colouring the block, and
  /// the last failure.
  static int failed = 0;
  static Object? lastFailure;

  /// The mode files unpacked and run: each once, when a block first asks for one of its languages.
  static int filesRun = 0;

  /// The languages whose mode could not be run, with why.
  static final Map<String, Object> unloaded = <String, Object>{};

  @override
  Object? startState(int indentUnit) {
    final start = _startState;
    refuel();
    return start is JsCallable ? start.call(_self, <Object?>[indentUnit]) : true;
  }

  @override
  Object? copyState(Object? state) {
    final copy = _copyState;
    try {
      refuel();
      return copy is JsCallable ? copy.call(_self, <Object?>[state]) : _defaultCopy(state);
      // ignore: avoid_catches_without_on_clauses
    } catch (thrown) {
      failed++;
      lastFailure = thrown;
      return _defaultCopy(state);
    }
  }

  @override
  String? token(StringStream stream, Object? state) {
    final host = _host;
    if (!identical(host._line, stream)) {
      host._line = stream;
      if (host.props.isNotEmpty) host.props.clear();
    }
    try {
      refuel();
      final style = _token.call(_self, <Object?>[host, state]);
      return style is String && style.isNotEmpty ? style : null;
      // The mode threw, or the reading of it did. CodeMirror's parse would end there; here the rest of the line
      // goes uncoloured and the next is read.
      // ignore: avoid_catches_without_on_clauses
    } catch (thrown) {
      failed++;
      lastFailure = thrown;
      stream.skipToEnd();
      return null;
    }
  }

  @override
  void blankLine(Object? state, int indentUnit) {
    final blank = _blankLine;
    if (blank is! JsCallable) return;
    try {
      refuel();
      blank.call(_self, <Object?>[state, indentUnit]);
      // ignore: avoid_catches_without_on_clauses
    } catch (thrown) {
      failed++;
      lastFailure = thrown;
    }
  }
}
