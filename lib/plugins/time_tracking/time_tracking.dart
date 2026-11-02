/// The Time tracking plugin, one of the project tools (docs/PM_PLUGINS.md): timers on tickets and the time logged under
/// their `## Time` heading (lib/book/timers.dart, time_log.dart, lib/editor/tickets/ticket_work.dart). It needs Tickets.
library;

import '../../core/project_tools.dart' show timeTrackingTool;
import '../types.dart';

const PluginManifest timeTrackingManifest = PluginManifest(
  id: timeTrackingTool,
  name: 'Time tracking',
  description:
      'A timer on a ticket, started from its panel or the palette and shown on the activity tray while it runs, and the time logged under the ticket’s Time heading, totalled in its `spent:` for a query to add up. Needs Tickets.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Timers and time logs on tickets',
  adds: [
    'Start and stop a timer on a ticket, from its panel or Start timer on… in the palette',
    'A ticket’s time log and its `spent:` total',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin timeTrackingPlugin = GlyphPlugin(manifest: timeTrackingManifest, icon: 'hourglass');
