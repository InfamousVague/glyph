import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/search_query.dart';

/// The operators a search reads (lib/core/search_query.dart), one rule a test.
void main() {
  final now = DateTime(2026, 10, 16, 15, 30);
  SearchQuery read(String text) => parseSearch(text, now: now);
  int day(int y, int m, int d) => DateTime(y, m, d).millisecondsSinceEpoch;

  test('plain words are read as they always were: lower case, split at spaces, nothing filtered', () {
    final q = read('  Trip   Packing ');
    expect(q.words, ['trip', 'packing']);
    expect(q.filters, isFalse);
    expect(q.parts, isEmpty);
    expect(read('').blank, isTrue);
    expect(read('   ').blank, isTrue);
  });

  test('a word with a colon that is no operator, or an operator with a value it does not know, stays a word', () {
    expect(read('note:taking').words, ['note:taking']);
    expect(read('https://example.com').words, ['https://example.com']);
    expect(read('is:blue').words, ['is:blue']);
    expect(read('has:dog').words, ['has:dog']);
    expect(read('before:someday').words, ['before:someday']);
    expect(read('tag:42').words, ['tag:42']);
    expect(read('tag:').words, ['tag:']);
    expect(read('is:blue').filters, isFalse);
  });

  test('tag: and #tag, nested tags, and a minus to leave one out', () {
    final q = read('tag:Work #web/Launch -tag:#draft -#old');
    expect(q.tags, ['work', 'web/launch']);
    expect(q.notTags, ['draft', 'old']);
    expect(q.words, isEmpty);
    expect([for (final p in q.parts) p.label], ['Tagged #work', 'Tagged #web/launch', 'Not #draft', 'Not #old']);
    // A trailing slash is punctuation, as in a note.
    expect(read('tag:work/').tags, ['work']);
    // A digit first is no tag.
    expect(read('#42').words, ['#42']);
  });

  test('in: takes a quoted name with spaces, and keeps the words after it apart', () {
    final q = read('in:"Field  Notes" ferns -in:Archive');
    expect(q.places, ['field notes']);
    expect(q.notPlaces, ['archive']);
    expect(q.words, ['ferns']);
    expect(q.parts.first.label, 'In Field Notes');
    // A quote still being typed runs to the end.
    expect(read('in:"Field no').places, ['field no']);
  });

  test('is: and has: with their words', () {
    final q = read('is:pinned is:ARCHIVED is:todo is:done is:ticket has:image has:link has:recording has:todo -is:canvas -has:photo');
    expect(q.isFlags, {SearchIs.pinned, SearchIs.archived, SearchIs.todo, SearchIs.done, SearchIs.ticket});
    expect(q.has, {SearchHas.image, SearchHas.link, SearchHas.recording, SearchHas.todo});
    expect(q.notIs, {SearchIs.canvas});
    expect(q.notHas, {SearchHas.image});
    expect(q.archived, isTrue);
    expect(read('is:pinned').archived, isFalse);
  });

  test('before: and after: are about when a note was made: before the day, and from the day on', () {
    final q = read('after:2026-10-01 before:2026-10-15');
    expect(q.made, TimeSpan(from: day(2026, 10, 1), to: day(2026, 10, 15)));
    expect(q.changed, const TimeSpan());
    expect(read('before:2026-10').made, TimeSpan(to: day(2026, 10, 1)));
    expect(read('after:2026').made, TimeSpan(from: day(2026, 1, 1)));
    expect(read('after:today').made, TimeSpan(from: day(2026, 10, 16)));
    expect(read('before:yesterday').made, TimeSpan(to: day(2026, 10, 15)));
    // A minus turns it round.
    expect(read('-before:2026-10-01').made, TimeSpan(from: day(2026, 10, 1)));
    // No such day.
    expect(read('after:2026-02-30').words, ['after:2026-02-30']);
    expect(read('after:2026-13').words, ['after:2026-13']);
  });

  test('updated: is the last change: a span back from now, a day, or before or after one', () {
    final ms = now.millisecondsSinceEpoch;
    expect(read('updated:<7d').changed, TimeSpan(from: ms - 7 * Duration.millisecondsPerDay));
    expect(read('updated:7d').changed, TimeSpan(from: ms - 7 * Duration.millisecondsPerDay));
    expect(read('updated:>2w').changed, TimeSpan(to: ms - 14 * Duration.millisecondsPerDay));
    expect(read('updated:<1m').changed, TimeSpan(from: ms - 30 * Duration.millisecondsPerDay));
    expect(read('updated:2026-10-01').changed, TimeSpan(from: day(2026, 10, 1), to: day(2026, 10, 2)));
    expect(read('updated:<2026-10-01').changed, TimeSpan(to: day(2026, 10, 1)));
    expect(read('updated:>2026-10-01').changed, TimeSpan(from: day(2026, 10, 2)));
    expect(read('updated:today').changed, TimeSpan(from: day(2026, 10, 16), to: day(2026, 10, 17)));
    expect(read('created:<3d').made, TimeSpan(from: ms - 3 * Duration.millisecondsPerDay));
    expect(read('updated:<7d').parts.single.label, 'Changed in the last 7 days');
    expect(read('updated:>1w').parts.single.label, 'Changed over a week ago');
    // Two of them are both held: the later start and the earlier end.
    expect(read('after:2026-10-01 created:<2026-10-10 before:2026-10-15').made, TimeSpan(from: day(2026, 10, 1), to: day(2026, 10, 10)));
    expect(read('updated:soon').words, ['updated:soon']);
    // A minus turns an open span round; a day has no one span outside it, and is a word left out.
    expect(read('-updated:<7d').changed, TimeSpan(to: ms - 7 * Duration.millisecondsPerDay));
    expect(read('-updated:<7d').parts.single.label, 'Not changed in the last 7 days');
    expect(read('-updated:2026-10-01').without, ['updated:2026-10-01']);
  });

  test('an exact phrase, a phrase and a word left out', () {
    final q = read('"Weekend   Trip" boots -"rain jacket" -socks');
    expect(q.phrases, ['weekend trip']);
    expect(q.withoutPhrases, ['rain jacket']);
    expect(q.without, ['socks']);
    expect(q.words, ['boots']);
    expect([for (final p in q.parts) p.label], ['“weekend trip”', 'Without “rain jacket”', 'Without “socks”']);
    // A lone minus, and an empty pair of quotes, ask for nothing.
    expect(read('-').words, ['-']);
    expect(read('""').blank, isTrue);
  });

  test('each part says where it was typed', () {
    const text = 'ferns tag:garden  is:pinned';
    final q = read(text);
    expect([for (final p in q.parts) text.substring(p.start, p.end)], ['tag:garden', 'is:pinned']);
    expect(q.parts.first.kind, SearchPartKind.tag);
  });

  test('a span holds its start and not its end', () {
    const span = TimeSpan(from: 10, to: 20);
    expect(span.holds(10), isTrue);
    expect(span.holds(19), isTrue);
    expect(span.holds(20), isFalse);
    expect(const TimeSpan().holds(-5), isTrue);
  });
}
