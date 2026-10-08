// A port of src/app/format/pipeline.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/body_hash.dart';
import 'package:ghost_md/format/modes.dart';
import 'package:ghost_md/format/pipeline.dart';

void main() {
  group('a note as the model sees it', () {
    tearDown(() => usePluginContext(noPlugins));

    test('hashes a note with no project as its body alone', () {
      const body = '# Trip\n\ncall the plumber';
      expect(noteHash('no-such-note', body), bodyHash(body));
      expect(noteContext('no-such-note'), isNull);
    });

    test('hashes a note a plugin gave context for with the context’s version, handed in or set for the app', () {
      // Not a case of the web's (its registry is the page's own): the parameter that stands for the registry here.
      const body = '# Trip\n\ncall the plumber';
      final projects = PluginContext(contextFor: (id) => id == 'n1' ? 'The trip project.' : null, contextVersion: (id) => id == 'n1' ? 7 : 0);
      expect(noteHash('n1', body, plugins: projects), bodyHash('$body\u0000project:7'));
      expect(noteHash('n2', body, plugins: projects), bodyHash(body));
      expect(noteContext('n1', plugins: projects), 'The trip project.');
      usePluginContext(projects);
      expect(noteHash('n1', body), bodyHash('$body\u0000project:7'));
      expect(noteContext('n1'), 'The trip project.');
      expect(noteContext('n2'), isNull);
    });

    test('swaps links for tokens the model can copy, and puts them back as the lines land and once at the end', () {
      final prepared = prepareNote('see [the docs](https://example.com/docs) now\n', RunKind.format);
      expect(prepared.prompt, contains('[the docs](link-1)'));
      expect(prepared.prompt, isNot(contains('https://example.com')));
      expect(prepared.restore('# Notes\nsee [the docs](link-1) no', false), '# Notes\nsee [the docs](https://example.com/docs) no');
      expect(prepared.restore('* see [the docs](link-1) now', true), '- see [the docs](https://example.com/docs) now\n');
    });

    test('takes off a code fence a model put round its whole answer, with or without a language, and the blank edges', () {
      final restore = prepareNote('# Trip\n', RunKind.format).restore;
      expect(restore('```markdown\n# Trip\n\n- call Sam\n```', true), '# Trip\n\n- call Sam\n');
      expect(restore('\n\n```\n# Trip\n```\n\n', true), '# Trip\n');
      expect(restore('\n\n# Trip\n\n\n', true), '# Trip\n');
    });

    test('leaves a code block inside the answer where it is', () {
      final restore = prepareNote('# Setup\n', RunKind.format).restore;
      const answer = '# Setup\n\n```bash\nnpm run dev\n```\n\nThen open the page.';
      expect(restore(answer, true), '$answer\n');
    });

    test('keeps a place whole through the model, its coordinates never shown to it, and lets a summary leave it out', () {
      const place = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
      final prepared = prepareNote('# Lisbon\n\nLunch\n\n$place\n', RunKind.format);
      expect(prepared.prompt, contains('![place-1](place)'));
      expect(prepared.prompt, isNot(contains('geo:')));
      expect(prepared.restore('# Lisbon\n\nLunch by the river.\n\n![place-1](place)\n', true), '# Lisbon\n\nLunch by the river.\n\n$place\n');
      expect(prepared.restore('# Lisbon\n\nLunch by the river.\n', true), '# Lisbon\n\nLunch by the river.\n\n$place\n');
      expect(prepareNote('# Lisbon\n\n$place\n', RunKind.summarize).restore('# Lisbon\n\nA lunch.\n', true), '# Lisbon\n\nA lunch.\n');
    });

    test('keeps a table whole through the model', () {
      const table = '| a | b |\n| - | - |\n| 1 | 2 |';
      final prepared = prepareNote('# T\n\n$table\n', RunKind.format);
      expect(prepared.prompt, contains('![table-1](table)'));
      expect(prepared.restore('# T\n\n![table-1](table)\n', true), '# T\n\n$table\n');
    });
  });
}
