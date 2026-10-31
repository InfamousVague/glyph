import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal.dart' show stampOf;
import 'package:ghost_md/book/tickets.dart' show newTicketBody, notebookFinder;
import 'package:ghost_md/canvas/json_canvas.dart' show canvasOf, isCanvasBody;
import 'package:ghost_md/core/book.dart' show isBookBody, isJournalBody;
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/geotag.dart' show geoTagOf;
import 'package:ghost_md/core/link_index.dart';
import 'package:ghost_md/core/note_facts.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/query/records.dart' show QueryNote, libraryOf;
import 'package:ghost_md/core/title_key.dart' show titleKey;
import 'package:ghost_md/editor/tickets/ticket_rows.dart' show otherKeys, panelRows;

import 'make_note.dart';

/// The two shapes of a note's front matter (docs/MARKDOWN_FIRST.md §11; Matt, 2026-10-31: "one block, phased"). A
/// note with page properties has been two `---` blocks on disk, the library's and then the page's, and the page's is
/// the block at the top of the body every reader here sees. The other shape is ONE block with the library's keys
/// (`id`, `created`, `pinned`, `archived`, `source`) beside the page's, in any order, as Obsidian writes a note's
/// properties and as a merged body will arrive once the writers switch. Every reader must answer the same for both:
/// the readers in lib/core/front_matter.dart and lib/core/properties.dart that everything else asks, and the kinds
/// of note built on them (a ticket, a notebook, a journal, a canvas, a geotagged note, a template's page, the link
/// index, the query engine). The ticket's key is the one key the shapes fight over, so it is read as `issue:` too,
/// the key other tools use, and never from a library's `id:`.
void main() {
  /// The page's block as it has always been, and the same keys in one block with the library's around and between them.
  const pageOnly = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\ndue: 2026-10-03\nlabels: [bug, ui]\n---\n# Fix the login loop\n\nIt loops.\n';
  const merged =
      '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\ncreated: 2026-09-14T10:32:10.123Z\nissue: GHO-12\nstatus: In progress\npinned: true\nassignee: Sam\nsource: capture\ndue: 2026-10-03\nlabels: [bug, ui]\narchived: 2026-09-15T08:00:00.000Z\n---\n# Fix the login loop\n\nIt loops.\n';

  group('the library’s keys', () {
    test('are never the page’s properties, in any case, except a ticket’s own id', () {
      expect(libraryKeys, <String>{'id', 'created', 'updated', 'source', 'pinned', 'archived', 'trashed'});
      for (final key in libraryKeys) {
        expect(isLibraryProperty(key, 'anything'), isTrue, reason: key);
        expect(isLibraryProperty(key.toUpperCase(), 'anything'), isTrue, reason: key);
      }
      expect(isLibraryProperty('id', 'GHO-12'), isFalse, reason: 'a ticket’s key is the page’s');
      expect(isLibraryProperty('id', 'gho-12'), isFalse);
      expect(isLibraryProperty('id', '7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6'), isTrue);
      expect(isLibraryProperty('issue', 'GHO-12'), isFalse);
      expect(isLibraryProperty('status', 'Done'), isFalse);
      expect(isTicketKey('GHO-12') && isTicketKey(' a1-999999 '), isTrue);
      expect(isTicketKey('7c1e') || isTicketKey('G-1') || isTicketKey('GHO-0') || isTicketKey('GHO-1234567') || isTicketKey(null), isFalse);
      expect(issueKey, same(ticketKeyPattern), reason: 'one pattern for the ticket’s key');
    });

    test('are left out of the page’s properties, which read the same from either shape', () {
      final fromPage = propertiesOf(pageOnly);
      final fromMerged = propertiesOf(merged);
      expect([for (final p in fromPage) p.key], ['type', 'id', 'status', 'assignee', 'due', 'labels']);
      expect([for (final p in fromMerged) p.key], ['type', 'issue', 'status', 'assignee', 'due', 'labels']);
      expect([for (final p in fromMerged) p.value], [for (final p in fromPage) p.value]);
      // The line each is on is the body's own, so a panel edits the right line in either shape.
      expect(fromMerged.map((p) => p.line), [2, 4, 5, 7, 9, 10]);
    });
  });

  group('the ticket’s key', () {
    test('is read from issue:, or from an id: that is one, never from the library’s id', () {
      expect(ticketKeyValue(pageOnly), 'GHO-12');
      expect(ticketKeyValue(merged), 'GHO-12');
      expect(ticketKeyValue('---\ntype: ticket\nissue: gho-3\nid: GHO-12\n---\n'), 'gho-3', reason: 'issue: outranks id:');
      expect(ticketKeyValue('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\nstatus: Done\n---\n'), isNull, reason: 'a merged ticket with no key has none');
      expect(ticketKeyValue('---\nid: 42\n---\n'), isNull);
      expect(ticketKeyValue('# No front matter\n'), isNull);
      expect(ticketIdOf(pageOnly), 'GHO-12');
      expect(ticketIdOf(merged), 'GHO-12');
      expect(ticketIdOf('---\ntype: ticket\nissue: gho-3\n---\n'), 'GHO-3');
      expect(ticketIdOf('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\n---\n'), isNull);
    });

    test('is written under id: as today, and under issue: where the block’s id: is the library’s', () {
      expect(ticketKeyName(pageOnly), 'id');
      expect(ticketKeyName('---\ntype: ticket\nstatus: To do\n---\n# New\n'), 'id');
      expect(ticketKeyName('# No front matter\n'), 'id');
      expect(ticketKeyName(merged), 'issue', reason: 'issue: is already there');
      expect(ticketKeyName('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\n---\n'), 'issue', reason: 'the id: is the library’s');
      expect(withTicketKey('---\ntype: ticket\nstatus: To do\n---\n# New\n', 'GHO-13'), '---\ntype: ticket\nstatus: To do\nid: GHO-13\n---\n# New\n');
      const oneBlock = '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\nstatus: To do\n---\n# New\n';
      final keyed = withTicketKey(oneBlock, 'GHO-13');
      expect(keyed, '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\nstatus: To do\nissue: GHO-13\n---\n# New\n', reason: 'the note id is not written over');
      expect(ticketIdOf(keyed), 'GHO-13');
      expect(withTicketKey(merged, 'GHO-14'), merged.replaceFirst('issue: GHO-12', 'issue: GHO-14'));
      // A new ticket's body, from a template that opens with a merged block, takes the same path.
      final fresh = newTicketBody('New', id: 'GHO-13', statuses: defaultStatuses, words: oneBlock);
      expect(fresh, contains('issue: GHO-13\n'));
      expect(fresh, isNot(contains('id: GHO-13')));
      expect(newTicketBody('New', id: 'GHO-13', statuses: defaultStatuses), '---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# New\n\n');
    });
  });

  group('a ticket', () {
    test('reads the same from either shape, and its minimum is type: ticket', () {
      final a = ticketOf(pageOnly)!;
      final b = ticketOf(merged)!;
      expect(b, a);
      expect(b.id, 'GHO-12');
      expect(b.status, 'In progress');
      expect(b.assignee, 'Sam');
      expect(b.due, '2026-10-03');
      expect(b.labels, ['bug', 'ui']);
      expect(isTicket(merged), isTrue);
      // What makes a file a ticket: `type: ticket` (or `type: epic`), in any case, in whichever block shape. A block
      // with a status and a due day alone is a page with properties (a Hugo draft, a journal's day), not a ticket.
      expect(isTicket('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\nstatus: To do\ndue: 2026-11-01\n---\n'), isFalse);
      expect(isTicket('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\nType: Ticket\n---\n'), isTrue);
      final bare = ticketOf('---\ntype: ticket\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\n---\n# Bare\n')!;
      expect((bare.id, bare.status, bare.category), (null, null, StatusCategory.todo), reason: 'every other field is optional');
      // Obsidian's properties for a ticket, one block, no library id yet.
      final obsidian = ticketOf('---\ntype: ticket\nstatus: Done\ndue: 2026-11-01\ntags:\n  - bug\n---\n# From Obsidian\n')!;
      expect((obsidian.id, obsidian.status, obsidian.category, obsidian.due), (null, 'Done', StatusCategory.done, '2026-11-01'));
    });

    test('is the same note’s facts, placed in a notebook and found by its key, in either shape', () {
      NoteFacts.debugForget();
      final page = makeNote('page', body: pageOnly);
      final one = makeNote('one', body: merged);
      expect(NoteFacts.of(page).ticketKey, 'GHO-12');
      expect(NoteFacts.of(one).ticketKey, 'GHO-12');
      expect(NoteFacts.of(one).isTicket, isTrue);
      expect(NoteFacts.of(one).ticket, NoteFacts.of(page).ticket);
      expect(NoteFacts.of(makeNote('plain', body: '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\n---\n# Plain\n')).ticketKey, isNull);
      final book = makeNote('book', body: '---\nid: 1111aaaa-4b5c-4d6e-8f90-a1b2c3d4e5f6\nbook: true\nkey: GHO\nstatuses: [Ideas, Building, Live]\n---\n# Ghost\n');
      final find = notebookFinder([book, page, one]);
      expect(find(page)?.id, 'book');
      expect(find(one)?.id, 'book', reason: 'the notebook whose key the merged ticket carries');
    });

    test('shows the same panel rows and quiet keys in either shape', () {
      expect(panelRows(merged), panelRows(pageOnly));
      expect(otherKeys(merged), otherKeys(pageOnly));
      expect(otherKeys(merged), isEmpty, reason: 'neither the library’s keys nor issue: are "other" keys');
      expect(otherKeys('---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ntype: ticket\nissue: GHO-1\ntopic: fold\n---\n'), ['topic']);
    });
  });

  group('every other kind of note', () {
    const uuid = 'id: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ncreated: 2026-09-14T10:32:10.123Z\npinned: true\n';

    test('a notebook, a journal and a template’s page', () {
      const book = '---\nbook: true\nkey: GHO\n---\n# Ghost\n\n- [[GHO-12]]\n';
      final one = '---\n${uuid}book: true\nkey: GHO\n---\n# Ghost\n\n- [[GHO-12]]\n';
      expect(isBookBody(one), isTrue);
      expect(notebookKey(one), notebookKey(book));
      expect(NoteFacts.read(one).isBook, isTrue);
      expect(NoteFacts.read(one).chapters.map((c) => c.title), NoteFacts.read(book).chapters.map((c) => c.title));
      final journal = '---\nbook: true\njournal: true\n$uuid---\n# Days\n';
      expect(isJournalBody(journal), isTrue);
      expect(NoteFacts.read(journal).isJournal, isTrue);
      const entry = '---\ndate: 2026-10-03T09:30\n---\n# Morning\n';
      final entryOne = '---\n${uuid}date: 2026-10-03T09:30\n---\n# Morning\n';
      expect(stampOf(entryOne, 0), stampOf(entry, 0));
      expect(NoteFacts.read('---\n${uuid}title: "Meeting"\ntemplates: page\n---\n# {{title}}\n').isTemplatePage, isTrue);
      expect(NoteFacts.read('---\n${uuid}book: true\ntemplates: true\n---\n# Templates\n').isTemplatesBook, isTrue);
    });

    test('a canvas and a geotagged note', () {
      const canvas = '---\ntitle: "Map"\n---\n{ "nodes": [{ "id": "a", "type": "text", "text": "Hi", "x": 0, "y": 0, "width": 100, "height": 50 }], "edges": [] }\n';
      final one = '---\n${uuid}title: "Map"\n---\n{ "nodes": [{ "id": "a", "type": "text", "text": "Hi", "x": 0, "y": 0, "width": 100, "height": 50 }], "edges": [] }\n';
      expect(isCanvasBody(one), isTrue);
      expect(canvasOf(one)?.nodes.length, canvasOf(canvas)?.nodes.length);
      expect(NoteFacts.read(one).isCanvas, isTrue);
      expect(NoteFacts.read(one).canvasCards, 1);
      const placed = '---\nlocation: 38.7223, -9.1393\nplace: Lisbon\n---\n# Trip\n';
      final placedOne = '---\nlocation: 38.7223, -9.1393\n${uuid}place: Lisbon\n---\n# Trip\n';
      final tag = geoTagOf(placedOne)!;
      final tagged = geoTagOf(placed)!;
      expect((tag.lat, tag.lon, tag.place), (tagged.lat, tagged.lon, tagged.place));
    });

    test('the link index and the query engine', () {
      final notes = [
        makeNote('ticket', body: merged),
        // A one-block ticket with no library id yet (as another app writes one): its `id:` is the ticket's.
        makeNote('other', body: '---\ncreated: 2026-09-14T10:32:10.123Z\npinned: true\ntype: ticket\nid: GHO-13\nstatus: Done\n---\n# Other\n'),
        makeNote('plain', body: '---\n$uuid---\n# Plain\n\nSee [[GHO-12]] and [[GHO-13]].\n'),
      ];
      final index = LinkIndex.build([for (final note in notes) (id: note.id, body: note.body, path: note.path, updatedAt: note.updatedAt)]);
      expect(index.resolve(titleKey('GHO-12')), 'ticket', reason: 'the merged ticket is found by its issue:');
      expect(index.resolve(titleKey('GHO-13')), 'other', reason: 'and one by an id: that is a key');
      expect(index.resolve(titleKey('7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6')), isNull, reason: 'the library’s id names nothing');
      final library = libraryOf([for (final note in notes) QueryNote.of(note)]);
      expect(library.byTicket['GHO-12']?.id, 'ticket');
      expect(library.byTicket['GHO-13']?.id, 'other');
      final record = library.records.firstWhere((record) => record.noteId == 'ticket' && record.ticket != null);
      expect(record.ticket?.id, 'GHO-12');
      expect(record.props.keys, isNot(contains('created')), reason: 'the library’s keys are not a record’s properties');
      expect(record.props.keys, isNot(contains('pinned')));
      expect(record.props['issue'], 'GHO-12');
      expect(record.props['status'], 'In progress');
    });
  });

  group('the writer', () {
    const two = '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ncreated: 2026-09-14T10:32:10.123Z\n---\n---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Two\n\nWords.\n';

    tearDown(() => FrontMatter.oneBlock = false);

    test('is off: a two-block body stays two blocks, and either shape round-trips byte for byte', () {
      expect(FrontMatter.oneBlock, isFalse, reason: 'nothing ships writing one block in this slice');
      expect(withFrontMatterValue(pageOnly, 'status', 'In progress'), pageOnly);
      expect(withFrontMatterValue(merged, 'status', 'In progress'), merged);
      expect(withProperty(merged, 'status', 'In progress'), merged);
      expect(withFrontMatterValue(two, 'id', '7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6'), two, reason: 'the first block is the one written into, as it was');
      expect(mergedBlocks(two), '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ncreated: 2026-09-14T10:32:10.123Z\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Two\n\nWords.\n');
      expect(mergedBlocks(pageOnly), pageOnly);
      expect(mergedBlocks(merged), merged);
      expect(mergedBlocks('# Plain\n'), '# Plain\n');
      expect(mergedBlocks('---\na: 1\n---\n'), '---\na: 1\n---\n');
      // A page key written into a merged body lands in its one block, the library's keys untouched, no second block made.
      final written = withProperty(merged, 'status', 'Done');
      expect(written, merged.replaceFirst('status: In progress', 'status: Done'));
      expect(written.split('\n').where((line) => line == '---').length, 2);
      expect(withProperty(merged, 'estimate', '3'), merged.replaceFirst('archived: 2026-09-15T08:00:00.000Z\n---', 'archived: 2026-09-15T08:00:00.000Z\nestimate: 3\n---'));
    });

    test('is on: a body with two blocks is written as one, and a body with one as it was', () {
      FrontMatter.oneBlock = true;
      expect(withFrontMatterValue(two, 'status', 'Done'), '---\nid: 7c1e2f3a-4b5c-4d6e-8f90-a1b2c3d4e5f6\ncreated: 2026-09-14T10:32:10.123Z\ntype: ticket\nid: GHO-12\nstatus: Done\n---\n# Two\n\nWords.\n');
      expect(withFrontMatterValue(pageOnly, 'status', 'In progress'), pageOnly);
      expect(withFrontMatterValue(merged, 'status', 'In progress'), merged);
      expect(withProperty('# Plain\n', 'status', 'Done'), '---\nstatus: Done\n---\n# Plain\n');
      final once = withFrontMatterValue(two, 'status', 'Done');
      expect(withFrontMatterValue(once, 'status', 'Done'), once, reason: 'merged once, then as it was');
    });
  });
}
