/// The Canvas plugin, one of the more tools (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other things that
/// can be plugins that might be overwhelming for a new user as well"): a note that is JSON Canvas 1.0 drawn as cards on
/// a page with lines between them, groups and workspace hues (lib/canvas, docs/CANVAS.md), the canvas sidecars the
/// core writes beside it, a new canvas in the + and in New, a canvas embedded with `![[A canvas]]`, and its mark in
/// the lists.
///
/// Off, a canvas is still a note, listed as every note is, and opens to a chip, "Turn on Canvas", where its cards
/// would be: its JSON is never rewritten, and the core goes on writing its `.canvas` file. On for a person whose
/// library held a canvas before it was a plugin (lib/plugins/more/more_tools.dart `adoptMoreTools`).
library;

import '../../core/more_tools.dart' show canvasTool;
import '../types.dart';

const PluginManifest canvasManifest = PluginManifest(
  id: canvasTool,
  name: 'Canvas',
  description:
      'Notes that are canvases: cards of words, notes, pictures and links on a page you pan and zoom, lines between them, groups, and your workspaces’ colours. Kept as JSON Canvas 1.0, the file Obsidian reads.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.editor,
  tagline: 'Cards on a page with lines between them',
  adds: [
    'A canvas in New and in the + and the / palette',
    'A canvas note drawn as its cards, and ![[A canvas]] drawn in a frame',
    'Add as a canvas in a notebook, and the example canvases in Settings › Examples',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin canvasPlugin = GlyphPlugin(manifest: canvasManifest, icon: 'shapes');
