/// The Publishing plugin's page in Settings (publishing.dart): the account's published sites, the card that was
/// Settings › Account's, whole (lib/settings/published_sites.dart [PublishedSites]), each with its link, Copy, and
/// Unpublish; moved here with the feature (docs/PM_PLUGINS.md §10). A note is published from its Share, and the git
/// backup's website from that plugin's page.
library;

import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/published_sites.dart';

class PublishingPane extends StatelessWidget {
  const PublishingPane({super.key, required this.services});

  final AccountServices? services;

  static Widget hosted(BuildContext context) => PublishingPane(services: AccountScope.maybeOf(context));

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final sites = services?.sites;
    if (services == null || sites == null || !services.signedIn) {
      return const PaneBody(children: [SettingsCallout(child: Text('Sign in to Ghost.md to publish a note or a notebook as a site. A note is published from its Share.'))]);
    }
    sites.readSoon();
    return ListenableBuilder(
      listenable: sites,
      builder: (context, _) => PaneBody(
        children: [
          if (publishedSitesShown(sites)) PublishedSites(services: services) else const SettingsCallout(child: Text('Nothing is published yet. Publish a note or a notebook as a site from its Share.')),
        ],
      ),
    );
  }
}
