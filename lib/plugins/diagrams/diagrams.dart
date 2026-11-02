/// The Diagrams and math plugin, one of the more tools (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other
/// things that can be plugins that might be overwhelming for a new user as well"): a ```mermaid fence drawn as its
/// diagram (lib/editor/diagrams), `$$` formulas and inline `$x^2$` drawn as maths (lib/editor/maths), and a fenced
/// block's colouring by its language (lib/editor/code/code_highlight.dart), with Appearance › Code's colours.
///
/// Off, each is drawn as plain code: a fence as a code block in the one ink of a block with no language, maths as the
/// words between its dollars, with a chip, "Turn on Diagrams", under a diagram's, a formula's or a language's block.
/// Nothing is rewritten. A plain ``` block is built in either way. On for a person whose notes held one before it
/// was a plugin (lib/plugins/more/more_tools.dart `adoptMoreTools`).
library;

import '../../core/more_tools.dart' show diagramsTool;
import '../../settings/appearance_pane.dart' show CodeColoursSection, codeColoursFindable;
import '../../settings/kit/settings_kit.dart' show PaneBody;
import '../types.dart';

const PluginManifest diagramsManifest = PluginManifest(
  id: diagramsTool,
  name: 'Diagrams and math',
  description:
      r'A ```mermaid fence drawn as its diagram, $$ formulas and inline maths drawn as maths, and code coloured by its language: Dart, Python, JavaScript and 140 more.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.editor,
  tagline: 'Mermaid diagrams, formulas and coloured code',
  adds: [
    'A ```mermaid fence drawn as its diagram, and A diagram in the + and the / palette',
    r'$$ formulas and $x^2$ drawn as maths, and A formula in the + and the / palette',
    'A ```dart, ```python or any language’s block coloured by its language, and the colours of code on its page',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

/// Its page: Appearance › Code's colours, moved here with the colouring they are the look of.
final GlyphPlugin diagramsPlugin = GlyphPlugin(
  manifest: diagramsManifest,
  icon: 'sigma',
  settings: PluginSettings(
    pane: (context) => const PaneBody(children: [CodeColoursSection()]),
    summary: () => 'Diagrams, maths and code’s colours',
    hue: 'purple',
    settings: const [codeColoursFindable],
  ),
);
