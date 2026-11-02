/// The Tickets plugin, one of the project tools (docs/PM_PLUGINS.md; Matt, 2026-11-01: "move the project managment
/// stuff like gantts and stuff into a suite of plugins that are disabled by default"): `type: ticket` notes and
/// everything that reads them. The base the other tools that need tickets stand on.
///
/// Like every tool of the suite it adds nothing through the registry's extension points: the features are the app's
/// own and ask lib/plugins/projects/suite.dart whether it is on where they are (`projectPluginOn`). This is its card.
library;

import '../../core/project_tools.dart' show ticketsTool;
import '../types.dart';

const PluginManifest ticketsManifest = PluginManifest(
  id: ticketsTool,
  name: 'Tickets',
  description:
      'Notes that are tickets: a status, an assignee, a priority and a due day in their front matter, drawn as a panel. Ticket notebooks with their own key and workflow, [[KEY-12]] links, My tickets and Triage, labels, sub-tickets and blockers, watchers and history, a morning digest, duplicates and merge, ticket templates, and queries of tickets.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Tickets, notebooks of them, My tickets and Triage',
  adds: [
    'A ticket’s front matter drawn as its properties, and [[KEY-12]] drawn with the ticket’s title',
    'Ticket notebooks: a key, a workflow and New ticket',
    'My tickets and Triage in the sidebar, and the digest in Settings › Notifications',
    'Labels, sub-tickets, blockers, watchers, history, duplicates and merge',
    'The Bug report and Feature templates, and `from: tickets` in a query',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin ticketsPlugin = GlyphPlugin(manifest: ticketsManifest, icon: 'ticket');
