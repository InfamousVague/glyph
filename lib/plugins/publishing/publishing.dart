/// The Publishing plugin, one of the more tools (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other things
/// that can be plugins that might be overwhelming for a new user as well"): a note or a notebook published as a site
/// of its own on ghostmarkdown.com (lib/share/sites.dart, the share sheet's Publish as a site rows, Settings' Published
/// sites), and the git backup's website, the publisher vendored into the repository with its workflow
/// (lib/plugins/git_backup/publish.dart).
///
/// Off, the share sheet has its plain links alone and the git backup writes no website. A site already published stays
/// published on the service. On for a person with a site published before it was a plugin (lib/plugins/more/
/// more_tools.dart `adoptMoreTools`).
library;

import '../../core/more_tools.dart' show publishingTool;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'publishing_pane.dart';

export 'publishing_pane.dart';

const PluginManifest publishingManifest = PluginManifest(
  id: publishingTool,
  name: 'Publishing',
  description:
      'A note or a notebook published as a website of its own, at an address on ghostmarkdown.com, and published again as you change it. With the git backup, the repository published as a website by GitHub Pages.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Publish a note or a notebook as a website',
  adds: [
    'Publish as a site in a note’s Share, and Publish again and Unpublish',
    'Your published sites on this page',
    'Publish as a website on the git backup’s page',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.network, 'Ghost.md’s server keeps the pages you publish and shows them at their address, to anyone with it.'),
  ],
  hosts: ['ghostmarkdown.com'],
  storage: [],
);

/// Its page: the published sites, listed where the account's service publishes them.
final GlyphPlugin publishingPlugin = GlyphPlugin(
  manifest: publishingManifest,
  icon: 'globe',
  settings: PluginSettings(
    pane: PublishingPane.hosted,
    summary: () => 'Your published sites',
    hue: 'cyan',
    offered: (services) => services != null && services.signedIn && services.sites != null,
    settings: const [SettingsFindable('Published sites', 'publish site website unpublish link pages')],
  ),
);
