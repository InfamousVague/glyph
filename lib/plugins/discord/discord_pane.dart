/// The Discord plugin's page in Settings: the channels, each with a test message, a new name and a way to forget it;
/// a channel added by name and pasted webhook; and where meetings go once they are written up, set in Settings ›
/// Meetings, with any that did not post. The Slack plugin's page (slack/slack_pane.dart) for Discord, less the
/// organizations' news, which this plugin does not post (discord.dart).
///
/// The webhooks are kept in the secure store (channels.dart) and follow the account sealed with the channels' names
/// (lib/sync/connections.dart), which the page says. What a note posts is chosen on the note, from its More sheet.
///
/// First on the page, Discord calls (calls_section.dart; Matt, 2026-10-26: Discord calls belong to the Discord
/// plugin): linking a Discord account, Join Discord calls, how to start one, and the calls Ghost recorded.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart' show AccountScope;
import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/settings_host.dart' show SettingsHost;
import '../details_cache.dart' show failureWords;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import 'calls_section.dart';
import 'channels.dart';
import 'meetings.dart' show meetingDiscordOffered;
import 'meetings_section.dart';

/// What a test post says in the channel.
const String discordTestText = 'A test from **Ghost.md**. What you post from this device will land here.';

const AppIcon _mark = AppIcon(Lucide.messageSquare, size: 16);

class DiscordPane extends StatefulWidget {
  const DiscordPane({super.key});

  @override
  State<DiscordPane> createState() => _DiscordPaneState();
}

class _DiscordPaneState extends State<DiscordPane> {
  /// The ids that have a webhook kept, once asked; a listed channel without one cannot post.
  List<String>? _kept;
  String? _said;
  String? _busy;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  /// The channel being renamed, and its name as typed.
  String? _renaming;
  final TextEditingController _newName = TextEditingController();
  late final VoidCallback _stop;
  List<DiscordChannel> _asked = const [];

  @override
  void initState() {
    super.initState();
    for (final typed in [_name, _url, _newName]) {
      typed.addListener(_redraw);
    }
    _stop = onPluginStorage(_changed);
    _askKept();
  }

  @override
  void dispose() {
    _stop();
    _name.dispose();
    _url.dispose();
    _newName.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    // The list changed: which of them have a webhook is asked again.
    if (!identical(_asked, discordChannels())) _askKept();
  }

  void _askKept() {
    final list = _asked = discordChannels();
    unawaited(keptDiscordWebhooks().then((ids) {
      if (mounted && identical(list, _asked)) setState(() => _kept = ids);
    }));
  }

  /// Runs one thing at a time, and says how it went at the top of the page.
  Future<void> _act(String what, Future<String> Function() run) async {
    setState(() {
      _busy = what;
      _said = null;
    });
    String said;
    try {
      said = await run();
    } catch (failure) {
      said = failureWords(failure);
    }
    if (!mounted) return;
    setState(() {
      _said = said;
      _busy = null;
    });
  }

  String? get _typedProblem => _name.text.trim().isNotEmpty || _url.text.trim().isNotEmpty ? (discordNameProblem(_name.text) ?? discordWebhookProblem(_url.text)) : null;

  Future<void> _add() => _act('add', () async {
        final channel = await addDiscordChannel(_name.text, _url.text);
        _name.clear();
        _url.clear();
        return 'Added ${channel.name}. Send it a test to be sure it posts.';
      });

  Future<void> _test(DiscordChannel channel) => _act(channel.id, () async {
        await postToDiscord(channel, discordTestText);
        return 'Sent a test to ${channel.name}.';
      });

  Future<void> _forget(DiscordChannel channel) => _act(channel.id, () async {
        await forgetDiscordChannel(channel.id);
        return 'Forgot ${channel.name} on your devices. The webhook still works in Discord until it is deleted there.';
      });

  void _rename() {
    final id = _renaming;
    if (id == null) return;
    try {
      renameDiscordChannel(id, _newName.text);
      setState(() {
        _renaming = null;
        _said = null;
      });
    } catch (failure) {
      setState(() => _said = failureWords(failure));
    }
  }

  /// The fields one under the other across the row, and the last thing at the row's end.
  Widget _form(Tokens t, List<Widget> fields, Widget last) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(2),
        children: [...fields, Align(alignment: AlignmentDirectional.centerEnd, child: last)],
      );

  /// A row's few words to press side by side, wrapping from the end.
  Widget _actions(Tokens t, List<Widget> words) => Wrap(alignment: WrapAlignment.end, spacing: t.space(3), runSpacing: t.space(3), children: words);

  Widget _channelRow(Tokens t, DiscordChannel channel) {
    if (_renaming == channel.id) {
      return SettingRow(
        key: ValueKey(channel.id),
        icon: _mark,
        label: 'Rename ${channel.name}',
        layout: SettingRowLayout.stacked,
        control: _form(
          t,
          [PlainField(label: 'Channel name', controller: _newName, placeholder: '#launch')],
          _actions(t, [
            RowAction(onPress: () => setState(() => _renaming = null), child: const Text('Cancel')),
            RowAction(onPress: _rename, disabled: discordNameProblem(_newName.text, channel.id) != null, child: const Text('Keep it')),
          ]),
        ),
      );
    }
    final kept = _kept;
    final missing = kept != null && !kept.contains(channel.id);
    return SettingRow(
      key: ValueKey(channel.id),
      icon: _mark,
      label: channel.name,
      hint: Text(missing ? 'Its webhook isn’t on this device any more. Forget it and add it again.' : 'Posts from your devices go here.'),
      control: _actions(t, [
        RowAction(onPress: () => unawaited(_test(channel)), disabled: _busy != null || missing, child: Text(_busy == channel.id ? 'Sending…' : 'Test')),
        RowAction(
          onPress: () => setState(() {
            _renaming = channel.id;
            _newName.text = channel.name;
          }),
          disabled: _busy != null,
          child: const Text('Rename'),
        ),
        RowAction(onPress: () => unawaited(_forget(channel)), disabled: _busy != null, child: const Text('Forget')),
      ]),
    );
  }

  /// Settings › Meetings, on its Post to Discord, where Settings is round the page; null where it is not.
  VoidCallback? _openMeetings(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return host == null ? null : () => host.go('meetings', setting: 'Post to Discord');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final list = discordChannels();
    final typedProblem = _typedProblem;
    final said = _said;
    return PaneBody(
      children: [
        if (said != null) SettingsCallout(child: Text(said)),
        DiscordCallsSection(services: AccountScope.maybeOf(context), onOpenNote: SettingsHost.maybeOf(context)?.onOpenNote, onOpenLink: SettingsHost.maybeOf(context)?.onOpenLink),
        PaneSection(
          title: 'Channels',
          description: const Text('Each is a Discord channel’s webhook, under a name you give it. The same on each of your devices, end-to-end encrypted, and once kept no page can read the webhook back.'),
          children: [
            if (list.isEmpty) const SettingRow(label: 'No channels yet', hint: Text('Add one below: a name, and the webhook URL Discord gives you.')) else for (final channel in list) _channelRow(t, channel),
          ],
        ),
        PaneSection(
          title: 'Add a channel',
          description: const Text('In Discord, open the channel’s settings: Integrations › Webhooks › New Webhook, then Copy Webhook URL, and paste it here. You need Manage Webhooks on the server.'),
          children: [
            SettingRow(
              label: 'A name and its webhook',
              hint: Text(typedProblem ?? 'The name is yours, for the rows you choose from. Discord decides the channel by the webhook.'),
              layout: SettingRowLayout.stacked,
              control: _form(
                t,
                [
                  PlainField(label: 'Channel name', controller: _name, placeholder: '#launch'),
                  PlainField(label: 'Webhook URL', controller: _url, placeholder: 'https://discord.com/api/webhooks/…', secret: true),
                ],
                RowAction(
                  onPress: () => unawaited(_add()),
                  disabled: _busy != null || _name.text.trim().isEmpty || _url.text.trim().isEmpty || typedProblem != null,
                  child: Text(_busy == 'add' ? 'Adding…' : 'Add it'),
                ),
              ),
            ),
          ],
        ),
        // Asked here as well as in the line, which draws nothing where meetings cannot post: an empty child would
        // still take a gap of the page's.
        if (list.isNotEmpty && meetingDiscordOffered()) DiscordMeetingsLine(onOpenMeetings: _openMeetings(context)),
        const SettingsFootnote(
          child: Text('Nothing goes to a Discord channel unless you post it from a note, or set meetings to go. What is posted leaves Ghost.md’s encryption: Discord, and everyone in the channel, can read it. Nobody is pinged by a post, @everyone included.'),
        ),
      ],
    );
  }
}
