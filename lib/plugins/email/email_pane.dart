/// The Email to a note plugin's page in Settings (email.dart): the card that was Settings › Account's, whole
/// (lib/mail/ui/mail_card.dart [MailCard]): the address with Copy, a name of one's own and a new one, and Turn off.
/// Moved here with the feature (docs/PM_PLUGINS.md §10). The address is read from the service as the page is drawn,
/// once; until it is, or where the service takes no mail, the page says so.
library;

import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../mail/ui/mail_card.dart';
import '../../settings/kit/settings_kit.dart';

class EmailPane extends StatelessWidget {
  const EmailPane({super.key, required this.services});

  final AccountServices? services;

  static Widget hosted(BuildContext context) => EmailPane(services: AccountScope.maybeOf(context));

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    final mail = services?.mailIn;
    if (services == null || mail == null || !services.signedIn) {
      return const PaneBody(children: [SettingsCallout(child: Text('Sign in to Ghost.md to have an address of your own whose mail becomes notes.'))]);
    }
    mail.readSoon();
    return ListenableBuilder(
      listenable: mail,
      builder: (context, _) => PaneBody(
        children: [
          if (mailCardShown(mail)) MailCard(services: services) else const SettingsCallout(child: Text('Your address is being read from Ghost.md, or this service takes no mail yet.')),
        ],
      ),
    );
  }
}
