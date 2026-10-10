/// A language read by one of CodeMirror's older modes: `StreamLanguage` of @codemirror/language 6.12 (MIT, Marijn
/// Haverbeke and others). The language pack reads C#, Kotlin, Swift, Ruby, the shell, TOML, Dart, Lua, diffs and
/// a hundred more this way: a line at a time, a `token` function eating characters and answering a word for
/// what they were (`keyword`, `def`, `string`), with a state it carries from line to line.
///
/// The word becomes tags and the tags a class as on the web (`createTokenType`, then the highlighter): the rules
/// are in [classOfToken], over the tables tool/code_grammars.mjs copies.
///
/// What differs: CodeMirror builds a tree of the tokens; here they are kept as they come, and the state is kept
/// as it stood at the start of each line, so a block that changed is read again from the line that changed.
library;

import '../work.dart';
import 'string_stream.dart';
import 'tags.g.dart';

/// One of the older modes.
abstract class StreamMode<S> {
  const StreamMode();

  S startState(int indentUnit);

  /// A copy of `state` that a later line's reading will not change.
  S copyState(S state);

  /// Reads one token off `stream` and answers its style, or null for none.
  String? token(StringStream stream, S state);

  void blankLine(S state, int indentUnit) {}

  /// The mode's own names for tags, beside the usual ones (`tokenTable`).
  Map<String, String> get tokenTable => const <String, String>{};
}

final Map<String, String> _classes = <String, String>{};

/// `powerSet`: every selection of `mods`, the longest first, in the order @lezer/highlight makes them.
List<List<String>> _powerSet(List<String> mods) {
  final sets = <List<String>>[<String>[]];
  for (var i = 0; i < mods.length; i++) {
    for (var j = 0, e = sets.length; j < e; j++) {
      sets.add(<String>[...sets[j], mods[i]]);
    }
  }
  // A stable sort, by length, longest first.
  final sorted = <List<String>>[];
  for (var length = mods.length; length >= 0; length--) {
    sorted.addAll(sets.where((set) => set.length == length));
  }
  return sorted;
}

/// The class of one tag, written `base.modifier.modifier`: the first of the tags it was made from that
/// glyphHighlight.ts has a class for (`tagHighlighter`'s `style` over `Tag.set`).
String _classOfTag(String base, List<String> mods) {
  final sorted = <String>[
    for (final mod in tagModifiers)
      if (mods.contains(mod)) mod,
  ];
  final configs = _powerSet(sorted);
  for (final parent in <String>[base, ...?tagParents[base]]) {
    for (final config in configs) {
      final cls = classedTags[<String>[parent, ...config].join('.')];
      if (cls != null) return cls;
    }
  }
  return '';
}

/// The class of a mode's token: `createTokenType` of @codemirror/language, then the highlighter. A token may
/// name several tags, a space between them, and each tag its modifiers after dots; a name that is no tag is
/// passed over, as CodeMirror passes it over with a warning.
String classOfToken(String token, [Map<String, String> table = const <String, String>{}]) {
  final key = table.isEmpty ? token : '$token\u0000${identityHashCode(table)}';
  final known = _classes[key];
  if (known != null) return known;
  final tagStr = legacyTokenNames[token] ?? token;
  final classes = <String>[];
  for (final name in tagStr.split(' ')) {
    String? base;
    final mods = <String>[];
    for (var part in name.split('.')) {
      part = table[part] ?? part;
      if (tagModifiers.contains(part)) {
        if (base != null && !mods.contains(part)) mods.add(part);
      } else if (tagParents.containsKey(part)) {
        base ??= part;
      }
    }
    if (base == null) continue;
    final cls = _classOfTag(base, mods);
    if (cls.isNotEmpty) classes.add(cls);
  }
  return _classes[key] = classes.join(' ');
}

class StreamLanguage<S> extends CodeLanguage {
  StreamLanguage(super.name, this._load);

  final StreamMode<S> Function() _load;
  late final StreamMode<S> mode = _load();

  @override
  CodeWork start(String code) {
    CodeStats.started++;
    return StreamWork<S>._(this, code);
  }

  @override
  CodeWork resume(CodeWork old, String code) {
    if (old is! StreamWork<S> || !identical(old.language, this)) return start(code);
    final before = old.code, shorter = before.length < code.length ? before.length : code.length;
    var same = 0;
    while (same < shorter && before.codeUnitAt(same) == code.codeUnitAt(same)) {
      same++;
    }
    if (same == before.length && same == code.length) return old;
    // The line the change is on is read again; the ones before it stand.
    var line = 0;
    while (line + 1 < old._lineStarts.length && old._lineStarts[line + 1] <= same) {
      line++;
    }
    if (line == 0) {
      CodeStats.started++;
      return StreamWork<S>._(this, code);
    }
    CodeStats.resumed++;
    return StreamWork<S>._(this, code, from: old, lines: line);
  }
}

/// CodeMirror's `C.MaxLineLength`: a line is not read past its ten-thousandth character.
const int _maxLineLength = 10000;

class StreamWork<S> extends CodeWork {
  StreamWork._(this.language, this.code, {StreamWork<S>? from, int lines = 0}) {
    if (from == null) {
      _lineStarts.add(0);
      _states.add(language.mode.startState(_indentUnit));
      return;
    }
    // The lines before the changed one: where each starts, the state it starts in, and its tokens.
    _lineStarts.addAll(from._lineStarts.take(lines + 1));
    _states.addAll(from._states.take(lines + 1));
    final upTo = _lineStarts[lines];
    var kept = from._from.length;
    while (kept > 0 && from._to[kept - 1] > upTo) {
      kept--;
    }
    _from.addAll(from._from.take(kept));
    _to.addAll(from._to.take(kept));
    _key.addAll(from._key.take(kept));
    _cls.addAll(from._cls.take(kept));
    _parsed = upTo;
  }

  @override
  final StreamLanguage<S> language;

  @override
  final String code;

  /// `parser.parse` outside an editor reads with a tab of four and an indent of two; the editor's own state
  /// has the same defaults, and the app sets neither.
  static const int _tabSize = 4, _indentUnit = 2;

  /// Where each line read so far starts, and the next one after them; the state each starts in.
  final List<int> _lineStarts = <int>[];
  final List<S> _states = <S>[];

  // The tokens, in order: from, to, the style's name (what two tokens are joined by), and its class.
  final List<int> _from = <int>[], _to = <int>[];
  final List<String> _key = <String>[], _cls = <String>[];

  int _parsed = 0;
  bool _ended = false;

  @override
  int get parsedTo => _ended ? code.length : _parsed;

  @override
  bool get done => _ended;

  @override
  void work(int upTo, Budget budget) {
    final mode = language.mode;
    var lines = 0;
    while (!_ended && _parsed <= upTo) {
      final start = _lineStarts.last;
      var end = code.indexOf('\n', start);
      if (end < 0) end = code.length;
      final state = mode.copyState(_states.last);
      final stream = StringStream(code.substring(start, end), _tabSize, _indentUnit);
      if (stream.eol()) {
        mode.blankLine(state, _indentUnit);
      } else {
        while (!stream.eol()) {
          stream.start = stream.pos;
          String? style;
          var moved = false;
          for (var i = 0; i < 10; i++) {
            style = mode.token(stream, state);
            if (stream.pos > stream.start) {
              moved = true;
              break;
            }
          }
          if (!moved) throw StateError('Stream parser failed to advance stream.');
          if (style != null && style.isNotEmpty) _emit(style, start + stream.start, start + stream.pos);
          if (stream.start > _maxLineLength) break;
        }
      }
      CodeStats.read += end - start + 1;
      if (end >= code.length) {
        _ended = true;
        _parsed = code.length;
        break;
      }
      _parsed = end + 1;
      _lineStarts.add(end + 1);
      _states.add(state);
      if ((++lines & 15) == 0 && budget.spent) break;
    }
  }

  /// `emitToken`: a token of the same style straight after another is one token with it.
  void _emit(String style, int from, int to) {
    final key = legacyTokenNames[style] ?? style;
    final last = _from.length - 1;
    if (last >= 0 && _to[last] == from && _key[last] == key) {
      _to[last] = to;
      return;
    }
    _from.add(from);
    _to.add(to);
    _key.add(key);
    _cls.add(classOfToken(style, language.mode.tokenTable));
  }

  @override
  void spans(int from, int to, SpanSink sink, {String inherited = '', Budget? budget}) {
    // The first token that ends after `from`.
    var low = 0, high = _from.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_to[mid] <= from) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < _from.length && _from[i] < to; i++) {
      final cls = _cls[i];
      if (cls.isEmpty && inherited.isEmpty) continue;
      final a = _from[i] < from ? from : _from[i], b = _to[i] > to ? to : _to[i];
      if (b > a) sink(a, b, inherited.isEmpty ? cls : (cls.isEmpty ? inherited : '$inherited $cls'));
    }
  }
}
