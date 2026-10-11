import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart' show Canvas, canvasNoteBody;
import 'package:ghost_md/capture/candidates.dart';
import 'package:ghost_md/capture/note_find.dart';
// The web's `FIND` is `find` there, which this file's own `find` hides.
import 'package:ghost_md/capture/note_find.dart' as note_find show find;
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody, guideTitle;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/notes/note_templates.dart' show TemplateId, builtIns;
import 'package:ghost_md/notes/own_templates.dart' show templatePageBody, templatesNotebookBody;

import 'support/library_titles.dart';
import 'support/notes.dart';
import 'support/shapes.dart';

/// The note a spoken name means (lib/capture/note_find.dart), case for case with the web's
/// `capture/noteFind.test.ts`.

/// Matt's library as the recorder reads it: his 76 titles (the two canvases among them as the canvases they are),
/// the Guide added (its index and 44 chapters), through the same filter the recorder uses (capture/candidates.dart).
final List<TakeCandidate<Note>> library = () {
  final titles = libraryTitles.where((title) => !RegExp('canvas', caseSensitive: false).hasMatch(title)).toList();
  final own = [
    for (var i = 0; i < titles.length; i += 1)
      makeNote('n$i', body: titles[i] == 'House TODOs' ? '# House TODOs\n\n- [ ] Fix the gutter\n' : '# ${titles[i]}', updatedAt: 1000 - i),
  ];
  final chapters = [
    for (var i = 0; i < guideChapterTitles.length; i += 1) makeNote('g$i', body: '# ${guideChapterTitles[i]}\n\nWords.', updatedAt: 2000 - i),
  ];
  final index = makeNote('guide', body: bookNoteBody(guideTitle, guideChapterTitles), updatedAt: 3000);
  final canvases = [
    makeNote('c1', body: canvasNoteBody('Canvas · The tick path', Canvas(nodes: const [], edges: const [])), updatedAt: 4000),
    makeNote('c2', body: canvasNoteBody('Untitled canvas', Canvas(nodes: const [], edges: const [])), updatedAt: 4001),
  ];
  return commandCandidates([...own, ...chapters, index, ...canvases]);
}();

Found<TakeCandidate<Note>> find(String name, [Aim? aim]) => findNote(name, library, aim: aim);

String titleOf(String name) {
  final found = find(name);
  return found is FoundResolved<TakeCandidate<Note>> ? found.note.title : found.status;
}

void main() {
  group('the notes a command can name', () {
    test('leaves out the Guide’s chapters and canvases, and keeps the book and the person’s own notes', () {
      final titles = library.map((c) => c.title).toList();
      expect(titles, contains('House TODOs'));
      expect(titles, contains(guideTitle));
      expect(titles, isNot(contains('Lists and to-dos')));
      expect(titles, isNot(contains('Untitled canvas')));
      expect(titles, isNot(contains('Canvas · The tick path')));
    });

    test('leaves out the pages of a Templates notebook: a checklist said is the person’s, never the template', () {
      final checklist = builtIns.firstWhere((one) => one.kind == TemplateId.checklist);
      final named = commandCandidates([
        makeNote('tpl', body: templatesNotebookBody([checklist.name]), updatedAt: 3),
        makeNote('page', body: templatePageBody(checklist), updatedAt: 2),
        makeNote('mine', body: '# Groceries\n\n- [ ] Eggs', updatedAt: 1),
      ]).map((c) => c.id).toList();
      expect(named, ['tpl', 'mine']);
    });
  });

  group('one spelling of to-do, and the kind words', () {
    test('hears every way Whisper writes to-do as one word', () {
      for (final said in ["house to do's", 'house to-dos', 'house todos', 'house todo', 'house 2 dos', 'house two dos', 'House TODOs', 'house to dos']) {
        expect(nameWords(said), matchObject({'distinctive': ['house'], 'specific': ['todo']}), reason: said);
      }
    });

    test('tells the words that say which note from the words that say what kind', () {
      expect(
        nameWords('the house list items'),
        const NameWords(words: ['house', 'list', 'item'], distinctive: ['house'], specific: [], generic: ['list', 'item']),
      );
      expect(nameWords('my chores'), const NameWords(words: ['chore'], distinctive: [], specific: ['chore'], generic: []));
    });

    test('reads a title’s kind for where words go in it', () {
      expect(titleKind('House TODOs'), TitleKind.task);
      expect(titleKind('Chores'), TitleKind.task);
      expect(titleKind('Groceries'), TitleKind.bullet);
      expect(titleKind('Packing list'), TitleKind.bullet);
      expect(titleKind('Daily Life'), isNull);
      // By the word it ends on: about tasks is not a list of them.
      expect(titleKind('Task Management'), isNull);
      expect(titleKind('Task list'), TitleKind.task);
      expect(titleKind('Home jobs'), TitleKind.task);
    });

    test('never lets a kind word decide, and lets a shared one back a match up', () {
      final house = nameWords('House TODOs');
      expect(nameScore(nameWords('house to do list'), house), 1);
      expect(nameScore(nameWords('house chores'), house), closeTo(0.9, 0.005));
      expect(nameScore(nameWords('house list'), house), greaterThan(nameScore(nameWords('house'), house)));
      expect(nameScore(nameWords('tasks'), nameWords('Task Management')), 0);
    });

    // A name that is only the start of a title is a fair pick after the keyword, and not clear without it
    // (docs/DESIGN.md §136).
    test('is clear only for the whole of a title’s distinctive words, never for its first word alone', () {
      double score(String said, String title) => nameScore(nameWords(said), nameWords(title));
      expect(note_find.find.clear, 0.9);
      expect(score('bank', 'Bank statements'), 0.85);
      expect(score('weekend', 'Weekend trip'), 0.85);
      expect(score('car', 'Car insurance'), 0.85);
      expect(score('garden jobs', 'House and garden jobs'), 0.85);
      expect(score('the weekend list', 'Weekend trip'), 0.85);
      expect(score('house', 'House TODOs'), 0.9);
      expect(score('the work list', 'Work'), 0.9);
      expect(score('weekend trip', 'Weekend trip'), 1);
    });
  });

  group('finding the note in Matt’s library', () {
    test('finds House TODOs however it is said', () {
      for (final said in [
        "house to do's",
        'house to-dos',
        'house todos',
        'house todo',
        'house 2 dos',
        'house two dos',
        'house to do list',
        'house list',
        'house list items',
        'house chores',
        'house tasks',
        'house stuff',
        'household to dos',
        'house',
        'the house to-do list',
        'my house to do’s list',
      ]) {
        expect(titleOf(said), 'House TODOs', reason: said);
      }
    });

    test('finds Todo by its kind words alone, with the Guide’s Lists and to-dos left out', () {
      for (final said in ['to-do list', 'my to-do list', 'todo', 'the to do list']) {
        expect(titleOf(said), 'Todo', reason: said);
      }
    });

    test('is unsure between titles that come as close as each other', () {
      for (final said in ['task list', 'hello trade the book', 'signing']) {
        expect(find(said).status, 'unsure', reason: said);
      }
      final book = find('hello trade the book');
      expect(
        book is FoundUnsure<TakeCandidate<Note>> ? (book.candidates.map((c) => c.title).toList()..sort()) : <String>[],
        ['HelloTrade — The Book', 'HelloTrade: The Book'],
      );
    });

    test('finds nothing where nothing is named, with the titles that came near', () {
      final tasks = find('tasks');
      expect(tasks.status, 'missing');
      expect(tasks is FoundMissing<TakeCandidate<Note>> ? tasks.near.map((c) => c.title).toList() : <String>[], contains('Task Management'));
      expect(find('the moon base'), const FoundMissing<TakeCandidate<Note>>(near: []));
      expect(find('groceries and eggs').status, 'missing');
      // Beside a Groceries note too: letters alone never stretch a title over more words than it has.
      final groceries = <Candidate>[
        ...library,
        const TakeCandidate<TakeNote>(id: 'gr', title: 'Groceries', note: TakeNote(id: 'gr', body: '# Groceries\n\n- Eggs\n')),
      ];
      expect(findNote('groceries', groceries), matchObject({'status': 'resolved', 'note': {'id': 'gr'}}));
      expect(findNote('groceries and eggs', groceries).status, 'missing');
    });

    test('takes words run together or apart', () {
      const titles = [Candidate(id: 'h', title: 'HelloTrade'), Candidate(id: 'w', title: 'Weekend trip')];
      expect(findNote('hello trade', titles), matchObject({'status': 'resolved', 'note': {'id': 'h'}}));
      expect(findNote('week end trip', titles), matchObject({'status': 'resolved', 'note': {'id': 'w'}}));
      expect(findNote('weekend', titles), matchObject({'status': 'resolved', 'note': {'id': 'w'}}));
    });
  });

  group('the note being written to', () {
    const homeJobs = Aim(id: 'jobs', body: '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n');

    test('is what “the list”, “this note” and “here” mean', () {
      for (final said in ['the list', 'this note', 'here', 'this list']) {
        expect(find(said), const FoundCurrent<TakeCandidate<Note>>(heading: null), reason: said);
      }
    });

    test('is what a kind word alone means when that note keeps such a list', () {
      expect(find('my to-do list', homeJobs), const FoundCurrent<TakeCandidate<Note>>(heading: null));
    });

    test('is the note, under a heading, when a name is one of its headings', () {
      expect(find('kitchen', homeJobs), const FoundCurrent<TakeCandidate<Note>>(heading: 'Kitchen'));
      expect(find('the electrical list', homeJobs), const FoundCurrent<TakeCandidate<Note>>(heading: 'Electrical'));
      // A note named better than any heading is still that note.
      expect(titleOf('house to-dos'), 'House TODOs');
      expect(findNote('house to-dos', library, aim: homeJobs), matchObject({'status': 'resolved', 'note': {'title': 'House TODOs'}}));
    });

    test('reads a board’s lanes and a note’s labels as its places, never its own title', () {
      expect(headingsOf('# Launch\n\n```board\nTo do: a\nDoing: b\n```\n\nShopping:\n- eggs\n'), ['Shopping', 'To do', 'Doing']);
      expect(headingsOf('# Home jobs\n\n## Kitchen\n```\n## Not a heading\n```\n'), ['Kitchen']);
      // A heading named as surely as a note is found (`find.resolved`): a quarter of its words is not it, half is.
      const drains = '# Home jobs\n\n## Upstairs kitchen sink drains\n- [ ] Fix tap\n';
      expect(headingIn(drains, 'the sink'), false);
      expect(headingIn(drains, 'kitchen sink'), true);
      expect(headingIn('# Launch\n\n```board\nTo do: a\nDoing: b\n```\n', 'doing'), true);
      expect(headingIn('# House TODOs\n\n- [ ] Fix the gutter\n', 'the sofa'), false);
    });
  });
}
