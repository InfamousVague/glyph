// The summary section (docs/DESIGN.md §127 section 2): its shape and what a model's looser answer is read as, how it
// is found again by that shape or closed by the kept text, where a fresh one goes, how a remake treats the one
// there, and the pieces a long transcript is cut into. A port of `src/app/ai/summaryText.test.ts`, case for case,
// through the AI's own path to the module (lib/ai/summary_text.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_text.dart';

final String section = [
  '## Summary',
  'What the call settled about the March launch.',
  '',
  '- Launch moves to the second week of March.',
  '- Decided: no paid ads until the beta closes.',
  '',
  '- [ ] Send Sam the press list by Friday.',
  '- [ ] Book the venue before the 10th.',
].join('\n');

void main() {
  group('the shape', () {
    test('takes the heading for the title, keeps one prose line and only item lines, and drops the rest', () {
      final model = [
        '# Planning call with Sam',
        'What the call settled about the March launch.',
        'Sam sounded tired.',
        '',
        '- Launch moves to the second week of March.',
        '* Decided: no paid ads until the beta closes.',
        '',
        '',
        '- [ ] Send Sam the press list by Friday.',
        '- [ ] Book the venue before the 10th.',
        '',
        'Let me know if you need more.',
      ].join('\n');
      expect(shapeSummary(model), ShapedSummary(title: 'Planning call with Sam', section: section));
    });

    test('never writes the model’s echoed heading, a rule or a code fence into the section', () {
      expect(shapeSummary('```markdown\n## Summary\nTwo errands.\n---\n- [ ] Milk.\n```'), const ShapedSummary(title: null, section: '## Summary\nTwo errands.\n\n- [ ] Milk.'));
      expect(shapeSummary(''), const ShapedSummary(title: null, section: ''));
      expect(shapeSummary('# Only a name'), const ShapedSummary(title: 'Only a name', section: ''));
    });

    test('reads a label or an introduction on the prose line as not the prose, so the sentence after it is taken', () {
      const rest = '\n\n- Launch moves to March.\n\n- [ ] Book the venue.';
      const wanted = '## Summary\nWhat the call settled.$rest';
      expect(shapeSummary('# Planning call\n**Summary**\nWhat the call settled.$rest'), const ShapedSummary(title: 'Planning call', section: wanted));
      expect(shapeSummary('# Planning call\nSummary:\nWhat the call settled.$rest').section, wanted);
      expect(shapeSummary('# Planning call\nHere is the summary:\nWhat the call settled.$rest').section, wanted);
      expect(shapeSummary('# Planning call\n**Summary:** What the call settled.$rest').section, wanted);
      expect(shapeSummary('# Planning call\n**Summary**: What the call settled.$rest').section, wanted);
      // A label alone with nothing after it leaves no empty prose line behind, and never two blanks in a row.
      final bare = shapeSummary('# Planning call\n**Summary**\n\n- Launch moves to March.').section;
      expect(bare, '## Summary\n\n- Launch moves to March.');
      expect(bare, isNot(contains('\n\n\n')));
      expect(summaryLine('# T\n$bare'), isNull);
    });

    test('reads a numbered list, a typographic bullet, a tight box and a bare decision as items', () {
      const model = '# Planning call\nWhat the call settled.\n\n1. Launch moves to March.\n2) Sam: the press list.\n• Site copy still open.\nDecided: no paid ads until the beta closes.\n\n-[ ] Book the venue.\n-[x] Send the list.';
      expect(shapeSummary(model).section,
          '## Summary\nWhat the call settled.\n\n- Launch moves to March.\n- Sam: the press list.\n- Site copy still open.\n- Decided: no paid ads until the beta closes.\n\n- [ ] Book the venue.\n- [x] Send the list.');
    });

    test('joins a sentence wrapped over two lines, and still drops a second sentence', () {
      expect(shapeSummary('# T\nWhat the call settled about\nthe March launch.\n\n- One.').section, '## Summary\nWhat the call settled about the March launch.\n\n- One.');
      expect(shapeSummary('# T\nWhat the call settled.\nSam sounded tired.\n\n- One.').section, '## Summary\nWhat the call settled.\n\n- One.');
      // A blank closes the sentence, however it ended.
      expect(shapeSummary('# T\nWhat the call settled about\n\nthe March launch.\n\n- One.').section, '## Summary\nWhat the call settled about\n\n- One.');
    });

    test('only ever grows as the model streams, so a run’s landed lines never move', () {
      const wholes = [
        '# Planning call\nWhat the call settled.\n- Launch moves.\n- [ ] Send the list.\n',
        '# Planning call\n**Summary**\nWhat the call settled about\nthe launch.\n\n1. Launch moves.\n• Sam: the list.\n\n-[ ] Send the list.\n',
      ];
      for (final whole in wholes) {
        var last = '';
        for (var n = 0; n <= whole.length; n += 1) {
          final shaped = shapeSummary(whole.substring(0, n)).section;
          final lines = shaped.split('\n')..removeLast();
          expect(shaped.startsWith(lines.join('\n')), isTrue);
          // Every finished line of the answer so far is a finished line of the next one.
          final finished = (last.split('\n')..removeLast()).join('\n');
          expect(shaped.startsWith(finished), isTrue, reason: 'at $n');
          last = shaped;
        }
      }
    });
  });

  group('finding the section', () {
    test('is found by its shape, and closed by a paragraph, a heading, a rule, or the transcript', () {
      final paragraphs = '# Planning call\n\n$section\n\nWe started with the launch date.\n\nThen the press.';
      expect(summarySection(paragraphs)?.text, section);
      expect(paragraphs.substring(summarySection(paragraphs)!.start, summarySection(paragraphs)!.end), section);
      expect(summarySection('# T\n$section\n## Transcript\nWords.')?.text, section);
      expect(summarySection('# T\n$section\n\n---\nWords.')?.text, section);
      expect(summarySection('# T\nNo section here.'), isNull);
      // A `## Summary` inside the front matter's lines is not the section; one after it is.
      expect(summarySection('---\ntitle: x\n---\n# T\n## Summary\nA line.')?.text, '## Summary\nA line.');
    });

    test('takes a prose line only straight after the heading, so a dictated paragraph after items is not the section’s', () {
      expect(summarySection('# T\n## Summary\n- One.\n- Two.\n\nA paragraph said later.')?.text, '## Summary\n- One.\n- Two.');
      expect(summarySection('# T\n## Summary\nThe line.\nA second line ends it.')?.text, '## Summary\nThe line.');
    });

    test('is closed by the kept text where the body still reads so, so the person’s own list under it is not read as its', () {
      const list = '- [ ] Task under the title\n- [ ] Another';
      final body = '# Title\n\n$section\n\n$list';
      // By the shape alone the list is the section's; the keep closes it.
      expect(summarySection(body)?.text, '$section\n\n$list');
      expect(summarySection(body, section)?.text, section);
      expect(body.substring(summarySection(body, section)!.start, summarySection(body, section)!.end), section);
      // A box the person ticked does not stop the keep closing it; the text it answers carries the tick.
      final ticked = body.replaceFirst('- [ ] Book the venue before the 10th.', '- [x] Book the venue before the 10th.');
      expect(summarySection(ticked, section)?.text, section.replaceFirst('- [ ] Book the venue before the 10th.', '- [x] Book the venue before the 10th.'));
      // Edited past a tick, or run straight into the list, and the shape is the fallback.
      expect(summarySection(body.replaceFirst('What the call settled', 'My own words'), section)?.text, '${section.replaceFirst('What the call settled', 'My own words')}\n\n$list');
      expect(summarySection('# Title\n\n$section\n$list', section)?.text, '$section\n$list');
      expect(summarySection('# T\nNo section here.', section), isNull);
    });

    test('answers the prose line for the shelf, the toast and the notification', () {
      expect(summaryLine('# T\n\n$section'), 'What the call settled about the March launch.');
      expect(summaryLine('# T\n## Summary\n- Only items.'), isNull);
      expect(summaryLine('# T\nNothing.'), isNull);
    });
  });

  group('its place', () {
    String at(String body) => body.substring(0, summaryPlace(body));

    test('is after the first line of words, whatever its marks, and after the front matter', () {
      expect(at('# Title\n\nWords.'), '# Title\n');
      expect(at('A plain first line\nthat runs on.\n\nMore.'), 'A plain first line\nthat runs on.\n');
      expect(at('- [ ] Call Sam\n- [ ] Book the venue\n\nNotes.'), '- [ ] Call Sam\n- [ ] Book the venue\n');
      expect(at('![](image/a.jpg)\n# Title\nWords.'), '![](image/a.jpg)\n# Title\n');
      expect(at('---\ntitle: x\n---\n# Title\nWords.'), '---\ntitle: x\n---\n# Title\n');
      expect(at('---\ntitle: x\n---\nPlain line.\n\nWords.'), '---\ntitle: x\n---\nPlain line.\n');
      expect(at('---\ntitle: x\n---\n- [ ] Task\nWords.'), '---\ntitle: x\n---\n- [ ] Task\nWords.');
      expect(at('---\ntitle: x\n---\n![](p.png)\n# T\n'), '---\ntitle: x\n---\n![](p.png)\n# T\n');
      expect(summaryPlace('# Title'), '# Title'.length);
      expect(summaryPlace(''), 0);
    });
  });

  group('writing it', () {
    test('writes a fresh section under the title with a blank line either side', () {
      expect(withSummary('# Planning call\n\nWe started with the launch.', section), '# Planning call\n\n$section\n\nWe started with the launch.');
      expect(withSummary('# Planning call\nWe started.', section), '# Planning call\n\n$section\n\nWe started.');
      expect(withSummary('# Planning call', section), '# Planning call\n\n$section');
      expect(withSummary('', '## Summary\nA line.'), '## Summary\nA line.');
    });

    test('puts the model’s heading above the section in a note with no words, which the section would otherwise title', () {
      expect(withSummary('', section, title: 'Planning call'), '# Planning call\n\n$section');
      expect(withSummary('![](image/a.jpg)', section, title: 'Planning call'), '![](image/a.jpg)\n\n# Planning call\n\n$section');
      expect(withSummary('---\nauthor: sam\n---\n', section, title: 'Planning call'), '---\nauthor: sam\n---\n\n# Planning call\n\n$section');
      // A title named in the front matter is a title, and is never written over.
      expect(withSummary('---\ntitle: x\n---\n', section, title: 'Planning call'), '---\ntitle: x\n---\n\n$section');
      expect(withSummary('---\ntitle: Meeting, 26 Sep 14:05\n---\nWords.', '## Summary\nA line.', title: 'Planning call'), '---\ntitle: Meeting, 26 Sep 14:05\n---\nWords.\n\n## Summary\nA line.');
      expect(hasWords(''), isFalse);
      expect(hasWords('![](image/a.jpg)'), isFalse);
      expect(hasWords('# T'), isTrue);
      expect(hasWords('---\ntitle: x\n---\n'), isTrue);
    });

    test('keeps the person’s list under a remade section, since the keep closes the section', () {
      const list = '- [ ] Task under the title\n- [ ] Another';
      final once = withSummary('# Title\n\n$list', section);
      expect(once, '# Title\n\n$section\n\n$list');
      const next = '## Summary\nA newer line.\n\n- [ ] One thing.';
      expect(withSummary(once, next, kept: section), '# Title\n\n$next\n\n$list');
      expect(withoutSummary(once, section), '# Title\n\n$list');
    });

    test('replaces the section it has, whole, and leaves every paragraph after it', () {
      final body = '# Planning call\n\n$section\n\nWe started with the launch.\n\nThen the press.';
      const next = '## Summary\nA newer line.\n\n- [ ] One thing.';
      expect(withSummary(body, next), '# Planning call\n\n$next\n\nWe started with the launch.\n\nThen the press.');
    });

    test('takes the model’s heading as the title only while the note still wears its date title', () {
      const meeting = '# Meeting, 26 Sep 14:05\n\n## Transcript\nWords.';
      expect(withSummary(meeting, '## Summary\nA line.', title: 'Planning call'), '# Planning call\n\n## Summary\nA line.\n\n## Transcript\nWords.');
      expect(withSummary('# Sam’s call\n\nWords.', '## Summary\nA line.', title: 'Planning call'), '# Sam’s call\n\n## Summary\nA line.\n\nWords.');
      expect(dateTitled('# Meeting, Sep 26 09:15'), isTrue);
      expect(dateTitled('Meeting, 26 Sep 14:05\n'), isTrue);
      expect(dateTitled('# Meeting with Sam'), isFalse);
    });

    test('takes the section off for a compare, and the blank that went with it', () {
      final body = '# Planning call\n\n$section\n\nWe started with the launch.';
      expect(withoutSummary(body), '# Planning call\n\nWe started with the launch.');
      expect(withoutSummary('# Planning call\n\n$section'), '# Planning call');
      expect(withoutSummary('# Planning call\n\nWords.'), '# Planning call\n\nWords.');
    });

    test('carries every ticked to-do of the old section into the new one, verbatim, after the new to-dos', () {
      const old = '## Summary\nOld line.\n\n- [x] Send Sam the press list.\n- [ ] Book the venue.\n- [x] Call Jo.';
      const next = '## Summary\nNew line.\n\n- Launch moves.\n\n- [ ] Send the press list to Sam by Friday.\n- [ ] Book the venue before the 10th.';
      expect(carryTicked(old, next), '$next\n- [x] Send Sam the press list.\n- [x] Call Jo.');
      // No to-dos in the new one: the ticked ones make a group of their own at the end.
      expect(carryTicked(old, '## Summary\nNew line.\n\n- Launch moves.'), '## Summary\nNew line.\n\n- Launch moves.\n\n- [x] Send Sam the press list.\n- [x] Call Jo.');
      // A ticked line the model kept word for word is not doubled, and un-ticked old to-dos are not carried.
      expect(carryTicked(old, '## Summary\nNew line.\n\n- [x] Call Jo.'), '## Summary\nNew line.\n\n- [x] Call Jo.\n- [x] Send Sam the press list.');
      expect(carryTicked('## Summary\nOld.\n\n- [ ] Open.', next), next);
      // Nor one it kept with a capital X, or without the full stop.
      expect(carryTicked('## Summary\nOld.\n\n- [x] Call Jo.', '## Summary\nNew.\n\n- [X] Call Jo.'), '## Summary\nNew.\n\n- [X] Call Jo.');
      expect(carryTicked('## Summary\nOld.\n\n- [x] Call Jo', '## Summary\nNew.\n\n- [x] Call Jo.'), '## Summary\nNew.\n\n- [x] Call Jo.');
    });

    test('keeps every paragraph of a dictated note when it is summarised again on purpose', () {
      final note = '# Groceries\n\n$section\n\nWe need oat milk and eggs.\n\nAnd the good coffee.';
      final remade = withSummary(note, '## Summary\nShopping for the week.\n\n- [ ] Oat milk and eggs.');
      expect(remade, '# Groceries\n\n## Summary\nShopping for the week.\n\n- [ ] Oat milk and eggs.\n\nWe need oat milk and eggs.\n\nAnd the good coffee.');
      expect(withoutSummary(remade), '# Groceries\n\nWe need oat milk and eggs.\n\nAnd the good coffee.');
    });
  });

  group('a long recording', () {
    String paragraph(int n) => 'Paragraph $n. ${'Words that were said. ' * 40}'.trim();

    test('goes in one piece up to twenty thousand characters, and in pieces cut at paragraph breaks past that', () {
      final short = [for (var i = 0; i < 10; i += 1) paragraph(i)].join('\n\n');
      expect(transcriptPieces(short), [short]);
      final long = [for (var i = 0; i < 40; i += 1) paragraph(i)].join('\n\n');
      expect(long.length, greaterThan(onePassChars));
      final pieces = transcriptPieces(long);
      expect(pieces.length, greaterThan(1));
      for (final piece in pieces) {
        expect(piece.length, lessThanOrEqualTo(12000));
      }
      // Nothing dropped, nothing cut mid-paragraph.
      expect(pieces.join('\n\n'), long);
      expect(transcriptPieces(''), isEmpty);
    });

    test('cuts a paragraph longer than a piece at sentence ends', () {
      final run = ('A sentence that was said. ' * 1200).trim();
      final pieces = transcriptPieces(run);
      expect(pieces.length, greaterThan(1));
      for (final piece in pieces) {
        expect(piece.length, lessThanOrEqualTo(12000));
        expect(piece.endsWith('.'), isTrue);
      }
      expect(pieces.join(' '), run);
    });
  });
}
