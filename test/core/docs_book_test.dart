import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/docs_book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/properties.dart' show isTicket;

/// Docs, a notebook kept as documentation (lib/core/docs_book.dart; Matt, 2026-10-31: "There should be a specific type
/// of notebook for docs that we made"): `book: true` and `type: docs`, its `## ` parts, its pages numbered straight
/// through, a page added under its part, and every reader of a notebook going through it part by part.
void main() {
  const index = '---\ntitle: "Field guide"\nbook: true\ntype: docs\n---\n# Field guide\n\nHow the garden works.\n\n## Getting started\n\n1. [[Welcome]]\n2. [[Install]]\n\n## Using it\n\n3. [[Planting]]\n4. [[Watering]]\n';

  group('the type', () {
    test('is a notebook that says type: docs, in any case, and nothing that only looks like one', () {
      expect(isDocsBody(index), isTrue);
      expect(isBookBody(index), isTrue);
      expect(isDocsBody('---\nbook: yes\ntype: Docs\n---\n# A\n'), isTrue);
      expect(isDocsBody('---\ntype: docs\n---\n# Not a book\n'), isFalse);
      expect(isDocsBody('---\nbook: true\n---\n# Plain\n'), isFalse);
      // A teamspace home's `docs:` is its read-or-edit setting, not this.
      expect(isDocsBody('---\nbook: true\ndocs: read\n---\n# Home\n'), isFalse);
    });

    test('is read as no ticket, journal or templates notebook', () {
      expect(isTicket(index), isFalse);
      expect(isJournalBody(index), isFalse);
      expect(isTemplatesBook(index), isFalse);
    });
  });

  group('docsBookBody', () {
    test('writes the index: its name, what it is about, and each part with its pages numbered straight through', () {
      final body = docsBookBody('Field guide', about: 'How the garden works.', parts: const [
        DocsPart('Getting started', ['Welcome', 'Install']),
        DocsPart('Using it', ['Planting', 'Watering']),
      ]);
      expect(body, index);
      expect([for (final c in chaptersOf(body)) c.title], ['Welcome', 'Install', 'Planting', 'Watering']);
    });

    test('keeps a part with no pages yet as its heading alone', () {
      final body = docsBookBody('Handbook', parts: const [DocsPart(docsStarterPart)]);
      expect(body, '---\ntitle: "Handbook"\nbook: true\ntype: docs\n---\n# Handbook\n\n## Getting started\n');
      expect(docsParts(body), const [DocsPart('Getting started')]);
    });
  });

  group('docsParts', () {
    test('reads each ## heading as a part with the pages under it, the ones before any heading a part of no title', () {
      expect(docsParts(index), const [
        DocsPart('Getting started', ['Welcome', 'Install']),
        DocsPart('Using it', ['Planting', 'Watering']),
      ]);
      expect(docsParts('---\nbook: true\ntype: docs\n---\n# A\n\n1. [[Loose]]\n\n## Later\n\n2. [[After]]\n'), const [
        DocsPart('', ['Loose']),
        DocsPart('Later', ['After']),
      ]);
    });

    test('reads the public Ghost.md Docs by its parts', () {
      // docs/book/index.md's own shape.
      const book = '---\ntitle: "Ghost.md Docs"\nbook: true\ntype: docs\n---\n# Ghost.md Docs\n\nIntro.\n\n## Part I: Getting started\n\n1. [[Welcome to Ghost.md]]\n2. [[Install Ghost.md]]\n\n## Part II: Writing\n\n3. [[Markdown and the Ghost.md marks]]\n';
      expect([for (final p in docsParts(book)) p.title], ['Part I: Getting started', 'Part II: Writing']);
      expect(docsPartHeads(book, chaptersOf(book)), ['Part I: Getting started', null, 'Part II: Writing']);
    });
  });

  group('withDocsPage', () {
    test('adds a page last in its part and numbers the rest again', () {
      final next = withDocsPage(index, 'getting STARTED', 'Your first bed');
      expect(next, contains('1. [[Welcome]]\n2. [[Install]]\n3. [[Your first bed]]\n\n## Using it\n\n4. [[Planting]]\n5. [[Watering]]\n'));
      expect(docsParts(next).first.pages, ['Welcome', 'Install', 'Your first bed']);
    });

    test('puts it at the place asked, from 1', () {
      final first = withDocsPage(index, 'Using it', 'Tools', position: 1);
      expect(docsParts(first)[1].pages, ['Tools', 'Planting', 'Watering']);
      expect(first, contains('## Using it\n\n3. [[Tools]]\n4. [[Planting]]\n5. [[Watering]]\n'));
      final far = withDocsPage(index, 'Using it', 'Last', position: 99);
      expect(docsParts(far)[1].pages.last, 'Last');
    });

    test('makes a part the index has not got, at the end', () {
      final next = withDocsPage(index, 'Troubleshooting', 'Pests');
      expect(next, endsWith('4. [[Watering]]\n\n## Troubleshooting\n\n5. [[Pests]]\n'));
      expect([for (final p in docsParts(next)) p.title], ['Getting started', 'Using it', 'Troubleshooting']);
    });

    test('fills a part that has no pages yet, under its heading', () {
      final empty = docsBookBody('Handbook', parts: const [DocsPart('Getting started'), DocsPart('Later')]);
      final next = withDocsPage(empty, 'Getting started', 'Welcome');
      expect(next, contains('## Getting started\n\n1. [[Welcome]]\n\n## Later\n'));
      expect(withDocsPage(next, 'Later', 'After'), endsWith('## Later\n\n2. [[After]]\n'));
    });

    test('leaves a page already in the index where it is, and a bullet index bullets', () {
      expect(withDocsPage(index, 'Using it', 'welcome'), index);
      const bullets = '---\nbook: true\ntype: docs\n---\n# B\n\n## One\n\n- [[A]]\n';
      expect(withDocsPage(bullets, 'One', 'B'), contains('- [[A]]\n- [[B]]\n'));
    });
  });

  group('a page', () {
    test('is its heading, its words and its icon, the heading never twice', () {
      expect(docsPageBody('Install', 'Download it.', icon: '📦'), '---\nicon: 📦\n---\n# Install\n\nDownload it.\n');
      expect(docsPageBody('Install', '# Install\n\nDownload it.'), '# Install\n\nDownload it.\n');
    });

    test('is refused a title a link could not name', () {
      expect(docsTitleProblem('Install'), isNull);
      expect(docsTitleProblem('A [draft]'), isNotNull);
      expect(docsTitleProblem('Q&A #2'), isNotNull);
      expect(docsTitleProblem('  '), isNotNull);
      expect(docsTitleProblem('x' * 121), isNotNull);
    });
  });

  test("the page tree's previous and next go through the pages part by part, as the index lists them", () {
    var clock = 0;
    Note at(String id, String path, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: clock += 1, path: path);
    final tree = PageTree.build([
      at('guide', 'Inbox/Field guide.md', index),
      // Made in another order than the index's: the index decides.
      at('water', 'Inbox/Watering.md', '# Watering\n'),
      at('plant', 'Inbox/Planting.md', '# Planting\n'),
      at('install', 'Inbox/Install.md', '# Install\n'),
      at('welcome', 'Inbox/Welcome.md', '---\nicon: 👋\n---\n# Welcome\n'),
    ]);
    expect([for (final n in tree.nodeOf('guide')!.children) n.title], ['Welcome', 'Install', 'Planting', 'Watering']);
    expect(tree.nodeOf('install')!.next?.title, 'Planting');
    expect(tree.nodeOf('plant')!.previous?.title, 'Install');
    expect(tree.nodeOf('welcome')!.icon, isNotNull);
  });
}
