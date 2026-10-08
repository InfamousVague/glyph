import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/preferences.dart';
import 'kit/settings_kit.dart';

/// The privacy policy (landing/privacy.html), on the download site (`PRIVACY_URL`).
const String privacyUrl = 'https://ghostmarkdown.com/privacy.html';

/// Port of `PrivacyCard` (src/app/settings/PrivacyCard.tsx): the switches that decide what leaves the device, and the
/// policy with what it comes to in two lines. Local only is the whole network switch; Link previews says whether a
/// link's card is drawn at all; Look up blanks online is greyed off under Local only, which keeps such blanks
/// waiting. Each is a stored preference (`localOnly`, `linkPreviews`, `lookUpBlanks`), live at once.
///
/// What differs from the web original: the words are the app's (the page had a second set for a browser), and the
/// policy's row opens its link through [onOpenLink], or cannot be pressed without one. Local only is read by the
/// sync (lib/sync/engine.dart), which runs nothing while it is on; there is no link card or fill to hold off yet.
/// It lived in panes/account_pane.dart until the account's own cards arrived, and that file still exports it.
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key, this.store, this.onOpenLink});
  final PreferencesStore? store;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? preferences;
    final open = onOpenLink;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) => PaneSection(
        title: 'Privacy',
        footer: const Text(
          'Your notes, recordings and pictures stay on this device, and your voice is turned into text here. Signed in, they sync encrypted on the device first, so only your own devices can read them. No ads, no analytics, no tracking.',
        ),
        children: [
          SettingRow(
            label: 'Local only',
            hint: const Text('No sync, updates, downloads or link titles, and plugins that use the internet are held off. Ghost.md runs from what is on this device.'),
            control: GlacierSwitch(ariaLabel: 'Local only', checked: prefs.localOnly, onCheckedChange: (on) => store.update((now) => now.copyWith(localOnly: on))),
          ),
          SettingRow(
            label: 'Link previews',
            hint: const Text("A card under a line that is only a link. In the app, the page's title is read from that site."),
            control: GlacierSwitch(ariaLabel: 'Link previews', checked: prefs.linkPreviews, onCheckedChange: (on) => store.update((now) => now.copyWith(linkPreviews: on))),
          ),
          SettingRow(
            label: 'Look up blanks online',
            hint: const Text('On Fill, a blank that needs something live asks Open-Meteo, Frankfurter’s bank rates or Wikipedia. Only its question goes.'),
            control: GlacierSwitch(ariaLabel: 'Look up blanks online', checked: prefs.lookUpBlanks && !prefs.localOnly, onCheckedChange: (on) => store.update((now) => now.copyWith(lookUpBlanks: on))),
            disabledReason: prefs.localOnly ? 'Local only is on, so such blanks wait.' : null,
          ),
          SettingRow(
            icon: const AppIcon(Lucide.shieldCheck, size: 20),
            label: 'Privacy policy',
            hint: const Text('What stays on this device, and what an account, a shared link or a plugin sends.'),
            onPress: open == null ? () {} : () => open(privacyUrl),
            disabled: open == null,
          ),
        ],
      ),
    );
  }
}

