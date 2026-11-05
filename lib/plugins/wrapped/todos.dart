/// The to-dos Wrapped lists as unfinished, read from a note's words, and the two changes a press makes to one: checked
/// off (`- [ ]` made `- [x]`) or taken out of its note. Pure: actions.dart writes what these answer through the
/// library, over the revision that was read.
///
/// A to-do is a list item with an open box, outside a code fence and the front matter, with words after the box. Its
/// [WrappedTodo.key] is its note and its words, so a dismissal ("Keep") holds while the line stays as it is, wherever
/// it moves in the note.
library;

import 'package:flutter/foundation.dart';

import '../../core/front_matter.dart' show frontMatterEnd;
import '../note_decay/ai.dart' show stableHash;

final RegExp _open = RegExp(r'^(\s*(?:[-*+]|\d+[.)])\s+)\[ \](\s+)(\S.*)$');
final RegExp _done = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+\[[xX]\](\s+|$)');
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// One open to-do in a note.
@immutable
class WrappedTodo {
  const WrappedTodo({required this.noteId, required this.line, required this.text, required this.words});

  final String noteId;

  /// Its line in the note, from 0, as it was read.
  final int line;

  /// The whole line as written.
  final String text;

  /// Its words after the box.
  final String words;

  /// The note and its words: what Keep is remembered by.
  String get key => '$noteId|${stableHash(words.trim())}';
}

/// Every line of [body] outside its front matter and its code fences, with its number.
Iterable<(int, String)> _lines(List<String> lines) sync* {
  var fenced = false;
  for (var i = frontMatterEnd(lines); i < lines.length; i += 1) {
    final line = lines[i];
    if (_fence.hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (!fenced) yield (i, line);
  }
}

/// The open to-dos of [body], note [noteId]'s, head to foot.
List<WrappedTodo> openTodos(String noteId, String body) => [
      for (final (i, line) in _lines(body.split('\n')))
        if (_open.firstMatch(line) case final m?) WrappedTodo(noteId: noteId, line: i, text: line, words: m.group(3)!),
    ];

/// How many to-dos [body] has, done and open.
({int done, int open}) todoCounts(String body) {
  var done = 0, open = 0;
  for (final (_, line) in _lines(body.split('\n'))) {
    if (_open.hasMatch(line)) {
      open += 1;
    } else if (_done.hasMatch(line)) {
      done += 1;
    }
  }
  return (done: done, open: open);
}

/// The line [todo] is at in [body] now: where it was read, or where the same line moved to; null where it is gone.
int? lineOfTodo(String body, WrappedTodo todo) {
  final lines = body.split('\n');
  if (todo.line < lines.length && lines[todo.line] == todo.text) return todo.line;
  final at = lines.indexOf(todo.text);
  return at < 0 ? null : at;
}

/// [body] with [todos] checked off; null where none of them is still there.
String? checkedOff(String body, Iterable<WrappedTodo> todos) {
  final lines = body.split('\n');
  var changed = false;
  for (final todo in todos) {
    final at = lineOfTodo(lines.join('\n'), todo);
    if (at == null) continue;
    final m = _open.firstMatch(lines[at]);
    if (m == null) continue;
    lines[at] = '${m.group(1)}[x]${m.group(2)}${m.group(3)}';
    changed = true;
  }
  return changed ? lines.join('\n') : null;
}

/// [body] without [todos]' lines; null where none of them is still there.
String? withoutTodos(String body, Iterable<WrappedTodo> todos) {
  final lines = body.split('\n');
  final drop = <int>{};
  for (final todo in todos) {
    final at = lineOfTodo(body, todo);
    if (at != null) drop.add(at);
  }
  if (drop.isEmpty) return null;
  return [for (var i = 0; i < lines.length; i += 1) if (!drop.contains(i)) lines[i]].join('\n');
}
