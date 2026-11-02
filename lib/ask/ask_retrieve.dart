/// Finding what a question is asked of: the scope's notes cut into passages, each with its lines, and the best of them
/// chosen to be sent (docs/ASK_THE_ORG.md, "Retrieval"; Matt, 2026-11-02: "'Ask the org' with receipts: questions
/// answered only from your notes, every claim linked to the note and line it came from").
///
/// Everything here runs on the device: team notes are sealed and opened only here, so this is the only place they
/// can be read. Nothing is sent but what [retrieve] chooses.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterOffset;
import '../core/link_index.dart' show linksIn;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/search_hits.dart' show findNotes;
import '../core/title_key.dart' show titleKey;

/// One stretch of a note: its lines, counted from 1 as the editor counts them (front matter included).
@immutable
class AskPassage {
  const AskPassage({required this.note, required this.fromLine, required this.toLine, required this.lines, this.heading = ''});

  final Note note;
  final int fromLine;
  final int toLine;

  /// The note's lines [fromLine] to [toLine], as written.
  final List<String> lines;

  /// The heading the passage stands under, its marks off; empty above the first.
  final String heading;

  /// Its stable id: `<note id>#L<from>-<to>`.
  String get id => '${note.id}#L$fromLine-$toLine';

  String get title => NoteFacts.of(note).title;
  String get text => lines.join('\n');

  @override
  String toString() => 'AskPassage($id)';
}

/// How much is sent: a cloud model is sent more than the device's.
@immutable
class AskBudget {
  const AskBudget({required this.passages, required this.chars, this.perNote = 4});

  final int passages;
  final int chars;
  final int perNote;

  static const AskBudget cloud = AskBudget(passages: 12, chars: 7000);
  static const AskBudget device = AskBudget(passages: 6, chars: 2500, perNote: 3);
}

/// What was found: the passages to send, best first, and the words they were found by.
@immutable
class AskRetrieval {
  const AskRetrieval({required this.passages, required this.words, required this.notesRead});

  final List<AskPassage> passages;
  final List<String> words;

  /// How many notes the scope had.
  final int notesRead;

  bool get isEmpty => passages.isEmpty;

  /// The different notes the passages are from.
  int get notesUsed => passages.map((p) => p.note.id).toSet().length;
}

const int _passageLines = 8, _passageChars = 700;

final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$');
final RegExp _fence = RegExp(r'^\s{0,3}(```|~~~)');
final RegExp _marks = RegExp(r'\*\*|__|`|\[\[|\]\]|==|\^[\w-]+\s*$|\[\^[^\]]*\]');

/// [note] cut into passages (docs/ASK_THE_ORG.md, "Passages"): a heading starts one, a blank line ends a paragraph,
/// and paragraphs are joined up to about eight lines or 700 letters. Front matter and code fences' own lines are not
/// in any passage but keep their place in the counting.
List<AskPassage> passagesOf(Note note) {
  final body = note.body;
  final lines = body.split('\n');
  final frontLines = '\n'.allMatches(body.substring(0, frontMatterOffset(body))).length;
  final out = <AskPassage>[];
  var heading = '';
  var from = -1;
  final held = <String>[];
  var chars = 0;

  void flush() {
    if (from >= 0 && held.any((line) => line.trim().isNotEmpty)) {
      // A passage ends on its last line with words, so its range is never a blank tail.
      var last = held.length;
      while (last > 0 && held[last - 1].trim().isEmpty) {
        last -= 1;
      }
      out.add(AskPassage(note: note, fromLine: from + 1, toLine: from + last, lines: List.unmodifiable(held.sublist(0, last)), heading: heading));
    }
    from = -1;
    held.clear();
    chars = 0;
  }

  for (var at = frontLines; at < lines.length; at += 1) {
    final line = lines[at];
    if (_fence.hasMatch(line)) {
      flush();
      continue;
    }
    final head = _heading.firstMatch(line);
    if (head != null) {
      flush();
      heading = head.group(2)!.replaceAll(_marks, '').trim();
    }
    if (line.trim().isEmpty) {
      // A paragraph ends here; the passage goes on while it has room.
      if (held.length >= _passageLines || chars >= _passageChars) flush();
      if (from >= 0) held.add(line);
      continue;
    }
    if (from >= 0 && (held.length >= _passageLines || chars + line.length > _passageChars * 1.4)) flush();
    if (from < 0) from = at;
    held.add(line);
    chars += line.length;
  }
  flush();
  return out;
}

const Set<String> _common = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'been', 'but', 'by', 'can', 'could', 'did', 'do', 'does', 'for', 'from', //
  'had', 'has', 'have', 'he', 'her', 'his', 'how', 'i', 'if', 'in', 'into', 'is', 'it', 'its', 'me', 'my', 'of', 'on', //
  'or', 'our', 'she', 'so', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'they', 'this', 'to', 'us', 'was', //
  'we', 'were', 'what', 'when', 'where', 'which', 'who', 'whom', 'why', 'will', 'with', 'would', 'you', 'your', 'about', //
  'any', 'all', 'say', 'said', 'says', 'tell', 'know', 'notes', 'note', 'should', 'shall', 'just', 'get', 'got',
};

final RegExp _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// A word's plain stem: "meetings" → "meeting", "decided" → "decid", "replies" → "reply".
String askStem(String word) {
  if (word.length > 4 && word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
  if (word.length > 5 && word.endsWith('ing')) return word.substring(0, word.length - 3);
  if (word.length > 4 && word.endsWith('ed')) return word.substring(0, word.length - 2);
  if (word.length > 3 && word.endsWith('s') && !word.endsWith('ss')) return word.substring(0, word.length - 1);
  return word;
}

/// The words of [question] a passage is found by: two letters or more, the common ones left out, each once.
List<String> askWords(String question) {
  final seen = <String>{};
  for (final match in _wordPattern.allMatches(question.toLowerCase())) {
    final word = match.group(0)!;
    if (word.length < 2 || _common.contains(word)) continue;
    seen.add(word);
  }
  return seen.toList(growable: false);
}

Set<String> _wordSet(String text) => {for (final match in _wordPattern.allMatches(text.toLowerCase())) match.group(0)!};

/// Whether [word] is found among [words]: itself, its stem, or as the start of a word of four letters or more.
bool _has(Set<String> words, String word) {
  if (words.contains(word)) return true;
  final stem = askStem(word);
  if (words.contains(stem)) return true;
  if (stem.length < 4) return false;
  for (final each in words) {
    if (each.length >= 4 && (each.startsWith(stem) || (each.length >= stem.length - 1 && stem.startsWith(askStem(each))))) return true;
  }
  return false;
}

/// The passages of [notes] (the scope's, already filtered) worth sending for [question], best first, within
/// [budget] (docs/ASK_THE_ORG.md, "Score"). [now] is for the lift a recent note is given.
AskRetrieval retrieve(String question, List<Note> notes, {AskBudget budget = AskBudget.cloud, required int now}) {
  final words = askWords(question);
  if (words.isEmpty || notes.isEmpty) return AskRetrieval(passages: const [], words: words, notesRead: notes.length);

  final passages = [for (final note in notes) ...passagesOf(note)];
  if (passages.isEmpty) return AskRetrieval(passages: const [], words: words, notesRead: notes.length);
  final textWords = [for (final p in passages) _wordSet(p.text)];
  final headWords = [for (final p in passages) _wordSet(p.heading)];
  final titleWords = <String, Set<String>>{for (final note in notes) note.id: _wordSet(NoteFacts.of(note).title)};

  // How rare each word is across the scope's passages.
  final weight = <String, double>{};
  for (final word in words) {
    var df = 0;
    for (final set in textWords) {
      if (_has(set, word)) df += 1;
    }
    weight[word] = df == 0 ? 0 : math.log(1 + passages.length / df);
  }

  // The notes the app's own search finds for the words, which forgives a slip.
  final searched = {for (final found in findNotes(notes, words.join(' '))) found.note.id};

  final scores = List<double>.filled(passages.length, 0);
  for (var i = 0; i < passages.length; i += 1) {
    var score = 0.0;
    var hits = 0;
    for (final word in words) {
      final w = weight[word]!;
      if (w == 0) continue;
      if (_has(textWords[i], word)) {
        score += w;
        hits += 1;
        if (_has(headWords[i], word)) score += w * 0.5;
      }
      if (_has(titleWords[passages[i].note.id]!, word)) score += w;
    }
    if (hits == 0) continue;
    // A passage holding more of the question's words stands over one holding one word many times.
    score *= 1 + hits / words.length;
    if (searched.contains(passages[i].note.id)) score *= 1.3;
    scores[i] = score;
  }

  // The best notes' links, either way, lift the notes at their other ends a little.
  final bestNotes = <String>[];
  final order = [for (var i = 0; i < passages.length; i += 1) i]..sort((a, b) => scores[b].compareTo(scores[a]));
  for (final i in order) {
    if (scores[i] <= 0 || bestNotes.length >= 3) break;
    if (!bestNotes.contains(passages[i].note.id)) bestNotes.add(passages[i].note.id);
  }
  final byKey = {for (final note in notes) titleKey(NoteFacts.of(note).title): note.id};
  final linked = <String>{};
  for (final note in notes) {
    final out = {for (final link in linksIn(note.body)) byKey[link.key]}.whereType<String>();
    if (bestNotes.contains(note.id)) linked.addAll(out);
    if (out.any(bestNotes.contains)) linked.add(note.id);
  }
  linked.removeAll(bestNotes);
  const fortnight = 14 * 24 * 3600 * 1000;
  for (var i = 0; i < passages.length; i += 1) {
    if (scores[i] <= 0) continue;
    if (linked.contains(passages[i].note.id)) scores[i] *= 1.15;
    if (now - passages[i].note.updatedAt < fortnight) scores[i] *= 1.1;
  }

  order.sort((a, b) {
    final by = scores[b].compareTo(scores[a]);
    return by != 0 ? by : passages[b].note.updatedAt.compareTo(passages[a].note.updatedAt);
  });
  final chosen = <AskPassage>[];
  final perNote = <String, int>{};
  var chars = 0;
  for (final i in order) {
    if (scores[i] <= 0 || chosen.length >= budget.passages) break;
    final p = passages[i];
    if ((perNote[p.note.id] ?? 0) >= budget.perNote) continue;
    final size = p.text.length + p.title.length + 80;
    if (chars + size > budget.chars && chosen.isNotEmpty) continue;
    chosen.add(p);
    chars += size;
    perNote[p.note.id] = (perNote[p.note.id] ?? 0) + 1;
  }
  return AskRetrieval(passages: List.unmodifiable(chosen), words: words, notesRead: notes.length);
}
