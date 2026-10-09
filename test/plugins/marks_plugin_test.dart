import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/registry.dart';

import 'support.dart';

/// The Marks plugin as a plugin (lib/plugins/marks_plugin.dart): the cases of `src/app/plugins/marks/marks.test.ts`
/// that are about the plugin and the registry. The rest of that file (how each mark parses, what the redaction
/// draws, the highlight's colours) is the editor's, and is ported in test/editor/marks/ and test/editor/syntax/.

void main() {
  group('Ghost.md’s own marks', () {
    test('are one plugin, with one switch, each mark carrying its own icon', () {
      expect(marksPlugin.manifest.id, 'marks');
      expect(identical(marksPlugin.formats, marks), isTrue);
      expect(marksPlugin.manifest.permissions, isEmpty);
      for (final format in marks) {
        expect(format.icon, isNotEmpty, reason: format.name);
        // And it is one the app can draw: none falls back to the plain letter.
        expect(Lucide.all[format.icon], isNotNull, reason: '${format.name}: ${format.icon}');
      }
      expect([for (final format in marks) format.name], contains('Spoiler'));
      expect(Lucide.all[marksPlugin.icon], isNotNull);
    });

    test('each has a cue and a line for the guide', () {
      for (final format in marks) {
        expect(format.cue, isNotEmpty, reason: format.name);
        expect(format.about, isNotEmpty, reason: format.name);
      }
    });

    test('shares no delimiter or node name with any other plugin', () {
      final all = [for (final plugin in webBuiltIn()) ...plugin.formats];
      expect({for (final f in all) f.delimiter}.length, all.length);
      expect({for (final f in all) f.name}.length, all.length);
    });

    test('are ones the registry will carry: every name and delimiter passes its check', () {
      final registry = createRegistry(const [marksPlugin], store: MemorySwitches());
      expect([for (final f in registry.formats()) f.name], ['Spoiler', 'Highlight', 'Aside', 'Unsure', 'Redact', 'Shout', 'Added', 'Heat', 'Frost', 'Wave', 'Shimmer', 'Haunt']);
      registry.setEnabled('marks', false);
      expect(registry.formats(), isEmpty, reason: 'one switch for all twelve');
    });

    test('ship with Ghost.md, reach nothing and keep nothing, in the web manifest’s words', () {
      const manifest = marksManifest;
      expect(manifest.name, 'Marks');
      expect(
        manifest.description,
        'Ghost.md’s own formatting on top of Markdown: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout, an addition, and five effects: heat, frost, a wave, a shimmer and a haunting. Typed or said.',
      );
      expect((manifest.version, manifest.author, manifest.standard), ('1.0.0', 'Ghost.md', true));
      expect(manifest.storage, isEmpty);
      expect(manifest.secrets, isEmpty);
      expect(usesNetwork(manifest), isFalse);
      expect(reachLine(manifest), '');
      expect(marksPlugin.settings, isNull);
    });
  });
}
