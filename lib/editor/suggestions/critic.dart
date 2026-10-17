/// Suggested edits, as CriticMarkup writes them: read out of a note's words, and Keep and Revert as the edits that
/// settle one. The drawing is suggestions.dart's.
///
///     The deposit is {--four hundred--}{>>Claude<<} {++due Friday++}{>>Claude<<}, {~~not~>never~~}{>>Claude<<} late.
///
/// The connector writes a change it was asked to suggest this way (docs/CLAUDE_LIVE.md, "Suggest mode"): an
/// insertion `{++…++}`, a deletion `{--…--}` and a replacement `{~~old~>new~~}`, each followed by its author in a
/// note, `{>>Claude<<}`. Other markdown apps read the same marks. The note is the whole truth: nothing about a
/// suggestion is kept anywhere but in its words, so one made on another device, or typed by hand, is the same.
///
/// A suggestion is never read inside code (a fence or a span of backticks) or the front matter, where the marks
/// are someone's words. They do not nest: what is inside one is its words, marks and all. One may run over a line's
/// end; its author's note may not.
library;

import '../../core/front_matter.dart' show frontMatterEnd;
import '../editor.dart';

/// What a suggestion does to the words.
enum SuggestionKind { insert, delete, replace }

/// One suggested edit: where the whole of it lies, its author's note included, and where its old and new words are.
class Suggestion {
  const Suggestion({
    required this.kind,
    required this.from,
    required this.to,
    required this.oldFrom,
    required this.oldTo,
    required this.newFrom,
    required this.newTo,
    required this.oldText,
    required this.newText,
    required this.markupTo,
    this.author,
  });

  final SuggestionKind kind;

  /// The `{` it opens with, and the end of its author's note (or of its closing mark, where it has no note).
  final int from;
  final int to;

  /// The words it takes out: a deletion's, a replacement's old ones. Empty, at the opening mark's end, for an
  /// insertion.
  final int oldFrom;
  final int oldTo;

  /// The words it puts in: an insertion's, a replacement's new ones. Empty, at the closing mark, for a deletion.
  final int newFrom;
  final int newTo;

  final String oldText;
  final String newText;

  /// Where its closing mark ends: the author's note, if it has one, runs from here to [to].
  final int markupTo;

  /// Who suggested it, from the note after it (`{>>Claude<<}`); null where there is none.
  final String? author;

  /// The marks that are not words: the opening mark, a replacement's `~>`, the closing mark and the author's note,
  /// in order.
  List<({int from, int to})> get marks => <({int from, int to})>[
    (from: from, to: from + 3),
    if (kind == SuggestionKind.replace) (from: oldTo, to: oldTo + 2),
    (from: markupTo - 3, to: markupTo),
    if (to > markupTo) (from: markupTo, to: to),
  ];

  /// Whether `pos` is on it, either edge included.
  bool covers(int pos) => pos >= from && pos <= to;

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.kind == kind &&
      other.from == from &&
      other.to == to &&
      other.oldFrom == oldFrom &&
      other.oldTo == oldTo &&
      other.newFrom == newFrom &&
      other.newTo == newTo &&
      other.markupTo == markupTo &&
      other.oldText == oldText &&
      other.newText == newText &&
      other.author == author;

  @override
  int get hashCode => Object.hash(kind, from, to, oldFrom, oldTo, newFrom, newTo, markupTo, oldText, newText, author);

  @override
  String toString() => 'Suggestion(${kind.name} $from-$to, "$oldText" -> "$newText"${author == null ? '' : ' by $author'})';
}

/// Words that are code or front matter, which a suggestion may not reach into: rubbed out to this before the
/// marks are looked for, the length kept so every position stays where it was.
const String _block = '\u0000';

/// A span of backticks: rubbed out to this, which a suggestion may hold (`{++run `npm i`++}`) but not begin in.
const String _inline = '\u0001';

/// A fence's run at the start of a line, up to three spaces in.
final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// A span of backticks on one line: a run, the fewest letters, and a run as long, neither touching another backtick.
final RegExp _codeSpan = RegExp(r'(?<!`)(`+)(?!`)[^\n]*?(?<!`)\1(?!`)');

/// The three kinds and the author's note after one. What is inside may run over lines but never into code or front
/// matter; the note stays on its line.
final RegExp _suggestion = RegExp(
  r'\{\+\+([^\x00]+?)\+\+\}'
  r'|\{--([^\x00]+?)--\}'
  r'|\{~~([^\x00]*?)~>([^\x00]*?)~~\}',
);
final RegExp _authorNote = RegExp(r'\{>>([^\n<>]*?)<<\}');

/// The words with their code and front matter rubbed out (see [_block], [_inline]), every position kept.
String _quieted(String text) {
  final lines = text.split('\n');
  final out = StringBuffer();
  final front = frontMatterEnd(lines);
  String? open;
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    if (n > 0) out.write('\n');
    var quiet = n < front;
    if (!quiet) {
      final run = _fence.firstMatch(line)?.group(1);
      if (open != null) {
        // A fence closes on a run of its own letter at least as long, and nothing after it.
        if (run != null && run[0] == open[0] && run.length >= open.length && line.substring(line.indexOf(run) + run.length).trim().isEmpty) open = null;
        quiet = true;
      } else if (run != null) {
        open = run;
        quiet = true;
      }
    }
    if (quiet) {
      out.write(_block * line.length);
    } else if (line.contains('`')) {
      out.write(line.replaceAllMapped(_codeSpan, (match) => _inline * match.group(0)!.length));
    } else {
      out.write(line);
    }
  }
  return out.toString();
}

/// Whether the words could hold a suggestion at all: one of the three opening marks is in them.
bool mayHoldSuggestions(String text) => text.contains('{++') || text.contains('{--') || text.contains('{~~');

/// Every suggestion in `text`, in order, counting positions from `offset`.
List<Suggestion> suggestionsIn(String text, [int offset = 0]) {
  if (!mayHoldSuggestions(text)) return const <Suggestion>[];
  final quiet = _quieted(text);
  final found = <Suggestion>[];
  for (final match in _suggestion.allMatches(quiet)) {
    final start = match.start;
    var end = match.end;
    String? author;
    final note = _authorNote.matchAsPrefix(quiet, end);
    if (note != null) {
      final name = note.group(1)!.trim();
      author = name.isEmpty ? null : name;
      end = note.end;
    }
    final markupTo = match.end;
    final SuggestionKind kind;
    final int oldFrom, oldTo, newFrom, newTo;
    if (match.group(1) != null) {
      kind = SuggestionKind.insert;
      oldFrom = oldTo = start + 3;
      newFrom = start + 3;
      newTo = markupTo - 3;
    } else if (match.group(2) != null) {
      kind = SuggestionKind.delete;
      oldFrom = start + 3;
      oldTo = markupTo - 3;
      newFrom = newTo = markupTo - 3;
    } else {
      kind = SuggestionKind.replace;
      oldFrom = start + 3;
      oldTo = oldFrom + match.group(3)!.length;
      newFrom = oldTo + 2;
      newTo = markupTo - 3;
    }
    found.add(
      Suggestion(
        kind: kind,
        from: offset + start,
        to: offset + end,
        oldFrom: offset + oldFrom,
        oldTo: offset + oldTo,
        newFrom: offset + newFrom,
        newTo: offset + newTo,
        markupTo: offset + markupTo,
        oldText: text.substring(oldFrom, oldTo),
        newText: text.substring(newFrom, newTo),
        author: author,
      ),
    );
  }
  return found;
}

/// A line that may begin or hold a suggestion's marks: the only lines whose note is read again for them.
final LineFact<bool> _marked = LineFact<bool>((text) => mayHoldSuggestions(text) ? true : null);

final DocMemo<List<Suggestion>> _ofDoc = DocMemo<List<Suggestion>>((doc) => _marked.nowhere(doc) ? const <Suggestion>[] : suggestionsIn(doc.toString()));

/// Every suggestion in a document, read once for each document. Not to be changed.
List<Suggestion> suggestionsOf(Doc doc) => _ofDoc.of(doc);

/// The suggestion `pos` is on, if there is one.
Suggestion? suggestionAt(Doc doc, int pos) {
  for (final one in suggestionsOf(doc)) {
    if (one.covers(pos)) return one;
    if (one.from > pos) break;
  }
  return null;
}

/// The words a note reads once `suggestion` is kept (`keep`) or reverted: the whole of it, marks and note, given
/// its new words or its old ones.
ChangeSpec settled(Suggestion suggestion, {required bool keep}) =>
    ChangeSpec(from: suggestion.from, to: suggestion.to, insert: keep ? suggestion.newText : suggestion.oldText);

/// A line with nothing on it but how it begins: space, a quote's `>`, a list's marker and a to-do's box, or a
/// heading's hashes.
final RegExp _leadOnly = RegExp(r'^[ \t]*(?:>[ \t]*)*(?:(?:[-*+]|\d{1,9}[.)])(?:[ \t]+\[[ xX]\])?|#{1,6})?[ \t]*$');

/// Whether `text`, one line or several, is nothing but the lines' leads.
bool leadOnly(String text) => text.split('\n').every(_leadOnly.hasMatch);

/// The edits that settle `chosen` (suggestions of `text`, in order) the same way. The connector keeps a whole
/// line's lead outside its marks (`- [ ] {++Buy a crib++}{>>Claude<<}`, `## {--Old--}{>>Claude<<}`), so a line
/// that would be left with nothing but its lead (a deletion kept, an insertion reverted) is taken out whole, its
/// break with it; every other suggestion is [settled] where it stands. The chosen suggestions on one line are
/// settled together before the line is read, and one not chosen is still there, so its line stays.
List<ChangeSpec> settlement(String text, List<Suggestion> chosen, {required bool keep}) {
  final changes = <ChangeSpec>[];
  var i = 0;
  while (i < chosen.length) {
    // The lines the next suggestion is on, and every chosen one that starts on them.
    final lineFrom = chosen[i].from == 0 ? 0 : text.lastIndexOf('\n', chosen[i].from - 1) + 1;
    var j = i;
    var lineTo = _lineEnd(text, chosen[i].to);
    while (j + 1 < chosen.length && chosen[j + 1].from <= lineTo) {
      j++;
      final end = _lineEnd(text, chosen[j].to);
      if (end > lineTo) lineTo = end;
    }
    final group = chosen.sublist(i, j + 1);
    final resolved = StringBuffer();
    var at = lineFrom;
    for (final one in group) {
      resolved
        ..write(text.substring(at, one.from))
        ..write(keep ? one.newText : one.oldText);
      at = one.to;
    }
    resolved.write(text.substring(at, lineTo));
    if (leadOnly(resolved.toString())) {
      // The line goes with the break after it, or the last line with the one before it.
      changes.add(lineTo < text.length ? ChangeSpec(from: lineFrom, to: lineTo + 1) : ChangeSpec(from: lineFrom > 0 ? lineFrom - 1 : 0, to: lineTo));
    } else {
      changes.addAll(<ChangeSpec>[for (final one in group) settled(one, keep: keep)]);
    }
    i = j + 1;
  }
  return changes;
}

/// Where the line holding `pos` ends, before its break.
int _lineEnd(String text, int pos) {
  final end = text.indexOf('\n', pos);
  return end < 0 ? text.length : end;
}

void _settle(StateCommandTarget view, List<Suggestion> chosen, bool keep) => view.dispatch(
  TransactionSpec(changes: settlement(view.state.doc.toString(), chosen, keep: keep), userEvent: keep ? 'suggest.keep' : 'suggest.revert'),
);

/// Settles the suggestion that starts at `from`, as one edit and one undo. False where none starts there.
bool settleSuggestion(StateCommandTarget view, int from, {required bool keep}) {
  final one = suggestionsOf(view.state.doc).where((s) => s.from == from).firstOrNull;
  if (one == null || view.state.readOnly) return false;
  _settle(view, <Suggestion>[one], keep);
  return true;
}

/// Settles every suggestion in the note the same way, as one edit and one undo. False where there are none.
bool settleAllSuggestions(StateCommandTarget view, {required bool keep}) {
  final all = suggestionsOf(view.state.doc);
  if (all.isEmpty || view.state.readOnly) return false;
  _settle(view, all, keep);
  return true;
}

/// Who suggested what: the one author every suggestion names, or null where they name none or several.
String? soleAuthor(List<Suggestion> suggestions) {
  final authors = <String?>{for (final one in suggestions) one.author};
  return authors.length == 1 ? authors.first : null;
}
