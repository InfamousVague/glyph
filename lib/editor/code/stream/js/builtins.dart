part of 'js.dart';

// What JavaScript itself brings: the methods of strings, arrays, functions and regular expressions, and the
// globals (`RegExp`, `Object`, `Math`, `parseInt`). Only what the modes call is here.

typedef _Fn = Object? Function(Object? self, List<Object?> args);

Map<String, Native> _natives(Map<String, _Fn> functions) => <String, Native>{for (final entry in functions.entries) entry.key: Native(entry.value)};

Object? _arg(List<Object?> args, int i) => i < args.length ? args[i] : undefined;

/// `ToIntegerOrInfinity` of an argument, `otherwise` where it was not given; an infinity is a very large number.
int _intArg(List<Object?> args, int i, int otherwise) {
  if (i >= args.length || identical(args[i], undefined)) return otherwise;
  final n = toNum(args[i]);
  if (n != n) return 0;
  if (n.isInfinite) return n > 0 ? 0x3fffffff : -0x3fffffff;
  return n.toInt();
}

String _selfString(Object? self) => self is String ? self : toStr(self);

/// A position counted from the end where it is negative, kept within the length: `slice`'s arguments.
int _relative(int at, int length) => at < 0 ? (at + length < 0 ? 0 : at + length) : (at > length ? length : at);

// ---- strings ---------------------------------------------------------------------------------------------------------

final RegExp _dollar = RegExp(r'\$([$&`' "'" r']|\d\d?)');

/// A replacement string's `$1`, `$&` and `$$`.
String _expand(String replacement, RegExpMatch? m, String matched, int at, String whole) {
  if (!replacement.contains(r'$')) return replacement;
  return replacement.replaceAllMapped(_dollar, (d) {
    final what = d.group(1)!;
    switch (what) {
      case r'$':
        return r'$';
      case '&':
        return matched;
      case '`':
        return whole.substring(0, at);
      case "'":
        return whole.substring(at + matched.length);
    }
    if (m == null) return d.group(0)!;
    var n = int.parse(what);
    if (n > m.groupCount && what.length == 2) {
      // `$12` with one group is group 1 and a 2.
      n = int.parse(what[0]);
      if (n == 0 || n > m.groupCount) return d.group(0)!;
      return (m.group(n) ?? '') + what[1];
    }
    if (n == 0 || n > m.groupCount) return d.group(0)!;
    return m.group(n) ?? '';
  });
}

String _replace(String s, Object? pattern, Object? replacement) {
  String put(RegExpMatch? m, String matched, int at) {
    if (replacement is JsCallable) {
      return toStr(
        replacement.call(undefined, <Object?>[
          matched,
          if (m != null)
            for (var g = 1; g <= m.groupCount; g++) m.group(g) ?? undefined,
          at,
          s,
        ]),
      );
    }
    return _expand(toStr(replacement), m, matched, at, s);
  }

  if (pattern is JsRegExp) {
    final out = StringBuffer();
    var from = 0;
    if (pattern.global) {
      pattern.lastIndex = 0;
      for (final m in pattern.re.allMatches(s)) {
        out
          ..write(s.substring(from, m.start))
          ..write(put(m, m.group(0)!, m.start));
        from = m.end;
      }
    } else {
      final m = pattern.re.firstMatch(s);
      if (m == null) return s;
      out
        ..write(s.substring(0, m.start))
        ..write(put(m, m.group(0)!, m.start));
      from = m.end;
    }
    out.write(s.substring(from));
    return out.toString();
  }
  final find = toStr(pattern), at = s.indexOf(find);
  if (at < 0) return s;
  return s.substring(0, at) + put(null, find, at) + s.substring(at + find.length);
}

JsArray _split(String s, Object? separator, int limit) {
  final out = <Object?>[];
  if (limit == 0) return JsArray(out);
  if (identical(separator, undefined)) return JsArray(<Object?>[s]);
  if (separator is JsRegExp) {
    final re = separator.re;
    if (s.isEmpty) return JsArray(re.matchAsPrefix(s) != null ? out : <Object?>[s]);
    var p = 0, q = 0;
    while (q < s.length) {
      final m = re.matchAsPrefix(s, q) as RegExpMatch?;
      if (m == null || m.end == p) {
        q++;
        continue;
      }
      out.add(s.substring(p, q));
      if (out.length == limit) return JsArray(out);
      for (var g = 1; g <= m.groupCount; g++) {
        out.add(m.group(g) ?? undefined);
        if (out.length == limit) return JsArray(out);
      }
      p = q = m.end;
    }
    out.add(s.substring(p));
    return JsArray(out);
  }
  final by = toStr(separator);
  if (by.isEmpty) {
    for (var i = 0; i < s.length && out.length < limit; i++) {
      out.add(s[i]);
    }
    return JsArray(out);
  }
  var from = 0;
  while (out.length < limit) {
    final at = s.indexOf(by, from);
    if (at < 0) break;
    out.add(s.substring(from, at));
    from = at + by.length;
  }
  if (out.length < limit) out.add(s.substring(from));
  return JsArray(out);
}

/// `String.prototype.match`: one match with its groups, or with the `g` flag every match's text. What is not a
/// pattern is made one of, from what it says as a string.
JsArray? stringMatch(String s, Object? pattern) {
  final re = pattern is JsRegExp ? pattern : JsRegExp(identical(pattern, undefined) ? '' : toStr(pattern), '');
  if (!re.global) return re.exec(s);
  re.lastIndex = 0;
  final all = <Object?>[for (final m in re.re.allMatches(s)) m.group(0)];
  return all.isEmpty ? null : JsArray(all);
}

final Map<String, Native> _stringProto = _natives(<String, _Fn>{
  'charAt': (self, args) {
    final s = _selfString(self), i = _intArg(args, 0, 0);
    return i >= 0 && i < s.length ? s[i] : '';
  },
  'charCodeAt': (self, args) {
    final s = _selfString(self), i = _intArg(args, 0, 0);
    return i >= 0 && i < s.length ? s.codeUnitAt(i) : double.nan;
  },
  'indexOf': (self, args) {
    final s = _selfString(self);
    return s.indexOf(toStr(_arg(args, 0)), _relativeFrom(_intArg(args, 1, 0), s.length));
  },
  'lastIndexOf': (self, args) {
    final s = _selfString(self), from = _intArg(args, 1, s.length);
    return s.lastIndexOf(toStr(_arg(args, 0)), from < 0 ? 0 : (from > s.length ? s.length : from));
  },
  'includes': (self, args) => _selfString(self).contains(toStr(_arg(args, 0))),
  'startsWith': (self, args) {
    final s = _selfString(self);
    return s.startsWith(toStr(_arg(args, 0)), _relativeFrom(_intArg(args, 1, 0), s.length));
  },
  'endsWith': (self, args) => _selfString(self).endsWith(toStr(_arg(args, 0))),
  'slice': (self, args) {
    final s = _selfString(self);
    final from = _relative(_intArg(args, 0, 0), s.length), to = _relative(_intArg(args, 1, s.length), s.length);
    return from < to ? s.substring(from, to) : '';
  },
  'substring': (self, args) {
    final s = _selfString(self);
    var from = _relativeFrom(_intArg(args, 0, 0), s.length), to = _relativeFrom(_intArg(args, 1, s.length), s.length);
    if (from > to) (from, to) = (to, from);
    return s.substring(from, to);
  },
  'substr': (self, args) {
    final s = _selfString(self);
    final from = _relative(_intArg(args, 0, 0), s.length);
    var length = _intArg(args, 1, s.length - from);
    if (length > s.length - from) length = s.length - from;
    return length > 0 ? s.substring(from, from + length) : '';
  },
  'toLowerCase': (self, args) => _selfString(self).toLowerCase(),
  'toUpperCase': (self, args) => _selfString(self).toUpperCase(),
  'trim': (self, args) => _selfString(self).trim(),
  'toString': (self, args) => _selfString(self),
  'valueOf': (self, args) => _selfString(self),
  'concat': (self, args) => _selfString(self) + args.map(toStr).join(),
  'split': (self, args) => _split(_selfString(self), _arg(args, 0), _intArg(args, 1, 0x3fffffff)),
  'match': (self, args) => stringMatch(_selfString(self), _arg(args, 0)),
  'replace': (self, args) => _replace(_selfString(self), _arg(args, 0), _arg(args, 1)),
  'search': (self, args) {
    final pattern = _arg(args, 0);
    final re = pattern is JsRegExp ? pattern.re : RegExp(toStr(pattern));
    return re.firstMatch(_selfString(self))?.start ?? -1;
  },
});

/// A start within the string: below nothing is nothing, past the end is the end.
int _relativeFrom(int at, int length) => at < 0 ? 0 : (at > length ? length : at);

final Map<String, Native> _numberProto = _natives(<String, _Fn>{
  'toString': (self, args) {
    final n = self as num, radix = _intArg(args, 0, 10);
    return radix == 10 || n != n.truncate() ? _numToStr(n) : n.toInt().toRadixString(radix);
  },
  'toFixed': (self, args) => (self as num).toStringAsFixed(_intArg(args, 0, 0)),
  'valueOf': (self, args) => self,
});

// ---- arrays ----------------------------------------------------------------------------------------------------------

List<Object?> _selfList(Object? self) {
  if (self is JsArray) return self.list;
  _typeError('not an array');
}

/// `Array.prototype.sort` as V8 does it, where it shows. A comparison that never answers below nothing
/// (Stylus's mode sorts its words by `b > a`, a boolean) leaves V8's merge sort seeing one run already in order,
/// and the array as it was; the order a mode builds its patterns in comes of that. So: the first run is counted
/// as V8 counts it, a short array is finished by V8's binary insertion, and a long one by a stable merge, which
/// for a comparison that makes sense gives what any stable sort gives.
void _sort(List<Object?> list, Object? by) {
  int compare(Object? a, Object? b) {
    // `undefined` sorts last, whatever the comparison says.
    final ua = identical(a, undefined), ub = identical(b, undefined);
    if (ua || ub) return ua ? (ub ? 0 : 1) : -1;
    if (by is JsCallable) {
      final n = toNum(by.call(undefined, <Object?>[a, b]));
      return n < 0 ? -1 : (n > 0 ? 1 : 0);
    }
    return toStr(a).compareTo(toStr(b));
  }

  final n = list.length;
  if (n < 2) return;
  // `CountAndMakeRun`.
  var run = 2;
  final descending = compare(list[1], list[0]) < 0;
  while (run < n) {
    final order = compare(list[run], list[run - 1]);
    if (descending ? order >= 0 : order < 0) break;
    run++;
  }
  if (descending) {
    for (var low = 0, high = run - 1; low < high; low++, high--) {
      final swap = list[low];
      list[low] = list[high];
      list[high] = swap;
    }
  }
  if (run == n) return;
  if (n < 32) {
    // `BinaryInsertionSort`.
    for (var start = run; start < n; start++) {
      var left = 0, right = start;
      final pivot = list[start];
      while (left < right) {
        final mid = left + ((right - left) >> 1);
        if (compare(pivot, list[mid]) < 0) {
          right = mid;
        } else {
          left = mid + 1;
        }
      }
      for (var p = start; p > left; p--) {
        list[p] = list[p - 1];
      }
      list[left] = pivot;
    }
    return;
  }
  final sorted = _mergeSort(list, compare);
  for (var i = 0; i < n; i++) {
    list[i] = sorted[i];
  }
}

List<Object?> _mergeSort(List<Object?> list, int Function(Object?, Object?) compare) {
  if (list.length < 2) return list;
  final middle = list.length >> 1;
  final a = _mergeSort(list.sublist(0, middle), compare), b = _mergeSort(list.sublist(middle), compare);
  final out = <Object?>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    out.add(compare(b[j], a[i]) < 0 ? b[j++] : a[i++]);
  }
  while (i < a.length) {
    out.add(a[i++]);
  }
  while (j < b.length) {
    out.add(b[j++]);
  }
  return out;
}

final Map<String, Native> _arrayProto = _natives(<String, _Fn>{
  'push': (self, args) {
    final list = _selfList(self)..addAll(args);
    return list.length;
  },
  'pop': (self, args) {
    final list = _selfList(self);
    return list.isEmpty ? undefined : list.removeLast();
  },
  'shift': (self, args) {
    final list = _selfList(self);
    return list.isEmpty ? undefined : list.removeAt(0);
  },
  'unshift': (self, args) {
    final list = _selfList(self)..insertAll(0, args);
    return list.length;
  },
  'slice': (self, args) {
    final list = _selfList(self);
    final from = _relative(_intArg(args, 0, 0), list.length), to = _relative(_intArg(args, 1, list.length), list.length);
    return JsArray(from < to ? list.sublist(from, to) : <Object?>[]);
  },
  'splice': (self, args) {
    final list = _selfList(self);
    final from = _relative(_intArg(args, 0, 0), list.length);
    var count = args.length < 2 ? list.length - from : _intArg(args, 1, 0);
    if (count < 0) count = 0;
    if (count > list.length - from) count = list.length - from;
    final removed = list.sublist(from, from + count);
    list.replaceRange(from, from + count, args.length > 2 ? args.sublist(2) : const <Object?>[]);
    return JsArray(removed);
  },
  'concat': (self, args) {
    final out = List<Object?>.of(_selfList(self));
    for (final arg in args) {
      if (arg is JsArray) {
        out.addAll(arg.list);
      } else {
        out.add(arg);
      }
    }
    return JsArray(out);
  },
  'join': (self, args) {
    final by = args.isEmpty || identical(args[0], undefined) ? ',' : toStr(args[0]);
    return _selfList(self).map((item) => item == null || identical(item, undefined) ? '' : toStr(item)).join(by);
  },
  'indexOf': (self, args) {
    final list = _selfList(self), what = _arg(args, 0);
    for (var i = _relative(_intArg(args, 1, 0), list.length); i < list.length; i++) {
      if (strictEquals(list[i], what)) return i;
    }
    return -1;
  },
  'lastIndexOf': (self, args) {
    final list = _selfList(self), what = _arg(args, 0);
    for (var i = list.length - 1; i >= 0; i--) {
      if (strictEquals(list[i], what)) return i;
    }
    return -1;
  },
  'includes': (self, args) {
    final what = _arg(args, 0);
    return _selfList(self).any((item) => strictEquals(item, what));
  },
  'forEach': (self, args) {
    final list = _selfList(self), f = _arg(args, 0);
    for (var i = 0; i < list.length; i++) {
      _call(f, <Object?>[list[i], i, self]);
    }
    return undefined;
  },
  'map': (self, args) {
    final list = _selfList(self), f = _arg(args, 0);
    return JsArray(<Object?>[for (var i = 0; i < list.length; i++) _call(f, <Object?>[list[i], i, self])]);
  },
  'filter': (self, args) {
    final list = _selfList(self), f = _arg(args, 0);
    return JsArray(<Object?>[
      for (var i = 0; i < list.length; i++)
        if (truthy(_call(f, <Object?>[list[i], i, self]))) list[i],
    ]);
  },
  'some': (self, args) {
    final list = _selfList(self), f = _arg(args, 0);
    for (var i = 0; i < list.length; i++) {
      if (truthy(_call(f, <Object?>[list[i], i, self]))) return true;
    }
    return false;
  },
  'every': (self, args) {
    final list = _selfList(self), f = _arg(args, 0);
    for (var i = 0; i < list.length; i++) {
      if (!truthy(_call(f, <Object?>[list[i], i, self]))) return false;
    }
    return true;
  },
  'reverse': (self, args) {
    final list = _selfList(self);
    final turned = list.reversed.toList();
    list.setAll(0, turned);
    return self;
  },
  'sort': (self, args) {
    _sort(_selfList(self), _arg(args, 0));
    return self;
  },
  'toString': (self, args) => toStr(self),
});

// ---- functions, regular expressions, objects -------------------------------------------------------------------------

JsCallable _selfFunction(Object? self) {
  if (self is JsCallable) return self;
  _typeError('not a function');
}

final Map<String, Native> _functionProto = _natives(<String, _Fn>{
  'call': (self, args) => _selfFunction(self).call(_arg(args, 0), args.length > 1 ? args.sublist(1) : const <Object?>[]),
  'apply': (self, args) {
    final list = _arg(args, 1);
    return _selfFunction(self).call(_arg(args, 0), list is JsArray ? List<Object?>.of(list.list) : const <Object?>[]);
  },
  'bind': (self, args) {
    final f = _selfFunction(self), bound = _arg(args, 0), first = args.length > 1 ? args.sublist(1) : const <Object?>[];
    return Native((_, more) => f.call(bound, <Object?>[...first, ...more]));
  },
});

final Map<String, Native> _regExpProto = _natives(<String, _Fn>{
  'test': (self, args) => (self as JsRegExp).test(toStr(_arg(args, 0))),
  'exec': (self, args) => (self as JsRegExp).exec(toStr(_arg(args, 0))),
  'toString': (self, args) => toStr(self),
});

final Map<String, Native> _objectProto = _natives(<String, _Fn>{
  'hasOwnProperty': (self, args) => self is JsObject && self.hasOwn(toStr(_arg(args, 0))),
  'propertyIsEnumerable': (self, args) => self is JsObject && self.hasOwn(toStr(_arg(args, 0))) && !(self is JsArray && _arg(args, 0) == 'length'),
  'toString': (self, args) => toStr(self),
});

// ---- the globals -----------------------------------------------------------------------------------------------------

JsRegExp _newRegExp(List<Object?> args) {
  final pattern = _arg(args, 0), flags = _arg(args, 1);
  if (pattern is JsRegExp) return JsRegExp(pattern.source, identical(flags, undefined) ? pattern.flags : toStr(flags));
  final source = identical(pattern, undefined) ? '' : toStr(pattern);
  return JsRegExp(source.isEmpty ? '(?:)' : _escapedSource(source), identical(flags, undefined) ? '' : toStr(flags));
}

/// A pattern made from a string, as its `source` then reads: a slash outside a class is written `\/` and a line
/// end `\n`, so that the source between slashes is a literal again (`EscapeRegExpPattern`). They match the same.
String _escapedSource(String source) {
  if (!source.contains('/') && !source.contains('\n')) return source;
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == r'\' && i + 1 < source.length) {
      out
        ..write(c)
        ..write(source[++i]);
      continue;
    }
    if (c == '[') inClass = true;
    if (c == ']') inClass = false;
    if (c == '/' && !inClass) {
      out.write(r'\/');
    } else if (c == '\n') {
      out.write(r'\n');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

final RegExp _floatPrefix = RegExp(r'^[+-]?(?:Infinity|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)');

num _parseFloat(Object? v) {
  final m = _floatPrefix.firstMatch(toStr(v).trimLeft());
  if (m == null) return double.nan;
  final text = m.group(0)!;
  if (text.endsWith('Infinity')) return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  final n = double.parse(text.endsWith('.') ? '${text}0' : text);
  return n == n.truncateToDouble() && n.abs() < 1e15 ? n.toInt() : n;
}

num _parseInt(Object? v, Object? base) {
  var s = toStr(v).trimLeft();
  var negative = false;
  if (s.startsWith('-') || s.startsWith('+')) {
    negative = s.startsWith('-');
    s = s.substring(1);
  }
  var radix = identical(base, undefined) ? 0 : toNum(base).toInt();
  if ((radix == 0 || radix == 16) && (s.startsWith('0x') || s.startsWith('0X'))) {
    s = s.substring(2);
    radix = 16;
  }
  if (radix == 0) radix = 10;
  if (radix < 2 || radix > 36) return double.nan;
  var end = 0;
  while (end < s.length && int.tryParse(s[end], radix: radix) != null) {
    end++;
  }
  if (end == 0) return double.nan;
  final n = int.tryParse(s.substring(0, end), radix: radix) ?? double.parse(s.substring(0, end));
  return negative ? -n : n;
}

JsObject _object(Map<String, Object?> props) => JsObject()..props.addAll(props);

num _fold(List<Object?> args, num start, num Function(num a, num b) f) {
  var out = start;
  for (final arg in args) {
    final n = toNum(arg);
    if (n != n) return double.nan;
    out = f(out, n);
  }
  return out;
}

/// Whether `code` is JavaScript with nothing wrong or missing, for the one mode that asks (`Function`, below).
/// Answered by whoever has a JavaScript parser at hand (`languages.dart`, with the grammar the editor colours
/// JavaScript by); with nobody to ask, nothing is whole.
bool Function(String code)? wholeJavaScript;

/// What a mode finds by a name it did not declare.
final Map<String, Object?> globals = <String, Object?>{
  'undefined': undefined,
  'Infinity': double.infinity,
  'NaN': double.nan,
  'RegExp': Native((self, args) => _newRegExp(args), isA: (value) => value is JsRegExp),
  'Object': Native(
      (self, args) => args.isNotEmpty && args[0] is JsObject ? args[0] : JsObject(),
      isA: (value) => value is JsObject,
    )
    ..props['keys'] = Native((self, args) {
      final of = _arg(args, 0);
      return JsArray(<Object?>[...(of is JsObject ? of.ownKeys() : forInKeys(of))]);
    })
    ..props['create'] = Native((self, args) {
      final proto = _arg(args, 0);
      return JsObject(proto is JsObject ? proto : null);
    })
    ..props['assign'] = Native((self, args) {
      final to = _arg(args, 0);
      if (to is! JsObject) return to;
      for (final from in args.skip(1)) {
        if (from is JsObject) {
          for (final key in from.ownKeys()) {
            to.set(key, from.get(key));
          }
        }
      }
      return to;
    }),
  'Array': Native(
    (self, args) => args.length == 1 && args[0] is num ? JsArray(<Object?>[for (var i = 0; i < (args[0]! as num); i++) undefined]) : JsArray(List<Object?>.of(args)),
    isA: (value) => value is JsArray,
  )..props['isArray'] = Native((self, args) => _arg(args, 0) is JsArray),
  'Function': Native(
    // Pug's mode asks this whether an attribute's value so far is whole JavaScript: `Function('', 'var x =' +
    // value)` throws where it is not. What it makes is never called, so only the asking is answered.
    (self, args) {
      final body = args.isEmpty ? '' : toStr(args.last);
      final whole = wholeJavaScript;
      if (whole == null || !whole(body)) throw _error('SyntaxError', 'Unexpected end of input');
      return Native((self, args) => throw _error('Error', 'A function made by Function(…) is not run here'));
    },
    isA: (value) => value is JsCallable,
  ),
  'Error': Native(
    (self, args) => _object(<String, Object?>{'name': 'Error', 'message': args.isEmpty ? '' : toStr(args[0])}),
    isA: (value) => value is JsObject && value.hasOwn('message'),
  ),
  'String': Native((self, args) => args.isEmpty ? '' : toStr(args[0]))..props['fromCharCode'] = Native((self, args) => String.fromCharCodes(args.map((c) => toNum(c).toInt() & 0xffff))),
  'Number': Native((self, args) => args.isEmpty ? 0 : toNum(args[0])),
  'Boolean': Native((self, args) => truthy(_arg(args, 0))),
  'parseInt': Native((self, args) => _parseInt(_arg(args, 0), _arg(args, 1))),
  'parseFloat': Native((self, args) => _parseFloat(_arg(args, 0))),
  'isNaN': Native((self, args) {
    final n = toNum(_arg(args, 0));
    return n != n;
  }),
  'isFinite': Native((self, args) => toNum(_arg(args, 0)).isFinite),
  'Math': _object(<String, Object?>{
    'max': Native((self, args) => _fold(args, double.negativeInfinity, (a, b) => a > b ? a : b)),
    'min': Native((self, args) => _fold(args, double.infinity, (a, b) => a < b ? a : b)),
    'floor': Native((self, args) => _whole(toNum(_arg(args, 0)), (n) => n.floorToDouble())),
    'ceil': Native((self, args) => _whole(toNum(_arg(args, 0)), (n) => n.ceilToDouble())),
    'round': Native((self, args) => _whole(toNum(_arg(args, 0)), (n) => (n + 0.5).floorToDouble())),
    'abs': Native((self, args) => toNum(_arg(args, 0)).abs()),
  }),
};

num _whole(num n, double Function(double n) f) {
  if (n is int) return n;
  if (n != n || n.isInfinite) return n;
  final out = f(n.toDouble());
  return out.abs() < 1e15 ? out.toInt() : out;
}
