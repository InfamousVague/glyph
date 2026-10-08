/// Links through the model, kept by construction rather than by asking. A port of `src/app/format/links.ts`.
///
/// Matt: "AI formatting drops links". A note carries links three ways: as markdown,
/// `[the words](https://www.notion.so/…)` from a Notion send; as an autolink, `<https://…>`; and bare, `https://…`
/// in the middle of a sentence. A small model rewriting the note loses them: an address is a hundred characters it
/// cannot copy and will not keep. So before the note goes in, every address is swapped for a short token it can copy
/// (`link-1`, `link-2`), the way a picture line is kept whole, and after the rewrite comes out the tokens are swapped
/// back. A markdown link keeps its words in the note, so the model can rewrite the sentence around them:
/// `[the words](link-1)`.
///
/// A token that does not come back is not a lost link. If the link's words survived, they are made the link again;
/// if not, the link is added at the end of the note on its own line. None of this depends on the prompt, though the
/// prompt asks as well (prompt.dart).
///
/// Blanks and the AI's answers to them go through the same way (docs/DESIGN.md §145, 9): a `{?question}` as
/// `[question](link-7)` and a filled answer as `[midweek](link-8)`, each put back whole by its token whatever words
/// the model gave it, so a rewrite never answers a blank, drops one, or strips an answer's bracket. The fill's own
/// message turns this off (`blanks: false`), since there the blanks are the point. A summary may leave a blank out.
///
/// What differs: a link's `kind` is a [LinkKind]; [restoreLinks] takes `isFinal` (Dart keeps the word `final`) as a
/// named switch beside `lostBlanks`.
library;

import 'package:flutter/foundation.dart';

import '../core/blanks.dart' show blanksIn, fillsIn;
import '../core/item_links.dart' show isMarkName, itemWords, withMark;
import '../core/item_syntax.dart' show afterMark, jsTrim;

/// What a token stands for when it is not a link: a blank, or a filled answer.
enum LinkKind { blank, filled }

/// A link held aside while the model works (`ProtectedLink`).
@immutable
class ProtectedLink {
  const ProtectedLink({required this.token, required this.text, required this.url, required this.original, this.item, this.kind});

  /// `link-3`: what stands in for the address while the model works.
  final String token;

  /// The link's own words, for a markdown link; null for an address on its own.
  final String? text;
  final String url;

  /// How the link was written, to put it back the same way: `[words](url)`, `<url>`, or the bare address.
  final String original;

  /// For an item's mark (core/item_links.dart, `- [ ] Buy milk [notion](url)`): the item's words, so a mark the model
  /// loses goes back onto the item it came from, found again by those words, rather than to the end of the note.
  final String? item;

  /// A blank, or a filled answer, kept by its token and put back whole (docs/DESIGN.md §145).
  final LinkKind? kind;

  @override
  bool operator ==(Object other) =>
      other is ProtectedLink && other.token == token && other.text == text && other.url == url && other.original == original && other.item == item && other.kind == kind;

  @override
  int get hashCode => Object.hash(token, text, url, original, item, kind);

  @override
  String toString() => 'ProtectedLink($token, $text, $url, $original, $item, $kind)';
}

/// A note with its links out, and the links (`Protected`).
@immutable
class Protected {
  const Protected({required this.text, required this.links});

  final String text;
  final List<ProtectedLink> links;

  @override
  bool operator ==(Object other) => other is Protected && other.text == text && listEquals(other.links, links);

  @override
  int get hashCode => Object.hash(text, Object.hashAll(links));

  @override
  String toString() => 'Protected($text, $links)';
}

/// `[words](https://…)`, but not a picture `![…](…)`.
final RegExp _markdown = RegExp(r'(?<!!)\[([^\]\n]*)\]\(\s*(https?:\/\/[^\s()]+)\s*\)');
final RegExp _autolink = RegExp(r'<(https?:\/\/[^\s<>]+)>');
final RegExp _bare = RegExp(r'https?:\/\/[^\s<>()[\]]+');

/// Punctuation that ends the sentence, not the address.
final RegExp _trailing = RegExp(r'''[.,;:!?'"]+$''');
final RegExp _squares = RegExp(r'[[\]]');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// The note with every link replaced by a token, and the links to put back. Blanks and filled answers too, unless
/// [blanks] is false.
Protected protectLinks(String body, {bool blanks = true}) {
  final links = <ProtectedLink>[];
  String next() => 'link-${links.length + 1}';
  var source = body;
  if (blanks && (body.contains('{?') || body.contains('??('))) {
    final all = <({int from, int to, String words, LinkKind kind})>[
      for (final f in fillsIn(body)) (from: f.from, to: f.to, words: f.words, kind: LinkKind.filled),
      for (final b in blanksIn(body)) (from: b.from, to: b.to, words: b.question.isNotEmpty ? b.question : '?', kind: LinkKind.blank),
    ];
    // The page's sort is stable; an insertion sort is too.
    for (var i = 1; i < all.length; i += 1) {
      final span = all[i];
      var j = i - 1;
      while (j >= 0 && all[j].from > span.from) {
        all[j + 1] = all[j];
        j -= 1;
      }
      all[j + 1] = span;
    }
    final out = StringBuffer();
    var at = 0;
    for (var i = 0; i < all.length; i += 1) {
      final span = all[i];
      if (all.take(i).any((other) => span.from < other.to)) continue;
      final token = next();
      final original = body.substring(span.from, span.to);
      links.add(ProtectedLink(token: token, text: span.words, url: '', original: original, kind: span.kind));
      out.write('${body.substring(at, span.from)}[${span.words.replaceAll(_squares, '')}]($token)');
      at = span.to;
    }
    out.write(body.substring(at));
    source = out.toString();
  }
  var text = source.replaceAllMapped(_markdown, (match) {
    final whole = match.group(0)!;
    final words = match.group(1) ?? '';
    final url = match.group(2) ?? '';
    final token = next();
    final item = _markedItem(source, match.start, whole, words);
    links.add(ProtectedLink(token: token, text: words, url: url, original: whole, item: item));
    return '[$words]($token)';
  });
  text = text.replaceAllMapped(_autolink, (match) {
    final token = next();
    links.add(ProtectedLink(token: token, text: null, url: match.group(1) ?? '', original: match.group(0)!));
    return '<$token>';
  });
  text = text.replaceAllMapped(_bare, (match) {
    final whole = match.group(0)!;
    final trailing = _trailing.firstMatch(whole)?.group(0) ?? '';
    final url = trailing.isNotEmpty ? whole.substring(0, whole.length - trailing.length) : whole;
    final token = next();
    links.add(ProtectedLink(token: token, text: null, url: url, original: url));
    return '<$token>$trailing';
  });
  return Protected(text: text, links: links);
}

/// The words of the item a link marks, when it is a mark: one lowercase name for its words, the last thing on its
/// line, and the line a list item.
String? _markedItem(String body, int offset, String whole, String words) {
  if (!isMarkName(words)) return null;
  final lineStart = offset <= 0 ? 0 : body.lastIndexOf('\n', offset - 1) + 1;
  final lineEndAt = body.indexOf('\n', offset + whole.length);
  final lineEnd = lineEndAt == -1 ? body.length : lineEndAt;
  // Nothing after it on the line but, at most, a board's anchor and counters (core/item_syntax.dart `afterMark`).
  final after = body.substring(offset + whole.length, lineEnd);
  if (!afterMark.hasMatch(after)) return null;
  final item = itemWords(body.substring(lineStart, lineEnd));
  return item == null || item.isEmpty ? null : item;
}

final RegExp _notWord = RegExp(r'[^a-z0-9]+');

/// The words of [text] worth matching on: lowercase, letters and digits, three characters or more.
List<String> _tokensOf(String text) {
  return jsTrim(text.toLowerCase().replaceAll(_notWord, ' ')).split(' ').where((t) => t.length >= 3).toList();
}

/// The line of [lines] that is the item [words] most likely became, or -1: three words in five must be there.
int _findItemLine(List<String> lines, String words) {
  final wanted = _tokensOf(words);
  if (wanted.isEmpty) return -1;
  var best = -1;
  var bestScore = 0.0;
  for (var index = 0; index < lines.length; index += 1) {
    final item = itemWords(lines[index]);
    if (item == null) continue;
    final have = _tokensOf(item).toSet();
    final score = wanted.where(have.contains).length / wanted.length;
    if (score > bestScore) {
      bestScore = score;
      best = index;
    }
  }
  return bestScore >= 0.6 ? best : -1;
}

/// The rewrite with its links back. Every way the model may have written a token is taken - `[words](link-1)`,
/// `<link-1>`, `link-1` or `link 1` on its own - and the model's words around it are kept. With [isFinal], a link
/// whose token never came back is restored around its words or added at the end; a partial rewrite still streaming
/// is only substituted. [lostBlanks] false lets a lost blank or answer stay lost, as a summary may.
String restoreLinks(String text, List<ProtectedLink> links, {bool isFinal = true, bool lostBlanks = true}) {
  var out = text;
  final missing = <ProtectedLink>[];
  for (final link in links) {
    final number = link.token.substring('link-'.length);
    // `link-1` and not `link-10`; `link 1` too, a model's likeliest slip.
    final token = 'link[\\s-]?$number(?!\\d)';
    var found = false;
    out = out.replaceAllMapped(RegExp('\\[([^\\]\\n]*)\\]\\s*\\(\\s*$token\\s*\\)', caseSensitive: false), (match) {
      found = true;
      // A blank or an answer comes back whole, whatever words the model gave its token.
      return link.kind != null ? link.original : '[${match.group(1)}](${link.url})';
    });
    out = out.replaceAllMapped(RegExp('<\\s*$token\\s*>', caseSensitive: false), (_) {
      found = true;
      return link.original;
    });
    out = out.replaceAllMapped(RegExp('\\b$token\\b', caseSensitive: false), (_) {
      found = true;
      return link.original;
    });
    if (!found) missing.add(link);
  }
  if (!isFinal) return out;

  // A lost mark goes back onto its item, found by the item's words.
  final lines = out.split('\n');
  final stillMissing = <ProtectedLink>[];
  for (final link in missing) {
    final item = link.item;
    final at = item != null && item.isNotEmpty ? _findItemLine(lines, item) : -1;
    if (at >= 0 && !lines[at].contains('](${link.url})')) {
      lines[at] = withMark(lines[at], link.original);
    } else {
      stillMissing.add(link);
    }
  }
  out = lines.join('\n');

  final orphans = <String>[];
  for (final link in stillMissing) {
    // A lost blank or answer goes at the end on a line of its own, as a lost link does; a summary may leave one out.
    if (link.kind != null) {
      if (lostBlanks) orphans.add(link.original);
      continue;
    }
    final words = jsTrim(link.text ?? '');
    final at = words.isNotEmpty ? _indexOfWords(out, words) : -1;
    if (at >= 0) {
      final end = at + words.length > out.length ? out.length : at + words.length;
      out = '${out.substring(0, at)}[${out.substring(at, end)}](${link.url})${out.substring(end)}';
    } else {
      orphans.add(link.original);
    }
  }
  if (orphans.isNotEmpty) out = '${out.replaceFirst(_trailingSpace, '')}\n\n${orphans.join('\n')}\n';
  return out;
}

final RegExp _linkSpan = RegExp(r'\[[^\]]*\]\([^)]*\)');

/// Where [words] appear in [haystack], regardless of case, and not inside a link already: wrapping those would nest
/// one.
int _indexOfWords(String haystack, String words) {
  final lower = haystack.toLowerCase();
  final needle = words.toLowerCase();
  final spans = [for (final m in _linkSpan.allMatches(haystack)) (m.start, m.end)];
  var from = 0;
  while (from <= lower.length) {
    final at = lower.indexOf(needle, from);
    if (at < 0) return -1;
    final inside = spans.any((span) => at >= span.$1 && at < span.$2);
    if (!inside) return at;
    from = at + needle.length;
  }
  return -1;
}
