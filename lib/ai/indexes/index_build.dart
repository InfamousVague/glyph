/// One refresh of an index, from a folder's page and its notes to the page with its section written again
/// (docs/AI_INDEXES.md §3). Matt, 2026-11-02: "the AI keeps an index note (what's here, the key decisions, who owns
/// what) and updates it as notes change".
///
/// **Incremental.** The previous section is read back ([parseSection]); a note is read again only where it changed
/// after the section's `updated=`, or the section does not list it ([notesToRead]). What the section said of every
/// other note is kept, a note gone is dropped, and only the changed notes go to the AI, in batches. A full rebuild
/// reads them all. Owners and Recently changed are worked out afresh from every note each time, without the AI.
///
/// **Links are the app's.** The AI answers about a note by the number it was sent under; the link is that note's
/// title. A note the AI said nothing of is still listed (under Other), so the page names every note in the folder.
library;

import '../../core/background_jobs.dart' show JobEstimate;
import '../../core/front_matter.dart' show frontMatterOffset;
import '../../core/note.dart';
import '../../core/title_key.dart' show titleKey;
import 'index_ai.dart';
import 'index_scope.dart';
import 'index_section.dart';

/// Why a refresh did not write.
class IndexRefused implements Exception {
  const IndexRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The person stopped it.
class IndexStopped implements Exception {
  const IndexStopped();
}

/// What a refresh made.
class IndexBuilt {
  const IndexBuilt({required this.body, required this.content, required this.read});

  /// The page's words with the section written again.
  final String body;
  final IndexContent content;

  /// The ids of the notes read again and sent to the AI.
  final List<String> read;
}

/// The notes of [notes] (the folder's, [notesIn]) a refresh of [pageBody]'s section reads: all of them for [full] or
/// a page with no section yet; else those changed after its `updated=` and those it does not list.
List<Note> notesToRead(String pageBody, List<Note> notes, {bool full = false}) {
  final span = readSection(pageBody).span;
  final since = span?.updated;
  if (full || span == null || since == null) return notes;
  final listed = {for (final e in parseSection(span.inner).entries) e.key};
  final ms = since.millisecondsSinceEpoch;
  return [for (final note in notes) if (note.updatedAt > ms || !listed.contains(titleKey(titleOf(note)))) note];
}

/// Whether [pageBody]'s index is behind [notes]: a note to read again, or a note it links that is gone.
bool indexDirty(String pageBody, List<Note> notes) {
  final span = readSection(pageBody).span;
  if (span == null) return true;
  if (notesToRead(pageBody, notes).isNotEmpty) return true;
  final here = byTitle(notes);
  return parseSection(span.inner).entries.any((e) => !here.containsKey(e.key));
}

/// What reading [toRead] with [ai] should take, said before a big one starts (lib/activity/activity_cost.dart).
JobEstimate indexEstimate(List<Note> toRead, IndexAi ai) {
  final noteChars = noteCharsOf(ai);
  var chars = 0;
  for (final note in toRead) {
    final words = note.body.length - frontMatterOffset(note.body);
    chars += words < noteChars ? words : noteChars;
  }
  final batches = (chars / batchCharsOf(ai)).ceil() + 1;
  final seconds = ai.onDevice ? chars ~/ 300 + batches * 40 : batches * 12 + 6;
  return JobEstimate(count: toRead.length, one: 'note', many: 'notes', duration: Duration(seconds: seconds), provider: ai.name);
}

/// Refreshes [pageBody]'s section for the folder [folderTitle] whose notes are [notes] ([notesIn]), asking [ai], as
/// of [now] (see the header). [onProgress] hears each batch; [stopped] is asked between them, and a stop throws
/// [IndexStopped] with nothing written. Throws [IndexRefused] for a page whose section has lost its end marker.
Future<IndexBuilt> buildIndex({
  required String folderTitle,
  required String pageBody,
  required List<Note> notes,
  required IndexAi ai,
  required DateTime now,
  bool full = false,
  void Function(int done, int total)? onProgress,
  bool Function()? stopped,
}) async {
  final found = readSection(pageBody);
  if (found.broken) throw const IndexRefused('The index’s end marker is missing from the page, so it was left alone. Put back “<!-- /ghost:index -->” or delete the index’s start marker.');
  final previous = full || found.span == null ? const IndexContent() : parseSection(found.span!.inner);
  final here = byTitle(notes);
  final toRead = notesToRead(pageBody, notes, full: full);
  final reading = {for (final note in toRead) note.id};

  // What the section said of the notes not read again, under their titles as they are now.
  final entries = <String, IndexEntry>{};
  for (final e in previous.entries) {
    final note = here[e.key];
    if (note == null || reading.contains(note.id)) continue;
    entries[note.id] = IndexEntry(title: titleOf(note), theme: e.theme, about: e.about);
  }
  final decisions = <IndexDecision>[
    for (final d in previous.decisions)
      if (here[titleKey(d.title)] case final note? when !reading.contains(note.id)) IndexDecision(date: d.date, what: d.what, title: titleOf(note)),
  ];
  final themes = <String>[...previous.themes];

  // The changed notes, a batch at a time.
  final batches = <List<Note>>[];
  final noteChars = noteCharsOf(ai), batchChars = batchCharsOf(ai);
  var size = 0;
  for (final note in toRead) {
    final words = note.body.length - frontMatterOffset(note.body);
    final cost = (words < noteChars ? words : noteChars) + 80;
    if (batches.isEmpty || (size + cost > batchChars && batches.last.isNotEmpty)) {
      batches.add([]);
      size = 0;
    }
    batches.last.add(note);
    size += cost;
  }
  for (var b = 0; b < batches.length; b += 1) {
    if (stopped?.call() ?? false) throw const IndexStopped();
    onProgress?.call(b, batches.length);
    final batch = batches[b];
    final sources = [
      for (final note in batch) IndexSource(title: titleOf(note), day: dayOf(DateTime.fromMillisecondsSinceEpoch(note.updatedAt)), text: note.body.substring(frontMatterOffset(note.body))),
    ];
    final answer = await ai.ask(system: noteFactsSystem, prompt: noteFactsPrompt(sources, themes: themes, noteChars: noteChars), maxTokens: ai.onDevice ? 1500 : 4000);
    if (stopped?.call() ?? false) throw const IndexStopped();
    final facts = {for (final f in readNoteFacts(answer, batch.length)) f.n: f};
    for (var i = 0; i < batch.length; i += 1) {
      final note = batch[i], said = facts[i + 1];
      final theme = said?.theme ?? 'Other';
      if (!themes.contains(theme)) themes.add(theme);
      entries[note.id] = IndexEntry(title: titleOf(note), theme: theme, about: said?.about ?? '');
      for (final (date, what) in said?.decisions ?? const <(String, String)>[]) {
        decisions.add(IndexDecision(date: date, what: what, title: titleOf(note)));
      }
    }
  }
  onProgress?.call(batches.length, batches.length);

  // In the themes' order, Other last, then by title.
  final order = [...themes.where((t) => t != 'Other'), if (themes.contains('Other')) 'Other'];
  final listed = entries.values.toList()
    ..sort((a, b) {
      final byTheme = order.indexOf(a.theme).compareTo(order.indexOf(b.theme));
      return byTheme != 0 ? byTheme : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  decisions.sort((a, b) => b.date.compareTo(a.date));

  // The overview again where anything changed, kept as it was where asking fails.
  var overview = previous.overview;
  if (toRead.isNotEmpty || entries.length != previous.entries.length || overview.isEmpty) {
    if (stopped?.call() ?? false) throw const IndexStopped();
    final byTheme = <String, List<String>>{};
    for (final e in listed) {
      byTheme.putIfAbsent(e.theme, () => []).add(e.about.isEmpty ? e.title : '${e.title}: ${e.about}');
    }
    try {
      if (listed.isNotEmpty) overview = readOverview(await ai.ask(system: overviewSystem, prompt: overviewPrompt(folderTitle, byTheme), maxTokens: ai.onDevice ? 300 : 800));
    } catch (_) {
      if (stopped?.call() ?? false) throw const IndexStopped();
    }
  }

  final content = IndexContent(overview: overview, entries: listed, decisions: decisions.take(20).toList(), owners: ownersIn(notes), recent: recentIn(notes));
  final body = withSection(pageBody, renderSection(content, updated: now, by: ai.name));
  if (body == null) throw const IndexRefused('The index’s end marker is missing from the page.');
  return IndexBuilt(body: body, content: content, read: [for (final note in toRead) note.id]);
}
