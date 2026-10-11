/// Comments on a note, in the markdown itself (docs/SHARED.md, S8). A port of `src/app/core/comments/format.ts`.
/// (Matt: "leave comments on documents in a common format that renders as a comment on the document as well as
/// allowing for threads on the comment, make this a standard format within the markdown documents themselves".)
///
/// Two parts, both plain text any other app shows as it is:
///
/// - **An anchor** in the prose: `[^c1]` after the words a thread is about, or `==the words==[^c1]` round a
///   selection. It reads as a footnote's marker anywhere else, and the selection as a highlight.
/// - **One fence at the end of the note** holding every thread:
///
///       ```comments
///       c1 matt 2026-10-04T19:00:12Z
///       The venue needs confirming - the hall or the barn?
///         sam 2026-10-04T19:05:40Z
///         The hall. Confirmed this morning.
///         resolved sam 2026-10-04T19:06:02Z
///       ```
///
/// A thread opens with its head line - its id, its author's handle and the time, ISO in UTC - and the comment's
/// words under it on lines of their own. A reply is the same shape indented two spaces, its words indented two as
/// well; a comment's words may run to several lines, each one a line of the fence, and an empty line in what was
/// typed is not kept. `resolved <handle> <time>`, indented two, closes the thread: its words stay, its wash goes. A
/// words line that would read as one of those heads, or that begins with a backslash or three backticks, is
/// written with a backslash in front, which reading takes off again.
///
/// Reading never rewrites. What is read keeps each part's place in the note - its lines and offsets - and every
/// change is a few edits at those places ([Edit]), so an unchanged note reads and writes back as the same text, a
/// fence edited by hand keeps the lines it does not understand, and a malformed entry is kept as the text it is.
///
/// Pure. Offsets are UTF-16 code units, the page's and CodeMirror's, which are a Dart string's own.
///
/// What differs:
/// - [applyEdits] puts two edits AT THE SAME PLACE in the order they were given, as the editor's one dispatch does
///   on the page. The page's own `applyEdits` (its tests' helper) puts the later one first, which for a comment on
///   the last line of a note with no fence yet lands the fence before the anchor; nothing the page ships goes
///   through it, and anything here might.
/// - `withoutAnchors` was already ported with the title rule (lib/core/note_text.dart) and is exported from here.
/// - White space is the page's (`\s`, and `trim` as JavaScript trims) rather than Dart's `trim`, which differs by
///   one character (U+0085).
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

export '../core/note_text.dart' show withoutAnchors;

/// One comment: the thread's first, or a reply (`Comment`).
@immutable
class Comment {
  const Comment({required this.by, required this.at, required this.words, required this.line});

  /// The author's handle, or `me` written without an account (author.dart).
  final String by;

  /// When, as written: ISO 8601 in UTC.
  final String at;

  /// The words, their lines joined by newlines.
  final String words;

  /// The head line, counting from 1.
  final int line;

  @override
  bool operator ==(Object other) => other is Comment && other.by == by && other.at == at && other.words == words && other.line == line;

  @override
  int get hashCode => Object.hash(by, at, words, line);

  @override
  String toString() => 'Comment($by $at line $line: $words)';
}

/// Who closed a thread and when, and the line that says so.
typedef Resolution = ({String by, String at, int line});

/// A thread (`Thread`).
@immutable
class Thread {
  const Thread({required this.id, required this.head, required this.replies, required this.resolved, required this.from, required this.to});
  final String id;

  /// The comment that opened it.
  final Comment head;
  final List<Comment> replies;

  /// Who closed it and when; null while it is open.
  final Resolution? resolved;

  /// The thread's lines in the note, its head's to its last that is its own, counting from 1.
  final int from;
  final int to;
}

/// Where a thread is anchored in the prose (`Anchor`).
@immutable
class Anchor {
  const Anchor({required this.id, required this.from, required this.to, required this.wash});
  final String id;

  /// The `[^c1]` itself, as offsets into the note.
  final int from;
  final int to;

  /// The `==the words==` before it, delimiters included, where the anchor is round a selection; null after the
  /// words.
  final ({int from, int to})? wash;
}

/// The comments fence (`CommentFence`).
@immutable
class CommentFence {
  const CommentFence({required this.open, required this.close, required this.from, required this.to});

  /// The opening line, counting from 1.
  final int open;

  /// The closing line; null for a fence never closed, which runs to the end of the note as CommonMark has it.
  final int? close;

  /// Offsets of the fence's first character and its last line's end.
  final int from;
  final int to;
}

/// A note's comments, read (`NoteComments`).
@immutable
class NoteComments {
  const NoteComments({required this.fence, required this.threads, required this.anchors, required this.strays});

  /// No fence, and so no comments.
  static const NoteComments none = NoteComments(fence: null, threads: [], anchors: [], strays: []);

  final CommentFence? fence;

  /// In the order the fence has them.
  final List<Thread> threads;

  /// In the order the note has them; only anchors whose thread is in the fence.
  final List<Anchor> anchors;

  /// Lines of the fence that are no thread's, counting from 1: kept as they are.
  final List<int> strays;
}

/// A change to the note: offsets into the text it was read from, as CodeMirror's changes are (`Edit`).
@immutable
class Edit {
  const Edit({required this.from, required this.to, required this.insert});
  final int from;
  final int to;
  final String insert;

  @override
  bool operator ==(Object other) => other is Edit && other.from == from && other.to == to && other.insert == insert;

  @override
  int get hashCode => Object.hash(from, to, insert);

  @override
  String toString() => 'Edit($from..$to, ${insert.replaceAll('\n', r'\n')})';
}

/// Who and when, for a new comment, a reply or a resolution (`Stamp`).
@immutable
class Stamp {
  const Stamp({required this.by, required this.at});
  final String by;

  /// ISO 8601 in UTC; [stampNow] writes one.
  final String at;
}

/// An id: `c` and a short tail of letters and digits.
const String _id = 'c[0-9a-z]+';

/// An ISO time, to the minute or finer, in UTC or with an offset.
const String _time = r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})';

/// A handle as a head writes it: no space, and no backslash first, which is how a words line is told from a head.
const String _handle = r'[^\s\\]\S*';
final RegExp _headLine = RegExp('^($_id) ($_handle) ($_time)\\s*\$');
final RegExp _replyLine = RegExp('^  ($_handle) ($_time)\\s*\$');
final RegExp _resolvedLine = RegExp('^(?:  )?resolved ($_handle) ($_time)\\s*\$');
final RegExp _openLine = RegExp(r'^(`{3,}|~{3,})\s*comments\s*$', caseSensitive: false);

/// An anchor in the prose, by its id (`COMMENT_ANCHOR`).
final RegExp commentAnchor = RegExp('\\[\\^($_id)\\]');

final RegExp _space = RegExp(r'\s');
final RegExp _spaceAtEnds = RegExp(r'^\s+|\s+$');
final RegExp _spaceAtEnd = RegExp(r'\s+$');
final RegExp _spaces = RegExp(r'\s+');

/// `String.prototype.trim`, by the page's idea of white space.
String _trim(String text) => text.replaceAll(_spaceAtEnds, '');
String _trimEnd(String text) => text.replaceFirst(_spaceAtEnd, '');

/// `String.prototype.slice` for places that are never negative: clamped to the text, empty when they cross.
String _slice(String text, int from, [int? to]) {
  final start = from.clamp(0, text.length);
  final end = (to ?? text.length).clamp(0, text.length);
  return end <= start ? '' : text.substring(start, end);
}

/// Each line's start offset, and the lines (`linesOf`).
({List<String> lines, List<int> starts}) _linesOf(String body) {
  final lines = body.split('\n');
  final starts = <int>[];
  var at = 0;
  for (final line in lines) {
    starts.add(at);
    at += line.length + 1;
  }
  return (lines: lines, starts: starts);
}

/// A fenced block in the note: its lines, counting from 1, the closing one null for a block never closed.
typedef _Block = ({int open, int? close, bool comments});

final RegExp _blockOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})');

/// Every fenced block in the note, read top to bottom as CommonMark reads them (`blocksOf`): a fence of three or
/// more backticks or tildes, up to three spaces in, closed by the same character at least as long with nothing
/// after it. A ```comments line inside another block - the Guide's own example of one - is that block's words, not
/// a fence.
List<_Block> _blocksOf(List<String> lines) {
  final blocks = <_Block>[];
  for (var i = 0; i < lines.length; i += 1) {
    final text = lines[i];
    final open = _blockOpen.firstMatch(text);
    if (open == null) continue;
    final mark = open[1]!;
    final close = RegExp('^\\s{0,3}${mark[0] == '~' ? '~' : '`'}{${mark.length},}\\s*\$');
    int? end;
    for (var j = i + 1; j < lines.length; j += 1) {
      if (close.hasMatch(lines[j])) {
        end = j;
        break;
      }
    }
    blocks.add((open: i + 1, close: end == null ? null : end + 1, comments: _openLine.hasMatch(text)));
    if (end == null) break;
    i = end;
  }
  return blocks;
}

/// The comments fence: the last one in the note, since it is kept at the end and an earlier one may be an example
/// (`fenceOf`).
CommentFence? _fenceOf(List<_Block> blocks, List<String> lines, List<int> starts) {
  _Block? block;
  for (final each in blocks.reversed) {
    if (each.comments) {
      block = each;
      break;
    }
  }
  if (block == null) return null;
  final last = (block.close ?? lines.length) - 1;
  return CommentFence(open: block.open, close: block.close, from: starts[block.open - 1], to: starts[last] + lines[last].length);
}

/// A words line as written: its backslash taken off.
String _unescape(String line) => line.startsWith(r'\') ? line.substring(1) : line;

/// A comment while its words are still being read.
class _Reading {
  _Reading(this.by, this.at, this.line);
  final String by;
  final String at;
  final int line;
  String words = '';

  Comment get done => Comment(by: by, at: at, words: words, line: line);
}

class _ThreadReading {
  _ThreadReading(this.id, this.head) : to = head.line;
  final String id;
  final _Reading head;
  final List<_Reading> replies = [];
  Resolution? resolved;
  int to;

  Thread get done => Thread(id: id, head: head.done, replies: [for (final reply in replies) reply.done], resolved: resolved, from: head.line, to: to);
}

/// The threads in a fence's lines, and the lines that are no thread's (`threadsOf`).
({List<Thread> threads, List<int> strays}) _threadsOf(List<String> lines, CommentFence fence) {
  final threads = <_ThreadReading>[];
  final strays = <int>[];
  _ThreadReading? thread;

  /// The comment words are being read for: the head, a reply, or none after a resolution.
  _Reading? current;
  final last = fence.close == null ? lines.length : fence.close! - 1;
  for (var n = fence.open + 1; n <= last; n += 1) {
    final text = lines[n - 1];
    final head = _headLine.firstMatch(text);
    if (head != null) {
      current = _Reading(head[2]!, head[3]!, n);
      thread = _ThreadReading(head[1]!, current);
      threads.add(thread);
      continue;
    }
    if (thread == null) {
      strays.add(n);
      continue;
    }
    final resolved = _resolvedLine.firstMatch(text);
    if (resolved != null) {
      thread.resolved = (by: resolved[1]!, at: resolved[2]!, line: n);
      thread.to = n;
      current = null;
      continue;
    }
    final reply = _replyLine.firstMatch(text);
    if (reply != null) {
      current = _Reading(reply[1]!, reply[2]!, n);
      thread.replies.add(current);
      thread.to = n;
      continue;
    }
    // A comment's words: unindented under the head before any reply, indented two under a reply.
    final isHead = current != null && identical(current, thread.head);
    final isReply = current != null && !isHead;
    if (_trim(text).isNotEmpty && ((isHead && !text.startsWith(' ')) || (isReply && text.startsWith('  ')))) {
      final words = _unescape(isReply ? text.substring(2) : text);
      current.words = current.words.isNotEmpty ? '${current.words}\n$words' : words;
      thread.to = n;
      continue;
    }
    strays.add(n);
  }
  return (threads: [for (final each in threads) each.done], strays: strays);
}

/// The lines inside a fenced block other than the comments fence, counting from 1: their brackets are code
/// (`codeLines`).
Set<int> _codeLines(List<_Block> blocks, CommentFence? fence, int total) {
  final code = <int>{};
  for (final block in blocks) {
    if (fence != null && block.open == fence.open) continue;
    for (var n = block.open; n <= (block.close ?? total); n += 1) {
      code.add(n);
    }
  }
  return code;
}

/// The `==words==` that ends where an anchor starts, on the same line (`washBefore`): the opening `==` nearest
/// before it with words between that do not start or end with a space, as a highlight's do.
({int from, int to})? _washBefore(String line, int lineFrom, int at) {
  final end = at - lineFrom;
  if (end < 4 || _slice(line, end - 2, end) != '==') return null;
  final open = line.lastIndexOf('==', end - 3);
  if (open < 0) return null;
  final words = _slice(line, open + 2, end - 2);
  if (words.isEmpty || words.startsWith(_space) || _space.hasMatch(words[words.length - 1]) || words.contains('==')) return null;
  return (from: lineFrom + open, to: lineFrom + end);
}

/// Every thread in the note's comments fence, and every anchor to one of them (`readComments`).
NoteComments readComments(String body) {
  final (:lines, :starts) = _linesOf(body);
  final blocks = _blocksOf(lines);
  final fence = _fenceOf(blocks, lines, starts);
  if (fence == null) return NoteComments.none;
  final (:threads, :strays) = _threadsOf(lines, fence);
  final ids = {for (final thread in threads) thread.id};
  final code = _codeLines(blocks, fence, lines.length);
  final anchors = <Anchor>[];
  for (var i = 0; i < fence.open - 1; i += 1) {
    if (code.contains(i + 1)) continue;
    final line = lines[i];
    final lineFrom = starts[i];
    for (final match in commentAnchor.allMatches(line)) {
      final id = match[1]!;
      // `[^c1]:` at the start of a line is a footnote's definition, not an anchor.
      if (!ids.contains(id) || (line.substring(match.end).startsWith(':') && _trim(line.substring(0, match.start)).isEmpty)) continue;
      final from = lineFrom + match.start;
      anchors.add(Anchor(id: id, from: from, to: from + (match.end - match.start), wash: _washBefore(line, lineFrom, from)));
    }
  }
  return NoteComments(fence: fence, threads: threads, anchors: anchors, strays: strays);
}

/// The thread by its id: the first, should a hand-edited fence say one twice (`threadOf`).
Thread? threadOf(NoteComments comments, String id) {
  for (final thread in comments.threads) {
    if (thread.id == id) return thread;
  }
  return null;
}

/// The edits applied to the text they were made against, for a test or a write outside the editor (`applyEdits`).
/// Two edits at the same place land in the order they were given (see the header).
String applyEdits(String body, List<Edit> edits) {
  final placed = edits.indexed.toList()
    ..sort((a, b) {
      final from = b.$2.from.compareTo(a.$2.from);
      if (from != 0) return from;
      final to = b.$2.to.compareTo(a.$2.to);
      return to != 0 ? to : b.$1.compareTo(a.$1);
    });
  var out = body;
  for (final (_, edit) in placed) {
    out = _slice(out, 0, edit.from) + edit.insert + _slice(out, edit.to);
  }
  return out;
}

/// Now, as a comment's time is written: ISO in UTC, to the second (`stampNow`).
String stampNow([DateTime? now]) {
  final at = (now ?? DateTime.now()).toUtc();
  return '${DateTime.utc(at.year, at.month, at.day, at.hour, at.minute, at.second).toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), '')}Z';
}

/// Whether a words line would be read as something else, and so is written behind a backslash (`needsEscape`).
bool _needsEscape(String line) =>
    line.startsWith(r'\') || line.startsWith('```') || line.startsWith('~~~') || _headLine.hasMatch(line) || _resolvedLine.hasMatch(line) || _replyLine.hasMatch('  $line');

/// Typed words as a comment's lines: each trimmed, empty ones left out, any that would misread escaped
/// (`wordLines`).
List<String> _wordLines(String words, String indent) => [
      for (final line in words.split('\n').map(_trim))
        if (line.isNotEmpty) '$indent${_needsEscape(line) ? '\\$line' : line}',
    ];

/// Whether [by] can head a line: a handle, with no space in it (`handleOf`).
String _handleOf(String by) {
  final handle = by.replaceAll(_spaces, '-');
  return handle.isEmpty ? 'me' : handle;
}

final Random _dice = Random();
final RegExp _footnotes = RegExp(r'\[\^([^\]\s]+)\]');
final RegExp _heads = RegExp('^($_id) ', multiLine: true);
const String _tails = '0123456789abcdefghijklmnopqrstuvwxyz';

/// A fresh id: `c` and four letters or digits, none this note has used for a thread, an anchor or a footnote
/// (`freshId`). [random] answers a number from 0 up to, not including, 1, as `Math.random` does.
String freshId(String body, [double Function()? random]) {
  final roll = random ?? _dice.nextDouble;
  final taken = <String>{
    for (final match in _footnotes.allMatches(body)) match[1]!,
    for (final match in _heads.allMatches(body)) match[1]!,
  };
  for (var tries = 0;; tries += 1) {
    final length = 4 + tries ~/ 50;
    final tail = StringBuffer();
    for (var i = 0; i < length; i += 1) {
      final at = (roll() * 36).floor();
      tail.write(at >= 0 && at < 36 ? _tails[at] : '0');
    }
    final id = 'c$tail';
    if (!taken.contains(id)) return id;
  }
}

/// The edit that puts [lines] into the fence as its last lines, or makes the fence at the note's end to hold them
/// (`intoFence`).
Edit _intoFence(String body, NoteComments comments, List<String> lines) {
  final text = lines.join('\n');
  final fence = comments.fence;
  if (fence != null && fence.close != null) {
    final starts = _linesOf(body).starts;
    final at = fence.close! - 1 < starts.length ? starts[fence.close! - 1] : body.length;
    return Edit(from: at, to: at, insert: '$text\n');
  }
  if (fence != null) return Edit(from: body.length, to: body.length, insert: '${body.endsWith('\n') ? '' : '\n'}$text');
  // A blank line between the words and the fence, as a fence is set off anywhere.
  final lead = body.isEmpty ? '' : (body.endsWith('\n\n') ? '' : (body.endsWith('\n') ? '\n' : '\n\n'));
  return Edit(from: body.length, to: body.length, insert: '$lead```comments\n$text\n```\n');
}

/// Where a new thread is anchored: round a stretch of the note, or after the words of a line (`Target`).
@immutable
sealed class Target {
  const Target();

  /// Round the stretch of the note from [from] to [to].
  const factory Target.span(int from, int to) = SpanTarget;

  /// After the words of line [line], counting from 1.
  const factory Target.line(int line) = LineTarget;
}

class SpanTarget extends Target {
  const SpanTarget(this.from, this.to);
  final int from;
  final int to;
}

class LineTarget extends Target {
  const LineTarget(this.line);
  final int line;
}

/// A new thread: its anchor in the prose and its entry in the fence (`addThread`). Round a selection,
/// `==the words==[^id]`, when the selection is words on one line; a selection over several lines, or one that is
/// already a highlight, is anchored after its words without a wash of its own. After a line's words, `[^id]`, for a
/// line. Null where there are no words to say or nowhere to anchor them: in the fence itself, or past the note.
List<Edit>? addThread(String body, Target target, Stamp stamp, String words, [String? id]) {
  final lines = _wordLines(words, '');
  if (lines.isEmpty) return null;
  final threadId = id ?? freshId(body);
  final comments = readComments(body);
  final (lines: noteLines, :starts) = _linesOf(body);
  final anchor = '[^$threadId]';
  final edits = <Edit>[];
  bool inFence(int pos) => comments.fence != null && pos >= comments.fence!.from;
  switch (target) {
    case LineTarget(:final line):
      if (line < 1 || line > noteLines.length) return null;
      final end = starts[line - 1] + _trimEnd(noteLines[line - 1]).length;
      if (inFence(end)) return null;
      edits.add(Edit(from: end, to: end, insert: anchor));
    case SpanTarget():
      var from = target.from, to = target.to;
      if (from > to) (from, to) = (to, from);
      from = from < 0 ? 0 : from;
      to = to > body.length ? body.length : to;
      // Whitespace at either end is not what was meant, and a highlight cannot start or end with it.
      while (from < to && _space.hasMatch(body[from])) {
        from += 1;
      }
      while (to > from && _space.hasMatch(body[to - 1])) {
        to -= 1;
      }
      if (inFence(from) || inFence(to)) return null;
      final picked = _slice(body, from, to);
      final n = _slice(body, 0, to).split('\n').length;
      final lineFrom = starts[n - 1];
      final text = noteLines[n - 1];
      // Inside a highlight already (an odd number of `==` before it on its line): that highlight is the wash, and
      // the anchor goes after its closing marks rather than a highlight being opened inside another.
      final inside = !picked.contains('\n') && (_slice(text, 0, from - lineFrom).split('==').length - 1) % 2 == 1;
      final closing = inside ? text.indexOf('==', (to - lineFrom).clamp(0, text.length)) : -1;
      if (picked.length > 4 && picked.startsWith('==') && picked.endsWith('==') && !picked.contains('\n') && !_slice(picked, 2, picked.length - 2).contains('==')) {
        // A highlight picked whole: it is the wash.
        edits.add(Edit(from: to, to: to, insert: anchor));
      } else if (closing >= 0) {
        final at = lineFrom + closing + 2;
        edits.add(Edit(from: at, to: at, insert: anchor));
      } else if (picked.isEmpty || picked.contains('\n') || picked.contains('==')) {
        // Words over several lines, or none: after the words of the line where the selection ends.
        final at = lineFrom + _trimEnd(text).length;
        edits.add(Edit(from: at, to: at, insert: anchor));
      } else {
        edits
          ..add(Edit(from: from, to: from, insert: '=='))
          ..add(Edit(from: to, to: to, insert: '==$anchor'));
      }
  }
  edits.add(_intoFence(body, comments, ['$threadId ${_handleOf(stamp.by)} ${stamp.at}', ...lines]));
  return edits;
}

/// The offset at the end of line [n] (from 1), its line break after it (`afterLine`).
int _afterLine(String body, int n) {
  final (:lines, :starts) = _linesOf(body);
  return n >= 1 && n <= lines.length ? starts[n - 1] + lines[n - 1].length : 0;
}

/// A reply under a thread, after its last comment and before its resolution, if it has one (`addReply`). Null for
/// no words or no thread.
List<Edit>? addReply(String body, String id, Stamp stamp, String words) {
  final lines = _wordLines(words, '  ');
  final thread = threadOf(readComments(body), id);
  if (lines.isEmpty || thread == null) return null;
  final text = ['  ${_handleOf(stamp.by)} ${stamp.at}', ...lines].join('\n');
  final resolved = thread.resolved;
  if (resolved != null) {
    final at = _linesOf(body).starts[resolved.line - 1];
    return [Edit(from: at, to: at, insert: '$text\n')];
  }
  final at = _afterLine(body, thread.to);
  return [Edit(from: at, to: at, insert: '\n$text')];
}

/// The thread closed: `resolved <handle> <time>` under it (`resolveThread`). Nothing for a thread already closed,
/// or none.
List<Edit>? resolveThread(String body, String id, Stamp stamp) {
  final thread = threadOf(readComments(body), id);
  if (thread == null || thread.resolved != null) return null;
  final at = _afterLine(body, thread.to);
  return [Edit(from: at, to: at, insert: '\n  resolved ${_handleOf(stamp.by)} ${stamp.at}')];
}

/// The lines from the first's start to the next one's after the last, or back to the end of the line before for the
/// note's last line (`wholeLines`).
Edit _wholeLines(String body, int first, int last) {
  final (:lines, :starts) = _linesOf(body);
  final from = starts[first - 1];
  if (last < lines.length) return Edit(from: from, to: starts[last], insert: '');
  return Edit(from: from - 1 < 0 ? 0 : from - 1, to: body.length, insert: '');
}

/// The thread open again: its resolution's line taken out (`reopenThread`). Nothing for a thread that is open, or
/// none.
List<Edit>? reopenThread(String body, String id) {
  final resolved = threadOf(readComments(body), id)?.resolved;
  if (resolved == null) return null;
  return [_wholeLines(body, resolved.line, resolved.line)];
}

/// The thread gone (`deleteThread`): its lines out of the fence, and every anchor to it out of the prose, a wash's
/// `==` with it so the words are as they were before the comment. The fence goes too when nothing is left in it,
/// with the blank line it was set off by. Lines in the fence that were no thread's stay.
List<Edit>? deleteThread(String body, String id) {
  final comments = readComments(body);
  final thread = threadOf(comments, id);
  final fence = comments.fence;
  if (thread == null || fence == null) return null;
  final edits = <Edit>[];
  for (final anchor in comments.anchors) {
    if (anchor.id != id) continue;
    final wash = anchor.wash;
    if (wash != null) {
      edits
        ..add(Edit(from: wash.from, to: wash.from + 2, insert: ''))
        ..add(Edit(from: wash.to - 2, to: anchor.to, insert: ''));
    } else {
      edits.add(Edit(from: anchor.from, to: anchor.to, insert: ''));
    }
  }
  final others = comments.threads.where((each) => !identical(each, thread));
  final lines = _linesOf(body).lines;
  if (others.isEmpty && !comments.strays.any((n) => _trim(lines[n - 1]).isNotEmpty)) {
    // Nothing left: the fence and the blank lines before it, back to the words' last line.
    var from = fence.from;
    while (from > 0 && body[from - 1] == '\n') {
      from -= 1;
    }
    final tail = _slice(body, fence.to);
    edits.add(Edit(from: from, to: fence.to + (tail.startsWith('\n') ? 1 : 0), insert: from > 0 && tail.startsWith('\n') ? '\n' : ''));
    return edits;
  }
  edits.add(_wholeLines(body, thread.from, thread.to));
  return edits;
}

/// How many threads the note has, and how many of them are open (`threadCounts`).
({int threads, int open}) threadCounts(List<Thread> threads) => (threads: threads.length, open: threads.where((thread) => thread.resolved == null).length);

/// "3 comments, 1 open", or null for none: the More sheet's line (`countWords`).
String? countWords(List<Thread> threads) {
  final (threads: all, :open) = threadCounts(threads);
  if (all == 0) return null;
  if (all == 1) return open > 0 ? '1 comment, open' : '1 comment, resolved';
  final said = '$all comments';
  if (open == all) return '$said, all open';
  return open > 0 ? '$said, $open open' : '$said, all resolved';
}

/// Each person's comments and replies, by handle (`countsBy`; S8: "a member's profile card counts their comments
/// and replies"): from parsed threads, not the fence's text, so a canvas's threads are counted the same way.
Map<String, ({int comments, int replies})> countsBy(List<Thread> threads) {
  final counts = <String, ({int comments, int replies})>{};
  for (final thread in threads) {
    final head = counts[thread.head.by] ?? (comments: 0, replies: 0);
    counts[thread.head.by] = (comments: head.comments + 1, replies: head.replies);
    for (final reply in thread.replies) {
      final was = counts[reply.by] ?? (comments: 0, replies: 0);
      counts[reply.by] = (comments: was.comments, replies: was.replies + 1);
    }
  }
  return counts;
}
