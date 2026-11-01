/// The Boards plugin, one of the project tools (docs/PM_PLUGINS.md): the ```board fence drawn as lanes of the note's
/// own items (lib/core/boards*, lib/editor/boards), and the board view of a query.
library;

import '../../core/project_tools.dart' show boardsTool;
import '../types.dart';

const PluginManifest boardsManifest = PluginManifest(
  id: boardsTool,
  name: 'Boards',
  description: 'A ```board fence drawn as lanes of cards, each card one of the note’s own items, to drag from lane to lane. And a query shown as a board.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Kanban boards of a note’s items',
  adds: [
    'A ```board fence drawn as its lanes, and a board in the + and the / palette',
    '`show: board` in a query',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin boardsPlugin = GlyphPlugin(manifest: boardsManifest, icon: 'square-kanban');
