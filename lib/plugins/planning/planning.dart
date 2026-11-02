/// The Planning plugin, one of the project tools (docs/PM_PLUGINS.md): cycles and sprints, estimates, burndown and
/// velocity, epics, milestones and the roadmap (lib/core/planning, lib/core/query/planning.dart). It needs Tickets.
library;

import '../../core/project_tools.dart' show planningTool;
import '../types.dart';

const PluginManifest planningManifest = PluginManifest(
  id: planningTool,
  name: 'Planning',
  description:
      'Plan tickets in cycles and sprints: estimates in points or hours, a cycle’s burndown and the cycles’ velocity as charts, epics and milestones, and the roadmap of them. Needs Tickets.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Cycles, estimates, burndown and the roadmap',
  adds: [
    'A ticket’s cycle, estimate, epic and milestone in its panel',
    '`show: burndown`, `show: velocity` and `show: roadmap` in a query',
    'Carry a cycle’s unfinished tickets on to the next',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin planningPlugin = GlyphPlugin(manifest: planningManifest, icon: 'calendar-days');
