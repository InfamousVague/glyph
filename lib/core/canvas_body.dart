/// Whether a note is a canvas, and how many cards it holds: the part of `src/app/canvas/jsonCanvas.ts` a list asks
/// (`isCanvasBody`, and `canvasOf(body).nodes.length` for a row's "6 cards"). A canvas note is front matter that names
/// it, then JSON Canvas 1.0 and nothing else.
///
/// What differs: the canvas itself is not read into a model here (that comes with the canvas's own screen); a node is
/// counted by the same rule that would keep it - an id, a place, a size, and what its type must hold - and an id seen
/// twice counts once.
library;

import 'dart:convert';
import 'front_matter.dart';

/// The body after its front matter, where it opens with one.
String _afterFrontMatter(String body) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  return end == 0 ? body : lines.sublist(end).join('\n');
}

bool _number(Object? value) => value is num && value.isFinite;
bool _string(Object? value) => value is String;

bool _isNode(Object? value) {
  if (value is! Map) return false;
  final id = value['id'];
  if (id is! String || id.isEmpty) return false;
  if (!_number(value['x']) || !_number(value['y']) || !_number(value['width']) || !_number(value['height'])) return false;
  switch (value['type']) {
    case 'text':
      return _string(value['text']);
    case 'file':
      return _string(value['file']) && (value['file'] as String).isNotEmpty;
    case 'link':
      return _string(value['url']) && (value['url'] as String).isNotEmpty;
    case 'group':
      return true;
    default:
      return false;
  }
}

/// How many cards the canvas in [body] holds, or null for a note that is words (`canvasOf(body)?.nodes.length`).
int? canvasCardCount(String body) {
  final rest = _afterFrontMatter(body).trim();
  if (!rest.startsWith('{')) return null;
  Object? value;
  try {
    value = jsonDecode(rest);
  } on FormatException {
    return null;
  }
  if (value is! Map) return null;
  final nodes = value['nodes'], edges = value['edges'];
  if (nodes is! List && edges is! List) return null;
  final seen = <String>{};
  for (final entry in nodes is List ? nodes : const <Object?>[]) {
    if (_isNode(entry)) seen.add((entry as Map)['id'] as String);
  }
  return seen.length;
}

/// Whether the note is a canvas rather than words: cheap enough to ask of every note in a list.
bool isCanvasBody(String body) => canvasCardCount(body) != null;
