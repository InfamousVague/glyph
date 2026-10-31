/// A ticket's likely duplicates (Matt, 2026-10-31: "When creating a ticket (any entry point, including forms and
/// triage), likely duplicates are shown, using titles plus words via the link index's word index, and on-device
/// embeddings if the app has them; the AI is optional and on-device only").
///
/// **How.** A title's words, less the small ones every title has ("the", "to", "when"), are looked up in the link
/// index's words (lib/core/link_index.dart `notesSaying`): only the tickets that say one of them are weighed at all, so
/// a library of thousands is a handful of sets. Each is weighed by the words its title shares with the one asked
/// about, the rarer a word the more it counts (a word in two notes says more than one in two hundred), against all
/// the words either title has; the words of the new ticket's own body, where it has any, count a little towards a
/// ticket whose words say them. A done ticket weighs a little less, and one already closed as another's duplicate
/// (`duplicate-of:`) is never offered.
///
/// **No embeddings.** The app has no on-device embedding model today (lib/ai has a summary model and Claude, which is
/// not on the device), so nothing here asks one: the words alone, which is quick, private and explains itself (the
/// words two titles share are what the hint shows). [DuplicateScorer] is the seam where one would go.
///
/// Pure, given the tickets and the index, so each is a test (test/book_core/ticket_duplicates_test.dart).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterValue;
import '../core/link_index.dart' show LinkIndex, plainText, wordsIn;
import '../core/properties.dart';
import 'tickets.dart';

/// The front matter key a closed duplicate names what it duplicates by.
const String duplicateOfKey = 'duplicate-of';

/// Words too common in a ticket's title to say anything.
const Set<String> _small = {
  'a', 'an', 'the', 'and', 'or', 'but', 'to', 'of', 'in', 'on', 'at', 'by', 'for', 'from', 'with', 'into', 'onto', 'is', 'are', 'be', 'it', 'its', 'as', 'if', 'when', 'then', //
  'than', 'that', 'this', 'not', 'no', 'can', 'cant', 'should', 'does', 'doesn', 'don', 'dont', 'do', 'we', 'i', 'you', 'our', 'my', 'so', 'up', 'out', 's', 't', //
};

/// A title's words as they are compared: lower case, letters and digits, none of the small ones, a plural's `s` off.
List<String> titleTerms(String text) {
  final out = <String>[];
  for (final word in wordsIn(text)) {
    if (_small.contains(word) || (word.length < 3 && int.tryParse(word) == null)) continue;
    final stem = word.length > 4 && word.endsWith('s') && !word.endsWith('ss') ? word.substring(0, word.length - 1) : word;
    if (!out.contains(stem)) out.add(stem);
  }
  return out;
}

/// One likely duplicate: the ticket, how alike, and the words their titles share.
@immutable
class DuplicateHit {
  const DuplicateHit({required this.entry, required this.score, required this.shared});
  final TicketEntry entry;

  /// From 0 to about 1.25: the titles' weighted overlap, and a little for the words.
  final double score;

  /// The words the two titles share, as the hint shows them.
  final List<String> shared;

  @override
  String toString() => 'DuplicateHit(${entry.ticket.id ?? entry.title} ${score.toStringAsFixed(2)} $shared)';
}

/// Something else that weighs two tickets alike, where the app has one (an on-device embedding): 0 to 1, added to the
/// words' weight at [DuplicateScorer.weight].
abstract interface class DuplicateScorer {
  double get weight;
  double alike(String title, TicketEntry other);
}

/// Whether [entry] is closed as another's duplicate.
bool isDuplicateClosed(TicketEntry entry) => (frontMatterValue(entry.note.body, duplicateOfKey) ?? '').trim().isNotEmpty;

/// The tickets among [entries] likely to be the one [title] names, most alike first, at most [most], none under
/// [floor]. [words] is the new ticket's body, if it has one; [selfId] the note it is, left out; [index] the link
/// index, whose words narrow the tickets weighed (every ticket is weighed without one).
List<DuplicateHit> likelyDuplicates({
  required String title,
  required List<TicketEntry> entries,
  String words = '',
  LinkIndex? index,
  String? selfId,
  int most = 5,
  double floor = 0.25,
  DuplicateScorer? scorer,
}) {
  final terms = titleTerms(title);
  if (terms.isEmpty || entries.isEmpty) return const [];
  final byId = {for (final entry in entries) entry.note.id: entry};
  // The tickets that say one of the title's words, by the index; or all of them.
  final Iterable<TicketEntry> weighed;
  if (index != null && index.length > 0) {
    final ids = <String>{};
    for (final term in terms) {
      ids.addAll(index.notesSaying(term));
      ids.addAll(index.notesSaying('${term}s'));
    }
    weighed = [for (final id in ids) ?byId[id]];
  } else {
    weighed = entries;
  }
  // How rare each word is, among the tickets' titles.
  final titles = {for (final entry in entries) entry.note.id: titleTerms(entry.title)};
  final count = entries.length;
  final seen = <String, int>{};
  for (final each in titles.values) {
    for (final term in each) {
      seen.update(term, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  double rarity(String term) => math.log(1 + count / (1 + (seen[term] ?? 0)));
  final bodyTerms = words.isEmpty ? <String>[] : [for (final term in titleTerms(plainText(words))) if (!terms.contains(term)) term];
  bodyTerms.sort((a, b) => rarity(b).compareTo(rarity(a)));
  final extra = bodyTerms.take(20).toList();
  final hits = <DuplicateHit>[];
  for (final entry in weighed) {
    if (entry.note.id == selfId || isDuplicateClosed(entry)) continue;
    final theirs = titles[entry.note.id] ?? const <String>[];
    if (theirs.isEmpty) continue;
    final shared = [for (final term in terms) if (theirs.contains(term)) term];
    if (shared.isEmpty) continue;
    final all = {...terms, ...theirs};
    var score = shared.fold<double>(0, (sum, term) => sum + rarity(term)) / all.fold<double>(0, (sum, term) => sum + rarity(term));
    if (extra.isNotEmpty) {
      final said = index?.factsOf(entry.note.id)?.words.toSet() ?? wordsIn(plainText(entry.note.body)).toSet();
      final told = extra.where(said.contains).fold<double>(0, (sum, term) => sum + rarity(term));
      score += 0.25 * told / extra.fold<double>(0, (sum, term) => sum + rarity(term));
    }
    if (scorer != null) score += scorer.weight * scorer.alike(title, entry);
    if (entry.ticket.category == StatusCategory.done) score *= 0.9;
    if (score >= floor) hits.add(DuplicateHit(entry: entry, score: score, shared: shared));
  }
  hits.sort((a, b) {
    final by = b.score.compareTo(a.score);
    return by != 0 ? by : (a.entry.ticket.id ?? a.entry.title).compareTo(b.entry.ticket.id ?? b.entry.title);
  });
  return hits.length > most ? hits.sublist(0, most) : hits;
}
