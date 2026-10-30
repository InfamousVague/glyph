/// The Changelog, a page of Settings behind About (Matt, 2026-10-30: "Add a changelog popup modal that shows after every
/// update with iconography"): every release the app carries, newest first, each a card of its lines drawn as the What's
/// new card draws them (change_look.dart). Reached from About's Help, the What's new card's See all changes, Settings'
/// search and the command search ("changelog", "what's new").
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../settings/kit/settings_kit.dart';
import '../settings/panes/about_pane.dart' show ghostVersion;
import '../settings/panes/settings_host.dart';
import 'change_look.dart';
import 'changelog.dart';

/// The page: [changelog] where given, else the bundle's, read as the page opens. [running] is the version this device
/// runs, said beside its release.
class ChangelogPane extends StatefulWidget {
  const ChangelogPane({super.key, this.changelog, this.running});

  final Changelog? changelog;
  final String? running;

  static Widget hosted(BuildContext context) => ChangelogPane(running: SettingsHost.maybeOf(context)?.updates?.version ?? ghostVersion);

  @override
  State<ChangelogPane> createState() => _ChangelogPaneState();
}

class _ChangelogPaneState extends State<ChangelogPane> {
  late Changelog? _changelog = widget.changelog ?? bundledChangelog;

  @override
  void initState() {
    super.initState();
    if (_changelog == null) {
      loadChangelog().then((read) {
        if (mounted) setState(() => _changelog = read);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final changelog = _changelog;
    if (changelog == null) return const PaneBody(children: [PaneSection(children: [SettingRow(label: 'Reading the changelog…')])]);
    if (changelog.releases.isEmpty) return const PaneBody(children: [PaneSection(children: [SettingRow(label: 'No changes to show.')])]);
    return PaneBody(
      children: [
        for (final release in changelog.releases)
          PaneSection(
            key: ValueKey('changelog:${release.version}'),
            title: release.title == null ? release.version : '${release.version} · ${release.title}',
            description: Text(release.version == widget.running ? "${releaseDay(release.date)} · you're on this one" : releaseDay(release.date)),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final item in release.items) ChangeLine(item: item)]),
              ),
            ],
          ),
      ],
    );
  }
}
