/// A note as a Slack message: its title as a bold first line, then its words in Slack's own markup, mrkdwn. A port
/// of `src/app/plugins/slack/mrkdwn.ts`.
///
/// Slack does not read Markdown. It has its own, smaller markup: `*bold*`, `_italic_`, `~strike~`, `` `code` ``,
/// ``` fences, `>` quotes and links as `<url|words>`, and it wants `&`, `<` and `>` written as entities everywhere
/// else. So the obvious Markdown is turned into that, line by line, and the rest goes as the words it is:
///
/// - `**bold**` and `__bold__` are `*bold*`; `*italic*` is `_italic_`; `~~struck~~` is `~struck~`.
/// - A heading is a bold line. A to-do is ☐, a ticked one ☑, and a bullet •, at the indent it had.
/// - `[words](https://…)` is `<https://…|words>`; a link into the app (a note, a picture on the phone) is its words
///   alone, since nobody in the channel can open it. A picture with a web address is a link to it; one on the phone
///   is left out.
/// - Code, in backticks or a fence, goes as it was written, escaped and nothing more.
/// - The Marks plugin's looks go as plain words, except a redaction (`@@…@@`), which goes as a bar: words drawn
///   hidden on the page are not handed to a whole channel in the clear.
/// - Front matter is dropped, and so is the title line, which the message already opens with.
///
/// Slack takes 40,000 characters in a message; a longer note is cut a little before that, and says so.
///
/// What differs: nothing in what it answers. The expressions are the page's own, written for Dart's `RegExp`
/// (the same engine's syntax), and lengths are counted in UTF-16 units as the page counts them.
library;

import '../../core/front_matter.dart' show frontMatterEnd;
import '../../core/note_text.dart' show noteTitle, withoutFrontMatter;

/// A little under Slack's 40,000, so the closing words fit.
const int _most = 39000;

/// A hidden marker for a span set aside while the line around it is converted. Never typed: a control character.
const String _held = '\u0000';

/// Bold, while the single stars around it become italics.
const String _bold = '\u0001';

/// Slack's three escapes, everywhere outside its own link and quote marks.
String _escaped(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// An address inside `<…|…>`: the characters that would end it early, percent-encoded.
String _slackUrl(String href) => href.replaceAll('|', '%7C').replaceAll('>', '%3E').replaceAll('<', '%3C');

final RegExp _web = RegExp(r'^(?:https?:\/\/|mailto:)', caseSensitive: false);
final RegExp _code = RegExp(r'`[^`\n]+`');
final RegExp _picture = RegExp(r'!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final RegExp _link = RegExp(r'\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
final RegExp _marksInLabel = RegExp(r'\*\*|__|~~|`');
final RegExp _bare = RegExp(r'<((?:https?:\/\/|mailto:)[^>\s]+)>', caseSensitive: false);
final RegExp _redaction = RegExp(r'@@(\S(?:[^@]*?\S)?)@@');
final RegExp _look = RegExp(r'(\|\||==|%%|\^\^)(\S(?:.*?\S)?)\1');
final RegExp _effect = RegExp(r'(\p{Extended_Pictographic}️?)\1(\S(?:.*?\S)?)\1\1', unicode: true);
final RegExp _stars = RegExp(r'\*\*(\S(?:.*?\S)?)\*\*');
final RegExp _unders = RegExp(r'__(\S(?:.*?\S)?)__');
final RegExp _italic = RegExp(r'(^|[^*\w])\*(\S(?:[^*]*?\S)?)\*(?![*\w])');
final RegExp _struck = RegExp(r'~~(\S(?:.*?\S)?)~~');
final RegExp _heldBack = RegExp('$_held(\\d+)$_held');

/// One line's inline marks, as mrkdwn.
String _inline(String line) {
  final held = <String>[];
  String hold(String made) {
    held.add(made);
    return '$_held${held.length - 1}$_held';
  }

  var text = line
      // Code first, so nothing inside it is read as a mark.
      .replaceAllMapped(_code, (m) => hold(_escaped(m[0]!)))
      // A picture: a link when it is on the web, and nothing when it is on the phone.
      .replaceAllMapped(_picture, (m) {
        final alt = m[1]!.trim();
        return _web.hasMatch(m[2]!) ? hold('<${_slackUrl(m[2]!)}|${_escaped(alt.isEmpty ? 'picture' : alt)}>') : '';
      })
      // A link: Slack's own, or its words where the address is the app's.
      .replaceAllMapped(_link, (m) {
        final words = m[1]!, href = m[2]!;
        if (!_web.hasMatch(href)) return words;
        final label = words.replaceAll(_marksInLabel, '').trim();
        return hold(label.isNotEmpty ? '<${_slackUrl(href)}|${_escaped(label)}>' : '<${_slackUrl(href)}>');
      })
      // An address written `<https://…>` is already Slack's shape.
      .replaceAllMapped(_bare, (m) => hold('<${_slackUrl(m[1]!)}>'));
  text = _escaped(text)
      // A redaction is a bar; the other looks are their words.
      .replaceAllMapped(_redaction, (m) => '▇' * m[1]!.length.clamp(3, 12))
      .replaceAllMapped(_look, (m) => m[2]!)
      .replaceAllMapped(_effect, (m) => m[2]!)
      .replaceAllMapped(_stars, (m) => '$_bold${m[1]}$_bold')
      .replaceAllMapped(_unders, (m) => '$_bold${m[1]}$_bold')
      .replaceAllMapped(_italic, (m) => '${m[1]}_${m[2]}_')
      .replaceAllMapped(_struck, (m) => '~${m[1]}~')
      .replaceAll(_bold, '*');
  return text.replaceAllMapped(_heldBack, (m) {
    final n = int.parse(m[1]!);
    return n < held.length ? held[n] : '';
  });
}

final RegExp _fence = RegExp(r'^\s*(```|~~~)');
final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$');
final RegExp _todo = RegExp(r'^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _boldMarks = RegExp(r'\*\*|__');
final RegExp _blankRun = RegExp(r'\n{3,}');

/// Markdown lines as mrkdwn, with runs of blank lines made one (`toMrkdwn`).
String toMrkdwn(String markdown) {
  final out = <String>[];
  var inCode = false;
  for (final line in markdown.split('\n')) {
    if (_fence.hasMatch(line)) {
      inCode = !inCode;
      out.add('```');
      continue;
    }
    if (inCode) {
      out.add(_escaped(line));
      continue;
    }
    final heading = _heading.firstMatch(line);
    final todo = _todo.firstMatch(line);
    final bullet = _bullet.firstMatch(line);
    final quote = _quote.firstMatch(line);
    if (heading != null) {
      final words = _inline(heading[1]!.replaceAll(_boldMarks, '')).replaceAll('*', '');
      out.add(words.isNotEmpty ? '*$words*' : '');
    } else if (todo != null) {
      out.add('${todo[1]}${todo[2] == ' ' ? '☐' : '☑'} ${_inline(todo[3]!)}');
    } else if (_rule.hasMatch(line)) {
      out.add('———');
    } else if (bullet != null) {
      out.add('${bullet[1]}• ${_inline(bullet[2]!)}');
    } else if (quote != null) {
      // Slack's quote mark is a `>` of its own at the line's start, so it stays one, not an entity.
      out.add('> ${_inline(quote[1]!)}');
    } else {
      out.add(_inline(line));
    }
  }
  if (inCode) out.add('```');
  return out.join('\n').replaceAll(_blankRun, '\n\n').trim();
}

final RegExp _pictureLine = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

/// The note's words after its front matter and its title line: what follows the bold title in the message. The
/// title is the first line of words that is not a picture (lib/core/note_text.dart), or the front matter's `title:`,
/// which `withoutFrontMatter` puts first; that line goes and the rest stays. A list item that opens the note stays
/// too: it is the list's first item as well as the title.
String _bodyAfterTitle(String body) {
  final words = withoutFrontMatter(body.split('\n'));
  final first = words.indexWhere((l) => l.trim().isNotEmpty && !_pictureLine.hasMatch(l));
  if (first >= 0 && !_todo.hasMatch(words[first]) && !_bullet.hasMatch(words[first])) words.removeAt(first);
  return words.join('\n');
}

/// Cut to what Slack takes, at a line where it can be, and saying so.
String _fitted(String message) {
  if (message.length <= _most) return message;
  final cut = message.substring(0, _most);
  final at = cut.lastIndexOf('\n');
  return '${at > _most / 2 ? cut.substring(0, at) : cut}\n…\n_The rest is in Ghost.md: it is longer than one Slack message._';
}

final RegExp _itemStart = RegExp(r'^[-*+]\s+(?:\[[ xX]\]\s+)?');

/// A title as the bold line a message opens with; an untitled note is "Untitled".
String _titleLine(String title) {
  // A note that opens with a list is titled by its first item, box and all; the message's title is its words.
  final bare = title.replaceFirst(_itemStart, '');
  final words = _inline(bare.replaceAll(_boldMarks, '')).replaceAll('*', '');
  return '*${words.isEmpty ? 'Untitled' : words}*';
}

/// The whole note as a message: the title bold, then the rest. A note whose title is its only line is the title
/// alone; a list that opens a note is its own first line, so it stays in the message under the title it gives
/// (`noteMessage`).
String noteMessage(String body) {
  final rest = toMrkdwn(_bodyAfterTitle(body));
  return _fitted(rest.isNotEmpty ? '${_titleLine(noteTitle(body))}\n$rest' : _titleLine(noteTitle(body)));
}

/// A meeting's summary as a message: the note's title bold, then the section (`## Summary` and what is under it)
/// (`summaryMessage`).
String summaryMessage(String body, String section) => _fitted('${_titleLine(noteTitle(body))}\n${toMrkdwn(section)}');

/// Whether a note has anything to post: words past its front matter (`hasWords`).
bool hasWords(String body) {
  final lines = body.split('\n');
  return lines.skip(frontMatterEnd(lines)).any((l) => l.trim().isNotEmpty);
}
