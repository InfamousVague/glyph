/// What may have made a page out of date, read from the page and the library alone (docs/NOTE_DECAY.md §1.1; Matt,
/// 2026-11-02: "docs and pages that reference things that have since changed (a renamed ticket, a merged PR on
/// GitHub, an old date) get a quiet 'may be out of date' mark with the reason"). The cheap layer: no model, no
/// network. GitHub's and Figma's answers come in from lookups.dart and are turned into signals here too
/// ([remoteSignalsOf]), so every reason is worded in one file.
///
/// Every signal is one line of the page (or its head), a reason in plain words, and a stamp: what its source said,
/// so a "Still right" (dismissals.dart) holds until the source changes again. Pure but for [remoteSignalsOf]'s
/// lookups, which a test hands in.
library;

import 'package:flutter/foundation.dart';

import '../../core/front_matter.dart' show frontMatterSpan, frontMatterValue, isTicketKey;
import '../../core/properties.dart' show StatusCategory, doneKey, statusCategory, ticketIdOf;
import 'dates.dart';
import 'lookups.dart';

/// What a signal is about.
enum DecayKind {
  /// A `[[link]]` to a note renamed, in the trash or archived.
  link,

  /// A ticket the page names, closed since the page was last edited.
  ticket,

  /// A GitHub issue or pull request the page links, merged or closed since.
  github,

  /// A date the page speaks of as ahead, now past.
  date,

  /// A Figma frame the page links that Figma says is gone.
  figma,

  /// A docs page not edited in months while the pages it links changed.
  stale,

  /// What the AI pass found (ai.dart).
  ai,
}

/// One reason a page may be out of date.
@immutable
class DecaySignal {
  const DecaySignal({required this.kind, required this.key, required this.stamp, required this.reason, this.line, this.quote = '', this.source});

  final DecayKind kind;

  /// What it is about, within its kind: the link's title, the ticket's key, the PR's address, the date as written.
  final String key;

  /// What the source said when this was made; a dismissal holds until it differs.
  final String stamp;

  /// The words after "May be out of date: ".
  final String reason;

  /// The page's line it is on, from 0 (the body's, front matter and all); null for the page's head.
  final int? line;

  /// The words of the line it is about, for the AI pass and Update with AI to be shown.
  final String quote;

  /// The note it points at, by id, where it is another note (a renamed link, a ticket, a changed linked page).
  final String? source;

  /// The signal across stamps: `ticket:GHO-12`.
  String get id => '${kind.name}:$key';

  /// What a dismissal keeps: `ticket:GHO-12@Done 2026-10-30`.
  String get token => '$id@$stamp';

  @override
  bool operator ==(Object other) => other is DecaySignal && other.token == token && other.line == line && other.reason == reason;

  @override
  int get hashCode => Object.hash(token, line, reason);

  @override
  String toString() => 'DecaySignal($token, line $line: $reason)';
}

/// A note as the checks read it.
@immutable
class DecayNote {
  const DecayNote({required this.id, required this.title, required this.body, required this.edited, this.trashed = false, this.archived = false, this.docPage = false});

  final String id;
  final String title;
  final String body;

  /// When the note was last edited.
  final DateTime edited;
  final bool trashed;
  final bool archived;

  /// A page of a docs notebook (`type: docs`, docs/TEAMSPACES.md): the `stale` check is for these alone.
  final bool docPage;
}

/// The library as the checks read it: every note, and what each title was before it was renamed.
class DecayLibrary {
  DecayLibrary(Iterable<DecayNote> notes, {Map<String, String> renamed = const {}})
      : notes = List.unmodifiable(notes),
        _renamed = {for (final MapEntry(:key, :value) in renamed.entries) _fold(key): value} {
    for (final note in this.notes) {
      _byTitle.putIfAbsent(_fold(note.title), () => note);
      final ticket = ticketIdOf(note.body);
      if (ticket != null) _byTicket.putIfAbsent(ticket, () => note);
    }
  }

  final List<DecayNote> notes;
  final Map<String, String> _renamed;
  final Map<String, DecayNote> _byTitle = {};
  final Map<String, DecayNote> _byTicket = {};

  /// The note called [title] now, in any case.
  DecayNote? byTitle(String title) => _byTitle[_fold(title)];

  /// The ticket whose key is [key] (`GHO-12`, any case).
  DecayNote? ticket(String key) => _byTicket[key.trim().toUpperCase()];

  /// What the note once called [title] is called now, following renames to the last; null where none was.
  String? renamedTo(String title) {
    String? now;
    var at = _fold(title);
    final seen = <String>{};
    while (seen.add(at)) {
      final next = _renamed[at];
      if (next == null) break;
      now = next;
      at = _fold(next);
    }
    return now;
  }
}

String _fold(String title) => title.trim().toLowerCase();

DateTime _dayOf(DateTime time) => DateTime(time.year, time.month, time.day);

/// `[[Title]]`, `[[Title|shown]]`, `[[Title#Heading]]`: the title.
final RegExp _wikiLink = RegExp(r'\[\[([^\]\n|#]+)(?:[#|][^\]\n]*)?\]\]');

/// A bare ticket key in a sentence: `GHO-12`.
final RegExp _bareKey = RegExp(r'(?<![\w\[-])([A-Z][A-Z0-9]{1,9}-[1-9]\d{0,5})(?![\w\]])');

final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// The lines of [body] the checks read: their numbers, front matter and fenced code left out.
Iterable<(int, String)> _proseLines(String body) sync* {
  final lines = body.split('\n');
  final from = frontMatterSpan(body).lines;
  var inFence = false;
  for (var i = from; i < lines.length; i++) {
    final line = lines[i];
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (!inFence) yield (i, line);
  }
}

/// The `[[link]]` titles of [body], each once, in order: what `stale` and the AI pass read as the page's sources.
List<String> linkedTitles(String body) {
  final seen = <String>{};
  return [
    for (final (_, line) in _proseLines(body))
      for (final match in _wikiLink.allMatches(line))
        if (seen.add(_fold(match[1]!))) match[1]!.trim(),
  ];
}

/// The deterministic signals of [note] in [library] at [now], line by line, then the page's head: every kind but
/// `github`, `figma` and `ai`. [staleMonths] is how long a docs page goes unedited before `stale` asks.
List<DecaySignal> signalsOf(DecayNote note, DecayLibrary library, {required DateTime now, int staleMonths = 3}) {
  final out = <DecaySignal>[];
  final editedDay = _dayOf(note.edited);
  final today = _dayOf(now);
  for (final (index, line) in _proseLines(note.body)) {
    final quote = line.trim();
    final keysLinked = <String>{};
    for (final match in _wikiLink.allMatches(line)) {
      final title = match[1]!.trim();
      if (isTicketKey(title)) {
        keysLinked.add(title.toUpperCase());
        continue;
      }
      final target = library.byTitle(title);
      if (target == null) {
        final now = library.renamedTo(title);
        if (now != null && library.byTitle(now) != null) {
          out.add(DecaySignal(kind: DecayKind.link, key: title, stamp: now, reason: '[[$title]] was renamed to [[$now]]', line: index, quote: quote, source: library.byTitle(now)!.id));
        }
      } else if (target.id != note.id && target.trashed) {
        out.add(DecaySignal(kind: DecayKind.link, key: title, stamp: 'trashed', reason: '[[$title]] is in the trash', line: index, quote: quote, source: target.id));
      } else if (target.id != note.id && target.archived) {
        out.add(DecaySignal(kind: DecayKind.link, key: title, stamp: 'archived', reason: '[[$title]] was archived', line: index, quote: quote, source: target.id));
      }
    }
    for (final match in _bareKey.allMatches(line)) {
      keysLinked.add(match[1]!);
    }
    for (final key in keysLinked) {
      final ticket = library.ticket(key);
      if (ticket == null || ticket.id == note.id) continue;
      final status = frontMatterValue(ticket.body, 'status')?.trim() ?? '';
      if (statusCategory(status) != StatusCategory.done) continue;
      final doneDay = DateTime.tryParse(frontMatterValue(ticket.body, doneKey)?.trim() ?? '') ?? ticket.edited;
      if (_dayOf(doneDay).isBefore(editedDay)) continue;
      final said = _closedWords(status);
      out.add(DecaySignal(kind: DecayKind.ticket, key: key, stamp: '$status ${_iso(doneDay)}', reason: '$key was $said on ${dayWords(doneDay, now: now)}', line: index, quote: quote, source: ticket.id));
    }
    for (final date in datesIn(line, edited: note.edited)) {
      if (!date.day.isBefore(today)) continue;
      if (!looksAhead(sentenceAt(line, date.start))) continue;
      out.add(DecaySignal(kind: DecayKind.date, key: date.text, stamp: _iso(date.day), reason: '${dayWords(date.day, now: now)} has passed; this still speaks of it as ahead', line: index, quote: quote));
    }
  }
  final stale = _staleOf(note, library, now: now, staleMonths: staleMonths);
  if (stale != null) out.add(stale);
  return out;
}

/// The words for a ticket's done status: "closed" for the plain ones, else "marked Shipped".
String _closedWords(String status) {
  const plain = {'done', 'closed', 'resolved', 'complete', 'completed', 'finished', 'fixed'};
  return status.isEmpty || plain.contains(status.toLowerCase()) ? 'closed' : 'marked $status';
}

String _iso(DateTime day) => '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

DecaySignal? _staleOf(DecayNote note, DecayLibrary library, {required DateTime now, required int staleMonths}) {
  if (!note.docPage) return null;
  final cutoff = DateTime(now.year, now.month - staleMonths, now.day);
  if (!note.edited.isBefore(cutoff)) return null;
  final changed = [
    for (final title in linkedTitles(note.body))
      if (library.byTitle(title) case final linked? when linked.id != note.id && !linked.trashed && linked.edited.isAfter(note.edited)) linked,
  ];
  if (changed.isEmpty) return null;
  final newest = changed.map((n) => n.edited).reduce((a, b) => a.isAfter(b) ? a : b);
  final names = changed.take(2).map((n) => '[[${n.title}]]').join(' and ');
  final more = changed.length > 2 ? ' and ${changed.length - 2} more' : '';
  return DecaySignal(kind: DecayKind.stale, key: 'page', stamp: _iso(newest), reason: 'Not edited since ${dayWords(note.edited, now: now)}, and $names$more changed since', source: changed.first.id);
}

/// A github.com issue or pull request: owner, repository, which, number.
final RegExp _githubLink = RegExp(r'https?://(?:www\.)?github\.com/([\w.-]+)/([\w.-]+)/(pull|issues)/(\d+)');

/// A figma.com design or file link.
final RegExp _figmaLink = RegExp(r'https?://(?:www\.)?figma\.com/(?:design|file|proto)/[A-Za-z0-9]+[^\s)\]>]*');

/// The GitHub and Figma links of [note], each once: what [remoteSignalsOf] would ask about.
({List<GithubRef> github, List<String> figma}) remoteLinksOf(DecayNote note) {
  final github = <GithubRef>[], figma = <String>[];
  final seen = <String>{};
  for (final (index, line) in _proseLines(note.body)) {
    for (final match in _githubLink.allMatches(line)) {
      final ref = GithubRef(owner: match[1]!, repo: match[2]!, pull: match[3] == 'pull', number: int.parse(match[4]!), line: index, quote: line.trim());
      if (seen.add(ref.key)) github.add(ref);
    }
    for (final match in _figmaLink.allMatches(line)) {
      if (seen.add(match[0]!)) figma.add(match[0]!);
    }
  }
  return (github: github, figma: figma);
}

/// The signals GitHub and Figma give for [note], asked of [lookups]: none of either where its lookups are off (Local
/// only, or its plugin not connected). A lookup that fails says nothing.
Future<List<DecaySignal>> remoteSignalsOf(DecayNote note, DecayLookups lookups, {required DateTime now}) async {
  final links = remoteLinksOf(note);
  final out = <DecaySignal>[];
  final editedDay = _dayOf(note.edited);
  if (lookups.githubOn) {
    for (final ref in links.github) {
      final state = await lookups.github(ref).catchError((Object _) => null);
      if (state == null || state.state == GithubStateKind.open) continue;
      final at = state.at;
      if (at != null && _dayOf(at.toLocal()).isBefore(editedDay)) continue;
      final what = ref.pull ? 'PR #${ref.number}' : 'Issue #${ref.number}';
      final how = state.state == GithubStateKind.merged ? 'merged' : 'closed';
      final when = at == null ? '' : ' on ${dayWords(at.toLocal(), now: now)}';
      out.add(DecaySignal(kind: DecayKind.github, key: ref.key, stamp: '$how@${at == null ? '' : _iso(at.toLocal())}', reason: '$what in ${ref.owner}/${ref.repo} was $how$when', line: ref.line, quote: ref.quote));
    }
  }
  if (lookups.figmaOn) {
    for (final url in links.figma) {
      final gone = await lookups.figmaGone(url).catchError((Object _) => false);
      if (gone != true) continue;
      final (line, quote) = _lineOf(note.body, url);
      out.add(DecaySignal(kind: DecayKind.figma, key: url, stamp: 'gone', reason: url.contains('node-id') ? 'The Figma frame this links to is gone' : 'The Figma file this links to is gone', line: line, quote: quote));
    }
  }
  return out;
}

(int?, String) _lineOf(String body, String text) {
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(text)) return (i, lines[i].trim());
  }
  return (null, '');
}
