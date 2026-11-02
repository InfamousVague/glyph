/// The Meetings plugin's page in Settings (meetings.dart [meetingsPlugin]; docs/PM_PLUGINS.md §10): where every
/// meeting goes, whichever plugin or recorder it came from, a row that opens Settings › Recording at its Meetings card
/// ([MeetingsGoSection]), the one card the meeting settings share (Sync meeting recordings, Sort meetings into
/// workspaces, a meeting's sound and its live transcript, when it is written up); and Google Meet and Zoom, which stand
/// on it, each a row to its own page where it is added.
///
/// The card stays Recording's, where the recorder's own rows are beside it: it is drawn there only while Meetings is
/// on (lib/settings/panes/recording_pane.dart).
library;

import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../meet/ui/meeting_settings.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/settings_host.dart';
import '../registry.dart' show plugins;

class MeetingsToolPane extends StatelessWidget {
  const MeetingsToolPane({super.key, this.store, this.onOpenRecording, this.onOpenPlugin});

  /// The preferences: the account's where there is one, else the app's.
  final PreferencesStore? store;

  /// Settings › Recording, at its Meetings card.
  final VoidCallback? onOpenRecording;

  /// A plugin's page in Settings, or its place in the Market where it is not added.
  final void Function(String id)? onOpenPlugin;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return MeetingsToolPane(
      store: AccountScope.maybeOf(context)?.prefs,
      onOpenRecording: host == null ? null : () => host.go(recordingSectionId, setting: meetingsGoName),
      onOpenPlugin: host == null ? null : (id) => host.go('plugin:$id'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [for (final (id, name) in const [('google-meet', 'Google Meet'), ('zoom', 'Zoom')]) if (plugins.byId(id) != null && plugins.isEnabled(id)) (id, name)];
    return PaneBody(
      children: [
        MeetingsGoSection(prefs: store ?? preferences, onOpen: onOpenRecording),
        if (kinds.isNotEmpty)
          PaneSection(
            title: 'Ghost in your calls',
            description: const Text('Ghost joins the calls you invite it to, a plugin for each service.'),
            children: [
              for (final (id, name) in kinds)
                SettingRow(key: ValueKey('meetings-kind-$id'), icon: const AppIcon(Lucide.video, size: 20), label: name, onPress: onOpenPlugin == null ? null : () => onOpenPlugin!(id)),
            ],
          ),
      ],
    );
  }
}
