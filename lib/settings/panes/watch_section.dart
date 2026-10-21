import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../../core/locale_dates.dart';
import '../../watch/watch_link.dart';
import '../kit/settings_kit.dart';

/// The switch's label.
const String watchClaudeLabel = 'Send short watch recordings to Claude';

/// "14:05" today, "18 Oct, 14:05" another day.
String watchWhen(int at, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(at);
  final today = now ?? DateTime.now();
  final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  if (date.year == today.year && date.month == today.month && date.day == today.day) return time;
  return '${localeDayMonth(date, DateForm.MMMd)}, $time';
}

/// "0:42", "12:05".
String watchLength(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The footer: the last voice note that came, and how many still wait to be made notes.
String? watchFooter(WatchStatus status, {DateTime? now}) {
  final lines = <String>[
    if (status.lastAt != null)
      'Last voice note${status.lastWatch == null || status.lastWatch!.isEmpty ? '' : ' from ${status.lastWatch}'} at ${watchWhen(status.lastAt!, now: now)}${status.lastMs == null || status.lastMs == 0 ? '' : ', ${watchLength(status.lastMs!)}'}.',
    if (status.waiting > 0) status.waiting == 1 ? 'One is waiting to be made a note.' : '${status.waiting} are waiting to be made notes.',
  ];
  return lines.isEmpty ? null : lines.join(' ');
}

/// Settings › Recording › Watch (docs/WATCH.md): the watches with Ghost.md connected now, and the last voice note one
/// sent. Drawn only where there is a watch to speak of ([WatchStatus.any]): a phone with no watch sees nothing new.
///
/// Under the watches, "Send short watch recordings to Claude" (lib/watch/watch_notes.dart, "To Claude"): on, and with
/// Claude shown here, a recording of up to ten minutes is a request Claude does, as one said to the dock's microphone
/// is; off, or with Claude not shown, it is a voice note.
class WatchSection extends StatelessWidget {
  const WatchSection({super.key, required this.status, this.claude = false, this.toClaude = true, this.onToClaude});

  final WatchStatus status;

  /// Whether Claude is shown here: its plugin on and a key on this device.
  final bool claude;

  /// The switch (`ClaudeSettings.watch`, kept on this device with the key), and its change.
  final bool toClaude;
  final ValueChanged<bool>? onToClaude;

  @override
  Widget build(BuildContext context) {
    final footer = watchFooter(status);
    return PaneSection(
      title: 'Watch',
      description: const Text('Tap Record on your Wear OS watch and the note is made here, its words heard by this phone.'),
      footer: footer == null ? null : Text(footer),
      children: [
        if (status.watches.isEmpty)
          const SettingRow(label: 'No watch connected', hint: Text('A voice note waits on the watch until it is near this phone.'))
        else
          for (final watch in status.watches) SettingRow(label: watch.name, value: Text(watch.nearby ? 'Connected' : 'Connected, not nearby')),
        SettingRow(
          label: watchClaudeLabel,
          hint: const Text('Up to ten minutes, the words go to Claude as if said to the microphone, to add to a note, make a list and so on; no note of its own is made and no audio kept. If Claude cannot do it, it is kept as a voice note. Longer recordings are meetings.'),
          control: claude ? GlacierSwitch(ariaLabel: watchClaudeLabel, checked: toClaude, onCheckedChange: onToClaude) : null,
          disabledReason: claude ? null : 'Switch Claude on and add your Anthropic API key in Settings › Plugins › Claude.',
        ),
      ],
    );
  }
}
