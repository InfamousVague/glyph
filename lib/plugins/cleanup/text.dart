/// What Cleanup does to a note's words, each a pure function so each is a test (docs/CLEANUP.md; Matt, 2026-11-02:
/// "spawn a task making a 'cleanup' plugin that allows us to use whatever AI we choose that's connected to clean up
/// and sort the notes in a given folder"): a new title written where the title is, tags and links added, a duplicate's
/// lines kept in the note it is merged into, and the check that a tidied note kept every word.
///
/// Nothing here reads the AI's answer or touches the library: plan.dart reads the answer, apply.dart writes.
library;

import '../../core/front_matter.dart' show frontMatterEnd, frontMatterValue;
import '../../core/note_text.dart' show noteTitle;
import '../../core/properties.dart' show propertyList, withProperty;

// ---- titles -------------------------------------------------------------------------------------------------------

final RegExp _heading = RegExp(r'^(#{1,6})\s+\S');
final RegExp _imageOnly = RegExp(r'^\s*!\[[^\]]*\]\([^)]*\)\s*$');

/// [body] titled [title], with none of its words lost: a front matter `title:` set where the note is titled by one; the
/// first heading's words replaced where the note opens with a heading (at its level); otherwise a `# title` put above
/// the first line, which was the title only because it came first, so it stays as the note's first words.
String titledBody(String body, String title) {
  final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return body;
  if (body.trim().isEmpty) return '# $clean';
  final named = frontMatterValue(body, 'title');
  if (named != null && named.trim().isNotEmpty) return withProperty(body, 'title', clean);
  final lines = body.split('\n');
  final start = frontMatterEnd(lines);
  for (var at = start; at < lines.length; at += 1) {
    final line = lines[at];
    if (line.trim().isEmpty || _imageOnly.hasMatch(line)) continue;
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      lines[at] = '${heading.group(1)} $clean';
    } else {
      lines.insertAll(at, ['# $clean', '']);
    }
    return lines.join('\n');
  }
  // Nothing but front matter, blanks or pictures: the title goes after the front matter.
  lines.insertAll(start, ['# $clean', '']);
  return lines.join('\n');
}

/// What a date (and a time) is written with: month and day names, digits, the signs between them, and the small words
/// round them ("the 3rd of May at 14:05").
final RegExp _dateWords = RegExp(
  r'\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?|\b(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\.?|\b(?:am|pm|at|of|the|th|st|nd|rd|on)\b|[\d:./,\-\s]',
  caseSensitive: false,
);

/// The words a note is given before anyone names it: a meeting's or a recording's date title is still weak.
final RegExp _madeLead = RegExp(r'^(?:meeting|voice note|recording|note|journal)\b[,:]?\s*', caseSensitive: false);

/// Whether [title] says nothing of what the note is: none, "Untitled", "New note", or a date (and a time) alone, or a
/// meeting's or a recording's date title ("Meeting, 26 Sep 14:05").
bool weakTitle(String title) {
  final t = title.trim().toLowerCase();
  if (t.isEmpty || t == 'untitled' || t == 'new note' || t == 'note' || t.startsWith('untitled ')) return true;
  final rest = t.replaceFirst(_madeLead, '');
  return RegExp(r'\d').hasMatch(rest) && rest.replaceAll(_dateWords, '').isEmpty;
}

// ---- the formatting-only check ----------------------------------------------------------------------------------

final RegExp _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*", unicode: true);

/// The words of [text], in lower case, in order: what a tidy must keep.
List<String> wordsOf(String text) => [for (final m in _word.allMatches(text)) m.group(0)!.toLowerCase()];

/// Why [after] is not [before] with only its formatting changed, or null where it is: every word of [before] is still
/// there in the same order, nothing is added, and only the words of a heading may go (an empty section's, which Tidy
/// may take away). A tidy that fails this is dropped, never applied (docs/CLEANUP.md, "Validation").
String? formattingOnlyWhy(String before, String after) {
  if (after.trim().isEmpty) return 'it came back empty';
  final kept = <({String word, bool heading})>[
    for (final line in before.split('\n'))
      for (final word in wordsOf(line)) (word: word, heading: _heading.hasMatch(line.trimLeft())),
  ];
  final now = wordsOf(after);
  var at = 0;
  var dropped = 0;
  for (final word in now) {
    while (at < kept.length && kept[at].word != word) {
      if (!kept[at].heading) return 'it changed the words (“${kept[at].word}” went)';
      dropped += 1;
      at += 1;
    }
    if (at >= kept.length) return 'it added words (“$word”)';
    at += 1;
  }
  for (; at < kept.length; at += 1) {
    if (!kept[at].heading) return 'it changed the words (“${kept[at].word}” went)';
    dropped += 1;
  }
  if (dropped > 12) return 'it took away too many headings';
  return null;
}

/// Why a rewrite (Rewrite for clarity on) is too far from [before] to be offered: empty, or under half or over twice
/// its length.
String? rewriteWhy(String before, String after) {
  if (after.trim().isEmpty) return 'it came back empty';
  final a = before.trim().length, b = after.trim().length;
  if (a > 40 && (b < a / 2 || b > a * 2)) return 'it was ${b < a ? 'under half' : 'over twice'} the note’s length';
  return null;
}

/// The note an AI answered with, taken out of a fence it may have wrapped it in, or out of `{"body": …}`.
String unwrapBody(String answer) {
  var text = answer.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final fence = RegExp(r'^```[a-zA-Z]*\n([\s\S]*?)\n```$').firstMatch(text);
  if (fence != null) text = fence.group(1)!;
  return text;
}

// ---- tags and links ----------------------------------------------------------------------------------------------

/// [body] with [tags] in its front matter's `tags:` list, after the ones it has, each once (in any case).
String withTags(String body, List<String> tags) {
  final had = propertyList(frontMatterValue(body, 'tags'));
  final seen = {for (final tag in had) tag.toLowerCase()};
  final more = [for (final tag in tags) if (seen.add(tag.toLowerCase())) tag];
  if (more.isEmpty) return body;
  return withProperty(body, 'tags', [...had, ...more]);
}

/// [body] with a last line linking [titles]: `Related: [[A]] · [[B]]`, leaving out any it links already.
String withRelated(String body, List<String> titles) {
  final lower = body.toLowerCase();
  final more = [for (final title in titles) if (!lower.contains('[[${title.toLowerCase()}]]') && !lower.contains('[[${title.toLowerCase()}|')) title];
  if (more.isEmpty) return body;
  final line = 'Related: ${more.map((t) => '[[$t]]').join(' · ')}';
  final trimmed = body.replaceFirst(RegExp(r'\s+$'), '');
  return trimmed.isEmpty ? line : '$trimmed\n\n$line\n';
}

// ---- duplicates -----------------------------------------------------------------------------------------------------

final RegExp _copyMark = RegExp(r'\s*(?:\((?:shared|copy|\d+)\)|-\s*copy|copy(?:\s+\d+)?)\s*$', caseSensitive: false);

/// A title as two copies of one note share it: lower case, "(shared)", "(copy)", "copy", "(2)" taken off its end.
String sameTitleKey(String title) {
  var t = title.trim();
  for (var i = 0; i < 3; i += 1) {
    final next = t.replaceFirst(_copyMark, '').trim();
    if (next == t) break;
    t = next;
  }
  return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// A body's words after its front matter and its title heading: what two copies of one note share whatever each was
/// called.
String duplicateContent(String body) {
  final lines = body.split('\n');
  final rest = lines.skip(frontMatterEnd(lines)).toList();
  final first = rest.indexWhere((line) => line.trim().isNotEmpty);
  if (first >= 0 && _heading.hasMatch(rest[first].trimLeft())) rest.removeAt(first);
  return rest.join('\n');
}

/// The words of a body in threes, for [likeness].
Set<String> _shingles(String body) {
  final words = wordsOf(body);
  if (words.length < 3) return {words.join(' ')};
  return {for (var i = 0; i + 2 < words.length; i += 1) '${words[i]} ${words[i + 1]} ${words[i + 2]}'};
}

/// How alike two bodies are, 0 to 1: the share of their runs of three words they have in common (Jaccard).
double likeness(String a, String b) {
  final x = _shingles(a), y = _shingles(b);
  if (x.isEmpty && y.isEmpty) return 1;
  final both = x.where(y.contains).length;
  final either = x.length + y.length - both;
  return either == 0 ? 0 : both / either;
}

/// One note as the duplicate finder reads it.
typedef DupNote = ({String id, String title, String body, int updatedAt});

/// Groups of notes that are one note more than once, found without the AI across the whole folder: the same words
/// after their titles; or the same title once its copy marks are off and words at least [alike] alike, or [copyAlike]
/// where one of the two is marked a copy ("Standup (shared)", often added to after it was shared). Each group's first
/// is the one to keep: a title with no copy mark first, then the longest, then the most recently changed. A note is in
/// one group at most.
List<List<String>> duplicateGroups(List<DupNote> notes, {double alike = 0.8, double copyAlike = 0.55}) {
  final content = {for (final note in notes) note.id: duplicateContent(note.body)};
  final byTitle = <String, List<DupNote>>{};
  final byWords = <String, List<DupNote>>{};
  for (final note in notes) {
    final words = wordsOf(content[note.id]!).join(' ');
    if (words.length < 12) continue; // an empty note is no one's copy
    final key = sameTitleKey(note.title);
    if (key.isNotEmpty && !weakTitle(key)) (byTitle[key] ??= []).add(note);
    (byWords[words] ??= []).add(note);
  }
  bool copy(DupNote n) => _copyMark.hasMatch(n.title);
  final grouped = <String>{};
  final groups = <List<String>>[];
  void take(List<DupNote> found, {required bool sameWords}) {
    final fresh = [for (final n in found) if (!grouped.contains(n.id)) n];
    if (fresh.length < 2) return;
    fresh.sort((a, b) {
      final byCopy = (copy(a) ? 1 : 0) - (copy(b) ? 1 : 0);
      if (byCopy != 0) return byCopy;
      final byLength = b.body.length.compareTo(a.body.length);
      return byLength != 0 ? byLength : b.updatedAt.compareTo(a.updatedAt);
    });
    for (var i = 0; i < fresh.length; i += 1) {
      final keep = fresh[i];
      if (grouped.contains(keep.id)) continue;
      final same = [
        keep,
        for (final n in fresh.skip(i + 1))
          if (!grouped.contains(n.id) && (sameWords || likeness(content[keep.id]!, content[n.id]!) >= (copy(keep) || copy(n) ? copyAlike : alike))) n,
      ];
      if (same.length < 2) continue;
      grouped.addAll(same.map((n) => n.id));
      groups.add([for (final n in same) n.id]);
    }
  }

  for (final found in byWords.values) {
    take(found, sameWords: true);
  }
  for (final found in byTitle.values) {
    take(found, sameWords: false);
  }
  return groups;
}

/// The kept note's body with what the others say that it does not: each other's lines it lacks (compared trimmed,
/// blank lines and the other's title aside), under `## From “<title>”`, in the others' order. [added] counts the lines
/// brought in; none, and the body is as it was.
({String body, int added}) mergedBody(String keep, List<({String title, String body})> others) {
  final have = {for (final line in keep.split('\n')) if (line.trim().isNotEmpty) line.trim()};
  final parts = <String>[];
  var added = 0;
  for (final other in others) {
    final title = other.title.trim().isEmpty ? noteTitle(other.body) : other.title.trim();
    final lines = other.body.split('\n');
    final start = frontMatterEnd(lines);
    var titleSkipped = false;
    final missing = <String>[];
    for (final line in lines.skip(start)) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (!titleSkipped) {
        titleSkipped = true;
        // The other's own title line is the copy's name, not its words.
        if (t.replaceFirst(RegExp(r'^#+\s*'), '') == title || t.replaceFirst(RegExp(r'^#+\s*'), '') == noteTitle(other.body)) continue;
      }
      if (have.add(t)) missing.add(line);
    }
    if (missing.isEmpty) continue;
    added += missing.length;
    parts.add('## From “${title.isEmpty ? 'Untitled' : title}”\n\n${missing.join('\n')}');
  }
  if (parts.isEmpty) return (body: keep, added: 0);
  final trimmed = keep.replaceFirst(RegExp(r'\s+$'), '');
  return (body: '$trimmed\n\n${parts.join('\n\n')}\n', added: added);
}
