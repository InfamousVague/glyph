import 'package:flutter/widgets.dart';

import '../../core/locale_dates.dart';
import '../../watch/watch_link.dart';
import '../kit/settings_kit.dart';

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
class WatchSection extends StatelessWidget {
  const WatchSection({super.key, required this.status});

  final WatchStatus status;

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
      ],
    );
  }
}
