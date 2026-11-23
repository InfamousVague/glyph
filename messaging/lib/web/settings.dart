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

/// What the browser keeps, as About says it (lib/web/store.dart says it at length): all of it sealed, and the words and
/// the password's key not at all.
const browserKeeps = 'Who you are here, your friends, circles and conversations, in this browser\'s own store for this address, every part of it sealed with a key the browser made for this page and won\'t give out. Your recovery words and your password\'s key are not kept here at all: your password opens them when you want to see the words or change your account. Signing out deletes all of it from this browser.';

/// What sealing doesn't keep out, as About says it: whatever runs in the page, a copy of the browser's files, and the
/// server the page comes from.
const browserLimits = 'Anything that runs in this page can open what it keeps, as the app does: a script slipped into it, or a browser extension allowed to read and change this site. In Chrome, Edge and Firefox the key is among the browser\'s own files, so a copy of them opens everything; Safari keeps it locked with your Mac\'s or iPhone\'s keychain. And the page comes from the server each time you open it, so a server broken into could hand out one that takes your password. On a computer of your own, the app keeps your keys safer.';

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
            // What lib/web/store.dart says, in fewer words: what is sealed, against what, and what isn't kept at all.
            const SettingRow(
              icon: AppIcon(Lucide.lock, size: 18),
              label: 'What this browser keeps',
              hint: Text(browserKeeps),
            ),
            const SettingRow(
              icon: AppIcon(Lucide.triangleAlert, size: 18),
              label: 'What that doesn\'t keep out',
              hint: Text(browserLimits),
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
