/// Evernote's note format (ENML, an XHTML of its own) as Markdown, for Settings › Import › Evernote export. Pure.
///
/// | ENML | Markdown |
/// | --- | --- |
/// | `<div>`, `<p>`, `<br/>` | a line each, `<div><br/></div>` a blank one, as Evernote shows them |
/// | `<h1>` … `<h6>` | `#` … `######` |
/// | `<b>`, `<strong>`, `font-weight: bold` | `**bold**` |
/// | `<i>`, `<em>`, `font-style: italic` | `*italic*` |
/// | `<s>`, `<strike>`, `<del>`, `line-through` | `~~struck~~` |
/// | `<code>`; `<pre>`, `-en-codeblock` | `` `code` ``; a fenced block |
/// | `<a href>` | `[words](address)`; a link to another Evernote note (`evernote:///view/…`) `[[its words]]` |
/// | `<ul>`, `<ol>`, `<li>`, nested | `- `, `1. `, indented two spaces a level |
/// | `<en-todo checked="true"/>`, `--en-todo` lists | `- [x] `, and `- [ ] ` unticked |
/// | `<table>` | a pipe table, its first row the header |
/// | `<blockquote>`, `<hr/>` | `> `, `---` |
/// | `<en-media hash type/>` | what [enmlToMarkdown]'s `media` answers: a picture or a file's link |
/// | `<en-crypt>` | left out and counted |
///
/// Anything else is its words. Characters Markdown would read as marks (`*`, `` ` ``, `[[`, a `#` or a `-` that
/// would open a heading or a list) are escaped where they stand in a note's words.
library;

import 'package:xml/xml.dart';

/// What came of one note's ENML.
typedef EnmlMarkdown = ({String markdown, int encrypted, Set<String> used});

const Set<String> _blocks = {
  'div', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'pre', 'blockquote', 'hr', //
  'en-note', 'center', 'section', 'article', 'header', 'footer', 'aside', 'nav', 'dl', 'dt', 'dd', 'figure', 'address', 'body', 'html',
};

/// The marks a to-do's box is held as inside a line, until the line is written: unticked, ticked.
const String _todo = '\u0000 ';
const String _done = '\u0000x';

/// A block of the note: its text, and whether it wants a blank line on each side (a heading, a list, a table).
typedef _Block = ({String text, bool spaced});

final RegExp _ws = RegExp(r'[ \t\r\n\f ]+');

/// [enml] as Markdown. [media] answers the Markdown for an `<en-media>` by its `hash` and `type`, or null where the
/// note has no resource with that hash; each hash answered is in `used`.
EnmlMarkdown enmlToMarkdown(String enml, {required String? Function(String hash, String type) media}) {
  final used = <String>{};
  var encrypted = 0;
  XmlElement? root;
  final clean = enml.replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>', caseSensitive: false), '').replaceFirst(RegExp(r'\s*<!DOCTYPE[^>]*>', caseSensitive: false), '');
  try {
    root = XmlDocument.parse(clean, entityMapping: const XmlDefaultEntityMapping.html5()).rootElement;
  } catch (_) {
    root = null;
  }
  if (root == null) {
    // Not well formed: its words, the tags taken out, a line where a block ended.
    final words = clean.replaceAll(RegExp(r'<(br|/div|/p|/li|/h[1-6]|/tr)\b[^>]*>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]*>'), '');
    return (markdown: _tidy(_unescapeEntities(words)), encrypted: 0, used: used);
  }
  final converter = _Converter(
    media: (hash, type) {
      final said = media(hash, type);
      if (said != null) used.add(hash);
      return said;
    },
    onCrypt: () => encrypted += 1,
  );
  final blocks = converter.blocks(root, 0);
  return (markdown: _join(blocks), encrypted: encrypted, used: used);
}

String _unescapeEntities(String text) => text
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _tidy(String text) => text.split('\n').map((line) => line.trimRight()).join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

String _join(List<_Block> blocks) {
  final out = StringBuffer();
  _Block? last;
  for (final block in blocks) {
    if (last != null) out.write(last.spaced || block.spaced ? '\n\n' : '\n');
    out.write(block.text);
    last = block;
  }
  return _tidy(out.toString());
}

String _style(XmlElement el) => (el.getAttribute('style') ?? '').toLowerCase().replaceAll(' ', '');

bool _bold(XmlElement el) {
  final style = _style(el);
  return style.contains('font-weight:bold') || style.contains('font-weight:700') || style.contains('font-weight:600') || style.contains('font-weight:800') || style.contains('font-weight:900');
}

bool _italic(XmlElement el) => _style(el).contains('font-style:italic');
bool _struck(XmlElement el) => _style(el).contains('line-through');
bool _codeBlock(XmlElement el) => _style(el).contains('-en-codeblock:true');
bool _todoList(XmlElement el) => _style(el).contains('--en-todo:true');
bool _checked(XmlElement el) => _style(el).contains('--en-checked:true');

String _name(XmlElement el) => el.name.local.toLowerCase();

bool _isBlock(XmlNode node) => node is XmlElement && (_blocks.contains(_name(node)) || _codeBlock(node));

/// Words as Markdown reads them, every mark in them escaped: what a paragraph's text is made of.
String _escape(String text) => text.replaceAll(r'\', r'\\').replaceAll('*', r'\*').replaceAll('`', r'\`').replaceAll('[[', r'\[\[');

/// A line of a paragraph that would read as a heading, a list, a quote or a rule, kept as words.
String _escapeLead(String line) {
  if (RegExp(r'^#{1,6}(\s|$)').hasMatch(line)) return '\\$line';
  if (RegExp(r'^([-+]|\d+[.)])\s').hasMatch(line)) {
    final at = line.indexOf(RegExp(r'[-+.)]'));
    return '${line.substring(0, at)}\\${line.substring(at)}';
  }
  if (line.startsWith('>')) return '\\$line';
  if (RegExp(r'^(-{3,}|_{3,})\s*$').hasMatch(line)) return '\\$line';
  return line;
}

/// [text] in [mark] on each side, its own spaces outside them: `**bold** next`, never `**bold **next`.
String _wrap(String text, String mark) {
  final lead = RegExp(r'^\s*').firstMatch(text)!.group(0)!;
  final trail = RegExp(r'\s*$').firstMatch(text)!.group(0)!;
  if (lead.length >= text.length) return text;
  final core = text.substring(lead.length, text.length - trail.length);
  if (core.contains('\n')) {
    return '$lead${core.split('\n').map((line) => line.trim().isEmpty ? line : '$mark${line.trim()}$mark').join('\n')}$trail';
  }
  return '$lead$mark$core$mark$trail';
}

class _Converter {
  _Converter({required this.media, required this.onCrypt});

  final String? Function(String hash, String type) media;
  final void Function() onCrypt;

  // ---- blocks ---------------------------------------------------------------------------------------------------

  /// The blocks inside [el], a list [depth] deep.
  List<_Block> blocks(XmlElement el, int depth) {
    final out = <_Block>[];
    final run = <XmlNode>[];
    void flush() {
      if (run.isEmpty) return;
      final text = inlineOf(run);
      run.clear();
      out.addAll(paragraph(text));
    }

    for (final child in el.children) {
      if (_isBlock(child)) {
        flush();
        out.addAll(block(child as XmlElement, depth));
      } else {
        run.add(child);
      }
    }
    flush();
    return out;
  }

  /// A paragraph's lines, each a block of its own: a to-do's box at a line's start is the item's.
  List<_Block> paragraph(String text) {
    // A `<br/>` that ends a line of words is no line of its own, as a page draws it.
    if (text.endsWith('\n') && text.trim().isNotEmpty) text = text.substring(0, text.length - 1);
    if (text.trim().isEmpty) return text.contains('\n') || text.isEmpty ? const [(text: '', spaced: false)] : const [];
    final lines = <_Block>[];
    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.startsWith(_todo) || line.startsWith(_done)) {
        final ticked = line.startsWith(_done);
        final rest = line.substring(2).trim().replaceAll(_todo, '[ ] ').replaceAll(_done, '[x] ');
        lines.add((text: '- [${ticked ? 'x' : ' '}] $rest', spaced: false));
      } else {
        lines.add((text: _escapeLead(line.replaceAll(_todo, '[ ] ').replaceAll(_done, '[x] ')), spaced: false));
      }
    }
    return lines;
  }

  List<_Block> block(XmlElement el, int depth) {
    final name = _name(el);
    if (_codeBlock(el) || name == 'pre') return [(text: fenced(codeText(el)), spaced: true)];
    switch (name) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final words = inlineOf(el.children).replaceAll(_todo, '').replaceAll(_done, '').replaceAll('\n', ' ').trim();
        return words.isEmpty ? const [] : [(text: '${'#' * int.parse(name.substring(1))} $words', spaced: true)];
      case 'ul' || 'ol':
        final lines = list(el, '  ' * depth);
        return lines.isEmpty ? const [] : [(text: lines.join('\n'), spaced: true)];
      case 'table':
        final table = this.table(el);
        return table == null ? const [] : [(text: table, spaced: true)];
      case 'blockquote':
        final inner = _join(blocks(el, depth));
        return inner.isEmpty ? const [] : [(text: inner.split('\n').map((line) => line.isEmpty ? '>' : '> $line').join('\n'), spaced: true)];
      case 'hr':
        return const [(text: '---', spaced: true)];
      case 'li':
        // A list item outside a list: an item all the same.
        return [(text: list(XmlElement(XmlName.parts('ul'), const [], [el.copy()]), '  ' * depth).join('\n'), spaced: true)];
      default:
        final inner = blocks(el, depth);
        // `<div></div>` and `<div><br/></div>`: a blank line, as Evernote draws it.
        if (inner.isEmpty && (name == 'div' || name == 'p')) return const [(text: '', spaced: false)];
        if (name == 'p') return [...inner, (text: '', spaced: false)];
        return inner;
    }
  }

  /// A list's items, each `- ` or `1. ` after [indent], what an item holds after its first line, and a list inside
  /// it, indented under its words (three spaces under `1. `, two under `- `, as CommonMark nests them).
  List<String> list(XmlElement el, String indent) {
    final ordered = _name(el) == 'ol';
    final todo = _todoList(el);
    final lines = <String>[];
    var n = 0;
    for (final child in el.children) {
      if (child is! XmlElement) continue;
      final name = _name(child);
      if (name == 'ul' || name == 'ol') {
        lines.addAll(list(child, '$indent  '));
        continue;
      }
      if (name != 'li') continue;
      n += 1;
      final nested = <XmlElement>[];
      final own = XmlElement(XmlName.parts('div'));
      for (final part in child.children) {
        if (part is XmlElement && (_name(part) == 'ul' || _name(part) == 'ol')) {
          nested.add(part);
        } else {
          own.children.add(part.copy());
        }
      }
      final words = _join(blocks(own, 0)).split('\n').where((line) => line.trim().isNotEmpty).toList();
      var first = words.isEmpty ? '' : words.first;
      final number = ordered ? '$n.' : '-';
      var marker = number;
      if (first.startsWith('- [')) {
        // An en-todo inside the item: the box is the item's.
        marker = '$number [${first[3]}]';
        first = first.substring(6);
      } else if (todo) {
        marker = '$number [${_checked(child) ? 'x' : ' '}]';
      }
      lines.add('$indent$marker ${first.trim()}'.trimRight());
      final under = '$indent${' ' * (number.length + 1)}';
      for (final more in words.skip(1)) {
        lines.add('$under${more.trim()}');
      }
      for (final inner in nested) {
        lines.addAll(list(inner, under));
      }
    }
    return lines;
  }

  /// A pipe table, its first row the header, every row as wide as the widest.
  String? table(XmlElement el) {
    final rows = <List<String>>[];
    void walk(XmlElement node) {
      for (final child in node.children.whereType<XmlElement>()) {
        final name = _name(child);
        if (name == 'tr') {
          rows.add([
            for (final cell in child.children.whereType<XmlElement>())
              if (_name(cell) == 'td' || _name(cell) == 'th') cellText(cell),
          ]);
        } else if (name == 'thead' || name == 'tbody' || name == 'tfoot') {
          walk(child);
        }
      }
    }

    walk(el);
    rows.removeWhere((row) => row.isEmpty);
    if (rows.isEmpty) return null;
    final width = rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    String line(List<String> row) => '| ${[...row, for (var i = row.length; i < width; i += 1) ''].join(' | ')} |';
    return [line(rows.first), '| ${List.filled(width, '---').join(' | ')} |', for (final row in rows.skip(1)) line(row)].join('\n');
  }

  /// A table cell's words on one line, a `|` in them escaped.
  String cellText(XmlElement cell) {
    final words = _join(blocks(cell, 0)).split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).join(' ');
    return words.replaceAll('|', r'\|');
  }

  /// A code block's text: its lines as written, a `<div>` or a `<br/>` a line.
  String codeText(XmlElement el) {
    final out = StringBuffer();
    void walk(XmlNode node) {
      if (node is XmlText || node is XmlCDATA) {
        out.write(node.value);
      } else if (node is XmlElement) {
        final name = _name(node);
        if (name == 'br') {
          out.write('\n');
          return;
        }
        final line = name == 'div' || name == 'p';
        if (line && out.isNotEmpty && !out.toString().endsWith('\n')) out.write('\n');
        node.children.forEach(walk);
        if (line && !out.toString().endsWith('\n')) out.write('\n');
      }
    }

    el.children.forEach(walk);
    return out.toString().replaceAll(' ', ' ').replaceFirst(RegExp(r'\n+$'), '');
  }

  String fenced(String code) {
    var fence = '```';
    while (code.contains(fence)) {
      fence += '`';
    }
    return '$fence\n$code\n$fence';
  }

  // ---- inline ---------------------------------------------------------------------------------------------------

  String inlineOf(Iterable<XmlNode> nodes) {
    final out = StringBuffer();
    for (final node in nodes) {
      out.write(inline(node));
    }
    // Whitespace collapsed as a page collapses it; a line break kept.
    return out.toString().split('\n').map((line) => line.replaceAll(RegExp(r' {2,}'), ' ')).join('\n');
  }

  String inline(XmlNode node) {
    if (node is XmlText) return _escape(node.value.replaceAll(_ws, ' '));
    if (node is XmlCDATA) return _escape(node.value.replaceAll(_ws, ' '));
    if (node is! XmlElement) return '';
    final name = _name(node);
    switch (name) {
      case 'br':
        return '\n';
      case 'en-todo':
        return (node.getAttribute('checked') ?? '').toLowerCase() == 'true' ? _done : _todo;
      case 'en-media':
        final said = media((node.getAttribute('hash') ?? '').toLowerCase(), node.getAttribute('type') ?? '');
        if (said == null) return '';
        // A picture on a line of its own, which is where a note draws one.
        return said.startsWith('!') ? '\n$said\n' : said;
      case 'en-crypt':
        onCrypt();
        return '';
      case 'img':
        final src = node.getAttribute('src') ?? '';
        if (!src.startsWith('http')) return '';
        return '\n![${(node.getAttribute('alt') ?? '').replaceAll(RegExp(r'[\[\]\n]'), '')}]($src)\n';
      case 'code' || 'tt' || 'kbd' || 'samp':
        final code = node.innerText.replaceAll(_ws, ' ');
        if (code.trim().isEmpty) return code;
        var ticks = '`';
        while (code.contains(ticks)) {
          ticks += '`';
        }
        final pad = code.startsWith('`') || code.endsWith('`') ? ' ' : '';
        return '$ticks$pad$code$pad$ticks';
      case 'a':
        return link(node);
    }
    var inner = inlineOf(node.children);
    if (name == 'b' || name == 'strong' || _bold(node)) inner = _wrap(inner, '**');
    if (name == 'i' || name == 'em' || name == 'cite' || _italic(node)) inner = _wrap(inner, '*');
    if (name == 's' || name == 'strike' || name == 'del' || _struck(node)) inner = _wrap(inner, '~~');
    return inner;
  }

  String link(XmlElement node) {
    final href = (node.getAttribute('href') ?? '').trim();
    final words = inlineOf(node.children).replaceAll('\n', ' ').trim();
    if (href.isEmpty) return words;
    // A link to another Evernote note: its words are that note's title, which is what a note link names.
    if (href.startsWith('evernote:')) {
      final title = words.replaceAll(RegExp(r'[\[\]|#^\\]'), '').trim();
      return title.isEmpty ? '' : '[[$title]]';
    }
    final address = href.contains(RegExp(r'[\s()<>]')) ? '<${href.replaceAll('>', '%3E')}>' : href;
    if (words.isEmpty || words == _escape(href)) return '<${href.replaceAll('>', '%3E')}>';
    return '[${words.replaceAll(']', r'\]')}]($address)';
  }
}
