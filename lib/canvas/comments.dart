/// A canvas's comment threads (docs/SHARED.md, S9): a `comments` array in its JSON, a thread each, anchored to a
/// card by its id. A port of `src/app/canvas/comments.ts`. Every change here is a new canvas, as every other edit
/// is (edits.dart): the view hands it back whole.
///
/// What differs:
/// - `threadsOf` answered the note's own `CardThread` (editor/CommentCard.tsx), which has no port yet; [CardThread]
///   here is that shape as a record, for whoever ports the comment sheet.
/// - Threads are ordered by their stamps as strings, unit by unit, where the web asked `localeCompare`: the same
///   order for ISO stamps and for ids of lower-case letters and digits, which is what both are.
library;

import 'dart:math' as math;

import '../comments/format.dart' show Stamp;
import 'card_looks.dart';
import 'json_canvas.dart';

typedef CardWords = ({String by, String at, String words});
typedef CardThread = ({String id, CardWords head, List<CardWords> replies, ({String by, String at})? resolved});

int _oldestFirst(CanvasComment a, CanvasComment b) {
  final at = a.at.compareTo(b.at);
  return at != 0 ? at : a.id.compareTo(b.id);
}

List<CanvasComment> _sorted(Iterable<CanvasComment> threads) {
  final list = threads.toList();
  // Insertion sort: stable, as the web's sort is.
  for (var i = 1; i < list.length; i += 1) {
    final each = list[i];
    var j = i - 1;
    while (j >= 0 && _oldestFirst(list[j], each) > 0) {
      list[j + 1] = list[j];
      j -= 1;
    }
    list[j + 1] = each;
  }
  return list;
}

/// The threads as the card draws them, oldest first.
List<CardThread> threadsOf(Canvas canvas) => [
  for (final thread in _sorted(canvas.comments ?? const []))
    (
      id: thread.id,
      head: (by: thread.by, at: thread.at, words: thread.text),
      replies: [for (final reply in thread.replies) (by: reply.by, at: reply.at, words: reply.text)],
      resolved: thread.resolved,
    ),
];

/// The threads on one card, oldest first.
List<CanvasComment> threadsOn(Canvas canvas, String nodeId) => _sorted((canvas.comments ?? const <CanvasComment>[]).where((thread) => thread.node == nodeId));

/// What a card's threads say: how many are open, and who started the first open one (or the first), for the
/// round's colour.
({int count, int open, String by})? markOf(Canvas canvas, String nodeId) {
  final on = threadsOn(canvas, nodeId);
  if (on.isEmpty) return null;
  final open = on.where((thread) => thread.resolved == null).toList();
  return (count: on.length, open: open.length, by: (open.isEmpty ? on.first : open.first).by);
}

String _firstLine(CanvasNode node) => switch (node.type) {
  NodeType.text => node.text.split('\n').map((each) => each.trim()).firstWhere((each) => each.isNotEmpty, orElse: () => ''),
  NodeType.group => node.label ?? '',
  NodeType.link => node.url,
  NodeType.file => fileTitle(node.file),
};

/// The words a thread is about: the card's first line, its name, its address or its note's title; null for
/// nothing to quote.
String? quoteOf(Canvas canvas, String nodeId) {
  final node = canvas.nodeOf(nodeId);
  if (node == null) return null;
  final line = _firstLine(node);
  if (line.isEmpty) return null;
  return line.length > 90 ? '${line.substring(0, 89).trimRight()}…' : line;
}

const String _letters = '0123456789abcdefghijklmnopqrstuvwxyz';
final math.Random _dice = math.Random();

/// An id a canvas's thread is called by: `c` and a short tail, none it has already.
String freshThreadId(Canvas canvas, [double Function()? random]) {
  final roll = random ?? _dice.nextDouble;
  final taken = {for (final thread in canvas.comments ?? const <CanvasComment>[]) thread.id};
  for (var tries = 0; ; tries += 1) {
    final length = 4 + tries ~/ 50;
    final tail = StringBuffer();
    for (var i = 0; i < length; i += 1) {
      final at = (roll() * 36).floor();
      tail.write(at >= 0 && at < 36 ? _letters[at] : '0');
    }
    final id = 'c$tail';
    if (!taken.contains(id)) return id;
  }
}

/// A thread started on a card; null for a card that is not there, or no words.
Canvas? withThread(Canvas canvas, String nodeId, Stamp stamp, String text, [String? id]) {
  final words = text.trim();
  if (words.isEmpty || canvas.nodeOf(nodeId) == null) return null;
  final thread = CanvasComment({'id': id ?? freshThreadId(canvas), 'node': nodeId, 'by': stamp.by, 'at': stamp.at, 'text': words, 'replies': const <Object?>[]});
  return Canvas(nodes: canvas.nodes, edges: canvas.edges, comments: [...?canvas.comments, thread]);
}

/// A reply under a thread; null for a thread that is not there, or no words.
Canvas? withReply(Canvas canvas, String id, Stamp stamp, String text) {
  final words = text.trim();
  if (words.isEmpty) return null;
  return _changed(canvas, id, (thread) => thread.put({
    'replies': [
      ...thread.fields['replies']! as List,
      {'by': stamp.by, 'at': stamp.at, 'text': words},
    ],
  }));
}

Canvas? resolvedThread(Canvas canvas, String id, Stamp stamp) => _changed(canvas, id, (thread) => thread.put({
  'resolved': {'by': stamp.by, 'at': stamp.at},
}));

Canvas? reopenedThread(Canvas canvas, String id) => _changed(canvas, id, (thread) => thread.without('resolved'));

/// A thread taken off; null for one that is not there.
Canvas? withoutThread(Canvas canvas, String id) {
  final comments = canvas.comments;
  if (comments == null || !comments.any((thread) => thread.id == id)) return null;
  final left = [
    for (final thread in comments)
      if (thread.id != id) thread,
  ];
  return Canvas(nodes: canvas.nodes, edges: canvas.edges, comments: left.isEmpty ? null : left);
}

Canvas? _changed(Canvas canvas, String id, CanvasComment Function(CanvasComment thread) change) {
  final comments = canvas.comments;
  if (comments == null || !comments.any((thread) => thread.id == id)) return null;
  return Canvas(nodes: canvas.nodes, edges: canvas.edges, comments: [for (final thread in comments) thread.id == id ? change(thread) : thread]);
}
