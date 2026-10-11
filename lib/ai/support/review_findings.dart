/// The reviewing model's answer, made safe to act on. A port of `src/app/review/findings.ts`.
///
/// The model is asked for a JSON array (review_prompt.dart), and a small model sometimes wraps it in a fence, adds a
/// sentence, or leaves a trailing comma, so the array is dug out leniently. Then every finding has to earn its place:
/// a known check, a note that exists, and a `find` that is really in that note (exactly, or once whitespace and case
/// are forgiven). A finding that fails is dropped, so the person is never asked to accept a change to text that isn't
/// there. What is left is applied only when the person commits ([applyFindings]).
///
/// What differs: a finding's change is a sealed [FindingChange] ([ReplaceChange] or [AddChange]) whose `kind` is the
/// web's word. [NoteText] is a `Candidate` (lib/capture/route.dart), which is what `matchNote` takes here. A place
/// found is a `({index, text})` record. `appendToList` and `leaveNote` come from list_append.dart beside this file
/// until the capture stage has its own. Kept under lib/ai/support until lib/review has a findings.dart.
library;

import 'dart:convert';

import '../../capture/route.dart';
import '../../core/item_syntax.dart';
import '../../core/text.dart';
import 'list_append.dart';

/// What a finding is about (`Check`).
enum Check { words, structure, commands, names }

/// A note as the review reads it (`NoteText`).
class NoteText extends Candidate {
  const NoteText({required super.id, required super.title, required this.body});

  final String body;

  NoteText copyWith({String? id, String? title, String? body}) => NoteText(id: id ?? this.id, title: title ?? this.title, body: body ?? this.body);

  @override
  bool operator ==(Object other) => other is NoteText && other.id == id && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(id, title, body);
}

/// What a finding would do to its note (`Finding['change']`).
sealed class FindingChange {
  const FindingChange();

  /// `replace` or `add`.
  String get kind;
}

/// Replace `find` (exactly as it is in the note) with `replace`.
final class ReplaceChange extends FindingChange {
  const ReplaceChange({required this.find, required this.replace});

  final String find;
  final String replace;

  @override
  String get kind => 'replace';

  @override
  bool operator ==(Object other) => other is ReplaceChange && other.find == find && other.replace == replace;

  @override
  int get hashCode => Object.hash(find, replace);
}

/// Add `line` as a line.
final class AddChange extends FindingChange {
  const AddChange({required this.line});

  final String line;

  @override
  String get kind => 'add';

  @override
  bool operator ==(Object other) => other is AddChange && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

/// One thing the review found (`Finding`).
class Finding {
  const Finding({required this.id, required this.check, required this.what, required this.why, required this.noteId, required this.noteTitle, required this.change});

  final String id;
  final Check check;
  final String what;
  final String why;
  final String noteId;
  final String noteTitle;
  final FindingChange change;

  @override
  bool operator ==(Object other) =>
      other is Finding &&
      other.id == id &&
      other.check == check &&
      other.what == what &&
      other.why == why &&
      other.noteId == noteId &&
      other.noteTitle == noteTitle &&
      other.change == change;

  @override
  int get hashCode => Object.hash(id, check, what, why, noteId, noteTitle, change);
}

final RegExp _fenceMark = RegExp(r'```(?:json)?', caseSensitive: false);
final RegExp _trailingComma = RegExp(r',\s*([}\]])');
final RegExp _space = RegExp(r'\s+');

/// The JSON array in a model's answer, or an empty one when there is none to read.
List<Object?> readArray(String answer) {
  final text = jsTrim(answer.replaceAll(_fenceMark, ''));
  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start < 0 || end <= start) return const <Object?>[];
  final raw = text.substring(start, end + 1).replaceAllMapped(_trailingComma, (m) => m.group(1)!);
  try {
    final Object? parsed = jsonDecode(raw);
    return parsed is List ? parsed : const <Object?>[];
  } catch (_) {
    return const <Object?>[];
  }
}

/// Where [find] is in [body]: exactly, or with whitespace and case forgiven. Answers the text as it is in the body.
String? locate(String body, String find) => locateLast(body, find)?.text;

/// The LAST place [find] is in [body], and its text there. A recording's words are the newest in their note, at its
/// end, so when the same words are in a note twice the one just said is the later one.
({int index, String text})? locateLast(String body, String find) {
  final wanted = jsTrim(find);
  if (wanted.isEmpty) return null;
  final exact = body.lastIndexOf(find);
  if (exact >= 0) return (index: exact, text: find);
  final pattern = wanted.split(_space).map(escapeRegExp).join(r'\s+');
  ({int index, String text})? last;
  for (final found in RegExp(pattern, caseSensitive: false).allMatches(body)) {
    last = (index: found.start, text: found.group(0)!);
  }
  return last;
}

String _text(Object? value) => value is String ? jsTrim(value) : '';

/// The findings worth showing: validated against the notes, one per change. [self] is the note reviewed; [others]
/// are notes a finding may name.
List<Finding> readFindings(String answer, NoteText self, List<NoteText> others) {
  final notes = <NoteText>[self, ...others.where((n) => n.id != self.id)];
  final seen = <String>{};
  final out = <Finding>[];
  final items = readArray(answer);
  for (var index = 0; index < items.length; index += 1) {
    final raw = items[index];
    if (raw is! Map) continue;
    final said = _text(raw['check']).toLowerCase();
    final check = Check.values.where((c) => c.name == said).firstOrNull;
    if (check == null) continue;
    final named = _text(raw['note']);
    final note = named.isEmpty || matchNote<NoteText>(named, <NoteText>[self], threshold: 0.6, margin: 0) != null
        ? self
        : matchNote<NoteText>(named, notes, threshold: 0.72, margin: 0.05)?.note;
    if (note == null) continue;
    final what = _text(raw['what']).isEmpty ? 'A change' : _text(raw['what']);
    final why = _text(raw['why']);
    final add = _text(raw['add']);
    final FindingChange change;
    if (add.isNotEmpty && _text(raw['find']).isEmpty) {
      if (note.body.contains(add)) continue;
      change = AddChange(line: add);
    } else {
      final find = raw['find'];
      final located = locate(note.body, find is String ? find : '');
      final replace = raw['replace'];
      if (located == null || replace is! String || jsTrim(replace) == jsTrim(located)) continue;
      change = ReplaceChange(find: located, replace: replace);
    }
    final key = '${note.id}|${switch (change) {
      AddChange() => change.line,
      ReplaceChange() => '${change.find}→${change.replace}',
    }}';
    if (!seen.add(key)) continue;
    out.add(Finding(id: 'f$index', check: check, what: what, why: why, noteId: note.id, noteTitle: note.title, change: change));
  }
  return out;
}

/// A line added to a note: a list item joins its list, anything else goes where it fits. A to-do's box is the list's
/// to write, so it goes; a choice's `( )` is part of what is added, so it stays with the words.
String addLine(String body, String line) {
  final item = listLead(line);
  if (item != null) {
    final words = line.substring(item.picked != null ? item.boxAt : item.wordsAt);
    return appendToList(body, <String>[words], asTasks: item.done != null).body;
  }
  return leaveNote(body, line).body;
}

/// The notes with the accepted findings applied, in order. A replace whose text is no longer there (an earlier
/// finding changed it) is skipped, not forced. Answers only the notes that changed, by id.
Map<String, String> applyFindings(List<NoteText> notes, List<Finding> findings) {
  final bodies = <String, String>{for (final n in notes) n.id: n.body};
  final changed = <String, String>{};
  for (final finding in findings) {
    final body = bodies[finding.noteId];
    if (body == null) continue;
    final String next;
    switch (finding.change) {
      case AddChange(:final line):
        next = addLine(body, line);
      case ReplaceChange(:final find, :final replace):
        final at = locateLast(body, find);
        if (at == null) continue;
        next = body.substring(0, at.index) + replace + body.substring(at.index + at.text.length);
    }
    if (next != body) {
      bodies[finding.noteId] = next;
      changed[finding.noteId] = next;
    }
  }
  return changed;
}
