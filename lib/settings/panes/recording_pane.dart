import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/preferences.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import '../tapes.dart';
import 'pane_parts.dart';
import 'settings_host.dart';

/// What Settings' search finds on Recording (`findable`, src/app/settings/RecordingPane.findable.ts, for the app), by
/// the names the page draws, in its order. Android's rows are listed on Android only, the meetings whether or not
/// this build has the service that records them: there the search opens the page.
List<SettingsFindable> recordingFindable({required bool android}) => [
      const SettingsFindable('Stop when I go quiet', 'silence auto stop'),
      const SettingsFindable('Review after recording', 'check transcript'),
      const SettingsFindable('Better words', 'refine clean up transcript'),
      const SettingsFindable('Summaries', 'summary meeting write-up minutes long voice notes'),
      if (android) ...const [
        SettingsFindable('Include sound from other apps', 'system audio media games screen share meeting record'),
        SettingsFindable('Tell me when a meeting is written up', 'notification notify alert written up'),
        SettingsFindable('Write up straight away', 'meeting battery charging background'),
      ],
      // The desktop's own Meetings card: one switch, for the computer's sound.
      if (!android) const SettingsFindable("Record the computer's sound too", 'system audio meeting call both sides zoom'),
      const SettingsFindable('Tapes', 'your tapes storage audio remove space'),
      const SettingsFindable('Remove audio older than a month', 'storage space delete recordings audio'),
    ];

/// Recording's row in the list: what a take becomes, better words or the words as heard.
String recordingSummary(Preferences prefs) => prefs.refine ? 'Better words' : 'Words as heard';

/// Port of `RecordingPane` (src/app/settings/RecordingPane.tsx): the microphone and what happens to a take. While
/// recording, After recording, the Summaries as three picks with a hint each, the Meetings, and the Tapes. The page's
/// words say where the work is done: "the phone" on Android, "this Mac" elsewhere.
///
/// Every switch and pick is a stored preference and is live in `preferences` at once: `quietStop`, `review`,
/// `refine`, `summaries`, `writeUp` and `meetingSound`.
///
/// What differs from the web original: there is no recorder, no meeting service and no tape store yet (stage 8), so
/// what needs one is asked of [features] and marked where it is missing.
/// - **Meetings** on Android is drawn only where this build has the meeting service ([SettingsFeatures.meetings],
///   the web's native generation 20). Its "Tell me when a meeting is written up" shows On or the word Allow, which
///   cannot be pressed until [SettingsFeatures.onAllowMeetingNotices] is given. The row for a meeting's own sound has
///   its switch only where the device can ([SettingsFeatures.meetingSound]), and otherwise says why when it is told.
/// - **Tapes**: the page's card read the notes and asked each tape's file itself (`listNotes`, `headStatus`); here
///   whoever holds the notes counts (the app's root, over lib/settings/tapes.dart and tapes_here.dart), and the
///   card asks for the files to be asked as it is put up ([SettingsFeatures.onCountTapes]). The room is
///   [SettingsFeatures.tapes], which with no tape store reads "No tapes on this device." (the page's "being
///   counted" has nothing to count here), and Remove is there once [SettingsFeatures.onRemoveOldAudio] is, asking
///   twice as the page's does. The page's "Update Ghost.md to remove audio here." is not said: there is no newer
///   build that could.
/// - The two rows the recorder reads, and the summaries, change nothing more than the preference until then.
class RecordingPane extends StatefulWidget {
  const RecordingPane({super.key, this.store, this.features = const SettingsFeatures(), this.android});

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;
  final SettingsFeatures features;

  /// Whether this is an Android phone; asked of the platform when null.
  final bool? android;

  static Widget hosted(BuildContext context) => RecordingPane(features: SettingsHost.maybeOf(context)?.features ?? const SettingsFeatures());

  @override
  State<RecordingPane> createState() => _RecordingPaneState();
}

class _RecordingPaneState extends State<RecordingPane> {
  /// What a removal did, or why it could not: the Tapes card's footer in place of the room.
  String? _said;

  /// Allow was pressed and the phone refused outright.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    // Each tape's file is asked whether it is on this device, as the page's Tapes card asked when it was put up.
    widget.features.onCountTapes?.call();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store ?? preferences;
    final features = widget.features;
    final android = widget.android ?? defaultTargetPlatform == TargetPlatform.android;
    // Where the model does its work.
    final device = android ? 'the phone' : 'this Mac';
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        void set(Preferences Function(Preferences now) change) => store.update(change);

        // The switch for a meeting's own sound (`MeetingSound`), with the honest limit under it.
        final sound = SettingRow(
          label: android ? 'Include sound from other apps' : "Record the computer's sound too",
          hint: Text(
            android
                ? 'Android lets Ghost.md hear media and games, never calls. It asks to share your screen each time; only the sound is kept.'
                : 'Both sides of a call: what this Mac plays goes into the recording with the microphone. macOS asks the first time.',
          ),
          control: features.meetingSound
              ? GlacierSwitch(ariaLabel: android ? 'Include sound from other apps' : "Record the computer's sound too", checked: prefs.meetingSound, onCheckedChange: (on) => set((now) => now.copyWith(meetingSound: on)))
              : null,
          disabledReason: features.meetingSound ? null : features.meetingSoundWhy,
        );

        final canNotify = features.canNotifyMeetings;
        final allow = features.onAllowMeetingNotices;
        final bytes = features.tapes ?? 0;
        final remove = features.onRemoveOldAudio;

        return PaneBody(
          children: [
            PaneSection(
              title: 'While recording',
              children: [
                SettingRow(
                  label: 'Stop when I go quiet',
                  hint: Text(
                    android
                        ? "Saves after four seconds of quiet, once you've started talking. The side key and Done still work."
                        : "Saves after four seconds of quiet, once you've started talking. Done still works.",
                  ),
                  control: GlacierSwitch(ariaLabel: 'Stop when I go quiet', checked: prefs.quietStop, onCheckedChange: (on) => set((now) => now.copyWith(quietStop: on))),
                ),
                SettingRow(
                  label: 'Review after recording',
                  hint: const Text('After you stop, a slower listen and a read-through, with what it would fix for you to keep. For recordings under three minutes.'),
                  control: GlacierSwitch(ariaLabel: 'Review after recording', checked: prefs.review, onCheckedChange: (on) => set((now) => now.copyWith(review: on))),
                ),
              ],
            ),
            PaneSection(
              title: 'After recording',
              children: [
                SettingRow(
                  label: 'Better words',
                  hint: Text('A larger model goes over the recording and fixes the words. A few seconds of $device per minute of speech.'),
                  control: GlacierSwitch(ariaLabel: 'Better words after recording', checked: prefs.refine, onCheckedChange: (on) => set((now) => now.copyWith(refine: on))),
                ),
              ],
            ),
            PaneSection(
              title: 'Summaries',
              description: Text('The language model on $device writes a summary under the title. What was said, what was decided, and your to-dos.'),
              children: [
                // Which recordings are summarised on their own (`summaryChoices`), each with what it means.
                for (final (value, label, hint) in <(String, String, String?)>[
                  ('meetings', 'Meetings', 'Every meeting, once it is done.'),
                  ('long', 'Meetings and long voice notes', 'A long voice note is one over three minutes. A few minutes of $device for each.'),
                  ('off', 'Off', null),
                ])
                  SettingRow(
                    key: ValueKey('summaries-$value'),
                    label: label,
                    hint: hint == null ? null : Text(hint),
                    control: Pick(checked: prefs.summaries == value, label: label, onPress: () => set((now) => now.copyWith(summaries: value))),
                  ),
              ],
            ),
            if (android && features.meetings)
              PaneSection(
                title: 'Meetings',
                children: [
                  sound,
                  SettingRow(
                    label: 'Tell me when a meeting is written up',
                    hint: Text(
                      _blocked && !canNotify
                          ? 'Notifications are off for Ghost.md in the phone’s settings.'
                          : 'A notification, with the first line of the summary once the phone is unlocked.',
                    ),
                    value: canNotify ? const Text('On') : null,
                    control: canNotify
                        ? null
                        : RowAction(
                            onPress: () {
                              if (allow != null && !allow()) setState(() => _blocked = true);
                            },
                            disabled: allow == null,
                            child: const Text('Allow'),
                          ),
                  ),
                  SettingRow(
                    label: 'Write up straight away',
                    hint: const Text('Off, a meeting is written up when the phone is charging or above half. On, straight away, which uses more of the battery.'),
                    control: GlacierSwitch(
                      ariaLabel: 'Write up straight away',
                      checked: prefs.writeUp == 'now',
                      onCheckedChange: (now) => set((was) => was.copyWith(writeUp: now ? 'now' : 'charging')),
                    ),
                  ),
                ],
              ),
            if (!android) PaneSection(title: 'Meetings', children: [sound]),
            // Tapes: the room the recordings take on this device, and the way to give back the room the old ones take.
            PaneSection(
              title: 'Tapes',
              footer: Text(_said ?? (bytes <= 0 ? 'No tapes on this device.' : 'Your tapes take about ${tapeSize(bytes)} on this device.')),
              children: [
                SettingRow(
                  label: 'Remove audio older than a month',
                  hint: const Text('Every word and phrase stays. Only the audio goes.'),
                  control: remove == null
                      ? null
                      : ArmedAction(
                          word: 'Remove',
                          busyWord: 'Removing',
                          disabled: features.oldTapes == 0,
                          onDo: () async {
                            final removed = await remove();
                            if (mounted) setState(() => _said = removed == 0 ? 'Nothing to remove.' : 'Removed the audio of ${removed == 1 ? 'one tape' : '$removed tapes'}. The words stay.');
                          },
                          onFailed: (why) => setState(() => _said = why),
                        ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
