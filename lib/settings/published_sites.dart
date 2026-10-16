import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../account/ui_state.dart';
import '../art/art.dart';
import '../share/sites.dart';
import '../sync/engine.dart' show syncedWhen;
import 'kit/settings_kit.dart';

/// Every site the account has published, in one place (Settings › Account › Published sites; lib/share/sites.dart,
/// docs/SITES.md): each with its link to copy, when it was last published, and a way to unpublish it, whichever device
/// published it, since the list is the service's and each site's key is sealed beside it under the account key.
///
/// Drawn only while there is something to list ([publishedSitesShown]); the page asks the service for the list as it
/// opens ([Sites.readSoon]).
bool publishedSitesShown(Sites sites) => sites.list.isNotEmpty || sites.unread > 0;

/// The card.
class PublishedSites extends StatefulWidget {
  const PublishedSites({super.key, required this.services, this.now});

  final AccountServices services;

  /// This moment, in ms: a test's clock.
  final int Function()? now;

  @override
  State<PublishedSites> createState() => _PublishedSitesState();
}

class _PublishedSitesState extends State<PublishedSites> {
  String? _said;
  bool _busy = false;

  Future<void> _copy(String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) setState(() => _said = 'The link is copied.');
    } catch (_) {
      if (mounted) setState(() => _said = link);
    }
  }

  Future<void> _unpublish(SiteEntry site) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await widget.services.sites!.unpublish(site);
      if (mounted) setState(() => _said = '“${site.title}” is unpublished.');
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.services.sites;
    if (sites == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: sites,
      builder: (context, _) {
        final now = (widget.now ?? widget.services.now)();
        final unread = sites.unread;
        return PaneSection(
          title: 'Published sites',
          footer: Text(_said ?? 'Anyone with a site’s link can read it, and nobody else, the server included. No search engine can list a site. Unpublishing takes it down at once.'),
          children: [
            for (final site in sites.list)
              SettingRow(
                key: ValueKey('site:${site.id}'),
                icon: const AppIcon(Lucide.globe, size: 20),
                label: site.title,
                // The day and the time kept on one line: a phone's width breaks before them, not inside them.
                hint: Text('${site.kind == 'book' ? 'A notebook. ' : ''}Published ${syncedWhen(site.updated, now: now).replaceAll(' ', '\u00A0')}.'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RowAction(onPress: () => unawaited(_copy(site.link)), child: const Text('Copy')),
                    RowAction(disabled: _busy, onPress: () => unawaited(_unpublish(site)), child: const Text('Unpublish')),
                  ],
                ),
              ),
            if (unread > 0)
              SettingRow(
                label: unread == 1 ? 'A site this version can’t read' : '$unread sites this version can’t read',
                hint: const Text('Published from a newer Ghost.md. Update the app to see them here.'),
              ),
          ],
        );
      },
    );
  }
}
