import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/panes/marks.g.dart' as sheet;

/// `academy/lessons.test.ts`, case for case, and then the page's own answers: fixtures/web_lessons.json is what the
/// web app's lessons.ts said on its running page (its words, and every lesson's check over every lesson's example
/// and every text the web's tests try), which the last group holds the Dart to.
void main() {
  final web = jsonDecode(File('test/academy/fixtures/web_lessons.json').readAsStringSync()) as Map<String, dynamic>;

  bool passes(String id, String text) => lessons.firstWhere((one) => one.id == id, orElse: () => throw StateError('no lesson $id')).passes(text);

  late Registry registry;
  setUp(() {
    useStored(MemoryStored());
    usePlugins(registry = createRegistry(const [marksPlugin], store: MemorySwitches()));
  });

  group('Ghost.md Academy’s lessons', () {
    test('teaches every lesson with an example that passes its own check', () {
      for (final lesson in lessons) {
        expect(lesson.passes(lesson.example), isTrue, reason: '${lesson.id}: its own example');
      }
    });

    test('has a lesson for every part of a mark: what it is, what to type, what to do, and a way out', () {
      for (final lesson in lessons) {
        expect(lesson.title, isNotEmpty, reason: lesson.id);
        expect(lesson.symbol, isNotEmpty, reason: lesson.id);
        expect(lesson.teach.length, greaterThan(30), reason: lesson.id);
        expect(lesson.task, isNotEmpty, reason: lesson.id);
        expect(lesson.hint, isNotEmpty, reason: lesson.id);
        expect(lesson.praise, isNotEmpty, reason: lesson.id);
        expect(chapters, contains(lesson.chapter));
      }
      expect({for (final lesson in lessons) lesson.id}.length, lessons.length);
      expect(chapters.expand((chapter) => lessonsIn(chapter)).length, lessons.length);
    });

    test('teaches each chapter in one run, in the order the chapters are named', () {
      final order = [for (final lesson in lessons) chapters.indexOf(lesson.chapter)];
      expect(order, [...order]..sort());
      for (final chapter in chapters) {
        expect(lessonsIn(chapter), isNotEmpty, reason: chapter);
      }
    });

    test('passes words of a person’s own, not only the example', () {
      expect(passes('title', '# Camping in June'), isTrue);
      expect(passes('heading', 'notes\n\n## What to pack'), isTrue);
      // The lesson offers ### as well as ##, so it has to take it (Matt: "the lesson isn't passed").
      expect(passes('heading', '### Friday'), isTrue);
      expect(passes('heading', '#### Friday morning'), isTrue);
      expect(passes('bold', 'bring the **big tent**'), isTrue);
      expect(passes('italic', 'the _small_ one leaks'), isTrue);
      // Stars lean words over too, and the page below shows it, so the lesson takes them.
      expect(passes('italic', 'the *small* one leaks'), isTrue);
      expect(passes('both', 'it is ***here***'), isTrue);
      expect(passes('struck', '~~Thursday~~ Friday'), isTrue);
      expect(passes('code', 'type `ls` to look'), isTrue);
      expect(passes('link', 'see [the map](https://maps.example.com/x)'), isTrue);
      expect(passes('list', '- tent\n- stove'), isTrue);
      expect(passes('number', '1) Pack\n2) Go'), isTrue);
      expect(passes('todo', '- [ ] ring the site'), isTrue);
      expect(passes('quote', '> no dogs in July'), isTrue);
      expect(passes('rule', 'before\n\n***\n\nafter'), isTrue);
      expect(passes('fence', '```\nkeep this\n```'), isTrue);
      expect(passes('table', '| Day | Where |\n| --- | --- |\n| Fri | Cabin |'), isTrue);
      expect(passes('picture', '![the view](image/lake.jpg)'), isTrue);
      expect(passes('raised', 'E = mc^2^'), isTrue);
      expect(passes('lowered', 'CO~2~ levels'), isTrue);
      expect(passes('footnote', 'the lake is cold[^1]\n\n[^1]: In June, anyway.'), isTrue);
      expect(passes('definition', 'Kayak\n: a boat for one'), isTrue);
      expect(passes('maths', r'area is $\pi r^2$'), isTrue);
      expect(passes('emoji', 'on the way :rocket:'), isTrue);
      expect(passes('callout', '> [!WARNING]\n> The road floods.'), isTrue);
      expect(passes('diagram', '```mermaid\nflowchart LR\n  Home --> Lake\n```'), isTrue);
      expect(passes('tag', 'swim at dawn #lake'), isTrue);
      expect(passes('choice', 'Dinner?\n- (x) Pasta\n- ( ) Fish'), isTrue);
      expect(passes('counter', '- Lengths [2/10]'), isTrue);
      expect(passes('sum', '= 12 * 4'), isTrue);
      expect(passes('hiddenLine', '>| the gate code is 4411'), isTrue);
      expect(passes('progress', '# Trip\n- [ ] Pack'), isTrue);
      expect(passes('comment', 'the lake is cold[^c9]\n\n```comments\nc9 sam 2026-10-05T09:00:00Z\nIn June?\n```'), isTrue);
      expect(passes('wiki', 'see [[Packing list]]'), isTrue);
      expect(passes('anchor', '- Book the kayak ^kayak'), isTrue);
      expect(passes('itemRef', 'after [[#^kayak]]'), isTrue);
      expect(passes('bookmark', 'start reading here §§'), isTrue);
      expect(passes('board', '```board\nLater: kayak\n```'), isTrue);
      expect(passes('ticket', '---\nTYPE: Ticket\nstatus: Doing\n---\nKayak trip'), isTrue);
      expect(passes('spoiler', 'it was ||Sam|| all along'), isTrue);
      expect(passes('highlight', 'the ==gate code=='), isTrue);
      expect(passes('tint', 'the ==gate code==(amber)'), isTrue);
      expect(passes('aside', 'swim %%if warm%%'), isTrue);
      expect(passes('unsure', 'about ??six miles??'), isTrue);
      expect(passes('markNote', 'about ??six miles??(from the map)'), isTrue);
      expect(passes('redact', 'the gate code is @@4417@@'), isTrue);
      expect(passes('shout', '^^do not^^ feed the ducks'), isTrue);
      expect(passes('added', 'bring ++a towel++'), isTrue);
      expect(passes('heat', '🔥🔥a hot day🔥🔥'), isTrue);
      expect(passes('frost', '❄️❄️cold water❄️❄️'), isTrue);
      expect(passes('wave', '🌊🌊rough today🌊🌊'), isTrue);
      expect(passes('shimmer', '✨✨the lake at night✨✨'), isTrue);
      expect(passes('haunt', '👻👻the old boathouse👻👻'), isTrue);
    });

    test('is not passed by the words alone, or by another mark', () {
      expect(passes('title', 'Weekend trip'), isFalse);
      // A title is not a heading: the lesson wants its own mark.
      expect(passes('heading', '# Weekend trip'), isFalse);
      expect(passes('bold', '*one star*'), isFalse);
      expect(passes('italic', 'snake_case_words'), isFalse);
      // Bold is two stars, and is its own lesson.
      expect(passes('italic', '**Friday at noon**'), isFalse);
      expect(passes('both', '**Friday at noon**'), isFalse);
      expect(passes('struck', '~one squiggle~'), isFalse);
      expect(passes('code', 'no backticks here'), isFalse);
      expect(passes('link', '[words] (https://example.com)'), isFalse);
      expect(passes('list', 'milk and bread'), isFalse);
      expect(passes('number', '2026 was the year'), isFalse);
      expect(passes('todo', '- ring the site'), isFalse);
      expect(passes('quote', 'she said no dogs'), isFalse);
      expect(passes('rule', '- -'), isFalse);
      // One fence is a block that never closes.
      expect(passes('fence', '```js\nconst x = 1;'), isFalse);
      expect(passes('table', '| just | pipes |'), isFalse);
      expect(passes('picture', '[the view](image/lake.jpg)'), isFalse);
      expect(passes('raised', 'x^2 with no end'), isFalse);
      // Two squiggles cross words out; one lowers them.
      expect(passes('lowered', '~~struck~~'), isFalse);
      // A mark that says nothing is a typo, not a footnote.
      expect(passes('footnote', 'the lake is cold[^1]'), isFalse);
      expect(passes('definition', ': a colon on its own'), isFalse);
      expect(passes('maths', r'it costs $450'), isFalse);
      expect(passes('emoji', 'a :not-a-name-we-know: here'), isFalse);
      expect(passes('callout', '> an ordinary quote'), isFalse);
      expect(passes('diagram', '```js\nconst x = 1;\n```'), isFalse);
      expect(passes('tag', '# Weekend trip'), isFalse);
      expect(passes('choice', '- [ ] a to-do, not a choice'), isFalse);
      expect(passes('counter', 'three of 3/8'), isFalse);
      expect(passes('sum', '450 + 120'), isFalse);
      expect(passes('hiddenLine', '> an ordinary quote'), isFalse);
      expect(passes('progress', '## Packing\n- tent'), isFalse);
      // A comment's mark with no thread for it is a footnote's marker, and a thread with no mark is nowhere in the words.
      expect(passes('comment', 'the lake is cold[^c9]'), isFalse);
      expect(passes('comment', 'the lake is cold\n\n```comments\nc9 sam 2026-10-05T09:00:00Z\nIn June?\n```'), isFalse);
      // A place in this note is not another note.
      expect(passes('wiki', 'after [[#^kayak]]'), isFalse);
      expect(passes('anchor', '- Book the kayak'), isFalse);
      expect(passes('itemRef', 'see [[Packing list]]'), isFalse);
      expect(passes('bookmark', 'one section sign §'), isFalse);
      expect(passes('board', '```\nLater: kayak\n```'), isFalse);
      // A ticket with no status yet, and the line anywhere but the front matter, are not the lesson's.
      expect(passes('ticket', '---\ntype: ticket\n---\nKayak trip'), isFalse);
      expect(passes('ticket', 'Kayak trip\n\ntype: ticket\nstatus: To do'), isFalse);
      expect(passes('spoiler', 'a |single| bar'), isFalse);
      expect(passes('highlight', 'a =single= sign'), isFalse);
      expect(passes('tint', 'a ==plain== highlight'), isFalse);
      expect(passes('aside', 'fifty %'), isFalse);
      expect(passes('unsure', 'really?'), isFalse);
      // A color is not a note, and a mark with nothing after it is not one either.
      expect(passes('markNote', 'the ==gate code==(amber)'), isFalse);
      expect(passes('markNote', 'about ??six miles??'), isFalse);
      // One at sign is an address, and a bar needs its other end.
      expect(passes('redact', 'write to sam@ortiz.example'), isFalse);
      expect(passes('redact', 'the gate code is @@4417'), isFalse);
      // One caret either side raises; two shout.
      expect(passes('shout', 'the 2^nd^ of June'), isFalse);
      expect(passes('added', '1 + 1'), isFalse);
      // One emoji is a word, and three are three.
      expect(passes('heat', '🔥a fire🔥'), isFalse);
      expect(passes('heat', '🔥🔥🔥a fire🔥🔥🔥'), isFalse);
      expect(passes('frost', '❄️cold❄️'), isFalse);
      expect(passes('wave', '🌊sea🌊'), isFalse);
      expect(passes('shimmer', '✨one✨'), isFalse);
      expect(passes('haunt', '👻boo👻'), isFalse);
    });

    test('goes further with boards and queries: a height, a key, where, show, group and total', () {
      expect(passes('boardHeight', '```board\nTo do: a\n```'), isFalse);
      expect(passes('boardHeight', '```board height=20\nTo do: a\n```'), isTrue);
      expect(passes('notebookKey', '---\nbook: true\n---\n# Glyph'), isFalse);
      expect(passes('notebookKey', '---\nkey: GLY\n---\n# Not a notebook'), isFalse);
      expect(passes('notebookKey', '---\ntitle: Work\nbook: true\nkey: WRK\n---\n# Work'), isTrue);
      expect(passes('queryWhere', '```query\nfrom: tasks\n```'), isFalse);
      expect(passes('queryWhere', '```query\nfrom: tasks\nwhere: due < today\n```'), isTrue);
      // A line the query cannot read is not yet a where.
      expect(passes('queryWhere', '```query\nfrom: tasks\nwher: due < today\n```'), isFalse);
      expect(passes('queryShow', '```query\nfrom: tasks\nshow: list\n```'), isFalse);
      expect(passes('queryShow', '```query\nfrom: tickets\nshow: gantt\n```'), isTrue);
      expect(passes('queryGroup', '```query\nfrom: tickets\n```'), isFalse);
      expect(passes('queryGroup', '```query\nfrom: tickets\ngroup: status\n```'), isTrue);
      expect(passes('queryGroup', '```query\nfrom: tickets\ntotal: estimate\n```'), isTrue);
    });

    test('says what every chapter is about', () {
      for (final chapter in chapters) {
        expect(chapterAbout[chapter]!.length, greaterThan(20), reason: chapter);
      }
    });

    test('leaves standard Markdown out for a person who knows it, and only that', () {
      final skipping = lessonsNow(true);
      expect(skipping.any((lesson) => lesson.standard), isFalse);
      expect(lessonsIn('Markdown basics', skipping), isEmpty);
      // Every Markdown basics lesson is standard; the marks only Ghost.md draws are still taught.
      expect(lessonsIn('Markdown basics').every((lesson) => lesson.standard), isTrue);
      expect([for (final lesson in skipping) lesson.id], containsAll(['callout', 'diagram', 'board', 'query', 'tag']));
      expect(skipping.length + lessons.where((lesson) => lesson.standard).length, lessons.length);
      expect(readSkipStandard(), isFalse);
      writeSkipStandard(true);
      expect(readSkipStandard(), isTrue);
      stored.setItem('glyph-academy-skip-standard', 'not json');
      expect(readSkipStandard(), isFalse);
    });

    test('knows a to-do the way the note does: a box after any marker, with a space after it (core/itemSyntax.ts)', () {
      expect(passes('todo', '1. [ ] ring the site'), isTrue);
      expect(passes('todo', '* [x] rang the site'), isTrue);
      // Brackets against the words draw no box in a note, so there is nothing to tap: not a to-do yet.
      expect(passes('todo', '- [ ]ring the site'), isFalse);
    });

    test('keeps what has been learned, and shrugs off a store it cannot read', () {
      writeProgress({'title', 'bold'});
      expect(readProgress(), {'title', 'bold'});
      // As the page writes it: a JSON list under the page's own key.
      expect(jsonDecode(stored.readText('glyph-academy')!), ['title', 'bold']);
      stored.setItem('glyph-academy', 'not json');
      expect(readProgress(), isEmpty);
      stored.removeItem('glyph-academy');
      expect(readProgress(), isEmpty);
    });
  });

  group('the Academy and the cheat sheet', () {
    // The cheat sheet's rows: Flutter's own (lib/settings/panes/marks.g.dart, every plugin on), and with the Marks
    // plugin off the rows the page's `markGroups()` then gave, since Flutter's sheet is not read from the registry yet.
    List<({String name, String symbol})> rows() => registry.isEnabled('marks')
        ? [for (final group in sheet.markGroups) for (final row in group.rows) (name: row.name, symbol: row.symbol)]
        : [for (final row in (web['rowsOff'] as List).cast<Map<String, dynamic>>()) (name: row['name'] as String, symbol: row['symbol'] as String)];

    test('teaches every mark the cheat sheet lists, each in exactly one lesson', () {
      final taught = [for (final lesson in lessons) ...lesson.rows];
      for (final row in rows()) {
        expect(taught.where((name) => name == row.name), hasLength(1), reason: row.name);
      }
      // And no lesson teaches a row the cheat sheet does not have.
      final names = {for (final row in rows()) row.name};
      for (final name in taught) {
        expect(names, contains(name));
      }
    });

    test('writes each lesson’s mark as the cheat sheet writes it', () {
      // A lesson that goes further with another's mark (a board's height, a query's where:) has no row of its own.
      for (final lesson in lessons.where((one) => one.rows.isNotEmpty)) {
        final row = rows().where((one) => one.name == lesson.rows[0]).firstOrNull;
        expect(row?.symbol, lesson.symbol, reason: lesson.id);
      }
    });

    test('has a lesson for each of the Marks plugin’s marks, the five effects among them', () {
      for (final mark in marks) {
        final lesson = lessons.where((one) => one.rows.contains(mark.name)).firstOrNull;
        expect(lesson?.symbol, mark.delimiter, reason: mark.name);
        expect(lesson?.needs, mark.name, reason: mark.name);
      }
    });

    test('offers a plugin’s lessons only while its marks are switched on, as the cheat sheet shows them', () {
      expect(lessonsNow(), hasLength(lessons.length));
      registry.setEnabled('marks', false);
      final now = lessonsNow();
      expect(now.every((lesson) => lesson.needs == null), isTrue);
      expect([for (final lesson in now) lesson.id], isNot(contains('hiddenLine')));
      expect([for (final lesson in now) lesson.id], contains('board'));
      // The two agree with the plugin off as well: every row still shown is still taught.
      final taught = [for (final lesson in now) ...lesson.rows];
      for (final row in rows()) {
        expect(taught, contains(row.name), reason: row.name);
      }
      expect(lessonsIn('Marks and effects', now), isEmpty);
    });
  });

  group('the lessons against the page’s own (fixtures/web_lessons.json)', () {
    final theirs = (web['lessons'] as List).cast<Map<String, dynamic>>();

    test('has the page’s chapters and what each is about, word for word', () {
      expect(chapters, web['chapters']);
      expect(chapters, hasLength(7));
      expect(chapterAbout, web['about']);
    });

    test('has every lesson the page has, in its order, word for word', () {
      expect(lessons, hasLength(61));
      expect([for (final lesson in lessons) lesson.id], [for (final lesson in theirs) lesson['id']]);
      for (final (at, lesson) in lessons.indexed) {
        final one = theirs[at];
        expect(
          {'chapter': lesson.chapter, 'symbol': lesson.symbol, 'rows': lesson.rows, 'standard': lesson.standard, 'needs': lesson.needs, 'title': lesson.title, 'teach': lesson.teach, 'example': lesson.example, 'task': lesson.task, 'praise': lesson.praise, 'hint': lesson.hint},
          // The app is "Ghost" in the Academy's words now (Matt, 2026-10-28), where the page still says Ghost.md.
          {for (final key in const ['chapter', 'symbol', 'rows', 'standard', 'needs', 'title', 'teach', 'example', 'task', 'praise', 'hint']) key: one[key] is String ? (one[key] as String).replaceAll('Ghost.md', 'Ghost') : one[key]},
          reason: lesson.id,
        );
      }
    });

    test('offers the lessons the page offers, with the Marks plugin on and off', () {
      expect([for (final lesson in lessonsNow()) lesson.id], web['nowOn']);
      registry.setEnabled('marks', false);
      expect([for (final lesson in lessonsNow()) lesson.id], web['nowOff']);
    });

    test('lists the rows the page’s cheat sheet lists with every plugin on', () {
      expect([for (final group in sheet.markGroups) for (final row in group.rows) {'name': row.name, 'symbol': row.symbol}], web['rows']);
    });

    /// Every lesson's check over every text, as a line of 1s and 0s in the lessons' order.
    List<String> answers(List<String> corpus) => [for (final text in corpus) lessons.map((lesson) => lesson.passes(text) ? '1' : '0').join()];

    /// The texts where the two disagree, each with the lessons that do.
    List<String> differing(List<String> corpus, List<String> ours, List<String> page) => [
      for (final (at, text) in corpus.indexed)
        if (ours[at] != page[at]) '${jsonEncode(text)}: ${[for (final (n, lesson) in lessons.indexed) if (ours[at][n] != page[at][n]) '${lesson.id} is ${ours[at][n]}, the page ${page[at][n]}'].join('; ')}',
    ];

    test('answers every check as the page answers it, for every lesson’s example and every text the web’s tests try', () {
      final corpus = (web['corpus'] as List).cast<String>();
      expect(corpus.length, greaterThan(170));
      expect(differing(corpus, answers(corpus), (web['answers'] as List).cast<String>()), isEmpty);
    });

    test('answers them as the page does with the Marks plugin off too', () {
      final corpus = (web['corpus'] as List).cast<String>();
      registry.setEnabled('marks', false);
      expect(differing(corpus, answers(corpus), (web['answersOff'] as List).cast<String>()), isEmpty);
    });
  });
}
