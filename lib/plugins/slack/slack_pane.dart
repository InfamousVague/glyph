/// The Slack plugin's page in Settings: the channels on this device, each with a test message, a new name and a way
/// to forget it; a channel added by name and pasted webhook; and, for each organization the person is a member of,
/// the channel its news goes to, if any. A port of `src/app/plugins/slack/SlackPane.tsx` and `SlackPane.module.css`.
///
/// Everything here is this device's: the webhooks are kept in the secure store (channels.dart) and nothing syncs,
/// which the page says, so a person with two phones is not surprised that the second has no channels, or that both
/// post an organization's news where both have it set. What a note posts is chosen on the note, from its More
/// sheet.
///
/// What differs:
/// - **"Slack works in the app." is not drawn**: that was the page in a browser, and this is the app.
/// - The organizations are news.dart's seam ([slackOrgs]); with none handed over the card is not drawn.
/// - The fields are plain_field.dart's (the GitHub page's rule is the same one), each with a controller.
/// - The page is a [PaneBody], where React returned a fragment into the pane.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../details_cache.dart' show failureWords;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import 'channels.dart';
import 'news.dart';

/// What a test post says in the channel (`TEST_TEXT`).
const String slackTestText = 'A test from Ghost.md. What you post from this device will land here.';

class SlackPane extends StatefulWidget {
  const SlackPane({super.key});

  @override
  State<SlackPane> createState() => _SlackPaneState();
}

class _SlackPaneState extends State<SlackPane> {
  bool? _available;

  /// The ids that have a webhook kept, once asked; a listed channel without one cannot post.
  List<String>? _kept;
  String? _said;
  String? _busy;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();

  /// The channel being renamed, and its name as typed.
  String? _renaming;
  final TextEditingController _newName = TextEditingController();

  /// The organization whose channel is being chosen.
  String? _choosing;
  late final VoidCallback _stop;
  Listenable? _orgs;
  List<Channel> _asked = const [];

  @override
  void initState() {
    super.initState();
    for (final typed in [_name, _url, _newName]) {
      typed.addListener(_redraw);
    }
    _stop = onPluginStorage(_changed);
    _orgs = slackOrgs.changes?..addListener(_redraw);
    unawaited(slackAvailable().then((yes) {
      if (!mounted) return;
      setState(() => _available = yes);
      _askKept();
    }));
  }

  @override
  void dispose() {
    _stop();
    _orgs?.removeListener(_redraw);
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
    if (!identical(_asked, channels())) _askKept();
  }

  void _askKept() {
    if (_available != true) return;
    final list = _asked = channels();
    unawaited(keptWebhooks().then((ids) {
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

  String? get _typedProblem => _name.text.trim().isNotEmpty || _url.text.trim().isNotEmpty ? (nameProblem(_name.text) ?? webhookProblem(_url.text)) : null;

  Future<void> _add() => _act('add', () async {
        final channel = await addChannel(_name.text, _url.text);
        _name.clear();
        _url.clear();
        return 'Added ${channel.name}. Send it a test to be sure it posts.';
      });

  Future<void> _test(Channel channel) => _act(channel.id, () async {
        await postToChannel(channel, slackTestText);
        return 'Sent a test to ${channel.name}.';
      });

  Future<void> _forget(Channel channel) => _act(channel.id, () async {
        await forgetChannel(channel.id);
        return 'Forgot ${channel.name}. Its webhook is gone from this device; it still works in Slack until it is removed there.';
      });

  void _rename() {
    final id = _renaming;
    if (id == null) return;
    try {
      renameChannel(id, _newName.text);
      setState(() {
        _renaming = null;
        _said = null;
      });
    } catch (failure) {
      setState(() => _said = failureWords(failure));
    }
  }

  /// `.form`: the fields one under the other across the row, a `--glacier-space-2` apart, and the last thing at the
  /// row's end.
  Widget _form(Tokens t, List<Widget> fields, Widget last) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(2),
        children: [...fields, Align(alignment: AlignmentDirectional.centerEnd, child: last)],
      );

  /// `.actions`: a row's few words to press side by side, wrapping from the end.
  Widget _actions(Tokens t, List<Widget> words) => Wrap(alignment: WrapAlignment.end, spacing: t.space(3), runSpacing: t.space(3), children: words);

  Widget _channelRow(Tokens t, Channel channel) {
    const icon = AppIcon(Lucide.hash, size: 16);
    if (_renaming == channel.id) {
      return SettingRow(
        key: ValueKey(channel.id),
        icon: icon,
        label: 'Rename ${channel.name}',
        layout: SettingRowLayout.stacked,
        control: _form(
          t,
          [PlainField(label: 'Channel name', controller: _newName, placeholder: '#launch')],
          _actions(t, [
            RowAction(onPress: () => setState(() => _renaming = null), child: const Text('Cancel')),
            RowAction(onPress: _rename, disabled: nameProblem(_newName.text, channel.id) != null, child: const Text('Keep it')),
          ]),
        ),
      );
    }
    final kept = _kept;
    final missing = kept != null && !kept.contains(channel.id);
    return SettingRow(
      key: ValueKey(channel.id),
      icon: icon,
      label: channel.name,
      hint: Text(missing ? 'Its webhook isn’t on this device any more. Forget it and add it again.' : 'Posts from this device go here.'),
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

  void _choose(String orgId, String? channelId) {
    setNewsChannel(orgId, channelId);
    setState(() => _choosing = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (_available == false) {
      return const PaneBody(
        children: [
          SettingsEmpty(icon: AppIcon(Lucide.hash, size: 22), title: 'Slack needs the newest Ghost.md.', body: Text('Install the latest version from Settings › Updates, then come back here to add a channel.')),
        ],
      );
    }
    final list = channels();
    final orgs = [for (final org in slackOrgs.list()) if (org.state == 'member') org];
    final typedProblem = _typedProblem;
    final said = _said;
    return PaneBody(
      children: [
        if (said != null) SettingsCallout(child: Text(said)),
        PaneSection(
          title: 'Channels',
          description: const Text('Each is a Slack channel’s incoming webhook, under a name you give it. Kept on this device: not synced, and once kept no page can read the webhook back.'),
          children: [
            if (list.isEmpty) const SettingRow(label: 'No channels yet', hint: Text('Add one below: a name, and the webhook Slack gives you.')) else for (final channel in list) _channelRow(t, channel),
          ],
        ),
        PaneSection(
          title: 'Add a channel',
          description: const Text('In Slack, add an incoming webhook to the channel (Apps › Incoming WebHooks, or a workflow’s webhook), copy its URL, and paste it here.'),
          children: [
            SettingRow(
              label: 'A name and its webhook',
              hint: Text(typedProblem ?? 'The name is yours, for the rows you choose from. Slack decides the channel by the webhook.'),
              layout: SettingRowLayout.stacked,
              control: _form(
                t,
                [
                  PlainField(label: 'Channel name', controller: _name, placeholder: '#launch'),
                  PlainField(label: 'Webhook', controller: _url, placeholder: 'https://hooks.slack.com/services/…', secret: true),
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
        if (orgs.isNotEmpty && list.isNotEmpty)
          PaneSection(
            title: 'Organizations’ news',
            description: const Text(
              'An organization’s news (who joined, left or changed role, and its new name) can go to a channel as it arrives. Set here, on this device only: each device with a channel set posts the news, so set it on one.',
            ),
            children: [
              for (final org in orgs) ...() {
                final to = newsChannelFor(org.id);
                final open = _choosing == org.id;
                return [
                  SettingRow(
                    key: ValueKey(org.id),
                    label: org.name,
                    hint: Text(to != null ? 'Its news goes to ${to.name}.' : 'Its news isn’t posted.'),
                    control: RowAction(onPress: () => setState(() => _choosing = open ? null : org.id), child: Text(open ? 'Done' : 'Change')),
                  ),
                  if (open) ...[
                    SettingRow(key: ValueKey('${org.id}-none'), label: 'Nowhere', control: Pick(checked: to == null, label: 'Don’t post ${org.name}’s news', onPress: () => _choose(org.id, null))),
                    for (final channel in list)
                      SettingRow(
                        key: ValueKey('${org.id}-${channel.id}'),
                        icon: const AppIcon(Lucide.hash, size: 16),
                        label: channel.name,
                        control: Pick(checked: to?.id == channel.id, label: 'Post ${org.name}’s news to ${channel.name}', onPress: () => _choose(org.id, channel.id)),
                      ),
                  ],
                ];
              }(),
            ],
          ),
        const SettingsFootnote(
          child: Text('Nothing goes to Slack unless you post it from a note, or set an organization’s news to go. What is posted leaves Ghost.md’s encryption: Slack, and everyone in the channel, can read it.'),
        ),
      ],
    );
  }
}
