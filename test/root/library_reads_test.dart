// A note's place in its notebook as the root reads it for the note on screen (lib/root/library_reads.dart
// `placeInBook`): every notebook's places at once, made once for the notes as they are, where each asking walked
// the library (`bookOf`). The two are held to one answer here, note by note, over a library with every case the
// walk decided: a page of a notebook, of two, a notebook naming itself, a notebook that is a page of another, a
// journal's entries in the order they were written, and a Templates notebook, whose lines are templates' pages.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart' show bookOf;
import 'package:ghost_md/book/journal_months.dart' show inTimeOrder;
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/notes/own_templates.dart';
import 'package:ghost_md/root/library_reads.dart';

import '../core/make_note.dart';

void main() {
  /// What `placeInBook` was: a walk of the library for the one note.
  BookPlace? walked(LibraryReads reads, Note note) {
    final notes = reads.notes;
    final books = isTemplatePageBody(note.body) ? notes : notes.where((each) => !isTemplatesBody(each.body));
    final place = bookOf(books, noteTitle(note.body));
    return place == null ? null : inTimeOrder(place, reads.titled);
  }

  Object? said(BookPlace? place) => place == null ? null : (place.book.id, place.title, [for (final chapter in place.chapters) chapter.title].join(' | '), place.at, place.journal);

  List<Note> library() => [
        makeNote('trip', body: bookNoteBody('The trip', ['Packing', 'The route', 'Shared page', 'The trip', 'Small book']), updatedAt: 90),
        makeNote('second', body: bookNoteBody('Second book', ['Shared page', 'Only here']), updatedAt: 80),
        makeNote('small', body: bookNoteBody('Small book', ['A page of the small book']), updatedAt: 70),
        makeNote('packing', body: '# Packing\n\nsocks', updatedAt: 60),
        makeNote('route', body: '# The route\n\nnorth', updatedAt: 50),
        makeNote('shared', body: '# Shared page\n\nin two books', updatedAt: 40),
        makeNote('only', body: '# Only here\n\nwords', updatedAt: 30),
        makeNote('alone', body: '# In no book\n\nwords', updatedAt: 20),
        makeNote('blank', body: '', updatedAt: 10),
        makeNote('templates', body: templatesNotebookBody(['Meeting', 'Packing']), updatedAt: 9),
        makeNote('meeting-page', body: newTemplatePageBody('Meeting'), updatedAt: 8),
        makeNote('packing-page', body: newTemplatePageBody('Packing'), updatedAt: 7),
        makeNote('meeting-note', body: '# Meeting\n\nminutes', updatedAt: 6),
      ];

  test('answers every note what a walk of the library answered', () {
    for (final notes in [library(), SampleLibrary.seeded().value]) {
      final reads = LibraryReads(shown: () => notes, all: () => notes);
      var placed = 0;
      for (final note in notes) {
        final place = reads.placeInBook(note);
        expect(said(place), said(walked(reads, note)), reason: 'the place of "${noteTitle(note.body)}" (${note.id})');
        if (place != null) placed += 1;
      }
      expect(placed, greaterThan(0));
    }
  });

  test('the cases: the first notebook that names a page, no notebook a page of itself, a Templates notebook only for a template\'s page', () {
    final notes = library();
    final reads = LibraryReads(shown: () => notes, all: () => notes);
    Note of(String id) => notes.firstWhere((note) => note.id == id);
    expect(reads.placeInBook(of('packing'))!.book.id, 'trip', reason: 'a note of the person\'s is never a Templates notebook\'s line');
    expect(reads.placeInBook(of('shared'))!.book.id, 'trip', reason: 'in two books, the first');
    expect(reads.placeInBook(of('only'))!.book.id, 'second');
    expect(reads.placeInBook(of('trip')), isNull, reason: 'a notebook that names itself is not its own page');
    expect(reads.placeInBook(of('small'))!.book.id, 'trip', reason: 'a notebook can be a page of another');
    expect(reads.placeInBook(of('alone')), isNull);
    expect(reads.placeInBook(of('blank')), isNull);
    expect(reads.placeInBook(of('meeting-page'))!.book.id, 'templates', reason: 'a template\'s page is its Templates notebook\'s');
    expect(reads.placeInBook(of('meeting-note')), isNull, reason: 'and a note of the person\'s by a template\'s name is not');
  });

  test('is looked up once for a note while the notes stand, and again once they changed', () {
    var notes = library();
    final reads = LibraryReads(shown: () => notes, all: () => notes);
    final packing = notes.firstWhere((note) => note.id == 'packing');
    final first = reads.placeInBook(packing);
    expect(identical(reads.placeInBook(packing), first), isTrue);
    // The note as an open screen holds it, with the words it was opened with: asked of by its own words.
    final opened = makeNote('packing', body: '# The route\n\nrenamed since', updatedAt: 60);
    expect(reads.placeInBook(opened)!.at, 1);
    // The notebook loses the page: told the notes changed, the place is read again.
    notes = [
      makeNote('trip', body: bookNoteBody('The trip', ['The route']), updatedAt: 91),
      ...notes.where((note) => note.id != 'trip'),
    ];
    expect(identical(reads.placeInBook(packing), first), isTrue, reason: 'not until it is told');
    reads.changed();
    expect(reads.placeInBook(packing), isNull);
  });
}
