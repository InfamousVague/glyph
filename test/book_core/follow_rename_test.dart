import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/follow_rename.dart';
import 'package:ghost_md/core/book.dart' show withChapterRenamed;
import 'package:ghost_md/core/sample_library.dart';

/// A page renamed keeps its place (lib/book/follow_rename.dart, lib/core/book.dart `withChapterRenamed`), case for
/// case with the web's `book/followRename.test.ts`. The store is the library kept in memory (lib/core/sample_library),
/// as the page's tests have the store's browser half.
const String book = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n1. [[Introduction]]\n2. [[Trees#Oaks]] the long one\n3. [[Birds|the birds]]\n\nMore in [[Trees]] as it grows.\n';

void main() {
  group('a chapter renamed in its index', () {
    test('names the new title on its line, its heading, alias and words kept, and leaves links in passing alone', () {
      final renamed = withChapterRenamed(book, 'Trees', 'Woodland');
      expect(renamed, contains('2. [[Woodland#Oaks]] the long one'));
      expect(renamed, contains('More in [[Trees]] as it grows.'));
      expect(withChapterRenamed(book, 'birds', 'Garden birds'), contains('3. [[Garden birds|the birds]]'));
      expect(withChapterRenamed(book, 'Trees', '  '), book);
    });
  });

  group('a page renamed keeps its place', () {
    test('in every notebook and journal that lists it', () async {
      final library = SampleLibrary(const []);
      await library.createNote(book, id: 'book');
      await library.createNote('---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[Introduction]]\n', id: 'journal');
      await library.createNote('# Introduction\n\nWhy this guide.', id: 'page');
      expect(await followRename(library, 'page', 'Introduction', 'Before you start'), 2);
      expect((await library.get('book'))!.body, contains('1. [[Before you start]]'));
      expect((await library.get('journal'))!.body, contains('- [[Before you start]]'));
    });

    test('never while another note still has the old title: the line means that one', () async {
      final library = SampleLibrary(const []);
      await library.createNote(book, id: 'book');
      await library.createNote('# Introduction\n\nMine.', id: 'page');
      await library.createNote('# Introduction\n\nTheirs.', id: 'other');
      expect(await followRename(library, 'page', 'Introduction', 'Before you start'), 0);
      expect((await library.get('book'))!.body, contains('1. [[Introduction]]'));
    });

    test('follows nothing for a name that is the same, or is no name', () async {
      // Not a web case of its own: the function's first line, held.
      final library = SampleLibrary(const []);
      await library.createNote(book, id: 'book');
      expect(await followRename(library, 'page', 'Introduction', 'introduction'), 0);
      expect(await followRename(library, 'page', 'Introduction', '  '), 0);
    });
  });
}
