/// What follows the account through the sealed keys (lib/sync/sealed_keys.dart), and what stays on each device and
/// why (Matt, 2026-10-26: "make it so things like the Claude tokens and other stuff is kept in sync across all
/// instances of ghost logged in to my account").
///
/// THAT TRAVELS, each an item read and written where its owner already keeps it:
/// - **Claude** (lib/claude/claude_settings.dart, claude_spend.dart): the API key, the model, the effort, the "Ask
///   Claude" inbox switch, the watch's To Claude switch, and the spending limit's switch, amount and warning
///   ([claudeLimitName]). The secure store's own names; [ClaudeSettings.reload] after each is written. So a key put in
///   on the Fold is the Mac's at its next sync, and the summaries' handoff (lib/ai/summary_handoff.dart), which looks
///   again when Claude's settings change, sees the Mac able to write a meeting up.
/// - **The plugins' switches** for the four whose connections travel, Claude, Slack, GitHub and Lovart (`plugin:<id>`,
///   [Registry.setSwitch]): Claude turned on anywhere is on everywhere, and Slack is on wherever its channels are.
/// - **Slack** (lib/plugins/slack/channels.dart, meetings.dart): each channel's webhook (the secure store's
///   `glyph-slack-webhook:<id>`) and the list that names them (`glyph-slack-channels`), and Settings › Meetings › Post
///   to Slack (`glyph-slack-meetings`: the switch, the channel, the share link). So the device that writes a meeting up
///   has the channel to post it to, whichever it is; that it is posted once stays the synced `slackMeetingPosts`'s.
/// - **GitHub's token** (lib/plugins/github/repos.dart): a personal access token, which works from any number of
///   devices at once.
/// - **Lovart's keys** (lib/plugins/lovart/manifest.dart): the access key and the secret key, a pair that signs each
///   request and works from any number of devices (Matt, 2026-10-26: "Yes please sync lovart too"). Its project
///   (`glyph-lovart-project`) stays: each device makes or finds its own. So does "Inspiration for design meetings"
///   (`glyph-lovart-meetings`) and the meetings it has done: each device that writes a meeting up asks for its own.
///
/// ALREADY TRAVELLING, in the settings sealed as a whole (lib/sync/prefs.dart): the calendars' iCal addresses and
/// Google's sign-in (`calendars`), and the webhooks with their secrets (`webhooks`). **Google's refresh token** may be
/// shared by several devices: Google does not turn it over when it is used, so each device makes its own access
/// tokens from the same one (lib/calendar/google.dart), and each keeps those (`glyph-google-token`) to itself.
///
/// THAT STAYS ON EACH DEVICE:
/// - **Notion's sign-in** (lib/plugins/notion/client.dart, `glyph-notion-account`), and with it which board a note
///   sends to (`glyph-notion-links`). Notion turns the refresh token over each time it is used: the refresh hands back
///   a new one and the old one stops working (server/src/notion.rs `refresh`). Two devices holding the same pair
///   would each refresh in turn, and the second to do so, holding a token already spent, would be signed out; a sync
///   every few minutes cannot close that gap. Each device signs in to Notion itself.
/// - **What Claude spent this month**: the count is each device's own, and the limit holds each to the same amount.
/// - **Where an organization's news goes on Slack** (`glyph-slack-news`, news.dart): every device with a channel set
///   for an organization posts its news, so synced, every device would post each row. Set on one device, as before.
/// - **What has been posted and what waits**: `glyph-slack-posted`, the meetings' queue of tries
///   (`glyph-slack-meeting-queue`), and the caches the plugins read into (`glyph-notion-tasks`, `glyph-github-issues`,
///   `glyph-github-projects`, `glyph-calendar-events`): a device's own bookkeeping, or what it fetched.
/// - **What is the device's**: the microphone and the models downloaded, its own sign-in session and keys
///   (lib/account/device_keys.dart), window and layout choices, and the plugins tied to its permissions (the
///   contacts, places and their reminders).
/// - **Todoist's token** is not kept anywhere: it is pasted for one import.
///
/// **On an iPhone** the Slack items are not offered (lib/core/iphone_app.dart `notOnIPhone`), as Slack is not there
/// yet: their entries are carried in the settings untouched. Claude's are offered, so a key reaches an iPhone too.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../claude/claude_settings.dart';
import '../claude/claude_spend.dart' show claudeLimitName;
import '../core/iphone_app.dart' show notOnIPhone;
import '../plugins/github/manifest.dart' as github show host, tokenSecret;
import '../plugins/host.dart' show onPluginStorage;
import '../plugins/lovart/manifest.dart' as lovart show accessKeySecret, host, secretKeySecret;
import '../plugins/registry.dart' show Registry, plugins;
import '../plugins/slack/manifest.dart' as slack show host, webhookPrefix;
import '../plugins/types.dart' show PluginHost;
import 'sealed_keys.dart';

/// Claude's names in the secure store that travel.
const List<String> claudeSyncedNames = [claudeKeyName, claudeModelName, claudeEffortName, claudeInboxName, claudeWatchName, claudeLimitName];

/// The plugins whose switch travels.
const List<String> syncedSwitches = ['claude', 'slack', 'github', 'lovart'];

/// The Slack plugin's storage keys that travel: the channels' names, and where meetings post.
const String slackChannelsKey = 'glyph-slack-channels';
const String slackMeetingsKey = 'glyph-slack-meetings';

/// A switch's name among the items.
String switchItemName(String pluginId) => 'plugin:$pluginId';

final RegExp _channelId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// The items this device offers (see the header), given the names the settings already hold. Claude's settings, the
/// plugins' hosts and the registry are the app's own unless a test gives its own; [platform] is the device's.
List<SyncedItem> connectionItems(Set<String> named, {ClaudeSettings? claude, PluginHost? slackHost, PluginHost? githubHost, PluginHost? lovartHost, Registry Function()? registry, TargetPlatform? platform}) {
  final settings = claude ?? claudeSettings;
  final reg = (registry ?? () => plugins)();
  final slackHere = notOnIPhone('slack', platform: platform) == null;
  return [
    for (final name in claudeSyncedNames)
      SyncedItem(
        name: name,
        read: () => settings.store.read(name),
        write: (value) async {
          await settings.store.write(name, value);
          await settings.reload();
        },
        peek: () => _claudePeek(settings, name),
      ),
    if (slackHere) ..._slackItems(named, slackHost ?? slack.host),
    _secretItem(githubHost ?? github.host, github.tokenSecret),
    for (final name in const [lovart.accessKeySecret, lovart.secretKeySecret]) _secretItem(lovartHost ?? lovart.host, name),
    for (final id in syncedSwitches)
      if (reg.byId(id) != null && (slackHere || id != 'slack')) _switchItem(reg, id),
  ];
}

Object? _claudePeek(ClaudeSettings settings, String name) => switch (name) {
      claudeKeyName => settings.key,
      claudeModelName => settings.model,
      claudeEffortName => settings.effortChosen ? settings.effort : null,
      claudeInboxName => settings.inbox,
      claudeWatchName => settings.watch,
      claudeLimitName => settings.spend.limitText,
      _ => null,
    };

SyncedItem _secretItem(PluginHost host, String name) => SyncedItem(
      name: name,
      read: () => host.secrets.read(name),
      write: (value) => host.secrets.write(name, value),
      peek: () => host.secrets.held(name),
    );

SyncedItem _storageItem(PluginHost host, String key) => SyncedItem(
      name: key,
      read: () async {
        final Object? kept = host.storage.get<Object?>(key, null);
        return kept == null ? null : jsonEncode(kept);
      },
      write: (value) async {
        if (value == null) {
          host.storage.remove(key);
        } else {
          host.storage.set(key, jsonDecode(value));
        }
      },
      peek: () => jsonEncode(host.storage.get<Object?>(key, null)),
      order: 1,
    );

/// Each channel's webhook, by the ids this device lists and the ones the settings name (a channel added or forgotten
/// on another device), then the list and Post to Slack.
List<SyncedItem> _slackItems(Set<String> named, PluginHost host) {
  final ids = <String>{};
  final Object? listed = host.storage.get<Object?>(slackChannelsKey, const <Object?>[]);
  if (listed is List) {
    for (final each in listed) {
      if (each is Map && each['id'] is String) ids.add(each['id'] as String);
    }
  }
  for (final name in named) {
    if (name.startsWith(slack.webhookPrefix)) ids.add(name.substring(slack.webhookPrefix.length));
  }
  return [
    for (final id in ids)
      if (_channelId.hasMatch(id)) _secretItem(host, '${slack.webhookPrefix}$id'),
    _storageItem(host, slackChannelsKey),
    _storageItem(host, slackMeetingsKey),
  ];
}

String? _switchOf(Registry reg, String id) => reg.hasSwitch(id) ? (reg.switchedOn(id) ? 'on' : 'off') : null;

SyncedItem _switchItem(Registry reg, String id) => SyncedItem(
      name: switchItemName(id),
      read: () async => _switchOf(reg, id),
      // A switch is never unset by another device: one that was never moved there sends nothing.
      write: (value) async {
        if (value != null) reg.setSwitch(id, value == 'on');
      },
      peek: () => _switchOf(reg, id),
      order: 2,
    );

/// What the items' owners tell of a change ([SealedKeys.heard]): Claude's settings, any plugin's storage or secrets,
/// and the plugins' switches, the registry as it is when something first listens.
Listenable connectionChanges({ClaudeSettings? claude, Registry Function()? registry}) => _Owners(claude ?? claudeSettings, registry ?? () => plugins);

class _Owners extends ChangeNotifier {
  _Owners(this._claude, this._registry);

  final ClaudeSettings _claude;
  final Registry Function() _registry;
  VoidCallback? _stopStorage;
  Registry? _switches;

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _claude.addListener(_told);
      _stopStorage = onPluginStorage(_told);
      _switches = _registry()..addListener(_told);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _claude.removeListener(_told);
      _stopStorage?.call();
      _stopStorage = null;
      _switches?.removeListener(_told);
      _switches = null;
    }
  }

  void _told() => notifyListeners();
}
