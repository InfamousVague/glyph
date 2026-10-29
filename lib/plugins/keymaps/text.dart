/// What the Keyboard modes plugin's engines (vim.dart, emacs.dart) work on: a text and its selection, with the few
/// things only the editor can do (undo, save, close, a line up or down as the text is laid out) asked of it. The
/// editor's own is lib/plugins/keymaps/editor_keys.dart `EditorKeyText`; [StringKeyText] is a plain string's, for the
/// engines' tests and for anything else that types without an editor.
///
/// And the questions both engines ask of a text: where a line starts and ends, its first letter, and which of three
/// kinds a character is (a space, a word's letter, anything else), as Vim and Emacs both split words.
library;

/// One replacement, in the text as it was before: [from] to [to] become [insert].
typedef KeyEdit = ({int from, int to, String insert});

/// A text an engine edits.
abstract interface class KeyText {
  /// The whole text, as it is now.
  String get text;

  /// The selection: where it was begun, and where its moving end (the caret) is.
  int get anchor;
  int get head;

  /// A text that may not be changed (a note in the Trash): the engines move and select, and change nothing.
  bool get readOnly;

  /// One level of indentation (`>>`).
  String get indentUnit;

  /// Selects [anchor] to [head]; a caret where they are the same.
  void select(int anchor, int head);

  /// Makes [edits] as one change, one step of the undo, the caret at [caret] in the text after. The edits are in the
  /// text before, in order and apart.
  void change(List<KeyEdit> edits, int caret);

  /// The undo's step back and forward; false where there was none.
  bool undo();
  bool redo();

  /// Saves the text now, and closes it (`:w`, `:q`, `C-x C-s`).
  void save();
  void close();

  /// Moves the caret a line down ([forward]) or up as the lines are drawn, keeping its place across; [extend] keeps
  /// the selection's anchor where it is. False where there is no line to go to.
  bool vertical(bool forward, {required bool extend});
}

/// A plain string as a [KeyText], with an undo of its own and a record of what was saved and closed.
class StringKeyText implements KeyText {
  StringKeyText(this.text, {int? caret, int? anchor, this.indentUnit = '  ', this.readOnly = false}) : head = caret ?? 0, anchor = anchor ?? caret ?? 0;

  @override
  String text;

  @override
  int anchor;

  @override
  int head;

  @override
  final String indentUnit;

  @override
  bool readOnly;

  /// How many times [save] and [close] were asked.
  int saves = 0;
  int closes = 0;

  final List<(String, int, int)> _undone = [], _redone = [];

  /// The selected words: `text` between the selection's ends.
  String get selected => text.substring(anchor < head ? anchor : head, anchor < head ? head : anchor);

  @override
  void select(int anchor, int head) {
    this.anchor = anchor.clamp(0, text.length);
    this.head = head.clamp(0, text.length);
  }

  @override
  void change(List<KeyEdit> edits, int caret) {
    _undone.add((text, anchor, head));
    _redone.clear();
    var next = text;
    for (final edit in edits.reversed) {
      next = next.replaceRange(edit.from, edit.to, edit.insert);
    }
    text = next;
    select(caret, caret);
  }

  /// Types [words] over the selection, as a keyboard does: one step of the undo.
  void type(String words) {
    final from = anchor < head ? anchor : head, to = anchor < head ? head : anchor;
    change([(from: from, to: to, insert: words)], from + words.length);
  }

  @override
  bool undo() {
    if (_undone.isEmpty) return false;
    _redone.add((text, anchor, head));
    final (was, a, h) = _undone.removeLast();
    text = was;
    select(a, h);
    return true;
  }

  @override
  bool redo() {
    if (_redone.isEmpty) return false;
    _undone.add((text, anchor, head));
    final (was, a, h) = _redone.removeLast();
    text = was;
    select(a, h);
    return true;
  }

  @override
  void save() => saves++;

  @override
  void close() => closes++;

  /// By the text's own lines: a string has no layout.
  @override
  bool vertical(bool forward, {required bool extend}) {
    final start = startOfLine(text, head), column = head - start;
    final int to;
    if (forward) {
      final end = endOfLine(text, head);
      if (end >= text.length) return false;
      to = (end + 1 + column).clamp(end + 1, endOfLine(text, end + 1));
    } else {
      if (start == 0) return false;
      final above = startOfLine(text, start - 1);
      to = (above + column).clamp(above, start - 1);
    }
    select(extend ? anchor : to, to);
    return true;
  }
}

/// Where the line [pos] is on starts.
int startOfLine(String t, int pos) => pos <= 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;

/// Where the line [pos] is on ends: its line break, or the text's end.
int endOfLine(String t, int pos) {
  final at = t.indexOf('\n', pos < 0 ? 0 : pos);
  return at < 0 ? t.length : at;
}

/// The line's first character that is not a space or a tab; its end where it has none.
int firstNonBlank(String t, int pos) {
  var i = startOfLine(t, pos);
  final end = endOfLine(t, pos);
  while (i < end && (t.codeUnitAt(i) == 0x20 || t.codeUnitAt(i) == 0x09)) {
    i++;
  }
  return i;
}

/// The 1-based number of the line [pos] is on, and the start of line [number] (the last line's where there are fewer).
int lineNumberAt(String t, int pos) => '\n'.allMatches(t.substring(0, pos.clamp(0, t.length))).length + 1;
int startOfLineNumber(String t, int number) {
  var at = 0;
  for (var line = 1; line < number; line++) {
    final next = t.indexOf('\n', at);
    if (next < 0) break;
    at = next + 1;
  }
  return at;
}

final RegExp _letter = RegExp(r'[\p{L}\p{N}\p{M}_]', unicode: true);

bool isBlank(int unit) => unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0;

/// A word's letter: a letter or a digit of any script, or `_`.
bool isWordUnit(int unit) {
  if (unit < 0x80) return (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F;
  return _letter.hasMatch(String.fromCharCode(unit));
}

/// The character at [i]'s kind: 0 a space (a line break too), 1 a word's letter, 2 anything else; with [big] (Vim's
/// WORD), everything not a space is 1.
int charKind(String t, int i, {bool big = false}) {
  final unit = t.codeUnitAt(i);
  if (isBlank(unit)) return 0;
  if (big) return 1;
  return isWordUnit(unit) ? 1 : 2;
}
