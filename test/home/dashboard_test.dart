import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/home/dashboard.dart';

import '../core/make_note.dart';

/// What the home page gathers (lib/home/dashboard.dart): the cases of the web's `home/dashboard.test.ts`.
void main() {
  group('the home page', () {
    final notes = [
      makeNote('a', body: '# A', updatedAt: 10),
      makeNote('b', body: '# B', updatedAt: 30, starred: true),
      makeNote('c', body: '# C', updatedAt: 20),
      makeNote('d', body: '# D', updatedAt: 40, archivedAt: 50),
    ];

    test('pins and lists recent notes without showing one twice or anything archived', () {
      expect(ids(pinnedNotes(notes)), ['b']);
      expect(ids(recentNotes(notes, 5, {})), ['c', 'a']);
      expect(ids(recentNotes(notes, 1, {})), ['c']);
    });

    test('leaves a journal’s entries out of Recent, and a notebook’s pages in', () {
      final withJournal = [
        ...notes,
        makeNote('j', body: '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n- [[2026-09-28 14.05]]\n', updatedAt: 60),
        makeNote('e', body: '---\ntitle: "2026-09-28 14.05"\n---\nWalked.', updatedAt: 70),
        makeNote('g', body: bookNoteBody('Field guide', ['Trees']), updatedAt: 5),
        makeNote('t', body: '# Trees', updatedAt: 80),
      ];
      expect(ids(recentNotes(withJournal, 5, {})), ['t', 'c', 'a']);
    });

    test('gathers every unticked to-do, the note touched last first', () {
      final tasks = openTasks([
        makeNote('old', body: '# Old\n- [ ] Buy milk\n- [x] Done already', updatedAt: 1),
        makeNote('new', body: '# New\n\n1. [ ] Ship it ^ship\n* [ ] Tell Sam\n- plain bullet', updatedAt: 2),
      ]);
      expect([for (final t in tasks) [t.noteId, t.line, t.text, t.at]], [
        ['new', 2, 'Ship it', 'ship'],
        ['new', 3, 'Tell Sam', null],
        ['old', 1, 'Buy milk', null],
      ]);
    });

    test('leaves out a to-do written as an example in a code fence, an empty box, and the archive', () {
      final tasks = openTasks([
        makeNote('n', body: '```md\n- [ ] not a task\n```\n- [ ] \n- [ ] real', updatedAt: 1),
        makeNote('gone', body: '- [ ] archived', updatedAt: 2, archivedAt: 3),
      ]);
      expect([for (final t in tasks) t.text], ['real']);
    });

    test('counts the ticked to-dos, leaving out examples in a fence, empty boxes and the archive', () {
      expect(
        tickedTasks([
          makeNote('a', body: '- [x] Done\n- [X] Also done\n- [ ] Open\n- [x] ', updatedAt: 1),
          makeNote('b', body: '```\n- [x] an example\n```\n1. [x] numbered', updatedAt: 2),
          makeNote('gone', body: '- [x] archived', updatedAt: 3, archivedAt: 4),
        ]),
        3,
      );
      expect(tickedTasks([makeNote('c', body: '- [ ] only open', updatedAt: 1)]), 0);
    });

    test('says a to-do by its words, without its fields, and leaves out one that is only fields (docs/DESIGN.md §158)', () {
      final tasks = openTasks([makeNote('n', body: '- [ ] Call the plumber @matt ⏫ 📅 2026-10-03\n- [ ] 📅 2026-10-04', updatedAt: 1)]);
      expect([for (final t in tasks) t.text], ['Call the plumber']);
    });

    test('takes brackets glued to the words as words, as the note draws them (core/itemSyntax.ts)', () {
      expect([for (final t in openTasks([makeNote('n', body: '- [ ]Buy milk\n- [ ] Real', updatedAt: 1)])) t.text], ['Real']);
      expect(tickedTasks([makeNote('n', body: '- [x]Done\n- [x](https://example.com/x)', updatedAt: 1)]), 0);
    });
  });

  group('the library', () {
    test('is the books, newest change first, the archive left out, and Recent is without them', () {
      final notes = [
        makeNote('a', body: '# A plain note', updatedAt: 5),
        makeNote('b', body: '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[A plain note]]\n', updatedAt: 3),
        makeNote('c', body: '---\ntitle: "Old"\nbook: true\n---\n', updatedAt: 9, archivedAt: 1),
        makeNote('d', body: '---\ntitle: "Trip"\nbook: true\n---\n', updatedAt: 7),
      ];
      expect(ids(bookNotes(notes)), ['d', 'b']);
      expect(ids(recentNotes(notes, 10, {})), ['a']);
    });
  });

  group('the shelf of tapes', () {
    Note recorded(String id, int createdAt, {int? updatedAt, int? recordingMs = 40000, int? archivedAt, bool starred = false}) =>
        makeNote(id, body: '# $id', source: NoteSource.capture, recordingMs: recordingMs, createdAt: createdAt, updatedAt: updatedAt ?? createdAt, archivedAt: archivedAt, starred: starred);
    const none = <String, int>{};

    test('is what the recorder made, the last recorded first, whatever was touched since', () {
      final notes = [recorded('old', 10, updatedAt: 90), recorded('new', 30), recorded('mid', 20)];
      expect(ids(tapedNotes(notes, none)), ['new', 'mid', 'old']);
    });

    test('leaves out the archive, the Guide, a typed note spoken into, and a recording whose tape was removed', () {
      final guide = makeNote('guide', body: bookNoteBody(guideTitle, ['Your first note']), updatedAt: 50);
      final notes = [
        recorded('kept', 5),
        recorded('gone', 6, archivedAt: 7),
        guide,
        makeNote('first', body: '# Your first note', source: NoteSource.capture, recordingMs: 9000, createdAt: 8, updatedAt: 8),
        makeNote('typed', body: '# Typed then spoken', recordingMs: 12000, createdAt: 9, updatedAt: 9),
        recorded('removed', 4, recordingMs: null),
        recorded('silent', 3, recordingMs: 0),
      ];
      expect(ids(tapedNotes(notes, none)), ['kept']);
      expect(isTape(notes[4], none), isFalse);
    });

    test('counts a meeting as a tape whatever its source, by the meetings preference', () {
      final meeting = makeNote('m', body: '# Meeting, 26 Sep 14:05', recordingMs: 3600000, createdAt: 40, updatedAt: 40);
      expect(isTape(meeting, {'m': 40}), isTrue);
      expect(isTape(meeting, none), isFalse);
      expect(ids(tapedNotes([meeting, recorded('r', 30)], {'m': 40})), ['m', 'r']);
    });

    test('asks the queue for a meeting’s write-up for a meeting, and a recording’s for anything else', () {
      final meeting = makeNote('m', body: '# Meeting', recordingMs: 3600000);
      expect(summaryKindOf(meeting, {'m': 40}), SummaryKind.meeting);
      expect(summaryKindOf(meeting, none), SummaryKind.recording);
      expect(summaryKindOf(recorded('r', 30), {'m': 40}), SummaryKind.recording);
    });

    test('keeps a pinned tape on the shelf as well as in Pinned, since pinning is a deliberate act', () {
      final pinned = recorded('p', 10, starred: true);
      expect(ids(tapedNotes([pinned], none)), ['p']);
      expect(ids(pinnedNotes([pinned])), ['p']);
    });

    test('puts the meeting being recorded first on the shelf, with no tape yet, and out of Recent', () {
      final live = makeNote('live', body: '# Meeting, 26 Sep 14:05', source: NoteSource.capture, createdAt: 5, updatedAt: 5);
      final notes = [recorded('tape', 50), live, makeNote('plain', body: '# Plain', updatedAt: 30)];
      // Without the live id it is a note with no recording: Recent's, not the shelf's.
      expect(ids(tapedNotes(notes, none)), ['tape']);
      expect(ids(recentNotes(notes, 10, none)), ['plain', 'live']);
      // With it, it is first on the shelf whatever its date, and gone from Recent.
      expect(ids(tapedNotes(notes, none, 'live')), ['live', 'tape']);
      expect(ids(recentNotes(notes, 10, none, 'live')), ['plain']);
      // A live id for a note that is not here changes nothing; an archived one stays out.
      expect(ids(tapedNotes(notes, none, 'elsewhere')), ['tape']);
      expect(tapedNotes([live.copyWith(archivedAt: () => 6)], none, 'live'), isEmpty);
      // Once it has its recording it is a tape by its own right, and is not listed twice.
      final taped = makeNote('live', body: live.body, source: NoteSource.capture, createdAt: 5, updatedAt: 5, recordingMs: 3600000);
      expect(ids(tapedNotes([recorded('tape', 50), taped], none, 'live')), ['live', 'tape']);
    });

    test('leaves out of Recent exactly what the shelf takes, so a typed note with a tape stays in Recent', () {
      final notes = [
        recorded('tape', 50),
        makeNote('typed', body: '# Typed then spoken', recordingMs: 12000, createdAt: 40, updatedAt: 40),
        makeNote('plain', body: '# Plain', updatedAt: 30),
        makeNote('meeting', body: '# Meeting', recordingMs: 900000, createdAt: 20, updatedAt: 60),
      ];
      expect(ids(recentNotes(notes, 10, none)), ['meeting', 'typed', 'plain']);
      expect(ids(recentNotes(notes, 10, {'meeting': 20})), ['typed', 'plain']);
      final shelf = ids(tapedNotes(notes, {'meeting': 20}));
      final recent = ids(recentNotes(notes, 10, {'meeting': 20}));
      expect(shelf.where(recent.contains), isEmpty);
      expect([...shelf, ...recent]..sort(), ['meeting', 'plain', 'tape', 'typed']);
    });
  });

  group('the digest', () {
    test('counts the notes touched since the local day began, the archive and the Guide out', () {
      // A Wednesday at 10:30, local time.
      final now = DateTime(2026, 9, 23, 10, 30).millisecondsSinceEpoch;
      final midnight = DateTime(2026, 9, 23).millisecondsSinceEpoch;
      expect(startOfToday(now), midnight);
      final guide = makeNote('guide', body: bookNoteBody(guideTitle, ['Your first note']), updatedAt: now - 60000);
      final notes = [
        makeNote('at-midnight', body: '# A', updatedAt: midnight),
        makeNote('just-before', body: '# B', updatedAt: midnight - 1),
        makeNote('this-morning', body: '# C', updatedAt: now - 60000),
        makeNote('gone', body: '# D', updatedAt: now, archivedAt: now),
        guide,
        makeNote('first', body: '# Your first note', updatedAt: now),
      ];
      expect(touchedToday(notes, now), 2);
    });

    test('counts what is waiting on the tapes once each, working before needing a model before failed', () {
      final tapes = [for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) makeNote(id, source: NoteSource.capture, recordingMs: 40000)];
      final waiting = tapesWaiting(
        tapes,
        refining: {'a'},
        summaries: const SummariesState(pending: {'b', 'e'}, native: {'c'}, needsModel: {'d', 'e'}, failed: {'d', 'f'}),
      );
      expect(waiting, (working: 4, needsModel: 1, failed: 1));
      // A write-up waiting for the phone to charge is working, as far as the digest says: it is on its way.
      expect(tapesWaiting(tapes, refining: {}, summaries: const SummariesState(waiting: {'a'})), (working: 1, needsModel: 0, failed: 0));
      expect(tapesWaiting(tapes, refining: {}, summaries: const SummariesState()), (working: 0, needsModel: 0, failed: 0));
      // Only the tapes given: a note in a queue but not on the page is not counted.
      expect(tapesWaiting([], refining: {'a'}, summaries: const SummariesState()), (working: 0, needsModel: 0, failed: 0));
    });

    test('says each phrase that is true, in its order, with where it goes', () {
      expect(digest(open: 5, waiting: (working: 2, needsModel: 1, failed: 1), touched: 3), [
        (text: '5 to-dos open', go: DigestGo.tasks),
        (text: 'Working on 2 tapes', go: DigestGo.tapes),
        (text: '1 tape needs a model', go: DigestGo.model),
        (text: '1 summary didn’t come', go: DigestGo.tapes),
        // The day's count is said, not a word: the notes it counts are all over the page, not in one group.
        (text: '3 notes touched today', go: null),
      ]);
    });

    test('speaks in the singular for one, and in the plural for more', () {
      expect([for (final p in digest(open: 1, waiting: (working: 1, needsModel: 2, failed: 2), touched: 1)) p.text], [
        '1 to-do open',
        'Working on 1 tape',
        '2 tapes need a model',
        '2 summaries didn’t come',
        '1 note touched today',
      ]);
    });

    test('says nothing is waiting when none of the waiting phrases are true, and leaves out a count of nothing', () {
      const quiet = (working: 0, needsModel: 0, failed: 0);
      expect(digest(open: 0, waiting: quiet, touched: 0), [(text: 'Nothing waiting on you', go: null)]);
      expect([for (final p in digest(open: 0, waiting: quiet, touched: 2)) p.text], ['Nothing waiting on you', '2 notes touched today']);
      expect([for (final p in digest(open: 3, waiting: quiet, touched: 0)) p.text], ['3 to-dos open']);
    });
  });

  group('Ghost.md: The Guide on the home page', () {
    final guide = makeNote('guide', body: bookNoteBody(guideTitle, ['Your first note', 'Boards made of list items']), updatedAt: 50);
    final first = makeNote('first', body: '# Your first note\n\n- [ ] Book the cabin\n- [x] Call Sam', updatedAt: 60);
    final boards = makeNote('boards', body: '# Boards made of list items\n\n- [ ] Pack the coffee', updatedAt: 70);
    final mine = makeNote('mine', body: bookNoteBody('Field guide', ['Trees']), updatedAt: 10);
    final trees = makeNote('trees', body: '# Trees\n\n- [ ] Find an oak', updatedAt: 20);
    final own = makeNote('own', body: '# Groceries\n\n- [ ] Eggs', updatedAt: 30);
    final notes = [guide, first, boards, mine, trees, own];

    test('keeps its pages out of Recent, and a chapter of a book of one’s own in it', () {
      expect(ids(recentNotes(notes, 6, {})), ['own', 'trees']);
    });

    test('leaves its example to-dos out of the to-do list and the count of ticked ones', () {
      expect([for (final t in openTasks(notes)) t.text], ['Eggs', 'Find an oak']);
      expect(tickedTasks(notes), 0);
    });
  });

  group('your templates on the home page', () {
    // `templatesNotebookBody` and `newTemplatePageBody` (notes/ownTemplates.ts), as they write them.
    final book = makeNote('tpl', body: '---\ntitle: ${quotedTitle('Templates', 'Templates')}\nbook: true\ntemplates: true\n---\n# Templates\n\n- [[A checklist]]\n- [[A walk]]\n', updatedAt: 90);
    final checklist = makeNote('checklist', body: '---\ntitle: "A checklist"\ntemplates: page\n---\n# {{title}}\n\n- [ ] Bread\n- [x] Milk', updatedAt: 80);
    final walk = makeNote('walk', body: '---\ntitle: "A walk"\ntemplates: page\n---\n# {{title}}\n\n', updatedAt: 70);
    final own = makeNote('own', body: '# Groceries\n\n- [ ] Eggs', updatedAt: 30);
    final notes = [book, checklist, walk, own];

    test('keeps a Templates notebook’s pages out of Recent, To do, the ticked count and the notes touched today', () {
      expect(ids(recentNotes(notes, 6, {})), ['own']);
      expect([for (final t in openTasks(notes)) t.text], ['Eggs']);
      expect(tickedTasks(notes), 0);
      expect(touchedToday(notes, 100), 2);
    });
  });

  group('a to-do the AI filled (docs/DESIGN.md §145)', () {
    test('is its answer’s words on home’s To do, and a to-do holding a blank is its question’s', () {
      final note = makeNote('tap',
          body: '# Kitchen tap\n- [x] Found the leak\n- [ ] ??Turn off the water and fit the new washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)\n- [ ] {?what to buy}');
      expect([for (final t in openTasks([note])) t.text], ['Turn off the water and fit the new washer', 'what to buy']);
    });
  });
}
