/// JSON Canvas (jsoncanvas.org, 1.0), the open format Obsidian's canvas is written in, read and written as it is.
/// A port of `src/app/canvas/jsonCanvas.ts`: the format, and the note that holds it (front matter naming it, then
/// the JSON and nothing else). What is made and changed on a canvas is edits.dart, where things are geometry.dart,
/// how lines run lines.dart, and what the screen makes of a node card_looks.dart.
///
/// Read leniently, written exactly: a node or edge that is not what the spec says is left out rather than the whole
/// canvas refused; what is kept is written back with only the fields the spec names, so a round trip changes
/// nothing a person meant.
///
/// What differs from the web:
/// - A JavaScript object is its fields in the order they were set, and `JSON.stringify` writes them in that order.
///   So a node here is that too: [CanvasRecord.fields], a map in insertion order, with the typed getters over it.
///   A field changed keeps its place and a field taken off and put back goes last (`put`, `without`), as
///   `{ ...node, x }` and `{ ...rest, label }` do, which is what makes the file come out byte for byte
///   (tool/canvas_fixtures.mjs, test/canvas/fixtures_test.dart).
/// - Two records are equal when their fields are, in any order, which is what the web's tests mean by `toEqual`.
/// - Numbers are doubles, as JavaScript's are, and written as JavaScript writes them (js.dart).
library;

import 'dart:convert';

import '../core/front_matter.dart';
import 'geometry.dart';
import 'js.dart';

/// The spec's colour: one of six presets, "1" to "6", or a hex colour like "#FF0000".
typedef CanvasColor = String;

enum Side { top, right, bottom, left }

enum End { none, arrow }

enum NodeType { text, file, link, group }

/// Whether two values of a file are the same: maps by their fields in any order, lists in theirs.
bool sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (!sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _hash(Object? value) {
  if (value is Map) return Object.hashAllUnordered(value.entries.map((e) => Object.hash(e.key, _hash(e.value))));
  if (value is List) return Object.hashAll(value.map(_hash));
  return value.hashCode;
}

T? _named<T extends Enum>(List<T> values, Object? name) {
  for (final each in values) {
    if (each.name == name) return each;
  }
  return null;
}

/// One object of the file: its fields as JSON holds them (strings, numbers, lists and maps of those), in the order
/// they were set.
abstract class CanvasRecord {
  CanvasRecord(Map<String, Object?> fields) : fields = Map.unmodifiable(fields);

  final Map<String, Object?> fields;

  String? _s(String key) => fields[key] as String?;
  double _d(String key) => (fields[key]! as num).toDouble();

  /// `{ ...this, ...changes }`: a field already there keeps its place, a new one goes last.
  Map<String, Object?> _put(Map<String, Object?> changes) => {...fields, ...changes};

  /// The fields without [key].
  Map<String, Object?> _without(String key) => {
    for (final entry in fields.entries)
      if (entry.key != key) entry.key: entry.value,
  };

  @override
  bool operator ==(Object other) => other is CanvasRecord && other.runtimeType == runtimeType && sameJson(fields, other.fields);

  @override
  int get hashCode => _hash(fields);

  @override
  String toString() => '$runtimeType$fields';
}

/// A card or a group. Positions and sizes are pixels in the canvas's own space; the spec says integers.
class CanvasNode extends CanvasRecord implements Box {
  CanvasNode(super.fields);

  /// A card of words, its fields in the order the web's makers set them.
  CanvasNode.text({required String id, required double x, required double y, required double width, required double height, required String text, CanvasColor? color})
    : super({'id': id, 'type': 'text', 'x': x, 'y': y, 'width': width, 'height': height, 'color': ?color, 'text': text});

  CanvasNode.file({required String id, required double x, required double y, required double width, required double height, required String file, String? subpath, CanvasColor? color})
    : super({'id': id, 'type': 'file', 'x': x, 'y': y, 'width': width, 'height': height, 'color': ?color, 'file': file, 'subpath': ?subpath});

  CanvasNode.link({required String id, required double x, required double y, required double width, required double height, required String url, CanvasColor? color})
    : super({'id': id, 'type': 'link', 'x': x, 'y': y, 'width': width, 'height': height, 'color': ?color, 'url': url});

  CanvasNode.group({required String id, required double x, required double y, required double width, required double height, String? label, CanvasColor? color})
    : super({'id': id, 'type': 'group', 'x': x, 'y': y, 'width': width, 'height': height, 'label': ?label, 'color': ?color});

  String get id => _s('id')!;
  NodeType get type => _named(NodeType.values, fields['type'])!;
  @override
  double get x => _d('x');
  @override
  double get y => _d('y');
  @override
  double get width => _d('width');
  @override
  double get height => _d('height');
  CanvasColor? get color => _s('color');

  /// A card of words' Markdown; empty for any other kind.
  String get text => _s('text') ?? '';

  /// A file card's path, and the anchor in it (`#^friday`).
  String get file => _s('file') ?? '';
  String? get subpath => _s('subpath');

  /// A link card's address.
  String get url => _s('url') ?? '';

  /// A group's name, its picture and how that is laid.
  String? get label => _s('label');
  String? get background => _s('background');
  String? get backgroundStyle => _s('backgroundStyle');

  bool get isGroup => type == NodeType.group;

  /// `{ ...node, ...changes }`.
  CanvasNode put(Map<String, Object?> changes) => CanvasNode(_put(changes));

  /// The node without one of its fields.
  CanvasNode without(String key) => CanvasNode(_without(key));
}

/// A line from one card to another. The spec's defaults: nothing at the start, an arrow at the end.
class CanvasEdge extends CanvasRecord {
  CanvasEdge(super.fields);

  CanvasEdge.of({required String id, required String fromNode, required String toNode, Side? fromSide, Side? toSide, End? fromEnd, End? toEnd, CanvasColor? color, String? label})
    : super({
        'id': id,
        'fromNode': fromNode,
        'toNode': toNode,
        'fromSide': ?fromSide?.name,
        'toSide': ?toSide?.name,
        'fromEnd': ?fromEnd?.name,
        'toEnd': ?toEnd?.name,
        'color': ?color,
        'label': ?label,
      });

  String get id => _s('id')!;
  String get fromNode => _s('fromNode')!;
  String get toNode => _s('toNode')!;
  Side? get fromSide => _named(Side.values, fields['fromSide']);
  Side? get toSide => _named(Side.values, fields['toSide']);
  End? get fromEnd => _named(End.values, fields['fromEnd']);
  End? get toEnd => _named(End.values, fields['toEnd']);
  CanvasColor? get color => _s('color');
  String? get label => _s('label');

  CanvasEdge put(Map<String, Object?> changes) => CanvasEdge(_put(changes));
  CanvasEdge without(String key) => CanvasEdge(_without(key));
}

/// A reply in a canvas's thread (docs/SHARED.md, S9): who, when (ISO 8601) and the words.
class CanvasReply extends CanvasRecord {
  CanvasReply(super.fields);
  CanvasReply.of({required String by, required String at, required String text}) : super({'by': by, 'at': at, 'text': text});

  String get by => _s('by')!;
  String get at => _s('at')!;
  String get text => _s('text')!;
}

/// A comment thread on a card: Ghost.md's own field in the JSON, `comments`, a thread each, anchored to a node by
/// id. The head is the thread's first comment; `resolved` names who closed it and when.
class CanvasComment extends CanvasRecord {
  CanvasComment(super.fields);

  String get id => _s('id')!;
  String get node => _s('node')!;
  String get by => _s('by')!;
  String get at => _s('at')!;
  String get text => _s('text')!;
  List<CanvasReply> get replies => [for (final each in fields['replies']! as List) CanvasReply((each as Map).cast<String, Object?>())];
  ({String by, String at})? get resolved {
    final value = fields['resolved'];
    return value is Map ? (by: value['by'] as String, at: value['at'] as String) : null;
  }

  CanvasComment put(Map<String, Object?> changes) => CanvasComment(_put(changes));
  CanvasComment without(String key) => CanvasComment(_without(key));
}

/// A canvas. Nodes are in ascending z-order, as the spec has them: the first is drawn first, under the rest.
class Canvas {
  Canvas({required List<CanvasNode> nodes, required List<CanvasEdge> edges, List<CanvasComment>? comments})
    : nodes = List.unmodifiable(nodes),
      edges = List.unmodifiable(edges),
      comments = comments == null ? null : List.unmodifiable(comments);

  final List<CanvasNode> nodes;
  final List<CanvasEdge> edges;

  /// The threads on its cards; left out of the JSON when there are none, so a canvas without them is the spec's alone.
  final List<CanvasComment>? comments;

  /// The node by that id, or null.
  CanvasNode? nodeOf(String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is Canvas && sameJson(nodes, other.nodes) && sameJson(edges, other.edges) && sameJson(comments, other.comments);

  @override
  int get hashCode => Object.hash(_hash(nodes), _hash(edges), _hash(comments));

  @override
  String toString() => 'Canvas(nodes: $nodes, edges: $edges${comments == null ? '' : ', comments: $comments'})';
}

const _styles = ['cover', 'ratio', 'repeat'];
const _sides = ['top', 'right', 'bottom', 'left'];
const _ends = ['none', 'arrow'];

String? _str(Object? value) => value is String ? value : null;

/// A string that is something: `str(value)` where the web then asks `if (!id)`.
String? _some(Object? value) => value is String && value.isNotEmpty ? value : null;
double? _num(Object? value) => value is num && value.isFinite ? jsRound(value.toDouble()) : null;
String? _oneOf(Object? value, List<String> of) => value is String && of.contains(value) ? value : null;

final RegExp _color = RegExp(r'^([1-6]|#[0-9a-f]{6}|#[0-9a-f]{3})$', caseSensitive: false);

/// A colour the spec allows: a preset digit, or a hex colour. Anything else is read as no colour.
String? _colorOf(Object? value) => value is String && _color.hasMatch(value) ? value : null;

CanvasNode? _readNode(Object? value) {
  if (value is! Map) return null;
  final id = _some(value['id']);
  final x = _num(value['x']);
  final y = _num(value['y']);
  final width = _num(value['width']);
  final height = _num(value['height']);
  if (id == null || x == null || y == null || width == null || height == null) return null;
  final base = <String, Object?>{'id': id, 'x': x, 'y': y, 'width': width, 'height': height, 'color': ?_colorOf(value['color'])};
  switch (value['type']) {
    case 'text':
      final text = _str(value['text']);
      return text == null ? null : CanvasNode({...base, 'type': 'text', 'text': text});
    case 'file':
      final file = _some(value['file']);
      if (file == null) return null;
      final subpath = _str(value['subpath']);
      return CanvasNode({...base, 'type': 'file', 'file': file, if (subpath != null && subpath.startsWith('#')) 'subpath': subpath});
    case 'link':
      final url = _some(value['url']);
      return url == null ? null : CanvasNode({...base, 'type': 'link', 'url': url});
    case 'group':
      return CanvasNode({...base, 'type': 'group', 'label': ?_some(value['label']), 'background': ?_some(value['background']), 'backgroundStyle': ?_oneOf(value['backgroundStyle'], _styles)});
    default:
      return null;
  }
}

CanvasEdge? _readEdge(Object? value, Set<String> nodes) {
  if (value is! Map) return null;
  final id = _some(value['id']);
  final fromNode = _some(value['fromNode']);
  final toNode = _some(value['toNode']);
  if (id == null || fromNode == null || toNode == null || !nodes.contains(fromNode) || !nodes.contains(toNode)) return null;
  return CanvasEdge({
    'id': id,
    'fromNode': fromNode,
    'toNode': toNode,
    'fromSide': ?_oneOf(value['fromSide'], _sides),
    'toSide': ?_oneOf(value['toSide'], _sides),
    'fromEnd': ?_oneOf(value['fromEnd'], _ends),
    'toEnd': ?_oneOf(value['toEnd'], _ends),
    'color': ?_colorOf(value['color']),
    'label': ?_some(value['label']),
  });
}

Map<String, Object?>? _readReply(Object? value) {
  if (value is! Map) return null;
  final by = _some(value['by']);
  final at = _some(value['at']);
  final text = _str(value['text']);
  return by != null && at != null && text != null ? {'by': by, 'at': at, 'text': text} : null;
}

/// A thread as the JSON has it: on a node that is there, with a head and whatever replies read; resolved when it
/// says so.
CanvasComment? _readComment(Object? value, Set<String> nodes) {
  if (value is! Map) return null;
  final id = _some(value['id']);
  final node = _some(value['node']);
  final head = _readReply(value);
  if (id == null || node == null || !nodes.contains(node) || head == null) return null;
  final given = value['replies'];
  final replies = [for (final each in given is List ? given : const <Object?>[]) ?_readReply(each)];
  final resolved = value['resolved'];
  final by = resolved is Map ? _some(resolved['by']) : null;
  final at = resolved is Map ? _some(resolved['at']) : null;
  return CanvasComment({
    'id': id,
    'node': node,
    ...head,
    'replies': replies,
    if (by != null && at != null) 'resolved': {'by': by, 'at': at},
  });
}

/// The canvas in [text], or null where the text is not one. A canvas is a JSON object with a `nodes` or an `edges`
/// array (the spec makes both optional; an object with neither is not a canvas, it is `{}`). Nodes that are not
/// nodes are left out, as are edges to nodes that are not there, and a node's id appearing twice keeps the first.
Canvas? parseCanvas(String text) {
  Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (value is! Map) return null;
  final givenNodes = value['nodes'];
  final givenEdges = value['edges'];
  final givenComments = value['comments'];
  if (givenNodes is! List && givenEdges is! List) return null;
  final nodes = <CanvasNode>[];
  final seen = <String>{};
  for (final entry in givenNodes is List ? givenNodes : const <Object?>[]) {
    final node = _readNode(entry);
    if (node != null && seen.add(node.id)) nodes.add(node);
  }
  final edges = <CanvasEdge>[];
  final edgeIds = <String>{};
  for (final entry in givenEdges is List ? givenEdges : const <Object?>[]) {
    final edge = _readEdge(entry, seen);
    if (edge != null && edgeIds.add(edge.id)) edges.add(edge);
  }
  final comments = <CanvasComment>[];
  final commentIds = <String>{};
  for (final entry in givenComments is List ? givenComments : const <Object?>[]) {
    final comment = _readComment(entry, seen);
    if (comment != null && commentIds.add(comment.id)) comments.add(comment);
  }
  return Canvas(nodes: nodes, edges: edges, comments: comments.isEmpty ? null : comments);
}

/// `JSON.stringify(value, null, 2)`.
void _write(StringBuffer out, Object? value, String indent) {
  if (value is CanvasRecord) return _write(out, value.fields, indent);
  if (value is Map) {
    if (value.isEmpty) return out.write('{}');
    final inner = '$indent  ';
    out.write('{\n');
    var first = true;
    for (final entry in value.entries) {
      if (!first) out.write(',\n');
      first = false;
      out
        ..write(inner)
        ..write(jsonEncode(entry.key))
        ..write(': ');
      _write(out, entry.value, inner);
    }
    out.write('\n$indent}');
    return;
  }
  if (value is List) {
    if (value.isEmpty) return out.write('[]');
    final inner = '$indent  ';
    out.write('[\n');
    for (var i = 0; i < value.length; i += 1) {
      if (i > 0) out.write(',\n');
      out.write(inner);
      _write(out, value[i], inner);
    }
    out.write('\n$indent]');
    return;
  }
  if (value is num) return out.write(value.isFinite ? jsNumber(value.toDouble()) : 'null');
  out.write(jsonEncode(value));
}

/// The canvas as the spec writes it, two spaces in, a newline at the end, the way Obsidian saves one - and its
/// threads after the edges, when it has any (docs/SHARED.md, S9), which Obsidian reads past.
String serializeCanvas(Canvas canvas) {
  final out = StringBuffer();
  _write(out, {'nodes': canvas.nodes, 'edges': canvas.edges, if (canvas.comments?.isNotEmpty ?? false) 'comments': canvas.comments}, '');
  out.write('\n');
  return out.toString();
}

// ---- a canvas as a note ---------------------------------------------------------------------

/// The body after its front matter, where it opens with one; the title is not put back as a first line - a
/// canvas's first line is `{`, and the title is the note's name.
String _afterFrontMatter(String body) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  return end == 0 ? body : lines.sublist(end).join('\n');
}

/// The canvas a note's body is, or null for a note that is words: front matter, then the JSON and nothing else.
Canvas? canvasOf(String body) {
  final rest = _afterFrontMatter(body).trim();
  return rest.startsWith('{') ? parseCanvas(rest) : null;
}

/// Whether the note is a canvas rather than words: cheap enough to ask of every note in a list.
bool isCanvasBody(String body) => canvasOf(body) != null;

/// A canvas note's body: the title as front matter, which is how the note gets its name, then the canvas exactly
/// as the spec writes it. Quoted, so a title with a colon in it stays one line.
String canvasNoteBody(String title, Canvas canvas) => '---\ntitle: ${quotedTitle(title, 'Canvas')}\n---\n${serializeCanvas(canvas)}';

/// The note's body with its canvas replaced and everything else kept: the front matter that names it, character
/// for character, then the canvas as the spec writes it. [canvasNoteBody] is for a new note; this is for a note
/// being edited, whose front matter may hold more than a title.
String withCanvas(String body, Canvas canvas) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  return end == 0 ? serializeCanvas(canvas) : '${lines.sublist(0, end).join('\n')}\n${serializeCanvas(canvas)}';
}
