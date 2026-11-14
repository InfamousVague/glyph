import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/settings_type.dart';
import '../../ui/shell.dart';
import '../../ui/update_banner.dart';
import '../desk.dart';
import 'desk_settings.dart';
import 'wizard.dart';

/// The Mac once a phone is paired: the app's one frame (lib/ui/shell.dart), as the phone has it, with what is the
/// Mac's own handed to it. Matt, 2026-11-14: "Unify the UI experience to match on desktop and mac as well the
/// desktop app should get all featues its missing from mobile and thr mobile app should gain the nav from desktop".
///
/// The list, the pane beside it, the navigation pill at the list's foot and every page are the phone's own screens;
/// what they ask is answered through the link to the phone (lib/desktop/remote.dart). This used to be a list of the
/// Mac's own, which read the conversations a second way and had fallen behind the phone's (no swiping, no choosing
/// several, no deleting). The Mac's own are three: how the phone is connected, kept with the list; what the pane
/// says with nothing open; and its Settings.
class DeskShell extends StatelessWidget {
  const DeskShell({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = DeskScope.of(context);
    return AppShell(
      // How the phone is connected, and what is waiting for it.
      status: ListenableBuilder(listenable: scope.link, builder: (context, _) => LinkStatus(link: scope.link, waiting: scope.calls.waiting)),
      nothing: (context) => const _Nothing(),
      settings: (context, section) => const DeskSettingsScreen(key: ValueKey('settings')),
      // Each page that opens in the pane asks for a look for a newer version, as on the phone.
      paneObservers: [UpdateWatch()],
    );
  }
}

/// The pane before a conversation is chosen.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = DeskScope.of(context);
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: ListenableBuilder(
          listenable: scope.link,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(Lucide.ghost, size: 40, color: t.color('app-ink-4')),
            SizedBox(height: t.space(3)),
            Text('Choose a conversation', style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink-2'))),
            SizedBox(height: t.space(1)),
            Text(
              scope.link.phone == null ? '' : 'Paired with ${scope.link.phone!.name}. What you send goes through it, sealed between the two.',
              textAlign: TextAlign.center,
              style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
            ),
          ]),
        ),
      ),
    );
  }
}
