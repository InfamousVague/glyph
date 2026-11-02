/// The Email to a note plugin, one of the more tools (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other
/// things that can be plugins that might be overwhelming for a new user as well"): an address of the account's own
/// (lib/mail, docs/MAIL.md) whose mail the service keeps sealed until a device turns it into a note in the Inbox.
///
/// Off, the address is not shown and this device leaves the mail where it waits on the service: nothing is taken,
/// opened or deleted (lib/root/account_wiring.dart), so whatever arrived is a note once it is turned on again. The
/// service is as it was. On for a person who made an address before it was a plugin, or whose notes came from mail
/// (lib/plugins/more/more_tools.dart `adoptMoreTools`).
library;

import '../../core/more_tools.dart' show emailTool;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../types.dart';
import 'email_pane.dart';

export 'email_pane.dart';

const PluginManifest emailManifest = PluginManifest(
  id: emailTool,
  name: 'Email to a note',
  description:
      'An address of your own: mail sent to it is kept sealed to your account on Ghost.md’s server until your device turns it into a note in your Inbox, its pictures and files with it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Mail sent to your address becomes a note',
  adds: [
    'Your Email to a note address, its name and a new one, on this page',
    'Each mail to it filed as a note in your Inbox',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Files each mail sent to your address as a note in your Inbox.'),
    PluginPermission(Permission.network, 'Ghost.md’s server takes the mail for your address and keeps it sealed to your account until one of your devices reads it.'),
  ],
  hosts: ['ghostmarkdown.com'],
  storage: [],
);

/// Its page, kept in Simple as the card was on Settings › Account, listed where the account's service takes mail.
final GlyphPlugin emailPlugin = GlyphPlugin(
  manifest: emailManifest,
  icon: 'mail',
  settings: PluginSettings(
    pane: EmailPane.hosted,
    summary: () => 'Mail to your address becomes a note',
    hue: 'blue',
    simple: true,
    offered: (services) => services != null && services.signedIn && services.mailIn != null,
    settings: const [SettingsFindable('Email to a note', 'mail inbox address turn off meeting invite ghost new name copy')],
  ),
);
