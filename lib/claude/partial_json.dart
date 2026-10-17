/// A tool's input read as Claude writes it (docs/CLAUDE_APP.md, "Typing as Claude writes"). With
/// `eager_input_streaming` the API hands a tool's input over in pieces of JSON (`input_json_delta`), cut anywhere: in
/// a key, in a word, in the middle of an escape. [PartialFields] reads the top level of that object as it comes and
/// says, for each field whose value is a string, when it starts, each run of its letters as they are decoded, and
/// when it ends. That is what lets a note's words be typed into it while Claude is still writing them.
///
/// Only the top level is read for this: a value that is not a string (a number, a list, an object) is stepped over,
/// strings and brackets inside it counted, and the whole input is parsed as JSON once it is complete, as ever. The
/// reader never throws on what it is given; JSON it cannot follow leaves it [broken], and the rest is ignored.
library;

/// What [PartialFields] says as it reads.
abstract class FieldListener {
  /// A string value for [key] has started.
  void started(String key) {}

  /// More letters of [key]'s value, decoded.
  void letters(String key, String text) {}

  /// [key]'s value is whole: [value] is all of it.
  void ended(String key, String value) {}
}

enum _At { start, key, keyText, colon, value, string, other, next, done }

/// Reads the top level of a JSON object from pieces.
class PartialFields {
  PartialFields([this.listener]);

  final FieldListener? listener;

  /// The string values read so far, whole or not yet.
  final Map<String, String> strings = {};

  /// The keys whose string values are whole.
  final Set<String> whole = {};

  /// Whether the JSON stopped making sense; nothing more is read.
  bool broken = false;

  _At _at = _At.start;
  final StringBuffer _key = StringBuffer();
  String _current = '';
  final StringBuffer _value = StringBuffer();

  // An escape in a string: after the backslash, and the hex digits of a \u.
  bool _escape = false;
  String? _hex;
  int? _high;

  // A value that is not a string: its depth and whether in a string inside it.
  int _depth = 0;
  bool _inner = false;
  bool _innerEscape = false;

  /// Whether the object has closed.
  bool get done => _at == _At.done;

  /// Reads one more piece.
  void add(String piece) {
    if (broken || done) return;
    final out = StringBuffer();
    for (var i = 0; i < piece.length && !broken && !done; i += 1) {
      final c = piece[i];
      switch (_at) {
        case _At.start:
          if (_space(c)) continue;
          c == '{' ? _at = _At.key : broken = true;
        case _At.key:
          if (_space(c) || c == ',') continue;
          if (c == '}') {
            _at = _At.done;
          } else if (c == '"') {
            _key.clear();
            _at = _At.keyText;
          } else {
            broken = true;
          }
        case _At.keyText:
          if (_escape) {
            _escape = false;
            _key.write(_simple(c) ?? c);
          } else if (c == r'\') {
            _escape = true;
          } else if (c == '"') {
            _current = _key.toString();
            _at = _At.colon;
          } else {
            _key.write(c);
          }
        case _At.colon:
          if (_space(c)) continue;
          c == ':' ? _at = _At.value : broken = true;
        case _At.value:
          if (_space(c)) continue;
          if (c == '"') {
            _value.clear();
            strings[_current] = '';
            _at = _At.string;
            listener?.started(_current);
          } else {
            _depth = (c == '{' || c == '[') ? 1 : 0;
            _inner = false;
            _at = _At.other;
            // A number, true, false or null (depth 0) runs to the next comma or brace.
          }
        case _At.string:
          final letter = _letter(c);
          if (letter == null) {
            if (_closed) {
              _closed = false;
              _flush(out);
              final value = _value.toString();
              strings[_current] = value;
              whole.add(_current);
              listener?.ended(_current, value);
              _at = _At.next;
            }
            continue;
          }
          out.write(letter);
          _value.write(letter);
        case _At.other:
          if (_inner) {
            if (_innerEscape) {
              _innerEscape = false;
            } else if (c == r'\') {
              _innerEscape = true;
            } else if (c == '"') {
              _inner = false;
            }
            continue;
          }
          if (c == '"') {
            _inner = true;
          } else if (c == '{' || c == '[') {
            _depth += 1;
          } else if (c == '}' || c == ']') {
            if (_depth == 0) {
              // The object's own close, after a bare value; a bracket there is not JSON.
              c == '}' ? _at = _At.done : broken = true;
            } else {
              _depth -= 1;
              if (_depth == 0) _at = _At.next;
            }
          } else if (c == ',' && _depth == 0) {
            _at = _At.key;
          }
        case _At.next:
          if (_space(c)) continue;
          if (c == ',') {
            _at = _At.key;
          } else if (c == '}') {
            _at = _At.done;
          } else {
            broken = true;
          }
        case _At.done:
          break;
      }
    }
    _flush(out);
  }

  bool _closed = false;

  /// Hands on the letters read in this piece. A high surrogate at the end waits for its low one in the next piece,
  /// so no half of a letter is ever handed on.
  String _held = '';

  void _flush(StringBuffer out) {
    if (out.isEmpty && _held.isEmpty) return;
    var text = _held + out.toString();
    out.clear();
    _held = '';
    if (_at == _At.string && text.isNotEmpty) {
      final last = text.codeUnitAt(text.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        _held = text.substring(text.length - 1);
        text = text.substring(0, text.length - 1);
      }
    }
    if (text.isEmpty) return;
    if (_at == _At.string) strings[_current] = _value.toString();
    listener?.letters(_current, text);
  }

  /// The letter [c] adds to a string's value, or null when it adds none (part of an escape, or the closing quote,
  /// which sets [_closed]).
  String? _letter(String c) {
    final hex = _hex;
    if (hex != null) {
      final more = hex + c;
      if (more.length < 4) {
        _hex = more;
        return null;
      }
      _hex = null;
      final code = int.tryParse(more, radix: 16);
      if (code == null) {
        broken = true;
        return null;
      }
      return _unit(code);
    }
    if (_escape) {
      _escape = false;
      if (c == 'u') {
        _hex = '';
        return null;
      }
      return _pending(_simple(c) ?? c);
    }
    if (c == r'\') {
      _escape = true;
      return null;
    }
    if (c == '"') {
      _closed = true;
      return null;
    }
    return _pending(c);
  }

  /// A UTF-16 unit from a \u escape: a high surrogate is held until its low one comes, so no half of a letter is
  /// ever handed on.
  String? _unit(int code) {
    if (code >= 0xD800 && code <= 0xDBFF) {
      _high = code;
      return null;
    }
    if (code >= 0xDC00 && code <= 0xDFFF) {
      final high = _high;
      _high = null;
      return high == null ? null : String.fromCharCodes([high, code]);
    }
    return _pending(String.fromCharCode(code));
  }

  /// A letter, after any high surrogate left waiting (which had no low one, and is dropped).
  String _pending(String letter) {
    _high = null;
    return letter;
  }

  static String? _simple(String c) => switch (c) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        'b' => '\b',
        'f' => '\f',
        '"' => '"',
        r'\' => r'\',
        '/' => '/',
        _ => null,
      };

  static bool _space(String c) => c == ' ' || c == '\n' || c == '\r' || c == '\t';
}
