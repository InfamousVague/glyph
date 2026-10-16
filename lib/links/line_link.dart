/// Copy link to this line: a link to the line the caret is on, `[[Trip#^ferry]]`, put on the clipboard, for
/// pasting into another note. A line with no name is given one first, ` ^ferry` at its end, made from its words
/// (lib/core/block_ids.dart): an edit in the editor like any typed, one undo. A heading needs no name, since a link
/// points at it by its words: `[[Trip#Packing]]`. A line in the front matter or a blank one has nothing to point
/// at.
library;

import 'package:flutter/services.dart';

import '../core/block_ids.dart';
import '../core/front_matter.dart' show frontMatterSpan;
import '../editor/editor.dart';
import '../editor/view/editor_view.dart';

final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');

/// The link to the caret's line in [view], naming the line first where it has no name; null where the line is
/// blank, in the front matter, or the note has no title to link by. The name's edit is made here; the clipboard is
/// the caller's ([copyLineLink]).
String? lineLink(EditorView view) {
  final state = view.state;
  final doc = state.doc;
  final body = doc.toString();
  final title = linkTitle(body);
  if (title.isEmpty) return null;
  final line = doc.lineAt(state.selection.main.head);
  final text = line.text;
  if (text.trim().isEmpty) return null;
  final front = frontMatterSpan(body);
  if (!front.isEmpty && line.from < front.offset) return null;
  final heading = _heading.firstMatch(text);
  if (heading != null) {
    final words = (heading.group(1) ?? '').replaceAll(RegExp(r'[\[\]|#^]'), '').trim();
    // The note's own title heading is the note.
    if (words.isEmpty) return null;
    return line.number == doc.lineAt(front.offset).number || words == title ? '[[$title]]' : placeLink(title, words);
  }
  final had = blockIdOf(text);
  if (had != null) return placeLink(title, '^${had.id}');
  final id = blockIdFor(text, blockIdsIn(body));
  final named = withBlockId(text, id);
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: line.from, to: line.to, insert: named), userEvent: 'input.name'));
  return placeLink(title, '^$id');
}

/// [lineLink], put on the clipboard; answers what to say, or null where there was nothing to link.
Future<String?> copyLineLink(EditorView view) async {
  final link = lineLink(view);
  if (link == null) return null;
  await Clipboard.setData(ClipboardData(text: link));
  return 'Copied $link';
}
