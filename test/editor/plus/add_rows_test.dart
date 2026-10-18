// What the + beside the line offers (lib/editor/plus/add_rows.dart): which rows are there, in what order, and
// exactly what each writes on an empty line. The cases of tauri/src/app/editor/addRows.test.ts, one for one;
// the two that stood a phone, the Mac and the iPhone in for the page's platform are not here, since in this app a
// row is there when the screen hands the list its callback (see add_rows.dart's header), and what is left of them
// is `readGates`.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/editor/plus/add_rows.dart';
import 'package:ghost_md/editor/state/history.dart';

import '../commands/support.dart';

final DateTime now = DateTime(2026, 9, 28, 14, 5);

AddGates gates({bool picture = true, bool video = false, PlaceGate place = PlaceGate.on, bool note = true, bool canvas = true, List<PlusEffect> effects = const [], bool tableAbove = false, bool ticket = false, bool simple = false}) =>
    AddGates(picture: picture, video: video, place: place, note: note, canvas: canvas, effects: effects, tableAbove: tableAbove, ticket: ticket, simple: simple);

TestView viewOf(String doc, [int? caret]) => TestView.of(doc, caret ?? doc.length, null, [history()]);

const PlusEffect heat = PlusEffect(name: 'Heat', delimiter: '🔥🔥', cue: 'heated', icon: Lucide.flame);

/// What a row writes on `doc`, with the caret at its end: the note after, and the words selected or the caret's
/// place as `|`.
String written(String id, [String doc = 'Lunch\n', List<PlusEffect> effects = const []]) {
  final view = viewOf(doc);
  expect(writeRow(view, id, now, effects: effects), isTrue);
  final main = view.state.selection.main;
  final text = view.text;
  return main.from == main.to ? '${text.substring(0, main.from)}|${text.substring(main.from)}' : '${text.substring(0, main.from)}[${text.substring(main.from, main.to)}]${text.substring(main.to)}';
}

void main() {
  group('in simple mode (GHST-103)', () {
    const basics = ['A picture', 'A to-do', 'A heading', 'A bulleted list', 'A numbered list', 'A quote', 'A table', 'A link', 'A divider'];

    test('the first page is the basics, each with a line saying what it makes, and More', () {
      final top = topRows(gates(video: true, simple: true), now);
      expect(top.map((row) => row.words), [...basics, 'More']);
      expect(top.every((row) => row.hint != null), isTrue, reason: 'every row says what it makes');
      expect(top.firstWhere((row) => row.id == 'heading').hint, 'A title for a section.');
      expect(top.last.step, AddStep.more);
    });

    test('More holds everything else, in the order the list has today, without the lines', () {
      final all = gates(video: true, simple: true, ticket: true, tableAbove: true, effects: [heat]);
      final rest = moreRows(all, now);
      expect(rest.map((row) => row.words), [
        'A video', 'A place', stamp(now), 'A board', 'A database', 'A note', //
        'A callout', 'A choice', 'A to-do with a due date', 'A block of code', 'Make this a ticket', 'A diagram', 'A formula', 'A canvas', 'A footnote', 'A tag', 'A counter', 'A sum', 'A blank for the AI', 'Blanks in the empty cells', 'Heated words',
      ]);
      expect(rest.any((row) => basics.contains(row.words)), isFalse);
      expect(rest.any((row) => row.hint != null), isFalse);
      // The steps are still steps there.
      expect(rest.firstWhere((row) => row.id == 'board').step, AddStep.board);
      expect(rest.firstWhere((row) => row.id == 'note').step, AddStep.note);
    });

    test('the flat list for the slash palette is the basics, then the rest', () {
      final flat = allRows(gates(video: true, simple: true), now).map((row) => row.words).toList();
      expect(flat.take(basics.length), basics);
      expect(flat, isNot(contains('More')));
      expect(flat.skip(basics.length).take(3), ['A video', 'A place', stamp(now)]);
    });

    test('A link writes [text](url) with "text" selected, to be written over', () {
      expect(written('link'), 'Lunch\n[[text]](url)');
    });

    test('advanced is as it was: no link row, no lines', () {
      final flat = allRows(gates(video: true), now);
      expect(flat.any((row) => row.id == 'link'), isFalse);
      expect(flat.any((row) => row.hint != null), isFalse);
    });
  });

  group('the list’s rows', () {
    test('lead with the phone’s things, then the data trio (table, board, database), then a note and a to-do, then More', () {
      final top = topRows(gates(video: true), now);
      expect(top.map((row) => row.words), ['A picture', 'A video', 'A place', stamp(now), 'A table', 'A board', 'A database', 'A note', 'A to-do', 'More']);
      // A board and a database are steps now, not direct writes (add_list.dart opens their page).
      expect(top.firstWhere((row) => row.id == 'board').step, AddStep.board);
      expect(top.firstWhere((row) => row.id == 'query').step, AddStep.database);
    });

    test('say the time as it will be written, and read it aloud with the month in full', () {
      final time = topRows(gates(), now).firstWhere((row) => row.id == 'time');
      expect(time.words, stamp(now));
      expect(time.words, '28 Sept 2026, 14:05');
      expect(time.label, matches(RegExp(r'^The date and time, .*2026, 14:05$')));
      expect(time.label, contains('September'));
    });

    group('in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);

      test('an American phone says the time month first, written and read aloud', () {
        toldLocale = DateLocale.enUS;
        final time = topRows(gates(), now).firstWhere((row) => row.id == 'time');
        expect(time.words, 'Sep 28 2026, 14:05');
        expect(time.label, 'The date and time, September 28 2026, 14:05');
        expect(written('time'), 'Lunch\nSep 28 2026, 14:05|');
      });

      test('a British phone says it day first, with Sept', () {
        toldLocale = DateLocale.enGB;
        final time = topRows(gates(), now).firstWhere((row) => row.id == 'time');
        expect(time.words, '28 Sept 2026, 14:05');
        expect(time.label, 'The date and time, 28 September 2026, 14:05');
        expect(written('time'), 'Lunch\n28 Sept 2026, 14:05|');
      });
    });

    test('write the minute’s name on the line that names the note, not the stamp, and say so', () {
      final naming = topRows(gates(), now, true).firstWhere((row) => row.id == 'time');
      expect(naming.words, '2026-09-28 14.05');
      expect(naming.label, 'The date and time as a name, 2026-09-28 14.05');
      expect(written('time', ''), '2026-09-28 14.05|');
      expect(written('time', '# '), '# 2026-09-28 14.05|');
      // Anywhere else, the stamp as before.
      expect(written('time', '# Lunch\n\n'), contains(stamp(now)));
      expect(written('time'), contains(stamp(now)));
    });

    test('leave out what the screen cannot do', () {
      final top = topRows(gates(picture: false, place: PlaceGate.absent, note: false), now);
      expect(top.map((row) => row.id), ['time', 'table', 'board', 'query', 'todo', 'more']);
    });

    test('dim a place under Local only, and say why', () {
      final place = topRows(gates(place: PlaceGate.dimmed), now).firstWhere((row) => row.id == 'place');
      expect(place.dimmed, 'Local only is on.');
    });

    test('keep the rest behind More: the forms, the blocks, the small marks, and the effects that are on', () {
      expect(moreRows(gates(effects: [heat])).map((row) => row.words), [
        'A heading',
        'A bulleted list',
        'A numbered list',
        'A quote',
        'A callout',
        'A choice',
        'A to-do with a due date',
        'A block of code',
        'A divider',
        'A diagram',
        'A formula',
        'A canvas',
        'A footnote',
        'A tag',
        'A counter',
        'A sum',
        'A blank for the AI',
        'Heated words',
      ]);
      expect(moreRows(gates(canvas: false)).map((row) => row.id), isNot(contains('canvas')));
    });
  });

  group('where a row is there at all', () {
    test('offers a video exactly where the screen says the binary adds one', () {
      AddGates read(bool video) => readGates(picture: true, video: video, place: true, note: true, canvas: true);
      expect(read(false).video, isFalse);
      expect(read(true).video, isTrue);
    });

    test('offers a picture, a note and a canvas where the screen can do them', () {
      final none = readGates(picture: false, video: false, place: false, note: false, canvas: false);
      expect([none.picture, none.note, none.canvas], [false, false, false]);
      final all = readGates(picture: true, video: false, place: true, note: true, canvas: true);
      expect([all.picture, all.note, all.canvas], [true, true, true]);
    });

    test('offers a place where the device can find one, dimmed under Local only, and never where it cannot', () {
      AddGates read({required bool place, bool localOnly = false}) => readGates(picture: true, video: false, place: place, note: true, canvas: true, localOnly: localOnly);
      expect(read(place: true).place, PlaceGate.on);
      expect(read(place: true, localOnly: true).place, PlaceGate.dimmed);
      expect(read(place: false).place, PlaceGate.absent);
      expect(read(place: false, localOnly: true).place, PlaceGate.absent);
    });
  });

  group('what each row writes on an empty line', () {
    test('the time and the words, at the caret', () {
      expect(written('time'), 'Lunch\n${stamp(now)}|');
      expect(written('tag'), 'Lunch\n#[tag]');
      expect(written('counter'), 'Lunch\n[Count] [0/8]');
      expect(written('counter', 'Goals\n- '), 'Goals\n- [Count] [0/8]');
    });

    test('an effect as words to write over between its marks, named as it is said', () {
      expect(written('effect:Heat', 'Lunch\n', [heat]), 'Lunch\n🔥🔥[words]🔥🔥');
      expect(effectWords(heat), 'Heated words');
      expect(effectWords(const PlusEffect(name: 'Glow', delimiter: '🔥🔥')), 'Glow words');
      // An effect the list was not given writes nothing.
      expect(writeRow(viewOf('Lunch\n'), 'effect:Heat', now), isFalse);
    });

    test('a to-do, a choice and the lists as a line’s lead', () {
      expect(written('todo'), 'Lunch\n- [ ] |');
      expect(written('choice'), 'Lunch\n- ( ) |');
      expect(written('bullets'), 'Lunch\n- |');
      expect(written('numbers', '1. one\n'), '1. one\n2. |');
      expect(written('todo', '- milk\n- '), '- milk\n- [ ] |');
    });

    test('a heading, a quote and a sum as a line’s form', () {
      expect(written('heading'), 'Lunch\n## |');
      expect(written('quote'), 'Lunch\n> |');
      expect(written('sum'), 'Lunch\n= |');
    });

    test('the blocks, with a blank line from the words above, and a seed to write over', () {
      expect(written('table'), 'Lunch\n\n| [Column] | Column |\n| --- | --- |\n| Cell | Cell |');
      expect(written('divider'), 'Lunch\n\n---\n|');
      expect(written('code'), 'Lunch\n\n```\n|\n```');
      expect(written('callout'), 'Lunch\n\n> [!NOTE]\n> |');
      expect(written('chart'), 'Lunch\n\n```mermaid\nflowchart LR\n  A[[Start]] --> B[Then]\n  B --> C[Done]\n```');
      // A formula is a $$ block, the caret on the empty line between its fences.
      expect(written('formula'), 'Lunch\n\n\$\$\n|\n\$\$');
    });

    test('a board as a page of the two ways to start one', () {
      expect(boardRows().map((row) => (row.id, row.words)), [('board', 'Fresh columns'), ('query:board', 'From your tickets')]);
      // Neither way is in More any more; the board and the database are steps on the first page.
      expect(moreRows(gates()).map((row) => row.id), isNot(contains('board')));
      expect(moreRows(gates()).map((row) => row.id), isNot(contains('query')));
    });

    test('a database as a page of ready-made ones, each drawn at once, and Write your own with its kind to write over', () {
      expect(databaseRows().map((row) => row.words), [
        'To-dos due this week',
        'Overdue to-dos',
        'To-dos by person',
        'To-dos on a calendar',
        'A ticket board',
        'Open tickets, with estimates',
        'A ticket timeline',
        'Notes changed this week',
        'How many to-dos are open',
        'Write your own',
      ]);
      expect(written('query:board'), 'Lunch\n\n```query\nfrom: tickets\nshow: board\n```\n|');
      expect(written('query:own'), 'Lunch\n\n```query\nfrom: [tasks]\nwhere: due <= today+7\nsort: due, priority\nshow: list\n```');
      expect(querySeed('query:nothing'), isNull);
    });

    test('a to-do with a due date, due tomorrow, its words to write over', () {
      expect(written('dated'), 'Lunch\n- [ ] [To-do] 📅 2026-09-29');
      expect(written('dated', 'Lunch\n- [ ] '), 'Lunch\n- [ ] [To-do] 📅 2026-09-29');
      // One undo takes the whole of it away.
      final view = viewOf('Lunch\n');
      writeRow(view, 'dated', now);
      view.undo_();
      expect(view.text, 'Lunch\n');
    });

    test('a note made a ticket, its front matter written for it, a status kept where it has one', () {
      expect(written('ticket', '# Fix the login loop\n\nIt loops.'), '---\ntype: ticket\nstatus: To do\n---\n# Fix the login loop\n\nIt loops.|');
      expect(written('ticket', '---\ntitle: "Plan"\nstatus: In review\n---\n# Plan'), '---\ntitle: "Plan"\nstatus: In review\ntype: ticket\n---\n# Plan|');
      expect(writeRow(viewOf('---\ntype: ticket\n---\n# Done already'), 'ticket', now), isFalse);
      expect(moreRows(gates()).map((row) => row.id), isNot(contains('ticket')));
      expect(moreRows(gates(ticket: true)).map((row) => row.id), contains('ticket'));
    });

    test('a board as Make a board writes one, its card named by an anchor nothing else has', () {
      expect(written('board', '- Tent ^first-card\n\n'), '- Tent ^first-card\n\n```board\nTo do: first-card-2\nDoing:\nDone:\n```\n\n- [ ] [First card] ^first-card-2');
    });

    test('a footnote, its number closing the words above and its line at the end', () {
      expect(written('footnote', 'Lunch  \n'), 'Lunch[^1]  \n\n[^1]: |');
      expect(written('footnote', 'Tent[^1]\n\n[^1]: Borrowed.\n\nStove\n'), 'Tent[^1]\n\n[^1]: Borrowed.\n\nStove[^2]\n\n[^2]: |');
      // With no words just above, or a table's row, it goes where the caret is.
      expect(written('footnote', 'Lunch\n\n'), 'Lunch\n\n[^1]\n\n[^1]: |');
      expect(written('footnote', '| a | b |\n'), '| a | b |\n[^1]\n\n[^1]: |');
    });

    test('each as one step to undo', () {
      for (final id in ['time', 'todo', 'table', 'board', 'footnote', 'heading']) {
        final view = viewOf('Lunch\n');
        writeRow(view, id, now);
        view.undo_();
        expect(view.text, 'Lunch\n', reason: id);
      }
    });
  });

  group('a note to link to', () {
    test('is any title a link can hold, but this note’s own, at most twelve', () {
      final titles = ['Lisbon', 'Lisbon, day two', 'Odd ] title', 'Pipe | title', 'Hash # title', for (var i = 0; i < 20; i += 1) 'Trip $i'];
      expect(linkableTitles(titles, 'Lisbon, day two', 'lis'), ['Lisbon']);
      expect(linkableTitles(titles, 'Lisbon', ''), hasLength(12));
    });

    test('is written at the caret as a link, and a canvas as a frame on a line of its own', () {
      final view = viewOf('Met at');
      writeNoteLink(view, 'Lisbon');
      expect(view.text, 'Met at [[Lisbon]]');
      final framed = viewOf('- ');
      writeCanvasFrame(framed, 'Cabin weekend');
      expect(framed.text, '![[Cabin weekend]]\n');
    });
  });

  group('a blank for the AI (docs/DESIGN.md §145)', () {
    test('writes {?} with the caret between its ? and }, a line of its own', () {
      expect(written('blank', ''), '{?|}\n');
      expect(written('blank', 'Lunch\n'), 'Lunch\n{?|}\n');
    });

    test('is an item’s words on an empty item, and keeps a blank line from a table, a list or a quote above', () {
      expect(written('blank', '- '), '- {?|}');
      expect(written('blank', '- [ ] '), '- [ ] {?|}');
      expect(written('blank', '| A | B |\n| --- | --- |\n| x | y |\n'), '| A | B |\n| --- | --- |\n| x | y |\n\n{?|}\n');
      expect(written('blank', '- Passport\n'), '- Passport\n\n{?|}\n');
    });

    test('fills every empty body cell of the table above, in one Undo, only where there is one', () {
      const table = '| Say | In Japanese |\n| --- | --- |\n| Thank you |  |\n| Excuse me | すみません |\n| Goodbye | |\n';
      expect(moreRows(gates(tableAbove: true)).map((r) => r.id), contains('blankCells'));
      expect(moreRows(gates()).map((r) => r.id), isNot(contains('blankCells')));
      final view = viewOf(table);
      expect(emptyCellsAbove(view.state, table.length), hasLength(2));
      expect(writeRow(view, 'blankCells', now), isTrue);
      expect(view.text, '| Say | In Japanese |\n| --- | --- |\n| Thank you | {?} |\n| Excuse me | すみません |\n| Goodbye | {?} |\n');
      expect(view.head, view.state.doc.length);
      view.undo_();
      expect(view.text, table);
      expect(emptyCellsAbove(viewOf('| A |\n| --- |\n| x |\n').state, 17), isNull);
    });
  });

  group('the gates this app adds, for rows whose blocks later stages draw', () {
    AddGates later({bool board = true, bool database = true, bool blank = true}) =>
        AddGates(picture: false, video: false, place: PlaceGate.absent, note: false, canvas: false, tableAbove: true, board: board, database: database, blank: blank);

    test('leave a board, a database and the blanks out, the rest in the web’s order', () {
      expect(topRows(later(board: false, database: false), now).map((row) => row.id), ['time', 'table', 'todo', 'more']);
      expect(moreRows(later(blank: false)).map((row) => row.id), isNot(anyOf(contains('blank'), contains('blankCells'))));
      expect(moreRows(later()).map((row) => row.id), containsAll(['blank', 'blankCells']));
    });

    test('make a board one write where there is no database to make a ticket board of', () {
      final board = topRows(later(database: false), now).firstWhere((row) => row.id == 'board');
      expect(board.step, isNull);
      expect(topRows(later(database: false), now).map((row) => row.id), isNot(contains('query')));
    });
  });
}
