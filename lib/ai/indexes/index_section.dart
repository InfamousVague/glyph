/// The index's own section of a folder's page, and the settings in the page's front matter (docs/AI_INDEXES.md §1,
/// §2). Matt, 2026-11-02: "Self-maintaining indexes: for any folder or org, the AI keeps an index note (what's here,
/// the key decisions, who owns what) and updates it as notes change. New teammates read one page instead of fifty."
///
/// Pure: nothing here reads a note or asks an AI. The section is the words between `<!-- ghost:index … -->` and
/// `<!-- /ghost:index -->`, and only those are ever rewritten ([withSection]); everything the person wrote on the page
/// before or after them is left byte for byte. It is drawn from an [IndexContent] ([renderSection]) and read back into
/// one ([parseSection]), so a refresh can keep what it did not re-read.
library;

import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/properties.dart' show withFrontMatterValue;
import '../../core/title_key.dart' show titleKey;

/// The markers round the section.
const String indexOpenMarker = '<!-- ghost:index';
const String indexCloseMarker = '<!-- /ghost:index -->';

/// The section's headings, as written and as read back.
const String overviewHeading = "## What's here";
const String decisionsHeading = '## Key decisions';
const String ownersHeading = '## Who owns what';
const String recentHeading = '## Recently changed';

/// Where the section is in a page, and what its opening marker says.
class IndexSpan {
  const IndexSpan({required this.start, required this.end, required this.inner, this.updated, this.by});

  /// The offset of the opening marker, and the offset just past the closing one.
  final int start, end;

  /// The words between the two markers' lines.
  final String inner;

  /// When it was last brought up to date (the marker's `updated=`), and who wrote it (`by=`).
  final DateTime? updated;
  final String? by;
}

/// What [readSection] found: the section, none ([IndexSpan] null, [broken] false), or an opening marker with no close
/// ([broken]), which nothing may write over.
class IndexFound {
  const IndexFound(this.span, {this.broken = false});

  final IndexSpan? span;
  final bool broken;
}

final RegExp _openLine = RegExp(r'<!--\s*ghost:index\b([^\n]*?)-->');
final RegExp _closeLine = RegExp(r'<!--\s*/ghost:index\s*-->');

/// The section of [body], if it has one (see [IndexFound]).
IndexFound readSection(String body) {
  final open = _openLine.firstMatch(body);
  if (open == null) return const IndexFound(null);
  final close = _closeLine.firstMatch(body.substring(open.end));
  if (close == null) return const IndexFound(null, broken: true);
  final closeAt = open.end + close.start, end = open.end + close.end;
  final attrs = open.group(1) ?? '';
  String? attr(String key) => RegExp('\\b$key=(\\S+)').firstMatch(attrs)?.group(1);
  var inner = body.substring(open.end, closeAt);
  if (inner.startsWith('\n')) inner = inner.substring(1);
  if (inner.endsWith('\n')) inner = inner.substring(0, inner.length - 1);
  return IndexFound(IndexSpan(start: open.start, end: end, inner: inner, updated: DateTime.tryParse(attr('updated') ?? '')?.toUtc(), by: attr('by')?.replaceAll('_', ' ')));
}

/// [body] with its section made [section] (the markers included, [renderSection]'s): what was between the markers
/// replaced, or, with none, added at the end after a blank line. Null where the page's section is [IndexFound.broken].
String? withSection(String body, String section) {
  final found = readSection(body);
  if (found.broken) return null;
  final span = found.span;
  if (span != null) return body.replaceRange(span.start, span.end, section);
  final trimmed = body.replaceFirst(RegExp(r'\s+$'), '');
  return '$trimmed${trimmed.isEmpty ? '' : '\n\n'}$section\n';
}

/// [body] with its section taken out, the person's words round it kept.
String withoutSection(String body) {
  final span = readSection(body).span;
  if (span == null) return body;
  final before = body.substring(0, span.start).replaceFirst(RegExp(r'\s+$'), '');
  final after = body.substring(span.end).replaceFirst(RegExp(r'^\s+'), '');
  return [before, if (after.isNotEmpty) after].join('\n\n') + (before.isEmpty && after.isEmpty ? '' : '\n');
}

// ---- what the section says -----------------------------------------------------------------------------------------

/// One note's line under its theme: `- [[Title]] — what it is`.
class IndexEntry {
  const IndexEntry({required this.title, required this.theme, required this.about});

  final String title, theme, about;

  String get key => titleKey(title);
}

/// One key decision: `- 2026-10-28 · Move sync to the new server — [[Sync rewrite]]`.
class IndexDecision {
  const IndexDecision({required this.date, required this.what, required this.title});

  /// `YYYY-MM-DD`.
  final String date;
  final String what, title;
}

/// Everything the section says, the AI's parts ([overview], [entries], [decisions]) and the app's own ([owners],
/// [recent]).
class IndexContent {
  const IndexContent({this.overview = '', this.entries = const [], this.decisions = const [], this.owners = const {}, this.recent = const []});

  final String overview;
  final List<IndexEntry> entries;
  final List<IndexDecision> decisions;

  /// Each person to the titles of the notes they own, in the order met.
  final Map<String, List<String>> owners;

  /// The most recently changed notes: their titles and days (`YYYY-MM-DD`).
  final List<(String, String)> recent;

  /// The themes in the order their first entry comes.
  List<String> get themes => {for (final e in entries) e.theme}.toList();
}

/// A link to [title], as a page's other links are written.
String noteLink(String title) => '[[$title]]';

/// The AI's words made safe to put on one line beside a link: no line breaks, no `[[`/`]]` (a link only the app
/// writes), no marker look-alikes.
String plainLine(String words, {int most = 200}) {
  var said = words.replaceAll('[[', '').replaceAll(']]', '').replaceAll('<!--', '').replaceAll('-->', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (said.length > most) said = '${said.substring(0, most - 1).trimRight()}…';
  return said;
}

/// The section, markers and all, for [content] as of [updated], written by [by] ("Claude", "On this device").
String renderSection(IndexContent content, {required DateTime updated, required String by}) {
  final out = StringBuffer()
    ..writeln('$indexOpenMarker updated=${updated.toUtc().toIso8601String().split('.').first}Z by=${by.replaceAll(RegExp(r'\s+'), '_')} -->')
    ..writeln(overviewHeading)
    ..writeln();
  if (content.overview.trim().isNotEmpty) {
    out
      ..writeln(content.overview.trim())
      ..writeln();
  }
  if (content.entries.isEmpty) {
    out
      ..writeln('Nothing here yet.')
      ..writeln();
  }
  for (final theme in content.themes) {
    out.writeln('### $theme');
    for (final entry in content.entries.where((e) => e.theme == theme)) {
      out.writeln('- ${noteLink(entry.title)}${entry.about.isEmpty ? '' : ' — ${entry.about}'}');
    }
    out.writeln();
  }
  if (content.decisions.isNotEmpty) {
    out.writeln(decisionsHeading);
    for (final d in content.decisions) {
      out.writeln('- ${d.date} · ${d.what} — ${noteLink(d.title)}');
    }
    out.writeln();
  }
  if (content.owners.isNotEmpty) {
    out.writeln(ownersHeading);
    for (final MapEntry(key: who, value: titles) in content.owners.entries) {
      out.writeln('- **$who** — ${titles.map(noteLink).join(', ')}');
    }
    out.writeln();
  }
  if (content.recent.isNotEmpty) {
    out.writeln(recentHeading);
    for (final (title, day) in content.recent) {
      out.writeln('- ${noteLink(title)} · $day');
    }
    out.writeln();
  }
  out.write(indexCloseMarker);
  return out.toString();
}

final RegExp _entryLine = RegExp(r'^-\s+\[\[([^\]]+)\]\](?:\s+—\s+(.*))?$');
final RegExp _decisionLine = RegExp(r'^-\s+(\d{4}-\d{2}-\d{2})\s+·\s+(.*?)\s+—\s+\[\[([^\]]+)\]\]$');

/// The AI's parts of a section's [inner] words, read back from what [renderSection] wrote: the overview, each entry
/// under its theme, each decision. Owners and Recently changed are the app's and are worked out afresh, not read.
IndexContent parseSection(String inner) {
  var overview = <String>[];
  final entries = <IndexEntry>[];
  final decisions = <IndexDecision>[];
  var part = '';
  String? theme;
  for (final raw in inner.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('## ')) {
      part = line;
      theme = null;
      continue;
    }
    if (line.startsWith('### ')) {
      theme = line.substring(4).trim();
      continue;
    }
    if (part == overviewHeading) {
      if (theme != null) {
        final m = _entryLine.firstMatch(line);
        if (m != null) entries.add(IndexEntry(title: m.group(1)!.trim(), theme: theme, about: (m.group(2) ?? '').trim()));
      } else if (line.isNotEmpty && line != 'Nothing here yet.') {
        overview.add(line);
      }
    } else if (part == decisionsHeading) {
      final m = _decisionLine.firstMatch(line);
      if (m != null) decisions.add(IndexDecision(date: m.group(1)!, what: m.group(2)!.trim(), title: m.group(3)!.trim()));
    }
  }
  return IndexContent(overview: overview.join(' ').trim(), entries: entries, decisions: decisions);
}

/// Every title the section links, for the notes gone since it was written.
Set<String> linkedKeys(String inner) => {for (final m in RegExp(r'\[\[([^\]]+)\]\]').allMatches(inner)) titleKey(m.group(1)!)};

// ---- the settings --------------------------------------------------------------------------------------------------

/// How often, at most, a dirty index is refreshed (docs/AI_INDEXES.md §3).
enum IndexEvery {
  quarter('15m', '15 min', Duration(minutes: 15)),
  hourly('hourly', 'Hourly', Duration(hours: 1)),
  nightly('nightly', 'Nightly', Duration(hours: 20));

  const IndexEvery(this.written, this.words, this.gap);

  /// As the front matter says it, and as a person reads it.
  final String written, words;

  /// The least time between two refreshes.
  final Duration gap;

  static IndexEvery read(String? said) => values.where((e) => e.written == said?.trim().toLowerCase()).firstOrNull ?? hourly;
}

/// The page's front matter's say on the index (docs/AI_INDEXES.md §2).
class IndexSettings {
  const IndexSettings({this.on = false, this.every = IndexEvery.hourly, this.by, this.byName});

  final bool on;
  final IndexEvery every;

  /// The one device that writes it, and what it is called.
  final String? by, byName;

  factory IndexSettings.of(String? body) {
    if (body == null) return const IndexSettings();
    final on = frontMatterValue(body, 'index')?.trim().toLowerCase();
    return IndexSettings(
      on: on == 'on' || on == 'true' || on == 'yes',
      every: IndexEvery.read(frontMatterValue(body, 'index-every')),
      by: _orNull(frontMatterValue(body, 'index-by')),
      byName: _orNull(frontMatterValue(body, 'index-by-name')),
    );
  }

  /// [body] with these settings written over its front matter; off takes every key off.
  String writeInto(String body) {
    var next = withFrontMatterValue(body, 'index', on ? 'on' : null);
    next = withFrontMatterValue(next, 'index-every', on ? every.written : null);
    next = withFrontMatterValue(next, 'index-by', on ? by : null);
    return withFrontMatterValue(next, 'index-by-name', on ? byName : null);
  }

  IndexSettings copyWith({bool? on, IndexEvery? every, String? by, String? byName}) => IndexSettings(on: on ?? this.on, every: every ?? this.every, by: by ?? this.by, byName: byName ?? this.byName);
}

String? _orNull(String? said) => said == null || said.trim().isEmpty ? null : said.trim();
