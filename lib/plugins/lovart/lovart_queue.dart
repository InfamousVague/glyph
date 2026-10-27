/// Settings › Lovart's Queue: every picture Lovart is making on this device now, and the ones waiting their turn
/// (Matt, 2026-10-27: "Please show the lovart image queue in the lovart settings").
///
/// What it reads, each as it changes:
/// - **The run over the recent notes** (banner_run.dart): its queue as kept in the plugin's storage
///   ([keptBannerQueue]), the notes being made now first, then the rest in the run's order, each a header image, or
///   one made again where the run asked for it again (a banner taken off, or one redone in colour).
/// - **A header image made as a note is left, or from the note's menu** ([lovartBannerMaking]).
/// - **An `{image: …}` being made** ([lovartMaking]), with its prompt.
/// - **An inspiration moodboard** being made, asked on a note or for a design meeting ([lovartInspiring]).
/// - **A run on another of the account's devices** ([BannerRun.elsewhere]): said in one line, since its notes are that
///   device's to list.
///
/// Each row is the note's title over what is made for it, and "Making" or its place in line. The first [queueShown]
/// waiting are listed and the rest counted, with what the whole queue will cost at [lovartCreditsPerImage] a picture.
library;

import 'package:flutter/widgets.dart';

import '../../core/note.dart' show Note;
import '../../core/note_text.dart' show noteTitle;
import '../../settings/kit/settings_kit.dart';
import '../host.dart' show onPluginStorage;
import 'banner_run.dart' show BannerQueue, BannerRun, bannerElsewhereWords, keptBannerQueue, lovartBannerJob, lovartBannerRun;
import 'banners.dart' show lovartBannerMaking;
import 'client.dart' show lovartCreditsPerImage;
import 'inspiration.dart' show inspirationCount;
import 'making.dart';

/// How many waiting pictures are listed before the rest are only counted.
const int queueShown = 20;

/// What a picture in the queue is.
enum QueueKind { header, headerAgain, headerRedo, picture, inspiration }

/// One line of the queue: whose, what, and whether it is being made or waits.
@immutable
class QueueItem {
  const QueueItem({required this.noteId, required this.kind, this.prompt = '', this.making = false});
  final String noteId;
  final QueueKind kind;

  /// A cue's prompt.
  final String prompt;
  final bool making;

  /// How many pictures it is.
  int get images => kind == QueueKind.inspiration ? inspirationCount : 1;

  /// What is made for the note, in words.
  String get what => switch (kind) {
    QueueKind.header => 'Header image',
    QueueKind.headerAgain => 'Header image, made again',
    QueueKind.headerRedo => 'Header image, redone in colour',
    QueueKind.picture => prompt.isEmpty ? 'Picture' : 'Picture: $prompt',
    QueueKind.inspiration => 'Inspiration, $inspirationCount images',
  };
}

final RegExp _cue = RegExp(r'^\{\s*image\s*:\s*([\s\S]*?)\s*\}$', caseSensitive: false);

/// The queue now: what is being made first, then what waits, in turn. Pure, for a test to ask.
List<QueueItem> lovartQueue({
  BannerQueue? run,
  Set<String> headers = const {},
  Set<String> cues = const {},
  Set<String> inspiring = const {},
}) {
  final items = <QueueItem>[];
  final seen = <String>{};
  QueueKind headerKind(String id) => run == null ? QueueKind.header : (run.replacing.containsKey(id) ? QueueKind.headerRedo : (run.again.contains(id) ? QueueKind.headerAgain : QueueKind.header));
  // Making now: the run's notes in hand, then any other header being made, then pictures and moodboards.
  for (final id in [...?run?.going, ...headers]) {
    if (seen.add(id)) items.add(QueueItem(noteId: id, kind: headerKind(id), making: true));
  }
  for (final key in cues) {
    final cut = key.indexOf('\n');
    if (cut < 0) continue;
    final text = key.substring(cut + 1);
    items.add(QueueItem(noteId: key.substring(0, cut), kind: QueueKind.picture, prompt: _cue.firstMatch(text.trim())?.group(1) ?? text, making: true));
  }
  for (final id in inspiring) {
    items.add(QueueItem(noteId: id, kind: QueueKind.inspiration, making: true));
  }
  // Waiting: the rest of the run, in its order.
  for (final id in run?.left ?? const <String>[]) {
    if (!seen.contains(id)) items.add(QueueItem(noteId: id, kind: headerKind(id)));
  }
  return items;
}

/// The Queue section of the Lovart page.
class LovartQueueSection extends StatefulWidget {
  const LovartQueueSection({super.key, this.titles});

  /// The notes' titles by id; the run's own notes where not given.
  final Map<String, String> Function()? titles;

  @override
  State<LovartQueueSection> createState() => _LovartQueueSectionState();
}

class _LovartQueueSectionState extends State<LovartQueueSection> {
  late final VoidCallback _unStorage;
  late final Listenable _heard = Listenable.merge([lovartBannerRun, lovartBannerMaking, lovartMaking, lovartInspiring]);

  @override
  void initState() {
    super.initState();
    _unStorage = onPluginStorage(_redraw);
    _heard.addListener(_redraw);
  }

  @override
  void dispose() {
    _unStorage();
    _heard.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Map<String, String> _titles() {
    final given = widget.titles;
    if (given != null) return given();
    final notes = lovartBannerJob?.notes() ?? const <Note>[];
    return {for (final note in notes) note.id: noteTitle(note.body)};
  }

  @override
  Widget build(BuildContext context) {
    final items = lovartQueue(run: keptBannerQueue(), headers: lovartBannerMaking.value, cues: lovartMaking.value, inspiring: lovartInspiring.value);
    final BannerRun? run = lovartBannerRun.value;
    final elsewhere = run?.elsewhere;
    final titles = items.isEmpty ? const <String, String>{} : _titles();
    final making = items.where((item) => item.making).toList();
    final waiting = items.where((item) => !item.making).toList();
    final images = items.fold<int>(0, (sum, item) => sum + item.images);
    String titleOf(QueueItem item) {
      final title = titles[item.noteId] ?? '';
      return title.isEmpty ? 'Untitled' : title;
    }

    final rows = <Widget>[
      if (items.isEmpty && elsewhere == null)
        const SettingRow(key: ValueKey('lovart-queue-empty'), label: 'Nothing waiting', hint: Text('Pictures being made, and the header images waiting their turn, show here.')),
      if (elsewhere != null) SettingRow(key: const ValueKey('lovart-queue-elsewhere'), label: 'On another device', hint: Text(bannerElsewhereWords(elsewhere))),
      for (final item in making)
        SettingRow(key: ValueKey('lovart-queue-making-${item.kind.name}-${item.noteId}-${item.prompt}'), label: titleOf(item), hint: Text(item.what), value: const Text('Making')),
      for (final (index, item) in waiting.take(queueShown).indexed)
        SettingRow(key: ValueKey('lovart-queue-waiting-${item.noteId}'), label: titleOf(item), hint: Text(item.what), value: Text('${index + 1}')),
      if (waiting.length > queueShown)
        SettingRow(key: const ValueKey('lovart-queue-more'), label: 'And ${waiting.length - queueShown} more waiting'),
    ];
    return PaneSection(
      title: 'Queue',
      description: items.isEmpty
          ? null
          : Text('${making.length} making, ${waiting.length} waiting on this device: about ${images * lovartCreditsPerImage} credits for the ${images == 1 ? 'picture' : '$images pictures'} still to make.'),
      children: rows,
    );
  }
}
