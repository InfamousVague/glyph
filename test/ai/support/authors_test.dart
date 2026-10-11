// A port of src/app/core/authors.test.ts, case for case.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/support/authors.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/properties.dart' show withFrontMatterValue;

void main() {
  group('a note’s authors', () {
    test('are the front matter’s authors line, in order, each once', () {
      expect(authorsOf('---\nauthors: matt, Claude, claude\n---\n# Trip'), ['matt', 'Claude']);
      expect(authorsOf('# Trip\n\nNo front matter.'), isEmpty);
    });

    test('take an AI after the owner on a note that named none, and keep the words and the other keys', () {
      final plain = withAuthor('# Trip\n\nWords.', 'Claude', 'matt');
      expect(plain, '---\nauthors: matt, Claude\n---\n# Trip\n\nWords.');
      final titled = withAuthor('---\ntitle: "Map"\n---\n{"nodes":[]}', 'Claude', 'matt');
      expect(frontMatterValue(titled, 'title'), 'Map');
      expect(authorsOf(titled), ['matt', 'Claude']);
      expect(titled.endsWith('{"nodes":[]}'), isTrue);
    });

    test('don’t take a name twice, and a note already by others gains the AI last', () {
      final once = withAuthor('# A', 'Claude', 'matt');
      expect(withAuthor(once, 'claude', 'matt'), once);
      expect(authorsOf(withAuthor('---\nauthors: sam\n---\n# A', 'Claude', 'matt')), ['sam', 'Claude']);
    });

    test('across a book are its own and its chapters’, first met first', () {
      expect(authorsAcross(['---\nauthors: matt, Claude\n---\n# Book', '# Plain chapter', '---\nauthors: matt, Gemini\n---\n# C']), ['matt', 'Claude', 'Gemini']);
    });
  });

  group('an AI’s name', () {
    test('is what it says it is, else its app’s name read as the product, else nothing', () {
      expect(aiName('Claude Opus', (name: 'claude-ai', title: null)), 'Claude Opus');
      expect(aiName(null, (name: 'claude-ai', title: 'Claude')), 'Claude');
      expect(aiName(null, (name: 'openai-mcp', title: null)), 'ChatGPT');
      expect(aiName(null, (name: 'some-agent', title: null)), 'some-agent');
      expect(aiName(null, null), isNull);
      expect(aiName('A, B', null), 'A B');
    });
  });

  // The web's file keeps this case of core/frontMatter.ts with the authors'; `withFrontMatterValue` is
  // lib/core/properties.dart's here.
  group('a front matter key written', () {
    test('replaces, adds, or takes off one key, and front matter that held only it', () {
      expect(withFrontMatterValue('---\nbook: true\n---\n# B', 'authors', 'a, b'), '---\nbook: true\nauthors: a, b\n---\n# B');
      expect(withFrontMatterValue('---\nauthors: a\n---\n# B', 'authors', null), '# B');
      expect(
        withFrontMatterValue('---\nbook: true\nauthors: a\n---\n# B', 'Authors', 'c'),
        '---\nbook: true\nauthors: c\n---\n# B'.replaceFirst('authors: c', 'Authors: c'),
      );
    });
  });
}
