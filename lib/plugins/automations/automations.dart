/// The Automations plugin, one of the project tools (docs/PM_PLUGINS.md): a notebook's ```rules fence, a sentence a
/// line, and its runs (lib/book/rules*, lib/root/root_ticket_rules.dart). It needs Tickets.
library;

import '../../core/project_tools.dart' show automationsTool;
import '../types.dart';

const PluginManifest automationsManifest = PluginManifest(
  id: automationsTool,
  name: 'Automations',
  description:
      'Rules for a ticket notebook, a sentence a line in its ```rules fence: when a ticket moves to a status, is assigned or is due, set a field, assign someone, post to a channel or make another ticket. Needs Tickets.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Rules that move tickets for you',
  adds: [
    'A notebook’s ```rules fence run as tickets change',
    'Rules and GitHub… on a ticket notebook’s settings',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin automationsPlugin = GlyphPlugin(manifest: automationsManifest, icon: 'workflow');
