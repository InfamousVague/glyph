/// A note as a Discord message: its title as a heading, then its words in Discord's own Markdown (Matt, 2026-10-26:
/// "Add a new plugin to post notes to discord chats"). The Slack plugin's mrkdwn.dart, for a chat that reads
/// Markdown already.
///
/// Discord reads most of it as it is: `**bold**`, `*italic*` and `_italic_`, `~~struck~~`, `` `code` `` and fences,
/// `>` quotes, `-` and `1.` lists at their indent, `#`, `##` and `###` headings, and `[words](https://…)` links. What
/// it reads differently, or not at all, is turned, line by line, and the rest goes as written:
///
/// - **`__words__` is underline in Discord**, bold in Markdown: it goes as `**words**`, what the note meant.
/// - **Headings.** Discord has three sizes and its first is a shout in a chat: the message's title is a `##`, the
///   note's own `#` and `##` are `###`, and anything deeper a bold line.
/// - **A to-do** is `- ☐` or `- ☑` (Discord draws no boxes), a `*` or `+` bullet a `-`, a rule `———` (Discord draws
///   none), and a table goes in a code block, where its columns at least line up, since Discord draws no tables.
/// - **Links**: a link into the app (a note, a picture on the phone) is its words alone, since nobody in the channel
///   can open it; a picture with a web address is a link to it, and one on the phone is left out.
/// - **Discord's own marks in plain words**: `||words||` is a spoiler in Discord and one of the Marks plugin's looks
///   here, so it goes as its words, as the other looks do; a line opening `-# ` (Discord's small print) is escaped.
///   A redaction (`@@…@@`) goes as a bar: words drawn hidden on the page are not handed to a whole channel in the
///   clear, and a spoiler is one tap from the clear. `@everyone` and `<@id>` are left as written, and ping nobody:
///   the post sends `allowed_mentions` empty (channels.dart).
/// - Code, in backticks or a fence, goes as written. A `~~~` fence is a ``` one, which Discord reads.
/// - Front matter is dropped, and so is the title line, which the message already opens with.
///
/// LENGTH: Discord takes [discordContentMost] (2000) characters in a message's `content`. A longer note is **one
/// message, cut** at a line a little before that, ending with a link to the rest ([discordFitted]): the note's
/// share link where one is handed over (discord.dart makes it, and the row says so before it is pressed), else a word
/// that the rest is in Ghost.md. Why not embeds (4096 in one's description, 6000 across ten): an embed is a boxed
/// card in small type, where a heading is not drawn as one in every client, so a long note would read as something
/// else than a short one; and 6000 only moves the cut, it does not end it. Why not several messages: a webhook takes
/// a few posts a second before its 429, and a note half-posted when one lands is worse than a note cut where it
/// says so. Lengths are counted in UTF-16 units, never fewer than Discord's characters, and a cut never splits a
/// pair of them or leaves a fence open.
library;

import '../../core/front_matter.dart' show frontMatterEnd;
import '../../core/note_text.dart' show noteTitle, withoutFrontMatter;
import 'channels.dart' show discordContentMost;

/// A hidden marker for a span set aside while the line around it is converted. Never typed: a control character.
const String _held = '\u0000';

/// Markdown's punctuation, backslashed: Discord's parser takes `\` before any of it as the character itself.
final RegExp _punctuation = RegExp(r'([\\*_~`|\[\]<>#])');

/// Words written into a message as they are, every mark of Discord's escaped: a title, a team's name, a person's.
String discordEscaped(String text) => text.replaceAllMapped(_punctuation, (m) => '\\${m[1]}');

/// An address inside `(…)`: the characters that would end it early, percent-encoded.
String discordLinkUrl(String href) => href.replaceAll('(', '%28').replaceAll(')', '%29').replaceAll(' ', '%20');

final RegExp _web = RegExp(r'^(?:https?:\/\/|mailto:)', caseSensitive: false);
final RegExp _code = RegExp(r'`[^`\n]+`');
final RegExp _picture = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final RegExp _link = RegExp(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final RegExp _marksInLabel = RegExp(r'\*\*|__|~~|`|\[|\]');
final RegExp _bare = RegExp(r'<((?:https?:\/\/|mailto:)[^>\s]+)>', caseSensitive: false);
final RegExp _redaction = RegExp(r'@@(\S(?:[^@]*?\S)?)@@');
final RegExp _look = RegExp(r'(\|\||==|%%|\^\^)(\S(?:.*?\S)?)\1');
// The analyzer reads the pattern without `unicode: true`, where `\p{…}` is not one (Slack's mrkdwn.dart has it too).
// ignore: valid_regexps
final RegExp _effect = RegExp(r'(\p{Extended_Pictographic}️?)\1(\S(?:.*?\S)?)\1\1', unicode: true);
final RegExp _unders = RegExp(r'(^|[^_\w])__(\S(?:.*?\S)?)__(?![_\w])');
final RegExp _heldBack = RegExp('$_held(\\d+)$_held');

/// One line's inline marks, as Discord reads them.
String _inline(String line) {
  final held = <String>[];
  String hold(String made) {
    held.add(made);
    return '$_held${held.length - 1}$_held';
  }

  final text = line
      // Code first, so nothing inside it is read as a mark.
      .replaceAllMapped(_code, (m) => hold(m[0]!))
      // A picture: a link when it is on the web, and nothing when it is on the phone.
      .replaceAllMapped(_picture, (m) {
        final alt = m[1]!.replaceAll(_marksInLabel, '').trim();
        return _web.hasMatch(m[2]!) ? hold('[${alt.isEmpty ? 'picture' : alt}](${discordLinkUrl(m[2]!)})') : '';
      })
      // A link: Discord's own, or its words where the address is the app's.
      .replaceAllMapped(_link, (m) {
        final words = m[1]!, href = m[2]!;
        if (!_web.hasMatch(href)) return words;
        final label = words.replaceAll(_marksInLabel, '').trim();
        return hold(label.isNotEmpty ? '[$label](${discordLinkUrl(href)})' : '<$href>');
      })
      // An address written `<https://…>` is already one Discord links.
      .replaceAllMapped(_bare, (m) => hold(m[0]!))
      // A redaction is a bar; the other looks are their words.
      .replaceAllMapped(_redaction, (m) => '▇' * m[1]!.length.clamp(3, 12))
      .replaceAllMapped(_look, (m) => m[2]!)
      .replaceAllMapped(_effect, (m) => m[2]!)
      // Markdown's other bold, which Discord would underline.
      .replaceAllMapped(_unders, (m) => '${m[1]}**${m[2]}**');
  return text.replaceAllMapped(_heldBack, (m) {
    final n = int.parse(m[1]!);
    return n < held.length ? held[n] : '';
  });
}

final RegExp _fence = RegExp(r'^\s*(```|~~~)(.*)$');
final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)(?:\s+#+)?\s*$');
final RegExp _todo = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _tableRow = RegExp(r'^\s*\|.*\|\s*$');
final RegExp _tableRule = RegExp(r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$');
final RegExp _subtext = RegExp(r'^(\s*)-#');
final RegExp _boldMarks = RegExp(r'\*\*|__');
final RegExp _blankRun = RegExp(r'\n{3,}');

/// A heading's words with no marks of their own: Discord draws a heading bold already.
String _headingWords(String words) => _inline(words.replaceAll(_boldMarks, ''));

/// Markdown lines as Discord's, with runs of blank lines made one.
String toDiscordMarkdown(String markdown) {
  final lines = markdown.split('\n');
  final out = <String>[];
  var inCode = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null && (!inCode || fence[2]!.trim().isEmpty)) {
      inCode = !inCode;
      out.add('```${inCode ? fence[2]!.trim() : ''}');
      continue;
    }
    if (inCode) {
      out.add(line);
      continue;
    }
    // A table: its rows, rule and all, as they are, in a block of code where the columns line up.
    if (_tableRow.hasMatch(line) && i + 1 < lines.length && _tableRule.hasMatch(lines[i + 1])) {
      out.add('```');
      while (i < lines.length && _tableRow.hasMatch(lines[i])) {
        out.add(lines[i].trim());
        i++;
      }
      i--;
      out.add('```');
      continue;
    }
    final heading = _heading.firstMatch(line);
    final todo = _todo.firstMatch(line);
    final bullet = _bullet.firstMatch(line);
    final quote = _quote.firstMatch(line);
    if (heading != null) {
      final words = _headingWords(heading[2]!);
      if (words.trim().isEmpty) {
        out.add('');
      } else {
        out.add(heading[1]!.length <= 2 ? '### $words' : '**$words**');
      }
    } else if (todo != null) {
      out.add('${todo[1]}- ${todo[2] == ' ' ? '☐' : '☑'} ${_inline(todo[3]!)}');
    } else if (_rule.hasMatch(line)) {
      out.add('———');
    } else if (bullet != null) {
      out.add('${bullet[1]}- ${_inline(bullet[2]!)}');
    } else if (quote != null) {
      out.add('> ${_inline(quote[1]!)}');
    } else {
      out.add(_inline(line).replaceFirstMapped(_subtext, (m) => '${m[1]}\\-#'));
    }
  }
  if (inCode) out.add('```');
  return out.join('\n').replaceAll(_blankRun, '\n\n').trim();
}

final RegExp _pictureLine = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

/// The note's words after its front matter and its title line: what follows the title in the message. The title
/// line goes and the rest stays; a list item that opens the note stays too, as the Slack post keeps it.
String _bodyAfterTitle(String body) {
  final words = withoutFrontMatter(body.split('\n'));
  final first = words.indexWhere((l) => l.trim().isNotEmpty && !_pictureLine.hasMatch(l));
  if (first >= 0 && !_todo.hasMatch(words[first]) && !_bullet.hasMatch(words[first])) words.removeAt(first);
  return words.join('\n');
}

final RegExp _itemStart = RegExp(r'^[-*+]\s+(?:\[[ xX]\]\s+)?');

/// A title as the heading a message opens with; an untitled note is "Untitled".
String discordTitleLine(String title) {
  final words = _headingWords(title.replaceFirst(_itemStart, '')).trim();
  return '## ${words.isEmpty ? 'Untitled' : words}';
}

/// The whole note as Discord's Markdown, at whatever length: the title, then the rest.
String discordNoteText(String body) {
  final rest = toDiscordMarkdown(_bodyAfterTitle(body));
  final title = discordTitleLine(noteTitle(body));
  return rest.isNotEmpty ? '$title\n$rest' : title;
}

/// A meeting's summary as Discord's Markdown: the note's title, then the section (`## Summary` and what is under it).
String discordSummaryText(String body, String section) => '${discordTitleLine(noteTitle(body))}\n${toDiscordMarkdown(section)}';

/// Whether [text] is longer than one message: the post is cut, with a link to the rest.
bool discordTooLong(String text) => text.length > discordContentMost;

final RegExp _fenceLine = RegExp(r'^```', multiLine: true);

/// [message] as one message: as it is when it fits, else cut at a line a little before [discordContentMost], a
/// fence it leaves open closed, and [rest] (the note's share link) to read the rest by, or a word that the rest is in
/// Ghost.md without one.
String discordFitted(String message, {String? rest}) {
  if (message.length <= discordContentMost) return message;
  final tail = rest != null && rest.isNotEmpty ? '\n…\n**[Read the rest in Ghost.md](${discordLinkUrl(rest)})**' : '\n…\n*The rest is in Ghost.md: it is longer than one Discord message.*';
  // Room for the tail, and for a fence closed.
  final most = discordContentMost - tail.length - 4;
  var end = most;
  final unit = message.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
  var cut = message.substring(0, end);
  final at = cut.lastIndexOf('\n');
  if (at > most / 2) cut = cut.substring(0, at);
  if (_fenceLine.allMatches(cut).length.isOdd) cut = '$cut\n```';
  return '$cut$tail';
}

/// The whole note as a message, cut to fit ([discordFitted]) with [rest] to read the rest by.
String discordNoteMessage(String body, {String? rest}) => discordFitted(discordNoteText(body), rest: rest);

/// A meeting's summary as a message, cut to fit with [rest].
String discordSummaryMessage(String body, String section, {String? rest}) => discordFitted(discordSummaryText(body, section), rest: rest);

/// One line's words as Discord's: its inline marks turned and the rest as written, as a line of [toDiscordMarkdown]
/// is. For a message made of pieces of a note: a meeting's action items (meetings.dart).
String discordInline(String line) => _inline(line);

/// One line's words with no marks at all, escaped: for words set inside a mark of the message's own (a meeting's
/// one sentence in italics), where a mark of the note's would end it early.
String discordPlain(String line) => discordEscaped(line.replaceAll(RegExp(r'\*\*|__|~~|\*|`'), ''));

/// Whether a note has anything to post: words past its front matter.
bool discordHasWords(String body) {
  final lines = body.split('\n');
  return lines.skip(frontMatterEnd(lines)).any((l) => l.trim().isNotEmpty);
}
