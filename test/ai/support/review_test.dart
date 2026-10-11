// A port of src/app/review/review.test.ts, case for case.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/support/review_diff.dart';
import 'package:ghost_md/ai/support/review_findings.dart';
import 'package:ghost_md/ai/support/review_prompt.dart';

void main() {
  group('where the two speech models disagree', () {
    test('finds the runs, ignoring case and punctuation, with context to place them', () {
      final changes = wordChanges('Hey Ghost add a list item to the hello trade. Fix the seat bar.', 'Hey Ghost, add a list item to the HelloTrade. Fix the seek bar.');
      expect(changes.map((c) => [c.heard, c.careful]).toList(), [
        ['hello trade.', 'HelloTrade.'],
        ['seat', 'seek'],
      ]);
      expect(changes[1].before, 'trade. Fix the');
      expect(changes[1].after, 'bar.');
    });

    test('sees words one of them missed', () {
      expect(wordChanges('call Sam today', 'call Sam about the cabin today').map((c) => [c.heard, c.careful]).toList(), [
        ['', 'about the cabin'],
      ]);
      expect(wordChanges('same words here', 'Same words, here!'), isEmpty);
    });
  });

  group('the reviewing model’s findings', () {
    const self = NoteText(id: 'n', title: 'Bug bash', body: '# Bug bash\n\n- [ ] Fix the seat bar\n- [ ] Downloads stuck\n');
    const other = NoteText(id: 'h', title: 'HelloTrade', body: '# HelloTrade\n\n- Ship the APK\n');

    test('digs the array out of a fenced or chatty answer', () {
      expect(readArray('Here you go:\n```json\n[{"a": 1},]\n```'), [
        {'a': 1},
      ]);
      expect(readArray('No problems found.'), isEmpty);
    });

    test('keeps findings that quote real text, and drops invented ones', () {
      final answer = jsonEncode([
        {'check': 'words', 'what': 'Seek, not seat', 'why': 'The slower model heard seek.', 'find': 'Fix the seat bar', 'replace': 'Fix the seek bar'},
        {'check': 'words', 'what': 'Invented', 'why': 'Not in the note.', 'find': 'Fix the login', 'replace': 'Fix the logout'},
        {'check': 'commands', 'what': 'Item went here', 'why': 'It was for HelloTrade.', 'note': 'hello trade', 'add': '- Update the readme'},
        {'check': 'style', 'what': 'Nope', 'why': '', 'find': 'Bug bash', 'replace': 'Bugbash'},
        {'check': 'names', 'what': 'Same', 'why': '', 'find': 'Downloads stuck', 'replace': 'Downloads stuck'},
      ]);
      final findings = readFindings(answer, self, [other]);
      expect(findings.map((f) => [f.check.name, f.noteTitle, f.change.kind]).toList(), [
        ['words', 'Bug bash', 'replace'],
        ['commands', 'HelloTrade', 'add'],
      ]);
    });

    test('changes the words just said when a note has them twice', () {
      const twice = NoteText(id: 'n', title: 'Bug bash', body: 'Fix the seat bar.\n\nFix the seat bar.\n');
      final findings = readFindings(
        jsonEncode([
          {'check': 'words', 'what': 'Seek', 'why': '', 'find': 'seat bar', 'replace': 'seek bar'},
        ]),
        twice,
        [],
      );
      expect(applyFindings([twice], findings)['n'], 'Fix the seat bar.\n\nFix the seek bar.\n');
    });

    test('forgives whitespace and case when finding the text', () {
      expect(locate('Fix  the Seat bar', 'fix the seat bar'), 'Fix  the Seat bar');
    });

    test('applies accepted findings to the notes they name', () {
      final findings = readFindings(
        jsonEncode([
          {'check': 'words', 'what': 'Seek', 'why': '', 'find': 'seat bar', 'replace': 'seek bar'},
          {'check': 'commands', 'what': 'Readme', 'why': '', 'note': 'HelloTrade', 'add': '- Update the readme'},
        ]),
        self,
        [other],
      );
      final changed = applyFindings([self, other], findings);
      expect(changed['n'], contains('- [ ] Fix the seek bar'));
      expect(changed['h'], '# HelloTrade\n\n- Ship the APK\n- Update the readme\n');
    });

    test('adds a starred or numbered to-do by its words, as a dashed one is (core/itemSyntax.ts)', () {
      // The box after `*` used to be read as words, and the list's own box went in front of it: `- [ ] [ ] Update…`.
      final findings = readFindings(
        jsonEncode([
          {'check': 'commands', 'what': 'Readme', 'why': '', 'add': '* [ ] Update the readme'},
          {'check': 'commands', 'what': 'Docs', 'why': '', 'add': '2. [ ] Write the docs'},
        ]),
        self,
        [],
      );
      expect(applyFindings([self], findings)['n'], '# Bug bash\n\n- [ ] Fix the seat bar\n- [ ] Downloads stuck\n- [ ] Update the readme\n- [ ] Write the docs\n');
    });

    test('keeps a choice’s round box on the line it adds, where a to-do’s box is left to the list', () {
      final bullets = self.copyWith(body: '# Bug bash\n\n- Fix\n');
      final findings = readFindings(
        jsonEncode([
          {'check': 'commands', 'what': 'Pick', 'why': '', 'add': '- ( ) Pick me'},
          {'check': 'commands', 'what': 'Picked', 'why': '', 'add': '* (x) Picked'},
        ]),
        bullets,
        [],
      );
      expect(applyFindings([bullets], findings)['n'], '# Bug bash\n\n- Fix\n- ( ) Pick me\n- (x) Picked\n');
    });
  });

  group('what the reviewing model is shown', () {
    test('labels every piece and puts the note last', () {
      final message = reviewMessage(
        const ReviewInput(
          title: 'Bug bash',
          body: '# Bug bash',
          heard: 'fix the seat bar',
          careful: 'fix the seek bar',
          changes: [WordChange(heard: 'seat', careful: 'seek', before: 'fix the', after: 'bar')],
          commands: ['Added “Fix the seek bar” to HelloTrade’s list'],
          titles: ['HelloTrade', 'Bug bash'],
          touched: [],
        ),
      );
      expect(message, startsWith('WHAT THE FAST SPEECH MODEL HEARD:'));
      expect(message, contains('- …fix the [seat → seek] bar…'));
      expect(message.trim().endsWith('# Bug bash'), isTrue);
    });

    test('says when the two models agree, and when nothing ran or nothing else was heard', () {
      final message = reviewMessage(
        const ReviewInput(title: 'Plain', body: '# Plain', heard: '  ', careful: 'plain words', changes: [], commands: [], titles: [], touched: [(title: 'Groceries', body: '- Milk\n')]),
      );
      expect(message, contains('WHAT THE FAST SPEECH MODEL HEARD:\n(nothing)'));
      expect(message, contains('WHERE THEY DISAGREE: nowhere.'));
      expect(message, contains('COMMANDS THAT RAN:\n(none)'));
      expect(message, contains("THE PERSON'S NOTE TITLES:\n(none)"));
      expect(message, contains('OTHER NOTE A COMMAND CHANGED, "Groceries":\n- Milk'));
      // With no second listen there is nothing to compare, and nothing is said about it.
      final once = reviewMessage(const ReviewInput(title: 'Plain', body: '# Plain', heard: 'words', careful: null, changes: [], commands: [], titles: [], touched: []));
      expect(once, isNot(contains('SLOWER')));
      expect(once, isNot(contains('DISAGREE')));
    });
  });

  group('how long the reviewing model may take', () {
    test('lets a bigger model think less, gives the answer room by the note’s length, and caps the whole', () {
      expect(reviewBudget('qwen3-9b', 0), (think: 500, total: 1000));
      expect(reviewBudget('gemma-2b', 1200), (think: 600, total: 1200));
      expect(reviewBudget('qwen3-4b', 12000), (think: 700, total: 1900));
    });
  });

  // Not in the web's file: the prompt is copied byte for byte, and this holds it to the web's own file where the
  // web app is checked out beside this one (and to its length where it is not).
  group('the prompt, beside the web’s cases', () {
    test('is the web’s REVIEW_PROMPT', () {
      expect(reviewPrompt.length, 2199);
      expect(reviewPrompt, startsWith('You check a voice note that a fast pipeline just wrote, inside Ghost.md, a notes app.'));
      expect(reviewPrompt, endsWith('No finding for style. If everything is right, answer [].'));
      final web = File('../glyph/src/app/review/prompt.ts');
      if (!web.existsSync()) return;
      final source = web.readAsStringSync();
      const open = 'export const REVIEW_PROMPT = String.raw`';
      final from = source.indexOf(open) + open.length;
      expect(reviewPrompt, source.substring(from, source.indexOf('`;', from)));
    });
  });
}
