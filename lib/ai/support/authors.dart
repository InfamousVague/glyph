/// Who wrote a note: the half of `src/app/core/authors.ts` that writes authors and names an AI.
///
/// A note's authors are its front matter's `authors:`, names separated by commas: `authors: infamousvague, Claude`.
/// A note with none is the person's own, and says nothing about it. An AI that writes in a note adds its own name
/// there, after the account's, so the note is listed as written by both. The line is part of the words, so it goes
/// wherever the note does: every device, a shared link, a download.
///
/// What differs: the readers, `authorsOf` and `isKnownAi`, were ported first with the byline that draws them
/// (lib/note/byline.dart), and are exported from there rather than written twice, so this file reaches a widget
/// file. They belong here, or in a lib/core/authors.dart, with the byline importing them. `AI_AUTHOR` is [aiAuthor].
/// An MCP client is a `({name, title})` record. Kept under lib/ai/support until lib/core has an authors.dart.
library;

import '../../core/item_syntax.dart' show jsTrim;
import '../../core/properties.dart' show withFrontMatterValue;
import '../../note/byline.dart' show authorsOf;

export '../../note/byline.dart' show authorsOf, isKnownAi;

/// The body with [author] among its authors. A note that named none takes [owner] first, since it was theirs before
/// anyone wrote in it with them; [owner] absent, the author alone. A name already there is not added again.
String withAuthor(String body, String author, [String? owner]) {
  final name = _cleanName(author);
  if (name.isEmpty) return body;
  final now = authorsOf(body);
  final first = owner == null ? '' : _cleanName(owner);
  final next = now.isNotEmpty ? <String>[...now] : <String>[if (first.isNotEmpty) first];
  if (!next.any((n) => n.toLowerCase() == name.toLowerCase())) next.add(name);
  if (next.length == now.length) {
    var same = true;
    for (var i = 0; i < next.length; i += 1) {
      if (next[i] != now[i]) same = false;
    }
    if (same) return body;
  }
  return withFrontMatterValue(body, 'authors', next.join(', '));
}

/// Every author across notes, in the order first met: a book's own and its chapters'.
List<String> authorsAcross(List<String> bodies) {
  final seen = <String>{};
  final out = <String>[];
  for (final body in bodies) {
    for (final name in authorsOf(body)) {
      if (seen.add(name.toLowerCase())) out.add(name);
    }
  }
  return out;
}

final RegExp _separators = RegExp(r'[,\n\r]');
final RegExp _space = RegExp(r'\s+');

/// A name as the line can hold it: one line, no commas (they separate names), a sensible length.
String _cleanName(String name) {
  final clean = jsTrim(name.replaceAll(_separators, ' ').replaceAll(_space, ' '));
  return clean.length > 40 ? clean.substring(0, 40) : clean;
}

/// The name an AI goes by, from what its app calls itself when it connects (MCP's clientInfo) or what it said it
/// is. Said beats known; known names read as the product ("claude-ai" is Claude). Null when there is nothing to go
/// on.
String? aiName(String? said, ({String? name, String? title})? client) {
  final given = said == null ? '' : jsTrim(said);
  if (given.isNotEmpty) return _cleanName(given);
  final from = '${client?.title ?? ''} ${client?.name ?? ''}'.toLowerCase();
  for (final (pattern, name) in _known) {
    if (pattern.hasMatch(from)) return name;
  }
  final title = jsTrim(client?.title ?? '');
  final raw = title.isNotEmpty ? title : jsTrim(client?.name ?? '');
  return raw.isNotEmpty ? _cleanName(raw) : null;
}

/// The name the app's own model signs with: the ghost is the app, whichever model wrote (`AI_AUTHOR`).
const String aiAuthor = 'Ghost';

final List<(RegExp, String)> _known = <(RegExp, String)>[
  (RegExp(r'^ghost$'), aiAuthor),
  (RegExp('claude'), 'Claude'),
  (RegExp('chatgpt|openai'), 'ChatGPT'),
  (RegExp('gemini'), 'Gemini'),
  (RegExp('copilot'), 'Copilot'),
  (RegExp('cursor'), 'Cursor'),
];
