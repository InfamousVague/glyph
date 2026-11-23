/// The Export conversation rows' work (GMFB-36; lib/export_chat.dart): the messages read, written as Markdown, and
/// saved where the person says.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../export_chat.dart';
import '../files/file_platform.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/hangout.dart';
import 'common.dart';

/// The most messages of a conversation of texts an export reads.
const exportMost = 20000;

/// Exports the conversation of texts (or with a friend) [thread], called [title], with [people] in it.
Future<void> exportTexts(BuildContext context, int thread, String title, List<Person> people) async {
  final byAddress = {for (final p in people) p.address: p.label};
  final List<Message> all;
  try {
    all = await Sms.instance.messages(thread, limit: exportMost);
  } catch (e) {
    if (context.mounted) toast(context, 'The messages couldn\'t be read: $e', tone: GlacierToastTone.danger);
    return;
  }
  final lines = <ExportLine>[
    for (final m in all)
      if (m.notice == null)
        (
          at: m.date,
          who: m.outgoing ? 'You' : (byAddress[m.address] ?? (people.length == 1 ? people.first.label : m.address)),
          text: m.body,
          files: [for (final a in m.attachments) a.name ?? a.type],
          replyTo: null,
          edited: m.edited,
        ),
  ];
  if (!context.mounted) return;
  await _save(context, title, lines);
}

/// Exports [room]'s chat, its threads among it.
Future<void> exportSpace(BuildContext context, HangoutRoom room) =>
    _save(context, room.channel.name, spaceLines(room, nameOf: Voice.instance.nameOf), where: 'a space');

Future<void> _save(BuildContext context, String title, List<ExportLine> lines, {String? where}) async {
  if (lines.isEmpty) {
    toast(context, 'There\'s nothing to export yet');
    return;
  }
  if (!FilePlatform.canSave) {
    toast(context, 'This device can\'t save files yet');
    return;
  }
  final name = exportName(title);
  final path = await writeExport(chatMarkdown(title, lines, where: where), name);
  final done = await FilePlatform.save(path, name, 'text/markdown');
  if (context.mounted && done != null) toast(context, '$done: ${lines.length == 1 ? '1 message' : '${lines.length} messages'}');
}
