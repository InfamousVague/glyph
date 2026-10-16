/// An Obsidian note's references to the vault's other files, found and rewritten to where each file landed in the
/// library. Pure: the importer (lib/importer/obsidian.dart) says where things are.
///
/// What counts as a reference, outside code (a fenced block, or `inline code`):
///
/// | Written | Is | Becomes, once its file is kept |
/// | --- | --- | --- |
/// | `![[photo.png]]`, `![[photo.png\|300]]`, `![[Photos/photo.png\|A caption]]` | an embed | `![](image/<name>)`, the alias as its caption unless it is a size |
/// | `[[report.pdf]]`, `![[report.pdf]]`, `[[report.pdf\|The report]]` | a link or an embed of a file | `[report.pdf](file/<name>)`, or the alias as its words |
/// | `![alt](photo%20one.png)`, `![alt](<photo one.png>)` | a Markdown picture | `![alt](image/<name>)` |
/// | `[words](Docs/report.pdf)` | a Markdown link | `[words](file/<name>)` |
///
/// A reference to a picture the library keeps (a JPEG, PNG or WebP) is drawn as the picture wherever it was written,
/// as a link or an embed; any other file is a link to its kept copy. Links and embeds of notes (`[[Alpha]]`,
/// `![[Alpha#Plan]]`, `[x](Alpha.md)`) are left exactly as written, as are addresses on the web.
library;

/// The extensions Obsidian reads as notes and canvases: a reference to one of these is not an attachment.
const Set<String> noteExtensions = {'md', 'canvas'};

/// What a reference names, as written: [target] the file (`Photos/photo.png`, decoded from `%20`), [embed] whether
/// it was `![[…]]` or `![…](…)`, [words] what it says (an alias, alt text, or a link's words), [wiki] which way it
/// was written.
typedef AttachmentRef = ({String target, bool embed, String? words, bool wiki});

/// Where a file landed: `image/<name>` for a picture, `file/<name>` for anything else.
typedef Landed = ({String ref, bool picture});

final RegExp _wiki = RegExp(r'(!?)\[\[([^\]\n|#^]+)((?:#|\^)[^\]\n|]*)?(?:\|([^\]\n]*))?\]\]');
final RegExp _markdown = RegExp(r'(!?)\[((?:[^\]\n\\]|\\.)*)\]\((<[^>\n]+>|[^)\s]+)(\s+"[^"\n]*")?\)');
/// Either kind, in one pass, so a reference is read once: the wiki's four groups, then the Markdown's four.
final RegExp _either = RegExp('${_wiki.pattern}|${_markdown.pattern}');
final RegExp _fence = RegExp(r'^ {0,3}(```+|~~~+)');
final RegExp _size = RegExp(r'^\s*\d+(\s*x\s*\d+)?\s*$');
final RegExp _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');

/// The extension of a reference's target, lower case, or '' for none (a note's name).
String extensionOf(String target) {
  final name = target.contains('/') ? target.substring(target.lastIndexOf('/') + 1) : target;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Whether [target] names a file that is not a note: it has an extension, and not `.md` or `.canvas`.
bool namesAttachment(String target) {
  final ext = extensionOf(target);
  return ext.isNotEmpty && !noteExtensions.contains(ext);
}

String _decoded(String raw) {
  var target = raw.startsWith('<') && raw.endsWith('>') ? raw.substring(1, raw.length - 1) : raw;
  try {
    target = Uri.decodeComponent(target);
  } catch (_) {
    // A lone `%` is a name, not an escape.
  }
  return target.trim();
}

/// Applies [rewrite] to every stretch of [body] that is not code: the lines of a fenced block, and `inline code`
/// in a line, are kept as they are.
String _outsideCode(String body, String Function(String text) rewrite) {
  final lines = body.split('\n');
  String? fence;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final open = _fence.firstMatch(line);
    if (fence != null) {
      if (open != null && open.group(1)!.startsWith(fence[0]) && open.group(1)!.length >= fence.length && line.trim() == open.group(1)) fence = null;
      continue;
    }
    if (open != null) {
      fence = open.group(1);
      continue;
    }
    if (!line.contains('[')) continue;
    lines[i] = line.contains('`') ? _outsideInline(line, rewrite) : rewrite(line);
  }
  return lines.join('\n');
}

String _outsideInline(String line, String Function(String text) rewrite) {
  final out = StringBuffer();
  var at = 0;
  while (at < line.length) {
    final tick = line.indexOf('`', at);
    if (tick < 0) break;
    var run = tick;
    while (run < line.length && line.codeUnitAt(run) == 0x60) {
      run += 1;
    }
    final ticks = line.substring(tick, run);
    final close = line.indexOf(ticks, run);
    if (close < 0) break;
    out
      ..write(rewrite(line.substring(at, tick)))
      ..write(line.substring(tick, close + ticks.length));
    at = close + ticks.length;
  }
  out.write(rewrite(line.substring(at)));
  return out.toString();
}

/// Every attachment [body] refers to, in order, outside code. A note's links are left out.
List<AttachmentRef> attachmentRefs(String body) {
  final found = <AttachmentRef>[];
  _outsideCode(body, (text) {
    for (final m in _either.allMatches(text)) {
      if (m.group(2) != null) {
        final target = m.group(2)!.trim();
        if (namesAttachment(target)) found.add((target: target, embed: m.group(1) == '!', words: m.group(4), wiki: true));
      } else {
        final target = _decoded(m.group(7)!);
        if (!_scheme.hasMatch(target) && namesAttachment(target)) found.add((target: target, embed: m.group(5) == '!', words: m.group(6), wiki: false));
      }
    }
    return text;
  });
  return found;
}

String _nameOf(String target) => target.contains('/') ? target.substring(target.lastIndexOf('/') + 1) : target;

String _words(String text) => text.replaceAll(RegExp(r'[\[\]\n]'), ' ').trim();

/// [body] with each reference to an attachment rewritten to where [landedOf] says it landed. A reference
/// [landedOf] answers null for is left as written, and [missing] is told of it.
String rewriteAttachments(String body, Landed? Function(AttachmentRef ref) landedOf, {void Function(AttachmentRef ref)? missing}) {
  String write(AttachmentRef ref, Landed landed, String whole) {
    if (landed.picture) {
      // A wiki embed's alias is its caption, unless it is the picture's size (`|300`, `|300x200`).
      final caption = ref.wiki ? (ref.words == null || _size.hasMatch(ref.words!) ? '' : _words(ref.words!)) : _words(ref.words ?? '');
      return '![$caption](${landed.ref})';
    }
    final said = ref.words == null || ref.words!.trim().isEmpty || (ref.wiki && _size.hasMatch(ref.words!)) ? _nameOf(ref.target) : _words(ref.words!);
    return '[${said.isEmpty ? _nameOf(ref.target) : said}](${landed.ref})';
  }

  return _outsideCode(body, (text) => text.replaceAllMapped(_either, (m) {
        final whole = m.group(0)!;
        final AttachmentRef ref;
        if (m.group(2) != null) {
          final target = m.group(2)!.trim();
          if (!namesAttachment(target)) return whole;
          ref = (target: target, embed: m.group(1) == '!', words: m.group(4), wiki: true);
        } else {
          final target = _decoded(m.group(7)!);
          if (_scheme.hasMatch(target) || !namesAttachment(target)) return whole;
          ref = (target: target, embed: m.group(5) == '!', words: m.group(6), wiki: false);
        }
        final landed = landedOf(ref);
        if (landed == null) {
          missing?.call(ref);
          return whole;
        }
        return write(ref, landed, whole);
      }));
}

/// Finds a reference's file in a vault as Obsidian does: by its path from the note's folder, then from the vault's
/// top, then (the vault's "shortest path" links) by its name alone anywhere, ignoring case each time.
class VaultResolver {
  VaultResolver(Iterable<String> paths) {
    for (final path in paths) {
      _byPath[path.toLowerCase()] = path;
      _byName.putIfAbsent(_nameOf(path).toLowerCase(), () => path);
    }
  }

  final Map<String, String> _byPath = {};
  final Map<String, String> _byName = {};

  /// The vault's path for [target] as written in a note in [folders], or null where the vault has no such file.
  String? resolve(String target, List<String> folders) {
    var clean = target.replaceAll('\\', '/');
    while (clean.startsWith('./')) {
      clean = clean.substring(2);
    }
    if (clean.startsWith('/')) clean = clean.substring(1);
    final relative = _normal([...folders, ...clean.split('/')]);
    final near = relative == null ? null : _byPath[relative.toLowerCase()];
    if (near != null) return near;
    if (_byPath[clean.toLowerCase()] case final found?) return found;
    return _byName[_nameOf(clean).toLowerCase()];
  }

  /// `a/b/../c` as `a/c`; null where it climbs out of the vault.
  static String? _normal(List<String> parts) {
    final out = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isEmpty) return null;
        out.removeLast();
      } else {
        out.add(part);
      }
    }
    return out.join('/');
  }
}
