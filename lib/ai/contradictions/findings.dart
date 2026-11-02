/// What the contradiction finder found, and where it is kept (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction
/// finder: spots when a newer note disagrees with an older one … and flags the stale one inline, 'superseded by …', so
/// old notes stop misleading you or the AI").
///
/// A [Finding] is one older line a newer note disagrees with. They are kept per scope ([ContradictionScope]) in a file
/// beside the notes, markdown-first (docs/MARKDOWN_FIRST.md), so a git restore brings back what was found and what the
/// person said was not a conflict: `Library/.glyph/contradictions.json` for personal notes, and
/// `Library/orgs/<Org>/.glyph/contradictions.json` for an organization's, inside its own folder, so a team's quotes never
/// sit in the personal file nor in a personal backup that leaves the organization out. Where the library has no folder
/// Dart can reach, the same JSON is held in the device's storage ([StoredFindingsFile]).
///
/// Also here, because it is the finding's own markdown: what Mark superseded writes under the stale line
/// ([supersededLine], [withSuperseded]): a blockquote that reads the same in any Markdown app.
library;

import 'dart:convert';
import 'dart:io';

import '../../core/stored.dart';

/// A finding's state.
enum FindingState {
  /// Shown: the mark on the older line, the page's list, the home line.
  open,

  /// "Not a conflict": never shown again, and never found again.
  dismissed,

  /// "Mark superseded" wrote its line under the older one.
  superseded,
}

/// The words compared for "the same line": spaces made one, curly quotes made straight, dashes made one, lower case.
String sameWords(String text) => text
    .replaceAll(RegExp('[‘’‛′]'), "'")
    .replaceAll(RegExp('[“”‟″]'), '"')
    .replaceAll(RegExp('[–—−]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// One disagreement: the older note's line, and the newer note that says otherwise.
class Finding {
  const Finding({
    required this.olderId,
    required this.olderTitle,
    required this.olderQuote,
    required this.newerId,
    required this.newerTitle,
    required this.newerQuote,
    required this.what,
    required this.confidence,
    required this.found,
    this.state = FindingState.open,
  });

  final String olderId, olderTitle, olderQuote;
  final String newerId, newerTitle, newerQuote;

  /// What disagrees, in a sentence the AI wrote: "The release day moved from Thursday to Monday."
  final String what;

  /// From 0 to 1, as the AI said it.
  final double confidence;
  final DateTime found;
  final FindingState state;

  /// The same disagreement whenever it is found: the older note, its line's words, the newer note. What a dismissal is
  /// remembered by.
  String get key => '$olderId|${sameWords(olderQuote)}|$newerId';

  Finding withState(FindingState next) => Finding(
        olderId: olderId,
        olderTitle: olderTitle,
        olderQuote: olderQuote,
        newerId: newerId,
        newerTitle: newerTitle,
        newerQuote: newerQuote,
        what: what,
        confidence: confidence,
        found: found,
        state: next,
      );

  Map<String, Object?> toJson() => {
        'older': olderId,
        'olderTitle': olderTitle,
        'olderQuote': olderQuote,
        'newer': newerId,
        'newerTitle': newerTitle,
        'newerQuote': newerQuote,
        'what': what,
        'confidence': confidence,
        'found': found.toUtc().toIso8601String(),
        'state': state.name,
      };

  /// Reads [toJson]'s; null for anything that is not one.
  static Finding? fromJson(Object? json) {
    if (json is! Map) return null;
    String? s(String key) => json[key] is String ? json[key] as String : null;
    final older = s('older'), newer = s('newer'), olderQuote = s('olderQuote'), newerQuote = s('newerQuote');
    final confidence = json['confidence'];
    if (older == null || newer == null || olderQuote == null || newerQuote == null || confidence is! num) return null;
    return Finding(
      olderId: older,
      olderTitle: s('olderTitle') ?? '',
      olderQuote: olderQuote,
      newerId: newer,
      newerTitle: s('newerTitle') ?? '',
      newerQuote: newerQuote,
      what: s('what') ?? '',
      confidence: confidence.toDouble(),
      found: DateTime.tryParse(s('found') ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      state: FindingState.values.where((v) => v.name == s('state')).firstOrNull ?? FindingState.open,
    );
  }
}

/// What one scope's file holds: its findings, and the pairs already asked about at the revisions they were asked at.
class FindingsBook {
  const FindingsBook({this.findings = const [], this.checked = const {}});

  final List<Finding> findings;

  /// `"<older id>|<newer id>"` to `"<older revision>:<newer revision>"`.
  final Map<String, String> checked;

  static const int version = 1;

  List<Finding> get open => [for (final f in findings) if (f.state == FindingState.open) f];

  /// Whether this disagreement was dismissed, or already marked superseded: it is never shown again.
  bool settled(Finding finding) => findings.any((f) => f.key == finding.key && f.state != FindingState.open);

  /// [found] added: a finding already here by its key is left as it is (an open one is kept, with its first date; a
  /// dismissed one stays dismissed), the rest go in.
  FindingsBook adding(Iterable<Finding> found, {Map<String, String> checked = const {}}) {
    final byKey = {for (final f in findings) f.key: f};
    for (final f in found) {
      byKey.putIfAbsent(f.key, () => f);
    }
    return FindingsBook(findings: byKey.values.toList(), checked: {...this.checked, ...checked});
  }

  /// The finding by [key] put in [state].
  FindingsBook setting(String key, FindingState state) => FindingsBook(findings: [for (final f in findings) f.key == key ? f.withState(state) : f], checked: checked);

  /// Without the findings and checks of notes that are gone.
  FindingsBook keepingNotes(Set<String> ids) => FindingsBook(
        findings: [for (final f in findings) if (ids.contains(f.olderId) && ids.contains(f.newerId)) f],
        checked: {
          for (final MapEntry(:key, :value) in checked.entries)
            if (key.split('|').every(ids.contains)) key: value,
        },
      );

  Map<String, Object?> toJson() => {'version': version, 'findings': [for (final f in findings) f.toJson()], 'checked': checked};

  String encode() => '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Reads [encode]'s text; an empty book for anything else.
  static FindingsBook decode(String? text) {
    if (text == null || text.trim().isEmpty) return const FindingsBook();
    try {
      final json = jsonDecode(text);
      if (json is! Map) return const FindingsBook();
      final raw = json['findings'];
      final checked = json['checked'];
      return FindingsBook(
        findings: [if (raw is List) for (final f in raw) ?Finding.fromJson(f)],
        checked: {
          if (checked is Map)
            for (final MapEntry(:key, :value) in checked.entries)
              if (key is String && value is String) key: value,
        },
      );
    } catch (_) {
      return const FindingsBook();
    }
  }
}

/// Where a scope's findings are: personal notes, or one organization's.
class ContradictionScope {
  const ContradictionScope.personal({this.folder}) : org = null;
  const ContradictionScope.org(String this.org) : folder = null;

  /// The organization's folder name under `orgs/` (`HelloTrade`); null for personal notes.
  final String? org;

  /// With "Within each folder only": the top folder personal notes are compared within (`workspaces/Work`); null for
  /// all of them.
  final String? folder;

  bool get personal => org == null;

  /// The file it is kept in, under [root] (the library's folder).
  String fileIn(String root) => org == null ? '$root/.glyph/contradictions.json' : '$root/orgs/$org/.glyph/contradictions.json';

  /// The book a scope's findings are in: personal notes share one whatever their folder.
  String get bookId => org == null ? 'personal' : 'org:$org';

  String get id => org != null ? 'org:$org' : (folder == null ? 'personal' : 'personal:$folder');

  @override
  bool operator ==(Object other) => other is ContradictionScope && other.org == org && other.folder == folder;

  @override
  int get hashCode => Object.hash(org, folder);

  @override
  String toString() => id;
}

/// The scope a note is in by its path: an organization's for a note under `orgs/<Org>/`, personal otherwise ([byFolder]
/// gives a personal note its top folder: `workspaces/Work`, `Inbox`).
ContradictionScope scopeOfPath(String? path, {bool byFolder = false}) {
  final p = path ?? '';
  if (p.startsWith('orgs/')) {
    final cut = p.indexOf('/', 5);
    if (cut > 5) return ContradictionScope.org(p.substring(5, cut));
  }
  if (!byFolder) return const ContradictionScope.personal();
  final parts = p.split('/');
  if (parts.length < 2) return const ContradictionScope.personal(folder: '');
  final top = parts.first == 'workspaces' && parts.length > 2 ? '${parts[0]}/${parts[1]}' : parts.first;
  return ContradictionScope.personal(folder: top);
}

/// The bytes of one book: a file beside the notes, or the device's storage.
abstract interface class FindingsFile {
  Future<String?> read();
  Future<void> write(String text);
}

/// A real file, written whole: a temporary file renamed over the old one (lib/core/library_config.dart's way).
class DiskFindingsFile implements FindingsFile {
  const DiskFindingsFile(this.path);
  final String path;

  @override
  Future<String?> read() async {
    try {
      final file = File(path);
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final part = File('$path.part');
    await part.writeAsString(text, flush: true);
    await part.rename(path);
  }
}

/// The device's storage, for a library with no folder Dart can reach, and for a test.
class StoredFindingsFile implements FindingsFile {
  StoredFindingsFile(this.key, [Stored? store]) : _store = store;
  final String key;
  final Stored? _store;

  @override
  Future<String?> read() async => (_store ?? stored).readText(key);

  @override
  Future<void> write(String text) async => (_store ?? stored).writeText(key, text);
}

// ---- Mark superseded's markdown ------------------------------------------------------------------------------------

final RegExp _listStart = RegExp(r'^(\s*)(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?');
final RegExp _supersededLine = RegExp(r'^\s*>\s*Superseded by\b', caseSensitive: false);

/// Whether [line] is a line Mark superseded wrote.
bool isSupersededLine(String line) => _supersededLine.hasMatch(line);

/// The line Mark superseded writes for [finding] on [on] (an ISO day, the person's own), as it stands under [stale]:
/// `> Superseded by [[Standup]] (2026-11-02): “release moved to Monday”`, indented to a list item's text so it stays
/// inside the item, and to the line's own indent otherwise.
String supersededLine(Finding finding, String stale, DateTime on) {
  final list = _listStart.firstMatch(stale);
  final indent = list != null ? ' ' * list.group(0)!.length : RegExp(r'^\s*').stringMatch(stale)!;
  final day = '${on.year.toString().padLeft(4, '0')}-${on.month.toString().padLeft(2, '0')}-${on.day.toString().padLeft(2, '0')}';
  final title = finding.newerTitle.trim().isEmpty ? 'a newer note' : '[[${finding.newerTitle.trim()}]]';
  final quote = finding.newerQuote.trim().replaceAll(RegExp(r'\s+'), ' ');
  return '$indent> Superseded by $title ($day): “$quote”';
}

/// The 1-based line of [body] that holds [quote], the first not already followed by a superseded line; null where none
/// does. Words compared as [sameWords] has them.
int? lineOfQuote(String body, String quote) {
  final want = sameWords(quote);
  if (want.isEmpty) return null;
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i += 1) {
    if (!sameWords(lines[i]).contains(want)) continue;
    if (isSupersededLine(lines[i])) continue;
    if (i + 1 < lines.length && isSupersededLine(lines[i + 1])) continue;
    return i + 1;
  }
  return null;
}

/// [body] with [finding]'s superseded line under its stale line; the body as it was where the line is not found (or is
/// already marked).
String withSuperseded(String body, Finding finding, DateTime on) {
  final at = lineOfQuote(body, finding.olderQuote);
  if (at == null) return body;
  final lines = body.split('\n');
  lines.insert(at, supersededLine(finding, lines[at - 1], on));
  return lines.join('\n');
}
