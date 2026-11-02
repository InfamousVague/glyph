// Ask the org (docs/ASK_THE_ORG.md; Matt, 2026-11-02: "'Ask the org' with receipts: questions answered only from
// your notes, every claim linked to the note and line it came from; when notes disagree, it shows both instead of
// guessing"): the scope holds to one organization or to your own notes, the passages keep the note's own lines, a
// quote that is not in the note is dropped, a disagreement is kept with both sides, newest first, and nothing found
// asks no model at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ask/ask.dart';
import 'package:ghost_md/ask/ask_answer.dart';
import 'package:ghost_md/ask/ask_note.dart';
import 'package:ghost_md/ask/ask_prompt.dart';
import 'package:ghost_md/ask/ask_retrieve.dart';
import 'package:ghost_md/ask/ask_scope.dart';
import 'package:ghost_md/core/workspaces.dart';

import 'support.dart';

void main() {
  group('scope', () {
    test('an organization reads its workspace and the folders under it, never another organization or your own', () {
      final ids = notesInScope(library, helloScope, world).map((n) => n.id).toSet();
      expect(ids, {'s27', 's29', 'm1'});
    });

    test('my notes are the notes in no organization', () {
      final ids = notesInScope(library, const AskScope.mine(), world).map((n) => n.id).toSet();
      expect(ids, {'p1'});
    });

    test('a folder inside an organization keeps to it', () {
      final folders = askFolders(workspaces.list);
      final meet = folders.singleWhere((f) => f.workspaceId == 'w-meet');
      expect(meet.orgId, 'o1');
      expect(meet.name, 'HelloTrade › Meetings');
      expect(notesInScope(library, meet, world).map((n) => n.id), ['m1']);
      // An organization's own workspace is offered as the organization, not as a folder.
      expect(folders.map((f) => f.workspaceId), isNot(contains('org-o1')));
    });

    test('a note under orgs/ on disk but unfiled is read as the organization’s by its path', () {
      final unfiled = note('u1', '# Launch memo\n\nThe launch is Monday.\n', path: 'orgs/HelloTrade/Launch memo.md');
      final byPath = AskWorld.of(const Workspaces(list: [helloTrade]), orgOfPath: (n) => (n.path ?? '').startsWith('orgs/HelloTrade/') ? 'o1' : null);
      expect(inAskScope(unfiled, helloScope, byPath), isTrue);
      expect(inAskScope(unfiled, const AskScope.mine(), byPath), isFalse);
    });
  });

  group('passages', () {
    test('keep the note’s own lines, front matter counted and left out', () {
      final passages = passagesOf(standup27);
      expect(passages.map((p) => '${p.fromLine}-${p.toLine}'), ['4-4', '6-8', '10-11']);
      expect(passages[1].heading, 'Launch');
      expect(passages[1].lines.first, '## Launch');
      expect(passages[1].id, 's27#L6-8');
      expect(passages.any((p) => p.text.contains('tags:')), isFalse);
    });

    test('a long note is cut into passages of about eight lines', () {
      final long = note('l1', ['# Long', for (var i = 1; i <= 30; i += 1) 'Line $i of the notes.'].join('\n'));
      final passages = passagesOf(long);
      expect(passages.length, greaterThan(3));
      for (final p in passages) {
        expect(p.toLine - p.fromLine, lessThan(9));
      }
      expect(passages.first.fromLine, 1);
      expect(passages.last.toLine, 31);
    });
  });

  group('retrieval', () {
    test('finds the launch passages in the scope, best first, and nothing from outside it', () {
      final notes = notesInScope(library, helloScope, world);
      final found = retrieve('When do we launch?', notes, now: nov2);
      expect(found.passages, isNotEmpty);
      expect(found.passages.map((p) => p.note.id).toSet(), {'s27', 's29'});
      expect(found.passages.first.heading, 'Launch');
      expect(found.words, contains('launch'));
    });

    test('a word written another way is still found: "meetings" finds a meeting, "launched" a launch', () {
      final notes = notesInScope(library, helloScope, world);
      expect(retrieve('what launched', notes, now: nov2).passages, isNotEmpty);
    });

    test('the device is sent fewer passages than a cloud model', () {
      final many = [for (var i = 0; i < 20; i += 1) note('n$i', '# Launch $i\n\nThe launch plan, part $i, with the launch checklist.\n')];
      expect(retrieve('launch plan', many, now: nov2).passages.length, AskBudget.cloud.passages);
      expect(retrieve('launch plan', many, budget: AskBudget.device, now: nov2).passages.length, AskBudget.device.passages);
    });

    test('nothing matching finds nothing', () {
      final notes = notesInScope(library, helloScope, world);
      expect(retrieve('the office wifi password', notes, now: nov2).isEmpty, isTrue);
      expect(retrieve('the and of', notes, now: nov2).isEmpty, isTrue);
    });

    test('the prompt numbers each line as the note does, with its note and date', () {
      final notes = notesInScope(library, helloScope, world);
      final prompt = askPrompt('When do we launch?', retrieve('When do we launch?', notes, now: nov2).passages);
      expect(prompt, contains('<passage note="s27" title="Standup Oct 27" written="2026-10-27" lines="6-8">'));
      expect(prompt, contains('7: - We ship on Thursday, after the store review.'));
      expect(prompt, contains('Question: When do we launch?'));
      expect(prompt, isNot(contains('Our launch is Friday')));
    });

    test('general knowledge is forbidden unless it is turned on', () {
      expect(askSystem(whose: 'your notes'), contains('Do not use general knowledge'));
      expect(askSystem(whose: 'your notes', general: true), contains('"general": true'));
    });
  });

  group('receipts', () {
    late List<AskPassage> sent;
    setUp(() => sent = retrieve('When do we launch? Who owns the release notes?', notesInScope(library, helloScope, world), now: nov2).passages);

    test('a quote at its lines holds', () {
      final c = checkCitation({'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': 'We ship on Thursday'}, sent);
      expect(c, isNotNull);
      expect(c!.moved, isFalse);
      expect(c.at, 'lines:7-7');
      expect(c.title, 'Standup Oct 27');
    });

    test('case, curly quotes and Markdown marks are forgiven', () {
      expect(checkCitation({'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': '“WE SHIP  ON THURSDAY.”'}, sent), isNotNull);
    });

    test('a made-up quote is dropped', () {
      expect(checkCitation({'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': 'We ship on Wednesday'}, sent), isNull);
    });

    test('a true quote at the wrong lines is moved to where it is', () {
      final c = checkCitation({'noteId': 's27', 'fromLine': 6, 'toLine': 6, 'quote': 'Ana owns the release notes'}, sent);
      expect(c, isNotNull);
      expect(c!.moved, isTrue);
      expect((c.fromLine, c.toLine), (8, 8));
    });

    test('a note that was not sent, or is in another organization, is dropped whatever it quotes', () {
      expect(checkCitation({'noteId': 'x1', 'fromLine': 4, 'toLine': 4, 'quote': 'Our launch is Friday'}, sent), isNull);
      expect(checkCitation({'noteId': 'p1', 'fromLine': 3, 'toLine': 3, 'quote': 'launch party cake'}, sent), isNull);
    });

    test('a sentence whose only quote is false is left out, and said so', () {
      final answer = validateAsk({
        'sentences': [
          {'text': 'We ship Thursday.', 'citations': [{'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': 'We ship on Thursday'}]},
          {'text': 'The CEO approved it.', 'citations': [{'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': 'the CEO approved'}]},
        ],
      }, sent);
      expect(answer.sentences.map((s) => s.text), ['We ship Thursday.']);
      expect(answer.leftOut, 1);
      expect(answer.dropped, 1);
      expect(answer.notFound, isFalse);
    });

    test('general knowledge is shown only when allowed, and marked', () {
      final raw = {
        'sentences': [
          {'text': 'Store reviews take about a day.', 'general': true, 'citations': []},
        ],
      };
      expect(validateAsk(raw, sent).sentences, isEmpty);
      final allowed = validateAsk(raw, sent, general: true);
      expect(allowed.sentences.single.general, isTrue);
      expect(allowed.notFound, isTrue, reason: 'nothing came from the notes');
    });
  });

  group('conflicts', () {
    test('both sides are kept, newest first', () {
      final sent = retrieve('When do we launch? Who owns the release notes?', notesInScope(library, helloScope, world), now: nov2).passages;
      final answer = validateAsk(parseAskJson(launchAnswer)!, sent);
      expect(answer.conflicts, hasLength(1));
      final sides = answer.conflicts.single.sides;
      expect(sides.map((s) => s.text), ['Monday', 'Thursday']);
      expect(sides.map((s) => s.citation.title), ['Standup Oct 29', 'Standup Oct 27']);
      expect(answer.receipts.map((c) => c.place), ['s27:8-8', 's29:4-4', 's27:7-7']);
    });

    test('a side whose quote fails leaves no disagreement: the other is a plain sentence', () {
      final sent = retrieve('When do we launch?', notesInScope(library, helloScope, world), now: nov2).passages;
      final answer = validateAsk({
        'conflicts': [
          {'about': 'Launch', 'sides': [
            {'text': 'Thursday', 'citation': {'noteId': 's27', 'fromLine': 7, 'toLine': 7, 'quote': 'We ship on Thursday'}},
            {'text': 'Sunday', 'citation': {'noteId': 's29', 'fromLine': 4, 'toLine': 4, 'quote': 'launch is Sunday'}},
          ]},
        ],
      }, sent);
      expect(answer.conflicts, isEmpty);
      expect(answer.sentences.single.text, 'Thursday');
      expect(answer.dropped, 1);
    });
  });

  group('asking', () {
    test('nothing found answers "not in your notes" without asking the model', () async {
      final model = ScriptedModel(launchAnswer);
      final run = ask('the office wifi password', scope: helloScope, notes: notesInScope(library, helloScope, world), model: model, now: nov2);
      final result = await run.done;
      expect(result.answer.notFound, isTrue);
      expect(result.by, isNull);
      expect(model.prompts, isEmpty);
    });

    test('the model saying notFound is not in your notes', () async {
      final model = ScriptedModel('{"notFound": true, "sentences": [], "conflicts": []}');
      final result = await ask('When is the launch party?', scope: helloScope, notes: notesInScope(library, helloScope, world), model: model, now: nov2).done;
      expect(model.prompts, hasLength(1));
      expect(result.answer.notFound, isTrue);
    });

    test('words that are no JSON are said as unreadable', () async {
      final model = ScriptedModel('The launch is on Monday, I think.');
      await expectLater(ask('When do we launch?', scope: helloScope, notes: notesInScope(library, helloScope, world), model: model, now: nov2).done, throwsA(isA<AskUnreadable>()));
    });

    test('only the scope’s passages are sent', () async {
      final model = ScriptedModel(launchAnswer);
      await ask('When do we launch?', scope: helloScope, notes: notesInScope(library, helloScope, world), model: model, now: nov2).done;
      expect(model.prompts.single, contains('Standup Oct 29'));
      expect(model.prompts.single, isNot(contains('Other team standup')));
      expect(model.prompts.single, isNot(contains('Groceries')));
      expect(model.systems.single, contains('HelloTrade’s notes'));
    });
  });

  group('Save as note', () {
    test('files the answer with its receipts as [[links]]', () async {
      final model = ScriptedModel(launchAnswer);
      final result = await ask('When do we launch? Who owns the release notes?', scope: helloScope, notes: notesInScope(library, helloScope, world), model: model, now: nov2).done;
      final body = askNoteBody(result);
      expect(body, startsWith('# Ask: When do we launch? Who owns the release notes?\n'));
      expect(body, contains('- Ana owns the release notes. [^1]'));
      expect(body, contains('## Your notes disagree'));
      expect(body, contains('The launch day: [[Standup Oct 29]] says Monday [^2]; [[Standup Oct 27]] says Thursday [^3]'));
      expect(body, contains('[^3]: [[Standup Oct 27]], line 7: “We ship on Thursday”'));
      expect(body, contains('Asked of HelloTrade’s notes, answered by Claude.'));
    });

    test('a question the notes do not answer is filed as such', () {
      final body = askNoteBody(const AskResult(question: 'Wifi?', scope: AskScope.mine(), answer: AskAnswer.nothingFound(), retrieval: AskRetrieval(passages: [], words: ['wifi'], notesRead: 3)));
      expect(body, contains('Not in your notes: nothing in your notes answers this.'));
      expect(body, isNot(contains('## Receipts')));
    });
  });
}
