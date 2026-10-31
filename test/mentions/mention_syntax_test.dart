// Mentions as a note writes them (lib/mentions/mention_syntax.dart; Matt, 2026-10-30: "add all 12"): `@sam` and
// `@2026-11-06`, never in quiet places; days typed as words read on a clock held at Friday 30 October 2026; and a
// note's words read and written back unchanged.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/mentions/mention_syntax.dart';

/// Friday 30 October 2026, the day Matt asked.
final DateTime friday = DateTime(2026, 10, 30, 10);

List<String> said(String text) => [for (final m in mentionsIn(text)) '${m.kind.name}:${m.value}'];

void main() {
  group('a mention in a line', () {
    test('a person and a day, where each is', () {
      const line = 'Ask @sam to look at it by @2026-11-06';
      final found = mentionsIn(line);
      expect(said(line), ['person:sam', 'day:2026-11-06']);
      expect((found[0].from, found[0].to), (line.indexOf('@sam'), line.indexOf('@sam') + 4));
      expect(line.substring(found[1].from, found[1].to), '@2026-11-06');
    });

    test('a trailing stop is the sentence, a bracket opens one, an address is not one', () {
      expect(said('Ask @sam. Then (@ana) and [@bo-k], sam@example.com, @sam@mastodon.social'), ['person:sam', 'person:ana', 'person:bo-k']);
    });

    test('a day the calendar has not got, or one a handle runs on from, is nothing', () {
      expect(said('@2026-02-30 @2026-11-06x @2026-13-01'), isEmpty);
    });

    test('today, tomorrow and yesterday left as words are days, never people', () {
      expect(said('@today @Tomorrow @yesterday @todayish'), ['day:today', 'day:Tomorrow', 'day:yesterday', 'person:todayish']);
      expect(mentionsIn('@tomorrow').single.dayOn(friday), '2026-10-31');
    });

    test('nothing in code, an address, a redaction or maths; a link’s own words are words', () {
      expect(said('`@code` [@title](https://x.y/@path) <https://x.y/@z> @@hidden @sam@@ \$@x\$ @real'), ['person:title', 'person:real']);
    });

    test('counted from the offset given', () {
      expect(mentionsIn('hi @sam', 10).single.from, 13);
    });
  });

  group('a note\'s mentions', () {
    test('line by line, not in the front matter or a fence', () {
      const body = '---\nowner: @fm\n---\n# Plan @ana\n```\n@code\n```\nThen @sam @2026-11-06';
      final found = mentionsInBody(body);
      expect([for (final m in found) '${m.line}:${m.mention.value}'], ['4:ana', '8:sam', '8:2026-11-06']);
      expect(found.last.text, 'Then @sam @2026-11-06');
    });

    test('a person beside a day, either side, nothing but spaces between', () {
      const line = '@sam @2026-11-06 and @2026-11-07 for @ana, @2026-11-08 @bo';
      final found = mentionsIn(line);
      Mention day(String iso) => found.firstWhere((m) => m.value == iso);
      expect(personBeside(line, found, day('2026-11-06'))?.value, 'sam');
      expect(personBeside(line, found, day('2026-11-07')), isNull, reason: '"for" is between');
      expect(personBeside(line, found, day('2026-11-08'))?.value, 'bo');
    });

    test('round-trips: reading a note never changes it, and every mention is its own words', () {
      const body = '# Launch\n\n- [ ] Ship @sam @2026-11-06\nAsk @ana by @2026-11-03.\n';
      for (final found in mentionsInBody(body)) {
        final line = body.split('\n')[found.line - 1];
        expect(line.substring(found.mention.from, found.mention.to), '@${found.mention.value}');
      }
      expect(mentionsInBody(body), hasLength(4));
    });
  });

  group('a day signed with its writer (MARKDOWN_FIRST §11, decision 18)', () {
    test('a bare day in a team’s note takes the writer’s handle before it; a person named before it is left as theirs', () {
      expect(signedDay('2026-11-06', owner: 'matt'), '@matt @2026-11-06');
      expect(signedDay('2026-11-06', owner: 'matt', before: 'Ask @sam '), '@2026-11-06');
      expect(signedDay('2026-11-06', owner: 'matt', before: 'Ask @sam, by '), '@matt @2026-11-06', reason: 'a comma: the day is not beside the person');
      expect(signedDay('2026-11-06', owner: 'matt', before: 'By @2026-11-05 and '), '@matt @2026-11-06', reason: 'a day before it is no person');
      expect(signedDay('2026-11-06'), '@2026-11-06', reason: 'a note of the person’s own keeps the bare day');
      expect(signedDay('2026-11-06', owner: ''), '@2026-11-06');
      expect(personEnds('Ask @sam '), isTrue);
      expect(personEnds('Ask @sam'), isTrue);
      expect(personEnds('Ask @sam. '), isFalse);
      expect(personEnds('Ask `@sam` '), isFalse);
      expect(personEnds(''), isFalse);
    });
  });

  group('days typed as words, on Friday 30 October 2026', () {
    final cases = <String, String?>{
      'today': '2026-10-30',
      'tomorrow': '2026-10-31',
      'tmrw': '2026-10-31',
      'yesterday': '2026-10-29',
      'friday': '2026-11-06',
      'fri': '2026-11-06',
      'monday': '2026-11-02',
      'this friday': '2026-10-30',
      'this sunday': '2026-11-01',
      'next friday': '2026-11-06',
      'next monday': '2026-11-02',
      'next week': '2026-11-02',
      'next month': '2026-11-01',
      'in 3 days': '2026-11-02',
      'in 2 weeks': '2026-11-13',
      'nov 6': '2026-11-06',
      '6 november': '2026-11-06',
      'november 6th': '2026-11-06',
      'oct 1': '2027-10-01',
      '2026-11-03': '2026-11-03',
      'sam': null,
      'next sam': null,
      'feb 30': null,
      'in many days': null,
    };
    for (final MapEntry(key: words, value: day) in cases.entries) {
      test('"$words" is ${day ?? 'no day'}', () => expect(dayOfWords(words, friday), day));
    }

    test('next friday on a Monday is the Friday of the week after', () {
      expect(dayOfWords('next friday', DateTime(2026, 10, 26)), '2026-11-06');
    });

    test('the words after an at sign that could be a day', () {
      expect(dayWordsBefore('ask @next friday', 16), (from: 4, words: 'next friday'));
      expect(dayWordsBefore('ask@x', 5), isNull, reason: 'not where a mention opens');
      expect(dayWordsBefore('see @one two three four', 23), isNull, reason: 'four words is not a day');
    });
  });

  group('a day as a chip says it', () {
    test('Today, Tomorrow, the weekday within a week, else the month and day, and the year when not this one', () {
      expect(dayShown('2026-10-30', friday), 'Today');
      expect(dayShown('2026-10-31', friday), 'Tomorrow');
      expect(dayShown('2026-10-29', friday), 'Yesterday');
      expect(dayShown('2026-11-03', friday), 'Tuesday');
      expect(dayShown('2026-10-26', friday), 'Last Monday');
      expect(dayShown('2026-12-01', friday), 'Dec 1');
      expect(dayShown('2027-01-04', friday), 'Jan 4, 2027');
    });

    test('a day before today has passed; today has not', () {
      expect(dayPast('2026-10-29', friday), isTrue);
      expect(dayPast('2026-10-30', friday), isFalse);
      expect(dayPast('2026-11-06', friday), isFalse);
    });
  });
}
