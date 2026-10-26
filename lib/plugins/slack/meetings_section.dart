/// Post to Slack (meetings.dart; Matt, 2026-10-26: "make the meetings plugin work hand in hand to sending meeting
/// action items and a link to the meeting transcript to a specified slack channel"), on the Slack plugin's own page.
/// It was a section of Settings › Meetings, with a line on this page pointing there, until Meetings became the meeting
/// plugins' pages the same day ("I want settings / meetings to be broken up into three plugins"); the section is here
/// now, and the line is gone.
///
/// The section is drawn only where meetings can post ([meetingSlackOffered]: the plugin on, a channel on this
/// device, not an iPhone), so a person without Slack never meets it. In it:
///
/// - **Post meetings to Slack**, the switch: off until a channel is chosen, then on. With one channel on the device,
///   turning it on chooses that one; with several it waits for a choice, and says so.
/// - **Channel**: the channel's name, and Change, which opens the device's channels in place to pick from.
/// - **Include a share link**: on unless turned off (Matt's "Both"), with the warning that anyone the link reaches
///   reads the transcript, a team's meeting's too.
/// - **A meeting not posted**, one row each, with Slack's reason, how many tries it has had, Try now, and Don't
///   post, which lets it go.
///
/// In Simple (`Preferences.simple`) the switch and a failure are drawn, and the channel and the share link wait
/// behind a More row that opens in place, as Simple's rule is (GHST-103).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../settings/kit/settings_kit.dart';
import '../host.dart' show onPluginStorage;
import '../registry.dart' show plugins;
import 'channels.dart';
import 'meetings.dart';

/// What the warning under "Include a share link" says.
const String meetingShareWarning =
    'Anyone with the link can read the meeting’s notes and its whole transcript, a team’s meeting too, and it follows the note’s edits. Stop it from the note’s Share.';

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

/// One meeting that did not post: Slack's reason, and how its tries stand.
String meetingTryLine(MeetingPostTry waiting) {
  final why = waiting.said ?? 'It hasn’t gone yet.';
  if (waiting.spent) return '$why Tried $meetingPostTriesMost times; it waits for Try now.';
  return '$why Ghost.md tries again when it next opens (tried ${waiting.tries} of $meetingPostTriesMost).';
}

/// Post to Slack, on the Slack plugin's page; nothing where meetings cannot post here.
class MeetingsSlackSection extends StatefulWidget {
  const MeetingsSlackSection({super.key, required this.prefs});

  /// The preferences, for Simple.
  final PreferencesStore prefs;

  @override
  State<MeetingsSlackSection> createState() => _MeetingsSlackSectionState();
}

class _MeetingsSlackSectionState extends State<MeetingsSlackSection> {
  bool _choosing = false;
  bool _more = false;
  String? _trying;

  Future<void> _tryNow(String noteId) async {
    final poster = meetingSlackPoster;
    if (poster == null) return;
    setState(() => _trying = noteId);
    try {
      await poster.tryNow(noteId);
    } finally {
      if (mounted) setState(() => _trying = null);
    }
  }

  List<Widget> _failures(Tokens t) => [
        for (final waiting in failedMeetingPosts())
          SettingRow(
            key: ValueKey('slack-try-${waiting.noteId}'),
            icon: const AppIcon(Lucide.triangleAlert, size: 16),
            label: 'Not posted: “${waiting.title}”',
            hint: Text(meetingTryLine(waiting)),
            // Slack's reason is a sentence or two: the words to press go under it, not beside it.
            layout: SettingRowLayout.stacked,
            control: Wrap(
              alignment: WrapAlignment.end,
              spacing: t.space(3),
              runSpacing: t.space(3),
              children: [
                RowAction(onPress: () => unawaited(_tryNow(waiting.noteId)), disabled: _trying != null || meetingSlackPoster == null, child: Text(_trying == waiting.noteId ? 'Posting…' : 'Try now')),
                RowAction(onPress: () => forgetMeetingPost(waiting.noteId), disabled: _trying != null, child: const Text('Don’t post')),
              ],
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return _Heard(
      also: widget.prefs,
      builder: (context) {
        if (!meetingSlackOffered()) return const SizedBox.shrink();
        final simple = widget.prefs.value.simple;
        final settings = meetingSlackSettings();
        final list = channels();
        final channel = meetingChannel();
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
          title: 'Post to Slack',
          description: const Text('The same on each of your devices, with your channels. Each meeting is posted once, from the device that writes it up.'),
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.hash, size: 16),
              label: 'Post meetings to Slack',
              hint: Text(hint),
              control: GlacierSwitch(ariaLabel: 'Post meetings to Slack', checked: on, disabled: !on && !canTurnOn, onCheckedChange: setMeetingPosts),
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
                    key: ValueKey('meetings-slack-${each.id}'),
                    icon: const AppIcon(Lucide.hash, size: 16),
                    label: each.name,
                    control: Pick(
                      checked: channel?.id == each.id,
                      label: 'Post meetings to ${each.name}',
                      onPress: () {
                        chooseMeetingChannel(each.id);
                        setState(() => _choosing = false);
                      },
                    ),
                  ),
              SettingRow(
                label: 'Include a share link',
                hint: const Text(meetingShareWarning),
                control: GlacierSwitch(ariaLabel: 'Include a share link', checked: settings.share, onCheckedChange: setMeetingShareLink),
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
