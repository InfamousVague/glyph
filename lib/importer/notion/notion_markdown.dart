/// Notion's blocks and rich text as the Markdown Ghost.md speaks (tauri/docs/MARKDOWN.md), for the import
/// (docs/NOTION_IMPORT.md has the table). Plain Markdown first: what Ghost.md draws richer (a callout, a toggle, a
/// link card, a query) is written the way GitHub and Obsidian read it too.
///
/// - **Rich text**: bold `**`, italic `*`, strikethrough `~~`, code `` ` ``, a coloured background `==…==` (with its
///   colour where the kit has it, `==…==(green)`), a link `[words](address)`, a link to an imported page `[[Title]]`
///   (`[[Title|words]]` where the words differ), an equation `$…$`. Underline and a coloured text have no Markdown
///   and are left as words. A run of the same marks is written once, and the spaces at its ends are put outside them.
/// - **Mentions**: a person is their name, a page or a database `[[Title]]`, a date the date (`2026-11-04`, `→` the
///   end), a link its link.
/// - **Blocks**: headings `#` to `###` (a toggle heading is the heading with its blocks under it: a heading folds in
///   Ghost.md), paragraphs, `-` lists, numbered lists counted, to-dos `- [ ]`/`- [x]`, each nested as deep as Notion
///   has it; quotes; callouts `> [!NOTE]` (a kind by the callout's icon) with its icon in its words; toggles as
///   `<details>`; code fenced with its language; an equation `$$`; a divider `---`; a table as a GFM table; a
///   picture kept in the app's pictures, a file among its files; a bookmark, an embed, a video or a link preview as
///   the bare link alone on its line (Ghost.md draws a card under it); a sub-page, a database and a link to a page
///   as `[[Title]]` on its line; a synced block and columns as their blocks, in order.
/// - **Left out**, and named in the report: a table of contents and a breadcrumb (Ghost.md draws neither from a
///   note), a template button, and what Notion's API itself calls unsupported.
library;

import 'dart:async';

/// What converting needs from the import: the title each imported page is linked by, the files kept, and where to
/// say what could not be brought.
abstract interface class NotionWriting {
  /// The title of the imported page or database [id] (a Notion id, [notionIdOf]'s form), or null where it is not
  /// among what was imported.
  String? titleOf(String id);

  /// Keeps the file at [url] and answers the Markdown that shows it there: a picture's `![caption](image/…)` where
  /// [picture] and its bytes are a picture the app keeps, else a file's `[name](file/…)`. Null where it could not be
  /// fetched.
  Future<String?> keep(String url, {required String name, String caption = '', bool picture = false});

  /// A block of [type] that has no Markdown and was left out.
  void leftOut(String type);

  /// A link or a mention of a page the import does not have: [words] is how Notion wrote it.
  void unresolved(String words);
}

/// The background colours the kit has a ramp for, by Notion's name (`yellow_background`).
const Map<String, String?> _highlights = {
  'yellow': null,
  'orange': 'amber',
  'brown': 'amber',
  'green': 'green',
  'blue': 'blue',
  'purple': 'purple',
  'pink': 'red',
  'red': 'red',
  'gray': 'gray',
};

/// One run of rich text: its words and what is done to them.
class _Run {
  _Run(this.text, this.marks, {this.raw = false});

  String text;

  /// Bold, italic, strike, code, highlight and link as one key, so neighbours that share them are one run.
  final String marks;

  /// Already Markdown (a wiki link, an equation): never escaped.
  final bool raw;
}

/// [text] with what would turn it into Markdown it never was escaped: a `*`, a `` ` ``, `[[`, `==` and `~~`.
String escapeNotionText(String text) => text
    .replaceAll(r'\', r'\\')
    .replaceAll('*', r'\*')
    .replaceAll('`', r'\`')
    .replaceAll('[[', r'\[\[')
    .replaceAll(']]', r'\]\]')
    .replaceAll('==', r'\=\=')
    .replaceAll('~~', r'\~\~');

/// The words of a rich text array, as they read with no marks: Notion's `plain_text`.
String notionPlain(Object? rich) => rich is List ? [for (final r in rich) r is Map && r['plain_text'] is String ? r['plain_text'] as String : ''].join() : '';

String _mentionWords(Map<Object?, Object?> mention, String plain, NotionWriting writing, {required void Function(String) link}) {
  final kind = mention['type'];
  switch (kind) {
    case 'user':
      // A person is their name: Notion's plain text is "@Name".
      return escapeNotionText(plain.startsWith('@') ? plain.substring(1) : plain);
    case 'page':
    case 'database':
      final inner = mention[kind];
      final id = inner is Map ? _id(inner['id']) : null;
      final title = id == null ? null : writing.titleOf(id);
      if (title == null) {
        writing.unresolved(plain);
        return escapeNotionText(plain);
      }
      link('[[$title]]');
      return '';
    case 'date':
      final date = mention['date'];
      if (date is! Map) return escapeNotionText(plain);
      final start = '${date['start'] ?? ''}', end = date['end'];
      return escapeNotionText(end == null ? start : '$start → $end');
    default:
      return escapeNotionText(plain);
  }
}

String? _id(Object? said) {
  if (said is! String) return null;
  final hex = said.replaceAll('-', '').toLowerCase();
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(hex) ? hex : null;
}

/// A rich text array as Markdown on one line or several (a soft break in Notion is a hard one here: two spaces).
String richMarkdown(Object? rich, NotionWriting writing, {bool lineBreaks = true}) {
  if (rich is! List) return '';
  final runs = <_Run>[];
  void add(String text, String marks, {bool raw = false}) {
    if (text.isEmpty) return;
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.marks == marks && last.raw == raw && !raw) {
      last.text += text;
    } else {
      runs.add(_Run(text, marks, raw: raw));
    }
  }

  for (final item in rich) {
    if (item is! Map) continue;
    final plain = item['plain_text'] is String ? item['plain_text'] as String : '';
    final notes = item['annotations'] is Map ? item['annotations'] as Map : const {};
    final color = '${notes['color'] ?? 'default'}';
    final highlight = color.endsWith('_background') ? color.substring(0, color.length - '_background'.length) : null;
    final code = notes['code'] == true;
    String marks(String? href) => [notes['bold'] == true ? 'b' : '', notes['italic'] == true ? 'i' : '', notes['strikethrough'] == true ? 's' : '', code ? 'c' : '', highlight == null ? '' : 'h:$highlight', href == null ? '' : 'l:$href'].join('|');
    switch (item['type']) {
      case 'equation':
        final eq = item['equation'];
        final expression = eq is Map ? '${eq['expression'] ?? plain}' : plain;
        add('\$${expression.trim()}\$', marks(null), raw: true);
      case 'mention':
        final mention = item['mention'] is Map ? item['mention'] as Map : const {};
        String? linked;
        final words = _mentionWords(mention, plain, writing, link: (said) => linked = said);
        if (linked != null) {
          add(linked!, marks(null), raw: true);
        } else if (mention['type'] == 'link_preview' || mention['type'] == 'link_mention') {
          final href = item['href'] is String ? item['href'] as String : null;
          add(code ? plain : words, marks(href), raw: code);
        } else {
          add(code ? plain : words, marks(null), raw: code);
        }
      default:
        final text = item['text'] is Map ? item['text'] as Map : const {};
        final content = text['content'] is String ? text['content'] as String : plain;
        final link = text['link'] is Map ? (text['link'] as Map)['url'] : item['href'];
        final href = link is String && link.isNotEmpty ? link : null;
        final page = _pageOf(href, writing);
        if (page != null) {
          add(content.trim() == page || content.trim().isEmpty ? '[[$page]]' : '[[$page|${content.trim().replaceAll(RegExp(r'[\[\]|\n]'), ' ')}]]', marks(null), raw: true);
        } else {
          if (href != null && _looksNotion(href)) writing.unresolved(content);
          add(code ? content : escapeNotionText(content), marks(href), raw: code);
        }
    }
  }

  final out = StringBuffer();
  for (final run in runs) {
    out.write(_marked(run));
  }
  var said = out.toString();
  said = lineBreaks ? said.replaceAll('\n', '  \n') : said.replaceAll('\n', ' ');
  return said;
}

/// A Notion page a link names, by its title here; null where it is not one, or not imported.
String? _pageOf(String? href, NotionWriting writing) {
  if (href == null) return null;
  final uri = Uri.tryParse(href);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final inside = host.isEmpty ? href.startsWith('/') : (host == 'notion.so' || host.endsWith('.notion.so') || host == 'notion.site' || host.endsWith('.notion.site'));
  if (!inside) return null;
  final match = RegExp(r'([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?![0-9a-f])', caseSensitive: false).firstMatch(uri.path);
  final id = match == null ? null : _id(match.group(1));
  return id == null ? null : writing.titleOf(id);
}

bool _looksNotion(String href) {
  final host = Uri.tryParse(href)?.host.toLowerCase() ?? '';
  return href.startsWith('/') || host == 'notion.so' || host.endsWith('.notion.so');
}

/// One run with its marks put on, the spaces at its ends outside them (`** bold **` is no bold).
String _marked(_Run run) {
  final text = run.text;
  if (run.marks.replaceAll('|', '').isEmpty) return text;
  final lead = RegExp(r'^\s*').firstMatch(text)!.group(0)!;
  final tail = RegExp(r'\s*$').firstMatch(text.substring(lead.length))!.group(0)!;
  var core = text.substring(lead.length, text.length - tail.length);
  if (core.isEmpty) return text;
  final marks = run.marks.split('|');
  String? href, highlight;
  for (final mark in marks) {
    if (mark.startsWith('l:')) href = mark.substring(2);
    if (mark.startsWith('h:')) highlight = mark.substring(2);
  }
  if (marks.contains('c')) {
    final fence = core.contains('`') ? '``' : '`';
    core = fence == '``' ? '`` $core ``' : '`$core`';
  }
  if (marks.contains('s')) core = '~~$core~~';
  if (marks.contains('i')) core = '*$core*';
  if (marks.contains('b')) core = '**$core**';
  if (highlight != null) {
    final hue = _highlights[highlight];
    core = hue == null ? '==$core==' : '==$core==($hue)';
  }
  if (href != null) core = '[$core](${href.replaceAll(' ', '%20').replaceAll(')', '%29')})';
  return '$lead$core$tail';
}

/// What a callout's icon says it is, as one of Ghost.md's five kinds.
String calloutKind(Object? icon) {
  final emoji = icon is Map && icon['type'] == 'emoji' ? '${icon['emoji']}' : '';
  if (emoji.contains('💡') || emoji.contains('✨') || emoji.contains('👉')) return 'TIP';
  if (emoji.contains('⚠')) return 'WARNING';
  if (emoji.contains('🚨') || emoji.contains('🛑') || emoji.contains('⛔') || emoji.contains('❌')) return 'CAUTION';
  if (emoji.contains('❗') || emoji.contains('‼') || emoji.contains('📌') || emoji.contains('🔥')) return 'IMPORTANT';
  return 'NOTE';
}

/// A code block's language as a fence names it: Notion's `plain text` none, `c++` `cpp`, `c#` `csharp`, and the rest
/// in lower case without spaces.
String fenceLanguage(Object? language) {
  final said = '${language ?? ''}'.trim().toLowerCase();
  return switch (said) {
    '' || 'plain text' || 'plaintext' => '',
    'c++' => 'cpp',
    'c#' => 'csharp',
    'f#' => 'fsharp',
    'objective-c' => 'objectivec',
    'shell' || 'bash' => 'bash',
    'java/c/c++/c#' => 'java',
    _ => said.replaceAll(RegExp(r'\s+'), ''),
  };
}

/// [text] with every line after a blank one given [prefix], and blank lines given its trimmed form.
String _indented(String text, String prefix) => text.split('\n').map((line) => line.isEmpty ? '' : '$prefix$line').join('\n');

String _quoted(String text) => text.split('\n').map((line) => line.isEmpty ? '>' : '> $line').join('\n');

const Set<String> _listKinds = {'bulleted_list_item', 'numbered_list_item', 'to_do'};

/// The file a block names: its address, whether Notion keeps it (and its link will expire), and its name.
({String url, bool hosted, String name})? _fileOf(Map<Object?, Object?> body) {
  final kind = body['type'];
  final inner = body[kind];
  final url = inner is Map ? inner['url'] : null;
  if (url is! String || url.isEmpty) return null;
  var name = body['name'] is String ? body['name'] as String : '';
  if (name.isEmpty) {
    final path = Uri.tryParse(url)?.pathSegments ?? const [];
    name = path.isEmpty ? 'file' : Uri.decodeComponent(path.last);
  }
  return (url: url, hosted: kind == 'file' || kind == 'file_upload', name: name);
}

/// Blocks (each with its own `children` read, as [NotionReader.tree] gives them) as Markdown.
Future<String> blocksMarkdown(List<Map<String, Object?>> blocks, NotionWriting writing) async {
  final parts = <(String, String)>[];
  var number = 0;
  String? before;
  for (final block in blocks) {
    final type = '${block['type']}';
    number = type == 'numbered_list_item' ? (before == 'numbered_list_item' ? number + 1 : 1) : 0;
    final said = await _block(block, writing, number);
    before = type;
    if (said == null || said.isEmpty) continue;
    parts.add((type, said));
  }
  final out = StringBuffer();
  for (var i = 0; i < parts.length; i += 1) {
    if (i > 0) out.write(_listKinds.contains(parts[i - 1].$1) && _listKinds.contains(parts[i].$1) ? '\n' : '\n\n');
    out.write(parts[i].$2);
  }
  return out.toString();
}

Future<String> _childrenOf(Map<String, Object?> block, NotionWriting writing) async {
  final children = block['children'];
  if (children is! List || children.isEmpty) return '';
  return blocksMarkdown([for (final child in children) if (child is Map) child.cast<String, Object?>()], writing);
}

Future<String?> _block(Map<String, Object?> block, NotionWriting writing, int number) async {
  final type = '${block['type']}';
  final body = block[type] is Map ? (block[type] as Map).cast<Object?, Object?>() : const <Object?, Object?>{};
  String rich() => richMarkdown(body['rich_text'], writing);
  String caption() => richMarkdown(body['caption'], writing, lineBreaks: false);
  switch (type) {
    case 'paragraph':
      final words = rich();
      final children = await _childrenOf(block, writing);
      // Notion's indent under a paragraph has no Markdown: its blocks follow, in order.
      final lines = [if (words.trim().isNotEmpty) _leadEscaped(words), if (children.isNotEmpty) children];
      return lines.join('\n\n');
    case 'heading_1':
    case 'heading_2':
    case 'heading_3':
      final level = int.parse(type.substring(type.length - 1));
      final words = richMarkdown(body['rich_text'], writing, lineBreaks: false).trim();
      final children = await _childrenOf(block, writing);
      final heading = words.isEmpty ? '' : '${'#' * level} $words';
      return [if (heading.isNotEmpty) heading, if (children.isNotEmpty) children].join('\n\n');
    case 'bulleted_list_item':
    case 'numbered_list_item':
    case 'to_do':
      final mark = switch (type) {
        'bulleted_list_item' => '- ',
        'numbered_list_item' => '$number. ',
        _ => body['checked'] == true ? '- [x] ' : '- [ ] ',
      };
      final hang = ' ' * (type == 'numbered_list_item' ? mark.length : 2);
      final words = rich();
      final lines = words.split('\n');
      final item = '$mark${lines.first}${lines.length > 1 ? '\n${_indented(lines.sublist(1).join('\n'), hang)}' : ''}';
      final children = await _childrenOf(block, writing);
      return children.isEmpty ? item : '$item\n${_indented(children, hang)}';
    case 'toggle':
      final summary = richMarkdown(body['rich_text'], writing, lineBreaks: false).trim();
      final children = await _childrenOf(block, writing);
      return '<details>\n<summary>${summary.isEmpty ? 'Toggle' : summary}</summary>\n\n${children.isEmpty ? '' : '$children\n\n'}</details>';
    case 'quote':
      final children = await _childrenOf(block, writing);
      return _quoted([rich(), if (children.isNotEmpty) children].join('\n\n'));
    case 'callout':
      final icon = body['icon'];
      final emoji = icon is Map && icon['type'] == 'emoji' ? '${icon['emoji']} ' : '';
      final children = await _childrenOf(block, writing);
      return '> [!${calloutKind(icon)}]\n${_quoted(['$emoji${rich()}'.trim(), if (children.isNotEmpty) children].join('\n\n'))}';
    case 'code':
      final code = notionPlain(body['rich_text']);
      final fence = code.contains('```') ? '````' : '```';
      final under = caption();
      return '$fence${fenceLanguage(body['language'])}\n$code\n$fence${under.isEmpty ? '' : '\n\n*$under*'}';
    case 'equation':
      return '\$\$\n${'${body['expression'] ?? ''}'.trim()}\n\$\$';
    case 'divider':
      return '---';
    case 'image':
      final file = _fileOf(body);
      if (file == null) return null;
      final under = caption();
      if (!file.hosted) return '![${under.replaceAll(RegExp(r'[\[\]]'), '')}](${file.url.replaceAll(' ', '%20')})';
      return await writing.keep(file.url, name: file.name, caption: under.replaceAll(RegExp(r'[\[\]]'), ''), picture: true);
    case 'video':
    case 'audio':
    case 'file':
    case 'pdf':
      final file = _fileOf(body);
      if (file == null) return null;
      final under = caption();
      final kept = file.hosted ? await writing.keep(file.url, name: file.name) : file.url;
      if (kept == null) return null;
      return under.isEmpty ? kept : '$kept\n\n*$under*';
    case 'bookmark':
    case 'embed':
    case 'link_preview':
      final url = body['url'];
      if (url is! String || url.isEmpty) return null;
      final under = caption();
      // Alone on its line, so Ghost.md draws its card (or YouTube's, Spotify's, Figma's) under it.
      return under.isEmpty ? url : '[${under.replaceAll(RegExp(r'[\[\]]'), '')}]($url)';
    case 'child_page':
    case 'child_database':
      final id = _id(block['id']);
      final title = id == null ? null : writing.titleOf(id);
      if (title == null) {
        writing.unresolved('${body['title'] ?? 'a page'}');
        return null;
      }
      return '[[$title]]';
    case 'link_to_page':
      final kind = body['type'];
      final id = _id(body[kind]);
      final title = id == null ? null : writing.titleOf(id);
      if (title == null) {
        writing.unresolved('a link to a page Ghost.md wasn’t shown');
        return null;
      }
      return '[[$title]]';
    case 'synced_block':
    case 'column_list':
    case 'column':
      // Their blocks, in order: a synced copy is its original's words, columns are read left to right.
      final children = await _childrenOf(block, writing);
      return children.isEmpty ? null : children;
    case 'table':
      return _table(block, body, writing);
    case 'table_of_contents':
      writing.leftOut('table of contents');
      return null;
    case 'breadcrumb':
      writing.leftOut('breadcrumb');
      return null;
    case 'template':
      writing.leftOut('template button');
      return null;
    default:
      writing.leftOut(type == 'unsupported' ? 'block Notion doesn’t share with apps' : type.replaceAll('_', ' '));
      return null;
  }
}

/// A paragraph's first character escaped where it would start a heading, a quote, a list or a sum.
String _leadEscaped(String words) {
  if (RegExp(r'^(#{1,6}\s|>|[-+*]\s|\d+[.)]\s|=\s|---)').hasMatch(words)) return '\\$words';
  return words;
}

String _table(Map<String, Object?> block, Map<Object?, Object?> body, NotionWriting writing) {
  final rows = <List<String>>[];
  final children = block['children'];
  if (children is List) {
    for (final row in children) {
      if (row is! Map || row['type'] != 'table_row') continue;
      final cells = (row['table_row'] is Map ? (row['table_row'] as Map)['cells'] : null);
      if (cells is! List) continue;
      rows.add([for (final cell in cells) richMarkdown(cell, writing, lineBreaks: false).replaceAll('|', r'\|').trim()]);
    }
  }
  if (rows.isEmpty) return '';
  final width = [for (final row in rows) row.length].fold<int>(body['table_width'] is int ? body['table_width'] as int : 0, (a, b) => a > b ? a : b);
  List<String> padded(List<String> row) => [...row, for (var i = row.length; i < width; i += 1) ''];
  String line(List<String> row) => '| ${padded(row).join(' | ')} |';
  final header = body['has_column_header'] == true;
  final head = header ? rows.first : List.filled(width, '');
  final rest = header ? rows.sublist(1) : rows;
  return [line(head), '|${List.filled(width, ' --- ').join('|')}|', for (final row in rest) line(row)].join('\n');
}
