import 'package:flutter/widgets.dart';

import '../kit/settings_kit.dart';
import '../settings_sections.dart' show SettingsNotPorted, settingsSections;
import 'settings_host.dart';

/// Port of `OrganizationsPane` (src/app/settings/OrganizationsPane.tsx) as far as it stands alone: signed out there is
/// nothing to list and nothing to make, and the words send the person to Account.
///
/// What differs from the web original: the signed-in page (the organizations, the invitations waiting, and a name to
/// make a new one) needs the account and the organizations' service, which are stage 7; signed in, this draws the
/// card that says the page is not ported.
class OrganizationsPane extends StatelessWidget {
  const OrganizationsPane({super.key, this.signedIn = false, this.onOpenAccount});

  final bool signedIn;

  /// Lands on Account; without it the word is a plain word.
  final VoidCallback? onOpenAccount;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return OrganizationsPane(signedIn: host?.features.signedIn ?? false, onOpenAccount: host == null ? null : () => host.go('account'));
  }

  @override
  Widget build(BuildContext context) {
    if (signedIn) return SettingsNotPorted(spec: settingsSections.firstWhere((spec) => spec.id == 'organizations'));
    return PaneBody(
      children: [
        SettingsCallout(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Organizations come with an account. Sign in under '),
                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Account', onPress: onOpenAccount)),
                const TextSpan(text: ' to make or join one.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
