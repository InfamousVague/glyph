/// The Forms plugin, one of the project tools (docs/PM_PLUGINS.md): a note's ```form fence shared by its link, and each
/// answer filed as a ticket (lib/forms, docs/FORMS.md). It needs Tickets.
library;

import '../../core/project_tools.dart' show formsTool;
import '../types.dart';

const PluginManifest formsManifest = PluginManifest(
  id: formsTool,
  name: 'Forms',
  description:
      'A note with a ```form fence is a form: share its link, anyone can fill it in, and each answer comes back sealed and is filed as a ticket in the notebook the form names. Needs Tickets.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.projects,
  tagline: 'Forms anyone can fill, filed as tickets',
  adds: [
    'Share a form’s link from its note’s settings',
    'Each answer filed as a ticket, read from the form inbox',
  ],
  standard: false,
  permissions: [],
  storage: [],
);

const GlyphPlugin formsPlugin = GlyphPlugin(manifest: formsManifest, icon: 'text-cursor-input');
