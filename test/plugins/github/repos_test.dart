import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/github/repos.dart';

/// The pure parts of reading a repo: a port of `src/app/plugins/github/repos.test.ts`, case for case.
void main() {
  group('reading a GitHub project', () {
    test('takes a repo from the ways people paste one', () {
      expect(parseRepo('https://github.com/InfamousVague/attackfm'), (owner: 'InfamousVague', repo: 'attackfm'));
      expect(parseRepo('github.com/InfamousVague/glyph.git'), (owner: 'InfamousVague', repo: 'glyph'));
      expect(parseRepo('InfamousVague/glyph/tree/main/src'), (owner: 'InfamousVague', repo: 'glyph'));
      expect(parseRepo('not a repo'), isNull);
    });

    test('picks the files that say what the project is, README first', () {
      const paths = ['src/main.rs', 'docs/DESIGN.md', 'README.md', 'node_modules/x/README.md', 'AGENTS.md', 'package.json', 'docs/notes/deep.md', 'docs/setup.md', 'vendor/lib/README.md'];
      expect(pickFiles(paths), ['README.md', 'AGENTS.md', 'docs/DESIGN.md', 'package.json', 'docs/setup.md']);
    });

    test('outlines the top-level folders by size', () {
      expect(outline(['src/a.ts', 'src/b.ts', 'docs/x.md', 'README.md']), 'src/ (2 files)\ndocs/ (1 file)\nREADME.md');
    });

    test('keeps a README’s words for the fallback briefing, not its markup', () {
      const readme = '<picture><source srcset="/banner.png"></picture>\n\n# livekit-wakeword\n\n[![CI](https://x/badge.svg)](https://x)\n\nTrain a [wake word](https://docs) model.\n\n![diagram](d.png)';
      expect(readmeWords(readme), '# livekit-wakeword\n\nTrain a wake word model.');
    });
  });
}
