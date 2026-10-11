/// The tidy-up the model does not do, and the mess it sometimes makes. A port of `src/app/format/clean.ts`.
///
/// Matt: "the formatter can do things like double nest links and not clean up Notion task links to simply say
/// notion, and other basic formatting tasks". Two passes, both pure:
///
/// [cleanNote], before the model: an item whose words are one link to a Notion task - the old way of marking a sent
/// item, `- [ ] [Buy milk](https://www.notion.so/…)` - becomes the mark form, `- [ ] Buy milk [notion](…)`
/// (core/item_links.dart), so the model sees the words as words and the mark as the one thing to keep.
///
/// [cleanRewrite], after the links are back: a link inside a link's words (`[[Buy milk](url)](url)`, which a small
/// model writes now and then) is one link; an item's mark is once, and last; and the markdown is the plain kind the
/// prompts ask for - `-` bullets, `- [ ]` task boxes with their spaces, a space after `#`, no trailing spaces, no
/// run of blank lines. Words are never touched.
///
/// What differs: nothing a caller sees.
library;

import '../core/item_links.dart' show isMarkName;
import '../core/item_syntax.dart' show jsTrim, listLead;

final RegExp _notionHost = RegExp(r'^https?:\/\/(?:[a-z0-9-]+\.)?notion\.(?:so|site)\/', caseSensitive: false);

/// `[words](url)` where the words hold no link of their own.
final RegExp _link = RegExp(r'\[([^[\]]*)\]\((https?:\/\/[^\s()]+)\)');
final RegExp _spaces = RegExp(r'\s{2,}');
final RegExp _spaceBeforeStop = RegExp(r'\s+([.,;:!?])');

/// An item's line with one mark, last, for the Notion task it is linked to - whichever way the link was written: the
/// old form with the words as the link (`[Buy milk](notion-url)`, whole or mid-words), a mark the model moved or
/// doubled, or both at once. Words are unwrapped, never changed; a link to anywhere else is left where it is. A line
/// that is not an item, or holds no Notion link and no mark, comes back as it was.
String _markItem(String line) {
  final item = listLead(line);
  if (item == null) return line;
  final lead = line.substring(0, item.wordsAt);
  final words = line.substring(item.wordsAt);
  String? url;
  var name = 'notion';
  final stripped = jsTrim(
    words.replaceAllMapped(_link, (match) {
      final text = match.group(1) ?? '';
      final target = match.group(2) ?? '';
      if (isMarkName(text)) {
        // A mark: remembered, and taken out to go last.
        url ??= target;
        name = text;
        return '';
      }
      if (_notionHost.hasMatch(target)) {
        // The old form: the words stay as words.
        url ??= target;
        return text;
      }
      return match.group(0)!;
    }).replaceAll(_spaces, ' ').replaceAllMapped(_spaceBeforeStop, (match) => match.group(1)!),
  );
  if (url == null) return line;
  return '$lead$stripped${stripped.isNotEmpty ? ' ' : ''}[$name]($url)';
}

/// The note as the model should see it: Notion item links as marks.
String cleanNote(String body) => body.split('\n').map(_markItem).join('\n');

final RegExp _nested = RegExp(r'\[([^[\]]*\[[^[\]]*\]\([^\s()]+\)[^[\]]*)\]\((?:https?:\/\/[^\s()]+)\)');

/// `[[a](u)](v)` and `[a [b](u)](v)`: the inner link wins, the outer brackets go.
String _unnest(String text) {
  var out = text;
  // Repeat until nothing changes: a triple nest unwinds a layer at a time.
  for (var i = 0; i < 4; i += 1) {
    final next = out.replaceAllMapped(_nested, (match) => match.group(1)!);
    if (next == out) return out;
    out = next;
  }
  return out;
}

final RegExp _trailingBlanks = RegExp(r'[ \t]+$');
final RegExp _starBullet = RegExp(r'^(\s*)[*+] ');
final RegExp _looseBox = RegExp(r'^(\s*)-\s*\[\s*([xX ]?)\s*\]\s*');
final RegExp _tightHeading = RegExp(r'^(#{1,6})([^#\s])');

/// The rewrite, tidy: one link per link, marks once and last, plain markdown.
String cleanRewrite(String text) {
  final lines = _unnest(text).split('\n').map((raw) {
    var line = raw.replaceFirst(_trailingBlanks, '');
    // Plain bullets, and task boxes with their spaces. Looser than core/item_syntax.dart on purpose: this repairs
    // what a model wrote (`-[ ]three`), which the grammar rightly does not read as a to-do until it has been repaired.
    line = line.replaceFirstMapped(_starBullet, (match) => '${match.group(1)}- ');
    line = line.replaceFirstMapped(_looseBox, (match) => '${match.group(1)}- [${(match.group(2) ?? '').toLowerCase() == 'x' ? 'x' : ' '}] ');
    // A space after the hashes of a heading.
    line = line.replaceFirstMapped(_tightHeading, (match) => '${match.group(1)} ${match.group(2)}');
    return _markItem(line);
  });
  // No run of blank lines.
  final out = <String>[];
  for (final line in lines) {
    if (jsTrim(line).isEmpty && out.isNotEmpty && jsTrim(out.last).isEmpty) continue;
    out.add(line);
  }
  return out.join('\n');
}
