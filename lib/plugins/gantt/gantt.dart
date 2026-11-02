/// The Gantt and timelines plugin, one of the project tools (docs/PM_PLUGINS.md): the ```gantt fence drawn as a chart
/// to drag (lib/core/gantt, lib/editor/gantt; docs/GANTT.md), and the gantt and timeline views of a query.
library;

import '../../core/project_tools.dart' show ganttTool;
import '../types.dart';

const PluginManifest ganttManifest = PluginManifest(
  id: ganttTool,
  name: 'Gantt and timelines',
  description:
      'A ```gantt fence drawn as a Gantt chart you drag: tasks, their days, who has them, what waits on what, and milestones, every change written back into the fence. And a query shown as a gantt or a timeline.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Gantt charts and timelines to drag',
  adds: [
    'A ```gantt fence drawn as its chart, and a Gantt chart in the + and the / palette',
    '`show: gantt` and `show: timeline` in a query',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin ganttPlugin = GlyphPlugin(manifest: ganttManifest, icon: 'chart-gantt');
