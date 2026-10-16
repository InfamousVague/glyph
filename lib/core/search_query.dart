/// What a search query asks for beyond its words: the operators Matt asked for on 2026-10-16 ("Add each of those",
/// after a look at what Evernote and Obsidian find with), read out of what is typed. Pure: a query in, a
/// [SearchQuery] out, and every rule here is a test (test/organize/search_query_test.dart).
///
///     tag:work            a note tagged #work, or #work/clients and any other tag under it (also written #work)
///     in:"Field notes"    a note in that workspace (and the folders inside it), or a page of that notebook
///     is:pinned           pinned
///     is:archived         in the archive, which a search otherwise leaves out
///     is:todo, has:todo   with a to-do still open
///     is:done             with to-dos, every one ticked; or a ticket whose status is done
///     is:ticket           a ticket (also is:notebook, is:journal, is:canvas)
///     has:image           with a picture in it
///     has:link            with a link to another note or a web address
///     has:recording       with a recording (its tape, or a voice memo)
///     before:2026-10-01   made before that day
///     after:2026-10-01    made on that day or later
///     created:<7d         made in the last seven days (and >7d, a date, <date, >date, as updated: takes)
///     updated:<7d         changed in the last seven days; updated:>30d not for thirty days; updated:2026-10-01
///                         changed that day; updated:<2026-10-01 before it, updated:>2026-10-01 after it
///     "exact phrase"      those words together, in that order
///     -word, -tag:x       not that word, not that tag: a minus before any of these turns it round
///
/// **Made, or changed.** `before:` and `after:` are about when a note was made, the day it was written, which is
/// the question a person asks of a journal or a meeting ("what did I write before the trip"). `updated:` is about
/// the last change. `created:` takes the same forms as `updated:` for the day it was made. A date is the phone's
/// own day (`2026-10-01` from its midnight), a month (`2026-10`) or a year (`2026`), or `today` or `yesterday`; a
/// span is days (`7d`), weeks (`2w`), months of thirty days (`3m`) or years of 365 (`1y`).
///
/// Operators combine with AND, every one of them must hold; the words left over are the search's own and keep
/// its ranking (lib/core/search_hits.dart). A word with a colon that is none of these, or one of these with a value
/// it does not know (`is:blue`), stays a plain word, so nothing typed is ever silently dropped. Upper or lower case
/// are the same everywhere.
///
/// [SearchQuery.parts] says what was understood, each operator with where it was typed and a few words for it, for
/// the chips under a search field (lib/home/search_hints.dart).
library;

import 'package:flutter/foundation.dart';

/// What an `is:` asks of a note.
enum SearchIs { pinned, archived, todo, done, ticket, notebook, journal, canvas }

/// What a `has:` asks of a note.
enum SearchHas { todo, image, link, recording }

/// A span of time, from (inclusive) to (exclusive), in milliseconds since the epoch; an end left null is open.
@immutable
class TimeSpan {
  const TimeSpan({this.from, this.to});
  final int? from;
  final int? to;

  bool holds(int at) => (from == null || at >= from!) && (to == null || at < to!);

  /// This span and [other] both: the later start and the earlier end.
  TimeSpan and(TimeSpan other) => TimeSpan(
        from: from == null ? other.from : (other.from == null || from! >= other.from! ? from : other.from),
        to: to == null ? other.to : (other.to == null || to! <= other.to! ? to : other.to),
      );

  @override
  bool operator ==(Object other) => other is TimeSpan && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'TimeSpan($from, $to)';
}

/// Which operator a part of the query is.
enum SearchPartKind { tag, place, isFlag, has, made, changed, phrase, without }

/// One operator as it was typed: what it is, where it stands in the query, and its words for a chip.
@immutable
class SearchPart {
  const SearchPart({required this.kind, required this.label, required this.start, required this.end, this.negated = false});

  final SearchPartKind kind;

  /// What it asks for, in a few plain words: "Tagged #work", "Not pinned", "Made before 2026-10-01".
  final String label;

  /// Where it was typed, as offsets into the query.
  final int start;
  final int end;
  final bool negated;

  @override
  bool operator ==(Object other) => other is SearchPart && other.kind == kind && other.label == label && other.start == start && other.end == end && other.negated == negated;

  @override
  int get hashCode => Object.hash(kind, label, start, end, negated);

  @override
  String toString() => 'SearchPart(${kind.name}, "$label", $start-$end${negated ? ', not' : ''})';
}

/// A query read ([parseSearch]).
@immutable
class SearchQuery {
  const SearchQuery({
    this.text = '',
    this.words = const [],
    this.phrases = const [],
    this.without = const [],
    this.withoutPhrases = const [],
    this.tags = const [],
    this.notTags = const [],
    this.places = const [],
    this.notPlaces = const [],
    this.isFlags = const {},
    this.notIs = const {},
    this.has = const {},
    this.notHas = const {},
    this.made = const TimeSpan(),
    this.changed = const TimeSpan(),
    this.parts = const [],
  });

  /// What was typed.
  final String text;

  /// The plain words, lower case, in the order typed: the ones a search ranks by.
  final List<String> words;

  /// Each `"exact phrase"`, lower case, its spaces made one.
  final List<String> phrases;

  /// `-word` and `-"a phrase"`: lower case, without the minus.
  final List<String> without;
  final List<String> withoutPhrases;

  /// `tag:` (and `#tag`), lower case, without the `#`.
  final List<String> tags;
  final List<String> notTags;

  /// `in:`, lower case.
  final List<String> places;
  final List<String> notPlaces;
  final Set<SearchIs> isFlags;
  final Set<SearchIs> notIs;
  final Set<SearchHas> has;
  final Set<SearchHas> notHas;

  /// When a note was made, and last changed, must fall in these.
  final TimeSpan made;
  final TimeSpan changed;

  /// What was understood, in the order typed.
  final List<SearchPart> parts;

  /// Whether anything is asked beyond the plain words: a filter to put the notes through before they are ranked.
  bool get filters => parts.isNotEmpty;

  /// Nothing asked at all: no words and no operator.
  bool get blank => words.isEmpty && parts.isEmpty;

  /// Whether the archive is looked in: only with `is:archived`.
  bool get archived => isFlags.contains(SearchIs.archived);
}

/// The operators' names, as a person types them.
const List<String> searchKeys = ['tag', 'in', 'is', 'has', 'before', 'after', 'updated', 'created'];

const Map<String, SearchIs> _isWords = {
  'pinned': SearchIs.pinned,
  'starred': SearchIs.pinned,
  'archived': SearchIs.archived,
  'todo': SearchIs.todo,
  'todos': SearchIs.todo,
  'open': SearchIs.todo,
  'done': SearchIs.done,
  'ticket': SearchIs.ticket,
  'tickets': SearchIs.ticket,
  'notebook': SearchIs.notebook,
  'book': SearchIs.notebook,
  'journal': SearchIs.journal,
  'canvas': SearchIs.canvas,
};

const Map<String, SearchHas> _hasWords = {
  'todo': SearchHas.todo,
  'todos': SearchHas.todo,
  'task': SearchHas.todo,
  'image': SearchHas.image,
  'images': SearchHas.image,
  'picture': SearchHas.image,
  'photo': SearchHas.image,
  'link': SearchHas.link,
  'links': SearchHas.link,
  'recording': SearchHas.recording,
  'tape': SearchHas.recording,
  'audio': SearchHas.recording,
  'voice': SearchHas.recording,
};

const Map<SearchIs, (String, String)> _isSaid = {
  SearchIs.pinned: ('Pinned', 'Not pinned'),
  SearchIs.archived: ('Archived', 'Not archived'),
  SearchIs.todo: ('Open to-dos', 'No open to-dos'),
  SearchIs.done: ('All done', 'Not done'),
  SearchIs.ticket: ('Tickets', 'Not tickets'),
  SearchIs.notebook: ('Notebooks', 'Not notebooks'),
  SearchIs.journal: ('Journals', 'Not journals'),
  SearchIs.canvas: ('Canvases', 'Not canvases'),
};

const Map<SearchHas, (String, String)> _hasSaid = {
  SearchHas.todo: ('Open to-dos', 'No open to-dos'),
  SearchHas.image: ('With a picture', 'No pictures'),
  SearchHas.link: ('With a link', 'No links'),
  SearchHas.recording: ('With a recording', 'No recording'),
};

/// A tag's name as the grammar has it (lib/core/tags.dart): a letter, then letters, digits, `_`, `-` or `/`.
final RegExp _tagName = RegExp(r'^[\p{L}][\p{L}\p{N}_/-]*$', unicode: true);

final RegExp _space = RegExp(r'\s');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _day = RegExp(r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$');
final RegExp _span = RegExp(r'^(\d{1,4})\s*(d|w|m|y)$');

/// One piece of the query: where it stands, whether a minus turned it round, its key where it has one, its value
/// (unquoted), and whether it was quoted.
class _Token {
  _Token(this.start, this.end, this.negated, this.key, this.value, this.quoted, this.raw);
  final int start;
  final int end;
  final bool negated;
  final String? key;
  final String value;
  final bool quoted;

  /// The piece as typed, for a word that turns out to be no operator.
  final String raw;
}

/// The query cut into pieces at its spaces, a quote holding its spaces in: `"a b"`, `-"a b"`, `in:"Field notes"`.
/// A quote not closed runs to the end, as one being typed does.
List<_Token> _tokens(String text) {
  final out = <_Token>[];
  var at = 0;
  final n = text.length;
  while (at < n) {
    while (at < n && _space.hasMatch(text[at])) {
      at += 1;
    }
    if (at >= n) break;
    final start = at;
    var negated = false;
    if (text[at] == '-' && at + 1 < n && !_space.hasMatch(text[at + 1])) {
      negated = true;
      at += 1;
    }
    String? key;
    // A key is letters before a colon, with something after it.
    final keyAt = at;
    var k = at;
    while (k < n && _isKeyLetter(text.codeUnitAt(k))) {
      k += 1;
    }
    if (k > keyAt && k < n && text[k] == ':' && k + 1 < n && !_space.hasMatch(text[k + 1])) {
      key = text.substring(keyAt, k).toLowerCase();
      at = k + 1;
    }
    String value;
    var quoted = false;
    if (at < n && text[at] == '"') {
      quoted = true;
      final close = text.indexOf('"', at + 1);
      final end = close < 0 ? n : close;
      value = text.substring(at + 1, end);
      at = close < 0 ? n : close + 1;
      // Whatever is stuck to the closing quote belongs to the piece too: `"a b"c` is read as the phrase.
      while (at < n && !_space.hasMatch(text[at])) {
        at += 1;
      }
    } else {
      final from = at;
      while (at < n && !_space.hasMatch(text[at])) {
        at += 1;
      }
      value = text.substring(from, at);
    }
    out.add(_Token(start, at, negated, key, value, quoted, text.substring(start, at)));
  }
  return out;
}

bool _isKeyLetter(int unit) => (unit >= 97 && unit <= 122) || (unit >= 65 && unit <= 90);

/// The start of a day on the phone's clock.
int _dayStart(int year, int month, int day) => DateTime(year, month, day).millisecondsSinceEpoch;

/// What a date names, as a span: a day, a month or a year, or `today` and `yesterday`. Null for what is no date.
TimeSpan? _dateSpan(String value, DateTime now) {
  final said = value.toLowerCase();
  if (said == 'today' || said == 'yesterday') {
    final day = said == 'today' ? now : now.subtract(const Duration(days: 1));
    return TimeSpan(from: _dayStart(day.year, day.month, day.day), to: _dayStart(day.year, day.month, day.day + 1));
  }
  final m = _day.firstMatch(said);
  if (m == null) return null;
  final year = int.parse(m[1]!);
  final month = m[2] == null ? null : int.parse(m[2]!);
  final day = m[3] == null ? null : int.parse(m[3]!);
  if (month != null && (month < 1 || month > 12)) return null;
  if (day != null && (day < 1 || day > DateTime(year, month! + 1, 0).day)) return null;
  if (month == null) return TimeSpan(from: _dayStart(year, 1, 1), to: _dayStart(year + 1, 1, 1));
  if (day == null) return TimeSpan(from: _dayStart(year, month, 1), to: _dayStart(year, month + 1, 1));
  return TimeSpan(from: _dayStart(year, month, day), to: _dayStart(year, month, day + 1));
}

/// A span back from now (`7d`, `2w`, `3m`, `1y`), in milliseconds; null for what is no span.
int? _spanMs(String value) {
  final m = _span.firstMatch(value.toLowerCase());
  if (m == null) return null;
  final count = int.parse(m[1]!);
  final days = switch (m[2]) { 'd' => 1, 'w' => 7, 'm' => 30, _ => 365 };
  return count * days * Duration.millisecondsPerDay;
}

String _spanWords(String value) {
  final m = _span.firstMatch(value.toLowerCase())!;
  final count = int.parse(m[1]!);
  final unit = switch (m[2]) { 'd' => 'day', 'w' => 'week', 'm' => 'month', _ => 'year' };
  return count == 1 ? 'a $unit' : '$count ${unit}s';
}

/// `updated:` and `created:`: a span back from now, a date, or before or after one. The span the note's moment
/// must fall in, and the words for its chip; null for a value that is none of these.
(TimeSpan, String)? _when(String value, DateTime now, String verb) {
  var said = value.trim();
  var sign = '';
  if (said.startsWith('<') || said.startsWith('>')) {
    sign = said[0];
    said = said.substring(1).trim();
    // `<=` and `>=` read as the sign they open with: a day is a span, so either edge is in it.
    if (said.startsWith('=')) said = said.substring(1).trim();
  }
  if (said.isEmpty) return null;
  final back = _spanMs(said);
  final ms = now.millisecondsSinceEpoch;
  if (back != null) {
    // No sign is the last few days, as `<` is.
    if (sign == '>') return (TimeSpan(to: ms - back), '$verb over ${_spanWords(said)} ago');
    return (TimeSpan(from: ms - back), '$verb in the last ${_spanWords(said)}');
  }
  final day = _dateSpan(said, now);
  if (day == null) return null;
  return switch (sign) {
    '<' => (TimeSpan(to: day.from), '$verb before $said'),
    '>' => (TimeSpan(from: day.to), '$verb after $said'),
    _ => (day, '$verb $said'),
  };
}

/// [text] read: its words and its operators (see the library's doc). [now] is the moment `today` and `7d` are
/// counted from.
SearchQuery parseSearch(String text, {DateTime? now}) {
  if (text.trim().isEmpty) return SearchQuery(text: text);
  final moment = now ?? DateTime.now();
  final words = <String>[], phrases = <String>[], without = <String>[], withoutPhrases = <String>[];
  final tags = <String>[], notTags = <String>[], places = <String>[], notPlaces = <String>[];
  final isFlags = <SearchIs>{}, notIs = <SearchIs>{}, has = <SearchHas>{}, notHas = <SearchHas>{};
  var made = const TimeSpan(), changed = const TimeSpan();
  final parts = <SearchPart>[];

  void part(SearchPartKind kind, String label, _Token token) => parts.add(SearchPart(kind: kind, label: label, start: token.start, end: token.end, negated: token.negated));

  /// A piece that is no operator: its words, as the search has always read them.
  void plain(_Token token) {
    final said = token.raw.toLowerCase();
    if (token.negated) {
      final word = said.substring(1);
      if (word.isEmpty) return;
      without.add(word);
      part(SearchPartKind.without, 'Without “$word”', token);
    } else {
      words.addAll(said.split(_spaces).where((word) => word.isNotEmpty));
    }
  }

  for (final token in _tokens(text)) {
    final key = token.key;
    final value = token.value.trim();
    if (key == null) {
      if (token.quoted) {
        final phrase = value.toLowerCase().replaceAll(_spaces, ' ');
        if (phrase.isEmpty) continue;
        if (token.negated) {
          withoutPhrases.add(phrase);
          part(SearchPartKind.without, 'Without “$phrase”', token);
        } else {
          phrases.add(phrase);
          part(SearchPartKind.phrase, '“$phrase”', token);
        }
        continue;
      }
      // `#work` is `tag:work`, as it is written in a note.
      if (value.startsWith('#') && _tagName.hasMatch(value.substring(1).replaceFirst(RegExp(r'[-/]+$'), ''))) {
        final name = value.substring(1).replaceFirst(RegExp(r'[-/]+$'), '').toLowerCase();
        (token.negated ? notTags : tags).add(name);
        part(SearchPartKind.tag, token.negated ? 'Not #$name' : 'Tagged #$name', token);
        continue;
      }
      plain(token);
      continue;
    }
    switch (key) {
      case 'tag':
        final name = value.replaceFirst(RegExp(r'^#+'), '').replaceFirst(RegExp(r'[-/]+$'), '').toLowerCase();
        if (!_tagName.hasMatch(name)) {
          plain(token);
          continue;
        }
        (token.negated ? notTags : tags).add(name);
        part(SearchPartKind.tag, token.negated ? 'Not #$name' : 'Tagged #$name', token);
      case 'in':
        final name = value.replaceAll(_spaces, ' ').toLowerCase();
        if (name.isEmpty) {
          plain(token);
          continue;
        }
        (token.negated ? notPlaces : places).add(name);
        part(SearchPartKind.place, token.negated ? 'Not in ${value.replaceAll(_spaces, ' ')}' : 'In ${value.replaceAll(_spaces, ' ')}', token);
      case 'is':
        final flag = _isWords[value.toLowerCase()];
        if (flag == null) {
          plain(token);
          continue;
        }
        (token.negated ? notIs : isFlags).add(flag);
        final said = _isSaid[flag]!;
        part(SearchPartKind.isFlag, token.negated ? said.$2 : said.$1, token);
      case 'has':
        final what = _hasWords[value.toLowerCase()];
        if (what == null) {
          plain(token);
          continue;
        }
        (token.negated ? notHas : has).add(what);
        final said = _hasSaid[what]!;
        part(SearchPartKind.has, token.negated ? said.$2 : said.$1, token);
      case 'before':
      case 'after':
        final day = _dateSpan(value, moment);
        if (day == null) {
          plain(token);
          continue;
        }
        // A minus turns it round: -before:X is after:X, and -after:X before:X.
        final before = (key == 'before') != token.negated;
        made = made.and(before ? TimeSpan(to: day.from) : TimeSpan(from: day.from));
        part(SearchPartKind.made, before ? 'Made before $value' : 'Made $value or later', token);
      case 'updated':
      case 'created':
        var read = _when(value, moment, key == 'updated' ? 'Changed' : 'Made');
        if (read != null && token.negated) {
          // A minus turns an open span round (not in the last week is over a week ago); a closed one, a day, has
          // no one span outside it, and stays a word left out.
          final span = read.$1;
          final open = (span.from == null) != (span.to == null);
          read = open ? (TimeSpan(from: span.to, to: span.from), 'Not ${read.$2[0].toLowerCase()}${read.$2.substring(1)}') : null;
        }
        if (read == null) {
          plain(token);
          continue;
        }
        if (key == 'updated') {
          changed = changed.and(read.$1);
          part(SearchPartKind.changed, read.$2, token);
        } else {
          made = made.and(read.$1);
          part(SearchPartKind.made, read.$2, token);
        }
      default:
        plain(token);
    }
  }
  return SearchQuery(
    text: text,
    words: List.unmodifiable(words),
    phrases: List.unmodifiable(phrases),
    without: List.unmodifiable(without),
    withoutPhrases: List.unmodifiable(withoutPhrases),
    tags: List.unmodifiable(tags),
    notTags: List.unmodifiable(notTags),
    places: List.unmodifiable(places),
    notPlaces: List.unmodifiable(notPlaces),
    isFlags: Set.unmodifiable(isFlags),
    notIs: Set.unmodifiable(notIs),
    has: Set.unmodifiable(has),
    notHas: Set.unmodifiable(notHas),
    made: made,
    changed: changed,
    parts: List.unmodifiable(parts),
  );
}

/// The operators a search field offers while it is empty, each as it is typed and what it finds
/// (lib/home/search_hints.dart).
const List<(String, String)> searchHints = [
  ('tag:', 'a tag'),
  ('in:', 'a workspace or notebook'),
  ('is:pinned', 'pinned'),
  ('is:todo', 'open to-dos'),
  ('is:done', 'all ticked'),
  ('is:ticket', 'tickets'),
  ('is:archived', 'the archive'),
  ('has:image', 'pictures'),
  ('has:link', 'links'),
  ('has:recording', 'recordings'),
  ('after:', 'made since a date'),
  ('before:', 'made before a date'),
  ('updated:<7d', 'changed this week'),
  ('"', 'an exact phrase'),
  ('-', 'leave a word out'),
];
