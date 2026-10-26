/// Settings › Meetings' Post to Discord (meetings.dart), beside Post to Slack, and the line on the Discord plugin's
/// own page that says where meetings go. Slack's meetings_section.dart, for Discord (Matt, 2026-10-26: "Add a new
/// plugin to post notes to discord chats").
///
/// Its own section rather than one "Post meetings to" listing both: each chat has its own switch, channel and share
/// link, a meeting can go to both, and a section that is there only with its plugin on keeps the page of a person
/// with one chat (or none) as it was. The two read alike, row for row:
///
/// - **Post meetings to Discord**, the switch: off until a channel is chosen, then on. With one channel on the device,
///   turning it on chooses that one; with several it waits for a choice, and says so.
/// - **Channel**: the channel's name, and Change, which opens the device's channels in place to pick from.
/// - **Include a share link**: on unless turned off, with Slack's warning ([meetingShareWarning]).
/// - **A meeting not posted**, one row each, with Discord's reason, how many tries it has had, Try now, and Don't
///   post, which lets it go.
///
/// In Simple (`Preferences.simple`) the switch and a failure are drawn, and the channel and the share link wait
/// behind a More row that opens in place (GHST-103).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../host.dart' show onPluginStorage;
import '../registry.dart' show plugins;
import '../slack/meetings_section.dart' show meetingShareWarning, meetingTryLine;
import 'channels.dart';
import 'meetings.dart';

/// Draws again when the plugin's storage, the plugins' switches or [also] change.
class _Heard extends StatefulWidget {
  const _Heard({required this.builder, this.also});

  final WidgetBuilder builder;
  final Listenable? also;

  @override
  State<_Heard> createState() => _HeardState();
}

class _HeardState extends State<_Heard> {
  late final VoidCallback _stopStorage;
  late final VoidCallback _stopPlugins;

  @override
  void initState() {
    super.initState();
    _stopStorage = onPluginStorage(_redraw);
    _stopPlugins = plugins.subscribe(_redraw);
    widget.also?.addListener(_redraw);
  }

  @override
  void didUpdateWidget(covariant _Heard old) {
    super.didUpdateWidget(old);
    if (old.also != widget.also) {
      old.also?.removeListener(_redraw);
      widget.also?.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    _stopStorage();
    _stopPlugins();
    widget.also?.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

const AppIcon _mark = AppIcon(Lucide.messageSquare, size: 16);

/// Settings › Meetings' Post to Discord; nothing where meetings cannot post there from here.
class MeetingsDiscordSection extends StatefulWidget {
  const MeetingsDiscordSection({super.key, required this.prefs});

  /// The preferences, for Simple.
  final PreferencesStore prefs;

  @override
  State<MeetingsDiscordSection> createState() => _MeetingsDiscordSectionState();
}

class _MeetingsDiscordSectionState extends State<MeetingsDiscordSection> {
  bool _choosing = false;
  bool _more = false;
  String? _trying;

  Future<void> _tryNow(String noteId) async {
    final poster = meetingDiscordPoster;
    if (poster == null) return;
    setState(() => _trying = noteId);
    try {
      await poster.tryNow(noteId);
    } finally {
      if (mounted) setState(() => _trying = null);
    }
  }

  List<Widget> _failures(Tokens t) => [
        for (final waiting in failedDiscordMeetingPosts())
          SettingRow(
            key: ValueKey('discord-try-${waiting.noteId}'),
            icon: const AppIcon(Lucide.triangleAlert, size: 16),
            label: 'Not posted: “${waiting.title}”',
            hint: Text(meetingTryLine(waiting)),
            // Discord's reason is a sentence: the words to press go under it, not beside it.
            layout: SettingRowLayout.stacked,
            control: Wrap(
              alignment: WrapAlignment.end,
              spacing: t.space(3),
              runSpacing: t.space(3),
              children: [
                RowAction(onPress: () => unawaited(_tryNow(waiting.noteId)), disabled: _trying != null || meetingDiscordPoster == null, child: Text(_trying == waiting.noteId ? 'Posting…' : 'Try now')),
                RowAction(onPress: () => forgetDiscordMeetingPost(waiting.noteId), disabled: _trying != null, child: const Text('Don’t post')),
              ],
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return _Heard(
      also: widget.prefs,
      builder: (context) {
        if (!meetingDiscordOffered()) return const SizedBox.shrink();
        final simple = widget.prefs.value.simple;
        final settings = discordMeetingSettings();
        final list = discordChannels();
        final channel = discordMeetingChannel();
        final on = settings.on && channel != null;
        final canTurnOn = channel != null || list.length == 1;
        final String hint;
        if (on) {
          hint = 'Each meeting’s action items and its links go to ${channel.name} once, as soon as it is written up.';
        } else if (canTurnOn) {
          hint = 'Once a meeting is written up, its action items and its links go to ${(channel ?? list.single).name}.';
        } else {
          hint = simple ? 'Choose a channel under More first.' : 'Choose a channel below first.';
        }
        final open = !simple || _more;
        return PaneSection(
          title: 'Post to Discord',
          description: const Text('The same on each of your devices, with your channels. Each meeting is posted once, from the device that writes it up.'),
          children: [
            SettingRow(
              icon: _mark,
              label: 'Post meetings to Discord',
              hint: Text(hint),
              control: GlacierSwitch(ariaLabel: 'Post meetings to Discord', checked: on, disabled: !on && !canTurnOn, onCheckedChange: setDiscordMeetingPosts),
            ),
            if (open) ...[
              SettingRow(
                label: 'Channel',
                hint: Text(channel?.name ?? 'None chosen yet'),
                control: RowAction(onPress: () => setState(() => _choosing = !_choosing), child: Text(_choosing ? 'Done' : (channel == null ? 'Choose' : 'Change'))),
              ),
              if (_choosing)
                for (final each in list)
                  SettingRow(
                    key: ValueKey('meetings-discord-${each.id}'),
                    icon: _mark,
                    label: each.name,
                    control: Pick(
                      checked: channel?.id == each.id,
                      label: 'Post meetings to ${each.name} on Discord',
                      onPress: () {
                        chooseDiscordMeetingChannel(each.id);
                        setState(() => _choosing = false);
                      },
                    ),
                  ),
              SettingRow(
                label: 'Include a share link',
                hint: const Text(meetingShareWarning),
                control: GlacierSwitch(ariaLabel: 'Include a share link on Discord', checked: settings.share, onCheckedChange: setDiscordMeetingShareLink),
              ),
            ] else
              SettingRow(
                label: 'More',
                hint: const Text('The channel, and whether a share link goes with each meeting.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ..._failures(context.tokens),
          ],
        );
      },
    );
  }
}

/// The Discord plugin's page's word on meetings: where they go, any that did not, and the way to Settings ›
/// Meetings, where it is set ([onOpenMeetings]).
class DiscordMeetingsLine extends StatefulWidget {
  const DiscordMeetingsLine({super.key, this.onOpenMeetings});

  final VoidCallback? onOpenMeetings;

  @override
  State<DiscordMeetingsLine> createState() => _DiscordMeetingsLineState();
}

class _DiscordMeetingsLineState extends State<DiscordMeetingsLine> {
  String? _trying;

  Future<void> _tryNow(String noteId) async {
    final poster = meetingDiscordPoster;
    if (poster == null) return;
    setState(() => _trying = noteId);
    try {
      await poster.tryNow(noteId);
    } finally {
      if (mounted) setState(() => _trying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Heard(
      builder: (context) {
        if (!meetingDiscordOffered()) return const SizedBox.shrink();
        final channel = discordMeetingChannel();
        final on = discordMeetingSettings().on && channel != null;
        final go = widget.onOpenMeetings;
        return PaneSection(
          title: 'Automations',
          children: [
            SettingRow(
              icon: _mark,
              label: on ? 'Meetings post to ${channel.name}' : 'Meetings aren’t posted',
              hint: Text(on ? 'Each meeting’s action items and its links, once it is written up. Set in Settings › Meetings.' : 'Choose a channel for them in Settings › Meetings, and each meeting’s action items go there once it is written up.'),
              control: go == null ? null : RowAction(onPress: go, child: const Text('Meetings')),
            ),
            for (final waiting in failedDiscordMeetingPosts())
              SettingRow(
                key: ValueKey('discord-line-${waiting.noteId}'),
                icon: const AppIcon(Lucide.triangleAlert, size: 16),
                label: 'Not posted: “${waiting.title}”',
                hint: Text(meetingTryLine(waiting)),
                layout: SettingRowLayout.stacked,
                control: RowAction(onPress: () => unawaited(_tryNow(waiting.noteId)), disabled: _trying != null || meetingDiscordPoster == null, child: Text(_trying == waiting.noteId ? 'Posting…' : 'Try now')),
              ),
          ],
        );
      },
    );
  }
}
