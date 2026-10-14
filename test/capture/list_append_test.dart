import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/list_append.dart';
import 'package:ghost_md/capture/place.dart' show Said, placeTake, placingFor;

/// Spoken items into a note's list (lib/capture/list_append.dart), case for case with the web's
/// `capture/listAppend.test.ts`.
void main() {
  group('adding spoken items to a note’s list', () {
    test('goes on the end of the last list, in its own style', () {
      const body = '# AttackFM\n\nSome thoughts about the app.\n\n- [ ] Fix the login bug\n- [x] Ship 0.6.9\n\nNotes after the list.';
      expect(
        appendToList(body, ['update the readme.']).body,
        '# AttackFM\n\nSome thoughts about the app.\n\n- [ ] Fix the login bug\n- [x] Ship 0.6.9\n- [ ] Update the readme\n\nNotes after the list.',
      );
    });

    test('counts on from a numbered list and keeps its delimiter', () {
      expect(appendToList('Steps\n\n1) Build\n2) Test', ['ship it', 'celebrate']).body, 'Steps\n\n1) Build\n2) Test\n3) Ship it\n4) Celebrate');
    });

    test('uses the list’s own bullet and indent, after an item’s continuation lines', () {
      const body = '- One\n  more about one\n* Two\n  - child\n\nEnd.';
      expect(appendToList(body, ['three']).body, '- One\n  more about one\n* Two\n  - child\n* Three\n\nEnd.');
    });

    test('picks the LAST list when a note has several', () {
      const body = '- a\n- b\n\nMiddle.\n\n- [ ] c';
      expect(appendToList(body, ['d']).added, ['- [ ] d'.replaceFirst('d', 'D')]);
    });

    test('starts a list at the end of a note that has none', () {
      expect(appendToList('# Backlog\n\nIdeas go here.\n', ['dark mode']).body, '# Backlog\n\nIdeas go here.\n\n- Dark mode\n');
      expect(appendToList('# Backlog', ['dark mode'], asTasks: true).body, '# Backlog\n\n- [ ] Dark mode\n');
      expect(appendToList('', ['first']).body, '- First\n');
    });

    test('adds nothing for empty items', () {
      expect(appendToList('- a', ['  ', '.']).added, isEmpty);
    });

    test('grows a starred or numbered to-do list by to-dos, as every other reader takes them for to-dos (core/itemSyntax.ts)', () {
      // A `* [ ]` list was read as bullets, so what was said came in with no box to tick.
      expect(appendToList('* [ ] Milk\n* [x] Eggs', ['bread']).added, ['* [ ] Bread']);
      expect(appendToList('1. [ ] Unplug it\n2. [ ] Wait', ['plug it back in']).added, ['3. [ ] Plug it back in']);
      expect(appendToList('- [ ]', ['first thing']).added, ['- [ ] First thing']);
    });

    test('writes a due day, a priority or a person said at an item’s end as its fields', () {
      const today = '2026-10-01';
      expect(appendToList('# House\n\n- [ ] Fix the tap', ['call the plumber due Friday.'], today: today).added, ['- [ ] Call the plumber 📅 2026-10-02']);
      expect(appendToList('', ['renew the passport, urgent, for Sam'], asTasks: true, today: today).added, ['- [ ] Renew the passport @Sam ⏫']);
      expect(appendToList('1. Build', ['ship it by Friday'], today: today).added, ['2. Ship it by Friday']);
    });

    test('knows a list however it is spaced or numbered', () {
      expect(appendToList('# Ideas\n\n-\tTabbed\n-  Spaced', ['more']).body, '# Ideas\n\n-\tTabbed\n-  Spaced\n- More');
      expect(appendToList('1000. The thousandth', ['next']).added, ['1001. Next']);
    });
  });

  group('leaving a spoken note in another note', () {
    test('adds it to the note’s list when it has one, in the list’s style', () {
      const body = '# AttackFM\n\nBugs to fix:\n\n- [ ] Seek bar mismatch\n- [ ] Downloads stuck\n\nLaunch on Friday.\n';
      final left = leaveNote(body, 'that says the login is broken on Android');
      expect(left.into, PlacedInto.list);
      expect(left.added, ['- [ ] The login is broken on Android']);
      expect(left.body, '# AttackFM\n\nBugs to fix:\n\n- [ ] Seek bar mismatch\n- [ ] Downloads stuck\n- [ ] The login is broken on Android\n\nLaunch on Friday.\n');
    });

    test('picks the list it fits when a note has several', () {
      const body = '# Ghost.md\n\n## Bugs\n\n- Paste drops pictures\n- Menu runs off the edge\n\n## Ideas\n\n- Wake word\n- Shared notes\n';
      expect(leaveNote(body, 'to fix the bug where the menu flickers').added, ['- Fix the bug where the menu flickers']);
      expect(leaveNote(body, 'to fix the bug where the menu flickers').body, contains('- Menu runs off the edge\n- Fix the bug where the menu flickers\n\n## Ideas'));
      expect(leaveNote(body, 'an idea for voice shortcuts').body, matches(RegExp(r'- Shared notes\n- An idea for voice shortcuts\n$')));
    });

    test('is an item for each short sentence said one after another, as a slowly said list arrives', () {
      const body = '# Groceries\n\n- Eggs\n';
      final left = leaveNote(body, 'Chicken. Ground chicken. Beef. Ground beef. Pork. Pork belly');
      expect(left.into, PlacedInto.list);
      expect(left.added, ['- Chicken', '- Ground chicken', '- Beef', '- Ground beef', '- Pork', '- Pork belly']);
      // Two sentences are a thought, not a list.
      expect(leaveNote(body, 'Call Sam. Book the flights').added, ['- Call Sam. Book the flights']);
    });

    test('is a paragraph in a note with no list, or when it is a long thought', () {
      final left = leaveNote('# Weekend trip\n\nCabin by the lake.\n', 'we need to book it by Thursday');
      expect(left.body, '# Weekend trip\n\nCabin by the lake.\n\nWe need to book it by Thursday.\n');
      expect(left.added, ['We need to book it by Thursday.']);
      expect(left.into, PlacedInto.paragraph);
      const long = 'The seek bar goes out of step when two devices play. It starts after a pause. It gets worse over time. Nobody has found why yet.';
      expect(leaveNote('- [ ] One\n', long).into, PlacedInto.paragraph);
    });
  });

  group('the list a thing goes in, for both readers', () {
    const jobs = '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n';

    test('is the list the live reader writes into (place.ts), fitting or not', () {
      for (final said in ['order a new kettle', 'call an electrician to fix the light sockets', 'rewire the porch light']) {
        final done = placeWords(jobs, said, Placing(how: PlacingHow.item, task: true, many: false, near: said));
        final live = placeTake(jobs, '$said.', placingFor(jobs, said: const Said(task: true)));
        expect(done.body, live.body, reason: said);
      }
    });
  });

  group('a note’s front matter and a title that says what it holds', () {
    const leave = Placing(how: PlacingHow.leave, task: false, many: false);

    // A block the app counts as front matter holds keys alone (core/front_matter.dart), never a list line, so
    // `runsOf` starting after it is a guard; what the front matter changes is the title read.
    test('reads the title after the front matter, and writes after it', () {
      const book = '---\nbook: true\ntitle: Todo\n---\n# Todo\n';
      expect(placeWords(book, 'call Sam', leave).body, '---\nbook: true\ntitle: Todo\n---\n# Todo\n\n- [ ] Call Sam\n');
    });

    test('starts to-dos in a note whose title says to-dos, and bullets in one whose title says list', () {
      expect(placeWords('# House TODOs\n', 'call an electrician', leave).added, ['- [ ] Call an electrician']);
      expect(placeWords('# Packing list\n', 'the tent', leave).added, ['- The tent']);
      // A first line that is a sentence is not a title that says what the note holds.
      expect(placeWords('Shopping for the weekend is below this line.', 'oat milk', leave).into, PlacedInto.paragraph);
    });

    test('leaves no backslash where the model’s words ended in an escaped full stop', () {
      expect(itemText(r'fix the light\-sockets\.'), r'Fix the light\-sockets');
      expect(appendToList('- [ ] Gutter', [r'call Sam\.']).added, ['- [ ] Call Sam']);
    });
  });
}
