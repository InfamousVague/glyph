import 'package:flutter/widgets.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_kit.dart';
import '../ui/common.dart' show openDocs;
import '../ui/settings.dart';
import '../ui/settings_panes.dart' show aboutLicences, appVersion;
import '../ui/whats_new.dart';

/// What is not in a browser yet, as About says it: each is absent from the page's screens, not broken in them.
const notInBrowserYet = 'Calls, voice messages and sounds, Files spaces, plugins and the Marketplace, chats on other networks, and texts through a phone. They are in Ghost Messaging on a phone or a computer.';

/// Settings › About, in a browser: the phone's About is the phone app's own and a computer's is its own
/// (lib/desktop/ui/desk_settings.dart), so the page has this one. It says what this is, what the browser keeps of
/// it, and what isn't here yet. Added to Settings by lib/web/app.dart, there alone.
List<SettingsSection> browserSettings() => [
      SettingsSection(
        id: 'browser-about',
        where: SettingsWhere.computer,
        label: 'About',
        icon: const AppIcon(Lucide.info, size: 18),
        hue: 'graphite',
        group: 'app',
        summary: (m) => 'Ghost Messaging in a browser $appVersion',
        page: (context, m) => [
          PaneSection(title: 'Ghost Messaging in a browser', children: [
            const SettingRow(icon: AppIcon(Lucide.ghost, size: 18), label: 'Version', value: Text(appVersion)),
            // The release notes again (lib/ui/whats_new.dart).
            SettingRow(icon: const AppIcon(Lucide.sparkles, size: 18), label: 'What\'s new', hint: const Text('What the last update brought.'), onPress: () => showWhatsNew(context)),
            // gogho.st/docs, in a tab beside this one.
            const SettingRow(icon: AppIcon(Lucide.bookOpen, size: 18), label: 'Help and docs', hint: Text('How everything works, step by step, at gogho.st/docs.'), onPress: openDocs),
            const SettingRow(
              icon: AppIcon(Lucide.lock, size: 18),
              label: 'What this browser keeps',
              hint: Text('Who you are here, your friends and your conversations, in this browser\'s own store for this address, with your keys sealed by one the browser holds and gives to nothing. Clearing this site\'s data takes them out of this browser: sign in again with your username and password, or your recovery words.'),
            ),
            const SettingRow(
              icon: AppIcon(LucideMore.appWindow, size: 18),
              label: 'One tab at a time',
              hint: Text('A second tab offers to take over from the first, so each message arrives once.'),
            ),
            const SettingRow(icon: AppIcon(Lucide.info, size: 18), label: 'Not in the browser yet', hint: Text(notInBrowserYet)),
          ]),
          aboutLicences(),
        ],
      ),
    ];
