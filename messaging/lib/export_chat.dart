/// Exporting a conversation (GMFB-36, from the Uplink gap review: importing and exporting conversations was in Warp's
/// backlog, #373): its messages as a Markdown file, saved where the person says (a phone's Save to, a Mac's save panel,
/// Downloads elsewhere).
///
/// Markdown because it is plain text any app opens, and what the sister app Ghost.md keeps notes in: a heading with the
/// conversation's name and when it was exported, a heading for each day, and each message as "**Name** 14:05" over its
/// words, with any pictures or files named under it. Pictures and files themselves stay in the app.
library;

import 'dart:io';

import 'voice/hangout.dart';

/// One message as an export writes it, whatever kind of conversation it came from.
typedef ExportLine = ({DateTime at, String who, String text, List<String> files, String? replyTo, bool edited});

/// [lines] as Markdown under [title], oldest first; [now] says when it was exported.
String chatMarkdown(String title, List<ExportLine> lines, {DateTime? now, String? where}) {
  final out = StringBuffer();
  final at = now ?? DateTime.now();
  out.writeln('# $title');
  out.writeln();
  out.writeln('Exported from Ghost Messaging on ${_day(at)} at ${_time(at)}${where == null ? '' : ' · $where'} · ${lines.length == 1 ? '1 message' : '${lines.length} messages'}');
  final sorted = [...lines]..sort((a, b) => a.at.compareTo(b.at));
  String? day;
  for (final l in sorted) {
    final d = _day(l.at);
    if (d != day) {
      day = d;
      out.writeln();
      out.writeln('## $d');
    }
    out.writeln();
    out.writeln('**${_escape(l.who)}** ${_time(l.at)}${l.edited ? ' (edited)' : ''}');
    if (l.replyTo != null && l.replyTo!.isNotEmpty) out.writeln('> ${l.replyTo!.replaceAll('\n', ' ')}');
    final words = l.text.trim();
    if (words.isNotEmpty) {
      // A line break kept as one: two spaces at a line's end.
      out.writeln(words.split('\n').join('  \n'));
    }
    for (final f in l.files) {
      out.writeln('- 📎 ${_escape(f)}');
    }
  }
  return out.toString();
}

/// A space's chat as export lines: the chat and its threads, a thread's replies under a quote of where they hang.
List<ExportLine> spaceLines(HangoutRoom room, {String Function(String id)? nameOf}) => [
      for (final m in room.messages)
        (
          at: DateTime.fromMillisecondsSinceEpoch(m.at),
          who: m.from == room.me ? 'You' : (m.name.isNotEmpty ? m.name : (nameOf?.call(m.from) ?? 'Someone')),
          text: m.poll != null ? '📊 ${m.text}' : (m.sticker != null && m.text.isEmpty ? 'Sticker' : m.text),
          files: [for (final f in m.files) f.name],
          replyTo: m.reply == null ? null : '${m.thread != null ? 'In the thread on' : 'Replying to'} ${m.reply!.name}: ${m.reply!.text}',
          edited: m.edited != null,
        ),
    ];

/// A file name made from [title] for the export: what a file system takes, and the day.
String exportName(String title, {DateTime? now}) {
  final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final d = now ?? DateTime.now();
  return '${clean.isEmpty ? 'Conversation' : (clean.length > 60 ? clean.substring(0, 60).trim() : clean)} ${_day(d)}.md';
}

/// Writes [markdown] to a file of the app's own to hand to Save: its path.
Future<String> writeExport(String markdown, String name) async {
  final dir = await Directory.systemTemp.createTemp('ghost-export');
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsString(markdown);
  return f.path;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// A name's Markdown marks made plain.
String _escape(String s) => s.replaceAllMapped(RegExp(r'([*_`\[\]#])'), (m) => '\\${m[1]}');
