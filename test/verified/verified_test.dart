// A verified page (lib/verified/verified.dart; Matt, 2026-10-30: "add all 12"): its front matter read and written,
// where it stands on a day (green, amber within a week, "Needs review" after), the edited-since flag, the bell's row
// when it runs out, and the query's `verified` field (lib/core/query/values.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/days.dart';
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/verified/verified.dart';

final DateTime friday = DateTime(2026, 10, 30, 10);

void main() {
  group('the front matter', () {
    test('a flow map with the handle quoted, as Verify… writes it, and the plainer forms by hand', () {
      expect(readVerified('{by: "@matt", until: 2026-12-01, words: 3f9a12c07b4e5d61}'), const Verified(by: 'matt', until: '2026-12-01', words: '3f9a12c07b4e5d61'));
      expect(readVerified('{by: @sam, until: 2026-12-01}'), const Verified(by: 'sam', until: '2026-12-01'));
      expect(readVerified("{ until: '2026-12-01', by: 'ana' }"), const Verified(by: 'ana', until: '2026-12-01'));
      expect(readVerified('@matt until 2026-12-01'), const Verified(by: 'matt', until: '2026-12-01'));
      for (final not in ['', 'yes', '{by: "@matt"}', '{until: 2026-12-01}', '{by: matt, until: 2026-02-30}', 'matt until soon']) {
        expect(readVerified(not), isNull, reason: not);
      }
    });

    test('Verify writes it, keeps the words as they were, and takes it off again', () {
      const body = '---\ntitle: Launch plan\n---\n# Launch plan\n\nShip on the 6th.';
      final verified = withVerified(body, by: 'matt', days: 30, today: friday);
      expect(verified, '---\ntitle: Launch plan\nverified: {by: "@matt", until: 2026-11-29, words: ${wordsMark(body)}}\n---\n# Launch plan\n\nShip on the 6th.');
      expect(verifiedOf(verified), Verified(by: 'matt', until: '2026-11-29', words: wordsMark(body)));
      expect(withVerified(verified, by: null), body);
      // A note with no front matter is given some, and the words are untouched.
      expect(withVerified('# Plan', by: 'sam', days: 90, today: friday), startsWith('---\nverified: {by: "@sam", until: 2027-01-28, words: '));
    });

    test('the fingerprint is of the words alone: the front matter changing is no edit', () {
      const one = '---\ntitle: A\n---\nWords', two = '---\ntitle: B\ntags: [x]\n---\nWords';
      expect(wordsMark(one), wordsMark(two));
      expect(wordsMark(one), isNot(wordsMark('---\ntitle: A\n---\nWords, changed')));
    });
  });

  group('where it stands', () {
    const verified = Verified(by: 'matt', until: '2026-12-01');
    test('fresh, then amber within a week of its last day, then expired from the day after', () {
      expect(verifiedStanding(verified, friday), VerifiedStanding.fresh);
      expect(verifiedStanding(verified, DateTime(2026, 11, 23)), VerifiedStanding.fresh);
      expect(verifiedStanding(verified, DateTime(2026, 11, 24)), VerifiedStanding.soon);
      expect(verifiedStanding(verified, DateTime(2026, 12, 1, 23)), VerifiedStanding.soon, reason: 'its last day still holds');
      expect(verifiedStanding(verified, DateTime(2026, 12, 2)), VerifiedStanding.expired);
    });

    test('what the badge says', () {
      expect(verifiedWords(verified, friday), 'Verified by Matt · until Dec 1');
      expect(verifiedWords(const Verified(by: 'sam-ortiz', until: '2027-01-04'), friday), 'Verified by Sam Ortiz · until Jan 4, 2027');
      expect(verifiedWords(verified, DateTime(2026, 12, 2)), 'Needs review');
    });

    test('edited since verified, only where a fingerprint was written and the words moved from it', () {
      const body = '---\nverified: x\n---\nThe plan.';
      final at = Verified(by: 'matt', until: '2026-12-01', words: wordsMark(body));
      expect(editedSinceVerified(at, body), isFalse);
      expect(editedSinceVerified(at, '$body And more.'), isTrue);
      expect(editedSinceVerified(const Verified(by: 'matt', until: '2026-12-01'), 'anything'), isFalse);
    });
  });

  group('the owner told when it runs out', () {
    final notes = [
      (id: 'a', title: 'Launch plan', body: '---\nverified: {by: "@matt", until: 2026-10-29}\n---\nx'),
      (id: 'b', title: 'Pricing', body: '---\nverified: {by: "@matt", until: 2026-11-29}\n---\nx'),
      (id: 'c', title: 'Theirs', body: '---\nverified: {by: "@sam", until: 2026-10-01}\n---\nx'),
      (id: 'd', title: 'Plain', body: 'no front matter'),
    ];

    test('only the owner’s pages that have run out, each once, by an id every device makes alike', () {
      final due = expiredNotices(notes, me: 'Matt', today: friday, told: (_) => false);
      expect([for (final page in due) page.noteId], ['a']);
      expect(expiredNotices(notes, me: 'matt', today: friday, told: (_) => false).single.id, due.single.id);
      expect(expiredNotices(notes, me: 'matt', today: friday, told: (id) => id == due.single.id), isEmpty);
      expect(expiredNotices(notes, me: 'sam', today: friday, told: (_) => false).single.noteId, 'c');
    });

    test('verified again, it is another last day and another row when that runs out', () {
      final first = expiredNotices(notes, me: 'matt', today: friday, told: (_) => false).single.id;
      final again = expiredNotices([(id: 'a', title: 'Launch plan', body: '---\nverified: {by: "@matt", until: 2026-12-01}\n---\nx')], me: 'matt', today: DateTime(2026, 12, 5), told: (_) => false).single.id;
      expect(again, isNot(first));
    });
  });

  group('the query’s verified field', () {
    final now = isoDay(DateTime.now());
    String until(int days) => isoDayAfter(now, days)!;
    QueryNote page(String id, String until) => QueryNote(id: id, body: '---\nverified: {by: "@matt", until: $until}\n---\n# $id\n', createdAt: 1, updatedAt: 1);
    final library = libraryOf([page('Fresh', until(40)), page('Soon', until(3)), page('Expired', until(-2)), QueryNote(id: 'Plain', body: '# Plain\n', createdAt: 1, updatedAt: 1)]);

    List<String> found(String where) {
      final reading = readQuery('from: notes\nwhere: $where');
      expect(reading.problem, isNull);
      return [for (final group in runQuery(reading.query!, library, now).groups) for (final row in group.rows) row.name]..sort();
    }

    test('verified = yes is every page that holds, verified = expired every one that ran out, verified alone every verified page', () {
      expect(found('verified = yes'), ['Fresh', 'Soon']);
      expect(found('verified = expired'), ['Expired']);
      expect(found('verified = soon'), ['Soon']);
      expect(found('verified'), ['Expired', 'Fresh', 'Soon']);
      expect(found('verified is empty'), ['Plain']);
    });
  });
}
