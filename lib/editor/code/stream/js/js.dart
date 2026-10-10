/// Enough of JavaScript to run CodeMirror's older modes as they are written.
///
/// The web editor's language pack reads a hundred and ten of its languages with @codemirror/legacy-modes: each
/// a `token(stream, state)` function in the plain JavaScript of CodeMirror 5, ten to a thousand lines of it,
/// full of the quirks a mode's colours come from. Seven are ported to Dart by hand (`../clike.dart`,
/// `../modes.dart`); porting the rest by hand would be months, and each port a chance to differ. So the rest are
/// run: tool/code_modes.mjs writes each mode's syntax tree (`../modes.g.dart`), this compiles a tree to Dart
/// closures the first time a block asks for its language, and the mode's own `token` reads the block.
///
/// What is here is what those files use and no more: functions and closures, objects with prototypes, arrays,
/// strings, numbers, regular expressions (Dart's are JavaScript's), `var` and `let`, the usual statements,
/// `new`, `this`, `arguments`, one `class`. What is not, because no mode uses it: arrow functions, template
/// strings, destructuring, generators, getters, `for…of`, `with`, `eval`. `Function(…)`, which Pug's mode calls
/// to ask whether an attribute's value is whole JavaScript, throws: it would take a JavaScript parser.
///
/// Values: a JavaScript string is a Dart [String], a number a [num], a boolean a [bool], `null` is `null`,
/// `undefined` is [undefined], and everything else is a [JsObject].
library;

part 'builtins.dart';
part 'compile.dart';

/// The turns of loops left to whoever is running: a mode's `token` is given two million ([refuel]), which none
/// comes near on a line it can read, so that a mode that would go round for ever on a line it cannot is stopped
/// (it throws, and the line goes uncoloured) and the page is not.
int _fuel = 0x3fffffff;

void refuel([int turns = 2000000]) => _fuel = turns;

Never _spent() => throw _error('RangeError', 'A mode ran too long on one token');

/// JavaScript's `undefined`.
final class Undefined {
  const Undefined._();

  @override
  String toString() => 'undefined';
}

const Undefined undefined = Undefined._();

/// What a JavaScript `throw` throws, and what the errors JavaScript itself would raise are raised as.
class JsThrow implements Exception {
  JsThrow(this.value);

  final Object? value;

  @override
  String toString() => 'JsThrow: ${toStr(value is JsObject && (value! as JsObject).hasOwn('message') ? (value! as JsObject).get('message') : value)}';
}

JsThrow _error(String kind, String message) => JsThrow(
  JsObject()
    ..props['name'] = kind
    ..props['message'] = message,
);

Never _typeError(String message) => throw _error('TypeError', message);

/// Whether `key` is written as an array's index is: `0`, `12`, not `01` or `1.0`.
int? _indexOf(String key) {
  final length = key.length;
  if (length == 0 || length > 9) return null;
  final first = key.codeUnitAt(0);
  if (first < 48 || first > 57 || (first == 48 && length > 1)) return null;
  var n = first - 48;
  for (var i = 1; i < length; i++) {
    final c = key.codeUnitAt(i);
    if (c < 48 || c > 57) return null;
    n = n * 10 + c - 48;
  }
  return n;
}

/// An object: its own properties in the order they were made, and the object it inherits from.
class JsObject {
  JsObject([this.proto]);

  JsObject? proto;
  final Map<String, Object?> props = <String, Object?>{};

  /// Whether `for…in` lists what this holds when it is another object's prototype: a class's methods are not
  /// listed, what is assigned to `F.prototype` is.
  bool listed = true;

  Object? get(String key) {
    JsObject? o = this;
    while (o != null) {
      final v = o.props[key];
      if (v != null || o.props.containsKey(key)) return v;
      o = o.proto;
    }
    return _objectProto[key] ?? undefined;
  }

  void set(String key, Object? value) => props[key] = value;

  bool hasOwn(String key) => props.containsKey(key);

  bool has(String key) {
    JsObject? o = this;
    while (o != null) {
      if (o.hasOwn(key)) return true;
      o = o.proto;
    }
    return _objectProto.containsKey(key);
  }

  void delete(String key) => props.remove(key);

  /// The object's own keys as JavaScript lists them: the ones that are whole numbers first, ascending, then the
  /// rest as they were made.
  List<String> ownKeys() {
    final keys = props.keys.toList();
    var numbered = false;
    for (final key in keys) {
      if (_indexOf(key) != null) {
        numbered = true;
        break;
      }
    }
    if (!numbered) return keys;
    final indices = <String>[
      for (final key in keys)
        if (_indexOf(key) != null) key,
    ]..sort((a, b) => _indexOf(a)! - _indexOf(b)!);
    return <String>[
      ...indices,
      for (final key in keys)
        if (_indexOf(key) == null) key,
    ];
  }
}

/// An array. What a match of a regular expression is, too: the groups, with `index` and `input` beside them.
class JsArray extends JsObject {
  JsArray(this.list);

  /// Growable.
  final List<Object?> list;

  @override
  Object? get(String key) {
    if (key == 'length') return list.length;
    final i = _indexOf(key);
    if (i != null) return i < list.length ? list[i] : undefined;
    final v = props[key];
    if (v != null || props.containsKey(key)) return v;
    return _arrayProto[key] ?? _objectProto[key] ?? undefined;
  }

  @override
  void set(String key, Object? value) {
    if (key == 'length') {
      final n = toNum(value).toInt();
      if (n < list.length) {
        list.length = n;
      } else {
        while (list.length < n) {
          list.add(undefined);
        }
      }
      return;
    }
    final i = _indexOf(key);
    if (i != null) {
      setAt(i, value);
    } else {
      props[key] = value;
    }
  }

  void setAt(int i, Object? value) {
    while (list.length <= i) {
      list.add(undefined);
    }
    list[i] = value;
  }

  @override
  bool hasOwn(String key) {
    final i = _indexOf(key);
    return i != null ? i < list.length : key == 'length' || props.containsKey(key);
  }

  @override
  bool has(String key) => hasOwn(key) || _arrayProto.containsKey(key) || _objectProto.containsKey(key);

  @override
  void delete(String key) {
    final i = _indexOf(key);
    if (i != null) {
      if (i < list.length) list[i] = undefined;
    } else {
      props.remove(key);
    }
  }

  @override
  List<String> ownKeys() => <String>[for (var i = 0; i < list.length; i++) '$i', ...props.keys];
}

/// Something that can be called: a function of a mode's ([Closure]) or one of JavaScript's own ([Native]).
abstract class JsCallable extends JsObject {
  Object? call(Object? self, List<Object?> args);

  /// `new F(…)`.
  Object? construct(List<Object?> args) {
    final prototype = get('prototype');
    final made = JsObject(prototype is JsObject ? prototype : null);
    final answer = call(made, args);
    return answer is JsObject ? answer : made;
  }

  @override
  Object? get(String key) {
    final v = props[key];
    if (v != null || props.containsKey(key)) return v;
    if (key == 'prototype') return props[key] = JsObject();
    return _functionProto[key] ?? _objectProto[key] ?? undefined;
  }

  @override
  bool has(String key) => hasOwn(key) || key == 'prototype' || _functionProto.containsKey(key) || _objectProto.containsKey(key);
}

/// One of JavaScript's own functions, in Dart.
class Native extends JsCallable {
  Native(this.fn, {this.make, this.isA});

  final Object? Function(Object? self, List<Object?> args) fn;

  /// What `new` makes of it, where that is not what calling it gives.
  final Object? Function(List<Object?> args)? make;

  /// `x instanceof` this.
  final bool Function(Object? value)? isA;

  @override
  Object? call(Object? self, List<Object?> args) => fn(self, args);

  @override
  Object? construct(List<Object?> args) => make != null ? make!(args) : fn(undefined, args);
}

final Map<String, RegExp> _compiled = <String, RegExp>{};

/// A regular expression. Dart's are JavaScript's (the same syntax, the same engine in the Dart VM), so the
/// pattern is handed over as written; what is kept here is what JavaScript keeps beside it: `lastIndex`, which a
/// pattern with the `g` flag matches from and moves.
class JsRegExp extends JsObject {
  JsRegExp(this.source, this.flags)
    : global = flags.contains('g'),
      ignoreCase = flags.contains('i'),
      multiline = flags.contains('m'),
      sticky = flags.contains('y'),
      unicode = flags.contains('u'),
      dotAll = flags.contains('s');

  final String source, flags;
  final bool global, ignoreCase, multiline, sticky, unicode, dotAll;
  int lastIndex = 0;

  RegExp? _re;

  RegExp get re {
    final made = _re;
    if (made != null) return made;
    final key = '$flags/$source';
    final known = _compiled[key];
    if (known != null) return _re = known;
    try {
      if (_compiled.length > 4000) _compiled.clear();
      return _re = _compiled[key] = RegExp(source, caseSensitive: !ignoreCase, multiLine: multiline, unicode: unicode, dotAll: dotAll);
    } on FormatException catch (e) {
      throw _error('SyntaxError', 'Invalid regular expression: /$source/: ${e.message}');
    }
  }

  /// `exec`: the first match in `s` (from `lastIndex` on with the `g` flag, which is then moved past it), as an
  /// array of its groups, or null.
  JsArray? exec(String s) {
    if (!global && !sticky) {
      final m = re.firstMatch(s);
      return m == null ? null : matchArray(m, s);
    }
    if (lastIndex > s.length) {
      lastIndex = 0;
      return null;
    }
    final RegExpMatch? m;
    if (sticky) {
      m = re.matchAsPrefix(s, lastIndex) as RegExpMatch?;
    } else {
      final found = re.allMatches(s, lastIndex).iterator;
      m = found.moveNext() ? found.current : null;
    }
    if (m == null) {
      lastIndex = 0;
      return null;
    }
    lastIndex = m.end;
    return matchArray(m, s);
  }

  /// `test`, without the array where nothing needs it.
  bool test(String s) => !global && !sticky ? re.hasMatch(s) : exec(s) != null;

  static JsArray matchArray(RegExpMatch m, String s) {
    final groups = <Object?>[for (var g = 0; g <= m.groupCount; g++) m.group(g) ?? undefined];
    return JsArray(groups)
      ..props['index'] = m.start
      ..props['input'] = s;
  }

  @override
  Object? get(String key) {
    switch (key) {
      case 'source':
        return source;
      case 'flags':
        return flags;
      case 'lastIndex':
        return lastIndex;
      case 'global':
        return global;
      case 'ignoreCase':
        return ignoreCase;
      case 'multiline':
        return multiline;
      case 'sticky':
        return sticky;
      case 'unicode':
        return unicode;
    }
    final v = props[key];
    if (v != null || props.containsKey(key)) return v;
    return _regExpProto[key] ?? _objectProto[key] ?? undefined;
  }

  @override
  void set(String key, Object? value) {
    if (key == 'lastIndex') {
      lastIndex = toNum(value).toInt();
    } else {
      props[key] = value;
    }
  }
}

// ---- what JavaScript makes of a value --------------------------------------------------------------------------------

bool truthy(Object? v) {
  if (v is bool) return v;
  if (v == null) return false;
  if (v is String) return v.isNotEmpty;
  if (v is num) return v != 0 && v == v;
  return !identical(v, undefined);
}

final RegExp _hex = RegExp(r'^0[xX][0-9a-fA-F]+$');

num toNum(Object? v) {
  if (v is num) return v;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return 0;
    if (_hex.hasMatch(s)) return int.parse(s.substring(2), radix: 16);
    return num.tryParse(s) ?? double.nan;
  }
  if (v is bool) return v ? 1 : 0;
  if (v == null) return 0;
  if (v is JsArray) return toNum(toStr(v));
  return double.nan;
}

/// A number written as JavaScript writes it: `2`, not `2.0`.
String _numToStr(num n) {
  if (n is int) return n.toString();
  if (n.isNaN) return 'NaN';
  if (n.isInfinite) return n > 0 ? 'Infinity' : '-Infinity';
  if (n == n.truncateToDouble() && n.abs() < 1e21) return n.toInt().toString();
  return n.toString();
}

String toStr(Object? v) {
  if (v is String) return v;
  if (v is num) return _numToStr(v);
  if (v is bool) return v ? 'true' : 'false';
  if (v == null) return 'null';
  if (identical(v, undefined)) return 'undefined';
  if (v is JsArray) return v.list.map((item) => item == null || identical(item, undefined) ? '' : toStr(item)).join(',');
  if (v is JsRegExp) return '/${v.source}/${v.flags}';
  if (v is JsCallable) return 'function () { [code] }';
  if (v is JsObject && v.hasOwn('message')) return '${toStr(v.get('name'))}: ${toStr(v.get('message'))}';
  return '[object Object]';
}

String typeOf(Object? v) {
  if (v is String) return 'string';
  if (v is num) return 'number';
  if (v is bool) return 'boolean';
  if (identical(v, undefined)) return 'undefined';
  if (v is JsCallable) return 'function';
  return 'object';
}

bool strictEquals(Object? a, Object? b) {
  if (a is String) return b is String && a == b;
  if (a is num) return b is num && a == b;
  if (a is bool) return b is bool && a == b;
  return identical(a, b);
}

bool looseEquals(Object? a, Object? b) {
  if (a is String && b is String) return a == b;
  if (a == null || identical(a, undefined)) return b == null || identical(b, undefined);
  if (b == null || identical(b, undefined)) return false;
  if (a is num && b is num) return a == b;
  if (a is bool && b is bool) return a == b;
  if (a is JsObject && b is JsObject) return identical(a, b);
  if (a is bool) return looseEquals(a ? 1 : 0, b);
  if (b is bool) return looseEquals(a, b ? 1 : 0);
  // An object against a string or a number is compared as its string.
  if (a is JsObject) return looseEquals(toStr(a), b);
  if (b is JsObject) return looseEquals(a, toStr(b));
  return toNum(a) == toNum(b);
}

Object? _add(Object? a, Object? b) {
  if (a is num && b is num) return a + b;
  if (a is String) return b is String ? a + b : a + toStr(b);
  if (b is String) return toStr(a) + b;
  if (a is JsObject || b is JsObject) return toStr(a) + toStr(b);
  return toNum(a) + toNum(b);
}

/// `a < b` and its like: -1, 0 or 1, or null where JavaScript answers false whichever way it is asked (a NaN).
int? _compare(Object? a, Object? b) {
  if (a is String && b is String) {
    final c = a.compareTo(b);
    return c < 0 ? -1 : (c > 0 ? 1 : 0);
  }
  final x = a is JsObject ? toNum(toStr(a)) : toNum(a), y = b is JsObject ? toNum(toStr(b)) : toNum(b);
  if (x != x || y != y) return null;
  return x < y ? -1 : (x > y ? 1 : 0);
}

int _int32(Object? v) {
  final n = toNum(v);
  if (n != n || n.isInfinite) return 0;
  return n.toInt().toSigned(32);
}

bool _instanceOf(Object? value, Object? of) {
  if (of is Native && of.isA != null) return of.isA!(value);
  if (of is! JsCallable) _typeError("Right-hand side of 'instanceof' is not callable");
  if (value is! JsObject) return false;
  final prototype = of.get('prototype');
  for (var o = value.proto; o != null; o = o.proto) {
    if (identical(o, prototype)) return true;
  }
  return false;
}

/// The keys a `for…in` goes over.
List<String> forInKeys(Object? v) {
  if (v is JsObject) {
    final keys = v.ownKeys();
    var o = v.proto;
    if (o == null) return keys;
    final seen = keys.toSet();
    while (o != null) {
      if (o.listed) {
        for (final key in o.ownKeys()) {
          if (seen.add(key)) keys.add(key);
        }
      }
      o = o.proto;
    }
    return keys;
  }
  if (v is String) return <String>[for (var i = 0; i < v.length; i++) '$i'];
  return const <String>[];
}

Object? getNamed(Object? o, String name) {
  if (o is JsObject) return o.get(name);
  if (o is String) {
    if (name == 'length') return o.length;
    final method = _stringProto[name];
    if (method != null) return method;
    final i = _indexOf(name);
    return i != null && i < o.length ? o[i] : (_objectProto[name] ?? undefined);
  }
  if (o is num) return _numberProto[name] ?? _objectProto[name] ?? undefined;
  if (o is bool) return _objectProto[name] ?? undefined;
  _typeError("Cannot read properties of ${toStr(o)} (reading '$name')");
}

Object? getComputed(Object? o, Object? key) {
  if (key is num) {
    final i = key.toInt();
    if (i == key && i >= 0) {
      if (o is JsArray) return i < o.list.length ? o.list[i] : undefined;
      if (o is String) return i < o.length ? o[i] : undefined;
    }
  }
  return getNamed(o, key is String ? key : toStr(key));
}

void setNamed(Object? o, String name, Object? value) {
  if (o is JsObject) return o.set(name, value);
  if (o == null || identical(o, undefined)) _typeError("Cannot set properties of ${toStr(o)} (setting '$name')");
}

void setComputed(Object? o, Object? key, Object? value) {
  if (key is num && o is JsArray) {
    final i = key.toInt();
    if (i == key && i >= 0) return o.setAt(i, value);
  }
  setNamed(o, key is String ? key : toStr(key), value);
}

/// Calls `f`, which a mode handed to one of JavaScript's own functions.
Object? _call(Object? f, List<Object?> args) {
  if (f is JsCallable) return f.call(undefined, args);
  _typeError('${toStr(f)} is not a function');
}
