/// Which notes link to which, kept as the library changes: what a note's "Linked from" and "Mentioned in" are read
/// from, and the graph of the library (lib/links). One index for the app, made once from the whole library off the
/// UI isolate and then told each note that changed, never read again whole for a keystroke.
///
/// What it keeps of each note ([LinkFacts]), read from its body alone:
/// - **its names**: the title (lib/core/note_text.dart `noteTitle`, as a list shows it), the `aliases:` of its front
///   matter (lib/core/aliases.dart), a ticket's key (`id: GHO-12`), and the path of its file;
/// - **its links**, each where it stands in the body: `[[Title]]`, `[[Title|words]]`, `[[Title#Heading]]`,
///   `[[Title#^block]]`, the embeds `![[Title]]`, and Markdown links to a note's file, `[words](Some%20note.md)`,
///   as Obsidian writes them. A link inside a code block or a code span is not one. `[[#^block]]` points inside the
///   note it is in, and is no link to another;
/// - **its words**, each once, for the notes that say another's name without linking it: the words are kept by
///   word, so a name is looked for only in the notes that hold its rarest word.
///
/// **A link is kept as the name it was written with, not the note it opened.** Which note a name means is asked
/// when it is wanted ([LinkIndex.resolve]), the way the editor asks (lib/root/library_reads.dart `titled`): a
/// note's title first (a note of the person's before a template's page, the newest of two with one title), then a
/// ticket's key, then an alias. So a note renamed, or a second note given the same title, changes what the links
/// mean at once, and no note but the one that changed is read again.
///
/// **What is read where.** [LinkIndex.build] reads a whole library, and is what a worker isolate runs
/// ([LinkIndexer], which hands the index back whole: `Isolate.run` passes the object graph over without copying
/// it). A note that changed is read on the UI isolate ([LinkIndex.put]), a body at a time, which is a fraction of a
/// millisecond; a change of more notes than [LinkIndexer.inlineUpTo] at once (a sync landing, a library opened) is
/// read in the worker again. test/core/link_index_test.dart times one change to a library of 2,000 notes.
///
/// The Markdown files stay as they are: nothing here is written anywhere, and the index is made again each time the
/// app starts.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'aliases.dart';
import 'front_matter.dart';
import 'note.dart';
import 'note_text.dart' show noteTitleIn;
import 'title_key.dart';

// ---- one note, read -----------------------------------------------------------------------------------------------

/// One link written in a note: what it names, and where it stands in the body.
@immutable
class LinkOut {
  const LinkOut({required this.target, required this.key, required this.from, required this.to, this.anchor, this.label, this.embed = false, this.path});

  /// The name as written: a title, an alias, a ticket's key; for a Markdown link, the file's name without `.md`.
  final String target;

  /// [target] as it is matched ([titleKey]).
  final String key;

  /// The whole link in the body, brackets and all.
  final int from;
  final int to;

  /// What followed a `#`: a heading's words, or `^` and a block's name.
  final String? anchor;

  /// What followed a `|`: the words the link is read as.
  final String? label;

  /// `![[…]]`: the other note drawn in this one.
  final bool embed;

  /// A Markdown link's file, as written, decoded, in lower case and without `.md`: `inbox/lisbon`. Null for a
  /// `[[link]]`.
  final String? path;

  @override
  bool operator ==(Object other) =>
      other is LinkOut && other.target == target && other.key == key && other.from == from && other.to == to && other.anchor == anchor && other.label == label && other.embed == embed && other.path == path;

  @override
  int get hashCode => Object.hash(target, key, from, to, anchor, label, embed, path);

  @override
  String toString() => 'LinkOut(${embed ? '!' : ''}"$target"${anchor == null ? '' : '#$anchor'}${label == null ? '' : '|$label'}${path == null ? '' : ' $path.md'} $from-$to)';
}

/// What the index keeps of one note (see the library's doc). Plain data, so it crosses between isolates.
class LinkFacts {
  LinkFacts({
    required this.id,
    required this.title,
    required this.aliases,
    required this.ticket,
    required this.path,
    required this.links,
    required this.words,
    required this.templatePage,
    required this.updatedAt,
  })  : key = titleKey(title),
        aliasKeys = [for (final alias in aliases) titleKey(alias)],
        ticketKey = ticket == null ? '' : titleKey(ticket);

  /// [body] read: what [LinkIndex.put] keeps.
  factory LinkFacts.read(String id, String body, {String? path, int updatedAt = 0}) {
    final front = frontMatterSpan(body);
    final title = noteTitleIn(body, front);
    final plain = plainText(body);
    return LinkFacts(
      id: id,
      title: title,
      aliases: aliasesOf(body),
      ticket: _ticketOf(body, front),
      path: path == null ? '' : pathKey(path),
      links: linksIn(body),
      words: wordsIn(plain),
      templatePage: _templatePage(body, front),
      updatedAt: updatedAt,
    );
  }

  final String id;
  final String title;

  /// The title as it is matched; empty for a note with no title.
  final String key;
  final List<String> aliases;
  final List<String> aliasKeys;

  /// A ticket's key as written (`GHO-12`), or null; and as it is matched, or empty.
  final String? ticket;
  final String ticketKey;

  /// The file's path in the library ([pathKey]), or empty where the note has none yet.
  final String path;
  final List<LinkOut> links;

  /// Every word of the note's words, each once: lower case, the letters a to z and the digits, as a title is matched.
  final List<String> words;

  /// A template's page (`templates: page`): a link finds a note of the person's of that title before it.
  final bool templatePage;

  /// When the note was last edited: of two notes with one title, the newest is the one a link means.
  int updatedAt;

  /// The names this note may be found by, as they are matched: its title, its aliases and its ticket's key.
  Iterable<String> get nameKeys sync* {
    if (key.isNotEmpty) yield key;
    for (final alias in aliasKeys) {
      if (alias.isNotEmpty) yield alias;
    }
    if (ticketKey.isNotEmpty) yield ticketKey;
  }
}

/// A path as a Markdown link matches it: lower case, `\` as `/`, no leading `./` or `/`, and no `.md`.
String pathKey(String path) {
  var text = path.trim().replaceAll(r'\', '/').toLowerCase();
  while (text.startsWith('./')) {
    text = text.substring(2);
  }
  while (text.startsWith('/')) {
    text = text.substring(1);
  }
  return text.endsWith('.md') ? text.substring(0, text.length - 3) : text;
}

String? _ticketOf(String body, FrontMatterSpan front) {
  if (front.isEmpty || frontMatterValueIn(body, front, 'type')?.trim().toLowerCase() != 'ticket') return null;
  final id = frontMatterValueIn(body, front, 'id')?.trim();
  return id == null || id.isEmpty ? null : id;
}

bool _templatePage(String body, FrontMatterSpan front) {
  if (front.isEmpty) return false;
  final book = frontMatterValueIn(body, front, 'book')?.trim().toLowerCase();
  if (book == 'true' || book == 'yes') return false;
  return (frontMatterValueIn(body, front, 'templates') ?? '').trim().toLowerCase() == 'page';
}

// ---- the words, with what is not words blanked ------------------------------------------------------------------

final RegExp _fenceLine = RegExp(r'^\s*(```|~~~)');
final RegExp _codeSpan = RegExp(r'`[^`\n]*`');
final RegExp _wikiAny = RegExp(r'!?\[\[[^\[\]\n]{1,200}\]\]');
final RegExp _mdTarget = RegExp(r'\]\([^)\n]*\)');
final RegExp _url = RegExp(r'\b(?:https?|ghostmd|mailto):[^\s)\]>]+', caseSensitive: false);
final RegExp _anchorTail = RegExp(r'(?<!\S)\^[a-z0-9][a-z0-9_-]*\s*$', multiLine: true);

/// [body] with everything that is not its words made spaces, every other character where it was, so a place in it
/// is the same place in the body: the front matter, code blocks and code spans, links between notes (their names
/// are the links' business, not words that mention a note), a Markdown link's address, web addresses, and a line's
/// `^name`.
String plainText(String body) {
  final out = StringBuffer();
  final front = frontMatterSpan(body).offset;
  out.write(_spaces(body.substring(0, front)));
  var inFence = false;
  var from = front;
  while (from <= body.length) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? body.length : next;
    final line = body.substring(from, to);
    if (_fenceLine.hasMatch(line)) {
      inFence = !inFence;
      out.write(_spaces(line));
    } else if (inFence) {
      out.write(_spaces(line));
    } else {
      out.write(_blankLine(line));
    }
    if (next < 0) break;
    out.write('\n');
    from = next + 1;
  }
  return out.toString();
}

String _blankLine(String line) {
  if (!line.contains('`') && !line.contains('[[') && !line.contains('](') && !line.contains(':') && !line.contains('^')) return line;
  var text = line;
  for (final pattern in [_codeSpan, _wikiAny, _mdTarget, _url, _anchorTail]) {
    if (!pattern.hasMatch(text)) continue;
    text = text.replaceAllMapped(pattern, (m) => _spaces(m[0]!));
  }
  return text;
}

String _spaces(String text) {
  if (text.isEmpty) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i += 1) {
    out.write(text.codeUnitAt(i) == 0x0A ? '\n' : ' ');
  }
  return out.toString();
}

final RegExp _notWord = RegExp(r'[^a-z0-9]+');

/// The different words of [plain], in lower case, as a title is matched: the letters a to z and the digits.
List<String> wordsIn(String plain) {
  final seen = <String>{};
  for (final word in plain.toLowerCase().split(_notWord)) {
    if (word.isNotEmpty) seen.add(word);
  }
  return seen.toList(growable: false);
}

// ---- the links ----------------------------------------------------------------------------------------------------

final RegExp _wiki = RegExp(r'(!?)\[\[([^\[\]\n]{1,200})\]\]');
final RegExp _markdown = RegExp(r'(!?)\[([^\]\n]*)\]\(<?([^)<>\n]+?\.md)(#[^)>\n]*)?>?\)', caseSensitive: false);
final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false);

/// Every link [body] makes to another note, in order: none inside a code block or a code span.
List<LinkOut> linksIn(String body) {
  if (!body.contains('[[') && !body.contains('.md')) return const [];
  final code = _codeOf(body);
  final found = <LinkOut>[];
  for (final match in _wiki.allMatches(body)) {
    if (_inCode(code, match.start)) continue;
    final inside = match.group(2) ?? '';
    final bar = inside.indexOf('|');
    final named = bar >= 0 ? inside.substring(0, bar) : inside;
    final label = bar >= 0 ? inside.substring(bar + 1).trim() : null;
    final hash = named.indexOf('#');
    final target = (hash >= 0 ? named.substring(0, hash) : named).trim();
    // `[[#^name]]` is a place in this note, not another note.
    if (target.isEmpty) continue;
    final anchor = hash >= 0 ? named.substring(hash + 1).trim() : null;
    found.add(LinkOut(
      target: target,
      key: titleKey(target),
      from: match.start,
      to: match.end,
      anchor: anchor == null || anchor.isEmpty ? null : anchor,
      label: label == null || label.isEmpty ? null : label,
      embed: (match.group(1) ?? '').isNotEmpty,
    ));
  }
  if (body.contains('.md')) {
    for (final match in _markdown.allMatches(body)) {
      if (_inCode(code, match.start)) continue;
      final raw = (match.group(3) ?? '').trim();
      if (raw.isEmpty || _scheme.hasMatch(raw)) continue;
      String file;
      try {
        file = Uri.decodeComponent(raw);
      } catch (_) {
        file = raw;
      }
      final path = pathKey(file);
      final name = path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;
      final shown = file.contains('/') ? file.substring(file.lastIndexOf('/') + 1) : file;
      final anchor = match.group(4);
      found.add(LinkOut(
        target: shown.toLowerCase().endsWith('.md') ? shown.substring(0, shown.length - 3) : shown,
        key: titleKey(name),
        from: match.start,
        to: match.end,
        anchor: anchor == null || anchor.length < 2 ? null : anchor.substring(1),
        label: (match.group(2) ?? '').trim().isEmpty ? null : match.group(2)!.trim(),
        embed: (match.group(1) ?? '').isNotEmpty,
        path: path,
      ));
    }
    found.sort((a, b) => a.from - b.from);
  }
  return found;
}

/// Where the code is in [body]: each fenced block's and code span's start and end, in order.
List<int> _codeOf(String body) {
  if (!body.contains('`') && !body.contains('~~~')) return const [];
  final spans = <int>[];
  var inFence = false;
  var fenceFrom = 0;
  var from = 0;
  while (from <= body.length) {
    final next = body.indexOf('\n', from);
    final to = next < 0 ? body.length : next;
    final line = body.substring(from, to);
    if (_fenceLine.hasMatch(line)) {
      if (inFence) {
        spans
          ..add(fenceFrom)
          ..add(to);
      } else {
        fenceFrom = from;
      }
      inFence = !inFence;
    } else if (!inFence && line.contains('`')) {
      for (final span in _codeSpan.allMatches(line)) {
        spans
          ..add(from + span.start)
          ..add(from + span.end);
      }
    }
    if (next < 0) break;
    from = next + 1;
  }
  if (inFence) {
    spans
      ..add(fenceFrom)
      ..add(body.length);
  }
  return spans;
}

bool _inCode(List<int> code, int at) {
  for (var i = 0; i + 1 < code.length; i += 2) {
    if (at >= code[i] && at < code[i + 1]) return true;
  }
  return false;
}

// ---- the index ----------------------------------------------------------------------------------------------------

/// A note that links to another, and where: the line round each link to it.
@immutable
class Backlink {
  const Backlink({required this.id, required this.title, required this.links});
  final String id;
  final String title;

  /// Each link to the note, in the order the note has them.
  final List<LinkPlace> links;
}

/// A place in a note: the line it is on (from 0), and the line's words.
@immutable
class LinkPlace {
  const LinkPlace({required this.line, required this.text, required this.from, required this.to, this.embed = false, this.mark});
  final int line;
  final String text;

  /// Where in [text] the link or the mention is, to be drawn so; null where it was cut off.
  final (int, int)? mark;

  /// The link, or the mention, in the note's body.
  final int from;
  final int to;
  final bool embed;
}

/// A note that says another's name, or one of its aliases, as words and does not link it.
@immutable
class Mention {
  const Mention({required this.id, required this.title, required this.places, required this.name});
  final String id;
  final String title;

  /// Each place it says it, the first few, in order.
  final List<LinkPlace> places;

  /// The name it says, as the other note has it: its title or an alias.
  final String name;
}

/// The library's notes and their links, for [LinkIndexer] or a test (see the library's doc).
class LinkIndex {
  LinkIndex();

  /// A whole library read at once: what the worker runs.
  factory LinkIndex.build(Iterable<LinkSource> notes) {
    final index = LinkIndex();
    for (final note in notes) {
      index.put(LinkFacts.read(note.id, note.body, path: note.path, updatedAt: note.updatedAt));
    }
    return index;
  }

  final Map<String, LinkFacts> _notes = <String, LinkFacts>{};

  /// Who links to a name, by its key; and to a file, by its path.
  final Map<String, Set<String>> _byKey = <String, Set<String>>{};
  final Map<String, Set<String>> _byPath = <String, Set<String>>{};

  /// Who answers to a name: by title, by ticket's key, by alias; and who is kept at a path.
  final Map<String, Set<String>> _titles = <String, Set<String>>{};
  final Map<String, Set<String>> _tickets = <String, Set<String>>{};
  final Map<String, Set<String>> _aliases = <String, Set<String>>{};
  final Map<String, Set<String>> _paths = <String, Set<String>>{};

  /// Who says a word, and one string for each word.
  final Map<String, Set<String>> _byWord = <String, Set<String>>{};

  /// Counted up at every change, so whatever was worked out from the index can tell it is out of date.
  int version = 0;

  int get length => _notes.length;
  Iterable<String> get ids => _notes.keys;
  LinkFacts? factsOf(String id) => _notes[id];

  /// The notes whose words say [word] ([wordsIn]'s form: lower case, letters and digits): what a ticket's likely
  /// duplicates are first looked for in (lib/book/ticket_duplicates.dart).
  Set<String> notesSaying(String word) => _byWord[word] ?? const <String>{};

  /// [facts] in place of whatever was kept for its note.
  void put(LinkFacts facts) {
    remove(facts.id);
    _notes[facts.id] = facts;
    for (final link in facts.links) {
      if (link.key.isNotEmpty) (_byKey[link.key] ??= <String>{}).add(facts.id);
      final path = link.path;
      if (path != null && path.isNotEmpty) (_byPath[path] ??= <String>{}).add(facts.id);
    }
    if (facts.key.isNotEmpty) (_titles[facts.key] ??= <String>{}).add(facts.id);
    if (facts.ticketKey.isNotEmpty) (_tickets[facts.ticketKey] ??= <String>{}).add(facts.id);
    for (final alias in facts.aliasKeys) {
      if (alias.isNotEmpty) (_aliases[alias] ??= <String>{}).add(facts.id);
    }
    if (facts.path.isNotEmpty) (_paths[facts.path] ??= <String>{}).add(facts.id);
    for (final word in facts.words) {
      (_byWord[word] ??= <String>{}).add(facts.id);
    }
    version += 1;
  }

  /// The note by that id taken out.
  void remove(String id) {
    final facts = _notes.remove(id);
    if (facts == null) return;
    void off(Map<String, Set<String>> map, String key) {
      final set = map[key];
      if (set == null) return;
      set.remove(id);
      if (set.isEmpty) map.remove(key);
    }

    for (final link in facts.links) {
      off(_byKey, link.key);
      final path = link.path;
      if (path != null) off(_byPath, path);
    }
    off(_titles, facts.key);
    off(_tickets, facts.ticketKey);
    for (final alias in facts.aliasKeys) {
      off(_aliases, alias);
    }
    off(_paths, facts.path);
    for (final word in facts.words) {
      off(_byWord, word);
    }
    version += 1;
  }

  /// The note's edit time moved and its words did not: kept, for which of two notes of one title a link means.
  void touch(String id, int updatedAt) {
    final facts = _notes[id];
    if (facts == null || facts.updatedAt == updatedAt) return;
    facts.updatedAt = updatedAt;
    version += 1;
  }

  /// Of [owners], the one a link means: a note of the person's before a template's page, then the newest.
  String? _best(Set<String>? owners) {
    if (owners == null || owners.isEmpty) return null;
    if (owners.length == 1) return owners.first;
    LinkFacts? best;
    for (final id in owners) {
      final facts = _notes[id]!;
      if (best == null ||
          (best.templatePage && !facts.templatePage) ||
          (best.templatePage == facts.templatePage && (facts.updatedAt > best.updatedAt || (facts.updatedAt == best.updatedAt && facts.id.compareTo(best.id) < 0)))) {
        best = facts;
      }
    }
    return best?.id;
  }

  /// The note a name means, by its key: a title, then a ticket's key, then an alias.
  String? resolve(String key) {
    if (key.isEmpty) return null;
    return _best(_titles[key]) ?? _best(_tickets[key]) ?? _best(_aliases[key]);
  }

  /// The note a link written in [from] means, or null where it means none.
  String? targetOf(LinkOut link, {String? from}) {
    final path = link.path;
    if (path != null) {
      final at = _best(_paths[path]);
      if (at != null) return at;
      // A link written beside its note: the same folder as the note it is in.
      final source = from == null ? null : _notes[from]?.path;
      if (source != null && source.contains('/')) {
        final joined = _joined(source.substring(0, source.lastIndexOf('/')), path);
        final there = _best(_paths[joined]);
        if (there != null) return there;
      }
    }
    return resolve(link.key);
  }

  /// The keys and paths by which [id] is linked to now: each of its names that means it.
  ({List<String> keys, String path}) _namesOf(LinkFacts facts) => (
        keys: [
          for (final key in facts.nameKeys)
            if (resolve(key) == facts.id) key,
        ],
        path: facts.path,
      );

  /// The notes that may link to [id]: written with one of its names, or its file's.
  Set<String> _maybeLinking(LinkFacts facts) {
    final names = _namesOf(facts);
    final out = <String>{};
    for (final key in names.keys) {
      out.addAll(_byKey[key] ?? const <String>{});
    }
    if (names.path.isNotEmpty) {
      out.addAll(_byPath[names.path] ?? const <String>{});
      final name = names.path.contains('/') ? names.path.substring(names.path.lastIndexOf('/') + 1) : names.path;
      out.addAll(_byKey[titleKey(name)] ?? const <String>{});
    }
    out.remove(facts.id);
    return out;
  }

  /// The links [source] makes to [target].
  List<LinkOut> linksTo(String source, String target) {
    final facts = _notes[source];
    if (facts == null) return const [];
    return [
      for (final link in facts.links)
        if (targetOf(link, from: source) == target) link,
    ];
  }

  /// The ids of the notes that link to [id], in no order.
  Set<String> linkingTo(String id) {
    final facts = _notes[id];
    if (facts == null) return const {};
    return {
      for (final source in _maybeLinking(facts))
        if (linksTo(source, id).isNotEmpty) source,
    };
  }

  /// How many notes link to [id].
  int backlinkCount(String id) => linkingTo(id).length;

  /// The notes [id] links to, each once, itself left out.
  Set<String> linkedFrom(String id) {
    final facts = _notes[id];
    if (facts == null) return const {};
    return {
      for (final link in facts.links)
        if (targetOf(link, from: id) case final target? when target != id) target,
    };
  }

  /// Every note that links to [id], with the line round each link: [bodyOf] is each note's words now. The notes
  /// in title order.
  List<Backlink> backlinksOf(String id, String? Function(String id) bodyOf) {
    final out = <Backlink>[];
    for (final source in linkingTo(id)) {
      final body = bodyOf(source);
      final facts = _notes[source];
      if (body == null || facts == null) continue;
      out.add(Backlink(
        id: source,
        title: facts.title,
        links: [
          for (final link in linksTo(source, id))
            if (link.to <= body.length) placeIn(body, link.from, link.to, embed: link.embed),
        ],
      ));
    }
    out.sort((a, b) => _byTitle(a.title, b.title));
    return out;
  }

  /// The notes that say [id]'s title or one of its aliases as words and do not link to it, with the first few
  /// places each says it ([most]). A note that answers to the same name itself is left out: its own heading is
  /// not a mention.
  List<Mention> mentionsOf(String id, String? Function(String id) bodyOf, {int most = 3}) {
    final facts = _notes[id];
    if (facts == null) return const [];
    final linking = linkingTo(id);
    final names = <String>[if (facts.key.isNotEmpty) facts.title, ...facts.aliases];
    final found = <String, Mention>{};
    for (final name in names) {
      final words = titleKey(name).split(' ').where((word) => word.isNotEmpty).toList();
      if (words.isEmpty) continue;
      // The rarest word's notes are the only ones that can say the name.
      Set<String>? fewest;
      for (final word in words) {
        final holders = _byWord[word];
        if (holders == null) {
          fewest = const {};
          break;
        }
        if (fewest == null || holders.length < fewest.length) fewest = holders;
      }
      if (fewest == null || fewest.isEmpty) continue;
      final pattern = mentionPattern(name);
      final key = titleKey(name);
      for (final other in fewest) {
        if (other == id || linking.contains(other) || found.containsKey(other)) continue;
        final its = _notes[other];
        if (its == null || its.nameKeys.contains(key)) continue;
        if (!words.every((word) => _byWord[word]?.contains(other) ?? false)) continue;
        final body = bodyOf(other);
        if (body == null) continue;
        final plain = plainText(body);
        final places = <LinkPlace>[];
        for (final match in pattern.allMatches(plain)) {
          places.add(placeIn(body, match.start, match.end));
          if (places.length >= most) break;
        }
        if (places.isNotEmpty) found[other] = Mention(id: other, title: its.title, places: places, name: name);
      }
    }
    return found.values.toList()..sort((a, b) => _byTitle(a.title, b.title));
  }

  /// Every note with a title and the links between them, each pair once: what the graph is drawn from. [keep] says
  /// which notes are drawn; all of them when it is null.
  LinkGraph graph({bool Function(String id)? keep}) {
    final ids = <String>[
      for (final id in _notes.keys)
        if (keep == null || keep(id)) id,
    ]..sort();
    final at = <String, int>{for (var i = 0; i < ids.length; i += 1) ids[i]: i};
    final pairs = <int>{};
    final from = <int>[], to = <int>[];
    for (var i = 0; i < ids.length; i += 1) {
      for (final target in linkedFrom(ids[i])) {
        final j = at[target];
        if (j == null || j == i) continue;
        final a = i < j ? i : j, b = i < j ? j : i;
        if (pairs.add(a * ids.length + b)) {
          from.add(a);
          to.add(b);
        }
      }
    }
    return LinkGraph(ids: ids, titles: [for (final id in ids) _notes[id]!.title], from: from, to: to);
  }
}

/// A note to be read into the index: what crosses to the worker.
typedef LinkSource = ({String id, String body, String? path, int updatedAt});

/// The notes and the links between them, as indexes into [ids]: edge `i` joins `from[i]` and `to[i]`.
@immutable
class LinkGraph {
  const LinkGraph({required this.ids, required this.titles, required this.from, required this.to});
  final List<String> ids;
  final List<String> titles;
  final List<int> from;
  final List<int> to;

  int get length => ids.length;

  /// How many links each note has, in or out.
  List<int> get degrees {
    final counts = List<int>.filled(ids.length, 0);
    for (var i = 0; i < from.length; i += 1) {
      counts[from[i]] += 1;
      counts[to[i]] += 1;
    }
    return counts;
  }

  /// The notes within [depth] links of [id], it among them, and the links between them: a note's local graph.
  LinkGraph around(String id, int depth) {
    final start = ids.indexOf(id);
    if (start < 0) return LinkGraph(ids: const [], titles: const [], from: const [], to: const []);
    final next = List<List<int>>.generate(ids.length, (_) => <int>[]);
    for (var i = 0; i < from.length; i += 1) {
      next[from[i]].add(to[i]);
      next[to[i]].add(from[i]);
    }
    final seen = <int>{start};
    var ring = <int>[start];
    for (var step = 0; step < depth; step += 1) {
      final further = <int>[];
      for (final node in ring) {
        for (final other in next[node]) {
          if (seen.add(other)) further.add(other);
        }
      }
      ring = further;
    }
    final kept = seen.toList()..sort();
    final at = <int, int>{for (var i = 0; i < kept.length; i += 1) kept[i]: i};
    final a = <int>[], b = <int>[];
    for (var i = 0; i < from.length; i += 1) {
      final x = at[from[i]], y = at[to[i]];
      if (x != null && y != null) {
        a.add(x);
        b.add(y);
      }
    }
    return LinkGraph(ids: [for (final i in kept) ids[i]], titles: [for (final i in kept) titles[i]], from: a, to: b);
  }
}

int _byTitle(String a, String b) {
  final byWords = a.toLowerCase().compareTo(b.toLowerCase());
  return byWords != 0 ? byWords : a.compareTo(b);
}

/// A name as words in a note's text: its words in order, anything but letters and digits between them, and no
/// letter or digit either side, in any case. "Launch week" is said in "the launch-week photos".
RegExp mentionPattern(String name) {
  final words = titleKey(name).split(' ').where((word) => word.isNotEmpty).map(RegExp.escape).join(r'[^A-Za-z0-9\n]+');
  return RegExp('(?<![A-Za-z0-9])$words(?![A-Za-z0-9])', caseSensitive: false);
}

final RegExp _lineLead = RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)*');

/// The line [from] stands on in [body]: its number from 0 and its words, its lead (a heading's signs, a list's
/// mark, a box) off and cut to about a hundred and forty characters round the place.
LinkPlace placeIn(String body, int from, int to, {bool embed = false, int most = 140}) {
  final start = body.lastIndexOf('\n', from > 0 ? from - 1 : 0) + 1;
  var end = body.indexOf('\n', from);
  if (end < 0) end = body.length;
  var line = 0;
  for (var i = body.indexOf('\n'); i >= 0 && i < start; i = body.indexOf('\n', i + 1)) {
    line += 1;
  }
  var text = body.substring(start < from ? start : from, end);
  final lead = _lineLead.matchAsPrefix(text);
  var cut = lead?.end ?? 0;
  if (cut > from - start) cut = 0;
  text = text.substring(cut).trimRight();
  // Where the link or the mention is in the words shown, as it is cut down.
  var at = from - start - cut;
  final long = (to < end ? to : end) - from;
  if (text.length > most) {
    final begin = (at - most ~/ 3).clamp(0, text.length);
    final stop = (begin + most).clamp(0, text.length);
    final kept = text.substring(begin, stop);
    final lost = kept.length - kept.trimLeft().length;
    text = '${begin > 0 ? '…' : ''}${kept.trim()}${stop < text.length ? '…' : ''}';
    at = at - begin - lost + (begin > 0 ? 1 : 0);
  }
  final shown = text.trim();
  final lostStart = text.length - text.trimLeft().length;
  at -= lostStart;
  final mark = at >= 0 && at + long <= shown.length && long > 0 ? (at, at + long) : null;
  return LinkPlace(line: line, text: shown, from: from, to: to, embed: embed, mark: mark);
}

String _joined(String folder, String path) {
  final parts = <String>[...folder.split('/').where((part) => part.isNotEmpty)];
  for (final part in path.split('/')) {
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  return parts.join('/');
}

// ---- kept with the library ----------------------------------------------------------------------------------------

/// Reads the whole library in a worker isolate: the index handed back whole.
Future<LinkIndex> buildLinkIndexElsewhere(List<LinkSource> notes) => Isolate.run(() => LinkIndex.build(notes), debugName: 'link index');

/// The app's one [LinkIndex], kept with the library: made from the whole of it in a worker, then told each note
/// that changed. Listen to it: it says when the index moved, which is when a panel or the graph reads it again.
///
/// [notes] are the notes every screen shows (none in the Trash); [changes] says when they changed. Each change
/// looks at the list once (a note that is the same object as before has not changed: lib/core/library.dart) and
/// reads again only the notes whose words or file moved.
class LinkIndexer extends ChangeNotifier {
  LinkIndexer({required this.notes, this.changes, this.inlineUpTo = 64, Future<LinkIndex> Function(List<LinkSource> notes)? build}) : _build = build ?? buildLinkIndexElsewhere {
    changes?.addListener(_changed);
    _changed();
  }

  final List<Note> Function() notes;
  final Listenable? changes;

  /// The most notes read on the UI isolate at once; more than that, the worker reads the whole library again. A
  /// library this small is read where it is: a worker costs more to start than the reading.
  final int inlineUpTo;
  final Future<LinkIndex> Function(List<LinkSource> notes) _build;

  LinkIndex _index = LinkIndex();

  /// The index as it stands. Empty until the first reading is done ([ready]).
  LinkIndex get index => _index;

  /// The notes as they were last read, by id.
  Map<String, Note> _seen = <String, Note>{};

  bool _ready = false;
  bool _building = false;
  bool _again = false;
  bool _gone = false;

  /// Whether the whole library has been read once.
  bool get ready => _ready;

  /// How long the last change took to read, for a test and the Developer page: the notes looked at, the notes
  /// read again, and the time on the UI isolate.
  ({int looked, int read, Duration took})? lastChange;

  /// The words of a note as the index last read them.
  String? bodyOf(String id) => _seen[id]?.body;

  void _changed() {
    if (_gone) return;
    if (_building) {
      _again = true;
      return;
    }
    final watch = Stopwatch()..start();
    final now = notes();
    final changed = <Note>[];
    final ids = <String>{};
    for (final note in now) {
      ids.add(note.id);
      final had = _seen[note.id];
      if (identical(had, note)) continue;
      if (had == null || had.body != note.body || had.path != note.path) {
        changed.add(note);
      } else {
        _seen[note.id] = note;
        _index.touch(note.id, note.updatedAt);
      }
    }
    final gone = [
      for (final id in _seen.keys)
        if (!ids.contains(id)) id,
    ];
    if (changed.isEmpty && gone.isEmpty) {
      if (!_ready) {
        _ready = true;
        notifyListeners();
      }
      return;
    }
    if (changed.length > inlineUpTo) {
      _rebuild(now);
      return;
    }
    for (final id in gone) {
      _seen.remove(id);
      _index.remove(id);
    }
    for (final note in changed) {
      _seen[note.id] = note;
      _index.put(LinkFacts.read(note.id, note.body, path: note.path, updatedAt: note.updatedAt));
    }
    lastChange = (looked: now.length, read: changed.length, took: watch.elapsed);
    _ready = true;
    notifyListeners();
  }

  void _rebuild(List<Note> now) {
    _building = true;
    final sources = <LinkSource>[for (final note in now) (id: note.id, body: note.body, path: note.path, updatedAt: note.updatedAt)];
    final seen = <String, Note>{for (final note in now) note.id: note};
    unawaited(_build(sources).then((built) {
      if (_gone) return;
      _index = built;
      _seen = seen;
      _building = false;
      _ready = true;
      notifyListeners();
      // What changed while the worker read is read now, a note at a time.
      if (_again) {
        _again = false;
        _changed();
      }
    }, onError: (Object error) {
      _building = false;
      if (_gone) return;
      debugPrint('[glyph] the link index could not be read: $error');
      // Read where it is instead: slower, and still right.
      _index = LinkIndex.build(sources);
      _seen = seen;
      _ready = true;
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    _gone = true;
    changes?.removeListener(_changed);
    super.dispose();
  }
}
