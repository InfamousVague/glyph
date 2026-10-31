/// Docs: a notebook kept as a book of documentation, the shape the public Ghost.md Docs have had since 2026-10-26
/// (docs/book/index.md, published at ghostmarkdown.com/docs), made a kind of its own. Matt, 2026-10-31: "There should
/// be a specific type of notebook for docs that we made, add it to the Claude and other AI connector so they can make
/// docs on ghost expose it in the MCP and then add instructions for AI to know how to use it".
///
/// It is a notebook ([isBookBody]) whose front matter also says `type: docs`, and nothing else of it is new:
///
///     ---
///     title: "Field guide"
///     book: true
///     type: docs
///     ---
///     # Field guide
///
///     What the docs are about, a line or two.
///
///     ## Getting started
///
///     1. [[Welcome]]
///     2. [[Install]]
///
///     ## Using it
///
///     3. [[Your first page]]
///
/// Each `## ` heading of the index is a part, and the numbered `[[links]]` under it are its pages, numbered straight
/// through the book as [chaptersOf] reads them, so the book view, a page's way round the book (book_nav.dart) and the
/// page tree's previous and next (page_tree.dart) all go part by part with no reader of their own. A page is a plain
/// note, named by its `# ` heading, which may carry an `icon:` (as a teamspace's page does, page_tree.dart
/// [withPageIcon]) and opens with a line that says what it is about.
///
/// Why `type:`: it is already the key that says what kind of thing a note is (`type: ticket`, `type: teamspace`,
/// `type: cycle`, `type: milestone`), and every reader of it asks for its own word alone (properties.dart
/// `isTicketType`, page_tree.dart, planning.dart `isMilestoneType`), so `docs` is read by none of them. `docs:` itself
/// is not used: it is a teamspace home's read-or-edit setting (docs/TEAMSPACES.md).
///
///     isDocsBody, docsParts, docsPartHeads, docsBookBody, withDocsPage, docsPageBody, docsTitleProblem
library;

import 'package:flutter/foundation.dart';

import 'book.dart' show Chapter, chaptersOf, saysYes;
import 'front_matter.dart';
import 'note_text.dart' show noteTitle, sameTitle, titleKey;
import 'page_tree.dart' show withPageIcon;

/// The `type:` a docs notebook says.
const String docsType = 'docs';

/// The part a new docs notebook starts with, in the sheet that makes one (new_book_sheet.dart).
const String docsStarterPart = 'Getting started';

/// Whether a note is docs: `book: true` and `type: docs` (any case) in its front matter.
bool isDocsBody(String body) {
  final span = frontMatterSpan(body);
  return saysYes(frontMatterValueIn(body, span, 'book')) && frontMatterValueIn(body, span, 'type')?.trim().toLowerCase() == docsType;
}

/// One part of docs: its heading's words and its pages' titles, in order. Read from an index, [line] is its heading's
/// line, or -1 for the pages listed before any heading (whose [title] is empty).
@immutable
class DocsPart {
  const DocsPart(this.title, [this.pages = const <String>[], this.line = -1]);
  final String title;
  final List<String> pages;
  final int line;

  @override
  bool operator ==(Object other) => other is DocsPart && other.title == title && listEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(pages));

  @override
  String toString() => 'DocsPart($title, $pages)';
}

final RegExp _part = RegExp(r'^##\s+(.+?)(?:\s+#+)?\s*$');

/// The parts of a docs index, in order, each with its pages ([chaptersOf]'s, an indented one with the page above it):
/// every `## ` heading after the front matter is a part, one with no pages under it yet too. Pages listed before the
/// first heading are a part with no title, there only where there are some.
List<DocsPart> docsParts(String body) {
  final lines = body.split('\n');
  final chapters = chaptersOf(body);
  final parts = <({String title, int line, List<String> pages})>[];
  var next = 0;
  final loose = <String>[];
  for (var n = frontMatterEnd(lines); n < lines.length; n += 1) {
    final heading = _part.firstMatch(lines[n]);
    while (next < chapters.length && chapters[next].line < n) {
      (parts.isEmpty ? loose : parts.last.pages).add(chapters[next].title);
      next += 1;
    }
    if (heading != null) parts.add((title: heading.group(1)!.trim(), line: n, pages: <String>[]));
  }
  for (; next < chapters.length; next += 1) {
    (parts.isEmpty ? loose : parts.last.pages).add(chapters[next].title);
  }
  return [
    if (loose.isNotEmpty) DocsPart('', List.unmodifiable(loose)),
    for (final part in parts) DocsPart(part.title, List.unmodifiable(part.pages), part.line),
  ];
}

/// The part each of [chapters] (the index's [chaptersOf]) opens, for the book view to draw over it: a part's title
/// over its first page, null over every other page.
List<String?> docsPartHeads(String body, List<Chapter> chapters) {
  final opens = <String, String>{};
  for (final part in docsParts(body)) {
    if (part.title.isNotEmpty && part.pages.isNotEmpty) opens[titleKey(part.pages.first)] = part.title;
  }
  return [for (final c in chapters) opens.remove(titleKey(c.title))];
}

/// The body of new docs named [title]: [about] under the heading, then each of [parts] as a `## ` heading with its
/// pages numbered under it, straight through the book.
String docsBookBody(String title, {String? about, List<DocsPart> parts = const []}) {
  final named = quotedTitle(title, 'Docs');
  final out = <String>['---', 'title: $named', 'book: true', 'type: $docsType', '---', '# ${named.substring(1, named.length - 1)}', ''];
  final said = about?.trim() ?? '';
  if (said.isNotEmpty) out.addAll([said, '']);
  var number = 0;
  for (final part in parts) {
    final heading = part.title.trim();
    if (heading.isNotEmpty) out.addAll(['## $heading', '']);
    for (final page in part.pages) {
      out.add('${number += 1}. [[${page.trim()}]]');
    }
    if (part.pages.isNotEmpty) out.add('');
  }
  return out.join('\n');
}

final RegExp _numbered = RegExp(r'^(\s*)(\d+)([.)])');

/// The index with a page called [page] added to the part called [part] (matched as a title is, [sameTitle]): last
/// in it, or [position]th (from 1) where that is given. A part the index has not got is made, at the end, as a `## `
/// heading. A page already in the index is left where it is. The index's numbered pages are numbered again straight
/// through, so the new one does not repeat a number; an index of bullets stays bullets.
String withDocsPage(String body, String part, String page, {int? position}) {
  final title = page.trim();
  final heading = part.trim();
  if (title.isEmpty || chaptersOf(body).any((c) => sameTitle(c.title, title))) return body;
  final lines = body.split('\n');
  final chapters = chaptersOf(body);
  final numbers = chapters.isEmpty || chapters.any((c) => _numbered.hasMatch(lines[c.line]));
  final item = '${numbers ? '1.' : '-'} [[$title]]';
  final found = heading.isEmpty ? docsParts(body).where((p) => p.title.isEmpty && p.pages.isNotEmpty).firstOrNull : docsParts(body).where((p) => p.title.isNotEmpty && sameTitle(p.title, heading)).firstOrNull;
  if (found == null) {
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    lines.addAll(['', if (heading.isNotEmpty) ...['## $heading', ''], item, '']);
    return _renumbered(lines.join('\n'));
  }
  // The part's own pages, at the top level: where the new one goes among them.
  final own = [
    for (final c in chapters)
      if (c.depth == 0 && found.pages.any((p) => sameTitle(p, c.title))) c,
  ];
  final at = position == null ? own.length : (position - 1).clamp(0, own.length);
  if (own.isEmpty) {
    // Under the heading, after the blank line it stands on.
    var where = found.line + 1;
    lines.insert(where, '');
    where += 1;
    lines.insert(where, item);
    if (where + 1 < lines.length && lines[where + 1].trim().isNotEmpty) lines.insert(where + 1, '');
  } else if (at < own.length) {
    lines.insert(own[at].line, item);
  } else {
    // After the last of the part's pages and any pages indented under it.
    final last = own.last;
    final under = [for (final c in chapters) if (c.line > last.line && c.depth == 1 && !chapters.any((d) => d.depth == 0 && d.line > last.line && d.line < c.line)) c];
    lines.insert((under.isEmpty ? last.line : under.last.line) + 1, item);
  }
  return _renumbered(lines.join('\n'));
}

/// The index's top-level numbered pages numbered 1, 2, 3 in the order they stand: what [withDocsPage] leaves.
String _renumbered(String body) {
  final lines = body.split('\n');
  var number = 0;
  for (final Chapter c in chaptersOf(body)) {
    if (c.depth != 0) continue;
    final marker = _numbered.firstMatch(lines[c.line]);
    if (marker == null) continue;
    number += 1;
    lines[c.line] = '${marker.group(1)}$number${marker.group(3)}${lines[c.line].substring(marker.end)}';
  }
  return lines.join('\n');
}

final RegExp _heading = RegExp(r'^#\s+');

/// A page of docs: [title] as its `# ` heading and [words] under it (a heading of the same name the words open with
/// is not written twice), and its `icon:` where one is given.
String docsPageBody(String title, String words, {String? icon}) {
  final clean = title.trim();
  var said = words.trim();
  final first = said.split('\n').first;
  if (_heading.hasMatch(first) && sameTitle(noteTitle(first), clean)) said = said.substring(first.length).trim();
  final body = '# $clean\n${said.isEmpty ? '' : '\n$said\n'}';
  return withPageIcon(body, icon);
}

final RegExp _unlinkable = RegExp(r'[\[\]|#\n]');

/// What is wrong with [title] as a page's (or the docs') name, or null where nothing is: a page is found by its title
/// from a `[[link]]`, which a bracket, a `|` or a `#` in it would cut short, and which reads at most 120 letters.
String? docsTitleProblem(String title) {
  final clean = title.trim();
  if (clean.isEmpty) return 'A page needs a title.';
  if (clean.length > 120) return '“${clean.substring(0, 40)}…” is longer than a link can name: keep a title under 120 letters.';
  if (_unlinkable.hasMatch(clean)) return '“$clean” has a [, ], |, # or a line break in it, which a [[link]] to it would cut short.';
  return null;
}
