/// The Marks plugin: marks.dart's twelve formattings under one switch in Settings > Plugins. The rest of
/// `src/app/plugins/marks/index.tsx` (its manifest and `marksPlugin`); the marks themselves are marks.dart's, kept
/// apart so the editor's parser can read the list without the plugin types.
library;

import 'marks.dart';
import 'types.dart';

const PluginManifest marksManifest = PluginManifest(
  id: 'marks',
  name: 'Marks',
  description:
      'Ghost.md’s own formatting on top of Markdown: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout, an addition, and five effects: heat, frost, a wave, a shimmer and a haunting. Typed or said.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.editor,
  tagline: 'Smoke, highlights, asides and effects',
  adds: [
    'Seven marks of its own, typed or said: a spoiler in smoke, a highlighter, an aside, a doubt, a redaction, a shout and an addition',
    'Five effects: heat, frost, a wave, a shimmer and a haunting',
  ],
  standard: true,
  permissions: [],
  storage: [],
);

const GlyphPlugin marksPlugin = GlyphPlugin(manifest: marksManifest, icon: 'highlighter', formats: marks);
